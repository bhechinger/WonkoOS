{
  config,
  lib,
  pkgs,
  ...
}:

let
  repository = "rest:https://restic.4amlunch.net/deepthought/";
  b2Repository = "rest:https://restic-b2.4amlunch.net/deepthought/";
  snapshot = "tank/home@restic-deepthought";
  dump = "/run/restic-deepthought/postgresql.sql";
  cleanup = pkgs.writeShellApplication {
    name = "deepthought-restic-cleanup";
    runtimeInputs = [ pkgs.zfs ];
    text = ''
      zfs destroy ${snapshot} 2>/dev/null || true
      rm -f ${dump}
      rmdir /run/restic-deepthought 2>/dev/null || true
    '';
  };
  prepare = pkgs.writeShellApplication {
    name = "deepthought-restic-prepare";
    runtimeInputs = [
      config.services.postgresql.package
      pkgs.coreutils
      pkgs.util-linux
      pkgs.zfs
    ];
    text = ''
      ${lib.getExe cleanup}
      trap '${lib.getExe cleanup}' ERR
      zfs snapshot ${snapshot}
      install -d -m 0700 /run/restic-deepthought
      umask 077
      runuser -u postgres -- pg_dumpall > ${dump}
      trap - ERR
    '';
  };
  b2Client = pkgs.writeShellApplication {
    name = "restic-deepthought-b2";
    runtimeInputs = [ pkgs.restic ];
    text = ''
      RESTIC_REST_USERNAME=deepthought
      RESTIC_REST_PASSWORD="$(<${config.sops.secrets.restic-http-password.path})"
      export RESTIC_REST_USERNAME RESTIC_REST_PASSWORD
      exec restic \
        --repo ${lib.escapeShellArg b2Repository} \
        --password-file ${config.sops.secrets.restic-repository-password.path} \
        "$@"
    '';
  };
in
{
  environment.systemPackages = [ b2Client ];

  sops = {
    secrets = {
      restic-http-password = {
        sopsFile = ./secrets/restic.sops;
        format = "yaml";
        key = "http-password";
        mode = "0400";
      };
      restic-repository-password = {
        sopsFile = ./secrets/restic.sops;
        format = "yaml";
        key = "repository-password";
        mode = "0400";
      };
    };
    templates.restic-environment = {
      content = ''
        RESTIC_REST_USERNAME=deepthought
        RESTIC_REST_PASSWORD=${config.sops.placeholder.restic-http-password}
      '';
      mode = "0400";
    };
  };

  services.restic.backups.deepthought = {
    inherit repository;
    passwordFile = config.sops.secrets.restic-repository-password.path;
    environmentFile = config.sops.templates.restic-environment.path;
    initialize = true;
    extraBackupArgs = [
      "--option"
      "rest.connections=20"
    ];
    paths = [
      "/home/.zfs/snapshot/restic-deepthought/wonko"
      dump
    ];
    exclude = [
      "/home/.zfs/snapshot/restic-deepthought/wonko/.cache"
      "/home/.zfs/snapshot/restic-deepthought/wonko/.local/share/Steam"
      "/home/.zfs/snapshot/restic-deepthought/wonko/.local/share/Trash"
      "/home/.zfs/snapshot/restic-deepthought/wonko/.local/share/containers"
    ];
    backupPrepareCommand = lib.getExe prepare;
    backupCleanupCommand = lib.getExe cleanup;
    timerConfig = {
      OnCalendar = "*-*-* 02:30:00";
      Persistent = true;
      RandomizedDelaySec = "15m";
    };
  };

  systemd.services."restic-backups-deepthought" = {
    after = [
      "network-online.target"
      "postgresql.service"
      "sops-install-secrets.service"
    ];
    wants = [ "network-online.target" ];
    requires = [
      "postgresql.service"
      "sops-install-secrets.service"
    ];
  };
}
