{
  services.jackett = {
    enable = true;
    dataDir = "/var/lib/jackett";
    openFirewall = false;
  };

  systemd = {
    services.jackett = {
      serviceConfig = {
        BindPaths = [ "/var/lib/jackett/downloads:/downloads" ];
        ReadWritePaths = [ "/var/lib/jackett/downloads" ];
      };
    };

    tmpfiles.settings."10-bob-native-services"."/var/lib/jackett/downloads".d = {
      group = "jackett";
      mode = "0770";
      user = "jackett";
    };
  };
}
