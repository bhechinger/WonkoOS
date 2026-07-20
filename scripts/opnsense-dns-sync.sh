set -euo pipefail

CURL=${CURL:-curl}
JQ=${JQ:-jq}

if [[ $# -ne 2 ]]; then
  echo "usage: opnsense-dns-sync HOSTNAME IPV4_ADDRESS" >&2
  exit 2
fi

DNS_HOSTNAME=$1
DNS_VALUE=$2

: "${OPNSENSE_URL:?OPNSENSE_URL is required}"
: "${OPNSENSE_NETRC:?OPNSENSE_NETRC is required}"
: "${OPNSENSE_PINNED_PUBLIC_KEY:?OPNSENSE_PINNED_PUBLIC_KEY is required}"
: "${DNS_DOMAIN:?DNS_DOMAIN is required}"
: "${DNS_TYPE:?DNS_TYPE is required}"
: "${DNS_DESCRIPTION:?DNS_DESCRIPTION is required}"

if [[ ! -r "$OPNSENSE_NETRC" ]]; then
  echo "OPNsense credentials are not readable: $OPNSENSE_NETRC" >&2
  exit 1
fi
if [[ $(<"$OPNSENSE_NETRC") == *REPLACE_WITH_* ]]; then
  echo "Replace the placeholder OPNsense credentials in $OPNSENSE_NETRC" >&2
  exit 1
fi

api_post() {
  local endpoint=$1
  local data=${2-}
  [[ -n "$data" ]] || data='{}'

  # OPNsense's self-signed certificate has a stale hostname; the public-key
  # pin still authenticates it before curl sends or receives API data.
  "$CURL" \
    --fail-with-body \
    --insecure \
    --pinnedpubkey "$OPNSENSE_PINNED_PUBLIC_KEY" \
    --silent \
    --show-error \
    --netrc-file "$OPNSENSE_NETRC" \
    --header "Content-Type: application/json" \
    --request POST \
    --data "$data" \
    "${OPNSENSE_URL%/}$endpoint"
}

# jq variables are populated by --arg, not expanded by the shell.
# shellcheck disable=SC2016
payload=$(
  "$JQ" -cn \
    --arg hostname "$DNS_HOSTNAME" \
    --arg domain "$DNS_DOMAIN" \
    --arg rr "$DNS_TYPE" \
    --arg server "$DNS_VALUE" \
    --arg description "$DNS_DESCRIPTION" \
    '{host: {
      enabled: "1",
      hostname: $hostname,
      domain: $domain,
      rr: $rr,
      server: $server,
      description: $description
    }}'
)

search_response=$(
  api_post \
    "/api/unbound/settings/search_host_override" \
    '{"current":1,"rowCount":-1,"sort":{}}'
)
# shellcheck disable=SC2016
matches=$(
  "$JQ" -ce \
    --arg hostname "$DNS_HOSTNAME" \
    --arg domain "$DNS_DOMAIN" \
    --arg rr "$DNS_TYPE" \
    'if (.rows | type) != "array" then
      error("OPNsense response has no rows array")
    else
      [.rows[] | select(
        .hostname == $hostname and
        .domain == $domain and
        .rr == $rr
      )]
    end' <<<"$search_response"
)
count=$("$JQ" -r length <<<"$matches")
fqdn="$DNS_HOSTNAME.$DNS_DOMAIN"

if ((count > 1)); then
  echo "Refusing to change $fqdn: found $count duplicate $DNS_TYPE records" >&2
  exit 1
fi

if ((count == 1)); then
  # shellcheck disable=SC2016
  if "$JQ" -e \
    --arg server "$DNS_VALUE" \
    --arg description "$DNS_DESCRIPTION" \
    '.[0] |
      (.enabled | tostring) == "1" and
      .server == $server and
      .description == $description' <<<"$matches" >/dev/null; then
    echo "$fqdn unchanged ($DNS_VALUE)"
    exit 0
  fi

  uuid=$("$JQ" -er '.[0].uuid | strings | select(length > 0)' <<<"$matches")
  mutation=$(api_post "/api/unbound/settings/set_host_override/$uuid" "$payload")
  result=updated
else
  mutation=$(api_post "/api/unbound/settings/add_host_override" "$payload")
  result=added
fi

if ! "$JQ" -e '.result == "saved"' <<<"$mutation" >/dev/null; then
  echo "OPNsense did not save $fqdn" >&2
  exit 1
fi

reconfigure=$(api_post "/api/unbound/service/reconfigure")
if ! "$JQ" -e '.status == "ok"' <<<"$reconfigure" >/dev/null; then
  echo "OPNsense saved $fqdn but failed to reconfigure Unbound" >&2
  exit 1
fi

echo "$fqdn $result ($DNS_VALUE)"
