#!/usr/bin/env sh
set -eu

audio_nix="${1:-home/audio.nix}"

fail() {
  printf 'audio-readiness: %s\n' "$*" >&2
  exit 1
}

grep -Fq 'node_ready()' "$audio_nix" ||
  fail 'ardour readiness helper must check expected PipeWire node properties'

grep -Fq 'saffire_nodes_ready()' "$audio_nix" ||
  fail 'ardour readiness helper must require ready Saffire nodes'

grep -Fq 'saffire_ffado_output' "$audio_nix" ||
  fail 'ardour readiness helper must target the Saffire FFADO output node'

grep -Fq 'saffire_ffado_input' "$audio_nix" ||
  fail 'ardour readiness helper must target the Saffire FFADO input node'

grep -Fq 'ffado-group' "$audio_nix" ||
  fail 'ardour readiness helper must identify FFADO-backed nodes'

grep -Fq 'readiness_failures()' "$audio_nix" ||
  fail 'ardour readiness helper must report missing readiness conditions'

grep -Fq 'required_consecutive_ready_checks=2' "$audio_nix" ||
  fail 'ardour readiness helper must require stable readiness across two polls'

if grep -Fq 'alsa_output.firewire-0x00130e0401c04de0' "$audio_nix"; then
  fail 'ardour readiness helper must not target the Saffire ALSA output node'
fi

if grep -Fq 'alsa_input.firewire-0x00130e0401c04de0' "$audio_nix"; then
  fail 'ardour readiness helper must not target the Saffire ALSA input node'
fi

if grep -Fq 'min_boot_age_seconds' "$audio_nix"; then
  fail 'ardour readiness helper must not use a static boot-age delay'
fi

if grep -Fq 'wait_for_saffire_boot_settle' "$audio_nix"; then
  fail 'ardour readiness helper must not call a static Saffire settle sleep'
fi

if grep -Fq '.info.state == "running"' "$audio_nix"; then
  fail 'ardour readiness helper must not require idle PipeWire nodes to be running'
fi

printf 'audio-readiness: ok\n'
