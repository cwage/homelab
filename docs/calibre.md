# Calibre-Web (calibre.quietlife.net)

A web reader over the existing Calibre library at `/mnt/nas/Books` — the same
library desktop Calibre manages (`metadata.db` lives at its root).
`books.quietlife.net`, the old nginx autoindex on felix, is unrelated and
stays as it is.

## Architecture

```
reader's browser
      │
      ▼
Cloudflare Access  ── one-time PIN emailed to the visitor; only allowlisted
      │               addresses can complete the login (tofu/cloudflare.tf)
      ▼
Cloudflare Tunnel  ── cloudflared container on the containers host; ingress
      │               route configured in the Zero Trust dashboard
      ▼
calibre-web        ── anonymous browsing ON: everyone Access admits lands in
                      the library as Guest, no second login
```

The pieces and where they're defined:

| Piece | Where | Notes |
|---|---|---|
| DNS + tunnel ingress | Zero Trust dashboard | route `calibre.quietlife.net` → `http://calibre-web:8083` |
| Access application + policy | `tofu/cloudflare.tf` | one-time PIN, 168h session |
| Reader allowlist | OpenBao `kv/infra/cloudflare/calibre-access` | read by Tofu (Access policy) and the seed script (accounts); edit via `scripts/calibre-readers.py` |
| Container | `hosts/containers/stacks/docker-compose.yml` | `linuxserver/calibre-web`, `tunnel` profile |
| App configuration | `scripts/calibre-web-seed.py` | stamps `/config/app.db`; the UI is not the source of truth |
| Library | NAS `/mnt/nas/Books`, mounted read-only | desktop Calibre is the only writer |

**Cloudflare Access is the entire security boundary.** Behind it, Calibre-Web
serves the whole library to any request that reaches it (`config_anonbrowse`),
and trusts the `Cf-Access-Authenticated-User-Email` header to log named users
(the admin) into their accounts.

> **This architecture is safe only while cloudflared is the ONLY path to the
> container.** Any other route — Traefik labels, a `calibre.lan` CNAME, a
> published host port — exposes the full library unauthenticated and lets
> anyone on the LAN spoof the identity header to arrive as admin. Likewise,
> deleting the Access application (or flipping its policy to bypass/everyone)
> makes the library world-readable. If Calibre-Web ever needs a LAN route,
> first turn `config_anonbrowse` and `config_allow_reverse_proxy_header_login`
> back off in `scripts/calibre-web-seed.py` and give readers real accounts.

## Managing readers

The allowlist lives in OpenBao, **not in the repo** — this repo is public and
readers' email addresses don't belong in it. It is one KV v2 secret:

- path: `kv/infra/cloudflare/calibre-access`
- key: `allowed_emails`
- value: a single comma-separated string, no spaces

That one list drives **both** halves of a reader's access:

- **Tofu** reads it via a `vault_kv_secret_v2` data source and splits it into
  the Access policy's `include.email` list — who can get past Cloudflare.
- **`scripts/calibre-web-seed.py`** reads the same key and creates a matching
  calibre-web account per address. Access injects
  `Cf-Access-Authenticated-User-Email` on every request, and calibre-web logs
  in whichever user has that exact (lowercase) name — so each reader lands in
  their *own* account, with their own shelves and reading progress, without
  ever seeing a login form. Account passwords are random throwaways generated
  at creation and never stored or shown; header SSO means nobody types one.
  An allowlisted address with no account yet just falls back to the shared
  `Guest` user until the next seed run — graceful, not an error.

The addresses land in tofu *state*, which is local and gitignored — fine, as
long as state is never committed or published.

The scripts take `BAO_ADDR`/`BAO_TOKEN` from the environment or the repo-root
`.env` — the same file the dockerized ansible/tofu stacks use (see
`docs/openbao-secrets.md`). The `bao` CLI is *not* needed (workstations don't
have it; it only exists on the OpenBao server).

**Writing the allowlist needs the `calibre-readers` policy** on the
workstation token — `ansible-deploy` alone is read-only, so `add`/`remove`
fail with HTTP 403 permission denied. Workstation tokens are minted with both
policies (see the Workstation Bootstrap section of `docs/openbao-secrets.md`);
the policy itself is defined in `docs/openbao.md`.

**The easy way** — `scripts/calibre-readers.py` wraps the list edit (the
OpenBao key is replace-only, so hand-editing risks dropping someone). It only
touches OpenBao, then prints the deploy commands for review:

```bash
scripts/calibre-readers.py list
scripts/calibre-readers.py add alice@example.com
scripts/calibre-readers.py remove alice@example.com
# then, as it prints:
make tofu-plan    # expect exactly one in-place change to the Access policy
make tofu-apply   # updates the Cloudflare Access allowlist
scripts/calibre-web-seed.py --apply   # creates/updates matching accounts (~20s blip)
```

**The manual way** — same thing without the wrapper, using the `bao` CLI on
the OpenBao server itself (`ssh bao.lan.quietlife.net`). There is no append:
always write the complete new list:

