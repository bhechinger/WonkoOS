{
  lib,
  pkgs,
  ...
}:

let
  mkOpnsenseDnsUpdate = import ../../../common/opnsense-dns-update.nix { inherit lib pkgs; };
  mkBobDnsUpdate =
    hostname:
    mkOpnsenseDnsUpdate {
      inherit hostname;
      value = "10.42.0.2";
    };
in
{
  sops.secrets.opnsense-api-netrc = {
    sopsFile = ../secrets/opnsense.sops;
    format = "yaml";
    key = "netrc";
    mode = "0400";
  };

  systemd.services = {
    opnsense-dns-bob = mkBobDnsUpdate "bob";
    opnsense-dns-cache = mkBobDnsUpdate "cache";
    opnsense-dns-jackett = mkBobDnsUpdate "jackett";
    opnsense-dns-minecraft = mkBobDnsUpdate "minecraft";
    opnsense-dns-paperless = mkBobDnsUpdate "paperless";
    opnsense-dns-pwppp = mkBobDnsUpdate "pwppp";
    opnsense-dns-pwppp-txt = mkOpnsenseDnsUpdate {
      hostname = "pwppp";
      recordType = "TXT";
      value = "local-direct";
    };
    opnsense-dns-rutorrent = mkBobDnsUpdate "rutorrent";
    opnsense-dns-sonarr = mkBobDnsUpdate "sonarr";
    opnsense-dns-voice = mkBobDnsUpdate "voice";
  };
}
