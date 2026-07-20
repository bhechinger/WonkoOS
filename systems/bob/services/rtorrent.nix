{
  bobRestoreMarker,
  config,
  lib,
  ...
}:

{
  services.rtorrent = {
    enable = true;
    downloadDir = "/nfs/Torrents";
    group = "nginx";
    openFirewall = false;
    user = "media";
  };

  systemd.services.rtorrent = {
    after = lib.optionals (config.networking.hostName == "bob") [ "nfs-Torrents.mount" ];
    requires = lib.optionals (config.networking.hostName == "bob") [ "nfs-Torrents.mount" ];
    unitConfig.ConditionPathExists = bobRestoreMarker;
  };
}
