#!/usr/bin/env python3
"""
Enforce Calibre-Web's configuration declaratively.

Calibre-Web has no config file and no env vars for any of this -- the source
of truth is a `settings` row and a `user` table inside /config/app.db, which
the product expects you to edit by clicking through the admin UI. This script
stamps the same state into that sqlite file instead, so rebuilding the
container from an empty volume is one command rather than a six-step runbook.

Idempotent: run it as often as you like. It reports what it changed.

    scripts/calibre-web-seed.py --check     # show current vs desired, change nothing
    scripts/calibre-web-seed.py --apply     # make it so

Calibre-Web caches its config in memory and rewrites app.db on save, so
--apply stops the container, edits, and starts it again -- roughly a 20-second
blip. The edit runs inside a throwaway container built from the calibre-web
image itself (which ships python3), mounting the same named volume; the same
trick the Home Assistant first-boot step uses in docs/services.md.

Readers are NOT added here -- Cloudflare Access is the authentication layer,
and its allowlist lives in OpenBao (see docs/calibre.md). This script reads
that same allowlist and creates a matching calibre-web account per address,
so Access's identity header logs each reader into their own account (shelves,
reading progress) with no password ever typed or stored. READERS below only
defines the exceptions: the admin role, and Guest. Needs BAO_ADDR/BAO_TOKEN.
"""

import argparse
import base64
import json
import os
import secrets
import subprocess
import sys

import baokv  # sibling module in scripts/

HOST = "deploy@10.10.15.11"
SSH_KEY = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                       "..", "ansible", "keys", "deploy")
CONTAINER = "calibre-web"
VOLUME = "stacks_calibre_web_config"
IMAGE = "linuxserver/calibre-web:0.6.27-ls397"
COMPOSE = "/opt/stacks/docker-compose.yml"

# --- desired state ----------------------------------------------------------

DESIRED_SETTINGS = {
    # The Calibre library, mounted read-only. Calibre-Web will warn "DB is not
    # Writeable" -- that is intentional: desktop Calibre is the only writer.
    "config_calibre_dir": "/books",

    # Trust Cloudflare Access's identity header, so the named admin account
    # is logged in automatically rather than prompted a second time.
    "config_allow_reverse_proxy_header_login": 1,
    "config_reverse_proxy_login_header_name": "Cf-Access-Authenticated-User-Email",

    # Accept that header only from the docker proxy network, where cloudflared
    # lives. BOTH forms are required: calibre-web listens dual-stack, so the
    # peer address arrives as an IPv4-mapped IPv6 address (::ffff:172.18.0.5).
    # Python parses that as an IPv6Address, which is never `in` an IPv4Network
    # -- with only the v4 entry the header is silently discarded and the admin
    # falls back to the password form.
    "config_reverse_proxy_trusted_ips": "172.18.0.0/16,::ffff:172.18.0.0/112",

    # Anonymous browsing ON -- this is what turns Calibre-Web's own login off.
    # Cloudflare Access is the only authentication: nobody reaches this app
    # without passing it, so everyone it admits lands straight in the library
    # as Guest with no second prompt.
    #
    # DEPENDS ON ACCESS BEING IN FRONT (tofu/cloudflare.tf). If that app is
    # removed or set to bypass, this makes the whole library world-readable.
    "config_anonbrowse": 1,

    # Per-request access log at /config/access.log: path, status, timestamp.
    # Off by default in calibre-web. Note it records WHAT, not WHO -- with
    # anonymous browsing everyone is the shared Guest, so identity only
    # exists in Cloudflare's Access logs (or for users with a named account
    # matching the address Access sends).
    "config_access_log": 1,
}

# Role bits (cps/constants.py): ADMIN 1, DOWNLOAD 2, UPLOAD 4, EDIT 8,
# PASSWD 16, ANONYMOUS 32, EDIT_SHELFS 64, DELETE_BOOKS 128, VIEWER 256.
#
# 274 = DOWNLOAD + PASSWD + VIEWER: read, download, and change their own
# password. That is the right shape for an ordinary reader -- no admin, no
# upload, no deleting books out of the library.
#
# Explicit entries here override the OpenBao-derived ones by name (that is
# how cwage@quietlife.net gets admin instead of reader). Existing users are
# left alone except for their role -- passwords are never reset from here.
READERS = [
    {"name": "cwage@quietlife.net", "role": 475},
    # Guest is what every anonymous visitor becomes, so its role IS the
    # reader experience: 290 = ANONYMOUS + DOWNLOAD + VIEWER. Guest ships
    # as 32 (ANONYMOUS alone), which can get in and see nothing.
    {"name": "Guest", "role": 290},
]

BAO_ALLOWLIST_PATH = "kv/infra/cloudflare/calibre-access"


def fetch_allowlist():
    """The Cloudflare Access allowlist in OpenBao, as a list of addresses.

    Same secret Tofu reads for the Access policy -- single source of truth.
    Uses BAO_ADDR/BAO_TOKEN from the environment or the repo .env (baokv).
    """
    raw = baokv.kv_get(BAO_ALLOWLIST_PATH).get("allowed_emails", "")
    return [a.strip().lower() for a in raw.split(",") if a.strip()]


