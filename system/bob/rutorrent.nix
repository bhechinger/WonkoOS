# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running `nixos-help`).

{ config, system, pkgs, nixpkgs_rutorrent, ... }:

{
  # make rutorrent package available to the system
  nixpkgs.overlays = [
    (final: prev: {
      rutorrent = nixpkgs_rutorrent.legacyPackages.${pkgs.system}.rutorrent;
    })
  ];

  imports =
    [
      "${nixpkgs_rutorrent}/nixos/modules/services/web-apps/rutorrent.nix" # pull in this service from the fork
      "${nixpkgs_rutorrent}/nixos/modules/services/torrent/rtorrent.nix" # use the fork's instead of upstream's
    ];

  # make rTorrent dependant on the NFS mount being up
  systemd.services.rtorrent = {
    requires = [ "nfs-Torrents.mount" ];
    after = [ "nfs-Torrents.mount" ];
  };

  users.groups.rtorrent = {};

  users.users = {
    rtorrent = {
      createHome = false;
      group = "rtorrent";
      extraGroups = [ "media" ];
    };

    rutorrent = {
      createHome = false;
      extraGroups = [ "media" ];
    };
  }; # needs to be enabled lest something else be enabled (some mutual exclusion config option)

  services.rutorrent = {
    enable = true;
    hostName = "rutorrent.4amlunch.net";
    plugins = ["httprpc" "data" "diskspace" "trafic" ];

    nginx.enable = true;
  };

  services.rtorrent = {
    enable = true;
    downloadDir = "/nfs/Torrents";
  };

  disabledModules = [ "services/torrent/rtorrent.nix" ]; # avoid conflict with upstream nixpkgs rtorrent service
}

