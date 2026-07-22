set -euo pipefail

script=$1
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

export OPNSENSE_URL=https://sierra.4amlunch.net
export OPNSENSE_NETRC="$tmp/netrc"
export DNS_ZONE=4amlunch.net
export CURL="$tmp/curl"
export CALLS="$tmp/calls"
export PAYLOADS="$tmp/payloads"

printf '%s\n' \
  "machine sierra.4amlunch.net" \
  "login test" \
  "password test" >"$OPNSENSE_NETRC"

printf '#!%s\n' "$BASH" >"$CURL"
cat >>"$CURL" <<'EOF'
set -euo pipefail

data='{}'
url=
while (($#)); do
  case "$1" in
    --insecure | --pinnedpubkey)
      echo "TLS verification must not be disabled" >&2
      exit 1
      ;;
    --data)
      data=$2
      shift 2
      ;;
    *)
      url=$1
      shift
      ;;
  esac
done

printf '%s\n' "$url" >>"$CALLS"
printf '%s\n' "$data" >>"$PAYLOADS"

case "$url" in
  */domain/search_primary_domain)
    printf '%s\n' "$DOMAIN_RESPONSE"
    ;;
  */record/search_record\?domain=*)
    printf '%s\n' "$RECORD_RESPONSE"
    ;;
  */record/del_record/*)
    printf '%s\n' "${DELETE_RESPONSE:-{\"result\":\"deleted\"}}"
    ;;
  */record/add_record)
    printf '%s\n' "${ADD_RESPONSE:-{\"result\":\"saved\",\"uuid\":\"new\"}}"
    ;;
  */service/reconfigure)
    printf '%s\n' "${RECONFIGURE_RESPONSE:-{\"status\":\"ok\"}}"
    ;;
  *)
    echo "unexpected URL: $url" >&2
    exit 1
    ;;
esac
EOF
chmod +x "$CURL"

desired="$tmp/desired.json"
cat >"$desired" <<'EOF'
[
  {"name":"@","type":"NS","value":"sierra.4amlunch.net."},
  {"name":"bob","type":"A","value":"10.42.0.2"},
  {"name":"pwppp","type":"TXT","value":"local \"direct\"\\path"}
]
EOF

domain='{"rows":[{"uuid":"zone","enabled":"1","type":"primary","domainname":"4amlunch.net"}]}'
current=$(
  jq -cn '{rows: [
    {uuid:"ns",enabled:"1",domain:"4amlunch.net",name:"@",type:"NS",value:"sierra.4amlunch.net."},
    {uuid:"bob",enabled:"1",domain:"4amlunch.net",name:"bob",type:"A",value:"10.42.0.2"},
    {uuid:"txt",enabled:"1",domain:"4amlunch.net",name:"pwppp",type:"TXT",value:"\"local \\\"direct\\\"\\\\path\""}
  ]}'
)

run_sync() {
  : >"$CALLS"
  : >"$PAYLOADS"
  DOMAIN_RESPONSE=$1 RECORD_RESPONSE=$2 bash "$script" "$desired"
}

output=$(run_sync "$domain" "$current")
grep -qx '4amlunch.net unchanged' <<<"$output"
[[ $(wc -l <"$CALLS") -eq 2 ]]
if grep -q '/service/reconfigure$' "$CALLS"; then
  echo "unchanged records must not reconfigure BIND" >&2
  exit 1
fi

drifted=$(
  jq -cn '{rows: [
    {uuid:"ns",enabled:"1",domain:"4amlunch.net",name:"@",type:"NS",value:"sierra.4amlunch.net."},
    {uuid:"ns-duplicate",enabled:"1",domain:"4amlunch.net",name:"@",type:"NS",value:"sierra.4amlunch.net."},
    {uuid:"old-bob",enabled:"1",domain:"4amlunch.net",name:"bob",type:"A",value:"10.42.0.99"},
    {uuid:"stale",enabled:"1",domain:"4amlunch.net",name:"stale",type:"A",value:"10.42.0.10"},
    {uuid:"disabled-txt",enabled:"0",domain:"4amlunch.net",name:"pwppp",type:"TXT",value:"\"local \\\"direct\\\"\\\\path\""}
  ]}'
)
output=$(run_sync "$domain" "$drifted")
grep -qx '4amlunch.net reconciled (2 added, 4 deleted)' <<<"$output"
[[ $(grep -c '/record/del_record/' "$CALLS") -eq 4 ]]
[[ $(grep -c '/record/add_record$' "$CALLS") -eq 2 ]]
[[ $(grep -c '/service/reconfigure$' "$CALLS") -eq 1 ]]
jq -e '
  select(.record.type == "TXT")
  | .record.value == "\"local \\\"direct\\\"\\\\path\""
' "$PAYLOADS" >/dev/null

if run_sync '{"rows":[]}' '{"rows":[]}' >"$tmp/output" 2>"$tmp/error"; then
  echo "a missing zone should fail" >&2
  exit 1
fi
grep -q 'Expected one primary BIND zone' "$tmp/error"
[[ $(wc -l <"$CALLS") -eq 1 ]]

if run_sync "$domain" '{"rows":[{"uuid":"other","enabled":"1","domain":"lan.4amlunch.net","name":"client","type":"A","value":"10.42.0.20"}]}' >"$tmp/output" 2>"$tmp/error"; then
  echo "records from another zone should fail" >&2
  exit 1
fi
grep -q 'record response contains another zone' "$tmp/error"
[[ $(wc -l <"$CALLS") -eq 2 ]]

printf '%s\n' \
  '[{"name":"bob","type":"A","value":"10.42.0.2"},{"name":"bob","type":"A","value":"10.42.0.2"}]' \
  >"$desired"
: >"$CALLS"
if DOMAIN_RESPONSE=$domain RECORD_RESPONSE='{"rows":[]}' bash "$script" "$desired" >"$tmp/output" 2>"$tmp/error"; then
  echo "duplicate desired records should fail" >&2
  exit 1
fi
grep -q 'desired records contain a duplicate' "$tmp/error"
[[ ! -s "$CALLS" ]]

printf '%s\n' '[{"name":"bob","type":"A","value":"10.42.0.2"}]' >"$desired"
if ADD_RESPONSE='{"result":"failed"}' run_sync "$domain" '{"rows":[]}' >"$tmp/output" 2>"$tmp/error"; then
  echo "a failed add should fail" >&2
  exit 1
fi
grep -q 'did not add BIND record' "$tmp/error"
if grep -q '/service/reconfigure$' "$CALLS"; then
  echo "a failed mutation must not reconfigure BIND" >&2
  exit 1
fi
