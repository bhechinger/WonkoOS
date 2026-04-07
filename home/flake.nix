{
  inputs = {
    nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0"; # Stable Nixpkgs
    unstable-nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0.1"; # Unstable Nixpkgs

    determinate = {
      url = "https://flakehub.com/f/DeterminateSystems/determinate/3"; # Determinate 3.*
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      nixpkgs,
      unstable-nixpkgs,
      home-manager,
      ...
    }:
    let
      #lib = nixpkgs.lib;
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config = {
          allowUnfree = true;
        };
      };
      unstable-pkgs = import unstable-nixpkgs {
        inherit system;
        config = {
          allowUnfree = true;
        };
      };
    in
    {
      homeConfigurations = {
        wonko = home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          extraSpecialArgs = {
            inherit unstable-pkgs;
          };
          modules = [
            ./home.nix
            ./zsh.nix
            ./atuin.nix
            ./audio.nix
            ./development.nix
            ./kubernetes.nix
            ./software.nix
            ./desktop.nix
          ];
        };
      };
    };
}
