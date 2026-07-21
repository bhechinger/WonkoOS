{
  config,
  lib,
  ...
}:

{
  services.rtorrent = {
    dataPermissions = "0700";
    enable = true;
    downloadDir = "/nfs/Torrents";
    openFirewall = false;
  };

  users.users.nginx.extraGroups = [ "rtorrent" ];

  systemd.services.rtorrent = {
    after = lib.optionals (config.networking.hostName == "bob") [ "nfs-Torrents.mount" ];
    requires = lib.optionals (config.networking.hostName == "bob") [ "nfs-Torrents.mount" ];
  };
}
