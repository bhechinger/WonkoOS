{ bobRestoreMarker, ... }:

{
  virtualisation.oci-containers.containers.unifi-controller = {
    image = "lscr.io/linuxserver/unifi-controller:latest";
    pull = "never";
    environment = {
      MEM_LIMIT = "1024";
      MEM_STARTUP = "1024";
      PGID = "1000";
      PUID = "1000";
      TZ = "Etc/UTC";
    };
    ports = [
      "8443:8443"
      "3478:3478/udp"
      "10001:10001/udp"
      "8080:8080"
      "1900:1900/udp"
      "8843:8843"
      "8880:8880"
      "6789:6789"
      "5514:5514/udp"
    ];
    volumes = [ "/home/unifi/config:/config" ];
  };

  systemd.services.docker-unifi-controller.unitConfig.ConditionPathExists = bobRestoreMarker;
}
