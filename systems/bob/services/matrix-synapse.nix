{ config, ... }:

{
  sops.secrets.matrix-synapse-registration = {
    sopsFile = ../secrets/matrix-synapse-registration.sops;
    format = "yaml";
    key = "registration_shared_secret";
    owner = "matrix-synapse";
    group = "matrix-synapse";
    mode = "0400";
  };
  sops.templates.matrix-synapse-registration = {
    content = "registration_shared_secret: ${config.sops.placeholder.matrix-synapse-registration}\n";
    owner = "matrix-synapse";
    group = "matrix-synapse";
    mode = "0400";
    restartUnits = [ "matrix-synapse.service" ];
  };

  services.matrix-synapse = {
    enable = true;
    extraConfigFiles = [ config.sops.templates.matrix-synapse-registration.path ];
    settings = {
      server_name = "4amlunch.net";
      public_baseurl = "https://matrix.4amlunch.net/";
      enable_registration = false;
      database = {
        name = "psycopg2";
        args = {
          database = "matrix-synapse";
          user = "matrix-synapse";
        };
      };
    };
  };

  services.postgresql = {
    ensureUsers = [
      {
        name = "matrix-synapse";
      }
    ];
  };

  systemd.services.postgresql-setup.postStart = ''
    if ! psql -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname = 'matrix-synapse'" | grep -q 1; then
      createdb --template=template0 --lc-collate=C --lc-ctype=C --owner=matrix-synapse matrix-synapse
    fi
  '';

  services.nginx.virtualHosts = {
    "4amlunch.net" = {
      useACMEHost = "4amlunch.net";
      onlySSL = true;
      locations."= /.well-known/matrix/client".extraConfig = ''
        default_type application/json;
        add_header Access-Control-Allow-Origin *;
        return 200 '{"m.homeserver":{"base_url":"https://matrix.4amlunch.net"}}';
      '';
      locations."= /.well-known/matrix/server".extraConfig = ''
        default_type application/json;
        return 200 '{"m.server":"matrix.4amlunch.net:443"}';
      '';
      locations."/".return = "404";
    };
    "matrix.4amlunch.net" = {
      useACMEHost = "4amlunch.net";
      onlySSL = true;
      extraConfig = ''
        client_max_body_size 50M;
        set_real_ip_from 127.0.0.1;
        set_real_ip_from ::1;
        real_ip_header CF-Connecting-IP;
      '';
      locations."/".return = "404";
      locations."/_matrix".proxyPass = "http://127.0.0.1:8008";
      locations."/_synapse/client".proxyPass = "http://127.0.0.1:8008";
    };
  };
}
