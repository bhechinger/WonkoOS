{ lib, pkgs }:

let
  sync = pkgs.writeShellApplication {
    name = "opnsense-dns-sync";
    runtimeInputs = with pkgs; [
      curl
      jq
    ];
    text = ''
      export OPNSENSE_URL=https://sierra.4amlunch.net
      export OPNSENSE_NETRC=/run/secrets/opnsense-api-netrc
      export OPNSENSE_PINNED_PUBLIC_KEY="sha256//F4l/+Ixg/E7gUdrN/knO5vkZV7J6gzRhSm27bTS+vWE="
      export DNS_DOMAIN=4amlunch.net
      export DNS_TYPE=A
      export DNS_DESCRIPTION="Managed by WonkoOS"
      ${builtins.readFile ../scripts/opnsense-dns-sync.sh}
    '';
  };
in
{ hostname, address }:
{
  description = "Update OPNsense DNS for ${hostname}.4amlunch.net";
  after = [
    "network-online.target"
    "sops-install-secrets.service"
  ];
  requires = [ "sops-install-secrets.service" ];
  wants = [ "network-online.target" ];
  wantedBy = [ "multi-user.target" ];
  serviceConfig = {
    Type = "oneshot";
    RemainAfterExit = true;
    # ponytail: host-local lock; centralize updates if cross-host races become real.
    ExecStart = "${lib.getExe' pkgs.util-linux "flock"} --wait 30 /run/opnsense-dns-sync.lock ${lib.getExe sync} ${
      lib.escapeShellArgs [
        hostname
        address
      ]
    }";
  };
}
