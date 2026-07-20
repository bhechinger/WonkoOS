# Bob backup runbook

Bob's backup is written to:

```text
/nfs/Brian/bob-backups/<UTC_TIMESTAMP>/
  rootfs/
  metadata/
    COMPLETE
    SOURCE-{RESTARTED,STOPPED}
    native-units-active.txt
    containers-running-{before,after}.txt
    images/
      active-images.tar
      active-images.txt
      active-image-digests.txt
      active-images.tar.sha256
```

## Preflight

- Confirm `/nfs/Brian` is mounted read/write from `10.42.0.30:/Brian`.
- Confirm at least 20 GiB is free.
- Review [`systems/bob/backup.sh`](systems/bob/backup.sh).
- Schedule an interruption: the script stops application units so PostgreSQL,
  Paperless, Plex, UniFi, and the other stateful services are copied
  consistently.

## Run

Normal backup:

```sh
sudo systems/bob/backup.sh /nfs/Brian
```

The exit trap restores exactly the service units that were active before the
backup, even after an error or interruption.

For a planned reinstall or recovery test, leave that service set stopped after
a successful backup:

```sh
sudo systems/bob/backup.sh --leave-stopped /nfs/Brian
```

This writes `metadata/SOURCE-STOPPED`. Errors still restore the original
service state.

The curated data includes native Paperless/PostgreSQL, Nginx certificates and
static content, Jackett, Sonarr, rTorrent/ruTorrent, Cloudflared credentials,
Plex, Murmur, NFS, Tailscale, ZeroTier, UniFi, and the Proton Mail Bridge
volume. The archive contains only the images for the two declarative OCI
services: UniFi and Proton Mail Bridge.

Docker engine state, Compose files, Redis's disposable Paperless broker state,
the unused GeoIP databases, Snap, the old Nix installation, libvirt, and
unrelated user data are excluded.

## Validation

- The command exits zero and prints the timestamped backup path.
- `metadata/COMPLETE`, the image archive and checksum, and exactly one source
  state marker exist.
- For a normal backup, before/after container lists match, all recorded units
  are active, and there are no `new-failed-units.txt`,
  `native-units-not-restarted.txt`, or `container-state.diff` files.
- Both Plex database checks contain only `ok`.

## Disposable restore test

```sh
nix run .#bob-vm-test -- /nfs/Brian/bob-backups/<UTC_TIMESTAMP>
```

The isolated VM runs `bob-restore` and verifies the native services, native
PostgreSQL/Redis readiness, the two retained OCI containers, HTTP endpoints,
Plex databases, NFS exports, and failed units. Internet control planes,
external SMTP, NAS media, UniFi adoption, and Proton connectivity are expected
to degrade in the isolated guest.

Do not rely on a backup until its result directory contains `PASS`.
