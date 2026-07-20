set -euo pipefail

script=$1
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

export OPNSENSE_URL=https://sierra.4amlunch.internal
export OPNSENSE_NETRC="$tmp/netrc"
export DNS_DOMAIN=4amlunch.net
export DNS_TYPE=A
export DNS_DESCRIPTION="Managed by WonkoOS"
export CURL="$tmp/curl"
export CALLS="$tmp/calls"

printf '%s\n' \
  "machine sierra.4amlunch.internal" \
  "login test" \
  "password test" >"$OPNSENSE_NETRC"

printf '#!%s\n' "$BASH" >"$CURL"
cat >>"$CURL" <<'EOF'
set -euo pipefail

url=${!#}
printf '%s\n' "$url" >>"$CALLS"

case "$url" in
  */search_host_override)
    printf '%s\n' "$SEARCH_RESPONSE"
    ;;
  */add_host_override | */set_host_override/*)
    printf '%s\n' '{"result":"saved"}'
    ;;
  */service/reconfigure)
    printf '%s\n' '{"status":"ok"}'
    ;;
  *)
    echo "unexpected URL: $url" >&2
    exit 1
    ;;
esac
EOF
chmod +x "$CURL"

run_sync() {
  local hostname=$1 address=$2 response=$3
  SEARCH_RESPONSE=$response bash "$script" "$hostname" "$address"
}

assert_calls() {
  [[ $(wc -l <"$CALLS") -eq $1 ]]
}

: >"$CALLS"
output=$(run_sync cache 10.42.0.2 '{"rows":[{"uuid":"same","enabled":"1","hostname":"cache","domain":"4amlunch.net","rr":"A","server":"10.42.0.2","description":"Managed by WonkoOS"}]}')
grep -qx 'cache.4amlunch.net unchanged (10.42.0.2)' <<<"$output"
assert_calls 1

: >"$CALLS"
output=$(run_sync sonarr 10.42.0.3 '{"rows":[]}')
grep -qx 'sonarr.4amlunch.net added (10.42.0.3)' <<<"$output"
grep -q '/add_host_override$' "$CALLS"
grep -q '/service/reconfigure$' "$CALLS"
assert_calls 3

: >"$CALLS"
output=$(run_sync rutorrent 10.42.0.4 '{"rows":[{"uuid":"change-me","enabled":"1","hostname":"rutorrent","domain":"4amlunch.net","rr":"A","server":"10.42.0.99","description":"Managed by WonkoOS"}]}')
grep -qx 'rutorrent.4amlunch.net updated (10.42.0.4)' <<<"$output"
grep -q '/set_host_override/change-me$' "$CALLS"
grep -q '/service/reconfigure$' "$CALLS"
assert_calls 3

: >"$CALLS"
duplicates='{"rows":[
  {"uuid":"one","hostname":"cache","domain":"4amlunch.net","rr":"A"},
  {"uuid":"two","hostname":"cache","domain":"4amlunch.net","rr":"A"}
]}'
if run_sync cache 10.42.0.2 "$duplicates" >"$tmp/output" 2>"$tmp/error"; then
  echo "duplicate records should fail" >&2
  exit 1
fi
grep -q 'duplicate' "$tmp/error"
assert_calls 1
