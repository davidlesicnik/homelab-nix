{
  description = "NixOS configurations for the homelab";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      disko,
      ...
    }:
    {
      nixosConfigurations.docker = nixpkgs.lib.nixosSystem {
        modules = [
          disko.nixosModules.disko
          ./hosts/docker
          { system.configurationRevision = self.rev or self.dirtyRev or null; }
        ];
      };

      # Use the locked Disko version for the initial installation, too.
      packages.x86_64-linux.disko = disko.packages.x86_64-linux.disko;
    };
}
