{ config, lib, pkgs, ... }:

let
  domain = "quietlife.net";
  xmppHost = "xmpp.${domain}";
  mucDomain = "conference.${domain}";
  uploadDomain = "upload.${domain}";
  turnDomain = "turn.${domain}";

  certDir = "/var/lib/acme/${domain}";
  certFile = "${certDir}/fullchain.pem";
  keyFile = "${certDir}/key.pem";

  # coturn's relay range. Must stay in sync with the Linode Cloud Firewall rule
  # in tofu/linode.tf — voice audio flows through these ports.
  relayMin = 49152;
  relayMax = 49200;
in
{
  networking.hostName = "xmpp1";
  networking.domain = domain;

  # --- Linode platform bits -------------------------------------------------

  # Linode's "GRUB 2" boot mode runs the HOST's grub, which loads
  # (hd0)/boot/grub/grub.cfg from our (partitionless — see disko.nix) disk. A
  # grub installed by us would never execute. So: device = "nodev" writes the
  # config without installing a bootloader, and forceInstall skips the sanity
  # checks that reject that combination.
  boot.loader.grub = {
    enable = true;
    device = lib.mkForce "nodev";
    forceInstall = true;
  };

  # Serial console so Lish works. Without this a boot failure means a blank
  # rescue console and no way to see what went wrong. Both console= entries:
  # kernel output goes to the LAST one listed (ttyS0 → Lish), while tty0 keeps
  # Glish (the graphical console) alive as a fallback.
  boot.kernelParams = [ "console=tty0" "console=ttyS0,19200n8" ];
  # terminal_input/output list BOTH serial and console. Serial-only here can
  # wedge GRUB with no visible output if serial init misbehaves — with both,
  # GRUB drives whichever works.
  boot.loader.grub.extraConfig = ''
    serial --speed=19200 --unit=0 --word=8 --parity=no --stop=1
    terminal_input serial console
    terminal_output serial console
  '';

  boot.initrd.availableKernelModules = [
    "virtio_pci"
    "virtio_scsi"
    "virtio_blk"
    "ahci"
    "sd_mod"
  ];

  networking.useDHCP = lib.mkDefault true;

  # No IPv6, deliberately. Linode routes only the EUI-64 SLAAC address, but the
  # box always ends up with a random-suffix stable-privacy address too (NixOS's
  # dhcpcd config hardcodes `slaac private`, and kernel autoconf adds its own),
  # and source selection prefers the unroutable one — so v6 sends packets whose
  # replies never come back. That half-dead state broke ACME issuance in a way
  # that looked like a Cloudflare outage. Everything this host does works over
  # v4 (DNS records are A-only, JMP federates v4, lego checks via 1.1.1.1), so
  # rather than fight dhcpcd/kernel address-generation duality, v6 is off. If
  # it's ever wanted, the fix that must work FIRST on a fresh boot: exactly one
  # global address, the EUI-64 one, preferred for source selection.
  networking.enableIPv6 = false;

  # base.nix turns the host firewall off because pf on fw1 handles the LAN.
  # This box has no fw1 in front of it, so it defends itself. The Linode Cloud
  # Firewall in tofu/linode.tf is the outer layer; this is the inner one.
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [
      22
      5344 # alt SSH, matching the linode_vps convention
      443 # HTTP upload (MMS attachments), BOSH, websockets
      5222 # XMPP client-to-server
      5269 # XMPP server-to-server — this is the one JMP uses
      3478 # STUN/TURN
      5349 # TURN over TLS
    ];
    allowedUDPPorts = [ 3478 5349 ];
    allowedUDPPortRanges = [
      { from = relayMin; to = relayMax; }
    ];
  };

  services.openssh.ports = [ 22 5344 ];

  # --- Secrets --------------------------------------------------------------
  #
  # sops-nix rather than the openbao-agent module used everywhere else. That
  # module authenticates with an AppRole CIDR-bound to a LAN address and talks
  # to bao.lan.quietlife.net:8200, neither of which this host can do. Secrets
  # here are age-encrypted in the repo and decrypted at activation using the
  # host's own SSH key. See docs/xmpp.md for the bootstrap.
  sops = {
    defaultSopsFile = ../../secrets/xmpp1.yaml;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

    secrets = {
      # Consumed by base.nix's users.users.cwage.hashedPasswordFile.
      cwage-password-hash.neededForUsers = true;

      # Shared between prosody (mints time-limited HMAC credentials from it)
      # and coturn (validates them). Both read this one file, so they cannot
      # drift out of sync.
      coturn-auth-secret = {
        group = "xmppsvc";
        mode = "0440";
      };

      # CF_DNS_API_TOKEN=... for lego's Cloudflare DNS-01 challenge. Scoped to
      # the quietlife.net zone only.
      acme-cloudflare-env = { };
    };
  };

  # base.nix hardcodes the openbao-agent destination; point it at sops instead.
  users.users.cwage.hashedPasswordFile =
    lib.mkForce config.sops.secrets.cwage-password-hash.path;

  # Shared group giving prosody and coturn read access to both the TLS
  # certificate and the TURN shared secret, without making either world
  # readable.
  users.groups.xmppsvc = { };
  users.users.prosody.extraGroups = [ "xmppsvc" ];
  users.users.turnserver.extraGroups = [ "xmppsvc" ];

  # --- TLS ------------------------------------------------------------------
  #
  # DNS-01 is the only workable challenge: the JID domain is the bare apex,
  # whose A record points at the website, not at this box. Renewal is handled
  # by the acme module's systemd timers — an expired cert here means federation
  # stops and text messages stop arriving.
  security.acme = {
    acceptTerms = true;
    defaults.email = "cwage@${domain}";

    # Check DNS-01 propagation through a recursive resolver over IPv4 instead
    # of querying Cloudflare's authoritative NS directly. The direct checks
    # prefer IPv6 and time out whenever v6 is unhealthy (see the ICMP note in
    # tofu/linode.tf for how that happens on a Linode) — which failed issuance
    # on first boot despite the challenge records being created correctly.
    defaults.dnsResolver = "1.1.1.1:53";

    certs.${domain} = {
      domain = domain;
      extraDomainNames = [ xmppHost mucDomain uploadDomain turnDomain ];
      dnsProvider = "cloudflare";
      environmentFile = config.sops.secrets.acme-cloudflare-env.path;
      group = "xmppsvc";

      # Both services read the certificate only at startup, so a renewal has to
      # bounce them or they keep serving the expired one until the next reboot.
      reloadServices = [ "prosody.service" "coturn.service" ];
    };
  };

  # --- Prosody --------------------------------------------------------------

  services.prosody = {
    enable = true;

    # nixos-24.11 ships Prosody 0.12, where cloud_notify (push notifications)
    # is still a community module. Without it Cheogram misses messages while
    # the phone is asleep. luadbi-sqlite3 backs the MAM archive — the default
    # flat-file store degrades badly once it holds years of SMS history.
    package = pkgs.prosody.override {
      withCommunityModules = [ "cloud_notify" ];
      withExtraLuaPackages = luaPkgs: [ luaPkgs.luadbi-sqlite3 ];
    };

    admins = [ "cwage@${domain}" ];
    allowRegistration = false;

    # Module options, not extraConfig — putting these in extraConfig duplicates
    # what the module emits and prosody warns at startup. s2sSecureAuth is the
    # one that isn't a module default: actually validate peer certificates
    # rather than accepting any TLS at all.
    c2sRequireEncryption = true;
    s2sRequireEncryption = true;
    s2sSecureAuth = true;

    ssl.cert = certFile;
    ssl.key = keyFile;

    virtualHosts.${domain} = {
      domain = domain;
      enabled = true;
      ssl.cert = certFile;
      ssl.key = keyFile;
    };

    # JMP delivers group texts as multi-user chats.
    muc = [{ domain = mucDomain; }];

    # MMS attachments and voice messages travel this path.
    uploadHttp.domain = uploadDomain;

    extraModules = [
      "smacks" # survive network flaps mid-conversation
      "carbons" # multi-device: phone and web client both see everything
      "mam" # the archive — the whole reason for self-hosting
      "csi_simple" # suppress chatter while the client is idle
      "cloud_notify" # push notifications
      "turn_external" # hand clients coturn credentials for Jingle RTP
      "blocklist"
      "vcard4"
      "vcard_legacy"
      "bosh" # legacy web transport
      "websocket" # what Converse.js will use
      "admin_adhoc"
      "limits"
    ];

    extraConfig = ''
      storage = "sql"
      sql = { driver = "SQLite3"; database = "prosody.sqlite"; }

      -- Keep everything. Owning the message history is the point; silently
      -- expiring it would defeat the exercise.
      archive_expires_after = "never"
      default_archive_policy = true
      max_archive_query_results = 250

      -- These two intentionally re-declare options the NixOS module also emits
      -- (its 5280/5281 defaults); prosody warns about the duplicates and takes
      -- ours, which is what we want. 443 so URLs carry no port number.
      https_ports = { 443 }
      -- No plaintext HTTP listener: everything here carries message content.
      http_ports = {}

      -- Prosody's default certificate-index directory is "certs" relative to
      -- /etc/prosody, which doesn't exist here — certs live under /var/lib/acme
      -- and the explicit ssl blocks below point straight at them. Redirect the
      -- indexer there so startup doesn't log a spurious certmanager error.
      certificates = "/var/lib/acme"

      -- TURN credentials for Jingle voice calls. The secret is read from disk
      -- at startup rather than interpolated, because this config file lives in
      -- the world-readable nix store. Read and close in one expression so the
      -- file handle isn't leaked (config is re-evaluated on every reload).
      turn_external_host = "${turnDomain}"
      turn_external_port = 3478
      turn_external_secret = (function()
        local f = assert(io.open("${config.sops.secrets.coturn-auth-secret.path}"))
        local secret = f:read("*l")
        f:close()
        return secret
      end)()

      -- One legitimate user lives here; anything near these rates is not us.
      limits = {
        c2s = { rate = "10kb/s"; };
        s2sin = { rate = "30kb/s"; };
      }
    '';
  };

  # Prosody drops privileges to the `prosody` user. Its own ports are all above
  # 1024, but we serve HTTP upload and websockets on 443 so URLs carry no port
  # number — and binding a privileged port needs this capability. Without it the
  # service fails to start with permission denied on the HTTPS listener.
  systemd.services.prosody.serviceConfig.AmbientCapabilities =
    [ "CAP_NET_BIND_SERVICE" ];

  # Prosody reads the certificate at startup; make sure it exists first.
  systemd.services.prosody.after = [ "acme-finished-${domain}.target" ];
  systemd.services.prosody.wants = [ "acme-finished-${domain}.target" ];

  # --- coturn ---------------------------------------------------------------

  services.coturn = {
    enable = true;
    realm = turnDomain;
    use-auth-secret = true;
    static-auth-secret-file = config.sops.secrets.coturn-auth-secret.path;
    no-cli = true;
    min-port = relayMin;
    max-port = relayMax;
    cert = certFile;
    pkey = keyFile;

    extraConfig = ''
      # Refuse to relay into private ranges. This box has no route to the LAN,
      # but deny it explicitly so a coturn compromise can never be used to probe
      # RFC1918 space from inside somebody else's network.
      denied-peer-ip=10.0.0.0-10.255.255.255
      denied-peer-ip=172.16.0.0-172.31.255.255
      denied-peer-ip=192.168.0.0-192.168.255.255
      denied-peer-ip=169.254.0.0-169.254.255.255
      denied-peer-ip=127.0.0.0-127.255.255.255
    '';
  };

  systemd.services.coturn.after = [ "acme-finished-${domain}.target" ];
  systemd.services.coturn.wants = [ "acme-finished-${domain}.target" ];
}
