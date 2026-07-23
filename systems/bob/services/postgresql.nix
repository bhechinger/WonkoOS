{
  pkgs,
  ...
}:

{
  services.postgresql = {
    dataDir = "/var/lib/postgresql/paperless";
    package = pkgs.postgresql_16;
  };
}
