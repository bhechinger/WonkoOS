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
      bobVmTest = pkgs.writeShellApplication {
        name = "bob-vm-test";
        runtimeInputs = with pkgs; [
          coreutils
          gnugrep
          gnutar
          procps
          zstd
        ];
        text = ''
          export BOB_COREUTILS=${pkgs.coreutils}/bin
          export BOB_TAR=${lib.getExe pkgs.gnutar}
          export BOB_VM_RUNNER=${lib.getExe self.nixosConfigurations.bob.config.system.build.vm}
          ${builtins.readFile ./systems/bob/vm-test.sh}
        '';
      };
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
        bob-vm-test = bobVmTest;
      };

      apps.${system}.bob-vm-test = {
        type = "app";
        program = lib.getExe bobVmTest;
      };

      formatter.${system} = pkgs.nixfmt-tree;

      checks.${system} = {
        bob = self.nixosConfigurations.bob.config.system.build.toplevel;
        bob-vm = self.nixosConfigurations.bob.config.system.build.vm;
        nixos = self.nixosConfigurations.deepthought.config.system.build.toplevel;
        home = self.homeConfigurations.wonko.activationPackage;

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
            vm = config.virtualisation.vmVariant;
            deepthought = self.nixosConfigurations.deepthought.config;
            firewall = config.networking.firewall;
            management = firewall.interfaces.management;
            vyprvpn = deepthought.services.openvpn.servers.vyprvpn-miami;
            vyprvpnProfile = builtins.readFile ./systems/deepthought/openvpn/vyprvpn-miami.ovpn;
            ociContainers = config.virtualisation.oci-containers.containers;
            dnsUpdate = config.systemd.services.opnsense-dns-cache;
          in
          assert config.services.tailscale.enable;
          assert config.services.zerotierone.enable;
          assert config.services.zerotierone.joinNetworks == [ "a84ac5c10a853bc1" ];
          assert config.services.openvpn.servers == { };
          assert builtins.attrNames deepthought.services.openvpn.servers == [ "vyprvpn-miami" ];
          assert !vyprvpn.autoStart;
          assert vyprvpn.updateResolvConf;
          assert vyprvpn.authUserPass == deepthought.sops.secrets.vyprvpn-auth.path;
          assert lib.hasInfix "verify-x509-name us4.vyprvpn.com name" vyprvpnProfile;
          assert lib.hasInfix "block-ipv6" vyprvpnProfile;
          assert lib.hasInfix "redirect-gateway ipv6" vyprvpnProfile;
          assert deepthought.systemd.services.openvpn-vyprvpn-miami.wantedBy == [ ];
          assert lib.elem "sops-install-secrets.service"
            deepthought.systemd.services.openvpn-vyprvpn-miami.requires;
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
          assert !(config.systemd.services ? compose-ad);
          assert !(config.systemd.services ? compose-main);
          assert !(config.systemd.services ? compose-unifi);
          assert config.services.jackett.enable;
          assert config.services.paperless.enable;
          assert config.services.paperless.database.createLocally;
          assert config.services.rtorrent.enable;
          assert config.services.rutorrent.enable;
          assert config.services.sonarr.enable;
          assert config.services.rtorrent.group == "nginx";
          assert config.users.users.avahi.uid == 992;
          assert config.users.users.media.uid == 999;
          assert config.services.postfix.rootAlias == "wonko";
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
          assert
            builtins.attrNames ociContainers == [
              "protonmail-bridge"
              "unifi-controller"
            ];
          assert lib.all (container: container.pull == "never") (builtins.attrValues ociContainers);
          assert lib.elem "network-online.target" dnsUpdate.after;
          assert lib.elem "sops-install-secrets.service" dnsUpdate.requires;
          assert lib.hasInfix "cache 10.42.0.2" dnsUpdate.serviceConfig.ExecStart;
          assert dnsUpdate.serviceConfig.RemainAfterExit;
          assert config.sops.age.sshKeyPaths == [ "/etc/ssh/ssh_host_ed25519_key" ];
          assert config.sops.secrets.opnsense-api-netrc.mode == "0400";
          assert !(vm.systemd.services ? opnsense-dns-cache);
          assert !(vm.sops.secrets ? opnsense-api-netrc);
          assert config.virtualisation.docker.storageDriver == "zfs";
          assert lib.any (mount: mount.what == "10.42.0.30:/Brian") config.systemd.mounts;
          assert lib.any (mount: mount.what == "10.42.0.30:/Plex") config.systemd.mounts;
          assert lib.any (mount: mount.what == "10.42.0.30:/Torrents") config.systemd.mounts;
          assert vm.virtualisation.docker.storageDriver == "overlay2";
          assert vm.virtualisation.restrictNetwork;
          assert vm.virtualisation.forwardPorts == [ ];
          assert !vm.networking.firewall.enable;
          assert vm.networking.useDHCP;
          assert !vm.networking.useNetworkd;
          assert lib.all (mount: !lib.hasPrefix "10.42.0.30:" mount.what) vm.systemd.mounts;
          assert vm.systemd.automounts == [ ];
          assert vm.boot.zfs.extraPools == [ ];
          assert !vm.services.zfs.autoScrub.enable;
          assert !vm.services.zfs.trim.enable;
          assert vm.virtualisation.memorySize == 12288;
          assert vm.virtualisation.cores == 4;
          assert vm.virtualisation.diskSize == 65536;
          assert lib.elem "ro" vm.fileSystems."/tmp/shared".options;
          pkgs.runCommand "bob-policy-test" { } ''
            touch "$out"
          '';

        bob-shell = pkgs.runCommand "bob-shell-check" { nativeBuildInputs = [ pkgs.shellcheck ]; } ''
          bash -n ${./systems/bob/backup.sh} ${./systems/bob/restore.sh} \
            ${./systems/bob/vm-test.sh} ${./systems/bob/vm-guest-test.sh} ${./repl.sh}
          shellcheck -s bash ${./systems/bob/backup.sh} ${./systems/bob/restore.sh} \
            ${./systems/bob/vm-test.sh} ${./systems/bob/vm-guest-test.sh} ${./repl.sh}
          ! grep -Eq '(/etc|/var/lib)/libvirt|/var/lib/machines|libvirt(d|-guests)\.service|/etc/postfix|/var/(spool/postfix|mail|snap)|canonical-livepatch' \
            ${./systems/bob/backup.sh} ${./systems/bob/restore.sh}
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
