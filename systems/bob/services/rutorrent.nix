{ bobRestoreMarker, ... }:

{
  services.rutorrent = {
    enable = true;
    hostName = "rutorrent.4amlunch.net";
    nginx.enable = true;
  };

  systemd = {
    services = {
      phpfpm-rutorrent.unitConfig.ConditionPathExists = bobRestoreMarker;
      rutorrent-setup.unitConfig.ConditionPathExists = bobRestoreMarker;
    };

    tmpfiles.settings."10-bob-native-services" = {
      "/var/lib/rutorrent".z = {
        group = "rutorrent";
        mode = "0751";
        user = "root";
      };
      "/var/lib/rutorrent/htpasswd".z = {
        group = "nginx";
        mode = "0640";
        user = "root";
      };
    };
  };
}
