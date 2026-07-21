{
  services.plex = {
    enable = true;
    dataDir = "/var/lib/plexmediaserver/Library/Application Support";
    openFirewall = false;
  };

  users.users.plex.extraGroups = [
    "render"
    "video"
  ];
}
