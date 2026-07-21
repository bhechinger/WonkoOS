{ config, ... }:

{
  sops.secrets.murmur-environment = {
    sopsFile = ../secrets/murmur.env.sops;
    format = "binary";
    owner = config.services.murmur.user;
    mode = "0400";
    restartUnits = [ "murmur.service" ];
  };

  services.murmur = {
    enable = true;
    environmentFile = config.sops.secrets.murmur-environment.path;
    openFirewall = false;
    password = "$MURMURD_PASSWORD";
    stateDir = "/var/lib/mumble-server";
  };
}
