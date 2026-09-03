{
  description = "flake for 4amlunch.net hosts";

  inputs = {
    nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0.2605"; # Stable Nixpkgs
    unstable-nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0.1"; # Unstable Nixpkgs
    pipewire-src = {
      url = "path:/home/wonko/src/pipewire";
      flake = false;
    };
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

    nix-minecraft = {
      url = "github:Infinidoge/nix-minecraft";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    playit-nixos-module = {
      url = "github:pedorich-n/playit-nixos-module";
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
      useSaffireFfado = false;
      hyprlandFix = "d8504461f0e9f95a5df9a0cdc0723d0ca6332888";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
      unstable-pkgs = import inputs.unstable-nixpkgs {
        inherit system;
        config.allowUnfree = true;
        overlays = [
          (_final: prev: {
            hyprland = prev.hyprland.overrideAttrs (old: {
              patches = (old.patches or [ ]) ++ [
                (prev.fetchurl {
                  url = "https://github.com/hyprwm/Hyprland/commit/${hyprlandFix}.patch";
                  hash = "sha256-cZ8LzzU7fUzV7C2VOqFUOs4IOuqDHFtBQmGGgbTRjhw=";
                })
              ];
            });
            codex =
              let
                version = "0.153.0";
                codexBin = prev.fetchurl {
                  url = "https://github.com/openai/codex/releases/download/rust-v${version}/codex-x86_64-unknown-linux-musl.tar.gz";
                  hash = "sha256-NagsFT2DlZ3gnCy4SscLpp0FeIrusI1Klcpo45+GaA4=";
                };
                codexCodeModeHost = prev.fetchurl {
                  url = "https://github.com/openai/codex/releases/download/rust-v${version}/codex-code-mode-host-x86_64-unknown-linux-musl.tar.gz";
                  hash = "sha256-K4F6SV41pTMz6Us1r57YeeGA+bKP1X7xWs6ahXuobyw=";
                };
              in
              prev.stdenvNoCC.mkDerivation {
                pname = "codex";
                inherit version;

                nativeBuildInputs = [ prev.makeWrapper ];
                dontUnpack = true;

                installPhase = ''
                  runHook preInstall

                  install -d $out/bin
                  tar -xzf ${codexBin} -C $out/bin
                  tar -xzf ${codexCodeModeHost} -C $out/bin
                  mv $out/bin/codex-x86_64-unknown-linux-musl $out/bin/.codex-setpriv-target
                  mv $out/bin/codex-code-mode-host-x86_64-unknown-linux-musl $out/bin/codex-code-mode-host
                  chmod +x $out/bin/.codex-setpriv-target $out/bin/codex-code-mode-host
                  makeWrapper ${prev.util-linux}/bin/setpriv $out/bin/codex \
                    --set RUST_MIN_STACK "16777216" \
                    --set SSL_CERT_FILE "${prev.cacert}/etc/ssl/certs/ca-bundle.crt" \
                    --set NIX_SSL_CERT_FILE "${prev.cacert}/etc/ssl/certs/ca-bundle.crt" \
                    --prefix PATH : ${
                      prev.lib.makeBinPath [
                        prev.ripgrep
                        prev.bubblewrap
                      ]
                    } \
                    --add-flags "--inh-caps=-all" \
                    --add-flags "--ambient-caps=-all" \
                    --add-flags "$out/bin/.codex-setpriv-target"

                  runHook postInstall
                '';

                meta = prev.codex.meta // {
                  changelog = "https://raw.githubusercontent.com/openai/codex/refs/tags/rust-v${version}/CHANGELOG.md";
                  platforms = [ "x86_64-linux" ];
                };
              };
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
            inherit inputs unstable-pkgs useSaffireFfado;
          };

          modules = [
            ./systems/deepthought/default.nix
          ];
        };
      };

      homeConfigurations.wonko = inputs.home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        extraSpecialArgs = {
          inherit hyprlandFix unstable-pkgs useSaffireFfado;
          inherit (inputs) auto-splice pipewire-src spotify-midi-control;
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

        hyprland-config =
          let
            hyprland = self.nixosConfigurations.deepthought.config.programs.hyprland.package;
            hyprlandConfig = self.homeConfigurations.wonko.config.xdg.configFile."hypr/hyprland.lua".source;
          in
          pkgs.runCommand "hyprland-config-check" { } ''
            XDG_RUNTIME_DIR="$TMPDIR" ${lib.getExe hyprland} --verify-config --config ${hyprlandConfig}
            touch "$out"
          '';

        hugepages =
          assert import ./common/hugepages-test.nix;
          pkgs.runCommand "hugepages-test" { } ''
            touch "$out"
          '';

        opnsense-dns-sync =
          pkgs.runCommand "opnsense-dns-sync-test"
            {
              nativeBuildInputs = with pkgs; [
                bash
                jq
                shellcheck
              ];
            }
            ''
              bash -n ${./scripts/opnsense-dns-sync.sh} ${./scripts/opnsense-dns-sync-test.sh}
              shellcheck -s bash ${./scripts/opnsense-dns-sync.sh} ${./scripts/opnsense-dns-sync-test.sh}
              bash ${./scripts/opnsense-dns-sync-test.sh} ${./scripts/opnsense-dns-sync.sh}
              touch "$out"
            '';

        sierra-bind =
          pkgs.runCommand "sierra-bind-test"
            {
              nativeBuildInputs = with pkgs; [
                bind
                shellcheck
              ];
            }
            ''
              shellcheck -s sh ${./systems/sierra/install-bind.sh}
              ${./systems/sierra/install-bind.sh} --self-test
              touch "$out"
            '';

        cloudflare-tunnel-sync = pkgs.runCommand "cloudflare-tunnel-sync-test" { } ''
          ${lib.getExe pkgs.python3} ${./scripts/cloudflare-tunnel-sync.py} --self-test
          touch "$out"
        '';

        storage-layout = import ./checks/storage-layout.nix { inherit self lib pkgs; };

        bob-policy = import ./checks/bob-policy.nix { inherit self lib pkgs; };

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
