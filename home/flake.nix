{
  inputs = {
    nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0"; # Stable Nixpkgs
    unstable-nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0.1"; # Unstable Nixpkgs

    determinate = {
      url = "https://flakehub.com/f/DeterminateSystems/determinate/3"; # Determinate 3.*
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    auto-splice.url = "github:zenith-network/auto-splice";

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      nixpkgs,
      unstable-nixpkgs,
      home-manager,
      auto-splice,
      sops-nix,
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
            inherit auto-splice;
            inherit sops-nix;
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
            ./nix_tools.nix
            ./zenith.nix
            ./games.nix
            ./circleci-runner.nix
            ./gamedev.nix
          ];
        };
      };
    };
}
