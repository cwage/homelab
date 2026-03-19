{ config, lib, pkgs, ... }:

{
  # Proxmox VMA image settings
  proxmox = {
    qemuConf = {
      cores = 2;
      memory = 2048;
      name = "nixos-template";
      net0 = "virtio=00:00:00:00:00:00,bridge=vmbr0,firewall=0";
      agent = true;
      scsihw = "virtio-scsi-single";
    };

    cloudInit.enable = true;

    filenameSuffix = "nixos-template";
  };
}
