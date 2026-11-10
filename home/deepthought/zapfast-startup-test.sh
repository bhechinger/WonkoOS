#!/bin/sh
set -eu
startup=$1
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT HUP INT TERM
export PASSWORD_STORE_DIR="$test_dir/store with spaces" TEST_LOG="$test_dir/log"
mkdir -p "$test_dir/bin"
export PATH="$test_dir/bin:$PATH"

cat >"$test_dir/bin/gpg" <<'EOF'
#!/bin/sh
set -eu
printf '%s\n' "$3" >>"$TEST_LOG"
if [ -n "${TEST_READY:-}" ]; then
  printf 'ready\n' >"$TEST_READY"
  read -r reply <"$TEST_CONTINUE"
fi
printf 'secret must not reach stdout\n'
exit "${GPG_STATUS:-0}"
EOF
cat >"$test_dir/bin/zapfast" <<'EOF'
#!/bin/sh
printf 'zapfast:%s\n' "$*" >>"$TEST_LOG"
EOF
chmod +x "$test_dir/bin/gpg" "$test_dir/bin/zapfast"

# A first launch with no credentials still starts normally and preserves arguments.
sh "$startup" --start-hidden
test "$(cat "$TEST_LOG")" = 'zapfast:--start-hidden'

collection="$PASSWORD_STORE_DIR/secret_service/collection"
mkdir -p "$collection"
printf '%s\n' '{"org.freedesktop.Secret.Item.Attributes":{"service":"other-app"}}' >"$collection/other.properties"
: >"$TEST_LOG"
sh "$startup"
test "$(cat "$TEST_LOG")" = 'zapfast:'

printf '%s\n' '{"org.freedesktop.Secret.Item.Attributes":{"service":"rocks.zapfast.ZapFast"}}' >"$collection/archive.properties"
touch "$collection/archive.gpg"
: >"$TEST_LOG"
export TEST_READY="$test_dir/ready" TEST_CONTINUE="$test_dir/continue"
mkfifo "$TEST_READY" "$TEST_CONTINUE"
sh "$startup" --start-hidden >"$test_dir/stdout" &
startup_pid=$!
read -r ready <"$TEST_READY"
test "$ready" = ready
test "$(cat "$TEST_LOG")" = "$collection/archive.gpg"
printf 'unlocked\n' >"$TEST_CONTINUE"
wait "$startup_pid"
test "$(cat "$TEST_LOG")" = "$(printf '%s\nzapfast:--start-hidden' "$collection/archive.gpg")"
test ! -s "$test_dir/stdout"
unset TEST_READY TEST_CONTINUE

# A cancelled or failed decryption must not launch ZapFast.
: >"$TEST_LOG"
if GPG_STATUS=2 sh "$startup"; then
  echo 'ZapFast started after a failed unlock' >&2
  exit 1
fi
test "$(cat "$TEST_LOG")" = "$collection/archive.gpg"
