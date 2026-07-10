# WonkoOS

This is the NixOS configuration of all (eventually) my machines.

## Storage installation

The `deepthought` disko layout manages only the two local NVMe drives. It never
manages the remote iSCSI `basket` pool. Normal NixOS rebuilds do not run disko.

From an installer, mount and reinstall an existing layout without formatting:

```sh
sudo nix run .#disko-install -- \
  --mode mount \
  --flake .#deepthought \
  --disk os /dev/disk/by-id/nvme-WDC_WDS100T2B0C-00PXH0_21281Y459408 \
  --disk tank /dev/disk/by-id/nvme-WDS200T1XHE-00AFY0_21143L800578
```

For blank replacement drives, inspect the command first:

```sh
sudo nix run .#disko-install -- \
  --dry-run \
  --mode format \
  --flake .#deepthought \
  --disk os /dev/disk/by-id/OS_DISK \
  --disk tank /dev/disk/by-id/TANK_DISK
```

Remove `--dry-run` only when both target drives are blank or disposable. Do not
use disko's `destroy` mode for repair or reinstallation.

## One-time native ZFS mount migration

The disko layout uses NixOS mounts only for `/` and `/nix`. OpenZFS mounts
`/var`, `/var/lib/docker`, and `/home` natively. Install the new boot generation
first, then run these commands from a maintenance shell:

```sh
make boot
sudo zfs set -u mountpoint=legacy zpool/root
sudo zfs set -u mountpoint=legacy zpool/nix
sudo zfs set -u mountpoint=/var zpool/var
sudo zfs set -u mountpoint=/var/lib/docker zpool/docker
sudo reboot
```

Do not use `make switch` for this migration. After reboot, verify with:

```sh
for mountpoint in / /nix /var /var/lib/docker /home; do findmnt "$mountpoint"; done
zfs mount
systemctl --failed
```

To roll the dataset properties back before booting the previous generation:

```sh
sudo zfs set -u mountpoint=none zpool/root
sudo zfs set -u mountpoint=none zpool/nix
sudo zfs set -u mountpoint=none zpool/var
sudo zfs set -u mountpoint=none zpool/docker
```

`tank/home` already has the native `/home` mountpoint and needs no migration.
After local ZFS mounts are ready, `zfs-import-basket.service` imports the remote
pool normally and ZFS mounts its datasets under `/basket` and `/home/wonko`.
