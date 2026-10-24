{ ... }:

{
  services.matrix-synapse = {
    enable = true;
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
    ensureDatabases = [ "matrix-synapse" ];
    ensureUsers = [
      {
        name = "matrix-synapse";
        ensureDBOwnership = true;
      }
    ];
  };

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
      extraConfig = "client_max_body_size 50M;";
      locations."/".return = "404";
      locations."/_matrix".proxyPass = "http://127.0.0.1:8008";
      locations."/_synapse/client".proxyPass = "http://127.0.0.1:8008";
    };
  };
}
