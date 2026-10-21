#!/bin/sh
set -eu

mongodb=$(NIXPKGS_ALLOW_UNFREE=1 nix build \
	--refresh \
	--impure \
	--no-link \
	--print-out-paths \
	github:NixOS/nixpkgs/nixos-unstable#mongodb)

attic push internal "$mongodb"
