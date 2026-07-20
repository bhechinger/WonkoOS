{
  bobRestoreMarker,
  config,
  lib,
  pkgs,
  ...
}:

let
  paperlessLocations = {
    "/" = {
      proxyPass = "http://paperless";
      proxyWebsockets = true;
      extraConfig = ''
        proxy_set_header X-ProxyScheme "http";
        proxy_set_header X-ProxyHost $http_host;
        proxy_set_header X-ProxyPort 8000;
        proxy_set_header X-ProxyContextPath "";
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

  security.acme = {
    acceptTerms = true;
    defaults.email = "wonko@4amlunch.net";
    certs."4amlunch.net" = {
      domain = "4amlunch.net";
      extraDomainNames = [ "*.4amlunch.net" ];
      dnsProvider = "cloudflare";
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
      "basket.4amlunch.net" = tls // {
        locations."/".proxyPass = "https://10.42.0.30:8443";
      };
      "bob.4amlunch.net" = tls // {
        root = "/home/docker/reverse/html";
      };
      "hamburgerking.pt".root = "/home/docker/reverse/html/hbk";
      "jackett.4amlunch.net" = tls // {
        locations."/".proxyPass = "http://127.0.0.1:9117";
      };
      "paperless.4amlunch.net" = tls // {
        locations = paperlessLocations;
      };
      paperless-direct = {
        default = true;
        listen = [
          {
            addr = "0.0.0.0";
            port = 8001;
          }
          {
            addr = "[::]";
            port = 8001;
          }
        ];
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
        basicAuthFile = "/var/lib/rutorrent/htpasswd";
      };
      "sonarr.4amlunch.net" = tls // {
        locations."/".proxyPass = "http://127.0.0.1:8989";
      };
    };
  };

  systemd.services.nginx = {
    unitConfig.ConditionPathExists = [
      bobRestoreMarker
      "/var/lib/rutorrent/htpasswd"
    ];
    serviceConfig.ProtectHome = lib.mkForce "read-only";
  };

  systemd.services."acme-4amlunch.net" = {
    after = [ "sops-install-secrets.service" ];
    requires = [ "sops-install-secrets.service" ];
  };
}
