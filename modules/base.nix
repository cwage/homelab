{ config, lib, pkgs, ... }:

{
  # Manage user accounts declaratively — passwords are set from hashedPasswordFile
  # on every activation rather than only at initial user creation
  users.mutableUsers = false;

  # Deploy user (matches Ansible deploy user on Debian hosts)
  users.users.deploy = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keyFiles = [
      ../ansible/keys/deploy.pub
    ];
  };

  # cwage user — password hash delivered by openbao-agent to /etc/secrets/
  users.users.cwage = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    hashedPasswordFile = "/etc/secrets/cwage-password-hash";
    openssh.authorizedKeys.keyFiles = [
      ../ansible/inventories/keys/cwage-portaplotz.pub
      ../ansible/inventories/keys/cwage-portaptty.pub
      ../ansible/inventories/keys/cwage-shot.pub
    ];
  };

  # Passwordless sudo for deploy user (matches Ansible sudoers config)
  security.sudo.extraRules = [
    {
      users = [ "deploy" ];
      commands = [
        { command = "ALL"; options = [ "NOPASSWD" ]; }
      ];
    }
  ];

  # SSH server
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };

  # QEMU guest agent (required for Proxmox VM management)
  services.qemuGuest.enable = true;

  # Timezone and locale (matches existing Ansible-managed hosts)
  time.timeZone = "America/Chicago";
  i18n.defaultLocale = "en_US.UTF-8";

  # Base packages
  environment.systemPackages = with pkgs; [
    vim
    curl
    htop
    git
    wget
    tmux
    jq
  ];

  # Enable nix flakes on the resulting host
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Allow deploy user to push store paths without signatures (for remote deploys)
  nix.settings.trusted-users = [ "root" "deploy" ];

  # Firewall disabled — pf on fw1 handles LAN firewalling
  networking.firewall.enable = lib.mkDefault false;

  system.stateVersion = "24.11";
}
