# Keeping the NixOS hosts up to date

How updates reach `dns1`, `bao`, `containers`, and `xmpp1`, what to do when
the weekly PRs arrive, and how to back out. Built under
[#298](https://github.com/cwage/homelab/issues/298); the tooling lives in
`modules/nixos-staleness.nix`, `modules/renovate.nix`, `renovate.json`,
`nix/deploy.sh`, and `.github/workflows/checks.yml`.

## The model in one paragraph

nixpkgs cuts a release branch every May and November (`nixos-YY.05`,
`nixos-YY.11`), supported for about seven months, so roughly one month of
overlap with its successor. Security and bug fixes are backported to the
release branch continuously; the branch head is the security feed. A host
runs exactly the nixpkgs commit recorded in `flake.lock`, forever, until
someone moves the lock and redeploys. So "am I patched" reduces to "how far
behind the branch head is my lock, and is it deployed". Two operations cover
everything: moving the lock within a branch (the weekly refresh, the analogue
of `apt upgrade`) and changing the branch in `flake.nix` (twice a year, the
analogue of `dist-upgrade`, e.g. [#299](https://github.com/cwage/homelab/pull/299)).

## The weekly loop

Every Monday around 06:00 Central, Renovate runs on `containers` and opens
PRs against this repo. Typically:

- **`chore(deps): refresh flake.lock`** — every flake input moved to the head
  of its ref. Usually just nixpkgs.
- **`chore(deps): update container images`** — minor/patch bumps for the
  compose image pins under `hosts/containers/stacks/` and `lego/`, grouped
  into one PR. Majors (traefik 3, postgres 18, ...) come as separate PRs.
- Occasionally Actions pins or a build Dockerfile.

CI (`checks` workflow) builds all four host toplevels on every lock or
host/module PR, and runs trufflehog on everything. Green CI on a lock PR means
every host evaluates and builds against it; it does not mean the services
behave. That check happens at deploy time.

**Master is what gets deployed.** The order is: merge, `git checkout master && git pull`, deploy.

### Deploying a lock refresh

1. Merge the PR (CI green is the signal; the diff is just lock revs).
2. From an up-to-date master, one host at a time:

   ```bash
   make nix-deploy-host HOST=containers
   make nix-deploy-host HOST=bao
   make nix-deploy-host HOST=xmpp1 TARGET=xmpp.quietlife.net
   make nix-deploy-host HOST=dns1
   ```

   Each builds in the nix container, copies the closure to the host, then
   prints two things and **waits for `y`**:

   - **Package changes** (`nix store diff-closures`): what versions move. A
     `linux` line means a kernel bump: the switch succeeds but the new kernel
     only runs after a reboot, so plan one.
   - **Activation dry run** (`switch-to-configuration dry-activate`): units
     that would restart, reload, or stop. This lists only changes to existing
     units; new units don't appear, so read the closure diff for additions.
     A restart of `nsd` on dns1 or `prosody` on xmpp1 means pick your moment.

   `NOCONFIRM=1` skips the prompt. If the host already runs the built path
   the script says so and exits.

3. Check the host does what it should, then move to the next one.

Order is a judgement call. `containers` first is a reasonable default (most
moving parts, least critical), `dns1` last (everything depends on it, and it
changes least).

### Deploying a container image bump

The compose file on `containers` is a symlink into the nix store
(`/opt/stacks/docker-compose.yml`), so a merged image PR is not on the host
until the nix config is deployed:

```bash
make nix-deploy-host HOST=containers
ssh -i ansible/keys/deploy deploy@containers 'cd /opt/stacks && docker compose pull && docker compose up -d'
```

Compose recreates only the containers whose image changed. Majors deserve a
read of the release notes first; leaving that PR open costs nothing.

If the grouped PR also bumped `lego/docker-compose.yml`, nothing runs on a
host for that one: the lego stack runs from the workstation via `make lego-*`,
so the new image is picked up by the next `make lego-renew` from an
up-to-date checkout.

### Deploying from the branch instead

`nix/deploy.sh` builds whatever is checked out, so for a change you want to
see on a real host before merging (a channel migration, a module rewrite):

```bash
gh pr checkout <n>
make nix-deploy-host HOST=containers
```

Verify, merge, then `git checkout master && git pull` (a bare `git pull` on the
PR branch pulls the branch, not master). The host ends up on master's closure either way. Don't
leave a host on a branch that never merges; the next master deploy shows a
confusing diff. For a routine lock refresh, merge first: CI already built the
exact closure you're about to deploy.

## Rolling back

Every switch keeps the previous generation in the system profile and the
GRUB menu. If a host misbehaves after a deploy:

```bash
ssh -i ansible/keys/deploy deploy@<host> sudo -n nixos-rebuild switch --rollback
```

That flips back in seconds: same atomic switch, nothing to fetch. If the host
won't come up cleanly, pick the previous generation from the boot menu. To see
what's there:

```bash
ssh -i ansible/keys/deploy deploy@<host> sudo -n nix-env -p /nix/var/nix/profiles/system --list-generations
```

The durable fix is then a revert of the offending PR (or a real fix) and a
redeploy. Master being ahead of a host in the meantime is fine; the next
deploy simply shows the diff again.

Deploys are per host and sequential, so a bad deploy on one host is contained:
roll it back and don't proceed to the others.

## The dependency dashboard

Renovate keeps issue [#307](https://github.com/cwage/homelab/issues/307) as a
status page, rewritten every run. You never maintain it, but it's useful for:

- **Awaiting schedule**: what next Monday will open. Tick a box to open that
  PR on the next run instead of waiting.
- **Ignored**: a PR closed without merging lands here and Renovate won't
  reopen it. Tick its box to un-ignore.
- **Rebase**: a PR that fell behind master has a rebase checkbox in its body;
  ticking it makes Renovate redo it fresh next run.

Renovate rebases its own open PRs as master moves and closes ones that
become obsolete. Its branches never need hand-editing.

To run it outside the schedule (it only opens PRs inside the schedule window
unless a dashboard box is ticked):

```bash
ssh -i ansible/keys/deploy deploy@containers sudo -n systemctl start renovate.service
ssh -i ansible/keys/deploy deploy@containers journalctl -u renovate -n 50 --no-pager
```

## The staleness nag

`nixos-staleness-check.timer` runs weekly on every host. The nixpkgs commit
date and the release branch's EOL are baked into the generation at build
time; the check compares them to the clock and, if the deployed nixpkgs is
older than 30 days or the release is within 30 days of EOL, exits non-zero
and posts its summary to ntfy through the `notify-failure@` hook. Only deploying
a build from a newer lock resets the clock; redeploying the same lock does not,
since the date is the nixpkgs commit date, not the build date. This is the
piece that catches a merged refresh that never got deployed, which a Nix
host would otherwise never mention.

To see what it thinks right now:

```bash
ssh -i ansible/keys/deploy deploy@<host> sudo -n systemctl start nixos-staleness-check.service
ssh -i ansible/keys/deploy deploy@<host> journalctl -u nixos-staleness-check -n 5 --no-pager
```

## Twice a year: moving to the next release

When the nag starts reporting EOL, or when the next `nixos-YY.MM` branch has
been out a few weeks: change the `nixpkgs.url` ref in `flake.nix`, run
`nix flake update` in the nix container, and treat it as a PR like any other,
expecting module renames and option changes that CI will surface. The lock
refresh PRs from Renovate follow whatever ref `flake.nix` names.
[#299](https://github.com/cwage/homelab/pull/299) is the worked example
(24.11 → 26.05).

## What is deliberately not automated

- **Deploys.** Manual, per host, with a prompt. dns1 is a single point of
  failure and kernel bumps need a reboot; a human choosing the moment is the
  feature.
- **Auto-merge.** CI proves it builds, not that it works.
- **`system.autoUpgrade`, deploy-rs, colmena.** More machinery than four
  hosts justify.
- **CVE scanners.** For a stable-branch user, lock age is the metric.

## Renovate itself

Self-hosted via nixpkgs `services.renovate` on `containers`
(`modules/renovate.nix`). Authenticates with a fine-grained GitHub PAT scoped
to this repo, stored at `kv/infra/renovate` and delivered by openbao-agent to
`/etc/secrets/renovate/token` (policy in [openbao.md](openbao.md)). PRs it
opens appear as cwage and trigger CI like any other. Moving the repo to
Forgejo later is `homelab.renovate.platform = "gitea"` plus an `endpoint`.
`.github/dependabot.yml` keeps only the terraform ecosystem; everything else
is Renovate's.
