#!/usr/bin/env sh
set -eu

ffado_conf="${1:-home/pipewire/saffire-ffado.conf}"
system_nix="${2:-systems/deepthought/system.nix}"

fail() {
  printf 'saffire-ffado-config: %s\n' "$*" >&2
  exit 1
}

grep -Fq 'ffado.devices = [ "hw:0" ]' "$ffado_conf" ||
  fail 'Saffire FFADO config must use the live Saffire selector hw:0'

grep -Fq '"snd_dice"' "$system_nix" ||
  fail 'snd_dice must be blacklisted so FFADO can own the Saffire'

printf 'saffire-ffado-config: ok\n'
