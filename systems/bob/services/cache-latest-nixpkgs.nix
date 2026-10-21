{ lib, pkgs, ... }:

let
  packages = [
    "mongodb"
  ];
  cacheLatestNixpkgs = pkgs.writeShellApplication {
    name = "cache-latest-nixpkgs";
    runtimeInputs = [
      pkgs.attic-client
      pkgs.nix
    ];
    text = ''
      exec ${../../../scripts/cache-latest-nixpkgs.sh} "$@"
    '';
  };
in
{
  systemd.services.cache-latest-nixpkgs = {
    description = "Build current nixpkgs packages and upload them to Attic";
    after = [
      "atticd.service"
      "network-online.target"
      "nginx.service"
    ];
    wants = [
      "atticd.service"
      "network-online.target"
      "nginx.service"
    ];
    serviceConfig = {
      ExecStart = "${lib.getExe cacheLatestNixpkgs} ${lib.escapeShellArgs packages}";
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      Type = "oneshot";
      UMask = "0077";
      User = "wonko";
    };
  };

  systemd.timers.cache-latest-nixpkgs = {
    description = "Build current nixpkgs packages nightly";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 04:00:00";
      Persistent = true;
    };
  };
}
