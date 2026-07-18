# Break-glass restore drill

Quarterly exercise proving that the break-glass credential set — the values
written in Bitwarden today, and on the offline USB once #213 is done — can
decrypt the off-site B2 backups **with zero homelab dependencies**: no
OpenBao, no NAS, no existing rclone config, no `.env`.

This is the only check in the backup pipeline that validates the *recorded*
credentials rather than the live ones. The automated monthly jobs
(`verify-b2-*`, issue #174) run with OpenBao-templated credentials on the
containers VM; they can stay green for years while the copy written in the
break-glass store is wrong, stale, or in the wrong form. With a wrong crypt
password or salt, every byte on B2 is unrecoverable noise — and nothing else
ever notices.

This doc is also the first section of the DR runbook (#266): in a real
disaster, this procedure is step one — proving the backups are usable before
rebuilding anything.

## What you need

- Any machine with Docker (does not need to be a homelab machine — that's
  the point; in a real DR it might be a laptop and a fresh OS).
- The break-glass credential set, read from Bitwarden / the #213 USB. Names
  match the openbao-agent template files the production backup jobs use:

  | Store entry | What it is |
  |---|---|
  | `b2-account` | B2 application key ID |
  | `b2-key` | B2 application key |
  | `b2crypt-pw` | rclone crypt password (obscured or plaintext — see below) |
  | `b2crypt-pw2` | crypt salt — only if one was configured (default: none) |

**The obscured-vs-plaintext trap:** rclone's env-var config expects the
*obscured* form of the crypt password (what OpenBao stores). If the
break-glass store holds the plaintext instead, it must be run through
`rclone obscure` first. The drill script asks which form you're pasting and
handles both — and the first drill's job is to discover which form the store
actually holds. **Write the answer next to the entry in the store.**

## Procedure

From the repo root (or a fresh GitHub-mirror clone — also realistic):

```
./backup/scripts/break-glass-drill.sh
```

The script re-executes itself inside a throwaway `rclone/rclone` container.
All credentials are typed at hidden prompts inside the container; nothing
touches disk, shell history, or `docker inspect`. The container is removed
on exit.

Four stages, each isolating one failure mode:

| Step | Proves | Failure means |
|---|---|---|
| 1. Raw bucket listing (`bgb2:`) | B2 key ID + key authenticate, bucket readable | `b2-account` / `b2-key` wrong, revoked, or mis-scoped |
| 2. Decrypted top-level listing (`bgcrypt:`) | Crypt password (and salt) are correct | `b2crypt-pw` / `b2crypt-pw2` wrong, or wrong form (see trap above) |
| 3. Recursive file listing in one share | Filename decryption works at depth | Same as 2 (partial corruption would be surprising — investigate) |
| 4. Download + sha256 of a sample file | Content decrypts end-to-end | Content-layer problem — investigate immediately, this should never fail if 2 passed |

Step 4 prints the restored file's sha256 and the ssh one-liner to hash the
live source for comparison. Pick an old, stable file — a mismatch on a
recently-modified file only means the nightly sync hasn't caught up.

## After the drill

1. Comment the result on issue #174 (pass/fail per step, date, where the
   credentials were read from).
2. If anything needed correcting — wrong value, wrong form, missing salt —
   fix the break-glass store *now* and note the correction. That discovery
   is the drill working as intended.
3. Once #213 exists: run the next drill from the USB copy, not Bitwarden.

## Cadence

Quarterly, ~15 minutes. Also rerun after **any** rotation of the B2 key or
crypt password, and as step one of the #266 DR drill.

## Appendix: manual procedure (no script)

If the script isn't available (or you're bootstrapping from nothing and
haven't cloned the repo yet), the whole drill is four rclone commands with
env-var config in any container or clean machine:

```sh
docker run --rm -it --entrypoint /bin/sh rclone/rclone:1.68

# inside the container — values from the break-glass store:
export RCLONE_CONFIG_BGB2_TYPE=b2
export RCLONE_CONFIG_BGB2_ACCOUNT=<b2-account>
export RCLONE_CONFIG_BGB2_KEY=<b2-key>
export RCLONE_CONFIG_BGCRYPT_TYPE=crypt
export RCLONE_CONFIG_BGCRYPT_REMOTE=bgb2:cwagenas-backup
export RCLONE_CONFIG_BGCRYPT_PASSWORD=<b2crypt-pw, OBSCURED form>
# only if a salt is configured:
# export RCLONE_CONFIG_BGCRYPT_PASSWORD2=<b2crypt-pw2, obscured>

rclone lsd bgb2:cwagenas-backup --max-depth 1   # step 1: auth
rclone lsd bgcrypt:                             # step 2: crypt layer
rclone lsf --files-only bgcrypt:Documents | head  # step 3: listing
rclone copyto "bgcrypt:<share>/<file>" /tmp/sample && sha256sum /tmp/sample  # step 4
```

If the store holds the plaintext crypt password: `rclone obscure '<plaintext>'`
and use its output for `RCLONE_CONFIG_BGCRYPT_PASSWORD`.
