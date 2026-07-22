set -euo pipefail

CURL=${CURL:-curl}
JQ=${JQ:-jq}

if [[ $# -ne 1 ]]; then
  echo "usage: opnsense-dns-sync RECORDS_JSON" >&2
  exit 2
fi

records_file=$1

: "${OPNSENSE_URL:?OPNSENSE_URL is required}"
: "${OPNSENSE_NETRC:?OPNSENSE_NETRC is required}"
: "${DNS_ZONE:?DNS_ZONE is required}"

for file in "$OPNSENSE_NETRC" "$records_file"; do
  if [[ ! -r "$file" ]]; then
    echo "Required file is not readable: $file" >&2
    exit 1
  fi
done
if [[ $(<"$OPNSENSE_NETRC") == *REPLACE_WITH_* ]]; then
  echo "Replace the placeholder OPNsense credentials in $OPNSENSE_NETRC" >&2
  exit 1
fi

api_post() {
  local endpoint=$1
  local data=${2-'{}'}

  "$CURL" \
    --fail-with-body \
    --silent \
    --show-error \
    --netrc-file "$OPNSENSE_NETRC" \
    --header "Content-Type: application/json" \
    --request POST \
    --data "$data" \
    "${OPNSENSE_URL%/}$endpoint"
}

# BIND's API stores zone-file RDATA, so TXT strings need their zone-file quotes.
# shellcheck disable=SC2016
desired=$(
  "$JQ" -ce '
    if type != "array" then error("records must be an array") else . end
    | map(
        if
          (.name | type) != "string" or
          (.type | type) != "string" or
          (.value | type) != "string" or
          .type == "" or .value == ""
        then error("every record needs string name, type, and value fields")
        elif .type == "TXT" and (.value | explode | any(. < 32 or . == 127))
        then error("TXT values cannot contain control characters")
        else {
          name,
          type,
          value: (if .type == "TXT" then (.value | @json) else .value end)
        }
        end
      )
    | sort_by(.name, .type, .value)
    | if group_by([.name, .type, .value]) | any(length > 1)
      then error("desired records contain a duplicate")
      else .
      end
  ' "$records_file"
)

search_payload='{"current":1,"rowCount":-1,"sort":{}}'
domains=$(api_post "/api/bind/domain/search_primary_domain" "$search_payload")
# shellcheck disable=SC2016
zone_matches=$(
  "$JQ" -ce --arg zone "$DNS_ZONE" '
    if (.rows | type) != "array" then
      error("OPNsense domain response has no rows array")
    else
      [.rows[] | select(.domainname == $zone and (.enabled | tostring) == "1")]
    end
  ' <<<"$domains"
)
zone_count=$("$JQ" -r length <<<"$zone_matches")
if ((zone_count != 1)); then
  echo "Expected one primary BIND zone named $DNS_ZONE, found $zone_count" >&2
  exit 1
fi
zone_uuid=$("$JQ" -er '.[0].uuid | strings | select(length > 0)' <<<"$zone_matches")

# shellcheck disable=SC2016
record_search_payload=$(
  "$JQ" -cn \
    --arg domain "$zone_uuid" \
    '{current: 1, rowCount: -1, sort: {}, domain: $domain}'
)
records=$(api_post "/api/bind/record/search_record?domain=$zone_uuid" "$record_search_payload")
# shellcheck disable=SC2016
current=$(
  "$JQ" -ce --arg zone "$DNS_ZONE" --arg zone_uuid "$zone_uuid" '
    if (.rows | type) != "array" then
      error("OPNsense record response has no rows array")
    elif any(.rows[]; .domain != $zone and .domain != $zone_uuid) then
      error("OPNsense record response contains another zone")
    else
      [.rows[] | {
        uuid: (.uuid | strings | select(length > 0)),
        enabled: (.enabled | tostring),
        name: (.name | strings),
        type: (.type | strings),
        value: (.value | strings)
      }]
    end
  ' <<<"$records"
)

# Keep one enabled copy of each exact desired tuple. Delete everything else in
# the static zone, then add missing tuples; BIND is reconfigured only afterward.
# shellcheck disable=SC2016
plan=$(
  "$JQ" -cn --argjson desired "$desired" --argjson current "$current" '
    def same($a; $b):
      $a.name == $b.name and $a.type == $b.type and $a.value == $b.value;
    [
      $desired[] as $wanted
      | first($current[] | select(.enabled == "1" and same(.; $wanted)))
      | .uuid
    ] as $keep
    | {
        delete: [$current[] | select(.uuid as $uuid | $keep | index($uuid) | not)],
        add: [
          $desired[] as $wanted
          | select(any($current[]; .enabled == "1" and same(.; $wanted)) | not)
          | $wanted
        ]
      }
  '
)

deleted=0
while IFS= read -r record; do
  uuid=$("$JQ" -er '.uuid' <<<"$record")
  response=$(api_post "/api/bind/record/del_record/$uuid")
  if ! "$JQ" -e '.result == "deleted"' <<<"$response" >/dev/null; then
    echo "OPNsense did not delete BIND record $uuid" >&2
    exit 1
  fi
  ((deleted += 1))
done < <("$JQ" -c '.delete[]' <<<"$plan")

added=0
while IFS= read -r record; do
  # shellcheck disable=SC2016
  payload=$(
    "$JQ" -cn \
      --arg domain "$zone_uuid" \
      --argjson record "$record" \
      '{record: ({enabled: "1", domain: $domain} + $record)}'
  )
  response=$(api_post "/api/bind/record/add_record" "$payload")
  if ! "$JQ" -e '.result == "saved" and (.uuid | type) == "string"' <<<"$response" >/dev/null; then
    echo "OPNsense did not add BIND record" >&2
    exit 1
  fi
  ((added += 1))
done < <("$JQ" -c '.add[]' <<<"$plan")

if ((deleted == 0 && added == 0)); then
  echo "$DNS_ZONE unchanged"
  exit 0
fi

reconfigure=$(api_post "/api/bind/service/reconfigure")
if ! "$JQ" -e '.status == "ok"' <<<"$reconfigure" >/dev/null; then
  echo "OPNsense saved records but failed to reconfigure BIND" >&2
  exit 1
fi

echo "$DNS_ZONE reconciled ($added added, $deleted deleted)"
