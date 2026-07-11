# Plan: Quiesce `bob` and Back Up Active Service Data to NFS

## Summary

Back up only active/non-stale service data from `bob` to `10.42.0.30:/Brian` mounted at `/nfs/Brian`, then leave services down. Do not back up stale Docker volumes, exited container data, old Authentik/Rancher data, or unrelated anonymous volumes.

Backup layout:

```text
/nfs/Brian/bob-backups/<UTC_TIMESTAMP>/
  rootfs/      # rsync-preserved absolute paths
  metadata/    # service state, mount info, backup logs
```

## Runbook

1. Preflight before stopping anything:

   - SSH with `ssh -F none bob`.
   - Mount NFS if needed: `sudo mount /nfs/Brian`.
   - Verify `findmnt -T /nfs/Brian` shows `10.42.0.30:/Brian`.
   - Verify at least `20G` free on `/nfs/Brian`.
   - Create timestamped backup dir.
   - Test `rsync -aHAX --numeric-ids` on a tiny file; if ACL/xattr preservation fails on the NFS export, fall back to `rsync -aH --numeric-ids` and record that in metadata.

2. Stop services in consistency order:

   - Stop NFS exports first after the backup NFS mount is established, so remote clients stop writing Paperless consume/export during backup.
   - Stop Docker compose projects:
     - `/home/wonko/docker/docker-compose.yaml`
     - `/home/wonko/unifi/docker-compose.yaml`
     - `/home/wonko/AD/docker-compose.yaml`
   - Stop Docker engine/socket afterward: `docker.service`, `docker.socket`, `containerd.service`.
   - Stop active operator-managed systemd services: Plex, Mumble, Postfix, libvirt/qemu, Tailscale, ZeroTier, NTP, Canonical Livepatch.
   - Keep SSH, networking, and NFS-client plumbing running until the backup is verified.

3. Back up active service data with `rsync --relative` into `rootfs/`:

   - Docker/Compose active data:
     - `/home/docker/reverse`
     - `/home/docker/paperless`
     - `/home/docker/pgsql/paperless`
     - `/home/docker/redis`
     - `/var/lib/docker/volumes/protonmail/_data`
     - `/home/docker/jackett`
     - `/home/wonko/docker/data/geoip`
     - `/home/unifi/config`
     - `/home/samba/etc`
     - `/home/samba/lib`
     - `/home/wonko/AD/docker-compose.yaml`
     - `/home/wonko/AD/samba-admin-password`
     - `/home/wonko/AD/ad_console`
     - `/home/wonko/docker/docker-compose.yaml`
     - `/home/wonko/docker/.env`
     - `/home/wonko/docker/paperless.env`
     - `/home/wonko/unifi/docker-compose.yaml`

   - Systemd service data/config:
     - `/var/lib/plexmediaserver`
     - `/etc/mumble-server.ini`
     - `/var/lib/mumble-server`
     - `/etc/postfix`
     - `/var/spool/postfix`
     - `/etc/exports`
     - `/var/lib/nfs`
     - `/etc/libvirt`
     - `/var/lib/libvirt`
     - `/var/lib/tailscale`
     - `/var/lib/zerotier-one`
     - `/var/snap/canonical-livepatch`

   - User unit metadata:
     - `/home/wonko/.config/systemd/user/minecraft@.service`
     - Do not back up `/home/wonko/minecraft`; the enabled `perfect-world` instance path was missing, so treat existing Minecraft data as out-of-scope/stale for this run.

4. Explicitly exclude stale data:

   - `/home/docker/sonarr`
   - `/home/docker/rutorrent`
   - `/var/lib/docker/volumes/docker_torrent-data/_data`
   - `/var/lib/docker/volumes/docker_plex-shows/_data`
   - `/var/lib/docker/volumes/docker_rancher-data/_data`
   - `/var/lib/docker/volumes/docker_authentik-*`
   - old `docker_paperless-*`, `docker_plex-*`, `ad_etc`, `ad_lib`
   - anonymous Docker volumes
   - `/home/wonko/docker/authentik*`
   - `/home/wonko/docker/docker-compose.yaml.with-authentik`

5. Final state:

   - Run a dry-run rsync verification against the completed backup.
   - Save final `systemctl`, Docker, `df`, and `findmnt` output under `metadata/`.
   - Unmount `/nfs/Brian` after logs are flushed.
   - Leave application/operator services down; do not disable them.

## Validation

- Abort before stopping services if `/nfs/Brian` cannot mount or free space is insufficient.
- Backup succeeds only if rsync exits `0`.
- Verify key restore paths exist under `rootfs/`, especially:
  - `home/docker/paperless`
  - `home/docker/pgsql/paperless`
  - `var/lib/plexmediaserver`
  - `var/lib/docker/volumes/protonmail/_data`
  - `home/unifi/config`
  - `home/samba/lib`
- Confirm Docker containers and targeted systemd services remain stopped at the end.

## Assumptions

- Target NFS mount is `/nfs/Brian`, source `10.42.0.30:/Brian`.
- Services should remain down after backup.
- “Stale data” means exited/inactive app data and Docker volumes not mounted by active services.
- This is a one-shot filesystem backup, not a compressed archive and not a deduplicated backup system.
