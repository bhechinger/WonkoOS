#!/usr/bin/env sh
set -eu

audio_nix="${1:-home/audio.nix}"
audio_routes_lua="${2:-home/wireplumber/audio-routes.lua}"

fail() {
  printf 'saffire-ffado-live-aliases: %s\n' "$*" >&2
  exit 1
}

require_readiness_alias() {
  alias="$1"

  grep -Fq "$alias" "$audio_nix" ||
    fail "readiness helper must require live FFADO alias: $alias"
}

require_route_alias() {
  alias="$1"

  grep -Fq "$alias" "$audio_routes_lua" ||
    fail "audio routes must use live WirePlumber FFADO port alias: $alias"
}

require_readiness_alias "saffire_ffado_output:00130e0401c04de0_1394/In:01 (Mixer/In:17)_in"
require_readiness_alias "saffire_ffado_output:00130e0401c04de0_1394/In:02 (Mixer/In:18)_in"
require_readiness_alias "saffire_ffado_input:00130e0401c04de0_1394/Out:01 (Anlg/In:03)_out"
require_readiness_alias "saffire_ffado_input:00130e0401c04de0_1394/Out:05 (SPDIF/In:01)_out"
require_readiness_alias "saffire_ffado_input:00130e0401c04de0_1394/Out:06 (SPDIF/In:02)_out"

require_route_alias "Saffire Pro 24 FFADO Output:00130e0401c04de0_1394/In:01 (Mixer/In:17)_in"
require_route_alias "Saffire Pro 24 FFADO Output:00130e0401c04de0_1394/In:02 (Mixer/In:18)_in"
require_route_alias "Saffire Pro 24 FFADO Input:00130e0401c04de0_1394/Out:01 (Anlg/In:03)_out"
require_route_alias "Saffire Pro 24 FFADO Input:00130e0401c04de0_1394/Out:05 (SPDIF/In:01)_out"
require_route_alias "Saffire Pro 24 FFADO Input:00130e0401c04de0_1394/Out:06 (SPDIF/In:02)_out"

printf 'saffire-ffado-live-aliases: ok\n'
