# Bob NixOS migration

Bob is configured as a single-node NixOS server on its existing 477 GiB NVMe.
The install is destructive and must only run after the backup in
[`bob-backup-plan.md`](../../bob-backup-plan.md) has completed and passed its
dry-run verification.

## Service model

| Workload | Choice | Reason |
|---|---|---|
| Plex, Murmur, Postfix, NFS, Tailscale, ZeroTier | NixOS modules | Stable native modules, direct systemd supervision, no container layer needed. |
| Paperless/PostgreSQL/Redis, nginx, ProtonMail Bridge, Jackett, GeoIP updater, Cloudflare Tunnel | Existing Docker Compose | Lowest-risk restoration of current images, environment files, bind mounts, and PostgreSQL major version. |
| UniFi | Existing Docker Compose | Preserves the application database and existing device adoption. |
| Kubernetes | Not used | One host has no failover benefit; Kubernetes complicates multicast and local persistent data. |

This is deliberately a lift-and-shift first. Convert individual Compose
services to NixOS modules only after the restored system is stable and each
application has a tested export/import path.

## Network policy

Bob has an internal network at `10.42.0.2`, a management network at
`10.42.11.2`, and an unnumbered guest bridge. The old external and storage
bridges are not recreated. Internal, Tailscale, and ZeroTier clients retain
the existing service access. Management is restricted to the UniFi device
plane: TCP `8080` and UDP `3478`, `10001`, `1900`, and `5514`. Docker enforces
the same restriction in its forwarding path.

## Storage

Disko destroys `/dev/disk/by-id/nvme-eui.6479a741b05004c5` and creates:

- a 1 GiB EFI system partition;
- 1 GiB emergency swap plus compressed zram swap;
- one ZFS pool, `zpool`, with datasets for `/`, `/nix`, `/var`, Docker, Plex,
  `/home`, and PostgreSQL;
- 16 KiB ZFS records for Plex metadata and PostgreSQL, with `zstd`, POSIX ACLs,
  xattrs, weekly scrubs, and SSD trim.

The service datasets retain the Ubuntu path layout, so the NFS backup can be
restored without rewriting Compose bind mounts.

## Before deployment

1. Review and run `systems/bob/backup.sh` as described in the backup plan; it
   leaves Ubuntu's application services down.
2. Record the chosen timestamp directory under
   `/nfs/Brian/bob-backups/<UTC_TIMESTAMP>`.
3. Confirm the backup contains `metadata/COMPLETE`, the required restore paths,
   and `metadata/images/active-images.tar`.
4. Confirm the target disk identity again:

   ```sh
   ssh -F none bob 'ls -l /dev/disk/by-id/nvme-eui.6479a741b05004c5'
   ```

5. Fix the local system SSH include before using nixos-anywhere. Ordinary SSH
   currently rejects its ownership while `ssh -F none` bypasses it:

   ```sh
   sudo chown root:root /etc/ssh/ssh_config.d/30-libvirt-ssh-proxy.conf
   sudo chmod 0644 /etc/ssh/ssh_config.d/30-libvirt-ssh-proxy.conf
   ssh bob true
   ```

6. Evaluate and build Bob locally:

   ```sh
   nix build .#nixosConfigurations.bob.config.system.build.toplevel
   nix run github:nix-community/nixos-anywhere -- --flake .#bob --vm-test
   ```

## Destructive deployment

Supply the private key that currently logs in as `wonko`. `--copy-host-keys`
keeps Bob's existing SSH host identity across the reinstall.

```sh
nix run github:nix-community/nixos-anywhere -- \
  --flake .#bob \
  --target-host wonko@bob \
  --build-on local \
  --copy-host-keys \
  -i /path/to/bob-login-key
```

Nixos-anywhere kexecs from Ubuntu, destroys the selected NVMe, applies the
Disko ZFS layout, installs NixOS, and reboots. Do not run this command until the
NFS backup has been independently verified.

## Restore

Application services have `ConditionPathExists=/var/lib/bob-restored`, so the
first NixOS boot exposes only SSH, networking, the NFS backup/Plex automounts,
and the Docker engine. Restore from the exact verified backup:

```sh
ssh bob
sudo bob-restore /nfs/Brian/bob-backups/<UTC_TIMESTAMP>
```

The restore command:

- copies only the active paths listed in the backup plan;
- loads every image used by the backed-up running containers and forbids
  implicit pulls during Compose startup;
- recreates the `protonmail` Docker volume before restoring its data;
- maps the Ubuntu Mumble database and password into the NixOS Murmur service;
- fixes native Plex and Murmur ownership after preserving numeric IDs for
  container data;
- retains old Postfix configuration under `/var/lib/bob-legacy` for inspection,
  while the active Postfix configuration is declarative;
- writes `/var/lib/bob-restored`, starts native and Compose services, and
  removes the marker again if startup fails so the restore can be retried.

Samba AD, Sonarr, ruTorrent, Minecraft, Rancher, Authentik, anonymous Docker
volumes, Canonical Livepatch, libvirt, and the old Nix store are not restored.
The stopped `sierra` definition remains only in the NFS backup; no VM disk was
found and libvirt is not enabled on NixOS.

## Validation

```sh
zpool status
zfs list
systemctl --failed
systemctl status compose-main compose-unifi
docker ps
iptables -S BOB-DOCKER
findmnt /nfs/Brian
findmnt /nfs/Plex
```

Check Paperless, Plex, Mumble, UniFi, Postfix port 25, and both Paperless NFS
exports from their clients. From the management network, verify that only the
UniFi device-plane ports are reachable. Confirm the same services remain
available from internal, Tailscale, and ZeroTier before considering the
migration complete.
