{
  lib,
  pkgs,
  ...
}:

let
  mkOpnsenseDnsSync = import ../../../common/opnsense-dns-update.nix { inherit lib pkgs; };
  bobServices = [
    "bob"
    "cache"
    "jackett"
    "minecraft"
    "paperless"
    "pwppp"
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
      name = "lan";
      type = "NS";
      value = "sierra.4amlunch.net.";
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
  ]
  ++ map (name: {
    inherit name;
    type = "A";
    value = "10.42.0.2";
  }) bobServices;
in
{
  sops.secrets.opnsense-api-netrc = {
    sopsFile = ../secrets/opnsense.sops;
    format = "yaml";
    key = "netrc";
    mode = "0400";
  };

  systemd.services.opnsense-dns-sync = mkOpnsenseDnsSync { inherit records; };
}
