{
  pkgs,
  unstable-pkgs,
  ...
}:

let
  codexGithubMcp = pkgs.writeShellApplication {
    name = "codex-github-mcp";
    runtimeInputs = with pkgs; [
      gh
      github-mcp-server
    ];
    text = ''
      if ! GITHUB_PERSONAL_ACCESS_TOKEN="$(gh auth token)"; then
        echo "codex-github-mcp: GitHub authentication is unavailable; run 'gh auth login'" >&2
        exit 1
      fi
      export GITHUB_PERSONAL_ACCESS_TOKEN
      exec github-mcp-server stdio
    '';
  };
  omnigraph = pkgs.callPackage ../../packages/omnigraph.nix { };
in
{
  home.packages = with pkgs; [
    unstable-pkgs.codex
    codexGithubMcp
    gh
    nodejs
    omnigraph
  ];

  home.file.".omnigraph/config.yaml".text = ''
    servers:
      bob:
        url: https://omnigraph.4amlunch.net
    defaults:
      server: bob
      output: table
  '';

  home.file.".codex/rules/omnigraph.rules".text = ''
    prefix_rule(pattern = ["omnigraph"], decision = "allow")
  '';

  home.file.".agents/skills/omnigraph-context" = {
    source = ./skills/omnigraph-context;
    force = true;
  };
}
