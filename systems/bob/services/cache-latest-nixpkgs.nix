{ lib, pkgs, ... }:

let
  packages = [
    "mongodb"
  ];
  serviceSandbox = {
    AmbientCapabilities = "";
    CapabilityBoundingSet = "";
    DynamicUser = true;
    NoNewPrivileges = true;
    PrivateDevices = true;
    PrivateTmp = true;
    ProtectHome = true;
    ProtectSystem = "strict";
    StateDirectory = "cache-latest-nixpkgs";
    Type = "oneshot";
    UMask = "0077";
  };
  cacheLatestNixpkgsBuild = pkgs.writeShellApplication {
    name = "cache-latest-nixpkgs-build";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.nix
    ];
    text = ''
      export HOME="$STATE_DIRECTORY"
      rm -f -- "$STATE_DIRECTORY"/result*
      exec ${../../../scripts/cache-latest-nixpkgs.sh} --build-only "$STATE_DIRECTORY/result" "$@"
    '';
  };
  cacheLatestNixpkgsUpload = pkgs.writeShellApplication {
    name = "cache-latest-nixpkgs-upload";
    runtimeInputs = [
      pkgs.attic-client
      pkgs.coreutils
    ];
    text = ''
      install -D -m 0400 "$CREDENTIALS_DIRECTORY/attic-config" "$RUNTIME_DIRECTORY/attic/config.toml"
      export HOME="$STATE_DIRECTORY"
      export XDG_CONFIG_HOME="$RUNTIME_DIRECTORY"
      attic push internal "$STATE_DIRECTORY"/result*
      rm -f -- "$STATE_DIRECTORY"/result*
    '';
  };
in
{
  systemd.services.cache-latest-nixpkgs = {
    description = "Build current nixpkgs packages";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    unitConfig.OnSuccess = "cache-latest-nixpkgs-upload.service";
    serviceConfig = serviceSandbox // {
      ExecStart = "${lib.getExe cacheLatestNixpkgsBuild} ${lib.escapeShellArgs packages}";
    };
  };

  systemd.services.cache-latest-nixpkgs-upload = {
    description = "Upload current nixpkgs packages to Attic";
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
    serviceConfig = serviceSandbox // {
      ExecStart = lib.getExe cacheLatestNixpkgsUpload;
      LoadCredential = "attic-config:/home/wonko/.config/attic/config.toml";
      RuntimeDirectory = "cache-latest-nixpkgs-upload";
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
