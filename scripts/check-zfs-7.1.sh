#!/usr/bin/env bash
set -euo pipefail

cd -- "$(dirname -- "$0")/.."

# Nix, not Bash, expands ${...}.
# shellcheck disable=SC2016
compatible="$(
  nix eval --impure --json --expr '
    let
      flake = builtins.getFlake "path:${toString ./.}";
      pkgs = flake.inputs.nixpkgs.legacyPackages.x86_64-linux;
    in
    (builtins.tryEval pkgs.linuxPackages_7_1.zfs.drvPath).success
  '
)"

if [[ $compatible == true ]]; then
  echo "Linux 7.1 is compatible with ZFS in the locked stable nixpkgs input."
else
  echo "Linux 7.1 is not compatible with ZFS in the locked stable nixpkgs input."
  exit 1
fi
