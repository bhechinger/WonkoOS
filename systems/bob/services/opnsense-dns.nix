{
  lib,
  pkgs,
  ...
}:

let
  mkOpnsenseDnsSync = import ../../../common/opnsense-dns-update.nix { inherit lib pkgs; };
  secondaryZones = [
    "0.42.10.in-addr.arpa"
    "11.42.10.in-addr.arpa"
    "4amlunch.net"
    "lan.4amlunch.net"
  ];
  bobServices = [
    "bob"
    "cache"
    "gigglesomething"
    "grafana"
    "jackett"
    "minecraft"
    "paperless"
    "pwppp"
    "restic"
    "restic-b2"
    "rutorrent"
    "sonarr"
    "voice"
  ];
  records = [
    {
      name = "@";
      type = "NS";
      value = "sierra.4amlunch.net.";
    }
    {
      name = "@";
      type = "NS";
      value = "bob.4amlunch.net.";
    }
    {
      name = "lan";
      type = "NS";
      value = "sierra.4amlunch.net.";
    }
    {
      name = "lan";
      type = "NS";
      value = "bob.4amlunch.net.";
    }
    {
      name = "basket";
      type = "A";
      value = "10.42.11.50";
    }
    {
      name = "sierra";
      type = "A";
      value = "10.42.0.251";
    }
    {
      name = "pwppp";
      type = "TXT";
      value = "local-direct";
    }
    {
      name = "gigglesomething";
      type = "TXT";
      value = "local-direct";
    }
  ]
  ++ map (name: {
    inherit name;
    type = "A";
    value = "10.42.0.2";
  }) bobServices;
  dnsSync = mkOpnsenseDnsSync { inherit records; };
in
{
  services.bind = {
    enable = true;
    ipv4Only = true;
    directory = "/var/lib/named";
    listenOn = [
      "127.0.0.1"
      "10.42.0.2"
      "10.42.11.2"
    ];
    listenOnIpv6 = [ "none" ];
    cacheNetworks = [
      "127.0.0.0/8"
      "10.42.0.0/24"
      "10.42.11.0/24"
    ];
    forwarders = [ ];
    zones = lib.genAttrs secondaryZones (name: {
      master = false;
      file = "${name}.db";
      masters = [ "10.42.0.251" ];
    });
  };

  sops.secrets.opnsense-api-netrc = {
    sopsFile = ../secrets/opnsense.sops;
    format = "yaml";
    key = "netrc";
    mode = "0400";
  };

  systemd.services.opnsense-dns-sync = dnsSync // {
    after = dnsSync.after ++ [ "bind.service" ];
  };
}
