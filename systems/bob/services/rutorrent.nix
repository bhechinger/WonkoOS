{ config, ... }:

{
  sops.secrets.rutorrent-htpasswd = {
    sopsFile = ../secrets/rutorrent.htpasswd.sops;
    format = "binary";
    group = config.services.nginx.group;
    mode = "0440";
    restartUnits = [ "nginx.service" ];
  };

  services.rutorrent = {
    enable = true;
    hostName = "rutorrent.4amlunch.net";
    nginx.enable = true;
  };

  systemd.tmpfiles.settings."10-bob-native-services"."/var/lib/rutorrent".z = {
    group = "rutorrent";
    mode = "0751";
    user = "root";
  };
}
