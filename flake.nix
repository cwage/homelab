{
  description = "Homelab NixOS configurations";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";

    # Secrets for hosts that cannot reach OpenBao. The openbao-agent module
    # authenticates via an AppRole CIDR-bound to a LAN address, which does not
    # work for a public VPS — see docs/xmpp.md.
    # Pinned, not tracking master. sops-nix builds sops-install-secrets from the
    # *consuming* system's nixpkgs, and current master needs buildGo125Module —
    # absent in nixos-24.11. This revision (2025-01-31) is the last that builds
    # against 24.11. Unpin when nixpkgs moves forward; see docs/xmpp.md.
    sops-nix = {
      url = "github:Mic92/sops-nix/4c1251904d8a08c86ac6bc0d72cc09975e89aef7";
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
