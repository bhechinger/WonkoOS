#!/usr/bin/env bash
set -euo pipefail
: "${MIGRATION_SCRIPT:?}"

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
host=x86_64-unknown-linux-gnu
backup_suffix=.before-nix-ld-migration

make_toolchain() {
  local toolchain_dir=$1
  local state=$2
  mkdir -p "$toolchain_dir/bin" "$toolchain_dir/lib/rustlib"
  printf '#!%s\n# %s\nexit 0\n' "$BASH" "$state" >"$toolchain_dir/bin/rustc"
  chmod +x "$toolchain_dir/bin/rustc"
  cat >"$toolchain_dir/lib/rustlib/multirust-channel-manifest.toml" <<'EOF'
manifest-version = "2"
date = "2026-05-28"

[pkg.rust]
version = "1.96.0 (fixture 2026-05-25)"
EOF
}

printf '#!%s\n' "$BASH" >"$work_dir/patchelf"
cat >>"$work_dir/patchelf" <<'EOF'
if [[ "$(<"$2")" == *'# healthy'* ]]; then
  printf '/lib64/ld-linux-x86-64.so.2\n'
else
  printf '/nix/store/collected-glibc/lib/ld-linux-x86-64.so.2\n'
fi
EOF
chmod +x "$work_dir/patchelf"

printf '#!%s\n' "$BASH" >"$work_dir/rustup"
cat >>"$work_dir/rustup" <<'EOF'
set -euo pipefail
if [[ "$1 $2" == 'component list' ]]; then
  printf '%s\n' cargo-x86_64-unknown-linux-gnu clippy-x86_64-unknown-linux-gnu rust-src rust-std-wasm32-wasip2 rust-std-x86_64-unknown-linux-gnu rustc-x86_64-unknown-linux-gnu
elif [[ "$1 $2" == 'target list' ]]; then
  printf '%s\n' wasm32-wasip2 x86_64-unknown-linux-gnu
elif [[ "$1 $2" == 'toolchain install' ]]; then
  printf '%s\n' "$*" >>"$TEST_LOG"
  toolchain=$3
  mkdir -p "$RUSTUP_HOME/toolchains/$toolchain/bin"
  printf '#!%s\n# healthy\nexit 0\n' "$BASH" >"$RUSTUP_HOME/toolchains/$toolchain/bin/rustc"
  chmod +x "$RUSTUP_HOME/toolchains/$toolchain/bin/rustc"
else
  exit 1
fi
EOF
chmod +x "$work_dir/rustup"

run_migration() {
  local case_dir=$1
  : >"$case_dir/log"
  RUSTUP_HOME="$case_dir/rustup" TEST_LOG="$case_dir/log" "$MIGRATION_SCRIPT" "$work_dir/rustup" "$work_dir/patchelf"
}

normal="$work_dir/normal"
make_toolchain "$normal/rustup/toolchains/stable-$host" stale
run_migration "$normal"
[[ "$(<"$normal/rustup/toolchains/stable-$host/bin/rustc")" == *'# healthy'* ]]
[[ ! -e "$normal/rustup/toolchains/stable-$host$backup_suffix" ]]
normal_log="$(<"$normal/log")"
[[ "$normal_log" == *"toolchain install 1.96.0-$host"* ]]
[[ "$normal_log" == *'--component clippy,rust-src'* ]]
[[ "$normal_log" == *'--target wasm32-wasip2,x86_64-unknown-linux-gnu'* ]]

before="$work_dir/before"
make_toolchain "$before/rustup/toolchains/stable-$host$backup_suffix" stale
run_migration "$before"
[[ "$(<"$before/rustup/toolchains/stable-$host/bin/rustc")" == *'# healthy'* ]]
[[ ! -e "$before/rustup/toolchains/stable-$host$backup_suffix" ]]

after="$work_dir/after"
make_toolchain "$after/rustup/toolchains/stable-$host" healthy
make_toolchain "$after/rustup/toolchains/stable-$host$backup_suffix" stale
run_migration "$after"
[[ "$(<"$after/rustup/toolchains/stable-$host/bin/rustc")" == *'# healthy'* ]]
[[ ! -e "$after/rustup/toolchains/stable-$host$backup_suffix" ]]
[[ ! -s "$after/log" ]]
