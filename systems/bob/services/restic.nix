{
  config,
  lib,
  pkgs,
  ...
}:

let
  repository = "rest:https://restic.4amlunch.net/bob/";
  b2Repository = "rest:https://restic-b2.4amlunch.net/bob/";
  nfsRoot = "/nfs/Minecraft/restic";
  bobNfsRepository = "${nfsRoot}/bob";
  deepthoughtNfsRepository = "${nfsRoot}/deepthought";
  datasets = [
    "zpool/var"
    "zpool/jackett"
    "zpool/paperless"
    "zpool/plex"
    "zpool/postgres"
    "zpool/redis"
    "zpool/www"
  ];
  snapshots = [
    "/var/.zfs/snapshot/restic-services"
    "/var/lib/jackett/.zfs/snapshot/restic-services"
    "/var/lib/paperless/.zfs/snapshot/restic-services"
    "/var/lib/plexmediaserver/.zfs/snapshot/restic-services"
    "/var/lib/postgresql/.zfs/snapshot/restic-services"
    "/var/lib/redis-paperless/.zfs/snapshot/restic-services"
    "/var/www/.zfs/snapshot/restic-services"
  ];
  hardening = {
    DynamicUser = true;
    LockPersonality = true;
    NoNewPrivileges = true;
    PrivateDevices = true;
    PrivateTmp = true;
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
  rootHardening = builtins.removeAttrs hardening [ "DynamicUser" ];
  cleanup = pkgs.writeShellApplication {
    name = "bob-restic-cleanup";
    runtimeInputs = [ pkgs.zfs ];
    text = ''
      for dataset in ${lib.concatStringsSep " " datasets}; do
        zfs destroy "$dataset@restic-services" 2>/dev/null || true
      done
    '';
  };
  prepare = pkgs.writeShellApplication {
    name = "bob-restic-prepare";
    runtimeInputs = [ pkgs.zfs ];
    text = ''
      ${lib.getExe cleanup}
      trap '${lib.getExe cleanup}' ERR
      zfs snapshot ${lib.concatMapStringsSep " " (dataset: "${dataset}@restic-services") datasets}
      trap - ERR
    '';
  };
  maintenance = pkgs.writeShellApplication {
    name = "restic-b2-maintenance";
    runtimeInputs = [
      pkgs.rclone
      pkgs.restic
    ];
    text = ''
      credential_directory="$1"

      maintain() {
        repository="rclone:b2:4amlunch-restic/restic/$1"
        password_file="$2"
        restic --repo "$repository" --password-file "$password_file" unlock
        restic --repo "$repository" --password-file "$password_file" forget --prune --keep-within 6m
        restic --repo "$repository" --password-file "$password_file" check
      }

      export RCLONE_CONFIG="$credential_directory/rclone.conf"
      maintain bob "$credential_directory/bob-password"
      maintain deepthought "$credential_directory/deepthought-password"
    '';
  };
  nfsMaintenance = pkgs.writeShellApplication {
    name = "restic-nfs-maintenance";
    runtimeInputs = [ pkgs.restic ];
    text = ''
      credential_directory="$1"

      maintain() {
        repository="${nfsRoot}/$1"
        password_file="$2"
        restic --repo "$repository" --password-file "$password_file" unlock
        restic --repo "$repository" --password-file "$password_file" forget --prune --keep-within 6m
        restic --repo "$repository" --password-file "$password_file" check
      }

      maintain bob "$credential_directory/bob-password"
      maintain deepthought "$credential_directory/deepthought-password"
    '';
  };
  mirror = pkgs.writeShellApplication {
    name = "restic-mirror";
    runtimeInputs = [
      pkgs.jq
      pkgs.rclone
      pkgs.restic
    ];
    text = ''
      rclone_config="$1"
      repository_password_file="$2"
      source_repository="$3"
      destination_repository="$4"

      export RCLONE_CONFIG="$rclone_config"

      destination() {
        restic \
          --repo "$destination_repository" \
          --password-file "$repository_password_file" \
          --option rclone.connections=20 \
          --retry-lock 5m \
          "$@"
      }

      if ! destination cat config >/dev/null 2>&1; then
        destination init \
          --copy-chunker-params \
          --from-repo "$source_repository" \
          --from-password-file "$repository_password_file"
      fi

      source_chunker="$(
        restic \
          --repo "$source_repository" \
          --password-file "$repository_password_file" \
          cat config |
          jq -r .chunker_polynomial
      )"
      destination_chunker="$(destination cat config | jq -r .chunker_polynomial)"
      if [[ "$source_chunker" != "$destination_chunker" ]]; then
        echo "source and destination Restic chunker parameters differ" >&2
        exit 1
      fi

      destination copy \
        --from-repo "$source_repository" \
        --from-password-file "$repository_password_file"
    '';
  };
  b2Client = pkgs.writeShellApplication {
    name = "restic-bob-b2";
    runtimeInputs = [ pkgs.restic ];
    text = ''
      RESTIC_REST_USERNAME=bob
      RESTIC_REST_PASSWORD="$(<${config.sops.secrets.bob-restic-http-password.path})"
      export RESTIC_REST_USERNAME RESTIC_REST_PASSWORD
      exec restic \
        --repo ${lib.escapeShellArg b2Repository} \
        --password-file ${config.sops.secrets.minecraft-restic-password.path} \
        "$@"
    '';
  };
