# Bob

Bob is a NixOS server on ZFS. Each workload has a module in
[`services/`](./services/); Docker and Docker Compose are not part of the
runtime model.

## Services

| Workload | Persistent state |
|---|---|
| Paperless-ngx | `/var/lib/paperless` and `/var/lib/postgresql/paperless` |
| Tandoor Recipes | `/var/lib/tandoor-recipes` and the `tandoor_recipes` database in `/var/lib/postgresql/paperless` |
| Proton Mail Bridge | `/var/lib/protonmail-bridge` |
| UniFi Network Application | `/var/lib/unifi` |
| Nginx | `/var/www` and ACME state under `/var/lib/acme` |
| Jackett | `/var/lib/jackett` |
| Sonarr | `/var/lib/sonarr` |
| rTorrent and ruTorrent | `/var/lib/{rtorrent,rutorrent}` and `/nfs/Torrents` |
| Plex | `/var/lib/plexmediaserver` and `/nfs/Plex` |
| Jellyfin | `/var/lib/jellyfin` and `/nfs/Plex` |
| Attic Nix cache | `/var/lib/atticd` and Basket at `/nfs/NixCache` |
| pwppp Minecraft server | `/var/lib/minecraft/pwppp` |
| Minecraft routers and Playit | Stateless; configuration is in this repository |
| Murmur, Postfix, NFS, Tailscale, ZeroTier | Their standard NixOS state paths |

Runtime credentials for Attic, Paperless, Tandoor, Cloudflare Tunnel,
Minecraft RCON and backups, Playit, Murmur, and ruTorrent are encrypted with
SOPS in [`secrets/`](./secrets/) and materialized under `/run/secrets`. Do not
recreate plaintext copies under `/home` or `/var/lib`.

Paperless connects to the native Proton Mail Bridge on loopback port `1143`
using STARTTLS. The Bridge certificate is trusted through
`/var/lib/paperless/proton-bridge-ca.pem`. Its scheduler and task queue order
themselves after the Bridge, so mail fetching does not depend on a container
hostname.

UniFi is the native NixOS service. Import controller state from a UniFi `.unf`
backup through the setup UI at `https://bob.4amlunch.net:8443`; do not copy an
old MongoDB data directory into `/var/lib/unifi`.

## Network policy

Bob has an internal network at `10.42.0.2` and a management network at
`10.42.11.2`. The management interface exposes only the UniFi device plane:
TCP `8080` and UDP `1900`, `3478`, `5514`, and `10001`. Administration and all
other application traffic use internal, Tailscale, or ZeroTier.

Nginx serves Bob, Paperless, Tandoor, Jackett, Jellyfin, Sonarr, and ruTorrent
with the wildcard ACME certificate. It also serves the Minecraft server list
and current pwppp client pack at `https://minecraft.4amlunch.net`. Unknown HTTP
hosts receive `444` and unknown TLS handshakes are rejected. The rTorrent
XML-RPC listener is only reachable through its Unix socket and the loopback
nginx endpoint.

Attic listens only on loopback and Nginx exposes it internally at
`https://cache.4amlunch.net`. Pulls are public on the trusted networks; pushes
use a shared cache-scoped Attic token. The hostname is managed only in
OPNsense and is deliberately absent from public DNS and Cloudflare Tunnel.

Jellyfin is available at `https://jellyfin.4amlunch.net` on the private
networks. Complete its first-run wizard there and add `/nfs/Plex` as the media
library. Then set Dashboard > Networking > Known Proxies to `127.0.0.1`. Intel
VA-API handles supported transcoding through `/dev/dri/renderD128`; Jellyfin
state is included in the hourly `/var` backup.

The Packwiz source uses Modrinth for Create: Oxidized and Create: Design n'
Decor so Bob can fetch them reproducibly. The generated CurseForge client ZIP
substitutes the matching CurseForge file IDs because CurseForge exports omit
Modrinth entries. Update both sets of pinned metadata when changing either mod.

Tandoor is available at `https://recipes.4amlunch.net`. It uses local accounts
with public signup disabled; create the initial administrator on Bob with:

```sh
sudo sh -c 'set -a; . /run/secrets/tandoor-environment; exec /var/lib/tandoor-recipes/tandoor-recipes-manage createsuperuser'
```

Until that administrator exists, the one-time `/setup/` wizard is reachable
only from the internal and Tailscale networks.

