{ pkgs, ... }:

{
  home.packages = with pkgs; [
    fira-code
    glab
    gdb
    lldb
    autoconf
    automake
    rustup
    #google-cloud-sdk-gce
    #(google-cloud-sdk.withExtraComponents [google-cloud-sdk.components.gke-gcloud-auth-plugin])
    podman
    podman-compose
    graphviz
    grpcurl
    act
    action-validator
    gcc
    zed-editor
  ];

  programs = {
    gh.enable = true;
    go.enable = true;
    zellij.enable = true;
  };
}
