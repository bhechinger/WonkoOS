# bob service data map

Collected from `bob` over SSH. Paths are on `bob`.

## Storage base

- `/` is `/dev/mapper/ubuntu--vg-ubuntu--lv` (`ext4`).
- `/boot` is `/dev/nvme0n1p2`; `/boot/efi` is `/dev/nvme0n1p1`.
- No separate persistent mount was found for `/home`, `/var`, `/var/lib/docker`, `/nix`, or service data directories. They all live on `/`.
- Docker root: `/var/lib/docker` (`25G` total); the engine state is not migrated.

## Docker / Compose data

| Service / container | Persistent data on host | Size observed | Notes |
|---|---|---:|---|
| `reverse` | `/home/docker/reverse/config`, `/home/docker/reverse/certs`, `/home/docker/reverse/html` | `/home/docker/reverse`: `272K` | nginx config, certs, static HTML |
| `paperless` | `/home/docker/paperless/{consume,data,export,media}` | `/home/docker/paperless`: `1.8G` | Paperless app data/documents; `consume` and `export` are also NFS-exported to `10.42.0.10` |
| `paperless-db` | `/home/docker/pgsql/paperless` | `131M` | PostgreSQL data directory |
| `paperless-broker` | `/home/docker/redis` | `8.0K` | Redis data |
| `protonmail-bridge` | `/var/lib/docker/volumes/protonmail/_data` | `1.8G` | Docker named volume mounted at container `/root` |
| `jackett` | `/home/docker/jackett/config`, `/home/docker/jackett/downloads` | `/home/docker/jackett`: `23M` | Jackett config/download handoff |
| `geoip-updater` | `/home/wonko/docker/data/geoip` | `72M` | GeoIP database output |
| `unifi-controller` | `/home/unifi/config` | `836M` | UniFi controller config/database |
| `sonarr` | `/home/docker/sonarr/config`, `/var/lib/docker/volumes/docker_torrent-data/_data` | config `156M`; volume `4K` | Container is exited but data remains |
| `rutorrent` | `/home/docker/rutorrent/data`, `/home/docker/rutorrent/passwd`, `/var/lib/docker/volumes/docker_torrent-data/_data` | `/home/docker/rutorrent`: `95M`; torrent volume `4K` | Container is exited but data remains |
| `cloudflared-tunnel` | no Docker mount found | n/a | Persistent config, if any, is likely in compose/env or Cloudflare-side, not a container mount |

Compose files that define the active containers:

- `/home/wonko/docker/docker-compose.yaml`
- `/home/wonko/unifi/docker-compose.yaml`

The migration keeps these Compose definitions, their referenced environment
files, the bind-mounted application data above, and the `protonmail` volume.
It does not copy Docker's layer, container, network, log, or daemon state.

## Systemd service data

| Service | Persistent data / config | Size observed | Notes |
|---|---|---:|---|
| `plexmediaserver.service` | `/var/lib/plexmediaserver` | `6.9G` | Main Plex library/config/cache; runs as `plex` |
| `mumble-server.service` | `/etc/mumble-server.ini`, `/var/lib/mumble-server` | `16K`, `120K` | Mumble config and server state |
| NFS stack: `nfs-server`, `nfs-*`, `rpc-*` | `/etc/exports`, `/var/lib/nfs` | `4K`, `84K` | Exports `/home/docker/paperless/consume` and `/home/docker/paperless/export` to `10.42.0.10` |
| `tailscaled.service` | `/var/lib/tailscale` | `48K` | Tailscale node state/key material |
| `zerotier-one.service` | `/var/lib/zerotier-one` | `92K` | ZeroTier identity/network state |
| `ntp.service` | package config under `/etc`; runtime drift/state is small/default | n/a | No app data directory identified |

Other `wonko` user units seen were baseline/inactive session agents (`dbus`, `gpg-agent`, `dirmngr`, `snapd.session-agent`, `gnome-keyring`, `session-migration`) with package-owned unit files under `/usr/lib/systemd/user`.

`chatgpt` had no active user manager, no linger entry, and no user service files under `/home/chatgpt/.config/systemd/user`.

## Ignored legacy Paperless volumes

The empty `docker_paperless-{consume,data,export,media,pgsql-data}` volumes were
created by an older Compose definition on 2024-06-08. No container attaches to
them and the current Compose file no longer declares them. Current Paperless,
PostgreSQL, and Redis data lives in the bind mounts listed above, so these
legacy volumes are not backed up or restored.

There are also many anonymous Docker volumes under `/var/lib/docker/volumes/<hash>/_data`; I did not map them to old containers because they are not mounted by the current service set.

## Biggest service data locations

1. `/var/lib/plexmediaserver` — `6.9G`
2. `/home/docker/paperless` — `1.8G`
3. `/var/lib/docker/volumes/protonmail/_data` — `1.8G`
4. `/home/unifi/config` — `836M`

## Notes / gaps

- I did not dump compose/env contents to avoid exposing secrets. Mounts and paths came from Docker inspect and targeted filesystem checks.
- `cloudflared-tunnel` has no mounted local data; its durable state may be in compose/env or Cloudflare.
- `sonarr` and `rutorrent` are inactive/exited but still have service definitions or data paths.
