# Bob

Bob is a NixOS server on ZFS. Each workload has a module in
[`services/`](./services/); Docker and Docker Compose are not part of the
runtime model.

## Services

| Workload | Persistent state |
|---|---|
| Paperless-ngx | `/var/lib/paperless` and `/var/lib/postgresql/paperless` |
| Proton Mail Bridge | `/var/lib/protonmail-bridge` |
| UniFi Network Application | `/var/lib/unifi` |
| Nginx | `/var/www` and ACME state under `/var/lib/acme` |
| Jackett | `/var/lib/jackett` |
| Sonarr | `/var/lib/sonarr` |
| rTorrent and ruTorrent | `/var/lib/{rtorrent,rutorrent}` and `/nfs/Torrents` |
| Plex | `/var/lib/plexmediaserver` and `/nfs/Plex` |
| Attic Nix cache | `/var/lib/atticd` and Basket at `/nfs/NixCache` |
| pwppp Minecraft server | `/var/lib/minecraft/pwppp` |
| Minecraft routers and Playit | Stateless; configuration is in this repository |
| Murmur, Postfix, NFS, Tailscale, ZeroTier | Their standard NixOS state paths |

Runtime credentials for Attic, Paperless, Cloudflare Tunnel, Minecraft RCON
and backups, Playit, Murmur, and ruTorrent are encrypted with SOPS in
[`secrets/`](./secrets/) and materialized under `/run/secrets`. Do not recreate
plaintext copies under `/home` or `/var/lib`.

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

Nginx serves Bob, Paperless, Jackett, Sonarr, and ruTorrent with the wildcard
ACME certificate. It also serves the Minecraft server list and current pwppp
client pack at `https://minecraft.4amlunch.net`. Unknown HTTP hosts receive
`444` and unknown TLS handshakes are rejected. The rTorrent XML-RPC listener is
only reachable through its Unix socket and the loopback nginx endpoint.

Attic listens only on loopback and Nginx exposes it internally at
`https://cache.4amlunch.net`. Pulls are public on the trusted networks; pushes
use a shared cache-scoped Attic token. The hostname is managed only in
OPNsense and is deliberately absent from public DNS and Cloudflare Tunnel.

The Packwiz source uses Modrinth for Create: Oxidized and Create: Design n'
Decor so Bob can fetch them reproducibly. The generated CurseForge client ZIP
substitutes the matching CurseForge file IDs because CurseForge exports omit
Modrinth entries. Update both sets of pinned metadata when changing either mod.

`cloudflare-tunnel-sync.service` declaratively manages the remotely managed
Cloudflare Tunnel and its public DNS records. It publishes Paperless and the
Minecraft download page through `https://localhost:443`, using each public
hostname for the TLS and HTTP host names. TLS verification remains enabled.

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
resolve internally unless they are also added to that Nix record list. The
internal `pwppp` TXT value is `local-direct`, masking the public
`cloudflared-use-tunnel` value so Modflared clients connect directly instead
of hairpinning through Cloudflare.

Internet game traffic uses the same tunnel at `pwppp.4amlunch.net`, with a
`tcp://localhost:25565` origin and the public TXT value
`cloudflared-use-tunnel`. Internet voice traffic cannot use that TCP tunnel and
instead uses Playit UDP at `147.185.221.19:34934`, forwarded to
`127.0.0.1:34934`. Public `voice.4amlunch.net` DNS points to that Playit IP and
is DNS-only. Apply or inspect the declarative Cloudflare state with:

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
`4amlunch-restic` Backblaze B2 bucket after the daily backups. The separate
append-only endpoint at `https://restic-b2.4amlunch.net` exposes that mirror
for disaster recovery. Both endpoints are available only through the private
networks. Bob and Deepthought have isolated repositories; only Bob's weekly
maintenance job has delete-capable B2 credentials. If NFS is unavailable, use
`sudo restic-bob-b2` on Bob or `sudo restic-deepthought-b2` on Deepthought.

Bob service state is backed up from temporary ZFS snapshots at 03:30 daily.
Minecraft keeps its two backup layers: Sanoid retains 24 hourly, 14 daily,
and 3 monthly snapshots on Bob, while Restic takes a consistent ZFS snapshot
after an RCON `save-all flush` and backs it up at 04:30 daily. Deepthought
backs up its home dataset and a PostgreSQL logical dump at 02:30 daily. Weekly
maintenance retains every snapshot from the last six months, prunes older
data, and checks the NFS and B2 repositories.

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
  protonmail-bridge unifi jackett sonarr rtorrent minecraft-server-pwppp \
  mc-router svc-router playit atticd
findmnt /nfs/Restic /nfs/NixCache /nfs/Plex /nfs/Torrents
ss -ltnup
```

Before the first Minecraft deployment, replace the placeholder in
[`secrets/playit.toml.sops`](./secrets/playit.toml.sops) with the claimed
Playit agent secret. The service intentionally skips startup while the
placeholder remains. Also create `zpool/var/minecraft` and mount it at
`/var/lib/minecraft` on an already-installed Bob; the disko declaration creates
it automatically only during a fresh installation.
