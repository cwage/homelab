{ config, lib, pkgs, ... }:

{
  networking.hostName = "dns1";

  # Prevent cloud-init from overriding the hostname (it cached "dns1-nixos" from
  # the original VM creation and re-applies it on every boot)
  environment.etc."cloud/cloud.cfg.d/99-preserve-hostname.cfg".text = ''
    preserve_hostname: true
  '';

  # --- NSD authoritative DNS for lan.quietlife.net ---

  # Disable systemd-resolved (conflicts with NSD on port 53)
  services.resolved.enable = false;

  # Static resolv.conf pointing to fw1 (Unbound) for recursive lookups
  networking.nameservers = [ "10.10.15.1" ];

  services.nsd = {
    enable = true;
    interfaces = [ "10.10.15.15" "127.0.0.1" ];
    port = 53;

    remoteControl.enable = false;

    zones = {
      "lan.quietlife.net" = {
        data = ''
          $ORIGIN lan.quietlife.net.
          $TTL 300

          @       IN  SOA dns1.lan.quietlife.net. hostmaster.lan.quietlife.net. (
                      2026031901  ; serial (YYYYMMDDNN)
                      3600        ; refresh
                      600         ; retry
                      604800      ; expire
                      300         ; minimum
                  )

          ; Nameserver
          @               IN  NS      dns1.lan.quietlife.net.

          ; A records — infrastructure
          fw1             IN  A       10.10.15.1
          wap             IN  A       10.10.15.2
          portaplotz      IN  A       10.10.15.3
          portanas        IN  A       10.10.15.4
          portaptty       IN  A       10.10.15.5
          portapttyeth    IN  A       10.10.15.6
          dns1            IN  A       10.10.15.15
          bao             IN  A       10.10.15.11
          containers      IN  A       10.10.15.12
          nintendoswitch  IN  A       10.10.15.13
          pve1            IN  A       10.10.15.18
          lattepanda      IN  A       10.10.15.20
          remarkable      IN  A       10.10.15.115
          lattepandaeth   IN  A       10.10.15.130

          ; CNAME records — service aliases
          firewall        IN  CNAME   fw1.lan.quietlife.net.
          nas             IN  CNAME   portanas.lan.quietlife.net.
          proxmox         IN  CNAME   pve1.lan.quietlife.net.
          traefik         IN  CNAME   containers.lan.quietlife.net.
          jellyfin        IN  CNAME   containers.lan.quietlife.net.
          sabnzbd         IN  CNAME   containers.lan.quietlife.net.
          radarr          IN  CNAME   containers.lan.quietlife.net.
          sonarr          IN  CNAME   containers.lan.quietlife.net.
          paperless       IN  CNAME   containers.lan.quietlife.net.
          owncast         IN  CNAME   containers.lan.quietlife.net.
          staticomment    IN  CNAME   containers.lan.quietlife.net.
          mm              IN  CNAME   containers.lan.quietlife.net.
          nash-services   IN  CNAME   containers.lan.quietlife.net.
        '';
      };

      "15.10.10.in-addr.arpa" = {
        data = ''
          $ORIGIN 15.10.10.in-addr.arpa.
          $TTL 300

          @       IN  SOA dns1.lan.quietlife.net. hostmaster.lan.quietlife.net. (
                      2026031901  ; serial
                      3600        ; refresh
                      600         ; retry
                      604800      ; expire
                      300         ; minimum
                  )

          ; Nameserver
          @       IN  NS      dns1.lan.quietlife.net.

          ; PTR records
          1       IN  PTR     fw1.lan.quietlife.net.
          2       IN  PTR     wap.lan.quietlife.net.
          3       IN  PTR     portaplotz.lan.quietlife.net.
          4       IN  PTR     portanas.lan.quietlife.net.
          5       IN  PTR     portaptty.lan.quietlife.net.
          6       IN  PTR     portapttyeth.lan.quietlife.net.
          12      IN  PTR     containers.lan.quietlife.net.
          13      IN  PTR     nintendoswitch.lan.quietlife.net.
          15      IN  PTR     dns1.lan.quietlife.net.
          18      IN  PTR     pve1.lan.quietlife.net.
          20      IN  PTR     lattepanda.lan.quietlife.net.
          115     IN  PTR     remarkable.lan.quietlife.net.
          130     IN  PTR     lattepandaeth.lan.quietlife.net.
        '';
      };
    };
  };

  # --- OpenBao agent for secrets ---
  homelab.openbao-agent = {
    enable = true;
    tlsSkipVerify = false;
    roleId = "bffb2f64-c53f-8ee8-7b60-72a94a5a7315";
    secrets = {
      cwage-password-hash = {
        path = "kv/data/infra/users/cwage";
        field = "password_hash";
        destination = "/etc/secrets/cwage-password-hash";
      };
    };
  };
}
