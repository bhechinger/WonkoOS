{ config, lib, ... }:

{
  users = {
    groups.media.gid = 2000;
    users.media = {
      description = "Shared media service account";
      group = "media";
      isSystemUser = true;
      uid = 999;
    };
  };

  systemd = {
    mounts = lib.mkIf (config.networking.hostName == "bob") [
      {
        what = "10.42.0.30:/Brian";
        where = "/nfs/Brian";
        type = "nfs4";
        mountConfig.Options = "noatime";
      }
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
        where = "/nfs/Brian";
        wantedBy = [ "multi-user.target" ];
        automountConfig.TimeoutIdleSec = "600";
      }
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

    tmpfiles.settings."10-bob-native-services"."/home/docker".z = {
      group = "-";
      mode = "0711";
      user = "-";
    };
  };
}
