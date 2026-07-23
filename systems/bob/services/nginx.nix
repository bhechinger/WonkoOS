{
  config,
  pkgs,
  ...
}:

let
  hsts = ''
    add_header Strict-Transport-Security "max-age=31536000" always;
  '';
  paperlessLocations = {
    "/" = {
      proxyPass = "http://paperless";
      proxyWebsockets = true;
      extraConfig = ''
        add_header Referrer-Policy "strict-origin-when-cross-origin";
      '';
    };
    "/static/" = {
      root = config.services.paperless.package;
      extraConfig = ''
        rewrite ^/(.*)$ /lib/paperless-ngx/$1 break;
      '';
    };
    "/ws/status" = {
      proxyPass = "http://paperless";
      proxyWebsockets = true;
    };
  };
  tls = {
    extraConfig = hsts;
    onlySSL = true;
    useACMEHost = "4amlunch.net";
  };
in
{
  sops.secrets.cloudflare-acme-token = {
    sopsFile = ../secrets/acme.sops;
    format = "yaml";
    key = "cloudflare-api-token";
    mode = "0400";
  };
  sops.secrets.rutorrent-htpasswd.restartUnits = [ "nginx.service" ];

  security.acme = {
    acceptTerms = true;
    defaults.email = "wonko@4amlunch.net";
    certs."4amlunch.net" = {
      domain = "4amlunch.net";
      extraDomainNames = [ "*.4amlunch.net" ];
      dnsProvider = "cloudflare";
      extraLegoFlags = [ "--dns.propagation-wait=30s" ];
      credentialFiles."CF_DNS_API_TOKEN_FILE" = config.sops.secrets.cloudflare-acme-token.path;
      group = config.services.nginx.group;
    };
  };

  services.nginx = {
    enable = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;
    upstreams.paperless.servers."127.0.0.1:8000" = { };
    virtualHosts = {
      _default = {
        default = true;
        rejectSSL = true;
        locations."/".return = "444";
      };
      "bob.4amlunch.net" = tls // {
        root = "/var/www";
      };
      "cache.4amlunch.net" = tls // {
        locations."/" = {
          proxyPass = "http://127.0.0.1:18081";
          extraConfig = ''
            client_max_body_size 0;
            proxy_request_buffering off;
          '';
        };
      };
      "hamburgerking.pt".root = "/var/www/hbk";
      "jackett.4amlunch.net" = tls // {
        locations."/".proxyPass = "http://127.0.0.1:9117";
      };
      "paperless.4amlunch.net" = tls // {
        extraConfig = hsts + ''
          proxy_cookie_flags ~ secure;
        '';
        locations = paperlessLocations;
      };
      "rtorrent-rpc" = {
        listen = [
          {
            addr = "127.0.0.1";
            port = 9000;
          }
        ];
        locations."/RPC2".extraConfig = ''
          include ${pkgs.nginx}/conf/scgi_params;
          scgi_pass unix:${config.services.rtorrent.rpcSocket};
        '';
      };
      "rutorrent.4amlunch.net" = tls // {
        basicAuthFile = config.sops.secrets.rutorrent-htpasswd.path;
      };
      "sonarr.4amlunch.net" = tls // {
        locations."/".proxyPass = "http://127.0.0.1:8989";
      };
    };
  };

  systemd.services.nginx = {
    after = [ "sops-install-secrets.service" ];
    requires = [ "sops-install-secrets.service" ];
  };

  systemd.services."acme-4amlunch.net" = {
    after = [ "sops-install-secrets.service" ];
    requires = [ "sops-install-secrets.service" ];
  };
}
