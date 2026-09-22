{
  lib,
  pkgs,
  unstable-pkgs,
  ...
}:

let
  rustupWithoutDynamicPatchelf = pkgs.rustup.overrideAttrs (old: {
    patches =
      let
        patches = old.patches or [ ];
        isDynamicPatchelfPatch =
          patch: lib.hasSuffix "dynamically-patchelf-binaries.patch" (toString patch);
      in
      assert lib.count isDynamicPatchelfPatch patches == 1;
      lib.filter (patch: !isDynamicPatchelfPatch patch) patches;
  });
in
{
  home.packages = with pkgs; [
    act
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
    rustupWithoutDynamicPatchelf
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
    unstable-pkgs.gram
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
