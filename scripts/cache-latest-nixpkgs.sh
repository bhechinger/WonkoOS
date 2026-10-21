#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -eq 0 ]; then
	printf 'Usage: %s PACKAGE...\n' "${0##*/}" >&2
	exit 2
fi

nixpkgs=github:NixOS/nixpkgs/nixos-unstable
installables=()
for package in "$@"; do
	installables+=("$nixpkgs#$package")
done

work_dir=$(mktemp -d)
trap 'rm -rf -- "$work_dir"' EXIT HUP INT TERM
result=$work_dir/result

NIXPKGS_ALLOW_UNFREE=1 nix build \
	--refresh \
	--impure \
	--out-link "$result" \
	"${installables[@]}"

attic push internal "$result"*
