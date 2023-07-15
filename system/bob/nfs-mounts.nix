{ config, lib, pkgs, modulesPath, ... }:

{
  fileSystems."/nfs/Plex" = {
    device = "basket.4amlunch.net:/Plex";
    fsType = "nfs";
    options = [ "x-systemd.automount" "x-systemd.after=network-online.target" "x-systemd.mount-timeout=90" ];
  };

  fileSystems."/nfs/Torrents" = {
    device = "basket.4amlunch.net:/Torrents";
    fsType = "nfs";
    options = [ "x-systemd.automount" "x-systemd.after=network-online.target" "x-systemd.mount-timeout=90" ];
  };
}
