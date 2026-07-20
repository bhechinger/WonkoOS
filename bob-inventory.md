# bob inventory

Collected from `bob` over SSH as `wonko` with `sudo` for systemd/root checks.

## Host

- Hostname: `bob`
- OS: Ubuntu 22.04.5 LTS
- Kernel: `Linux 5.15.0-185-generic`
- Hardware: Intel NUC10i5FNK
- Uptime at collection: 1 week, 3 days, 11 hours

## Docker containers

Docker was queried as `wonko`. All containers below are compose-managed except where noted.

| Container | State | Image | Ports / exposure | Config / data |
|---|---:|---|---|---|
| `reverse` | running | `nginx` | `80/tcp`, `443/tcp` on all interfaces | compose project `docker`, `/home/wonko/docker/docker-compose.yaml`; mounts `/home/docker/reverse/{config,certs,html}` |
| `paperless` | running, healthy | `ghcr.io/paperless-ngx/paperless-ngx:2.20` | `8001 -> 8000/tcp` | compose project `docker`; mounts `/home/docker/paperless/{consume,data,export,media}` |
| `protonmail-bridge` | running | `shenxn/protonmail-bridge` | `1025 -> 25/tcp`, `1143 -> 143/tcp` | compose project `docker`; volume `protonmail:/root` |
| `jackett` | running | `lscr.io/linuxserver/jackett:latest` | `9117/tcp` | compose project `docker`; mounts `/home/docker/jackett/{config,downloads}` |
| `paperless-db` | running | `postgres:16` | internal `5432/tcp` only | compose project `docker`; mount `/home/docker/pgsql/paperless:/var/lib/postgresql/data` |
| `paperless-broker` | running | `redis:7` | internal `6379/tcp` only | compose project `docker`; mount `/home/docker/redis:/data` |
| `geoip-updater` | running | `crazymax/geoip-updater:latest` | none published | compose project `docker`; mount `/home/wonko/docker/data/geoip:/data` |
| `cloudflared-tunnel` | running | `cloudflare/cloudflared` | outbound tunnel, no published ports | compose project `docker`, service `tunnel`; runs in container as `65532:65532` |
| `unifi-controller` | running | `lscr.io/linuxserver/unifi-controller:latest` | `1900/udp`, `3478/udp`, `5514/udp`, `10001/udp`, `6789/tcp`, `8080/tcp`, `8443/tcp`, `8843/tcp`, `8880/tcp` | compose project `unifi`, `/home/wonko/unifi/docker-compose.yaml`; mount `/home/unifi/config:/config` |
| `sonarr` | exited | `lscr.io/linuxserver/sonarr:latest` | configured `8989/tcp`, not currently listening | compose project `docker`; mounts `/home/docker/sonarr/config`, torrent/show volumes |
| `rutorrent` | exited | `crazymax/rtorrent-rutorrent:latest` | configured `8000/tcp`, `9000/tcp`, `6881/udp`, `50000/tcp`, `8081 -> 8080/tcp`, not currently listening | compose project `docker`; mounts `/home/docker/rutorrent/{data,passwd}`, torrent volume |

## Systemd services: custom / operator-managed

| Unit | State | Runs as | Why included | Exposure / notes |
|---|---:|---|---|---|
| `docker.service` | active/running, enabled | root | Docker host for the containers above | `dockerd -H fd:// --containerd=/run/containerd/containerd.sock` |
| `containerd.service` | active/running, enabled | root | Docker runtime | supporting service for Docker |
| `plexmediaserver.service` | active/running, enabled | `plex` | media server, non-root service user | `32400/tcp`; local `32401`, `32600`; UDP discovery ports including `1901`, `32410-32414` |
| `mumble-server.service` | active/running, generated | root | Mumble VoIP server | `64738/tcp` and `64738/udp` |
| `postfix.service` / `postfix@-.service` | active, enabled/runtime | root | mail transport agent | `25/tcp` |
| `nfs-server.service` plus `nfs-*`, `rpc-*` | active, enabled/static | root | NFS server stack | `2049/tcp`; rpcbind `111`; dynamic mount/statd ports |
| `libvirtd.service` | active/running, enabled | root | virtualization daemon | includes libvirt `dnsmasq` on `192.168.122.1:53` and DHCP on `virbr0:67` |
| `libvirt-guests.service` | active/exited, enabled | root | libvirt guest suspend/resume helper | no listener itself |
| `qemu-kvm.service` | active/exited, enabled | root | KVM preparation | no listener itself |
| `tailscaled.service` | active/running, enabled | root | Tailscale node agent | UDP `41641`, plus Tailscale interface listeners |
| `zerotier-one.service` | active/running, enabled | root | ZeroTier overlay network | `9993/tcp+udp`, plus per-interface UDP `21100` and `52693` |
| `ntp.service` | active/running, enabled | root | NTP server/client daemon | `123/udp` on multiple interfaces |
| `snap.canonical-livepatch.canonical-livepatchd.service` | active/running, enabled | root | Canonical Livepatch snap service | no server port found |

## User-owned systemd units

### `wonko`

- Real local user: `wonko:1000:/home/wonko:/usr/bin/zsh`
- Active user manager: yes (`/run/user/1000`)
- Linger enabled: yes
- Active app-like user services: none found.

Baseline/inactive user units seen for `wonko`: `dbus.service`, `dirmngr.service`, `gpg-agent.service`, `pk-debconf-helper.service`, `snapd.session-agent.service`, `gnome-keyring.service`, `session-migration.service`. `podman.service` appeared as `not-found`.

### Other users

- `chatgpt:30033:/home/chatgpt:/bin/sh`
  - No active `/run/user/30033` user manager found.
  - No linger entry found.
  - No `*.service` files found under `/home/chatgpt/.config/systemd/user`.
- `plex`
  - Used by system unit `plexmediaserver.service`; see systemd table above.
- Other non-root `User=` system units found were baseline OS services: `systemd-resolved`, `systemd-networkd`, `man-db`, `pollinate`, `uuidd`.

## Other notable listeners

- `ssh.service`: `22/tcp`.
- `avahi-daemon`: `5353/udp` and mDNS dynamic ports.
- `systemd-resolved`: `127.0.0.53:53`.
- `rpcbind` / NFS stack: `111`, `2049`, and dynamic RPC ports.
- Docker proxies expose the published container ports listed in the Docker table.

## Skipped baseline services

Omitted from the main table unless relevant above: normal Ubuntu/systemd plumbing such as `cron`, `dbus`, `getty`, `irqbalance`, `multipathd`, `networkd-dispatcher`, `polkit`, `rsyslog`, `snapd`, `ssh`, `systemd-*`, `thermald`, `unattended-upgrades`, and `wpa_supplicant`.

## Ambiguous / worth review

- `nix-daemon.service` is linked from `/etc/systemd/system/nix-daemon.service` but was inactive/dead during collection.
- `sonarr` and `rutorrent` have restart policies but are exited. If they should be part of the active server set, they need investigation separately.
