{ config, lib, pkgs, ... }:

{
  networking.hostName = "containers";

  # Prevent cloud-init from overriding the hostname after rebuild
  # (same workaround as dns1/bao)
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

  # Work around a Docker startup race that breaks GPU containers after every
  # reboot / docker.service restart. dockerd restores `restart: unless-stopped`
  # containers during daemon startup *before* its CDI registry is populated, so
  # the jellyfin container (devices: nvidia.com/gpu=all) comes up with
  # "could not select device driver cdi", exits 128, and is never retried -
  # which 404s Jellyfin until a manual `docker start`. The CDI spec file is
  # already present in /run/cdi at that point, so spec-generator ordering does
  # not help; the fix is to (re)start the container once dockerd is fully up.
  #
  # partOf docker.service => this re-runs whenever docker restarts (e.g. on a
  # nixos activation that bounces docker). The guard skips the start when the
  # container is already running, so a normal activation won't kill live
  # playback.
  systemd.services.jellyfin-gpu-start = {
    description = "Start the Jellyfin GPU container once Docker's CDI registry is ready";
    after = [ "docker.service" ];
    requires = [ "docker.service" ];
    partOf = [ "docker.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "start-jellyfin-gpu" ''
        set -eu
        running=$(${pkgs.docker}/bin/docker inspect -f '{{.State.Running}}' jellyfin 2>/dev/null || echo missing)
        if [ "$running" != "true" ]; then
          ${pkgs.docker}/bin/docker start jellyfin
        fi
      '';
    };
  };

  users.users.deploy.extraGroups = [ "docker" ];
  users.users.cwage.extraGroups = [ "docker" ];

  # /opt/stacks holds the docker-compose.yml + supporting files.
  # deploy user's primary group is "users" (NixOS default for isNormalUser).
  # Static stack config (compose, traefik dyn config) is symlinked from the
  # nix store. Stack secrets (.env, traefik basicauth, staticomment ssh key)
  # and the wildcard TLS cert are rendered by openbao-agent into the dirs
  # below.
  systemd.tmpfiles.rules = [
    "d /opt/stacks                  0755 deploy users -"
    "z /opt/stacks                  0755 deploy users -"
    "d /opt/stacks/certs            0700 deploy users -"
    "z /opt/stacks/certs            0700 deploy users -"
    "d /opt/stacks/staticomment-ssh 0700 deploy users -"
    "z /opt/stacks/staticomment-ssh 0700 deploy users -"
    "L+ /opt/stacks/docker-compose.yml - - - - ${./stacks/docker-compose.yml}"
    "L+ /opt/stacks/traefik-tls.yml    - - - - ${./stacks/traefik-tls.yml}"
  ];

  environment.systemPackages = with pkgs; [
    docker-compose
    rsync
  ];

  # --- OpenBao agent for secrets ---
  # Delivers: cwage password hash, B2 backup credentials, wildcard TLS cert
  # for Traefik, and the three stack secrets (compose .env, traefik
  # basicauth, staticomment SSH deploy key).
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

      # --- Stack secrets ---
      # /opt/stacks is 0755 deploy:users (declared above); render each file
      # with explicit owner/group + manageDestinationDir = false so the
      # agent doesn't try to redeclare the dir. Each secret is stored in
      # OpenBao as a single `content` field whose value is the entire
      # file body (same approach as the cert delivery below).

      # docker-compose .env (CLOUDFLARE_TUNNEL_TOKEN, STATICOMMENT_*).
      # Compose only re-reads .env at compose-up time, so on rotation we
      # `compose up -d` to recreate any container whose env changed.
      stacks-env = {
        path = "kv/data/stacks/containers/env";
        field = "content";
        destination = "/opt/stacks/.env";
        owner = "deploy";
        group = "users";
        permissions = "0600";
        manageDestinationDir = false;
        command = "${pkgs.bash}/bin/bash -c 'cd /opt/stacks && ${pkgs.docker}/bin/docker compose up -d'";
      };

      # Traefik basicauth (htpasswd) for the dashboard middleware. Bind-
      # mounted into the container; Traefik reads it at start, so a
      # restart is required on rotation.
      stacks-traefik-basicauth = {
        path = "kv/data/stacks/containers/basicauth";
        field = "content";
        destination = "/opt/stacks/traefik-basicauth";
        owner = "deploy";
        group = "users";
        permissions = "0600";
        manageDestinationDir = false;
        command = "${pkgs.docker}/bin/docker restart traefik";
      };

      # staticomment SSH deploy key. The dir at /opt/stacks/staticomment-ssh
      # is 0700 deploy:users (declared above).
      stacks-staticomment-ssh-key = {
        path = "kv/data/stacks/containers/staticomment-ssh-key";
        field = "content";
        destination = "/opt/stacks/staticomment-ssh/id_ed25519";
        owner = "deploy";
        group = "users";
        permissions = "0600";
        manageDestinationDir = false;
        command = "${pkgs.docker}/bin/docker restart staticomment";
      };

      # LE wildcard cert delivery for Traefik. The dir at /opt/stacks/certs
      # is 0700 deploy:users (declared above), so we set owner/group on the
      # rendered files explicitly and tell the agent not to redeclare the dir.
      traefik-tls-cert = {
        path = "kv/data/infra/certs/lan.quietlife.net";
        field = "certificate";
        destination = "/opt/stacks/certs/lan.quietlife.net.crt";
        owner = "deploy";
        group = "users";
        permissions = "0644";
        manageDestinationDir = false;
      };
      traefik-tls-key = {
        path = "kv/data/infra/certs/lan.quietlife.net";
        field = "private_key";
        destination = "/opt/stacks/certs/lan.quietlife.net.key";
        owner = "deploy";
        group = "users";
        permissions = "0600";
        manageDestinationDir = false;
        # Command on the key, which sorts after traefik-tls-cert and is
        # therefore rendered second (see modules/openbao-agent.nix). The
        # command fires only after both files are on disk.
        # Traefik doesn't watch bind-mounted cert files, so a restart is
        # required — `docker restart` is idempotent and ~2s, fine for a
        # quarterly rotation.
        command = "${pkgs.docker}/bin/docker restart traefik";
      };
    };
  };

  # The agent's stack-secret post-render hooks invoke docker (compose up,
  # restart). Ordering after docker.service ensures those commands don't
  # race the daemon on a cold boot — without this, a fresh boot can render
  # secrets before docker is up, the command fails silently, and the
  # consumer container never gets restarted until the next rotation.
  systemd.services.openbao-agent.after = [ "docker.service" ];

  # --- ntfy.sh notifications ---
  # OnFailure/OnSuccess hooks on the backup units pull last 20 journal lines
  # and post them to this topic.
  homelab.ntfy = {
    enable = true;
    topic = "https://ntfy.sh/cwage-homelab-backup";
  };

  # --- Redheaded Stranger specials -> ntfy ---
  # Polls their Instagram feed hourly 07:00-13:00 plus a 19:00 sweep (module
  # defaults) and pushes new posts to ntfy.sh/rhs-specials. Failures ping the
  # notify-failure@ hook above.
  homelab.rhs-specials.enable = true;

  # --- Backups ---
  # Three nightly jobs:
  #   - configs (03:00): briefly stop/start each compose service while
  #     rsyncing its named volume to /mnt/nas/containers-configs/
  #   - b2 (03:40):       encrypted Backblaze sync (configs land here too,
  #                       picked up via the containers-configs path)
  #   - local (02:00):    full unencrypted copy to the USB drive at /mnt/nasbak
  # Schedules are deliberately staggered: local first, then configs, then b2
  # consumes the fresh containers-configs snapshot.
  #
  # Plus monthly restore verification on the 1st (issue #174), after the
  # nightly jobs have finished:
  #   - verify-b2-cryptcheck (05:00): hash-verify every synced file against
  #     B2 without downloading (Media excluded — cryptcheck reads all source
  #     bytes, and multi-TB over NFS makes the run take most of a day)
  #   - verify-b2-sample (06:30):     random file per share pulled back
  #     through b2crypt and byte-compared against the NAS source
  #   - verify-local-sample (07:00):  random file per share compared against
  #     the USB copy
  homelab.backups = {
    verify = {
      enable = true;
      cryptcheckPaths = [
        "Pictures"
        "Documents"
        "paperless"
        "Books"
        "bp"
        "caitstuff"
        "syncthing-data"
        "backup"
        "Misc"
        "homelab-backups"
        "containers-configs"
        "tofu-state"
      ];
    };

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
        # CryptPad stores data across several dirs; back up the four that hold
        # real state (documents/channels, pins+metadata, uploaded blobs, and
        # account login blocks). The job stops/starts the container per entry,
        # so cryptpad briefly flaps a few times during the nightly snapshot.
        { name = "cryptpad";        mount = "/cryptpad/datastore"; }
        { name = "cryptpad";        mount = "/cryptpad/data"; }
        { name = "cryptpad";        mount = "/cryptpad/blob"; }
        { name = "cryptpad";        mount = "/cryptpad/block"; }
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
