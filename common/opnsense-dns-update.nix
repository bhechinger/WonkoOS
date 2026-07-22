{ lib, pkgs }:

{ records }:

let
  recordsFile = pkgs.writeText "opnsense-bind-records.json" (builtins.toJSON records);
  sync = pkgs.writeShellApplication {
    name = "opnsense-bind-dns-sync";
    runtimeInputs = with pkgs; [
      curl
      jq
    ];
    text = ''
      export OPNSENSE_URL=https://sierra.4amlunch.net
      export OPNSENSE_NETRC=/run/secrets/opnsense-api-netrc
      export DNS_ZONE=4amlunch.net
      ${builtins.readFile ../scripts/opnsense-dns-sync.sh}
    '';
  };
in
{
  description = "Reconcile the internal 4amlunch.net BIND zone";
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
    ExecStart = "${lib.getExe' pkgs.util-linux "flock"} --wait 30 /run/opnsense-dns-sync.lock ${lib.getExe sync} ${recordsFile}";
  };
}
