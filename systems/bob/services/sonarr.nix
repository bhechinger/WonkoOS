{
  bobRestoreMarker,
  config,
  lib,
  ...
}:

{
  services.sonarr = {
    enable = true;
    group = "media";
    openFirewall = false;
    user = "media";
  };

  systemd = {
    services.sonarr = {
      after = lib.optionals (config.networking.hostName == "bob") [
        "nfs-Plex.mount"
        "nfs-Torrents.mount"
      ];
      requires = lib.optionals (config.networking.hostName == "bob") [
        "nfs-Plex.mount"
        "nfs-Torrents.mount"
      ];
      unitConfig.ConditionPathExists = bobRestoreMarker;
    };

    tmpfiles.settings."10-bob-native-services"."/var/lib/sonarr/.config/NzbDrone".d = {
      group = "media";
      mode = "0750";
      user = "media";
    };
  };
}
