#!/usr/bin/env bash
set -euo pipefail

for mountpoint in / /nix /var /var/lib/docker /home; do
  findmnt "$mountpoint"
done

zfs mount
zpool list basket
systemctl status zfs-mount.service zfs-import-basket.service --no-pager
systemctl --failed
