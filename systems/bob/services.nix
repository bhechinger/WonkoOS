{
  config,
  lib,
  pkgs,
  ...
}:

let
  restoreMarker = "/var/lib/bob-restored";
  certificateDirectory = "/home/docker/reverse/certs/4amlunch.net";
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
    sslCertificate = "${certificateDirectory}/fullchain.pem";
    sslCertificateKey = "${certificateDirectory}/privkey.pem";
  };
  dockerFirewall = pkgs.writeShellApplication {
    name = "bob-docker-firewall";
    runtimeInputs = [ pkgs.iptables ];
    text = ''
      chain=BOB-DOCKER

      iptables -w -N "$chain" 2>/dev/null || true
      iptables -w -F "$chain"
      if ! iptables -w -C DOCKER-USER -j "$chain" 2>/dev/null; then
        iptables -w -I DOCKER-USER 1 -j "$chain"
      fi

      iptables -w -A "$chain" -i management -p tcp \
        -m conntrack --ctorigdstport 8080 -j ACCEPT
      for port in 3478 10001 1900 5514; do
        iptables -w -A "$chain" -i management -p udp \
          -m conntrack --ctorigdstport "$port" -j ACCEPT
      done
      iptables -w -A "$chain" -i management -j DROP
    '';
  };
  bobRestore = pkgs.writeShellApplication {
    name = "bob-restore";
    runtimeInputs = with pkgs; [
      coreutils
      docker
      findutils
      gnugrep
      gnused
      rsync
      config.services.postgresql.package
      systemd
      util-linux
    ];
    text = builtins.readFile ./restore.sh;
  };
