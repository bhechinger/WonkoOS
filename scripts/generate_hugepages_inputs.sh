#!/usr/bin/env bash
set -euo pipefail

host_name="$(hostname)"
output="${1:-systems/${host_name}/hugepages-inputs.nix}"

kernel_release="$(uname -r)"
huge_page_size_kib="$(awk '/Hugepagesize/ { print $2; exit }' /proc/meminfo)"
segment_sizes="$(awk 'NR > 1 && $4 ~ /^[0-9]+$/ { print $4 }' /proc/sysvipc/shm | sort -n | tr '\n' ' ')"

mkdir -p "$(dirname "$output")"
tmp="$(mktemp "${output}.tmp.XXXXXX")"
trap 'rm -f "$tmp"' EXIT

cat > "$tmp" <<NIX
{
  kernelRelease = "$kernel_release";
  hugePageSizeKiB = $huge_page_size_kib;
  sharedMemorySegmentsBytes = [ $segment_sizes ];
}
NIX

mv "$tmp" "$output"
trap - EXIT
