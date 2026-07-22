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

        cloudflare-tunnel-sync = pkgs.runCommand "cloudflare-tunnel-sync-test" { } ''
          ${lib.getExe pkgs.python3} ${./scripts/cloudflare-tunnel-sync.py} --self-test
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
            deepthought = self.nixosConfigurations.deepthought.config;
            firewall = config.networking.firewall;
            internal = firewall.interfaces.internal;
            management = firewall.interfaces.management;
            minecraft = config.services.minecraft-servers.servers.pwppp;
            minecraftPackFiles = lib.filesystem.listFilesRecursive ./systems/bob/minecraft/pwppp;
            minecraftRestic = config.services.restic.backups.minecraft;
            minecraftService = config.systemd.services.minecraft-server-pwppp;
            minecraftWhitelist = config.systemd.services.minecraft-whitelist-pwppp;
            mcRouter = config.systemd.services.mc-router;
            svcRouter = config.systemd.services.svc-router;
            cloudflareSync = config.systemd.services.cloudflare-tunnel-sync;
            attic = config.services.atticd;
            vyprvpn = deepthought.services.openvpn.servers.vyprvpn-miami;
            vyprvpnProfile = builtins.readFile ./systems/deepthought/openvpn/vyprvpn-miami.ovpn;
            dnsUpdate = config.systemd.services.opnsense-dns-bob;
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
              "internal"
              "management"
            ];
          assert builtins.attrNames config.networking.vlans == [ "vlan.420" ];
          assert !(config.networking.interfaces ? storage);
          assert !(config.networking.interfaces ? guest);
          assert config.networking.nameservers == [ "10.42.0.1" ];
          assert !config.systemd.network.wait-online.anyInterface;
          assert lib.elem "--interface=internal:routable" config.systemd.network.wait-online.extraArgs;
          assert !(config.systemd.services ? compose-ad);
          assert !(config.systemd.services ? compose-main);
          assert !(config.systemd.services ? compose-unifi);
          assert config.services.jackett.enable;
          assert config.services.paperless.enable;
          assert config.services.paperless.database.createLocally;
          assert !config.services.paperless.consumptionDirIsPublic;
          assert config.services.paperless.settings.PAPERLESS_URL == "https://paperless.4amlunch.net";
          assert
            config.services.paperless.settings.PAPERLESS_EMAIL_CERTIFICATE_LOCATION
            == "/var/lib/paperless/proton-bridge-ca.pem";
          assert
            config.services.paperless.settings.PAPERLESS_PROXY_SSL_HEADER == [
              "HTTP_X_FORWARDED_PROTO"
              "https"
            ];
          assert config.services.paperless.environmentFile == config.sops.secrets.paperless-environment.path;
          assert lib.hasInfix "proxy_cookie_flags ~ secure;"
            config.services.nginx.virtualHosts."paperless.4amlunch.net".extraConfig;
          assert !(config.services.nginx.virtualHosts ? "basket.4amlunch.net");
          assert !(config.services.nginx.virtualHosts ? paperless-direct);
          assert config.services.nginx.virtualHosts._default.rejectSSL;
          assert config.services.rtorrent.enable;
          assert config.services.rutorrent.enable;
          assert config.services.sonarr.enable;
          assert config.services.rtorrent.user == "rtorrent";
          assert config.services.rtorrent.group == "rtorrent";
          assert lib.elem "rtorrent" config.users.users.nginx.extraGroups;
          assert !(config.users.users ? media);
          assert !(config.users.groups ? media);
          assert config.services.avahi.allowInterfaces == [ "internal" ];
          assert config.services.postfix.rootAlias == "wonko";
          assert config.services.postfix.settings.main.inet_interfaces == [ "loopback-only" ];
          assert config.services.unifi.enable;
          assert config.services.unifi.initialJavaHeapSize == 1024;
          assert config.services.unifi.maximumJavaHeapSize == 1024;
          assert config.systemd.services ? protonmail-bridge;
          assert config.systemd.services.protonmail-bridge.serviceConfig.User == "protonmail-bridge";
          assert !(config.virtualisation.docker.enable);
          assert config.virtualisation.oci-containers.containers == { };
          assert firewall.allowedTCPPorts == [ ];
          assert firewall.allowedUDPPorts == [ ];
          assert
            builtins.attrNames firewall.interfaces == [
              "internal"
              "management"
              "tailscale0"
              "ztnfaeb6wl"
            ];
          assert
            internal.allowedTCPPorts == [
              22
              80
              443
              2049
              6789
              8443
              25565
              32400
              32469
              64738
            ];
          assert
            internal.allowedUDPPorts == [
              1900
              5353
              9993
              32410
              32411
              32412
              32413
              32414
              34934
              41641
              64738
            ];
          assert management.allowedTCPPorts == [ 8080 ];
          assert
            management.allowedUDPPorts == [
              1900
              3478
              5514
              10001
            ];
          assert lib.elem "network-online.target" dnsUpdate.after;
          assert lib.elem "sops-install-secrets.service" dnsUpdate.requires;
          assert lib.all
            (
              hostname:
              let
                update = config.systemd.services."opnsense-dns-${hostname}";
              in
              update.description == "Update OPNsense A DNS for ${hostname}.4amlunch.net"
              && lib.hasInfix "${hostname} 10.42.0.2" update.serviceConfig.ExecStart
            )
            [
              "bob"
              "jackett"
              "minecraft"
              "paperless"
              "pwppp"
              "rutorrent"
              "sonarr"
              "voice"
            ];
          assert
            config.systemd.services.opnsense-dns-pwppp-txt.description
            == "Update OPNsense TXT DNS for pwppp.4amlunch.net";
          assert lib.hasInfix "pwppp local-direct"
            config.systemd.services.opnsense-dns-pwppp-txt.serviceConfig.ExecStart;
          assert dnsUpdate.serviceConfig.RemainAfterExit;
          assert config.systemd.services ? sops-install-secrets;
          assert config.sops.age.sshKeyPaths == [ "/etc/ssh/ssh_host_ed25519_key" ];
          assert config.sops.secrets.opnsense-api-netrc.mode == "0400";
          assert config.sops.secrets.cloudflared-environment.mode == "0400";
          assert config.sops.secrets.cloudflare-acme-token.mode == "0400";
          assert lib.elem "cloudflare-tunnel-sync.service" config.systemd.services.cloudflared-tunnel.after;
          assert lib.hasPrefix "cloudflare-api-token:" cloudflareSync.serviceConfig.LoadCredential;
          assert cloudflareSync.serviceConfig.DynamicUser;
          assert cloudflareSync.serviceConfig.ProtectSystem == "strict";
          assert config.sops.secrets.murmur-environment.mode == "0400";
          assert config.sops.secrets.paperless-environment.mode == "0400";
          assert config.sops.secrets.rutorrent-htpasswd.mode == "0440";
          assert config.sops.secrets.minecraft-rcon-password.mode == "0400";
          assert config.sops.secrets.minecraft-restic-password.mode == "0440";
          assert config.sops.secrets.playit-secret.mode == "0400";
          assert config.sops.secrets.atticd-environment.mode == "0400";
          assert config.services.nginx.virtualHosts ? "cache.4amlunch.net";
          assert
            config.services.nginx.virtualHosts."cache.4amlunch.net".locations."/".proxyPass
            == "http://127.0.0.1:18081";
          assert attic.enable;
          assert attic.settings.listen == "127.0.0.1:18081";
          assert attic.settings.allowed-hosts == [ "cache.4amlunch.net" ];
          assert attic.settings.storage.path == "/nfs/NixCache";
          assert attic.settings.database.url == "sqlite:///var/lib/atticd/server.db?mode=rwc";
          assert attic.settings.garbage-collection.interval == "12 hours";
          assert attic.settings.garbage-collection.default-retention-period == "1 year";
          assert lib.last config.nix.settings.substituters == "https://cache.4amlunch.net/internal";
          assert lib.last deepthought.nix.settings.substituters == "https://cache.4amlunch.net/internal";
          assert lib.elem "internal:71s87pJDYLG9Ruu6BxjTC4wZzxneZXqc2U3da6/C2PI="
            config.nix.settings.trusted-public-keys;
          assert lib.elem "internal:71s87pJDYLG9Ruu6BxjTC4wZzxneZXqc2U3da6/C2PI="
            deepthought.nix.settings.trusted-public-keys;
          assert lib.elem "nfs-NixCache.automount" config.systemd.services.atticd.requires;
          assert config.systemd.services ? opnsense-dns-cache;
          assert lib.all (mount: mount.what != "10.42.0.30:/Brian") config.systemd.mounts;
          assert lib.any (mount: mount.what == "10.42.0.30:/NixCache") config.systemd.mounts;
          assert lib.any (mount: mount.what == "10.42.0.30:/Plex") config.systemd.mounts;
          assert lib.any (mount: mount.what == "10.42.0.30:/Torrents") config.systemd.mounts;
          assert lib.any (mount: mount.what == "10.42.0.30:/Minecraft") config.systemd.mounts;
          assert !(config.disko.devices.zpool.zpool.datasets ? docker);
          assert config.disko.devices.zpool.zpool.datasets ? "var/minecraft";
          assert config.services.minecraft-servers.enable;
          assert config.services.minecraft-servers.eula;
          assert lib.all (path: !lib.hasSuffix ".jar" (toString path)) minecraftPackFiles;
          assert !builtins.pathExists ./systems/bob/minecraft/pwppp/options.txt;
          assert !builtins.pathExists ./systems/bob/minecraft/pwppp/servers.dat;
          assert minecraft.enable;
          assert minecraft.autoStart;
          assert minecraft.serverProperties.server-ip == "127.0.0.11";
          assert minecraft.serverProperties.server-port == 25566;
          assert minecraft.serverProperties.online-mode;
          assert minecraft.serverProperties.white-list;
          assert minecraft.serverProperties.enforce-whitelist;
          assert minecraft.serverProperties.enable-rcon;
          assert minecraft.serverProperties."rcon.password" == "@RCON_PASSWORD@";
          assert lib.hasInfix "-XX:+UseG1GC" minecraft.jvmOpts;
          assert minecraftService.serviceConfig.MemoryMax == "6G";
          assert lib.hasInfix "numactl" minecraftService.environment.LD_LIBRARY_PATH;
          assert minecraftService.serviceConfig.ProtectSystem == "strict";
          assert minecraftService.restartIfChanged;
          assert !minecraftService.reloadIfChanged;
          assert lib.elem "minecraft-whitelist-pwppp.service" minecraftService.wants;
          assert minecraftWhitelist.after == [ "minecraft-server-pwppp.service" ];
          assert minecraftWhitelist.partOf == [ "minecraft-server-pwppp.service" ];
          assert minecraftWhitelist.serviceConfig.Type == "oneshot";
          assert lib.hasInfix "pwppp.4amlunch.net=127.0.0.11:25566" mcRouter.serviceConfig.ExecStart;
          assert lib.hasInfix "127.0.0.1:18080/event" mcRouter.serviceConfig.ExecStart;
          assert mcRouter.serviceConfig.DynamicUser;
          assert mcRouter.serviceConfig.IPAddressDeny == "any";
          assert lib.hasInfix "0.0.0.0:34934" svcRouter.serviceConfig.ExecStart;
          assert lib.hasInfix "127.0.0.1:18080" svcRouter.serviceConfig.ExecStart;
          assert svcRouter.serviceConfig.DynamicUser;
          assert svcRouter.serviceConfig.IPAddressDeny == "any";
          assert config.services.playit.enable;
          assert config.services.playit.secretPath == config.sops.secrets.playit-secret.path;
          assert lib.hasInfix "REPLACE_WITH_PLAYIT_SECRET"
            config.systemd.services.playit.serviceConfig.ExecCondition;
          assert config.services.nginx.virtualHosts ? "minecraft.4amlunch.net";
          assert config.services.nginx.virtualHosts."minecraft.4amlunch.net".useACMEHost == "4amlunch.net";
          assert config.services.sanoid.datasets ? "zpool/var/minecraft";
          assert config.services.sanoid.datasets."zpool/var/minecraft".autosnap;
          assert minecraftRestic.user == "minecraft-backup";
          assert minecraftRestic.repository == "/nfs/Minecraft/restic-bob";
          assert minecraftRestic.paths == [ "/var/lib/minecraft/.zfs/snapshot/restic" ];
          assert lib.elem "nfs-Minecraft.mount" config.systemd.services.restic-backups-minecraft.requires;
          assert builtins.length config.swapDevices == 1;
          assert
            (builtins.head config.swapDevices).device
            == "/dev/disk/by-partuuid/1ad95369-76dd-45cb-bf83-e84637ff25de";
          assert (builtins.head config.swapDevices).randomEncryption.enable;
          pkgs.runCommand "bob-policy-test" { } ''
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
