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
result=$work_dir/result
child_pid=

terminate() {
	local signal=$1
	local exit_status=$2

	trap - HUP INT TERM
	if [[ -n $child_pid ]]; then
		kill "-$signal" "$child_pid" 2>/dev/null || true
		wait "$child_pid" 2>/dev/null || true
	fi
	exit "$exit_status"
}

run() {
	local status

	"$@" &
	child_pid=$!
	if wait "$child_pid"; then
		child_pid=
		return 0
	else
		status=$?
		child_pid=
		return "$status"
	fi
}

trap 'rm -rf -- "$work_dir"' EXIT
trap 'terminate HUP 129' HUP
trap 'terminate TERM 130' INT
trap 'terminate TERM 143' TERM

run env NIXPKGS_ALLOW_UNFREE=1 nix build \
	--refresh \
	--impure \
	--out-link "$result" \
	"${installables[@]}"

run attic push internal "$result"*
