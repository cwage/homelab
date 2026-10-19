# Seestar (seestar_alp)

[seestar_alp](https://github.com/smart-underworld/seestar_alp) is a web
controller and scheduler for ZWO Seestar smart telescopes. It runs as the
`seestar` compose service on the **containers** host and talks to the scope
over the LAN.

- UI: `http://containers.lan.quietlife.net:5432` (plain HTTP, no auth of its
  own — LAN only, never route it through the Cloudflare tunnel)
- Alpaca API on 5555, imaging/event streams on 7556, Alpaca discovery on
  UDP 32227 (for clients such as NINA)
- Config: `/opt/stacks/seestar/config.toml` on the host, owned by the app
  after first boot (edit settings in the UI, not the seed in this repo)
- Source of truth: `hosts/containers/stacks/docker-compose.yml` (service),
  `hosts/containers/stacks/seestar/config.toml` (seed),
  `hosts/containers/configuration.nix` (tmpfiles + the PEM secret)

## Design decisions

- **Built from source, pinned to a release tag.** Upstream ships no container
  image, so compose builds `docker/Dockerfile` straight from the GitHub repo
  at the tag in the `build.context` URL. Renovate cannot track this; bump the
  tag by hand (see Upgrading). The image is a few GB (Ubuntu + OpenCV,
  astropy, pandas, a C toolchain).
- **Host networking.** The live view is RTSP over UDP from the scope, whose
  return packets do not survive docker NAT, and Alpaca discovery is a UDP
  broadcast listener. Nothing else on the host uses these ports.
- **No Traefik route.** The UI hands the browser absolute
  `http://<host>:7556/...` URLs for the live image and server-sent events,
  built from the Host header plus the raw connection scheme. Behind the
  HTTPS wildcard that becomes mixed content and the browser blocks it.
- **Config dir mount, not a file mount.** The Settings page saves via a temp
  file and `rename`, which fails on a single-file bind mount. The whole
  `/opt/stacks/seestar` dir is mounted at `/etc/seestar` and the app is
  pointed at it with `SEESTAR_ALP_CONFIG_PATH`. The in-container user is
  built as uid 1001 / gid 100 so it matches `deploy:users` on the host.
- **mDNS does not work from the container** (no Avahi on the NixOS host, no
  mDNS resolver in the image), so the scope is addressed by LAN name, not
  `seestar.local`.
- **Nothing is written to the NAS.** The app's "save frames" option is a
  stub in upstream; stacked images stay on the scope's own storage. Pulling
  them onto the NAS is separate work (and should land on a share Immich does
  not index).

## Firmware 7.18+ authentication

Firmware 7.18 and later silently ignore every command until the client signs
the scope's challenge with an RSA private key that upstream cannot ship. The
key is stored in OpenBao and rendered by openbao-agent to
`/opt/stacks/seestar/seestar_client_key.pem` (0400 `deploy:users`), which the
seed config already points at as `/etc/seestar/seestar_client_key.pem`.

Store it **before** deploying the containers host — openbao-agent stalls on a
missing secret and stops rendering the other templates:

```
bao kv put kv/stacks/containers/seestar-interop-pem content=@/path/to/seestar_client_key.pem
```

If the agent logs permission denied for the new path, the host's AppRole
policy needs read on `kv/data/stacks/containers/*` (see `docs/openbao.md`).
Symptom of a missing or wrong key: the scope's event stream flows but no
command ever gets a reply, and the UI shows the firmware-auth warning banner.

## First-time setup

1. Put the scope in **station mode** on the house WiFi (ZWO app → network
   settings). WiFi clients land on the same `10.10.15.0/24` as the VM.
2. Note its MAC, add a DHCP reservation in
   `ansible/roles/openbsd_firewall/templates/dhcpd.conf.j2` and an A record
   (plus PTR) named `seestar` in `hosts/dns1/configuration.nix`; pick an
   unused IP (`ping -c1`). Deploy fw1 and dns1. Until then the IP can be set
   directly in the UI's Settings page.
3. Store the PEM in OpenBao (above).
4. `make nix-deploy-host HOST=containers TARGET=10.10.15.11` — creates
   `/opt/stacks/seestar`, seeds the config, renders the PEM.
5. A nix deploy does not start new compose services (#337). On `containers`:
   ```
   cd /opt/stacks && sudo docker compose up -d --build seestar
   ```
   The first build takes several minutes.
6. Open the UI, Settings: set latitude/longitude (deliberately 0/0 in the
   public seed; 0 means "guess from public IP"), confirm the scope address.

## Upgrading

Change the tag in the `build.context` URL in the compose file (and the
`image:` tag to match), deploy, then on the host:

```
cd /opt/stacks && sudo docker compose build seestar && sudo docker compose up -d seestar
```

Check upstream release notes first; the auth handshake and config schema have
changed between releases.

## Known caveats

- The UI's light/dark **toggle button** hardcodes the in-image config path
  and errors under this layout. The Settings page works; the seed sets dark.
- The Settings page can rewrite anything, including the PEM path, and there
  is no login. Fine on the LAN; this is why it stays off the tunnel.
- Root disk headroom: the image build needs a few GB of free space on
  `containers` (`df -h /`).
