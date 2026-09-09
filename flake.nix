{
  description = "flake for 4amlunch.net hosts";

  inputs = {
    nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0.2605"; # Stable Nixpkgs
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
      darwinSystem = "aarch64-darwin";
      codexVersion = "0.153.0";
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
                version = codexVersion;
                src = prev.fetchurl {
                  url = "https://github.com/openai/codex/releases/download/rust-v${version}/codex-package-x86_64-unknown-linux-musl.tar.gz";
                  hash = "sha256-J7DXp1OsGQw0ORhUGkIGe+MHzIijKxqf6vb5Nkig6eo=";
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
                  tar -xzf ${src} -C $out
                  mv $out/bin/codex $out/bin/.codex-setpriv-target
                  makeWrapper ${prev.util-linux}/bin/setpriv $out/bin/codex \
                    --set RUST_MIN_STACK "16777216" \
                    --set SSL_CERT_FILE "${prev.cacert}/etc/ssl/certs/ca-bundle.crt" \
                    --set NIX_SSL_CERT_FILE "${prev.cacert}/etc/ssl/certs/ca-bundle.crt" \
                    --prefix PATH : ${prev.lib.makeBinPath [ prev.bubblewrap ]} \
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
      darwinPkgs = import nixpkgs {
        system = darwinSystem;
        config.allowUnfree = true;
      };
      darwinUnstablePkgs = import inputs.unstable-nixpkgs {
        system = darwinSystem;
        config.allowUnfree = true;
        overlays = [
          (_final: prev: {
            codex = prev.stdenvNoCC.mkDerivation {
              pname = "codex";
              version = codexVersion;
              src = prev.fetchurl {
                url = "https://github.com/openai/codex/releases/download/rust-v${codexVersion}/codex-aarch64-apple-darwin.tar.gz";
                hash = "sha256-jN7NC46+I/IOs3MBD9kelReXfoQLaJQe9qZGtAnLMuE=";
              };
              dontUnpack = true;
              installPhase = ''
                mkdir -p "$out/bin"
                tar -xzf "$src"
                install -m 0755 codex-aarch64-apple-darwin "$out/bin/codex"
              '';
              meta = prev.codex.meta // {
                platforms = [ darwinSystem ];
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
            inherit inputs unstable-pkgs;
          };

          modules = [
            ./systems/deepthought/default.nix
          ];
        };
      };

      homeConfigurations.deepthought = inputs.home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        extraSpecialArgs = {
          inherit
            inputs
            hyprlandFix
            unstable-pkgs
            ;
          inherit (inputs) auto-splice spotify-midi-control;
        };
        modules = [
          ./home/deepthought
        ];
      };

      homeConfigurations.wintermute = inputs.home-manager.lib.homeManagerConfiguration {
        pkgs = darwinPkgs;
        extraSpecialArgs.unstable-pkgs = darwinUnstablePkgs;
        modules = [
          inputs.sops-nix.homeManagerModules.sops
          ./home/wintermute
        ];
      };

      packages.${system} = {
        inherit (inputs.disko.packages.${system}) disko disko-install;
      };

      formatter.${system} = pkgs.nixfmt-tree;
      formatter.${darwinSystem} = darwinPkgs.nixfmt-tree;

      checks.${system} = {
        bob = self.nixosConfigurations.bob.config.system.build.toplevel;
        nixos = self.nixosConfigurations.deepthought.config.system.build.toplevel;
        home = self.homeConfigurations.deepthought.activationPackage;

        hyprland-config =
          let
            hyprland = self.nixosConfigurations.deepthought.config.programs.hyprland.package;
            hyprlandConfig =
              self.homeConfigurations.deepthought.config.xdg.configFile."hypr/hyprland.lua".source;
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

        host-workflows =
          pkgs.runCommand "host-workflows-test"
            {
              nativeBuildInputs = [ pkgs.gnumake ];
            }
            ''
              cp ${./Makefile} Makefile
              mkdir bin
              printf '%s\n' '#!/bin/sh' 'printf "%s\n" deepthought' > bin/hostname
              chmod +x bin/hostname
              for host in deepthought bob wintermute unknown; do
                mkdir -p "hosts/$host"
                sed "s|^override HOST :=.*$|override HOST := $host|" Makefile > "hosts/$host/Makefile"
              done

              make -C hosts/deepthought --no-print-directory -n build switch boot > deepthought
              grep -Fq 'nh os build -H deepthought .' deepthought
              grep -Fq 'nh home build . -c deepthought' deepthought
              grep -Fq 'nh home switch . -c deepthought' deepthought

              make -C hosts/bob --no-print-directory -n build switch boot > bob
              grep -Fq 'nh os build -H bob --diff never .' bob
              grep -Fq 'nh os switch -H bob --diff never .' bob
              grep -Fq './scripts/generate_hugepages_inputs.sh' bob

              make -C hosts/deepthought --no-print-directory -n build-bob > bob-remote
              ! grep -Fq './scripts/generate_hugepages_inputs.sh' bob-remote

              make -C hosts/wintermute --no-print-directory -n build switch > wintermute
              grep -Fq 'nix build .#homeConfigurations.wintermute.activationPackage' wintermute
              ! grep -Fq 'ssh ' wintermute

              make -C hosts/deepthought --no-print-directory -n build-wintermute > wintermute-remote
              grep -Fq -- '--eval-store daemon --store ssh-ng://wonko@wintermute.lan' wintermute-remote

              ! make -C hosts/wintermute --no-print-directory boot
              ! make -C hosts/bob --no-print-directory build-wintermute
              ! make -C hosts/wintermute --no-print-directory deploy-bob
              ! make -C hosts/bob --no-print-directory build-deepthought
              ! make -C hosts/wintermute --no-print-directory rollback-pwppp
              ! make -C hosts/unknown --no-print-directory build
              ! make -C hosts/wintermute --no-print-directory HOST=deepthought deploy-bob
              ! make -C hosts/wintermute --no-print-directory --ignore-errors build-bob
              ! make -C hosts/wintermute --no-print-directory require_host= build-bob
              ! make -C hosts/wintermute --no-print-directory require_self= boot-bob
              ! make -C hosts/wintermute --no-print-directory --eval='build-bob: override HOST := deepthought' --eval='build-bob: override require_host :=' -n build-bob

              actual="$(cut -d. -f1 /proc/sys/kernel/hostname)"
              detected="$(PATH="$PWD/bin:$PATH" make -f Makefile --no-print-directory -s --eval 'print-host: ; @printf "%s\n" "$(HOST)"' print-host)"
              test "$detected" = "$actual"

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

      checks.${darwinSystem}.home = self.homeConfigurations.wintermute.activationPackage;
    };
}
