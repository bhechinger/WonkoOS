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
    if builtins.hasAttr "linuxPackages_7_2" pkgs then
      let
        kernelPackages = pkgs.linuxPackages_7_2;
        zfs = kernelPackages.${pkgs.zfs.kernelModuleAttribute};
      in
      (builtins.tryEval (
        assert zfs.version == "2.4.4";
        zfs.drvPath
      )).success
    else
      false
  '
)"

if [[ $compatible == true ]]; then
  echo "OpenZFS 2.4.4 is compatible with Linux 7.2 in the locked stable nixpkgs input."
else
  echo "OpenZFS 2.4.4 is not compatible with Linux 7.2 in the locked stable nixpkgs input."
  exit 1
fi
