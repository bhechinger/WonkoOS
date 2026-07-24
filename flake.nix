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
            bobDatasets = config.disko.devices.zpool.zpool.datasets;
            deepthought = self.nixosConfigurations.deepthought.config;
            firewall = config.networking.firewall;
            internal = firewall.interfaces.internal;
            management = firewall.interfaces.management;
            minecraft = config.services.minecraft-servers.servers.pwppp;
            minecraftPackFiles = lib.filesystem.listFilesRecursive ./systems/bob/minecraft/pwppp;
            gigglesomething = config.services.minecraft-servers.servers.gigglesomething;
            gigglesomethingPackFiles = lib.filesystem.listFilesRecursive ./systems/bob/minecraft/gigglesomething;
            minecraftRestic = config.services.restic.backups.minecraft;
            bobServicesRestic = config.services.restic.backups.bob-services;
            deepthoughtRestic = deepthought.services.restic.backups.deepthought;
            resticGateway = config.systemd.services.restic-gateway;
            resticB2Gateway = config.systemd.services.restic-b2-gateway;
            resticCopyBob = config.systemd.services.restic-copy-bob;
            resticCopyDeepthought = config.systemd.services.restic-copy-deepthought;
            resticMaintenance = config.systemd.services.restic-maintenance;
            minecraftSanoid = config.services.sanoid.datasets."zpool/var/minecraft";
            minecraftSanoidService = config.systemd.services.sanoid;
            minecraftService = config.systemd.services.minecraft-server-pwppp;
            minecraftWhitelist = config.systemd.services.minecraft-whitelist-pwppp;
            gigglesomethingService = config.systemd.services.minecraft-server-gigglesomething;
            gigglesomethingWhitelist = config.systemd.services.minecraft-whitelist-gigglesomething;
            mcRouter = config.systemd.services.mc-router;
            svcRouter = config.systemd.services.svc-router;
            cloudflareSync = config.systemd.services.cloudflare-tunnel-sync;
            cloudflareSyncTimer = config.systemd.timers.cloudflare-tunnel-sync;
            attic = config.services.atticd;
            bind = config.services.bind;
            grafana = config.services.grafana;
            mimir = config.services.mimir.configuration;
            loki = config.services.loki.configuration;
            tempo = config.services.tempo.settings;
            bobNode = config.services.prometheus.exporters.node;
            deepthoughtNode = deepthought.services.prometheus.exporters.node;
            deepthoughtNvidia = deepthought.services.prometheus.exporters.nvidia-gpu;
            bobAlloy = config.environment.etc."alloy/config.alloy".text;
            deepthoughtAlloy = deepthought.environment.etc."alloy/config.alloy".text;
            vyprvpn = deepthought.services.openvpn.servers.vyprvpn-miami;
            vyprvpnProfile = builtins.readFile ./systems/deepthought/openvpn/vyprvpn-miami.ovpn;
            dnsUpdate = config.systemd.services.opnsense-dns-sync;
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
          assert
            config.networking.nameservers == [
              "10.42.0.1"
              "10.42.0.2"
            ];
          assert
            deepthought.networking.nameservers == [
              "10.42.0.1"
              "10.42.0.2"
            ];
          assert bind.enable;
          assert bind.ipv4Only;
          assert bind.directory == "/var/lib/named";
          assert bind.forwarders == [ ];
          assert
            bind.listenOn == [
              "127.0.0.1"
              "10.42.0.2"
              "10.42.11.2"
            ];
          assert
            builtins.attrNames bind.zones == [
              "0.42.10.in-addr.arpa"
              "11.42.10.in-addr.arpa"
              "4amlunch.net"
              "lan.4amlunch.net"
            ];
          assert lib.all (zone: !zone.master && zone.masters == [ "10.42.0.251" ]) (
            builtins.attrValues bind.zones
          );
          assert !config.systemd.network.wait-online.anyInterface;
          assert lib.elem "--interface=internal:routable" config.systemd.network.wait-online.extraArgs;
          assert !(config.systemd.services ? compose-ad);
          assert !(config.systemd.services ? compose-main);
          assert !(config.systemd.services ? compose-unifi);
          assert config.services.jackett.enable;
          assert config.services.jackett.dataDir == "/var/lib/jackett";
          assert config.services.paperless.enable;
          assert config.services.paperless.dataDir == "/var/lib/paperless/data";
          assert config.services.paperless.mediaDir == "/var/lib/paperless/media";
          assert config.services.paperless.consumptionDir == "/var/lib/paperless/consume";
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
          assert config.services.postgresql.dataDir == "/var/lib/postgresql/paperless";
          assert lib.hasInfix "/var/lib/paperless/consume " config.services.nfs.server.exports;
          assert lib.hasInfix "/var/lib/paperless/export " config.services.nfs.server.exports;
          assert config.services.nginx.virtualHosts."bob.4amlunch.net".root == "/var/www";
          assert config.services.nginx.virtualHosts."hamburgerking.pt".root == "/var/www/hbk";
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
              53
              80
              443
              2049
              3100
              4317
              4318
              6789
              8443
              25565
              32400
              32469
              64738
            ];
          assert
            internal.allowedUDPPorts == [
              53
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
          assert
            management.allowedTCPPorts == [
              53
              8080
            ];
          assert
            management.allowedUDPPorts == [
              53
              1900
              3478
              5514
              10001
            ];
          assert lib.elem "network-online.target" dnsUpdate.after;
          assert lib.elem "bind.service" dnsUpdate.after;
          assert lib.elem "sops-install-secrets.service" dnsUpdate.requires;
          assert dnsUpdate.description == "Reconcile the internal 4amlunch.net BIND zone";
          assert lib.hasInfix "opnsense-bind-records.json" dnsUpdate.serviceConfig.ExecStart;
          assert
            lib.filter (name: lib.hasPrefix "opnsense-dns-" name) (builtins.attrNames config.systemd.services)
            == [ "opnsense-dns-sync" ];
          assert dnsUpdate.serviceConfig.RemainAfterExit;
          assert config.systemd.services ? sops-install-secrets;
          assert config.sops.age.sshKeyPaths == [ "/etc/ssh/ssh_host_ed25519_key" ];
          assert config.sops.secrets.opnsense-api-netrc.mode == "0400";
          assert config.sops.secrets.cloudflared-environment.mode == "0400";
          assert config.sops.secrets.cloudflare-acme-token.mode == "0400";
          assert config.sops.secrets.cloudflare-spectrum-token.mode == "0400";
          assert lib.elem "cloudflare-tunnel-sync.service" config.systemd.services.cloudflared-tunnel.after;
          assert lib.any (lib.hasPrefix "cloudflare-api-token:") cloudflareSync.serviceConfig.LoadCredential;
          assert lib.any (lib.hasPrefix "cloudflare-spectrum-token:")
            cloudflareSync.serviceConfig.LoadCredential;
          assert cloudflareSyncTimer.timerConfig.OnBootSec == "5min";
          assert cloudflareSyncTimer.timerConfig.OnUnitActiveSec == "5min";
          assert cloudflareSync.serviceConfig.DynamicUser;
          assert cloudflareSync.serviceConfig.ProtectSystem == "strict";
          assert config.sops.secrets.murmur-environment.mode == "0400";
          assert config.sops.secrets.paperless-environment.mode == "0400";
          assert config.sops.secrets.rutorrent-htpasswd.mode == "0440";
          assert config.sops.secrets.minecraft-rcon-password.mode == "0400";
          assert config.sops.secrets.minecraft-restic-password.mode == "0400";
          assert config.sops.secrets.restic-b2-application-key-id.mode == "0400";
          assert config.sops.secrets.restic-b2-application-key.mode == "0400";
          assert config.sops.secrets.bob-restic-http-password.mode == "0400";
          assert config.sops.secrets.bob-restic-http-password-hash.mode == "0400";
          assert config.sops.secrets.deepthought-restic-http-password-hash.mode == "0400";
          assert config.sops.secrets.deepthought-restic-repository-password.mode == "0400";
          assert deepthought.sops.secrets.restic-http-password.mode == "0400";
          assert deepthought.sops.secrets.restic-repository-password.mode == "0400";
          assert config.sops.secrets.playit-secret.mode == "0400";
          assert config.sops.secrets.atticd-environment.mode == "0400";
          assert config.sops.secrets.grafana-admin-password.mode == "0400";
          assert config.sops.secrets.grafana-secret-key.mode == "0400";
          assert grafana.enable;
          assert grafana.settings.server.http_addr == "127.0.0.1";
          assert grafana.settings.server.domain == "grafana.4amlunch.net";
          assert grafana.settings.security.cookie_secure;
          assert !grafana.settings."auth.anonymous".enabled;
          assert config.services.mimir.enable;
          assert mimir.server.http_listen_address == "127.0.0.1";
          assert mimir.server.http_listen_port == 9009;
          assert mimir.frontend.address == "127.0.0.1";
          assert mimir.query_scheduler.ring.instance_addr == "127.0.0.1";
          assert mimir.store_gateway.sharding_ring.instance_addr == "127.0.0.1";
          assert mimir.limits.compactor_blocks_retention_period == "30d";
          assert config.services.loki.enable;
          assert loki.server.http_listen_address == "10.42.0.2";
          assert loki.server.http_listen_port == 3100;
          assert loki.limits_config.retention_period == "720h";
          assert config.services.tempo.enable;
          assert tempo.server.http_listen_address == "127.0.0.1";
          assert tempo.server.http_listen_port == 3200;
          assert tempo.compactor.compaction.block_retention == "720h";
          assert config.services.alloy.enable;
          assert deepthought.services.alloy.enable;
          assert config.systemd.services ? alloy-log-access;
          assert lib.elem "alloy-log-access.service" config.systemd.services.alloy.after;
          assert bobNode.enable;
          assert bobNode.listenAddress == "127.0.0.1";
          assert lib.elem "systemd" bobNode.enabledCollectors;
          assert deepthoughtNode.enable;
          assert deepthoughtNode.listenAddress == "10.42.0.10";
          assert lib.elem 9100 deepthought.networking.firewall.interfaces.internal.allowedTCPPorts;
          assert deepthoughtNvidia.enable;
          assert deepthoughtNvidia.listenAddress == "10.42.0.10";
          assert deepthoughtNvidia.port == 9835;
          assert lib.elem 9835 deepthought.networking.firewall.interfaces.internal.allowedTCPPorts;
          assert lib.all (port: lib.elem port internal.allowedTCPPorts) [
            3100
            4317
            4318
          ];
          assert lib.all (target: lib.hasInfix target bobAlloy) [
            "127.0.0.1:9100"
            "10.42.0.10:9100"
            "10.42.0.251:9100"
            "127.0.0.11:19565"
            "127.0.0.12:19565"
            "10.42.0.10:9835"
          ];
          assert lib.hasInfix "10.42.0.2:3100/loki/api/v1/push" deepthoughtAlloy;
          assert config.services.nginx.virtualHosts ? "grafana.4amlunch.net";
          assert
            config.services.nginx.virtualHosts."grafana.4amlunch.net".locations."/".proxyPass
            == "http://127.0.0.1:3000";
          assert config.services.nginx.virtualHosts ? "cache.4amlunch.net";
          assert
            config.services.nginx.virtualHosts."cache.4amlunch.net".locations."/".proxyPass
            == "http://127.0.0.1:18081";
          assert config.services.nginx.virtualHosts ? "restic.4amlunch.net";
          assert
            config.services.nginx.virtualHosts."restic.4amlunch.net".locations."/".proxyPass
            == "http://127.0.0.1:18082";
          assert resticGateway.serviceConfig.DynamicUser;
          assert resticGateway.serviceConfig.ProtectSystem == "strict";
          assert resticGateway.serviceConfig.UMask == "0077";
          assert lib.hasInfix "--append-only" resticGateway.serviceConfig.ExecStart;
          assert lib.hasInfix "--private-repos" resticGateway.serviceConfig.ExecStart;
          assert lib.hasInfix "/nfs/Restic" resticGateway.serviceConfig.ExecStart;
          assert config.services.nginx.virtualHosts ? "restic-b2.4amlunch.net";
          assert
            config.services.nginx.virtualHosts."restic-b2.4amlunch.net".locations."/".proxyPass
            == "http://127.0.0.1:18083";
          assert resticB2Gateway.serviceConfig.DynamicUser;
          assert lib.hasInfix "--append-only" resticB2Gateway.serviceConfig.ExecStart;
          assert lib.hasInfix "b2:4amlunch-restic/restic" resticB2Gateway.serviceConfig.ExecStart;
          assert resticMaintenance.serviceConfig.DynamicUser;
          assert lib.elem "/nfs/Restic/bob" resticCopyBob.serviceConfig.ReadWritePaths;
          assert lib.elem "/nfs/Restic/deepthought" resticCopyDeepthought.serviceConfig.ReadWritePaths;
          assert config.systemd.timers.restic-maintenance.timerConfig.OnCalendar == "Sun *-*-* 12:00:00";
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
          assert config.systemd.services ? opnsense-dns-sync;
          assert lib.all (mount: mount.what != "10.42.0.30:/Brian") config.systemd.mounts;
          assert lib.any (mount: mount.what == "10.42.0.30:/NixCache") config.systemd.mounts;
          assert lib.any (mount: mount.what == "10.42.0.30:/Plex") config.systemd.mounts;
          assert lib.any (mount: mount.what == "10.42.0.30:/Torrents") config.systemd.mounts;
          assert lib.any (mount: mount.what == "10.42.0.30:/Restic") config.systemd.mounts;
          assert !(bobDatasets ? docker);
          assert bobDatasets.jackett.mountpoint == "/var/lib/jackett";
          assert bobDatasets.paperless.mountpoint == "/var/lib/paperless";
          assert bobDatasets.postgres.mountpoint == "/var/lib/postgresql";
          assert bobDatasets.redis.mountpoint == "/var/lib/redis-paperless";
          assert bobDatasets.www.mountpoint == "/var/www";
          assert bobDatasets ? "var/minecraft";
          assert bobDatasets."var/minecraft/pwppp".mountpoint == "/var/lib/minecraft/pwppp";
          assert
            bobDatasets."var/minecraft/gigglesomething".mountpoint == "/var/lib/minecraft/gigglesomething";
          assert config.services.minecraft-servers.enable;
          assert config.services.minecraft-servers.eula;
          assert lib.all (path: !lib.hasSuffix ".jar" (toString path)) minecraftPackFiles;
          assert lib.all (path: !lib.hasSuffix ".jar" (toString path)) gigglesomethingPackFiles;
          assert !builtins.pathExists ./systems/bob/minecraft/pwppp/mods/modflared.pw.toml;
          assert !builtins.pathExists ./systems/bob/minecraft/pwppp/options.txt;
          assert !builtins.pathExists ./systems/bob/minecraft/pwppp/servers.dat;
          assert !builtins.pathExists ./systems/bob/minecraft/gigglesomething/logs;
          assert !builtins.pathExists ./systems/bob/minecraft/gigglesomething/options.txt;
          assert !builtins.pathExists ./systems/bob/minecraft/gigglesomething/servers.dat;
          assert minecraft.enable;
          assert minecraft.autoStart;
          assert minecraft.serverProperties.server-ip == "127.0.0.11";
          assert minecraft.serverProperties.server-port == 25566;
          assert minecraft.serverProperties.motd == "A NEOFORGE server on 1.21.1\\nrunning pwppp 1.1.8";
          assert minecraft.serverProperties.online-mode;
          assert minecraft.serverProperties.white-list;
          assert minecraft.serverProperties.enforce-whitelist;
          assert minecraft.serverProperties.enable-rcon;
          assert minecraft.serverProperties."rcon.password" == "@RCON_PASSWORD@";
          assert builtins.hasAttr "config/prometheus_exporter-server.toml" minecraft.files;
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
          assert gigglesomething.enable;
          assert gigglesomething.autoStart;
          assert gigglesomething.serverProperties.server-ip == "127.0.0.12";
          assert gigglesomething.serverProperties.server-port == 25567;
          assert
            gigglesomething.serverProperties.motd == "A FORGE server on 1.20.1\\nrunning gigglesomething 1.0.1";
          assert gigglesomething.serverProperties.online-mode;
          assert gigglesomething.serverProperties.white-list;
          assert gigglesomething.serverProperties.enforce-whitelist;
          assert gigglesomething.serverProperties.enable-rcon;
          assert gigglesomething.serverProperties."rcon.port" == 25576;
          assert gigglesomething.serverProperties."rcon.password" == "@RCON_PASSWORD@";
          assert builtins.hasAttr "world/serverconfig/prometheus_exporter-server.toml" gigglesomething.files;
          assert lib.hasInfix "-XX:+UseG1GC" gigglesomething.jvmOpts;
          assert gigglesomethingService.serviceConfig.MemoryMax == "6G";
          assert gigglesomethingService.serviceConfig.ProtectSystem == "strict";
          assert gigglesomethingService.restartIfChanged;
          assert !gigglesomethingService.reloadIfChanged;
          assert lib.elem "minecraft-whitelist-gigglesomething.service" gigglesomethingService.wants;
          assert
            gigglesomethingWhitelist.after == [
              "minecraft-server-gigglesomething.service"
            ];
          assert
            gigglesomethingWhitelist.partOf == [
              "minecraft-server-gigglesomething.service"
            ];
          assert gigglesomethingWhitelist.serviceConfig.Type == "oneshot";
          assert lib.hasInfix "pwppp.4amlunch.net=127.0.0.11:25566" mcRouter.serviceConfig.ExecStart;
          assert lib.hasInfix "gigglesomething.4amlunch.net=127.0.0.12:25567"
            mcRouter.serviceConfig.ExecStart;
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
          assert minecraftSanoid.recursive == "zfs";
          assert lib.elem "minecraft" minecraftSanoidService.serviceConfig.SupplementaryGroups;
          assert minecraftRestic.user == "root";
          assert minecraftRestic.repository == "rest:https://restic.4amlunch.net/bob/";
          assert minecraftRestic.environmentFile == config.sops.templates.bob-restic-environment.path;
          assert lib.all
            (
              backup:
              backup.extraBackupArgs == [
                "--option"
                "rest.connections=20"
                "--retry-lock"
                "2h"
              ]
            )
            [
              minecraftRestic
              bobServicesRestic
              deepthoughtRestic
            ];
          assert minecraftRestic.timerConfig.OnCalendar == "*-*-* 00,04,08,12,16,20:40:00";
          assert minecraftRestic.pruneOpts == [ ];
          assert
            minecraftRestic.paths == [
              "/var/lib/minecraft/pwppp/.zfs/snapshot/restic"
              "/var/lib/minecraft/gigglesomething/.zfs/snapshot/restic"
            ];
          assert bobServicesRestic.repository == "rest:https://restic.4amlunch.net/bob/";
          assert bobServicesRestic.passwordFile == config.sops.secrets.minecraft-restic-password.path;
          assert bobServicesRestic.environmentFile == config.sops.templates.bob-restic-environment.path;
          assert bobServicesRestic.timerConfig.OnCalendar == "*-*-* *:00:00";
          assert bobServicesRestic.pruneOpts == [ ];
          assert
            bobServicesRestic.paths == [
              "/var/.zfs/snapshot/restic-services"
              "/var/lib/jackett/.zfs/snapshot/restic-services"
              "/var/lib/paperless/.zfs/snapshot/restic-services"
              "/var/lib/plexmediaserver/.zfs/snapshot/restic-services"
              "/var/lib/postgresql/.zfs/snapshot/restic-services"
              "/var/lib/redis-paperless/.zfs/snapshot/restic-services"
              "/var/www/.zfs/snapshot/restic-services"
            ];
          assert lib.elem "restic-gateway.service" config.systemd.services.restic-backups-minecraft.requires;
          assert !lib.elem "nfs-Restic.mount" config.systemd.services.restic-backups-minecraft.requires;
          assert deepthoughtRestic.repository == "rest:https://restic.4amlunch.net/deepthought/";
          assert deepthoughtRestic.environmentFile == deepthought.sops.templates.restic-environment.path;
          assert deepthoughtRestic.timerConfig.OnCalendar == "*-*-* *:20:00";
          assert deepthoughtRestic.pruneOpts == [ ];
          assert !builtins.hasAttr "restic-copy-deepthought" deepthought.systemd.services;
          assert
            deepthoughtRestic.paths == [
              "/home/.zfs/snapshot/restic-deepthought/wonko"
              "/run/restic-deepthought/postgresql.sql"
            ];
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
