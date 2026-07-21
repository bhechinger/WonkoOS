{
  lib,
  pkgs,
  ...
}:

{
  services.postgresql = {
    dataDir = "/home/docker/pgsql/paperless";
    package = pkgs.postgresql_16;
  };

  systemd.services.postgresql = {
    serviceConfig.ProtectHome = lib.mkForce "read-only";
  };
}
