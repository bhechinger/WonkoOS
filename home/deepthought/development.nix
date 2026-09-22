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
  home.activation.reinstallPatchedRustupToolchains = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    rustup=${rustupWithoutDynamicPatchelf}/bin/rustup
    for toolchain_dir in "$HOME/.rustup/toolchains/"*; do
      [[ -d "$toolchain_dir" && ! -L "$toolchain_dir" ]] || continue
      [[ "$toolchain_dir" != *.before-nix-ld-migration ]] || continue
      rustc="$toolchain_dir/bin/rustc"
      [[ -x "$rustc" ]] || continue
      interpreter="$(${pkgs.patchelf}/bin/patchelf --print-interpreter "$rustc" 2>/dev/null || true)"
      if [[ "$interpreter" == /nix/store/* ]]; then
        toolchain="$(basename "$toolchain_dir")"
        mapfile -t components < <($rustup component list --installed --toolchain "$toolchain")
        mapfile -t targets < <($rustup target list --installed --toolchain "$toolchain")
        if (( ''${#components[@]} == 0 || ''${#targets[@]} == 0 )); then
          _iError "Could not inventory Rustup toolchain %s" "$toolchain"
          exit 1
        fi
        optional_components=()
        for component in "''${components[@]}"; do
          for target in "''${targets[@]}"; do
            component="''${component%-$target}"
          done
          case "$component" in
            cargo | rustc | rust-std) ;;
            llvm-tools) optional_components+=(llvm-tools-preview) ;;
            *) optional_components+=("$component") ;;
          esac
        done
        install_args=(toolchain install "$toolchain" --profile minimal)
        if (( ''${#optional_components[@]} )); then
          install_args+=(--component "$(IFS=,; printf '%s' "''${optional_components[*]}")")
        fi
        install_args+=(--target "$(IFS=,; printf '%s' "''${targets[*]}")")
        backup_dir="$toolchain_dir.before-nix-ld-migration"
        if [[ -e "$backup_dir" ]]; then
          _iError "Refusing to overwrite Rustup migration backup %s" "$backup_dir"
          exit 1
        fi
        if [[ -v DRY_RUN ]]; then
          run mv "$toolchain_dir" "$backup_dir"
          run $rustup "''${install_args[@]}"
          run rm -rf "$backup_dir"
        else
          mv "$toolchain_dir" "$backup_dir"
          if ! $rustup "''${install_args[@]}"; then
            rm -rf "$toolchain_dir"
            mv "$backup_dir" "$toolchain_dir"
            exit 1
          fi
          rm -rf "$backup_dir"
        fi
      fi
    done
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