in
{
  environment.systemPackages = [ bobRestore ];

  networking.extraHosts = ''
    127.0.0.1 reverse paperless jackett sonarr
  '';

  services = {
    avahi = {
      enable = true;
      nssmdns4 = true;
    };

    jackett = {
      enable = true;
      dataDir = "/home/docker/jackett/config/Jackett";
      group = "media";
      openFirewall = false;
      user = "media";
    };

    murmur = {
      enable = true;
      environmentFile = "/var/lib/mumble-server/murmurd.env";
      openFirewall = false;
      password = "$MURMURD_PASSWORD";
      stateDir = "/var/lib/mumble-server";
    };

    nfs.server = {
      enable = true;
      exports = ''
        /home/docker/paperless/consume 10.42.0.10(rw,sync,no_subtree_check,root_squash)
        /home/docker/paperless/export 10.42.0.10(rw,sync,no_subtree_check,root_squash)
      '';
    };

    nginx = {
      enable = true;
      recommendedProxySettings = true;
      recommendedTlsSettings = true;
      upstreams.paperless.servers."127.0.0.1:8000" = { };
      virtualHosts = {
        "basket.4amlunch.net" = tls // {
          serverAliases = [
            "basket"
            "basket.4amlunch.internal"
          ];
          locations."/".proxyPass = "https://10.42.0.30:8443";
        };
        "bob.4amlunch.net" = tls // {
          serverAliases = [
            "bob"
            "bob.4amlunch.internal"
          ];
          root = "/home/docker/reverse/html";
        };
        "hamburgerking.pt".root = "/home/docker/reverse/html/hbk";
        "jackett.4amlunch.net" = tls // {
          serverAliases = [
            "jackett"
            "jackett.4amlunch.internal"
          ];
          locations."/".proxyPass = "http://127.0.0.1:9117";
        };
        "paperless.4amlunch.net" = tls // {
          serverAliases = [
            "paperless"
            "paperless.4amlunch.internal"
          ];
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
          serverAliases = [
            "rutorrent"
            "rutorrent.4amlunch.internal"
          ];
        };
        "sonarr.4amlunch.net" = tls // {
          serverAliases = [
            "sonarr"
            "sonarr.4amlunch.internal"
          ];
          locations."/".proxyPass = "http://127.0.0.1:8989";
        };
      };
    };

    paperless = {
      enable = true;
      address = "127.0.0.1";
      port = 8000;
      dataDir = "/home/docker/paperless/data";
      mediaDir = "/home/docker/paperless/media";
      consumptionDir = "/home/docker/paperless/consume";
      consumptionDirIsPublic = true;
      database.createLocally = true;
      environmentFile = "/home/wonko/docker/paperless.env";
      # Include both installed OCR languages. paperless.env keeps English as
      # the existing runtime default.
      settings.PAPERLESS_OCR_LANGUAGE = "eng+por";
    };

    plex = {
      enable = true;
      dataDir = "/var/lib/plexmediaserver/Library/Application Support";
      openFirewall = false;
    };

    postfix = {
      enable = true;
      rootAlias = "wonko";
      settings.main = {
        append_dot_mydomain = "no";
        inet_interfaces = [ "all" ];
        inet_protocols = [ "all" ];
        mailbox_size_limit = "0";
        mydestination = [
          "$myhostname"
          "bob.4amlunch.net"
          "bob"
          "localhost.localdomain"
          "localhost"
        ];
        myhostname = "bob.4amlunch.net";
        mynetworks = [
          "127.0.0.0/8"
          "[::ffff:127.0.0.0]/104"
          "[::1]/128"
        ];
        recipient_delimiter = "+";
        relayhost = [ ];
        smtp_tls_security_level = "may";
        smtpd_relay_restrictions = [
          "permit_mynetworks"
          "permit_sasl_authenticated"
          "defer_unauth_destination"
        ];
        smtpd_tls_security_level = "may";
      };
    };

    postgresql = {
      dataDir = "/home/docker/pgsql/paperless";
      package = pkgs.postgresql_16;
    };

    rtorrent = {
      enable = true;
      downloadDir = "/nfs/Torrents";
      group = "nginx";
      openFirewall = false;
      user = "media";
    };

    rutorrent = {
      enable = true;
      hostName = "rutorrent.4amlunch.net";
      nginx.enable = true;
    };

    sonarr = {
      enable = true;
      group = "media";
      openFirewall = false;
      user = "media";
    };

    tailscale = {
      enable = true;
      openFirewall = false;
    };

    timesyncd.enable = true;

    zerotierone = {
      enable = true;
      joinNetworks = [ "a84ac5c10a853bc1" ];
    };
  };

  users = {
    groups.media.gid = 2000;
    users = {
      avahi.uid = 992;
      media = {
        description = "Shared media service account";
        group = "media";
        isSystemUser = true;
        uid = 999;
      };
      plex.extraGroups = [
        "render"
        "video"
      ];
    };
  };

  virtualisation = {
    docker = {
      enable = true;
      storageDriver = "zfs";
    };
    oci-containers = {
      backend = "docker";
      containers = {
        protonmail-bridge = {
          image = "shenxn/protonmail-bridge:latest";
          pull = "never";
          ports = [
            "1025:25"
            "1143:143"
          ];
          volumes = [ "protonmail:/root" ];
        };
        unifi-controller = {
          image = "lscr.io/linuxserver/unifi-controller:latest";
          pull = "never";
          environment = {
            MEM_LIMIT = "1024";
            MEM_STARTUP = "1024";
            PGID = "1000";
            PUID = "1000";
            TZ = "Etc/UTC";
          };
          ports = [
            "8443:8443"
            "3478:3478/udp"
            "10001:10001/udp"
            "8080:8080"
            "1900:1900/udp"
            "8843:8843"
            "8880:8880"
            "6789:6789"
            "5514:5514/udp"
          ];
          volumes = [ "/home/unifi/config:/config" ];
        };
      };
    };
  };

  systemd = {
    mounts = lib.mkIf (config.networking.hostName == "bob") [
      {
        what = "10.42.0.30:/Brian";
        where = "/nfs/Brian";
        type = "nfs4";
        mountConfig.Options = "noatime";
      }
      {
        what = "10.42.0.30:/Plex";
        where = "/nfs/Plex";
        type = "nfs4";
        mountConfig.Options = "noatime";
      }
      {
        what = "10.42.0.30:/Torrents";
        where = "/nfs/Torrents";
        type = "nfs4";
        mountConfig.Options = "noatime";
      }
    ];
    automounts = lib.mkIf (config.networking.hostName == "bob") [
      {
        where = "/nfs/Brian";
        wantedBy = [ "multi-user.target" ];
        automountConfig.TimeoutIdleSec = "600";
      }
      {
        where = "/nfs/Plex";
        wantedBy = [ "multi-user.target" ];
        automountConfig.TimeoutIdleSec = "600";
      }
      {
        where = "/nfs/Torrents";
        wantedBy = [ "multi-user.target" ];
        automountConfig.TimeoutIdleSec = "600";
      }
    ];

    services = {
      cloudflared-tunnel = {
        after = [
          "network-online.target"
          "nginx.service"
        ];
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];
        unitConfig.ConditionPathExists = [
          restoreMarker
          "/var/lib/cloudflared/tunnel.env"
        ];
        serviceConfig = {
          DynamicUser = true;
          EnvironmentFile = "/var/lib/cloudflared/tunnel.env";
          ExecStart = "${lib.getExe pkgs.cloudflared} tunnel --no-autoupdate run";
          Restart = "always";
          RestartSec = "5s";
        };
      };

      docker.postStart = lib.getExe dockerFirewall;
      docker-protonmail-bridge.unitConfig.ConditionPathExists = restoreMarker;
      docker-unifi-controller.unitConfig.ConditionPathExists = restoreMarker;

      jackett = {
        serviceConfig = {
          BindPaths = [ "/home/docker/jackett/downloads:/downloads" ];
          ReadWritePaths = [ "/home/docker/jackett/downloads" ];
        };
        unitConfig.ConditionPathExists = restoreMarker;
      };
      murmur.unitConfig.ConditionPathExists = restoreMarker;
      nginx.unitConfig.ConditionPathExists = [
        restoreMarker
        "${certificateDirectory}/fullchain.pem"
        "${certificateDirectory}/privkey.pem"
        "/var/lib/rutorrent/htpasswd"
      ];
      nginx.serviceConfig.ProtectHome = lib.mkForce "read-only";
      "nfs-server".unitConfig.ConditionPathExists = restoreMarker;
      paperless-consumer.unitConfig.ConditionPathExists = restoreMarker;
      paperless-scheduler.unitConfig.ConditionPathExists = restoreMarker;
      paperless-task-queue.unitConfig.ConditionPathExists = restoreMarker;
      paperless-web.unitConfig.ConditionPathExists = restoreMarker;
      phpfpm-rutorrent.unitConfig.ConditionPathExists = restoreMarker;
      plex.unitConfig.ConditionPathExists = restoreMarker;
      postfix.unitConfig.ConditionPathExists = restoreMarker;
      postgresql.unitConfig.ConditionPathExists = restoreMarker;
      postgresql.serviceConfig.ProtectHome = lib.mkForce "read-only";
      rtorrent = {
        after = lib.optionals (config.networking.hostName == "bob") [ "nfs-Torrents.mount" ];
        requires = lib.optionals (config.networking.hostName == "bob") [ "nfs-Torrents.mount" ];
        unitConfig.ConditionPathExists = restoreMarker;
      };
      rutorrent-setup.unitConfig.ConditionPathExists = restoreMarker;
      sonarr = {
        after = lib.optionals (config.networking.hostName == "bob") [
          "nfs-Plex.mount"
          "nfs-Torrents.mount"
        ];
        requires = lib.optionals (config.networking.hostName == "bob") [
          "nfs-Plex.mount"
          "nfs-Torrents.mount"
        ];
        unitConfig.ConditionPathExists = restoreMarker;
      };
      tailscaled.unitConfig.ConditionPathExists = restoreMarker;
      zerotierone.unitConfig.ConditionPathExists = restoreMarker;
    };

    tmpfiles.settings."10-bob-native-services" = {
      "/home/docker".z = {
        group = "-";
        mode = "0711";
        user = "-";
      };
      "/home/docker/jackett/downloads".d = {
        group = "media";
        mode = "0770";
        user = "media";
      };
      "/var/lib/rutorrent".z = {
        group = "rutorrent";
        mode = "0751";
        user = "root";
      };
      "/var/lib/rutorrent/htpasswd".z = {
        group = "nginx";
        mode = "0640";
        user = "root";
      };
      "/var/lib/sonarr/.config/NzbDrone".d = {
        group = "media";
        mode = "0750";
        user = "media";
      };
    };
  };
}