def build_readers():
    """READERS plus one ordinary-reader account per allowlisted address.

    Cloudflare Access sends Cf-Access-Authenticated-User-Email; calibre-web
    logs in whichever user has that exact name (lowercase -- Access
    normalizes). So every allowlisted address gets a matching account and
    lands in the app as themselves, with their own shelves and progress.
    Anyone added to the allowlist before the next seed run just falls back
    to Guest -- graceful, not an error.

    Creation needs a password, but header SSO means nobody ever types it, so
    each new account gets a random throwaway that is never stored or shown.
    """
    readers = list(READERS)
    explicit = {r["name"] for r in readers}
    for addr in fetch_allowlist():
        if addr not in explicit:
            readers.append({"name": addr, "role": 274, "email": addr})
    for r in readers:
        if "password" not in r and r["name"] != "Guest":
            r["password"] = secrets.token_urlsafe(24)
    return readers

# --- the part that runs inside the container --------------------------------

INNER = r'''
import json, os, sqlite3, sys

desired = json.loads(os.environ["SEED_SETTINGS"])
readers = json.loads(os.environ["SEED_READERS"])
apply = os.environ.get("SEED_APPLY") == "1"

db = sqlite3.connect("/config/app.db")
cols = [r[1] for r in db.execute("pragma table_info(settings)")]
row = list(db.execute("select * from settings"))[0]
current = dict(zip(cols, row))

changes = []
for key, want in desired.items():
    if key not in cols:
        changes.append(("MISSING", key, None, want))
        continue
    have = current.get(key)
    if str(have) != str(want):
        changes.append(("settings", key, have, want))

existing = {name: (uid, role) for uid, name, role in
            db.execute("select id, name, role from user")}
for r in readers:
    if r["name"] not in existing:
        changes.append(("user", r["name"], None, f"create (role {r['role']})"))
    elif existing[r["name"]][1] != r["role"]:
        changes.append(("user", r["name"], existing[r["name"]][1], r["role"]))

for kind, key, have, want in changes:
    print(f"  {kind:9} {key:45} {have!r} -> {want!r}")
if not changes:
    print("  (already in desired state)")

if not apply:
    print(f"\nCHECK ONLY -- {len(changes)} change(s) would be made")
    sys.exit(0)

if any(k == "MISSING" for k, *_ in changes):
    print("\nERROR: a desired setting has no column in this schema -- refusing "
          "to guess. Has the calibre-web version changed?")
    sys.exit(1)

for kind, key, _, want in changes:
    if kind == "settings":
        db.execute(f"update settings set {key} = ?", (desired[key],))

for r in readers:
    if r["name"] not in existing:
        # Hash with the same helper calibre-web uses, so the account is
        # indistinguishable from one made through the admin UI.
        from werkzeug.security import generate_password_hash
        pw = r.get("password")
        if not pw:
            print(f"  SKIP {r['name']}: no password given, cannot create a "
                  f"loginable account")
            continue
        db.execute(
            "insert into user (name, password, role, sidebar_view, locale, "
            "default_language, view_settings, kindle_mail, email) "
            "values (?, ?, ?, 1, 'en', 'all', '{}', '', ?)",
            (r["name"], generate_password_hash(pw), r["role"], r.get("email", "")),
        )
    elif existing[r["name"]][1] != r["role"]:
        db.execute("update user set role = ? where name = ?",
                   (r["role"], r["name"]))

db.commit()
print(f"\napplied {len(changes)} change(s)")
'''


def ssh(cmd, stdin=None):
    return subprocess.run(
        ["ssh", "-i", SSH_KEY, "-o", "ConnectTimeout=20", HOST, cmd],
        input=stdin, capture_output=True, text=True,
    )


def run_inner(apply, readers):
    """Pipe INNER into a throwaway container that mounts the config volume."""
    payload = base64.b64encode(INNER.encode()).decode()
    env = (
        f"-e SEED_SETTINGS={json.dumps(json.dumps(DESIRED_SETTINGS))} "
        f"-e SEED_READERS={json.dumps(json.dumps(readers))} "
        f"-e SEED_APPLY={'1' if apply else '0'}"
    )
    cmd = (
        f"echo {payload} | base64 -d > /tmp/cw-seed.py && "
        f"docker run --rm -v {VOLUME}:/config -v /tmp/cw-seed.py:/seed.py:ro "
        f"{env} --entrypoint python3 {IMAGE} /seed.py; "
        f"rc=$?; rm -f /tmp/cw-seed.py; exit $rc"
    )
    return ssh(cmd)


def compose(action):
    return ssh(f"cd /opt/stacks && docker compose {action} {CONTAINER}")


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    g = ap.add_mutually_exclusive_group()
    g.add_argument("--check", action="store_true",
                   help="report drift without changing anything (default)")
    g.add_argument("--apply", action="store_true",
                   help="stop the container, enforce state, start it again")
    args = ap.parse_args()

    if not os.path.exists(SSH_KEY):
        sys.exit(f"deploy key not found at {SSH_KEY}")

    readers = build_readers()

    if not args.apply:
        print(f"Checking {CONTAINER} on {HOST}...\n")
        res = run_inner(apply=False, readers=readers)
        print(res.stdout.rstrip() or res.stderr.rstrip())
        return res.returncode

    print(f"Stopping {CONTAINER}...")
    if (r := compose("stop")).returncode != 0:
        sys.exit(f"failed to stop:\n{r.stderr.strip()}")

    try:
        print("Enforcing configuration...\n")
        res = run_inner(apply=True, readers=readers)
        print(res.stdout.rstrip() or res.stderr.rstrip())
        if res.returncode != 0:
            print("\nseed failed -- starting the container again anyway",
                  file=sys.stderr)
    finally:
        print("\nStarting container...")
        if (r := compose("start")).returncode != 0:
            sys.exit(f"FAILED TO RESTART -- do this by hand:\n{r.stderr.strip()}")

    print("done")
    return res.returncode


if __name__ == "__main__":
    sys.exit(main())
