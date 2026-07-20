{ bobRestoreMarker, ... }:

{
  services.jackett = {
    enable = true;
    dataDir = "/home/docker/jackett/config/Jackett";
    group = "media";
    openFirewall = false;
    user = "media";
  };

  systemd = {
    services.jackett = {
      serviceConfig = {
        BindPaths = [ "/home/docker/jackett/downloads:/downloads" ];
        ReadWritePaths = [ "/home/docker/jackett/downloads" ];
      };
      unitConfig.ConditionPathExists = bobRestoreMarker;
    };

    tmpfiles.settings."10-bob-native-services"."/home/docker/jackett/downloads".d = {
      group = "media";
      mode = "0770";
      user = "media";
    };
  };
}
