# Bob

Bob is a NixOS server on ZFS. Each workload has a module in
[`services/`](./services/); Docker and Docker Compose are not part of the
runtime model.

## Services

| Workload | Persistent state |
|---|---|
| Paperless-ngx | `/home/docker/paperless` and `/home/docker/pgsql/paperless` |
| Proton Mail Bridge | `/var/lib/protonmail-bridge` |
| UniFi Network Application | `/var/lib/unifi` |
| Nginx | `/home/docker/reverse/html` and ACME state under `/var/lib/acme` |
| Jackett | `/home/docker/jackett` |
| Sonarr | `/var/lib/sonarr` |
| rTorrent and ruTorrent | `/var/lib/{rtorrent,rutorrent}` and `/nfs/Torrents` |
| Plex | `/var/lib/plexmediaserver` and `/nfs/Plex` |
| Murmur, Postfix, NFS, Tailscale, ZeroTier | Their standard NixOS state paths |

Runtime credentials for Paperless, Cloudflare Tunnel, Murmur, and ruTorrent
are encrypted with SOPS in [`secrets/`](./secrets/) and materialized under
`/run/secrets`. Do not recreate plaintext copies under `/home` or `/var/lib`.

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
ACME certificate. Unknown HTTP hosts receive `444` and unknown TLS handshakes
are rejected. The rTorrent XML-RPC listener is only reachable through its Unix
socket and the loopback nginx endpoint.

Only `paperless.4amlunch.net` is published through the remotely managed
Cloudflare Tunnel. Its origin is `https://localhost:443`, with the origin and
HTTP host names both set to `paperless.4amlunch.net` and TLS verification
enabled.

## Storage

ZFS datasets back `/`, `/nix`, `/var`, `/var/lib/plexmediaserver`, `/home`, and
`/home/docker/pgsql`. Basket is automounted over NFSv4 at `/nfs/Plex` and
`/nfs/Torrents`; Bob does not mount the `Brian` share.

Jackett, Sonarr, rTorrent, and Plex keep separate service accounts. Basket's
NFS host entries for Bob on both `Plex` and `Torrents` use **Squash all users**
and map to the dedicated QNAP user `bob-nfs` and group `bob-media`. Those
identities have access only to the two media shares. This lets the services
share NFS data without sharing their local Unix identities or using QNAP's
generic anonymous account. NFS exports of the Paperless consume/export
directories separately map the single authorized client (`10.42.0.10`) to the
Paperless account with `all_squash`.

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
  protonmail-bridge unifi jackett sonarr rtorrent
findmnt /nfs/Plex /nfs/Torrents
ss -ltnup
```