Share invitation links manually. Tandoor has no SMTP configuration, so an
administrator must also handle password resets.

`cloudflare-tunnel-sync.service` declaratively manages the remotely managed
Cloudflare Tunnel, Spectrum app, and public DNS records. It publishes
Paperless, Tandoor, and the Minecraft download page through
`https://localhost:443`, using each public hostname for the TLS and HTTP host
names. TLS verification remains enabled.

`mc-router` accepts Minecraft TCP traffic on internal port `25565` and routes
`pwppp.4amlunch.net` to the isolated NeoForge listener at
`127.0.0.11:25566`. `svc-router` accepts Simple Voice Chat UDP traffic on
internal port `34934`, while its webhook API is loopback-only. Both routers
run as dynamic, heavily sandboxed users. The game server is online-mode and
whitelist-only; add a player from Bob with:

```sh
printf 'whitelist add PLAYER_NAME\n' > /run/minecraft/pwppp.stdin
```

Sierra's BIND server is authoritative for the internal `4amlunch.net` view.
`opnsense-dns-sync.service` reconciles its complete static record set from
[`opnsense-dns.nix`](./services/opnsense-dns.nix); Kea owns the delegated
`lan.4amlunch.net` subzone. Bob serves secondary copies of both forward zones
and their two IPv4 reverse zones, and performs recursion independently so DNS
continues working if Sierra is unavailable. DHCP advertises Sierra first and
Bob second on both LANs. Public-only Cloudflare names deliberately do not
resolve internally unless they are also added to that Nix record list.

Internet game traffic enters the `minecraft-tcp.4amlunch.net` Spectrum app on
TCP `25565`. Public DNS-only aliases `pwppp.4amlunch.net` and
`gigglesomething.4amlunch.net` point to that app. Spectrum forwards to Sierra's
current WAN IPv4, where DNAT sends TCP `25565` to Bob at
`10.42.0.2:25565` and a separate WAN pass rule admits only Cloudflare sources;
`mc-router` then selects the server from the requested hostname. The reconciler
refreshes the Spectrum origin every five minutes so WAN DHCP changes do not
require manual updates.

The Spectrum token in `secrets/cloudflare-spectrum.sops` is separate from the
ACME/tunnel token and is limited to the `4amlunch.net` zone with **Zone
Settings: Edit**. Sierra uses the URL-table alias `Cloudflare_Spectrum_IPv4`,
populated hourly from `https://www.cloudflare.com/ips-v4`. Its WAN TCP `25565`
pass rule accepts that alias as its only source; the corresponding port forward
redirects to `10.42.0.2:25565` with NAT reflection disabled.

Internet voice traffic remains on Playit UDP at `147.185.221.19:34934`,
forwarded to `127.0.0.1:34934`. Public `voice.4amlunch.net` DNS points to that
Playit IP and is DNS-only. Apply or inspect the declarative Cloudflare state
with:

```sh
sudo systemctl restart cloudflare-tunnel-sync
systemctl status cloudflare-tunnel-sync cloudflared-tunnel
```

## Storage

ZFS datasets back `/`, `/nix`, `/var`, `/var/lib/jackett`,
`/var/lib/minecraft`, `/var/lib/paperless`, `/var/lib/plexmediaserver`,
`/var/lib/postgresql`, `/var/lib/redis-paperless`, `/var/www`, and `/home`. Basket is
automounted over NFSv4 at `/nfs/Restic`, `/nfs/NixCache`, `/nfs/Plex`, and
`/nfs/Torrents`; Bob does not mount the `Brian` share.

Tandoor media stays on the parent `/var` dataset at
`/var/lib/tandoor-recipes/media`; no separate dataset is required.

Jackett, Sonarr, rTorrent, and Plex keep separate service accounts. Basket's
NFS host entries for Bob on both `Plex` and `Torrents` use **Squash all users**
and map to the dedicated QNAP user `bob-nfs` and group `bob-media`. Those
identities have access only to the two media shares. This lets the services
share NFS data without sharing their local Unix identities or using QNAP's
generic anonymous account. NFS exports of the Paperless consume/export
directories separately map the single authorized client (`10.42.0.10`) to the
Paperless account with `all_squash`.

Bob's Restic server stores the primary `bob` and `deepthought` repositories
under `/nfs/Restic`. Clients use HTTPS and do not mount or know the
NFS storage path. Normal Restic commands and restores therefore use Bob's
NFS-backed endpoint.

