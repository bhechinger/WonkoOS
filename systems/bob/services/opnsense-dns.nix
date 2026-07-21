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
      address = "10.42.0.2";
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
    opnsense-dns-jackett = mkBobDnsUpdate "jackett";
    opnsense-dns-paperless = mkBobDnsUpdate "paperless";
    opnsense-dns-rutorrent = mkBobDnsUpdate "rutorrent";
    opnsense-dns-sonarr = mkBobDnsUpdate "sonarr";
  };
}