in
{
  environment.systemPackages = [ b2Client ];

  sops = {
    secrets = {
      restic-b2-application-key-id = {
        sopsFile = ../secrets/restic.sops;
        format = "yaml";
        key = "b2-application-key-id";
        mode = "0400";
      };
      restic-b2-application-key = {
        sopsFile = ../secrets/restic.sops;
        format = "yaml";
        key = "b2-application-key";
        mode = "0400";
      };
      bob-restic-http-password = {
        sopsFile = ../secrets/restic.sops;
        format = "yaml";
        key = "bob-http-password";
        mode = "0400";
      };
      bob-restic-http-password-hash = {
        sopsFile = ../secrets/restic.sops;
        format = "yaml";
        key = "bob-http-password-hash";
        mode = "0400";
      };
      deepthought-restic-http-password-hash = {
        sopsFile = ../secrets/restic.sops;
        format = "yaml";
        key = "deepthought-http-password-hash";
        mode = "0400";
      };
      deepthought-restic-repository-password = {
        sopsFile = ../secrets/restic.sops;
        format = "yaml";
        key = "deepthought-repository-password";
        mode = "0400";
      };
    };
    templates = {
      restic-rclone = {
        content = ''
          [b2]
          type = b2
          account = ${config.sops.placeholder.restic-b2-application-key-id}
          key = ${config.sops.placeholder.restic-b2-application-key}
        '';
        mode = "0400";
        restartUnits = [ "restic-b2-gateway.service" ];
      };
      restic-htpasswd = {
        content = ''
          bob:${config.sops.placeholder.bob-restic-http-password-hash}
          deepthought:${config.sops.placeholder.deepthought-restic-http-password-hash}
        '';
        mode = "0400";
        restartUnits = [
          "restic-b2-gateway.service"
          "restic-gateway.service"
        ];
      };
      bob-restic-environment = {
        content = ''
          RESTIC_REST_USERNAME=bob
          RESTIC_REST_PASSWORD=${config.sops.placeholder.bob-restic-http-password}
        '';
        mode = "0400";
      };
    };
  };

  services = {
    nginx.virtualHosts."restic.4amlunch.net" = {
      onlySSL = true;
      useACMEHost = "4amlunch.net";
      extraConfig = ''
        add_header Strict-Transport-Security "max-age=31536000" always;
      '';
      locations."/" = {
        proxyPass = "http://127.0.0.1:18082";
        extraConfig = ''
          client_max_body_size 0;
          proxy_buffering off;
          proxy_request_buffering off;
          proxy_read_timeout 3600s;
          proxy_send_timeout 3600s;
        '';
      };
    };

    nginx.virtualHosts."restic-b2.4amlunch.net" = {
      onlySSL = true;
      useACMEHost = "4amlunch.net";
      extraConfig = ''
        add_header Strict-Transport-Security "max-age=31536000" always;
      '';
      locations."/" = {
        proxyPass = "http://127.0.0.1:18083";
        extraConfig = ''
          client_max_body_size 0;
          proxy_buffering off;
          proxy_request_buffering off;
          proxy_read_timeout 3600s;
          proxy_send_timeout 3600s;
        '';
      };
    };

    restic.backups.bob-services = {
      inherit repository;
      passwordFile = config.sops.secrets.minecraft-restic-password.path;
      environmentFile = config.sops.templates.bob-restic-environment.path;
      initialize = true;
      extraBackupArgs = [
        "--option"
        "rest.connections=20"
      ];
      paths = snapshots;
      exclude = [
        "/var/.zfs/snapshot/restic-services/cache"
        "/var/.zfs/snapshot/restic-services/lib/minecraft"
        "/var/.zfs/snapshot/restic-services/lib/systemd/coredump"
        "/var/.zfs/snapshot/restic-services/log"
        "/var/.zfs/snapshot/restic-services/tmp"
        "/var/lib/plexmediaserver/.zfs/snapshot/restic-services/Library/Application Support/Plex Media Server/Cache"
        "/var/lib/plexmediaserver/.zfs/snapshot/restic-services/Library/Application Support/Plex Media Server/Crash Reports"
        "/var/lib/plexmediaserver/.zfs/snapshot/restic-services/Library/Application Support/Plex Media Server/Logs"
      ];
      backupPrepareCommand = lib.getExe prepare;
      backupCleanupCommand = lib.getExe cleanup;
      timerConfig = {
        OnCalendar = "*-*-* 03:30:00";
        Persistent = true;
        RandomizedDelaySec = "15m";
      };
    };
  };

  systemd = {
    services = {
      restic-gateway = {
        description = "Append-only Restic gateway to the NFS primary";
        wantedBy = [ "multi-user.target" ];
        after = [
          "nfs-Minecraft.mount"
          "sops-install-secrets.service"
        ];
        requires = [
          "nfs-Minecraft.mount"
          "sops-install-secrets.service"
        ];
        serviceConfig = hardening // {
          ExecStart = "${lib.getExe pkgs.rclone} serve restic --addr 127.0.0.1:18082 --append-only --private-repos --htpasswd %d/htpasswd --server-read-timeout 1h --server-write-timeout 1h ${nfsRoot}";
          LoadCredential = [ "htpasswd:${config.sops.templates.restic-htpasswd.path}" ];
          ReadWritePaths = [ nfsRoot ];
          Restart = "on-failure";
          RestartSec = "5s";
          UMask = "0077";
        };
      };

      restic-b2-gateway = {
        description = "Append-only Restic disaster-recovery gateway to Backblaze B2";
        wantedBy = [ "multi-user.target" ];
        after = [
          "network-online.target"
          "sops-install-secrets.service"
        ];
        wants = [ "network-online.target" ];
        requires = [ "sops-install-secrets.service" ];
        serviceConfig = hardening // {
          ExecStart = "${lib.getExe pkgs.rclone} --config %d/rclone.conf serve restic --addr 127.0.0.1:18083 --append-only --private-repos --htpasswd %d/htpasswd --server-read-timeout 1h --server-write-timeout 1h b2:4amlunch-restic/restic";
          LoadCredential = [
            "rclone.conf:${config.sops.templates.restic-rclone.path}"
            "htpasswd:${config.sops.templates.restic-htpasswd.path}"
          ];
          Restart = "on-failure";
          RestartSec = "5s";
        };
      };

      restic-maintenance = {
        description = "Prune and check Restic repositories in Backblaze B2";
        after = [
          "network-online.target"
          "sops-install-secrets.service"
        ];
        wants = [ "network-online.target" ];
        requires = [ "sops-install-secrets.service" ];
        serviceConfig = hardening // {
          ExecStart = "${lib.getExe maintenance} %d";
          LoadCredential = [
            "rclone.conf:${config.sops.templates.restic-rclone.path}"
            "bob-password:${config.sops.secrets.minecraft-restic-password.path}"
            "deepthought-password:${config.sops.secrets.deepthought-restic-repository-password.path}"
          ];
          CacheDirectory = "restic-maintenance";
          CacheDirectoryMode = "0700";
          Environment = "RESTIC_CACHE_DIR=/var/cache/restic-maintenance";
          Type = "oneshot";
        };
      };

      restic-maintenance-nfs = {
        description = "Prune and check the Restic repositories on NFS";
        after = [
          "nfs-Minecraft.mount"
          "sops-install-secrets.service"
        ];
        requires = [
          "nfs-Minecraft.mount"
          "sops-install-secrets.service"
        ];
        serviceConfig = rootHardening // {
          ExecStart = "${lib.getExe nfsMaintenance} %d";
          LoadCredential = [
            "bob-password:${config.sops.secrets.minecraft-restic-password.path}"
            "deepthought-password:${config.sops.secrets.deepthought-restic-repository-password.path}"
          ];
          CacheDirectory = "restic-maintenance-nfs";
          CacheDirectoryMode = "0700";
          Environment = "RESTIC_CACHE_DIR=/var/cache/restic-maintenance-nfs";
          ReadWritePaths = [
            "-${bobNfsRepository}"
            "-${deepthoughtNfsRepository}"
          ];
          Type = "oneshot";
        };
      };

      restic-copy-bob = {
        description = "Mirror Bob's NFS Restic snapshots to Backblaze B2";
        after = [
          "network-online.target"
          "nfs-Minecraft.mount"
          "sops-install-secrets.service"
        ];
        wants = [ "network-online.target" ];
        requires = [
          "nfs-Minecraft.mount"
          "sops-install-secrets.service"
        ];
        serviceConfig = rootHardening // {
          ExecStart = "${lib.getExe mirror} %d/rclone.conf %d/repository-password ${bobNfsRepository} rclone:b2:4amlunch-restic/restic/bob";
          LoadCredential = [
            "rclone.conf:${config.sops.templates.restic-rclone.path}"
            "repository-password:${config.sops.secrets.minecraft-restic-password.path}"
          ];
          CacheDirectory = "restic-copy-bob";
          CacheDirectoryMode = "0700";
          Environment = "RESTIC_CACHE_DIR=/var/cache/restic-copy-bob";
          ReadWritePaths = [ bobNfsRepository ];
          Type = "oneshot";
        };
      };

      restic-copy-deepthought = {
        description = "Mirror Deepthought's NFS Restic snapshots to Backblaze B2";
        after = [
          "network-online.target"
          "nfs-Minecraft.mount"
          "sops-install-secrets.service"
        ];
        wants = [ "network-online.target" ];
        requires = [
          "nfs-Minecraft.mount"
          "sops-install-secrets.service"
        ];
        serviceConfig = rootHardening // {
          ExecStart = "${lib.getExe mirror} %d/rclone.conf %d/repository-password ${deepthoughtNfsRepository} rclone:b2:4amlunch-restic/restic/deepthought";
          LoadCredential = [
            "rclone.conf:${config.sops.templates.restic-rclone.path}"
            "repository-password:${config.sops.secrets.deepthought-restic-repository-password.path}"
          ];
          CacheDirectory = "restic-copy-deepthought";
          CacheDirectoryMode = "0700";
          Environment = "RESTIC_CACHE_DIR=/var/cache/restic-copy-deepthought";
          ReadWritePaths = [ deepthoughtNfsRepository ];
          Type = "oneshot";
        };
      };

      "restic-backups-bob-services" = {
        after = [
          "restic-gateway.service"
          "sops-install-secrets.service"
        ];
        requires = [
          "restic-gateway.service"
          "sops-install-secrets.service"
        ];
      };

      "restic-backups-minecraft" = {
        after = [
          "restic-gateway.service"
          "sops-install-secrets.service"
        ];
        requires = [
          "restic-gateway.service"
          "sops-install-secrets.service"
        ];
      };
    };

    timers.restic-maintenance = {
      description = "Weekly Restic repository maintenance";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "Sun *-*-* 12:00:00";
        Persistent = true;
        RandomizedDelaySec = "15m";
        Unit = "restic-maintenance.service";
      };
    };

    timers.restic-maintenance-nfs = {
      description = "Weekly NFS Restic repository maintenance";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "Sun *-*-* 10:00:00";
        Persistent = true;
        RandomizedDelaySec = "15m";
        Unit = "restic-maintenance-nfs.service";
      };
    };

    timers.restic-copy-bob = {
      description = "Daily Bob Restic mirror to Backblaze B2";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-* 05:30:00";
        Persistent = true;
        RandomizedDelaySec = "15m";
        Unit = "restic-copy-bob.service";
      };
    };

    timers.restic-copy-deepthought = {
      description = "Daily Deepthought Restic mirror to Backblaze B2";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-* 06:00:00";
        Persistent = true;
        RandomizedDelaySec = "15m";
        Unit = "restic-copy-deepthought.service";
      };
    };
  };
}
