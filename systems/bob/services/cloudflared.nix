{
  bobRestoreMarker,
  lib,
  pkgs,
  ...
}:

{
  networking.extraHosts = ''
    127.0.0.1 reverse paperless jackett sonarr
  '';

  systemd.services.cloudflared-tunnel = {
    after = [
      "network-online.target"
      "nginx.service"
    ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    unitConfig.ConditionPathExists = [
      bobRestoreMarker
      "/var/lib/cloudflared/tunnel.env"
    ];
    serviceConfig = {
      DynamicUser = true;
      EnvironmentFile = "/var/lib/cloudflared/tunnel.env";
      ExecStart = "${lib.getExe pkgs.cloudflared} tunnel --no-autoupdate run";
      Restart = "always";
      RestartSec = "5s";
    };
  };
}
