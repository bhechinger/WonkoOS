{ bobRestoreMarker, ... }:

{
  services.tailscale = {
    enable = true;
    openFirewall = false;
  };

  systemd.services.tailscaled.unitConfig.ConditionPathExists = bobRestoreMarker;
}
