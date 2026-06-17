#!/usr/bin/env sh
set -eu

audio_routes_lua="${1:-home/wireplumber/audio-routes.lua}"

require_text() {
  pattern="$1"
  description="$2"

  if ! grep -Fq "$pattern" "$audio_routes_lua"; then
    printf 'missing %s in %s\n' "$description" "$audio_routes_lua" >&2
    exit 1
  fi
}

require_text 'local reconcile_interval_ms = 2000' 'periodic reconcile interval'
require_text 'local reconcile_interval_source = nil' 'periodic reconcile source'
require_text 'reconcile_interval_source = Core.timeout_add(reconcile_interval_ms, function()' 'periodic reconcile timer'
require_text 'reconcile_links()' 'periodic reconcile invocation'
require_text 'return true' 'periodic reconcile timer continuation'
require_text 'ardour:Master/audio_out 1' 'left Ardour master output route'
require_text 'ardour:Master/audio_out 2' 'right Ardour master output route'

printf 'audio-routes-reconcile: ok\n'