Create the `NixCache` share on Basket with a 1 TiB quota and Bob
as its only NFS client. Squash all users to a dedicated `nix-cache` QNAP
account. Attic is the sole NFS writer; other hosts publish through its HTTPS
API. See the [cache runbook](../../docs/superpowers/plans/2026-07-10-harmonia-cache.md)
for bootstrap and client setup.

Bob serves the NFS primary through the append-only endpoint at
`https://restic.4amlunch.net`. Bob copies missing snapshots to the private
`4amlunch-restic` Backblaze B2 bucket daily at 05:30 for Bob and 06:00 for
Deepthought. The separate
append-only endpoint at `https://restic-b2.4amlunch.net` exposes that mirror
for disaster recovery. Both endpoints are available only through the private
networks. Bob and Deepthought have isolated repositories; only Bob's mirror
and weekly maintenance jobs have delete-capable B2 credentials. If NFS is
unavailable, use `sudo restic-bob-b2` on Bob or `sudo restic-deepthought-b2`
on Deepthought.

Bob service state is backed up from temporary ZFS snapshots at the start of
each hour.

Tandoor also writes an hourly zstd-compressed logical database dump to
`/var/backup/postgresql/tandoor_recipes.sql.zstd`; the next Bob service backup
captures it alongside the media directory. Restore the database dump and media
directory together while `tandoor-recipes.service` is stopped.

Minecraft keeps its two backup layers: Sanoid retains 24 hourly, 14 daily,
and 3 monthly snapshots on Bob, while Restic takes a consistent ZFS snapshot
after an RCON `save-all flush` and backs it up every four hours at 00:40,
04:40, 08:40, 12:40, 16:40, and 20:40. Deepthought backs up its home dataset
and a PostgreSQL logical dump hourly at 20 minutes past the hour. All backup
timers add up to 15 minutes of randomized delay.

After each successful B2 mirror, Restic retains hourly and four-hour snapshots
for 24 hours, daily snapshots for 7 days, and monthly snapshots for 6 months
on both NFS and B2. Weekly maintenance physically prunes unreferenced data and
checks both repositories. Backup, mirror, retention, and maintenance commands
wait up to two hours for repository locks.

Check or trigger the Bob jobs with:

```sh
systemctl status sanoid.timer restic-backups-bob-services.timer \
  restic-backups-minecraft.timer restic-maintenance-nfs.timer \
  restic-copy-bob.timer restic-copy-deepthought.timer \
  restic-maintenance.timer
sudo systemctl start restic-backups-bob-services.service
sudo systemctl start restic-backups-minecraft.service
journalctl -u restic-backups-bob-services.service \
  -u restic-backups-minecraft.service -u restic-copy-bob.service
```

The 1 GiB disk swap partition is retained and encrypted with a fresh random
key on every boot. Zram remains the higher-capacity primary swap. Hibernation
must not be enabled against randomly encrypted swap.

## Build, deploy, and verify

The local Makefile chooses the flake configuration from the hostname:

```sh
make build
make switch
make deploy-bob
```

After deploying Bob, verify the native services and their listeners:

```sh
systemctl --failed
systemctl status nginx postgresql paperless-web paperless-task-queue \
  tandoor-recipes postgresqlBackup-tandoor_recipes \
  protonmail-bridge unifi jackett jellyfin sonarr rtorrent minecraft-server-pwppp \
  mc-router svc-router playit atticd
findmnt /nfs/Restic /nfs/NixCache /nfs/Plex /nfs/Torrents
ss -ltnup
curl --fail https://jellyfin.4amlunch.net/health
sudo -u jellyfin test -r /dev/dri/renderD128
sudo -u jellyfin test -w /dev/dri/renderD128
# After forcing a lower-bitrate playback:
sudo grep -l -- '-hwaccel vaapi' /var/lib/jellyfin/log/FFmpeg.Transcode-*.txt
```

Before the first Minecraft deployment, replace the placeholder in
[`secrets/playit.toml.sops`](./secrets/playit.toml.sops) with the claimed
Playit agent secret. The service intentionally skips startup while the
placeholder remains. Also create `zpool/var/minecraft` and mount it at
`/var/lib/minecraft` on an already-installed Bob; the disko declaration creates
it automatically only during a fresh installation.