```bash
bao kv get -field=allowed_emails kv/infra/cloudflare/calibre-access
bao kv put kv/infra/cloudflare/calibre-access allowed_emails='alice@example.com,bob@example.com'
# back on the workstation:
make tofu-apply
scripts/calibre-web-seed.py --apply
```

Skipping the seed step is fine — the new reader can get in immediately after
`tofu-apply`, just as Guest rather than as themselves. Nothing else is
provisioned anywhere: they visit the URL, type their address, get a PIN.

**"I never got the code":** the login page shows "a code has been emailed
to you" for EVERY address, allowlisted or not — Cloudflare deliberately never
reveals whether an address is authorized (verified empirically: a bogus
address gets the same screen and simply no email). So a reader stuck at that
screen looks like an email-delivery problem but usually isn't. Diagnose in
this order: are they on the allowlist, did they type the exact address that's
on it, then spam folders. The Access logs (Zero Trust dashboard → Logs →
Access) show what address they actually submitted.

**Removal is not instant.** The policy is evaluated at login, and sessions
last 168h — a removed reader's existing session keeps working until it
expires. To cut access immediately, also revoke their session in the Zero
Trust dashboard (Access → Applications → Calibre-Web → Revoke existing
sessions, or per-user under My Team → Users).

**Who's been reading:** every login is attributable at the Cloudflare layer
(Zero Trust dashboard → Logs → Access). Inside the app, seeded readers act
as their own named account; calibre-web's own access log
(`/config/access.log`) records what was fetched but not by whom.

## App configuration: the seed script

Calibre-Web has no config file or env vars — its source of truth is a
`settings` row and a `user` table in `/config/app.db` (sqlite).
`scripts/calibre-web-seed.py` stamps the desired state into that file
(library path, anonymous browsing on, header auth trusted from the tunnel
network only, and the user list with roles) and is idempotent:

```bash
scripts/calibre-web-seed.py --check    # report drift, change nothing
scripts/calibre-web-seed.py --apply    # stop container, enforce, start
```

Reader accounts are derived from the OpenBao allowlist (see above); `READERS`
in the script only defines the exceptions — the admin's role and Guest's.
Existing users keep whatever password they have since set — the script never
resets passwords, only creates missing accounts and corrects roles.
Rebuilding from an empty volume is one `--apply`. `/config` is in the nightly
configs backup, so per-user state survives independently.

**The library mount is read-only.** Desktop Calibre is the only writer; a
second writer against `metadata.db` is how a Calibre library gets corrupted.
The cost is that metadata editing, upload, and on-the-fly conversion are
unavailable in the web UI. Per-user state lives in `app.db` and is unaffected.

## Formats and the epubify script

The in-browser reader handles epub, pdf, txt, cbz, djvu, and fb2 — but not
mobi, azw3, lit, lrf, or doc. Books in those formats appear in the library
but are download-only. `scripts/calibre-epubify.py` fixes that: it walks the
library and attaches an EPUB to every book lacking a readable format, via
`calibredb add_format` (originals are kept, nothing is replaced). Dry-run by
default; run it from a workstation that mounts the library read-write, with
the Calibre desktop GUI closed.

Library state when this was set up (2026-08-16), from `calibredb`, not a
filesystem walk — the two disagree:

| | books |
|---|---|
| Total | 1026 |
| Already browser-readable | 504 |
| Convertible by the script | 460 |
| Not fixable | 62 |

Sources needing conversion: mobi 409, lrf 15, rtf 10, htmlz 9, azw3 8, lit 6,
azw 2, azw4 1. Sample conversions across every one of those formats
succeeded, so DRM is not a meaningful obstacle here — only 2 `.azw` are
actually DRM-protected.

The 62 unfixable are **44 metadata-only records** (a `cover.jpg` and
`metadata.opf` with no ebook file at all — several Harry Potter entries among
them; these will be empty in Calibre-Web no matter what), **9 legacy binary
`.doc`** (Word 97-2003, not a Calibre input format — `--with-doc` routes them
through LibreOffice), and **9 `.zip`** (unexamined; any that are really comic
archives would just need renaming to `.cbz`).

The 163 `.kfx` files need no attention — every one already has an EPUB
alongside it.

## History and limitations

Getting Access working was a saga: it initially could not issue PINs because
the account had no identity provider configured, and the dashboard pages for
adding one were missing until Zero Trust onboarding completed. The app and
policy are managed from Tofu; the One-Time PIN login method was created in
the dashboard (the Tofu token lacks the `Access: Organizations, Identity
Providers, and Groups · Edit` permission). An intermediate iteration used
`everyone = true` (any mailbox could request a PIN), which made the hostname
the only real secret; the allowlist replaced it.

**Known limitation:** Access is a browser flow, so OPDS feeds and KOReader
sync do not work through it — non-browser clients can't complete the OTP
handshake. Revisit when LDAP lands.
