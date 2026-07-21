{ config, lib, ... }:

{
  systemd = {
    mounts = lib.mkIf (config.networking.hostName == "bob") [
      {
        what = "10.42.0.30:/Plex";
        where = "/nfs/Plex";
        type = "nfs4";
        mountConfig.Options = "noatime";
      }
      {
        what = "10.42.0.30:/Torrents";
        where = "/nfs/Torrents";
        type = "nfs4";
        mountConfig.Options = "noatime";
      }
    ];
    automounts = lib.mkIf (config.networking.hostName == "bob") [
      {
        where = "/nfs/Plex";
        wantedBy = [ "multi-user.target" ];
        automountConfig.TimeoutIdleSec = "600";
      }
      {
        where = "/nfs/Torrents";
        wantedBy = [ "multi-user.target" ];
        automountConfig.TimeoutIdleSec = "600";
      }
    ];
  };
}
