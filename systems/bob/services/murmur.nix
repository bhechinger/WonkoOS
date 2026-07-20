{ bobRestoreMarker, ... }:

{
  services.murmur = {
    enable = true;
    environmentFile = "/var/lib/mumble-server/murmurd.env";
    openFirewall = false;
    password = "$MURMURD_PASSWORD";
    stateDir = "/var/lib/mumble-server";
  };

  systemd.services.murmur.unitConfig.ConditionPathExists = bobRestoreMarker;
}
