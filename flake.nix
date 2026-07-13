{
  description = "flake for 4amlunch.net hosts";

  inputs = {
    nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0"; # Stable Nixpkgs
    unstable-nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0.1"; # Unstable Nixpkgs
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

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    auto-splice = {
      url = "github:zenith-network/auto-splice";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    spotify-midi-control = {
      url = "github:bhechinger/spotify-midi-control";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
  };

  outputs =
    { self, nixpkgs, ... }@inputs:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
      unstable-pkgs = import inputs.unstable-nixpkgs {
        inherit system;
        config.allowUnfree = true;
        overlays = [
          (_final: prev: {
            codex = prev.codex.overrideAttrs (old: rec {
              version = "0.144.1";
              src = prev.fetchFromGitHub {
                owner = "openai";
                repo = "codex";
                tag = "rust-v0.144.1";
                hash = "sha256-KHgrqIZyAmLhTZSRYbb7huBO8neOib/B1Vx/oPW2nEU=";
              };
              cargoHash = "sha256-S4dsZXfmKvJItL2XYKyxfhqdCMATEG6oPjrtVRwkuYc=";
              cargoDeps = prev.rustPlatform.fetchCargoVendor {
                inherit src version;
                pname = "codex";
                hash = cargoHash;
              };
              env = (old.env or { }) // {
                RUST_MIN_STACK = "16777216";
              };
              postFixup = (old.postFixup or "") + ''
                mv $out/bin/codex $out/bin/.codex-setpriv-target
                makeWrapper ${prev.util-linux}/bin/setpriv $out/bin/codex \
                  --set SSL_CERT_FILE "${prev.cacert}/etc/ssl/certs/ca-bundle.crt" \
                  --set NIX_SSL_CERT_FILE "${prev.cacert}/etc/ssl/certs/ca-bundle.crt" \
                  --add-flags "--inh-caps=-all" \
                  --add-flags "--ambient-caps=-all" \
                  --add-flags "$out/bin/.codex-setpriv-target"
              '';
            });
          })
        ];
      };
      inherit (nixpkgs) lib;
    in
    {
      nixosConfigurations = {
        bob = lib.nixosSystem {
          inherit system;

          specialArgs = {
            inherit inputs;
          };

          modules = [
            ./systems/bob/default.nix
          ];
        };

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

      homeConfigurations.wonko = inputs.home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        extraSpecialArgs = {
          inherit unstable-pkgs;
          inherit (inputs) auto-splice spotify-midi-control;
        };
        modules = [
          inputs.determinate.homeManagerModules.default
          inputs.spotify-midi-control.homeManagerModules.default
          ./home/home.nix
          ./home/zsh.nix
          ./home/atuin.nix
          ./home/audio.nix
          ./home/development.nix
          ./home/greptile.nix
          ./home/kubernetes.nix
          ./home/software.nix
          ./home/desktop.nix
          ./home/nix_tools.nix
          ./home/zenith.nix
          ./home/games.nix
          ./home/gamedev.nix
        ];
      };

      packages.${system} = {
        inherit (inputs.disko.packages.${system}) disko disko-install;
      };

      formatter.${system} = pkgs.nixfmt-tree;

      checks.${system} = {
        bob = self.nixosConfigurations.bob.config.system.build.toplevel;
        nixos = self.nixosConfigurations.deepthought.config.system.build.toplevel;
        home = self.homeConfigurations.wonko.activationPackage;

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

        bob-policy =
          let
            config = self.nixosConfigurations.bob.config;
            firewall = config.networking.firewall;
            management = firewall.interfaces.management;
            composeServices = [
              config.systemd.services.compose-ad
              config.systemd.services.compose-main
              config.systemd.services.compose-unifi
            ];
          in
          assert config.services.tailscale.enable;
          assert config.services.zerotierone.enable;
          assert config.services.zerotierone.joinNetworks == [ "a84ac5c10a853bc1" ];
          assert config.services.openvpn.servers == { };
          assert self.nixosConfigurations.deepthought.config.services.openvpn.servers == { };
          assert !config.virtualisation.libvirtd.enable;
          assert !(config.systemd.network.links ? "10-storage");
          assert
            builtins.attrNames config.networking.bridges == [
              "guest"
              "internal"
              "management"
            ];
          assert
            builtins.attrNames config.networking.vlans == [
              "vlan.410"
              "vlan.420"
            ];
          assert !(config.networking.interfaces ? storage);
          assert !config.systemd.network.wait-online.anyInterface;
          assert lib.elem "--interface=internal:routable" config.systemd.network.wait-online.extraArgs;
          assert firewall.allowedTCPPorts == [ ];
          assert firewall.allowedUDPPorts == [ ];
          assert
            builtins.attrNames firewall.interfaces == [
              "internal"
              "management"
              "tailscale0"
              "ztnfaeb6wl"
            ];
          assert management.allowedTCPPorts == [ 8080 ];
          assert
            management.allowedUDPPorts == [
              1900
              3478
              5514
              10001
            ];
          assert lib.all (
            service: lib.hasInfix "--pull never" service.serviceConfig.ExecStart
          ) composeServices;
          pkgs.runCommand "bob-policy-test" { } ''
            touch "$out"
          '';

        bob-shell = pkgs.runCommand "bob-shell-check" { nativeBuildInputs = [ pkgs.shellcheck ]; } ''
          bash -n ${./systems/bob/backup.sh} ${./systems/bob/restore.sh} ${./repl.sh}
          shellcheck -s bash ${./systems/bob/backup.sh} ${./systems/bob/restore.sh} ${./repl.sh}
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
