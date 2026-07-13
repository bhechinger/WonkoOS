{
  pkgs,
  unstable-pkgs,
  ...
}:

let
  codex = pkgs.writeShellScriptBin "codex" ''
    exec ${unstable-pkgs.codex}/bin/codex \
      -c 'shell_environment_policy.exclude=["GITHUB_PAT_TOKEN","GITHUB_TOKEN","GH_TOKEN","GITHUB_PERSONAL_ACCESS_TOKEN"]' \
      -c 'shell_environment_policy.allow_login_shell=false' \
      "$@"
  '';
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
in
{
  home.packages = with pkgs; [
    act
    codex
    codexGithubMcp
    nodejs
    unstable-pkgs.opencode
    unstable-pkgs.zed-editor
    cloc
    nil
    nixd
    just
    openssl
    fira-code
    glab
    gdb
    lldb
    autoconf
    automake
    rustup
    (google-cloud-sdk.withExtraComponents [ google-cloud-sdk.components.gke-gcloud-auth-plugin ])
    podman
    podman-compose
    graphviz
    grpcurl
    action-validator
    gcc
    k8sgpt
    skopeo
    circleci-cli
  ];

  programs = {
    asciinema.enable = true;
    gh.enable = true;
    go.enable = true;
    zellij = {
      enable = true;
    };
    git = {
      enable = true;
      lfs.enable = true;
    };
  };
}
