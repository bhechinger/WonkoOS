{
  services.jackett = {
    enable = true;
    dataDir = "/home/docker/jackett/config/Jackett";
    openFirewall = false;
  };

  systemd = {
    services.jackett = {
      serviceConfig = {
        BindPaths = [ "/home/docker/jackett/downloads:/downloads" ];
        ReadWritePaths = [ "/home/docker/jackett/downloads" ];
      };
    };

    tmpfiles.settings."10-bob-native-services"."/home/docker/jackett/downloads".d = {
      group = "jackett";
      mode = "0770";
      user = "jackett";
    };
  };
}
