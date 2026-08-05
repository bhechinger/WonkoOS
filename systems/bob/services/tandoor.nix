{
  config,
  lib,
  ...
}:

{
  sops.secrets.tandoor-environment = {
    sopsFile = ../secrets/tandoor.env.sops;
    format = "binary";
    mode = "0400";
    restartUnits = [ "tandoor-recipes.service" ];
  };

  services = {
    tandoor-recipes = {
      enable = true;
      address = "127.0.0.1";
      port = 18084;
      database.createLocally = true;
      extraConfig = {
        ALLOWED_HOSTS = "recipes.4amlunch.net";
        ALLAUTH_TRUSTED_PROXY_COUNT = 1;
        CSRF_TRUSTED_ORIGINS = "https://recipes.4amlunch.net";
        ENABLE_SIGNUP = 0;
        GUNICORN_MEDIA = 0;
        MEDIA_ROOT = "/var/lib/tandoor-recipes/media";
      };
    };

    postgresqlBackup = {
      enable = true;
      compression = "zstd";
      databases = [ "tandoor_recipes" ];
      startAt = "*-*-* *:20:00";
    };
  };

  users.users.nginx.extraGroups = [ "tandoor_recipes" ];

  systemd.services.tandoor-recipes = {
    after = [ "sops-install-secrets.service" ];
    requires = [ "sops-install-secrets.service" ];
    serviceConfig = {
      EnvironmentFile = config.sops.secrets.tandoor-environment.path;
      StateDirectoryMode = "0750";
      TimeoutStartSec = "10min";
      UMask = lib.mkForce "0027";
    };
  };
}
