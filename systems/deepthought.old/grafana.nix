{ config, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    #prometheus-dcgm-exporter
    promql-cli
  ];

  services = {
    grafana = {
      enable = true;
      settings = {
        server = {
          # Listening Address
          http_addr = "127.0.0.1";
          # and Port
          http_port = 3000;
          # Grafana needs to know on which domain and URL it's running
          domain = "deepthought.4amlunch.net";
          root_url = "http://deepthought.4amlunch.net/grafana/"; # Not needed if it is `https://your.domain/`
          serve_from_sub_path = true;
        };
      };
    };

    nginx = {
      enable = true;
      virtualHosts."deepthought.4amlunch.net" = {
        #        addSSL = true;
        #        enableACME = true;
        locations."/grafana/" = {
          proxyPass = "http://${toString config.services.grafana.settings.server.http_addr}:${toString config.services.grafana.settings.server.http_port}";
          proxyWebsockets = true;
          recommendedProxySettings = true;
        };
      };
    };

    prometheus = {
      enable = true;
      globalConfig.scrape_interval = "15s";
      exporters = {
        node = {
          enable = true;
          enabledCollectors = [ "systemd" ];
        };
        zfs = {
          enable = true;
          pools = [
            "rpool"
            "zpool"
          ];
        };
        systemd = {
          enable = true;
        };
        smokeping = {
          enable = true;
          hosts = [
            "8.8.8.8"
            "10.42.0.1"
            "192.168.99.30"
          ];
        };
        smartctl = {
          enable = true;
          devices = [
            "/dev/nvme0n1"
            "/dev/nvme1n1"
          ];
        };
        nginx = {
          enable = true;
        };
        #unifi = {
        #  enable = true;
        #  unifiUsername = "wonko";
        #  unifiPassword = "password";
        #  unifiAddress = "https://10.42.0.2:8443";
        #};
      };
      scrapeConfigs = [
        {
          job_name = "deepthought";
          static_configs = [
            {
              targets = [
                "127.0.0.1:${toString config.services.prometheus.exporters.node.port}"
                "127.0.0.1:9835"
              ];
            }
          ];
        }
        {
          job_name = "sierra";
          static_configs = [
            {
              targets = [
                "10.42.0.251:9100"
              ];
            }
          ];
        }
      ];
    };

    #loki = {
    #  enable = true;
    #  configFile = ./loki-config.json;
    #};
  };

  #systemd.services.promtail = {
  #  description = "Promtail service for Loki";
  #  wantedBy = [ "multi-user.target" ];
  #
  #    serviceConfig = {
  #      ExecStart = ''
  #        ${pkgs.grafana-loki}/bin/promtail --config.file ${./promtail.yaml}
  #      '';
  #    };
  #  };
}
