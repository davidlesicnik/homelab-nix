{
  description = "NixOS configurations for the homelab";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      disko,
      sops-nix,
      ...
    }:
    let
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
    in
    {
      nixosConfigurations.docker = nixpkgs.lib.nixosSystem {
        modules = [
          disko.nixosModules.disko
          sops-nix.nixosModules.sops
          ./hosts/docker
          { system.configurationRevision = self.rev or self.dirtyRev or null; }
        ];
      };

      packages.x86_64-linux = {
        # Use the locked Disko version for the initial installation, too.
        disko = disko.packages.x86_64-linux.disko;
        caddy = pkgs.callPackage ./stacks/caddy/package.nix { };
        caddy-image = pkgs.callPackage ./stacks/caddy/image.nix { };
      };

      checks.x86_64-linux.caddy-config = pkgs.callPackage ./stacks/caddy/config.nix { };
      checks.x86_64-linux.container-images =
        assert import ./tests/container-image.nix;
        pkgs.runCommand "container-images" { } "touch $out";

      devShells =
        nixpkgs.lib.genAttrs
          [
            "aarch64-darwin"
            "x86_64-darwin"
            "aarch64-linux"
            "x86_64-linux"
          ]
          (system: {
            default = nixpkgs.legacyPackages.${system}.mkShellNoCC {
              packages = with nixpkgs.legacyPackages.${system}; [
                sops
                age
              ];
            };
          });
    };
}
