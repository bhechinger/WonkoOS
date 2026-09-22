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

  rustupToolchainMigration = pkgs.writeShellApplication {
    name = "rustup-toolchain-migration";
    runtimeInputs = [ pkgs.gawk ];
    text = builtins.readFile ./rustup-toolchain-migration.sh;
    checkPhase = ''
      runHook preCheck
      ${pkgs.bash}/bin/bash -n "$target"
      ${pkgs.shellcheck}/bin/shellcheck "$target" ${./rustup-toolchain-migration-test.sh}
      MIGRATION_SCRIPT="$target" ${pkgs.bash}/bin/bash ${./rustup-toolchain-migration-test.sh}
      runHook postCheck
    '';
  };
in
{
  home.activation.reinstallPatchedRustupToolchains = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${rustupToolchainMigration}/bin/rustup-toolchain-migration \
      ${rustupWithoutDynamicPatchelf}/bin/rustup \
      ${pkgs.patchelf}/bin/patchelf
  '';

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
