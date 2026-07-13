{
  lib,
  pkgs,
  ...
}:

let
  restoreMarker = "/var/lib/bob-restored";
  compose = lib.getExe pkgs.docker-compose;
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
      systemd
    ];
    text = builtins.readFile ./restore.sh;
  };
  mkComposeService = directory: services: {
    after = [
      "docker.service"
      "network-online.target"
    ];
    requires = [ "docker.service" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    unitConfig.ConditionPathExists = [
      restoreMarker
      "${directory}/docker-compose.yaml"
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      WorkingDirectory = directory;
      ExecStart = "${compose} -f ${directory}/docker-compose.yaml up -d --pull never --remove-orphans ${lib.escapeShellArgs services}";
      ExecStop = "-${compose} -f ${directory}/docker-compose.yaml stop ${lib.escapeShellArgs services}";
      TimeoutStartSec = "infinity";
      TimeoutStopSec = "5min";
    };
  };
in
{
  environment.systemPackages = [ bobRestore ];

  services = {
    avahi = {
      enable = true;
      nssmdns4 = true;
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

    plex = {
      enable = true;
      dataDir = "/var/lib/plexmediaserver";
      openFirewall = false;
    };

    postfix = {
      enable = true;
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

  users.users.plex.extraGroups = [
    "render"
    "video"
  ];

  virtualisation.docker = {
    enable = true;
    storageDriver = "zfs";
  };

  systemd = {
    mounts = [
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
    ];
    automounts = [
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
    ];

    services = {
      compose-ad = mkComposeService "/home/wonko/AD" [ "app" ];
      compose-main = mkComposeService "/home/wonko/docker" [
        "reverse"
        "paperless"
        "paperless-db"
        "paperless-broker"
        "protonmail-bridge"
        "jackett"
        "geoip-updater"
        "tunnel"
      ];
      compose-unifi = mkComposeService "/home/wonko/unifi" [ "unifi-controller" ];

      docker.postStart = lib.getExe dockerFirewall;
      murmur.unitConfig.ConditionPathExists = restoreMarker;
      "nfs-server".unitConfig.ConditionPathExists = restoreMarker;
      plex.unitConfig.ConditionPathExists = restoreMarker;
      postfix.unitConfig.ConditionPathExists = restoreMarker;
      tailscaled.unitConfig.ConditionPathExists = restoreMarker;
      zerotierone.unitConfig.ConditionPathExists = restoreMarker;
    };
  };
}
