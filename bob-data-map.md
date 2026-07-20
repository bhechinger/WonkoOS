# Bob service data map

Paths are on Bob unless noted otherwise.

## Native services

| Service | Persistent data | Notes |
|---|---|---|
| Paperless-ngx | `/home/docker/paperless/{consume,data,export,media}` | `consume` and `export` are NFS-exported to `10.42.0.10` |
| PostgreSQL 16 | `/home/docker/pgsql/paperless` | Paperless database cluster; stop PostgreSQL before raw backup |
| Redis | None required | Paperless broker state is disposable |
| Nginx | `/home/docker/reverse/{certs,html}` | Virtual-host configuration is declarative in `systems/bob/services.nix` |
| Cloudflared | `/var/lib/cloudflared/tunnel.env` | Root-only tunnel token |
| Jackett | `/home/docker/jackett` | Native data directory is `/home/docker/jackett/config/Jackett` |
| Sonarr | `/var/lib/sonarr` | Shows are on Basket at `/nfs/Plex/Shows` |
| rTorrent | `/var/lib/rtorrent` | Downloads are on Basket at `/nfs/Torrents` |
| ruTorrent | `/var/lib/rutorrent` | Includes profile data and HTTP basic-auth files |
| Plex | `/var/lib/plexmediaserver` | Media is on Basket at `/nfs/Plex` |
| Murmur | `/var/lib/mumble-server`, `/etc/mumble-server.ini` | Password is mapped into `murmurd.env` on restore |
| NFS server | `/var/lib/nfs`, declarative exports | Exports Paperless consume/export |
| Tailscale | `/var/lib/tailscale` | Node identity |
| ZeroTier | `/var/lib/zerotier-one` | Node identity and joined network |
| Postfix | Declarative configuration | No mail spool is preserved |

Paperless's secret-bearing runtime settings remain in
`/home/wonko/docker/paperless.env`; Docker-only `USERMAP_UID` and
`USERMAP_GID` entries are harmless but unused.

## Declarative OCI services

| Service | Persistent data | Reason it remains containerized |
|---|---|---|
| Proton Mail Bridge | Docker volume `protonmail` | Preserves the authenticated headless Bridge state |
| UniFi Network Application 7.5 | `/home/unifi/config` | Its MongoDB 3.6 database cannot jump directly to the MongoDB 7 used by the current native UniFi module |

Compose is no longer used. Docker's layer, network, log, and daemon state are
not backed up; the backup contains portable image archives for only these two
containers.

## Basket NFS data

| Mount | Source | Consumers |
|---|---|---|
| `/nfs/Brian` | `10.42.0.30:/Brian` | Bob backups |
| `/nfs/Plex` | `10.42.0.30:/Plex` | Plex and Sonarr |
| `/nfs/Torrents` | `10.42.0.30:/Torrents` | rTorrent and Sonarr |

Basket authorizes `bob.4amlunch.net` for `/Torrents`; Basket must resolve it to
`10.42.0.2` and reload its exports after a DNS change. Bob's restricted
`media` account is UID 999/GID 2000. Jackett, Sonarr, and rTorrent use its UID
because it already owns the NAS media/download trees created by the former
LinuxServer containers. Avahi is pinned separately to UID 992.

## Unrecoverable legacy state

The Ubuntu-to-NixOS backup deliberately omitted `/home/docker/sonarr`,
`/home/docker/rutorrent`, and the Docker `torrent-data` volume. Those paths do
not exist on the rebuilt Bob and neither retained backup contains them.
Consequently, Sonarr history/settings and the old rTorrent session/auth files
cannot be restored. The actual shows and downloaded payloads live on Basket
and were not lost.

The old GeoIP databases remain non-authoritative leftovers and are no longer
updated because no active service references them.
