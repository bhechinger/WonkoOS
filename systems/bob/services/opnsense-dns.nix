{
  config,
  lib,
  pkgs,
  ...
}:

let
  mkOpnsenseDnsUpdate = import ../../../common/opnsense-dns-update.nix { inherit lib pkgs; };
in
{
  sops = lib.mkIf (config.networking.hostName == "bob") {
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    secrets.opnsense-api-netrc = {
      sopsFile = ../secrets/opnsense.sops;
      format = "yaml";
      key = "netrc";
      mode = "0400";
    };
  };

  systemd.services.opnsense-dns-cache =
    lib.mkIf (config.networking.hostName == "bob")
      (mkOpnsenseDnsUpdate {
        hostname = "cache";
        address = "10.42.0.2";
      });
}
