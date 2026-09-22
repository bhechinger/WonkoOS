{ config, inputs, ... }:

{
  disabledModules = [ "services/torrent/rtorrent.nix" ];

  imports = [
    (inputs.unstable-nixpkgs.outPath + "/nixos/modules/services/torrent/rtorrent.nix")
  ];

  nixpkgs.overlays = [
    (
      _final: prev:
      let
        unstablePkgs = inputs.unstable-nixpkgs.legacyPackages.${prev.stdenv.hostPlatform.system};
      in
      {
        inherit (unstablePkgs) rtorrent rutorrent;
      }
    )
  ];

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
