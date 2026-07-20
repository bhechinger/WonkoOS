# Bob

Bob is a single-node NixOS server on ZFS. Its service definitions live in
[`services/`](./services/); Docker Compose is not part of the runtime model.

## Service model

| Workload | Runtime | Persistent data |
|---|---|---|
| Paperless-ngx | Native NixOS module with native PostgreSQL 16 and Redis | `/home/docker/paperless`, `/home/docker/pgsql/paperless`, `/home/wonko/docker/paperless.env` |
| Nginx | Native NixOS module | `/home/docker/reverse/{certs,html}` |
| Jackett | Native NixOS module | `/home/docker/jackett` |
| Sonarr | Native NixOS module | `/var/lib/sonarr`; shows at `/nfs/Plex/Shows` |
| rTorrent and ruTorrent | Native NixOS modules | `/var/lib/{rtorrent,rutorrent}`; downloads at `/nfs/Torrents` |
| Cloudflare Tunnel | Native `cloudflared` systemd service | `/var/lib/cloudflared/tunnel.env` |
| Plex, Murmur, Postfix, NFS, Tailscale, ZeroTier | Native NixOS modules | Their standard state paths |
| Proton Mail Bridge | Declarative OCI container | Docker volume `protonmail` |
| UniFi Network Application | Declarative OCI container | `/home/unifi/config` |

UniFi remains containerized because the restored controller is version 7.5
with MongoDB 3.6. NixOS supplies UniFi 10 with MongoDB 7, and MongoDB does not
support skipping the intervening major-version upgrades. Proton Mail Bridge
remains containerized because its headless image and existing authenticated
state are the reliable server deployment.

The GeoIP updater was removed because no service consumes its databases.
Sonarr and ruTorrent were absent from the curated Ubuntu-to-NixOS backup, so
their former local settings, history, and torrent session could not be
recovered. Their media and download trees remain on Basket and the native
services use those NFS shares.
Sonarr is configured with `/nfs/Plex/Shows`, the local rTorrent client, and
TorrentLeech through Jackett. Existing shows still require a library import
because the lost Sonarr state included their exact matches, monitoring
choices, and quality profiles.

## Network policy

Bob has an internal network at `10.42.0.2`, a management network at
`10.42.11.2`, and an unnumbered guest bridge. Internal, Tailscale, and ZeroTier
clients can reach application ports. Management is restricted to the UniFi
device plane: TCP `8080` and UDP `3478`, `10001`, `1900`, and `5514`.

Nginx serves the existing HTTPS names for Bob, Basket, Paperless, Jackett,
Sonarr, and ruTorrent. Paperless also retains its direct port `8001`. The
rTorrent XML-RPC listener is bound only to `127.0.0.1:9000`. ruTorrent requires
basic authentication; retrieve the generated initial password once with:

```sh
sudo cat /var/lib/rutorrent/initial-password
```

Delete that plaintext file after recording the password. The active password
hash is `/var/lib/rutorrent/htpasswd`.

## Storage

ZFS datasets back `/`, `/nix`, `/var`, `/var/lib/docker`,
`/var/lib/plexmediaserver`, `/home`, and `/home/docker/pgsql`. Basket is
automounted over NFS at:

- `/nfs/Brian`
- `/nfs/Plex`
- `/nfs/Torrents`

Basket authorizes `bob.4amlunch.net` for `/Torrents`; that name must resolve on
Basket to Bob's stable address, `10.42.0.2`. Reload Basket's exports with
`sudo exportfs -ra` after changing that DNS record. Jackett, Sonarr, and
rTorrent run as Bob's restricted `media` account (`uid 999`, `gid 2000`).
Avahi is pinned to UID 992 so it cannot share that NAS identity. UID 999
matches the existing Shows and Torrents trees created by LinuxServer images.

## Build and activate

The Makefile chooses the flake configuration from the local hostname:

```sh
make build
make switch
```

Before a service-data migration, create a recursive ZFS snapshot and a
PostgreSQL logical dump. Do not activate a change that repoints PostgreSQL at
an existing data directory until the old database writer is stopped and the
directory is owned by the native `postgres` user.

## Backup and restore

Run a normal backup with:

```sh
sudo systems/bob/backup.sh /nfs/Brian
```

Use `--leave-stopped` only for a planned recovery or reinstall. The script
records and stops the active native/OCI service units, saves the two retained
container images, copies the curated state with ACLs/xattrs/numeric IDs,
verifies the copy, and restores the original service state unless explicitly
asked to leave it stopped.

Restore a verified backup with:

```sh
sudo bob-restore /nfs/Brian/bob-backups/<UTC_TIMESTAMP>
```

Application services are gated by `/var/lib/bob-restored`, so a fresh system
does not expose empty services before restoration. Validate with:

```sh
systemctl --failed
systemctl status nginx postgresql paperless-web jackett sonarr rtorrent
systemctl status docker-protonmail-bridge docker-unifi-controller
docker ps
findmnt /nfs/Brian /nfs/Plex /nfs/Torrents
```
