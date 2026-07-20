# Bob backup runbook

The repository only stages the backup process. Nothing in this file or
`systems/bob/backup.sh` changes the existing Ubuntu host until an operator
explicitly runs the command below.

The backup is written to:

```text
/nfs/Brian/bob-backups/<UTC_TIMESTAMP>/
  rootfs/                         # rsync-preserved active service paths
  metadata/
    COMPLETE                      # written only after verification succeeds
    SOURCE-{RESTARTED,STOPPED}    # exactly one records the final source state
    native-units-active.txt
    compose-{main,unifi}-running.txt
    containers-running-{before,after}.txt
    plex-database-{0,1}-check.txt
    images/
      active-images.tar           # every image used by a running container
      active-images.txt
      active-image-digests.txt
      active-images.tar.sha256
```

## Preflight

- Review `systems/bob/backup.sh` before running it.
- Add Bob's internal address, `10.42.0.2`, to the NAS NFS permissions for
  `/Brian`, with read/write access and no user mapping so root can preserve
  numeric ownership, ACLs, and xattrs. This is an external NAS change and is
  intentionally not made by this repository.
- Confirm `/nfs/Brian` is mounted read/write from `10.42.0.30:/Brian`. The
  script verifies the source and performs a write probe before stopping anything.
- Schedule a service interruption for the consistent application-data copy.
- The script requires at least 20 GiB free and aborts before stopping services
  if any required Compose file, data path, image, or mount is missing.

## Run

From this repository, stream the reviewed script to Bob without installing or
copying it there:

```sh
ssh -F none bob 'sudo bash -s -- /nfs/Brian' < systems/bob/backup.sh
```

The script records the exact active native units, running Compose services, and
container names before making changes. It saves all images used by running
containers, stops only that recorded application set, checks both Plex
databases with Plex SQLite, copies the curated service data, and verifies the
copy with a dry-run rsync. An exit trap restores the recorded source state on
success, error, interruption, or failed verification. The image archive is a
portable input for the fresh Docker installation, not a copy of Docker's
engine state.

For the final cutover, keep that recorded service set stopped after a
successful backup:

```sh
ssh -F none bob 'sudo bash -s -- --leave-stopped /nfs/Brian' < systems/bob/backup.sh
```

This writes `metadata/SOURCE-STOPPED` instead of `SOURCE-RESTARTED`. Errors,
interruptions, and failed verification still restore the original service
state. Do not use this option until the maintenance window has started.

Libvirt is excluded: a live check found no running domains, and the only
defined domain has no disk, installation ISO, or managed save.

The retired Samba AD service, Sonarr, ruTorrent, Snap and Canonical Livepatch,
Docker engine state and unused volumes, the old Nix store and daemon
configuration, and unrelated user data remain excluded.

## Validation

- The command must exit zero and print the timestamped backup path.
- `metadata/COMPLETE`, `metadata/images/active-images.tar`, and exactly one of
  `metadata/SOURCE-RESTARTED` or `metadata/SOURCE-STOPPED` must exist.
- Verify the recorded SHA-256 checksum.
- For a normal backup, confirm the before/after container lists are identical,
  every recorded native unit is active, and there are no
  `new-failed-units.txt`, `native-units-not-restarted.txt`, or
  `container-state.diff` files.
- For `--leave-stopped`, confirm the recorded native and Compose services and
  Docker remain stopped.
- Confirm both Plex check files contain only `ok`.

## Disposable restore test

Build and run the isolated NixOS VM from the local checkout. The backup path is
validated and staged as a single compressed archive outside the Nix store:

```sh
nix run .#bob-vm-test -- /nfs/Brian/bob-backups/<UTC_TIMESTAMP>
```

The runner requires 40 GiB free under `/tmp`, uses KVM when available (with a
slower TCG fallback), creates a fresh 64 GiB VM disk, mounts the staged backup
read-only, and disables guest network access to the host, LAN, and Internet. It
always deletes the VM disk and staged archive when the run ends.

The guest runs the normal `bob-restore`, then checks native units, exact active
Compose workloads, Paperless/PostgreSQL/Redis health, Plex identity and
databases, Murmur and Postfix listeners, NFS exports, application HTTP ports,
the Proton volume, and failed systemd units. Sonarr and ruTorrent must remain
absent. Cloudflare, GeoIP, overlay control planes, Proton's remote service,
UniFi adoption, NAS media, and external SMTP are reported as expected degraded
checks because the VM is intentionally isolated.

Results are stored with mode `0700` below:

```text
${XDG_STATE_HOME:-$HOME/.local/state}/wonkoos/bob-vm-tests/
```

A successful run contains `PASS`, `summary.txt`, `checks.tsv`, service and
container inventories, and `serial.log`. A failure contains `FAIL` and the same
diagnostic artifacts when the guest was able to write them.

Do not start the destructive NixOS installation until the completion and
source-state markers and a VM `PASS` result have been reviewed.
