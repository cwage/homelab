{
  description = "Homelab NixOS configurations";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
  };

  outputs = { self, nixpkgs }:
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

      nixosConfigurations.bao2 = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          "${nixpkgs}/nixos/modules/virtualisation/proxmox-image.nix"
          ./modules/base.nix
          ./modules/openbao-agent.nix
          ./hosts/openbao/configuration.nix
        ];
      };

      packages.${system} = {
        proxmox-template =
          self.nixosConfigurations.proxmox-template.config.system.build.VMA;
        default = self.packages.${system}.proxmox-template;
      };
    };
}
