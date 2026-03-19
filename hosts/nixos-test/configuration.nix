{ config, lib, pkgs, ... }:

{
  # Test VM for validating openbao-agent AppRole integration.
  # Clone from NixOS template (VMID 9001), apply with:
  #   nixos-rebuild switch --flake /path/to/homelab#nixos-test

  networking.hostName = "nixos-test";

  homelab.openbao-agent = {
    enable = true;
    roleId = "d3cab8d5-581a-be79-6119-9d4b8396b554";
    secrets = {
      cwage-password-hash = {
        path = "kv/data/infra/users/cwage";
        field = "password_hash";
        destination = "/etc/secrets/cwage-password-hash";
      };
    };
  };
}
