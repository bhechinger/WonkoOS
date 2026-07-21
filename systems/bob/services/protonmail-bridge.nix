{
  inputs,
  lib,
  pkgs,
  ...
}:

let
  package =
    inputs.unstable-nixpkgs.legacyPackages.${pkgs.stdenv.hostPlatform.system}.protonmail-bridge;
in
{
  environment.systemPackages = [ package ];

  users = {
    groups.protonmail-bridge = { };
    users.protonmail-bridge = {
      description = "Proton Mail Bridge";
      group = "protonmail-bridge";
      home = "/var/lib/protonmail-bridge";
      isSystemUser = true;
    };
  };

  systemd.services.protonmail-bridge = {
    description = "Proton Mail Bridge";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    environment = {
      GNUPGHOME = "/var/lib/protonmail-bridge/.gnupg";
      HOME = "/var/lib/protonmail-bridge";
      PASSWORD_STORE_DIR = "/var/lib/protonmail-bridge/.password-store";
      XDG_CACHE_HOME = "/var/lib/protonmail-bridge/.cache";
      XDG_CONFIG_HOME = "/var/lib/protonmail-bridge/.config";
      XDG_DATA_HOME = "/var/lib/protonmail-bridge/.local/share";
    };
    path = [
      pkgs.gnupg
      pkgs.pass
    ];
    serviceConfig = {
      AmbientCapabilities = "";
      # The migrated container vault stores its Gluon cache below /root.
      # Map the dedicated state directory there only inside this unit's
      # private mount namespace; the service still runs unprivileged.
      BindPaths = [ "/var/lib/protonmail-bridge:/root" ];
      CapabilityBoundingSet = "";
      ExecStart = "${lib.getExe package} --noninteractive --log-level info";
      Group = "protonmail-bridge";
      LockPersonality = true;
      NoNewPrivileges = true;
      PrivateDevices = true;
      PrivateTmp = true;
      ProtectClock = true;
      ProtectControlGroups = true;
      ProtectHostname = true;
      ProtectKernelLogs = true;
      ProtectKernelModules = true;
      ProtectKernelTunables = true;
      ProtectSystem = "strict";
      Restart = "on-failure";
      RestartSec = "5s";
      RestrictSUIDSGID = true;
      StateDirectory = "protonmail-bridge";
      StateDirectoryMode = "0700";
      UMask = "0077";
      User = "protonmail-bridge";
    };
  };
}
