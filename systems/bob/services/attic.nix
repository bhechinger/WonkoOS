{ config, ... }:

{
  sops.secrets.atticd-environment = {
    sopsFile = ../secrets/attic.env.sops;
    format = "binary";
    mode = "0400";
    restartUnits = [ "atticd.service" ];
  };

  services.atticd = {
    enable = true;
    environmentFile = config.sops.secrets.atticd-environment.path;
    settings = {
      listen = "127.0.0.1:18081";
      allowed-hosts = [ "cache.4amlunch.net" ];
      api-endpoint = "https://cache.4amlunch.net/";
      substituter-endpoint = "https://cache.4amlunch.net/";
      database.url = "sqlite:///var/lib/atticd/server.db?mode=rwc";
      storage = {
        type = "local";
        path = "/nfs/NixCache";
      };
      compression.type = "zstd";
      garbage-collection = {
        interval = "12 hours";
        default-retention-period = "1 year";
      };
    };
  };
  systemd = {
    mounts = [
      {
        what = "10.42.0.30:/NixCache";
        where = "/nfs/NixCache";
        type = "nfs4";
        mountConfig.Options = "noatime,nodev,nosuid,noexec";
      }
    ];
    automounts = [
      {
        where = "/nfs/NixCache";
        wantedBy = [ "multi-user.target" ];
        automountConfig.TimeoutIdleSec = "600";
      }
    ];
    services.atticd = {
      after = [ "nfs-NixCache.automount" ];
      requires = [ "nfs-NixCache.automount" ];
    };
  };
}
