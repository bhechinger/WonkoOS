{
  description = "wonkoOS system builds";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    nixpkgs_rutorrent.url = "github:bolives-hax/nixpkgs/add-rutorrent-service";
    disko_pkgs.url = "github:nix-community/disko";
  };

  outputs = { nixpkgs, home-manager, nixpkgs_rutorrent, disko_pkgs, ... }:
    let
      system = "x86_64-linux";

      pgks = import nixpkgs {
        inherit system;
        config = { allowUnfree = true; };
      };

      lib = nixpkgs.lib;
    in
    {
      nixosConfigurations = {
        bob = nixpkgs.lib.nixosSystem {
          inherit system;

          modules = [
            ./system/bob/configuration.nix
            ./system/bob/nfs-mounts.nix
            ./system/bob/media.nix
            ./system/bob/rutorrent.nix
          ];

	  specialArgs = {
		inherit nixpkgs_rutorrent;
	  };
        };

        deepthought = nixpkgs.lib.nixosSystem {
          inherit system;

          modules = [
            ./system/deepthought/configuration.nix
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.cesar = import ./home/home.nix;
            }
          ];
        };
      };
    };
}
