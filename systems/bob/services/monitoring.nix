{
  config,
  lib,
  pkgs,
  ...
}:

let
  nodeDashboardSource = pkgs.fetchurl {
    url = "https://grafana.com/api/dashboards/1860/revisions/45/download";
    hash = "sha256-GExrdAnzBtp1Ul13cvcZRbEM6iOtFrXXjEaY6g6lGYY=";
  };
  nodeDashboard = pkgs.runCommand "node-exporter-full.json" { nativeBuildInputs = [ pkgs.jq ]; } ''
    jq 'del(.id)' ${nodeDashboardSource} > "$out"
  '';
  minecraftDashboardSource = pkgs.fetchurl {
    url = "https://grafana.com/api/dashboards/22017/revisions/1/download";
    hash = "sha256-it/gUa24vIIZfDeW3QvvHnWIhBcqAsaGZDRcJNydxsc=";
  };
  minecraftDashboard = pkgs.runCommand "minecraft-server.json" { nativeBuildInputs = [ pkgs.jq ]; } ''
    jq '
      del(.id, .__inputs)
      | walk(if . == "$" + "{DS_BONSAI}" then "mimir" else . end)
    ' ${minecraftDashboardSource} > "$out"
  '';
  dashboards = pkgs.linkFarm "grafana-dashboards" [
    {
      name = "minecraft-server.json";
      path = minecraftDashboard;
    }
    {
      name = "node-exporter-full.json";
      path = nodeDashboard;
    }
  ];
