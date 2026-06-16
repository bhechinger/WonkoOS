#!/usr/bin/env bash
set -euo pipefail

host_name="$(hostname)"
output="${1:-systems/${host_name}/hugepages-inputs.nix}"

kernel_release="$(uname -r)"
huge_page_size_kib="$(awk '/Hugepagesize/ { print $2; exit }' /proc/meminfo)"
segment_sizes="$(awk 'NR > 1 && $4 ~ /^[0-9]+$/ { print $4 }' /proc/sysvipc/shm | sort -n | tr '\n' ' ')"
huge_page_size_bytes=$((huge_page_size_kib * 1024))

hugepage_count() {
  local total=1
  local segment_bytes min_pages

  for segment_bytes in "$@"; do
    min_pages=$((segment_bytes / huge_page_size_bytes))
    if [ "$min_pages" -gt 0 ]; then
      total=$((total + min_pages + 1))
    fi
  done

  printf '%s\n' "$total"
}

# SysV SHM segment sizes are runtime state. Keep an existing same-kernel input
# when the current sample would only lower or preserve the hugepage count.
if [ -f "$output" ]; then
  existing_kernel_release="$(awk -F '"' '/kernelRelease/ { print $2; exit }' "$output")"
  existing_huge_page_size_kib="$(awk '/hugePageSizeKiB/ { print $3; exit }' "$output" | tr -d ';')"

  if [ "$existing_kernel_release" = "$kernel_release" ] && [ "$existing_huge_page_size_kib" = "$huge_page_size_kib" ]; then
    existing_segment_sizes="$(awk '/sharedMemorySegmentsBytes/ { collecting = 1 } collecting { for (i = 1; i <= NF; i++) if ($i ~ /^[0-9]+$/) print $i } /];/ { collecting = 0 }' "$output" | sort -n | tr '\n' ' ')"
    current_hugepages="$(hugepage_count $segment_sizes)"
    existing_hugepages="$(hugepage_count $existing_segment_sizes)"

    if [ "$current_hugepages" -le "$existing_hugepages" ]; then
      exit 0
    fi
  fi
fi

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
