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
    patchelf=${pkgs.patchelf}/bin/patchelf
    backup_suffix=.before-nix-ld-migration

    for backup_dir in "$HOME/.rustup/toolchains/"*"$backup_suffix"; do
      [[ -d "$backup_dir" && ! -L "$backup_dir" ]] || continue
      toolchain_dir="''${backup_dir%$backup_suffix}"
      if [[ ! -e "$toolchain_dir" ]]; then
        run mv "$backup_dir" "$toolchain_dir"
      elif [[ "$($patchelf --print-interpreter "$toolchain_dir/bin/rustc" 2>/dev/null || true)" == /lib64/ld-linux-x86-64.so.2 ]]; then
        run rm -rf "$backup_dir"
      else
        _iError "Refusing to choose between Rustup toolchain and migration backup %s" "$toolchain_dir"
        exit 1
      fi
    done

    for toolchain_dir in "$HOME/.rustup/toolchains/"*; do
      [[ -d "$toolchain_dir" && ! -L "$toolchain_dir" ]] || continue
      [[ "$toolchain_dir" != *"$backup_suffix" ]] || continue
      rustc="$toolchain_dir/bin/rustc"
      [[ -x "$rustc" ]] || continue
      interpreter="$($patchelf --print-interpreter "$rustc" 2>/dev/null || true)"
      if [[ "$interpreter" == /nix/store/* ]]; then
        toolchain="$(basename "$toolchain_dir")"
        mapfile -t components < <($rustup component list --installed --toolchain "$toolchain")
        mapfile -t targets < <($rustup target list --installed --toolchain "$toolchain")
        host=""
        for component in "''${components[@]}"; do
          if [[ "$component" == rustc-* ]]; then
            host="''${component#rustc-}"
            break
          fi
        done
        manifest="$toolchain_dir/lib/rustlib/multirust-channel-manifest.toml"
        date="$(${pkgs.gawk}/bin/awk -F '"' '/^date = / { print $2; exit }' "$manifest")"
        release="$(${pkgs.gawk}/bin/awk '
          $0 == "[pkg.rust]" { rust = 1; next }
          rust && /^version = / {
            split($0, fields, "\"")
            split(fields[2], version, " ")
            print version[1]
            exit
          }
        ' "$manifest")"
        if (( ''${#components[@]} == 0 || ''${#targets[@]} == 0 )) || [[ -z "$host" || -z "$date" || -z "$release" ]]; then
          _iError "Could not inventory Rustup toolchain %s" "$toolchain"
          exit 1
        fi
        case "$release" in
          *-nightly) source_toolchain="nightly-$date-$host" ;;
          *-beta) source_toolchain="beta-$date-$host" ;;
          *) source_toolchain="$release-$host" ;;
        esac
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
        install_args=(toolchain install "$source_toolchain" --profile minimal)
        if (( ''${#optional_components[@]} )); then
          install_args+=(--component "$(IFS=,; printf '%s' "''${optional_components[*]}")")
        fi
        install_args+=(--target "$(IFS=,; printf '%s' "''${targets[*]}")")
        backup_dir="$toolchain_dir$backup_suffix"
        if [[ -e "$backup_dir" ]]; then
          _iError "Refusing to overwrite Rustup migration backup %s" "$backup_dir"
          exit 1
        fi
        if [[ -v DRY_RUN ]]; then
          staging_dir="$HOME/.rustup/rustup-nix-ld-migration.XXXXXXXX"
          run ${pkgs.coreutils}/bin/env RUSTUP_HOME="$staging_dir/rustup" CARGO_HOME="$staging_dir/cargo" $rustup "''${install_args[@]}"
          run mv "$toolchain_dir" "$backup_dir"
          run mv "$staging_dir/rustup/toolchains/$source_toolchain" "$toolchain_dir"
          run rm -rf "$backup_dir" "$staging_dir"
        else
          staging_dir="$(mktemp -d "$HOME/.rustup/rustup-nix-ld-migration.XXXXXXXX")"
          staging_rustup="$staging_dir/rustup"
          if ! ${pkgs.coreutils}/bin/env RUSTUP_HOME="$staging_rustup" CARGO_HOME="$staging_dir/cargo" $rustup "''${install_args[@]}"; then
            rm -rf "$staging_dir"
            exit 1
          fi
          replacement_dirs=("$staging_rustup/toolchains/"*)
          if (( ''${#replacement_dirs[@]} != 1 )) || [[ ! -d "''${replacement_dirs[0]}" ]]; then
            _iError "Could not locate replacement Rustup toolchain %s" "$source_toolchain"
            rm -rf "$staging_dir"
            exit 1
          fi
          replacement_dir="''${replacement_dirs[0]}"
          replacement_interpreter="$($patchelf --print-interpreter "$replacement_dir/bin/rustc" 2>/dev/null || true)"
          if [[ "$replacement_interpreter" != /lib64/ld-linux-x86-64.so.2 ]] || ! "$replacement_dir/bin/rustc" --version >/dev/null; then
            _iError "Replacement Rustup toolchain %s does not use nix-ld" "$source_toolchain"
            rm -rf "$staging_dir"
            exit 1
          fi
          mv "$toolchain_dir" "$backup_dir"
          if ! mv "$replacement_dir" "$toolchain_dir"; then
            mv "$backup_dir" "$toolchain_dir"
            rm -rf "$staging_dir"
            exit 1
          fi
          rm -rf "$backup_dir" "$staging_dir"
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
