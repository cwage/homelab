{
  description = "Homelab NixOS configurations";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    # Secrets for hosts that cannot reach OpenBao. The openbao-agent module
    # authenticates via an AppRole CIDR-bound to a LAN address, which does not
    # work for a public VPS — see docs/xmpp.md.
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Declarative partitioning, used by nixos-anywhere to install onto a Linode.
    # Proxmox hosts don't need this — they clone a prebuilt VMA template.
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, sops-nix, disko }:
    let
      system = "x86_64-linux";
    in
    {
      nixosConfigurations.proxmox-template = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          "${nixpkgs}/nixos/modules/virtualisation/proxmox-image.nix"
          ./modules/base.nix
          ./nix/template.nix
        ];
      };

      nixosConfigurations.nixos-test = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          "${nixpkgs}/nixos/modules/virtualisation/proxmox-image.nix"
          ./modules/base.nix
          ./modules/openbao-agent.nix
          ./hosts/nixos-test/configuration.nix
        ];
      };

      nixosConfigurations.dns1 = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          "${nixpkgs}/nixos/modules/virtualisation/proxmox-image.nix"
          ./modules/base.nix
          ./modules/openbao-agent.nix
          ./modules/ntfy-notify.nix
          ./modules/nixos-staleness.nix
          ./hosts/dns1/configuration.nix
        ];
      };

      nixosConfigurations.bao = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          "${nixpkgs}/nixos/modules/virtualisation/proxmox-image.nix"
          ./modules/base.nix
          ./modules/openbao-agent.nix
          ./modules/ntfy-notify.nix
          ./modules/nixos-staleness.nix
          ./hosts/openbao/configuration.nix
        ];
      };

      nixosConfigurations.containers = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          "${nixpkgs}/nixos/modules/virtualisation/proxmox-image.nix"
          ./modules/base.nix
          ./modules/openbao-agent.nix
          ./modules/ntfy-notify.nix
          ./modules/backups.nix
          ./modules/rhs-specials
          ./modules/nixos-staleness.nix
          ./hosts/containers/configuration.nix
        ];
      };

      # xmpp1 — Prosody + coturn on a public Linode. The only NixOS host outside
      # the LAN, so it differs from the others in two ways: no proxmox-image
      # (installed with nixos-anywhere + disko instead of cloned from a
      # template), and sops-nix rather than openbao-agent for secrets, since it
      # cannot reach bao.lan.quietlife.net. See docs/xmpp.md.
      nixosConfigurations.xmpp1 = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          disko.nixosModules.disko
          sops-nix.nixosModules.sops
          ./modules/base.nix
          ./modules/ntfy-notify.nix
          ./modules/nixos-staleness.nix
          ./hosts/xmpp1/disko.nix
          ./hosts/xmpp1/configuration.nix
        ];
      };

      packages.${system} = {
        proxmox-template =
          self.nixosConfigurations.proxmox-template.config.system.build.VMA;
        default = self.packages.${system}.proxmox-template;
      };
    };
}
