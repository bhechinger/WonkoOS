{
  description = "wonkoOS system builds";

  inputs = {
    # Nixpkgs
    nixpkgs.url = "github:nixos/nixpkgs/nixos-23.05";

    # Nixpkgs-unstable
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    # Home manager
    home-manager.url = "github:nix-community/home-manager/release-23.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    # Branch with working ruTorrent
    nixpkgs_rutorrent.url = "github:bolives-hax/nixpkgs/add-rutorrent-service";

    # Disko
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs-unstable";
  };

  outputs = { self, nixpkgs, home-manager, nixpkgs_rutorrent, ... }@inputs:
    let
      inherit (self) outputs;

      system = "x86_64-linux";

      pgks = import nixpkgs {
        inherit system;
        config = { allowUnfree = true; };
      };

	  specialArgs = system: {
		inherit inputs outputs;
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
