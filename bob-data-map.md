# bob service data map

Collected from `bob` over SSH. Paths are on `bob`.

## Storage base

- `/` is `/dev/mapper/ubuntu--vg-ubuntu--lv` (`ext4`).
- `/boot` is `/dev/nvme0n1p2`; `/boot/efi` is `/dev/nvme0n1p1`.
- No separate persistent mount was found for `/home`, `/var`, `/var/lib/docker`, `/nix`, or service data directories. They all live on `/`.
- Docker root: `/var/lib/docker` (`25G` total).

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
| `sonarr` | `/home/docker/sonarr/config`, `/var/lib/docker/volumes/docker_torrent-data/_data`, `/var/lib/docker/volumes/docker_plex-shows/_data` | config `156M`; volumes `4K` each | Container is exited but data remains |
| `rutorrent` | `/home/docker/rutorrent/data`, `/home/docker/rutorrent/passwd`, `/var/lib/docker/volumes/docker_torrent-data/_data` | `/home/docker/rutorrent`: `95M`; torrent volume `4K` | Container is exited but data remains |
| `cloudflared-tunnel` | no Docker mount found | n/a | Persistent config, if any, is likely in compose/env or Cloudflare-side, not a container mount |

Compose files that define the active containers:

- `/home/wonko/docker/docker-compose.yaml`
- `/home/wonko/unifi/docker-compose.yaml`

## Systemd service data

| Service | Persistent data / config | Size observed | Notes |
|---|---|---:|---|
| `plexmediaserver.service` | `/var/lib/plexmediaserver` | `6.9G` | Main Plex library/config/cache; runs as `plex` |
| `mumble-server.service` | `/etc/mumble-server.ini`, `/var/lib/mumble-server` | `16K`, `120K` | Mumble config and server state |
| `postfix.service`, `postfix@-.service` | `/etc/postfix`, `/var/spool/postfix` | `124K`, `3.1M` | Mail config and queue/spool |
| NFS stack: `nfs-server`, `nfs-*`, `rpc-*` | `/etc/exports`, `/var/lib/nfs` | `4K`, `84K` | Exports `/home/docker/paperless/consume` and `/home/docker/paperless/export` to `10.42.0.10` |
| `libvirtd.service`, `libvirt-guests.service`, `qemu-kvm.service` | `/etc/libvirt`, `/var/lib/libvirt`, `/var/lib/machines` | `256K`, `604K`, `4K` | Libvirt config/state; no large VM image directory found under `/var/lib/libvirt` |
| `tailscaled.service` | `/var/lib/tailscale` | `48K` | Tailscale node state/key material |
| `zerotier-one.service` | `/var/lib/zerotier-one` | `92K` | ZeroTier identity/network state |
| `ntp.service` | package config under `/etc`; runtime drift/state is small/default | n/a | No app data directory identified |
| `snap.canonical-livepatch.canonical-livepatchd.service` | `/var/snap/canonical-livepatch` | `1.5M` | Snap service state |
| `docker.service`, `containerd.service` | `/var/lib/docker`, plus service-specific bind mounts above | `25G` | Docker engine state, layers, named volumes, logs |
| `nix-daemon.service` | `/nix`, `/etc/nix` | `/nix`: `11G`; `/etc/nix`: `8K` | Service was inactive, but store/config exist |

## User systemd data

| User unit | Data/config paths | State |
|---|---|---|
| `wonko` `minecraft@perfect-world.service` | unit: `/home/wonko/.config/systemd/user/minecraft@.service`; script root: `/home/wonko/minecraft/perfect-world`; declared working dir: `/home/minecraft/perfect-world` | enabled but inactive; both instance paths were missing during collection |

Other `wonko` user units seen were baseline/inactive session agents (`dbus`, `gpg-agent`, `dirmngr`, `snapd.session-agent`, `gnome-keyring`, `session-migration`) with package-owned unit files under `/usr/lib/systemd/user`.

`chatgpt` had no active user manager, no linger entry, and no user service files under `/home/chatgpt/.config/systemd/user`.

## Named Docker volumes not attached to running containers

These named volumes exist and may be stale service data:

| Volume | Path | Size |
|---|---|---:|
| `docker_rancher-data` | `/var/lib/docker/volumes/docker_rancher-data/_data` | `2.6G` |
| `docker_authentik-database` | `/var/lib/docker/volumes/docker_authentik-database/_data` | `81M` |
| `docker_authentik-redis` | `/var/lib/docker/volumes/docker_authentik-redis/_data` | `300K` |
| `docker_paperless-*` | `/var/lib/docker/volumes/docker_paperless-{consume,data,export,media,pgsql-data}/_data` | `4K` each |
| `docker_plex-data`, `docker_plex-movies` | `/var/lib/docker/volumes/docker_plex-{data,movies}/_data` | `4K` each |

There are also many anonymous Docker volumes under `/var/lib/docker/volumes/<hash>/_data`; I did not map them to old containers because they are not mounted by the current service set.

## Biggest service data locations

1. `/var/lib/plexmediaserver` — `6.9G`
2. `/var/lib/docker/volumes/docker_rancher-data/_data` — `2.6G`, likely stale
3. `/home/docker/paperless` — `1.8G`
4. `/var/lib/docker/volumes/protonmail/_data` — `1.8G`
5. `/home/wonko/minecraft` — `1.2G` total, but the enabled `perfect-world` instance path was missing
6. `/home/unifi/config` — `836M`

## Notes / gaps

- I did not dump compose/env contents to avoid exposing secrets. Mounts and paths came from Docker inspect and targeted filesystem checks.
- `cloudflared-tunnel` has no mounted local data; its durable state may be in compose/env or Cloudflare.
- `sonarr`, `rutorrent`, and `minecraft@perfect-world` are inactive/exited but still have service definitions or data paths.
