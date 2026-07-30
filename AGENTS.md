# Repository instructions

Do all work concerning `bob` on `deepthought`, including editing, testing,
committing, and pushing. Never push `bob` work from another host.

## Service inventory

Only `bob` and `deepthought` are NixOS flake configurations in this repository.
Treat the host named below as the operational owner of its services.

| Host | Services and role | Where to look |
|---|---|---|
| `sierra` | OPNsense router/firewall and VLAN gateway; Kea DHCP; BIND primary for the internal forward and reverse zones; node exporter | `systems/sierra/README.md` and `systems/sierra/*.sh`; administer the appliance over SSH. DNS changes must only be made on the BIND primary, never on `bob`'s secondary. |
| `bob` | BIND secondary and recursive fallback; Nginx and ACME; Cloudflare Tunnel; Attic; Paperless, PostgreSQL, Redis, and Proton Mail Bridge; Plex, Sonarr, Jackett, rTorrent, and ruTorrent; Minecraft servers, routers, backups, and Playit; Murmur, Postfix, UniFi, NFS, Tailscale, and ZeroTier; Grafana, Mimir, Loki, Tempo, Alloy, and node exporter | `systems/bob/services/` and `systems/bob/README.md`. Work on and deploy these services only from `deepthought`. |
| `deepthought` | Workstation and build/deploy host; Atuin and PostgreSQL; Docker, Podman, and libvirt; CUPS and Avahi; on-demand VyprVPN; Alloy plus node and NVIDIA exporters; NFS and iSCSI/ZFS clients for `basket` | `systems/deepthought/`, `home/`, and the root `Makefile`. |
| `basket` | QNAP/QTS NAS; NFS exports and iSCSI backing storage; QTS HTTPS with local acme.sh renewal | `systems/basket/README.md` and `systems/basket/*.sh`; the appliance itself is administered over SSH. |
| Cloudflare and Playit | Public HTTP/Minecraft ingress, public DNS, and the Minecraft voice relay | Reconciled from `systems/bob/services/cloudflared.nix` and `systems/bob/services/minecraft.nix`; the control planes are external. |
