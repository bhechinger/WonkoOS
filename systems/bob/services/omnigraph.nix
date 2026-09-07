{
  config,
  lib,
  pkgs,
  ...
}:

let
  omnigraph = pkgs.callPackage ../../../packages/omnigraph.nix { };
  graphIds = [
    "dev"
    "gevulot"
    "nix"
    "projects"
    "shared"
  ];
  cookbooks = pkgs.fetchFromGitHub {
    owner = "ModernRelay";
    repo = "omnigraph-cookbooks";
    rev = "cb7870d8e798e2fe07a2da3ac65ffce62ef37a5e";
    hash = "sha256-INOcTKqJ6hB/TOOs+60SCkwI1HLmlc3qfbb/4/3dWF4=";
  };
  clusterConfig = (pkgs.formats.yaml { }).generate "cluster.yaml" {
    version = 1;
    metadata.name = "dev-graph";
    storage = "/var/lib/omnigraph/cluster";
    state = {
      backend = "cluster";
      lock = true;
    };
    graphs = lib.genAttrs graphIds (_: {
      schema = "schema.pg";
      queries = "queries/";
    });
    policies = {
      graph = {
        file = "policies/graph.yaml";
        applies_to = graphIds;
      };
      server = {
        file = "policies/server.yaml";
        applies_to = [ "cluster" ];
      };
    };
  };
  cluster = pkgs.runCommand "omnigraph-dev-graph-cluster" { nativeBuildInputs = [ omnigraph ]; } ''
    mkdir -p "$out/policies"
    ln -s ${clusterConfig} "$out/cluster.yaml"
    ln -s ${cookbooks}/dev-graph/schema.pg "$out/schema.pg"
    cp -r --no-preserve=mode ${cookbooks}/dev-graph/queries "$out/queries"
    ln -s ${./omnigraph-context.gq} "$out/queries/omnigraph-context.gq"
    ln -s ${cookbooks}/deploy/railway/config/policy.railway.yaml "$out/policies/graph.yaml"
    ln -s ${cookbooks}/deploy/railway/config/server.policy.railway.yaml "$out/policies/server.yaml"
    omnigraph cluster validate --config "$out"
  '';
in
{
  environment.systemPackages = [ omnigraph ];

  sops.secrets.omnigraph-bearer-tokens = {
    sopsFile = ../secrets/omnigraph.tokens.sops;
    format = "binary";
    mode = "0400";
    restartUnits = [ "omnigraph.service" ];
  };

  systemd.services.omnigraph = {
    description = "OmniGraph graph database";
    after = [ "sops-install-secrets.service" ];
    requires = [ "sops-install-secrets.service" ];
    wantedBy = [ "multi-user.target" ];
    environment.OMNIGRAPH_SERVER_BEARER_TOKENS_FILE = "%d/tokens.json";
    preStart = ''
      if ! import_output="$(${lib.getExe omnigraph} cluster import --config ${cluster} 2>&1)"; then
        if ! ${lib.getExe pkgs.gnugrep} -q state_already_exists <<<"$import_output"; then
          printf '%s\n' "$import_output" >&2
          exit 1
        fi
      fi
      ${lib.getExe omnigraph} cluster apply --config ${cluster} --as act-admin
    '';
    serviceConfig = {
      AmbientCapabilities = "";
      CapabilityBoundingSet = "";
      DynamicUser = true;
      ExecStart = "${omnigraph}/bin/omnigraph-server --cluster ${cluster} --bind 127.0.0.1:18085 --require-all-graphs";
      IPAddressAllow = "localhost";
      IPAddressDeny = "any";
      LoadCredential = [ "tokens.json:${config.sops.secrets.omnigraph-bearer-tokens.path}" ];
      LockPersonality = true;
      MemoryDenyWriteExecute = true;
      NoNewPrivileges = true;
      PrivateDevices = true;
      PrivateTmp = true;
      ProtectClock = true;
      ProtectControlGroups = true;
      ProtectHome = true;
      ProtectHostname = true;
      ProtectKernelLogs = true;
      ProtectKernelModules = true;
      ProtectKernelTunables = true;
      ProtectSystem = "strict";
      Restart = "on-failure";
      RestartSec = "5s";
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
        "AF_UNIX"
      ];
      RestrictNamespaces = true;
      RestrictRealtime = true;
      RestrictSUIDSGID = true;
      StateDirectory = "omnigraph";
      StateDirectoryMode = "0700";
      UMask = "0077";
    };
  };
}
