{ config, lib, pkgs, modulesPath, ... }:

{
  # Group so everyone has filesystem access to media
  users.groups.media = {
    gid = 999;
  };

  # Plex service and user
  users.users.plex = {
    createHome = false;
    extraGroups = [ "media" ];
  };
  services.plex = {
    enable = true;
    openFirewall = true;
  };

  # make plex dependant on the NFS mount being up
  systemd.services.plex = {
    requires = [ "nfs-Plex.mount" ];
    after = [ "nfs-Plex.mount" ];
  };

  # Jackett service and user
  users.users.jackett = {
    createHome = false;
    extraGroups = [ "media" ];
  };
  services.jackett = {
    enable = true;
    openFirewall = true;
  };

  # Sonarr service and user
  users.users.sonarr = {
    createHome = false;
    extraGroups = [ "media" ];
  };
  services.sonarr = {
    enable = true;
    openFirewall = true;
  };

  # Radarr service and user
  users.users.radarr = {
    createHome = false;
    extraGroups = [ "media" ];
  };
  services.radarr = {
    enable = true;
    openFirewall = true;
  };


}
