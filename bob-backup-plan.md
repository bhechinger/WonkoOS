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
    images/
      active-images.tar           # every image used by a running container
      active-images.txt
      active-image-digests.txt
      active-images.tar.sha256
```

## Preflight

- Review `systems/bob/backup.sh` before running it.
- Confirm `/nfs/Brian` is mounted from `10.42.0.30:/Brian`.
- Confirm Bob can remain offline for application traffic after the backup.
- The script requires at least 20 GiB free and aborts before stopping services
  if any required Compose file, data path, image, or mount is missing.

## Run

From this repository, stream the reviewed script to Bob without installing or
copying it there:

```sh
ssh -F none bob 'sudo bash -s -- /nfs/Brian' < systems/bob/backup.sh
```

The script saves all images used by running containers before stopping Docker,
stops NFS exports and application services, copies only active service data,
verifies the copy with a dry-run rsync, and leaves application services down.
Libvirt data is archived for historical recovery only; the NixOS target does
not enable libvirt.

Sonarr, ruTorrent, Minecraft, Rancher, Authentik, unused Docker volumes, the
old Nix store, and unrelated user data remain excluded.

## Validation

- The command must exit zero and print the timestamped backup path.
- `metadata/COMPLETE` and `metadata/images/active-images.tar` must exist.
- Verify the recorded SHA-256 checksum.
- Load `active-images.tar` on a disposable Docker host and confirm every image
  in `active-images.txt` resolves locally.
- Confirm targeted application services remain stopped before installing
  NixOS.

Do not start the destructive NixOS installation until this validation is
complete.
