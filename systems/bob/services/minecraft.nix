{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:

let
  voicePort = 34934;
  routerApiPort = 18080;
  packSource = ../minecraft/pwppp;
  configRoot = packSource + "/config";

  mcRouter = pkgs.buildGoModule rec {
    pname = "mc-router";
    version = "1.44.1";
    src = pkgs.fetchFromGitHub {
      owner = "itzg";
      repo = "mc-router";
      tag = "v${version}";
      hash = "sha256-pSS/qXJwNToVcYOScIKgOO82NS9eusjlwisZyJ0cfvw=";
    };
    # v1.44.1 requires Go 1.26.5, while the pinned nixpkgs has 1.26.4.
    # This changes only the accepted patch release, not the language version.
    postPatch = ''
      substituteInPlace go.mod --replace-fail "go 1.26.5" "go 1.26.4"
    '';
    vendorHash = "sha256-XyplBsGTFQBmzqtujFERxq5/AoMMcA6G3Uhw3Tfyrsg=";
    subPackages = [ "cmd/mc-router" ];
    ldflags = [
      "-s"
      "-w"
      "-X main.version=${version}"
    ];
    meta.mainProgram = "mc-router";
  };

  svcRouter = pkgs.buildGoModule rec {
    pname = "svc-router";
    version = "0.0.2";
    src = pkgs.fetchFromGitHub {
      owner = "JLSchuler99";
      repo = "svc-router";
      tag = "v${version}";
      hash = "sha256-/qUFQPdpop4z99vHen107zDiQk0/+eKrJ1GzqCNAPtE=";
    };
    patches = [ ../minecraft/svc-router-session-cleanup.patch ];
    vendorHash = "sha256-mGKxBRU5TPgdmiSx0DHEd0Ys8gsVD/YdBfbDdSVpC3U=";
    subPackages = [ "cmd/router" ];
    postInstall = ''
      mv "$out/bin/router" "$out/bin/svc-router"
    '';
    meta.mainProgram = "svc-router";
  };

  serverPack = pkgs.fetchPackwizModpack {
    pname = "pwppp-server";
    version = "1.1.5-wonko.1";
    src = packSource;
    side = "server";
    packHash = "sha256-Ou628MU5zC2o84My8PkvFwUmaAqvmK11rdpybRlMWig=";
  };

  # CurseForge exports omit Modrinth entries. Use the matching CurseForge file
  # IDs in the client artifact while retaining reliable Modrinth downloads for
  # the native server build and Packwiz clients.
  clientOxidizedMetadata = pkgs.writeText "create-oxidized.pw.toml" ''
    name = "Create: Oxidized"
    filename = "create_oxidized-0.1.3.jar"
    side = "both"

    [download]
    hash-format = "sha1"
    hash = "fe93a9575174b4993cf3fb5f2aed4dd4431096ee"
    mode = "metadata:curseforge"

    [update]
    [update.curseforge]
    file-id = 6286593
    project-id = 953729
  '';
  clientDesignDecorMetadata = pkgs.writeText "create-design-n-decor.pw.toml" ''
    name = "Create: Design n' Decor"
    filename = "Design-n-Decor-1.21.1-2.2b.jar"
    side = "both"

    [download]
    hash-format = "sha1"
    hash = "ff5f0411a3d82e15d69b65617128f6d54e818e1b"
    mode = "metadata:curseforge"

    [update]
    [update.curseforge]
    file-id = 8156977
    project-id = 923238
  '';

  clientPack = pkgs.runCommand "pwppp-1.1.5-wonko.1.zip" { nativeBuildInputs = [ pkgs.packwiz ]; } ''
    export HOME="$TMPDIR"
    cp -r ${packSource} pack
    chmod -R u+w pack
    cd pack
    cp ${clientOxidizedMetadata} mods/create-oxidized.pw.toml
    cp ${clientDesignDecorMetadata} mods/create-design-n-decor.pw.toml
    packwiz refresh
    packwiz curseforge export --output "$out"
  '';

  siteIndex = pkgs.writeText "minecraft-index.html" ''
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>4amlunch Minecraft</title>
        <style>
          body { color: #eee; background: #181818; font: 1rem system-ui, sans-serif; margin: 2rem auto; max-width: 64rem; padding: 0 1rem; }
          table { border-collapse: collapse; width: 100%; }
          th, td { border: 1px solid #555; padding: .7rem; text-align: left; }
          a { color: #8cc8ff; }
        </style>
      </head>
      <body>
        <h1>4amlunch Minecraft servers</h1>
        <table>
          <thead><tr><th>Server</th><th>Hostname</th><th>Version</th><th>Access</th><th>Client pack</th></tr></thead>
          <tbody>
            <tr>
              <td>pwppp</td>
              <td><code>pwppp.4amlunch.net</code></td>
              <td>Minecraft 1.21.1 / NeoForge 21.1.240</td>
              <td>Whitelist</td>
              <td><a href="/packs/pwppp/pwppp-1.1.5-wonko.1.zip">Download</a></td>
            </tr>
          </tbody>
        </table>
      </body>
    </html>
  '';

  minecraftSite = pkgs.runCommand "minecraft-site" { } ''
    mkdir -p "$out/packs/pwppp/packwiz"
    cp ${siteIndex} "$out/index.html"
    cp ${clientPack} "$out/packs/pwppp/pwppp-1.1.5-wonko.1.zip"
    cp -r ${packSource}/. "$out/packs/pwppp/packwiz/"
  '';

  voiceConfig = pkgs.runCommand "pwppp-voicechat-server.properties" { } ''
    substitute ${packSource}/config/voicechat/voicechat-server.properties "$out" \
      --replace-fail 'bind_address=' 'bind_address=127.0.0.11' \
      --replace-fail 'voice_host=' 'voice_host=voice.4amlunch.net:${toString voicePort}'
  '';

  packFiles = pkgs.runCommand "pwppp-managed-files" { } ''
    mkdir "$out"
    cp -r ${packSource}/config ${packSource}/datapacks "$out/"
  '';

  relativeTo = root: path: lib.removePrefix "${toString root}/" (toString path);
  managedConfigs = builtins.listToAttrs (
    map (path: {
      name = "config/${relativeTo configRoot path}";
      value = "${packFiles}/config/${relativeTo configRoot path}";
    }) (lib.filesystem.listFilesRecursive configRoot)
  );
  datapacks = builtins.listToAttrs (
    map (path: {
      name = "world/datapacks/${baseNameOf path}";
      value = "${packFiles}/datapacks/${baseNameOf path}";
    }) (lib.filesystem.listFilesRecursive (packSource + "/datapacks"))
  );
  serverFiles =
    removeAttrs managedConfigs [ "config/voicechat/voicechat-server.properties" ]
    // datapacks
    // {
      "config/voicechat/voicechat-server.properties" = voiceConfig;
    };

  routerHardening = {
    CapabilityBoundingSet = "";
    DeviceAllow = "";
    DynamicUser = true;
    IPAddressAllow = [
      "localhost"
      "10.42.0.0/24"
    ];
    IPAddressDeny = "any";
    LockPersonality = true;
    NoNewPrivileges = true;
    PrivateDevices = true;
    PrivateTmp = true;
    PrivateUsers = true;
    ProtectClock = true;
    ProtectControlGroups = true;
    ProtectHome = true;
    ProtectHostname = true;
    ProtectKernelLogs = true;
    ProtectKernelModules = true;
    ProtectKernelTunables = true;
    ProtectSystem = "strict";
    RestrictAddressFamilies = [
      "AF_INET"
      "AF_INET6"
      "AF_UNIX"
    ];
    RestrictNamespaces = true;
    RestrictRealtime = true;
    RestrictSUIDSGID = true;
  };

  rcon = "${lib.getExe pkgs.mcrcon} -H 127.0.0.11 -P 25575 -p \"$RCON_PASSWORD\"";
  saveOff = pkgs.writeShellApplication {
    name = "minecraft-save-off";
    excludeShellChecks = [ "SC1091" ];
    text = ''
      source ${config.sops.templates.minecraft-environment.path}
      ${rcon} "save-off" "save-all flush"
    '';
  };
  saveOn = pkgs.writeShellApplication {
    name = "minecraft-save-on";
    excludeShellChecks = [ "SC1091" ];
    text = ''
      source ${config.sops.templates.minecraft-environment.path}
      ${rcon} "save-on"
    '';
  };
  prepareBackup = pkgs.writeShellApplication {
    name = "minecraft-prepare-backup";
    runtimeInputs = [ pkgs.zfs ];
    text = ''
      zfs destroy zpool/var/minecraft@restic 2>/dev/null || true
      ${lib.getExe saveOff}
      trap '${lib.getExe saveOn}' EXIT
      zfs snapshot zpool/var/minecraft@restic
    '';
  };
  cleanupBackup = pkgs.writeShellApplication {
    name = "minecraft-cleanup-backup";
    runtimeInputs = [ pkgs.zfs ];
    text = ''
      zfs destroy zpool/var/minecraft@restic 2>/dev/null || true
    '';
  };
in
{
  imports = [
    inputs.nix-minecraft.nixosModules.minecraft-servers
    inputs.playit-nixos-module.nixosModules.default
  ];

  nixpkgs.overlays = [ inputs.nix-minecraft.overlay ];

  sops = {
    secrets = {
      minecraft-rcon-password = {
        sopsFile = ../secrets/minecraft.sops;
        format = "yaml";
        key = "rcon-password";
      };
      minecraft-restic-password = {
        sopsFile = ../secrets/minecraft.sops;
        format = "yaml";
        key = "restic-password";
        owner = "minecraft-backup";
        group = "minecraft-backup";
        mode = "0440";
      };
      playit-secret = {
        sopsFile = ../secrets/playit.toml.sops;
        format = "binary";
        mode = "0400";
      };
    };
    templates.minecraft-environment = {
      content = ''
        RCON_PASSWORD=${config.sops.placeholder.minecraft-rcon-password}
      '';
      owner = "root";
      group = "minecraft";
      mode = "0440";
      restartUnits = [ "minecraft-server-pwppp.service" ];
    };
  };

  services = {
    minecraft-servers = {
      enable = true;
      eula = true;
      dataDir = "/var/lib/minecraft";
      openFirewall = false;
      environmentFile = config.sops.templates.minecraft-environment.path;
      managementSystem = {
        tmux.enable = false;
        systemd-socket.enable = true;
      };
      servers.pwppp = {
        enable = true;
        autoStart = true;
        restart = "on-failure";
        package = pkgs.minecraftServers."neoforge-1_21_1-21_1_240";
        jvmOpts = "-Xms1G -Xmx4G";
        symlinks.mods = "${serverPack}/mods";
        files = serverFiles;
        serverProperties = {
          server-ip = "127.0.0.11";
          server-port = 25566;
          motd = "pwppp";
          max-players = 20;
          online-mode = true;
          white-list = true;
          enforce-whitelist = true;
          enable-rcon = true;
          broadcast-rcon-to-ops = false;
          "rcon.port" = 25575;
          "rcon.password" = "@RCON_PASSWORD@";
        };
      };
    };

    nginx.virtualHosts."minecraft.4amlunch.net" = {
      root = minecraftSite;
      onlySSL = true;
      useACMEHost = "4amlunch.net";
      extraConfig = ''
        add_header Strict-Transport-Security "max-age=31536000" always;
        add_header Content-Security-Policy "default-src 'none'; style-src 'unsafe-inline'" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header X-Frame-Options "DENY" always;
      '';
      locations."/".extraConfig = ''
        limit_except GET HEAD { deny all; }
      '';
    };

    playit = {
      enable = true;
      secretPath = config.sops.secrets.playit-secret.path;
    };

    sanoid = {
      enable = true;
      datasets."zpool/var/minecraft" = {
        autosnap = true;
        autoprune = true;
        hourly = 24;
        daily = 14;
        monthly = 3;
        yearly = 0;
        pre_snapshot_script = lib.getExe saveOff;
        post_snapshot_script = lib.getExe saveOn;
        force_post_snapshot_script = true;
        script_timeout = 60;
      };
    };

    restic.backups.minecraft = {
      user = "minecraft-backup";
      repository = "/nfs/Minecraft/restic-bob";
      passwordFile = config.sops.secrets.minecraft-restic-password.path;
      initialize = true;
      paths = [ "/var/lib/minecraft/.zfs/snapshot/restic" ];
      backupPrepareCommand = lib.getExe prepareBackup;
      backupCleanupCommand = lib.getExe cleanupBackup;
      pruneOpts = [
        "--keep-daily 7"
        "--keep-weekly 4"
        "--keep-monthly 6"
      ];
      timerConfig = {
        OnCalendar = "*-*-* 04:30:00";
        Persistent = true;
        RandomizedDelaySec = "15m";
      };
    };
  };

  users = {
    users = {
      wonko.extraGroups = [ "minecraft" ];
      minecraft-backup = {
        isSystemUser = true;
        group = "minecraft-backup";
        extraGroups = [ "minecraft" ];
      };
    };
    groups.minecraft-backup = { };
  };

  networking.firewall.interfaces.internal = {
    allowedTCPPorts = [ 25565 ];
    allowedUDPPorts = [ voicePort ];
  };

  systemd = {
    mounts = [
      {
        what = "10.42.0.30:/Minecraft";
        where = "/nfs/Minecraft";
        type = "nfs4";
        mountConfig.Options = "noatime,nodev,nosuid,noexec";
      }
    ];
    automounts = [
      {
        where = "/nfs/Minecraft";
        wantedBy = [ "multi-user.target" ];
        automountConfig.TimeoutIdleSec = "600";
      }
    ];

    services = {
      mc-router = {
        description = "Minecraft hostname router";
        after = [ "network.target" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = routerHardening // {
          ExecStart = "${lib.getExe mcRouter} -port 25565 -mapping pwppp.4amlunch.net=127.0.0.11:25566 -connection-rate-limit 10 -webhook-url http://127.0.0.1:${toString routerApiPort}/event";
          Restart = "on-failure";
          RestartSec = "5s";
        };
      };

      svc-router = {
        description = "Simple Voice Chat router";
        after = [ "network.target" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = routerHardening // {
          ExecStart = "${lib.getExe svcRouter} -svc-binding 0.0.0.0:${toString voicePort} -api-binding 127.0.0.1:${toString routerApiPort}";
          Restart = "on-failure";
          RestartSec = "5s";
        };
      };

      playit.serviceConfig.ExecCondition = "${lib.getExe' pkgs.gnugrep "grep"} -qv REPLACE_WITH_PLAYIT_SECRET %d/secret";

      minecraft-server-pwppp.serviceConfig = {
        MemoryHigh = "5G";
        MemoryMax = "6G";
        NoNewPrivileges = true;
        OOMPolicy = "stop";
        ProtectSystem = "strict";
        ReadWritePaths = [ "/var/lib/minecraft/pwppp" ];
      };

      minecraft-zfs-delegation = {
        description = "Delegate Minecraft backup snapshots";
        after = [ "zfs-mount.service" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${lib.getExe' pkgs.zfs "zfs"} allow minecraft-backup snapshot,destroy zpool/var/minecraft";
        };
      };

      restic-backups-minecraft = {
        after = [
          "minecraft-server-pwppp.service"
          "minecraft-zfs-delegation.service"
          "nfs-Minecraft.mount"
        ];
        requires = [
          "minecraft-zfs-delegation.service"
          "nfs-Minecraft.mount"
        ];
      };

      sanoid = {
        after = [
          "minecraft-server-pwppp.service"
          "sops-install-secrets.service"
        ];
        requires = [ "sops-install-secrets.service" ];
      };
    };
  };
}
