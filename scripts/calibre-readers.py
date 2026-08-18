#!/usr/bin/env python3
"""Manage the calibre.quietlife.net reader allowlist in OpenBao.

    scripts/calibre-readers.py list
    scripts/calibre-readers.py add alice@example.com
    scripts/calibre-readers.py remove alice@example.com

This ONLY edits the list in OpenBao (the single source of truth). It does
not deploy: it prints the tofu/seed commands to run next, so the plan can
be reviewed before anything changes at Cloudflare or in calibre-web.
Uses BAO_ADDR/BAO_TOKEN from the environment or the repo .env.
Full architecture: docs/calibre.md.
"""

import argparse
import re
import sys

import baokv  # sibling module in scripts/

BAO_PATH = "kv/infra/cloudflare/calibre-access"
FIELD = "allowed_emails"
EMAIL_RE = re.compile(r"^[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}$")


def fetch():
    raw = baokv.kv_get(BAO_PATH).get(FIELD, "")
    return [a.strip().lower() for a in raw.split(",") if a.strip()]


def store(emails):
    # KV v2 put replaces the whole secret, so always write the full list.
    baokv.kv_put(BAO_PATH, {FIELD: ",".join(emails)})


def next_steps():
    print()
    print("Allowlist updated in OpenBao. To deploy:")
    print("  make tofu-plan    # expect one in-place change to the Access policy")
    print("  make tofu-apply   # updates the Cloudflare Access allowlist")
    print("  scripts/calibre-web-seed.py --apply   # creates/updates matching calibre-web accounts")


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("list", help="print the current allowlist")
    for name in ("add", "remove"):
        sub.add_parser(name, help=f"{name} an address").add_argument("email")
    args = ap.parse_args()

    if args.cmd == "list":
        print("\n".join(fetch()))
        return 0

    email = args.email.strip().lower()
    if not EMAIL_RE.match(email):
        sys.exit(f"not a valid email address: {email}")
    current = fetch()

    if args.cmd == "add":
        if email in current:
            print(f"{email} is already on the allowlist")
            return 0
        store(current + [email])
        print(f"added {email}")
    else:
        if email not in current:
            sys.exit(f"{email} is not on the allowlist")
        updated = [a for a in current if a != email]
        if not updated:
            sys.exit("refusing to empty the allowlist (that would lock everyone out)")
        store(updated)
        print(f"removed {email}")
        print("NOTE: their existing Access session stays valid up to 168h --")
        print("revoke it in the Zero Trust dashboard to cut access immediately.")

    next_steps()
    return 0


if __name__ == "__main__":
    sys.exit(main())
