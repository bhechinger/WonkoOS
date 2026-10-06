rustup=$1
patchelf=$2
rustup_home=${RUSTUP_HOME:-$HOME/.rustup}
toolchains_dir="$rustup_home/toolchains"
backup_suffix=.before-nix-ld-migration
staging_dir=

cleanup_staging() {
  [[ -z "$staging_dir" ]] || rm -rf "$staging_dir"
}
trap cleanup_staging EXIT

[[ -d "$toolchains_dir" ]] || exit 0

for backup_dir in "$toolchains_dir/"*"$backup_suffix"; do
  [[ -d "$backup_dir" && ! -L "$backup_dir" ]] || continue
  toolchain_dir="${backup_dir%"$backup_suffix"}"
  if [[ ! -e "$toolchain_dir" ]]; then
    mv "$backup_dir" "$toolchain_dir"
  elif [[ "$("$patchelf" --print-interpreter "$toolchain_dir/bin/rustc" 2>/dev/null || true)" == /lib64/ld-linux-x86-64.so.2 ]]; then
    rm -rf "$backup_dir"
  else
    printf 'Refusing to choose between Rustup toolchain and migration backup: %s\n' "$toolchain_dir" >&2
    exit 1
  fi
done

for toolchain_dir in "$toolchains_dir/"*; do
  [[ -d "$toolchain_dir" && ! -L "$toolchain_dir" ]] || continue
  [[ "$toolchain_dir" != *"$backup_suffix" ]] || continue
  rustc="$toolchain_dir/bin/rustc"
  [[ -x "$rustc" ]] || continue
  interpreter="$("$patchelf" --print-interpreter "$rustc" 2>/dev/null || true)"
  [[ "$interpreter" == /nix/store/* ]] || continue

  toolchain="$(basename "$toolchain_dir")"
  mapfile -t components < <("$rustup" component list --installed --toolchain "$toolchain")
  mapfile -t targets < <("$rustup" target list --installed --toolchain "$toolchain")
  host=
  for component in "${components[@]}"; do
    if [[ "$component" == rustc-* ]]; then
      host="${component#rustc-}"
      break
    fi
  done
  manifest="$toolchain_dir/lib/rustlib/multirust-channel-manifest.toml"
  date="$(awk -F '"' '/^date = / { print $2; exit }' "$manifest")"
  release="$(awk '
    $0 == "[pkg.rust]" { rust = 1; next }
    rust && /^version = / {
      split($0, fields, "\"")
      split(fields[2], version, " ")
      print version[1]
      exit
    }
  ' "$manifest")"
  if (( ${#components[@]} == 0 || ${#targets[@]} == 0 )) || [[ -z "$host" || -z "$date" || -z "$release" ]]; then
    printf 'Could not inventory Rustup toolchain: %s\n' "$toolchain" >&2
    exit 1
  fi
  case "$release" in
    *-nightly) source_toolchain="nightly-$date-$host" ;;
    *-beta) source_toolchain="beta-$date-$host" ;;
    *) source_toolchain="$release-$host" ;;
  esac

  optional_components=()
  for component in "${components[@]}"; do
    for target in "${targets[@]}"; do
      component="${component%-"$target"}"
    done
    case "$component" in
      cargo | rustc | rust-std) ;;
      llvm-tools) optional_components+=(llvm-tools-preview) ;;
      *) optional_components+=("$component") ;;
    esac
  done
  install_args=(toolchain install "$source_toolchain" --profile minimal)
  if (( ${#optional_components[@]} )); then
    install_args+=(--component "$(IFS=,; printf '%s' "${optional_components[*]}")")
  fi
  install_args+=(--target "$(IFS=,; printf '%s' "${targets[*]}")")

  backup_dir="$toolchain_dir$backup_suffix"
  if [[ -e "$backup_dir" ]]; then
    printf 'Refusing to overwrite Rustup migration backup: %s\n' "$backup_dir" >&2
    exit 1
  fi
  staging_dir="$(mktemp -d "$rustup_home/rustup-nix-ld-migration.XXXXXXXX")"
  staging_rustup="$staging_dir/rustup"
  if ! RUSTUP_HOME="$staging_rustup" CARGO_HOME="$staging_dir/cargo" "$rustup" "${install_args[@]}"; then
    exit 1
  fi
  replacement_dirs=("$staging_rustup/toolchains/"*)
  if (( ${#replacement_dirs[@]} != 1 )) || [[ ! -d "${replacement_dirs[0]}" ]]; then
    printf 'Could not locate replacement Rustup toolchain: %s\n' "$source_toolchain" >&2
    exit 1
  fi
  replacement_dir="${replacement_dirs[0]}"
  replacement_interpreter="$("$patchelf" --print-interpreter "$replacement_dir/bin/rustc" 2>/dev/null || true)"
  if [[ "$replacement_interpreter" != /lib64/ld-linux-x86-64.so.2 ]] || ! "$replacement_dir/bin/rustc" --version >/dev/null; then
    printf 'Replacement Rustup toolchain does not use nix-ld: %s\n' "$source_toolchain" >&2
    exit 1
  fi

  mv "$toolchain_dir" "$backup_dir"
  if ! mv "$replacement_dir" "$toolchain_dir"; then
    mv "$backup_dir" "$toolchain_dir"
    exit 1
  fi
  rm -rf "$backup_dir" "$staging_dir"
  staging_dir=
done
