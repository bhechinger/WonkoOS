#!/bin/sh
set -eu

work_dir=$(mktemp -d)
trap 'rm -rf -- "$work_dir"' EXIT HUP INT TERM
mongodb=$work_dir/mongodb

NIXPKGS_ALLOW_UNFREE=1 nix build \
	--refresh \
	--impure \
	--out-link "$mongodb" \
	github:NixOS/nixpkgs/nixos-unstable#mongodb

attic push internal "$mongodb"
