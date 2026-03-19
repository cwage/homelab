{ config, lib, pkgs, ... }:

{
  # Deploy user (matches Ansible deploy user on Debian hosts)
  users.users.deploy = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keyFiles = [
      ../ansible/keys/deploy.pub
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

  # Firewall disabled — pf on fw1 handles LAN firewalling
  networking.firewall.enable = lib.mkDefault false;

  system.stateVersion = "24.11";
}
