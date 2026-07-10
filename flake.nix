{
  description = "flake for 4amlunch.net hosts";

  inputs = {
    nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0"; # Stable Nixpkgs
    linux_7_0.url = "github:NixOS/nixpkgs/709592197675b569aeaf6a68eb66365226a7c718";
    determinate = {
      url = "https://flakehub.com/f/DeterminateSystems/determinate/3"; # Determinate 3.*
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko/latest";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    musnix = {
      url = "github:musnix/musnix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { self, nixpkgs, ... }@inputs:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      inherit (nixpkgs) lib;
    in
    {
      nixosConfigurations = {
        deepthought = lib.nixosSystem {
          inherit system;

          specialArgs = {
            inherit inputs;
          };

          modules = [
            ./systems/deepthought/default.nix
          ];
        };
      };

      packages.${system} = {
        inherit (inputs.disko.packages.${system}) disko disko-install;
      };

      formatter.${system} = pkgs.nixfmt-tree;

      checks.${system} = {
        nixos = self.nixosConfigurations.deepthought.config.system.build.toplevel;

        hugepages =
          assert import ./common/hugepages-test.nix;
          pkgs.runCommand "hugepages-test" { } ''
            touch "$out"
          '';

        storage-layout =
          let
            config = self.nixosConfigurations.deepthought.config;
            activeMounts = map (filesystem: filesystem.mountPoint) config.system.build.fileSystems;
          in
          assert
            builtins.attrNames config.disko.devices.disk == [
              "os"
              "tank"
            ];
          assert
            builtins.attrNames config.disko.devices.zpool == [
              "tank"
              "zpool"
            ];
          assert config.disko.devices.zpool.zpool.datasets.root.options.mountpoint == "legacy";
          assert config.disko.devices.zpool.zpool.datasets.nix.options.mountpoint == "legacy";
          assert config.disko.devices.zpool.zpool.datasets.var.mountpoint == "/var";
          assert config.disko.devices.zpool.zpool.datasets.docker.mountpoint == "/var/lib/docker";
          assert config.disko.devices.zpool.tank.datasets.home.mountpoint == "/home";
          assert lib.all (mountpoint: lib.elem mountpoint activeMounts) [
            "/"
            "/boot"
            "/nix"
          ];
          assert lib.all (mountpoint: !lib.elem mountpoint activeMounts) [
            "/var"
            "/var/lib/docker"
            "/home"
          ];
          assert !lib.elem "basket" config.boot.zfs.extraPools;
          pkgs.runCommand "storage-layout-test" { } ''
            touch "$out"
          '';

        formatting = pkgs.runCommand "formatting-check" { nativeBuildInputs = [ pkgs.nixfmt-tree ]; } ''
          cp -r ${self} source
          chmod -R u+w source
          cd source
          treefmt --ci --tree-root "$PWD" --walk filesystem .
          touch "$out"
        '';
      };
    };
}
