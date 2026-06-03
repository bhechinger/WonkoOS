{ pkgs, unstable-pkgs, ... }:

{
  home.packages = with pkgs; [
    act
    unstable-pkgs.codex
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
    act
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
      #enableZshIntegration = true;
    };
    git = {
      enable = true;
      lfs.enable = true;
    };
  };
}
