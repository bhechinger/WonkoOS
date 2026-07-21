{
  config,
  lib,
  pkgs,
  ...
}:

{
  sops.secrets.cloudflared-environment = {
    sopsFile = ../secrets/cloudflared.env.sops;
    format = "binary";
    mode = "0400";
    restartUnits = [ "cloudflared-tunnel.service" ];
  };

  systemd.services.cloudflared-tunnel = {
    after = [
      "network-online.target"
      "nginx.service"
      "sops-install-secrets.service"
    ];
    requires = [ "sops-install-secrets.service" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      AmbientCapabilities = "";
      CapabilityBoundingSet = "";
      DynamicUser = true;
      EnvironmentFile = config.sops.secrets.cloudflared-environment.path;
      ExecStart = "${lib.getExe pkgs.cloudflared} tunnel --no-autoupdate run";
      LockPersonality = true;
      NoNewPrivileges = true;
      PrivateDevices = true;
      PrivateTmp = true;
      ProtectClock = true;
      ProtectControlGroups = true;
      ProtectHome = true;
      ProtectHostname = true;
      ProtectKernelLogs = true;
      ProtectKernelModules = true;
      ProtectKernelTunables = true;
      ProtectSystem = "strict";
      Restart = "always";
      RestartSec = "5s";
      RestrictSUIDSGID = true;
    };
  };
}
