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

  # --- NFS mounts (mirror the Ansible-managed mounts on the live containers VM) ---
  # Subset for now: just what's needed to consume the pre-migration snapshots
  # and operate the existing services. Read-only shares (Books, Documents, etc.)
  # follow once we're closer to cutover.
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
    "d /opt/stacks/certs 0755 deploy users -"
    "d /opt/backup       0750 deploy users -"
    "d /opt/backup/logs  0750 deploy users -"
    "L+ /opt/stacks/docker-compose.yml - - - - ${./stacks/docker-compose.yml}"
    "L+ /opt/stacks/traefik-tls.yml    - - - - ${./stacks/traefik-tls.yml}"
  ];

  environment.systemPackages = with pkgs; [
    docker-compose
    rsync
  ];

  # --- OpenBao agent for secrets (cwage password hash for now) ---
  # Real services (Docker, GPU, NFS, TLS, stack) land in follow-up PRs.
  # The roleId below is per-host and CIDR-bound to 10.10.15.11; fill it in
  # after running:
  #   make openbao-approle-create-role NAME=containers2 IP=10.10.15.11
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
    };
  };
}
