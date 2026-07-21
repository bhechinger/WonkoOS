{
  config,
  lib,
  ...
}:

{
  services.sonarr = {
    enable = true;
    openFirewall = false;
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
    };
  };
}
