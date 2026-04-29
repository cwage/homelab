{ config, lib, pkgs, ... }:

{
  networking.hostName = "containers2";

  # Prevent cloud-init from overriding the hostname after rebuild
  # (same workaround as dns1/bao2)
  environment.etc."cloud/cloud.cfg.d/99-preserve-hostname.cfg".text = ''
    preserve_hostname: true
  '';

  # Resolve via fw1 (Unbound recursive, which stubs LAN zone to dns1)
  networking.nameservers = [ "10.10.15.1" ];

  # --- NFS mounts ---
  # RW shares are written by services on this host (paperless ingests, the
  # arr stack writes to Media, config snapshots land in containers-configs).
  # RO shares are read-only sources for the B2 + local backup sweeps.
  fileSystems."/mnt/nas/containers-configs" = {
    device = "10.10.15.4:/volume1/containers-configs";
    fsType = "nfs";
    options = [ "rw" "_netdev" "hard" "nofail" "vers=3" "noatime" ];
  };

  fileSystems."/mnt/nas/Media" = {
    device = "10.10.15.4:/volume1/Media";
    fsType = "nfs";
    options = [ "rw" "_netdev" "hard" "nofail" "vers=3" "noatime" ];
  };

  fileSystems."/mnt/nas/paperless" = {
    device = "10.10.15.4:/volume1/paperless";
    fsType = "nfs";
    options = [ "rw" "_netdev" "hard" "nofail" "vers=3" "noatime" ];
  };

  # Read-only NAS shares — backup sources only, never written from here.
  fileSystems."/mnt/nas/Pictures" = {
    device = "10.10.15.4:/volume1/Pictures";
    fsType = "nfs";
    options = [ "ro" "_netdev" "hard" "nofail" "vers=3" "noatime" ];
  };

  fileSystems."/mnt/nas/Documents" = {
    device = "10.10.15.4:/volume1/Documents";
    fsType = "nfs";
    options = [ "ro" "_netdev" "hard" "nofail" "vers=3" "noatime" ];
  };

  fileSystems."/mnt/nas/Books" = {
    device = "10.10.15.4:/volume1/Books";
    fsType = "nfs";
    options = [ "ro" "_netdev" "hard" "nofail" "vers=3" "noatime" ];
  };

  fileSystems."/mnt/nas/bp" = {
    device = "10.10.15.4:/volume1/bp";
    fsType = "nfs";
    options = [ "ro" "_netdev" "hard" "nofail" "vers=3" "noatime" ];
  };

  fileSystems."/mnt/nas/caitstuff" = {
    device = "10.10.15.4:/volume1/caitstuff";
    fsType = "nfs";
    options = [ "ro" "_netdev" "hard" "nofail" "vers=3" "noatime" ];
  };

  fileSystems."/mnt/nas/syncthing-data" = {
    device = "10.10.15.4:/volume1/syncthing-data";
    fsType = "nfs";
    options = [ "ro" "_netdev" "hard" "nofail" "vers=3" "noatime" ];
  };

  fileSystems."/mnt/nas/backup" = {
    device = "10.10.15.4:/volume1/backup";
    fsType = "nfs";
    options = [ "ro" "_netdev" "hard" "nofail" "vers=3" "noatime" ];
  };

  fileSystems."/mnt/nas/Misc" = {
    device = "10.10.15.4:/volume1/Misc";
    fsType = "nfs";
    options = [ "ro" "_netdev" "hard" "nofail" "vers=3" "noatime" ];
  };

  fileSystems."/mnt/nas/tb" = {
    device = "10.10.15.4:/volume1/tb";
    fsType = "nfs";
    options = [ "ro" "_netdev" "hard" "nofail" "vers=3" "noatime" ];
  };

  fileSystems."/mnt/nas/homelab-backups" = {
    device = "10.10.15.4:/volume1/homelab-backups";
    fsType = "nfs";
    options = [ "ro" "_netdev" "hard" "nofail" "vers=3" "noatime" ];
  };

  fileSystems."/mnt/nas/tofu-state" = {
    device = "10.10.15.4:/volume1/tofu-state";
    fsType = "nfs";
    options = [ "ro" "_netdev" "hard" "nofail" "vers=3" "noatime" ];
  };

  # Seagate 12TB USB backup drive (passed through from Proxmox).
  # Mounted RW for the local backup target. nofail so the VM still boots if
  # the drive is detached (e.g., during passthrough swaps).
  fileSystems."/mnt/nasbak" = {
    device = "/dev/disk/by-uuid/479d8cc7-5779-4707-bb19-87b555d7580b";
    fsType = "ext4";
    options = [ "rw" "nofail" "noatime" ];
  };

  # --- NVIDIA GPU (GTX 1050 Ti, passed through from Proxmox) ---
  # Headless docker host: no X, but the videoDrivers entry is the canonical
  # NixOS way to load the proprietary kernel module.
  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) [
      "nvidia-x11"
      "nvidia-settings"
      "nvidia-persistenced"
    ];
  hardware.graphics.enable = true;
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.nvidia = {
    modesetting.enable = true;
    open = false;
    nvidiaSettings = false;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };

  # --- Docker host ---
  virtualisation.docker = {
    enable = true;
    daemon.settings = {
      log-driver = "json-file";
      log-opts = {
        max-size = "10m";
        max-file = "3";
      };
      # Register nvidia as a docker runtime so compose's
      # `deploy.resources.reservations.devices` with driver: nvidia (and
      # `--gpus all`) resolve to GPU passthrough.
      runtimes.nvidia.path = "${pkgs.nvidia-container-toolkit}/bin/nvidia-container-runtime";
    };
  };

  # CDI-based GPU access for containers (also used by the runtime above).
  hardware.nvidia-container-toolkit.enable = true;

  users.users.deploy.extraGroups = [ "docker" ];
  users.users.cwage.extraGroups = [ "docker" ];

  # /opt/stacks holds the docker-compose.yml + supporting files.
  # /opt/backup holds the rclone backup container (parity with live VM).
  # deploy user's primary group is "users" (NixOS default for isNormalUser).
  # Static stack config (compose, traefik dyn config) is symlinked from the
  # nix store. Secrets (.env, basicauth, ssh deploy key) and TLS certs remain
  # mutable in /opt/stacks until they migrate to openbao-agent / lego.
  systemd.tmpfiles.rules = [
    "d /opt/stacks       0755 deploy users -"
    "d /opt/stacks/certs 0700 deploy users -"
    "z /opt/stacks/certs 0700 deploy users -"
    "d /opt/backup       0750 deploy users -"
    "d /opt/backup/logs  0750 deploy users -"
    "L+ /opt/stacks/docker-compose.yml - - - - ${./stacks/docker-compose.yml}"
    "L+ /opt/stacks/traefik-tls.yml    - - - - ${./stacks/traefik-tls.yml}"
  ];

  environment.systemPackages = with pkgs; [
    docker-compose
    rsync
  ];

  # --- OpenBao agent for secrets ---
  # Currently delivers the cwage password hash and the B2 backup credentials.
  # Stack secrets (.env, traefik basicauth, staticomment ssh deploy key) and
  # lego-managed TLS certs are still mutable in /opt/stacks/ and are slated
  # to move into the agent in a follow-up.
  # roleId is per-host and CIDR-bound to 10.10.15.11.
  homelab.openbao-agent = {
    enable = true;
    tlsSkipVerify = false;
    roleId = "63c7ca9b-f390-ba83-5679-849473fe44f9";
    secrets = {
      cwage-password-hash = {
        path = "kv/data/infra/users/cwage";
        field = "password_hash";
        destination = "/etc/secrets/cwage-password-hash";
      };

      backup-b2-account = {
        path = "kv/data/backup/backblaze";
        field = "account_id";
        destination = "/etc/secrets/backup/b2-account";
      };
      backup-b2-key = {
        path = "kv/data/backup/backblaze";
        field = "application_key";
        destination = "/etc/secrets/backup/b2-key";
      };
      backup-b2crypt-pw = {
        path = "kv/data/backup/rclone-crypt";
        field = "password";
        destination = "/etc/secrets/backup/b2crypt-pw";
      };
      # password2 (salt) intentionally omitted — this rclone crypt remote uses
      # the default salt, not a custom one. Templating a non-existent field
      # would write the literal string "<no value>" to disk and break rclone.
    };
  };

  # --- ntfy.sh notifications ---
  # OnFailure/OnSuccess hooks on the backup units pull last 20 journal lines
  # and post them to this topic.
  homelab.ntfy = {
    enable = true;
    topic = "https://ntfy.sh/cwage-homelab-backup";
  };

  # --- Backups ---
  # Three jobs:
  #   - configs (03:00): briefly stop/start each compose service while
  #     rsyncing its named volume to /mnt/nas/containers-configs/
  #   - b2 (03:40):       encrypted Backblaze sync (configs land here too,
  #                       picked up via the containers-configs path)
  #   - local (02:00):    full unencrypted copy to the USB drive at /mnt/nasbak
  # Schedules are deliberately staggered: local first, then configs, then b2
  # consumes the fresh containers-configs snapshot.
  homelab.backups = {
    local = {
      enable = true;
      paths = [
        "Pictures"
        "Documents"
        "paperless"
        "Books"
        "bp"
        "caitstuff"
        "syncthing-data"
        "backup"
        "Misc"
        "Media"
        "tb"
        "homelab-backups"
        "containers-configs"
        "tofu-state"
      ];
    };

    configs = {
      enable = true;
      services = [
        { name = "jellyfin";        mount = "/config"; }
        { name = "sabnzbd";         mount = "/config"; }
        { name = "radarr";          mount = "/config"; }
        { name = "sonarr";          mount = "/config"; }
        { name = "paperless-redis"; mount = "/data"; }
      ];
    };

    b2 = {
      enable = true;
      paths = [
        "Pictures"
        "Documents"
        "paperless"
        "Books"
        "bp"
        "caitstuff"
        "syncthing-data"
        "backup"
        "Misc"
        "Media"
        "homelab-backups"
        "containers-configs"
        "tofu-state"
      ];
    };
  };
}