in
{
  sops.secrets = {
    grafana-admin-password = {
      sopsFile = ../secrets/grafana.sops;
      owner = "grafana";
      mode = "0400";
      restartUnits = [ "grafana.service" ];
    };
    grafana-secret-key = {
      sopsFile = ../secrets/grafana.sops;
      owner = "grafana";
      mode = "0400";
      restartUnits = [ "grafana.service" ];
    };
  };

  services = {
    prometheus.exporters.node = {
      enable = true;
      enabledCollectors = [
        "processes"
        "systemd"
      ];
      listenAddress = "127.0.0.1";
      openFirewall = false;
    };

    mimir = {
      enable = true;
      configuration = {
        target = "all";
        multitenancy_enabled = false;
        blocks_storage = {
          backend = "filesystem";
          bucket_store.sync_dir = "/var/lib/mimir/tsdb-sync";
          filesystem.dir = "/var/lib/mimir/data/tsdb";
          tsdb.dir = "/var/lib/mimir/tsdb";
        };
        compactor = {
          data_dir = "/var/lib/mimir/compactor";
          sharding_ring.kvstore.store = "memberlist";
        };
        distributor.ring = {
          instance_addr = "127.0.0.1";
          kvstore.store = "memberlist";
        };
        ingester.ring = {
          instance_addr = "127.0.0.1";
          kvstore.store = "memberlist";
          replication_factor = 1;
        };
        limits.compactor_blocks_retention_period = "30d";
        memberlist.bind_addr = [ "127.0.0.1" ];
        frontend.address = "127.0.0.1";
        query_scheduler.ring.instance_addr = "127.0.0.1";
        ruler_storage = {
          backend = "filesystem";
          filesystem.dir = "/var/lib/mimir/rules";
        };
        server = {
          http_listen_address = "127.0.0.1";
          http_listen_port = 9009;
          grpc_listen_address = "127.0.0.1";
          grpc_listen_port = 9095;
        };
        store_gateway.sharding_ring = {
          instance_addr = "127.0.0.1";
          replication_factor = 1;
        };
      };
    };

    loki = {
      enable = true;
      configuration = {
        auth_enabled = false;
        server = {
          http_listen_address = "10.42.0.2";
          http_listen_port = 3100;
          grpc_listen_address = "127.0.0.1";
          grpc_listen_port = 9096;
        };
        common = {
          instance_addr = "127.0.0.1";
          path_prefix = "/var/lib/loki";
          replication_factor = 1;
          ring.kvstore.store = "inmemory";
          storage.filesystem = {
            chunks_directory = "/var/lib/loki/chunks";
            rules_directory = "/var/lib/loki/rules";
          };
        };
        schema_config.configs = [
          {
            from = "2024-01-01";
            store = "tsdb";
            object_store = "filesystem";
            schema = "v13";
            index = {
              prefix = "index_";
              period = "24h";
            };
          }
        ];
        limits_config = {
          allow_structured_metadata = true;
          retention_period = "720h";
        };
        compactor = {
          working_directory = "/var/lib/loki/retention";
          delete_request_store = "filesystem";
          retention_enabled = true;
        };
      };
    };

    tempo = {
      enable = true;
      settings = {
        server = {
          http_listen_address = "127.0.0.1";
          http_listen_port = 3200;
          grpc_listen_address = "127.0.0.1";
          grpc_listen_port = 9097;
        };
        distributor.receivers.otlp.protocols = {
          grpc.endpoint = "127.0.0.1:4317";
          http.endpoint = "127.0.0.1:4318";
        };
        storage.trace = {
          backend = "local";
          wal.path = "/var/lib/tempo/wal";
          local.path = "/var/lib/tempo/blocks";
        };
        compactor.compaction.block_retention = "720h";
      };
    };

    alloy = {
      enable = true;
      extraFlags = [ "--server.http.listen-addr=127.0.0.1:12345" ];
    };

    grafana = {
      enable = true;
      settings = {
        server = {
          http_addr = "127.0.0.1";
          http_port = 3000;
          domain = "grafana.4amlunch.net";
          enforce_domain = true;
          root_url = "https://grafana.4amlunch.net/";
        };
        security = {
          admin_user = "admin";
          admin_password = "$__file{${config.sops.secrets.grafana-admin-password.path}}";
          secret_key = "$__file{${config.sops.secrets.grafana-secret-key.path}}";
          cookie_secure = true;
        };
        users = {
          allow_sign_up = false;
          allow_org_create = false;
        };
        "auth.anonymous".enabled = false;
      };
      provision = {
        enable = true;
        datasources.settings = {
          apiVersion = 1;
          prune = true;
          datasources = [
            {
              name = "Mimir";
              type = "prometheus";
              uid = "mimir";
              url = "http://127.0.0.1:9009/prometheus";
              isDefault = true;
              editable = false;
            }
            {
              name = "Loki";
              type = "loki";
              uid = "loki";
              url = "http://10.42.0.2:3100";
              editable = false;
            }
            {
              name = "Tempo";
              type = "tempo";
              uid = "tempo";
              url = "http://127.0.0.1:3200";
              editable = false;
            }
          ];
        };
        dashboards.settings = {
          apiVersion = 1;
          providers = [
            {
              name = "observability";
              folder = "Observability";
              disableDeletion = true;
              editable = false;
              options.path = dashboards;
            }
          ];
        };
      };
    };
  };

  environment.etc."alloy/config.alloy".text = ''
    prometheus.remote_write "mimir" {
      endpoint {
        url = "http://127.0.0.1:9009/api/v1/push"
      }
    }

    prometheus.scrape "nodes" {
      targets = [
        {"__address__" = "127.0.0.1:9100", "instance" = "bob", "job" = "node"},
        {"__address__" = "10.42.0.10:9100", "instance" = "deepthought", "job" = "node"},
        {"__address__" = "10.42.0.251:9100", "instance" = "sierra", "job" = "node"},
      ]
      scrape_interval = "15s"
      forward_to = [prometheus.remote_write.mimir.receiver]
    }

    prometheus.scrape "minecraft" {
      targets = [
        {"__address__" = "127.0.0.11:19565", "instance" = "pwppp", "job" = "minecraft"},
        {"__address__" = "127.0.0.12:19565", "instance" = "gigglesomething", "job" = "minecraft"},
      ]
      scrape_interval = "15s"
      forward_to = [prometheus.remote_write.mimir.receiver]
    }

    loki.write "local" {
      endpoint {
        url = "http://10.42.0.2:3100/loki/api/v1/push"
      }
    }

    loki.relabel "journal" {
      forward_to = []

      rule {
        source_labels = ["__journal__systemd_unit"]
        regex = "minecraft-server-(pwppp|gigglesomething)\\.service"
        action = "drop"
      }

      rule {
        source_labels = ["__journal__systemd_unit"]
        target_label = "unit"
      }
    }

    loki.source.journal "system" {
      labels = {"host" = "bob", "job" = "systemd-journal"}
      max_age = "1h"
      relabel_rules = loki.relabel.journal.rules
      forward_to = [loki.write.local.receiver]
    }

    loki.source.file "minecraft" {
      targets = [
        {
          "__path__" = "/var/lib/minecraft/pwppp/logs/latest.log",
          "host" = "bob",
          "job" = "minecraft",
          "minecraft_server" = "pwppp",
        },
        {
          "__path__" = "/var/lib/minecraft/gigglesomething/logs/latest.log",
          "host" = "bob",
          "job" = "minecraft",
          "minecraft_server" = "gigglesomething",
        },
      ]
      tail_from_end = true
      forward_to = [loki.write.local.receiver]
    }

    otelcol.receiver.otlp "lan" {
      grpc {
        endpoint = "10.42.0.2:4317"
      }
      http {
        endpoint = "10.42.0.2:4318"
      }
      output {
        traces = [otelcol.processor.batch.traces.input]
      }
    }

    otelcol.processor.batch "traces" {
      output {
        traces = [otelcol.exporter.otlp.tempo.input]
      }
    }

    otelcol.exporter.otlp "tempo" {
      client {
        endpoint = "127.0.0.1:4317"
        tls {
          insecure = true
        }
      }
    }
  '';

  users.groups.minecraft-logs = { };

  systemd = {
    services = {
      alloy-log-access = {
        description = "Grant Alloy read-only access to collected logs";
        before = [ "alloy.service" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig.Type = "oneshot";
        path = [ pkgs.acl ];
        script = ''
          journal_dir="/var/log/journal/$(cat /etc/machine-id)"
          if [ -d "$journal_dir" ]; then
            setfacl -m d:g:systemd-journal:r-X "$journal_dir"
            for journal in "$journal_dir"/user-*.journal; do
              [ ! -e "$journal" ] || setfacl -m g:systemd-journal:r-- "$journal"
            done
          fi

          for path in \
            /var/lib/minecraft \
            /var/lib/minecraft/pwppp \
            /var/lib/minecraft/gigglesomething
          do
            setfacl -m g:minecraft-logs:--x "$path"
          done
          for path in \
            /var/lib/minecraft/pwppp/logs \
            /var/lib/minecraft/gigglesomething/logs
          do
            setfacl -R -m g:minecraft-logs:r-X "$path"
            setfacl -m d:g:minecraft-logs:r-X "$path"
          done
        '';
      };
      alloy = {
        after = [
          "loki.service"
          "alloy-log-access.service"
          "mimir.service"
          "tempo.service"
        ];
        wants = [
          "loki.service"
          "alloy-log-access.service"
          "mimir.service"
          "tempo.service"
        ];
        serviceConfig.SupplementaryGroups = lib.mkAfter [ "minecraft-logs" ];
      };
      grafana = {
        after = [
          "loki.service"
          "mimir.service"
          "tempo.service"
        ];
        wants = [
          "loki.service"
          "mimir.service"
          "tempo.service"
        ];
      };
    };
  };
}
