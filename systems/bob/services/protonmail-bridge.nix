{ bobRestoreMarker, ... }:

{
  virtualisation.oci-containers.containers.protonmail-bridge = {
    image = "shenxn/protonmail-bridge:latest";
    pull = "never";
    ports = [
      "1025:25"
      "1143:143"
    ];
    volumes = [ "protonmail:/root" ];
  };

  systemd.services.docker-protonmail-bridge.unitConfig.ConditionPathExists = bobRestoreMarker;
}
