# Repository instructions

Do all work concerning `bob` on `deepthought`, including editing, testing,
committing, and pushing. Never push `bob` work from another host.

## Service inventory

Only `bob` and `deepthought` are NixOS flake configurations in this repository.
Treat the host named below as the operational owner of its services.

| Host                  | Services and role                                                                                                                                                                                                                                                                                                                                   | Where to look                                                                                                                                                           |
| --------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `sierra`              | OPNsense router/firewall and VLAN gateway; Kea DHCP; BIND primary for the internal forward and reverse zones; node exporter                                                                                                                                                                                                                         | `systems/sierra/README.md` and `systems/sierra/*.sh`; administer the appliance over SSH. DNS changes must only be made on the BIND primary, never on `bob`'s secondary. |
| `bob`                 | BIND secondary and recursive fallback; Nginx and ACME; Cloudflare Tunnel; Attic; Paperless, PostgreSQL, Redis, and Proton Mail Bridge; Plex, Sonarr, Jackett, rTorrent, and ruTorrent; Minecraft servers, routers, backups, and Playit; Murmur, Postfix, UniFi, NFS, Tailscale, and ZeroTier; Grafana, Mimir, Loki, Tempo, Alloy, and node exporter | `systems/bob/services/` and `systems/bob/README.md`. Work on and deploy these services only from `deepthought`.                                                         |
| `deepthought`         | Workstation and build/deploy host; Atuin and PostgreSQL; Docker, Podman, and libvirt; CUPS and Avahi; on-demand VyprVPN; Alloy plus node and NVIDIA exporters; NFS and iSCSI/ZFS clients for `basket`                                                                                                                                               | `systems/deepthought/`, `home/`, and the root `Makefile`.                                                                                                               |
| `basket`              | QNAP/QTS NAS; NFS exports and iSCSI backing storage; QTS HTTPS with local acme.sh renewal                                                                                                                                                                                                                                                           | `systems/basket/README.md` and `systems/basket/*.sh`; the appliance itself is administered over SSH.                                                                    |
| Cloudflare and Playit | Public HTTP/Minecraft ingress, public DNS, and the Minecraft voice relay                                                                                                                                                                                                                                                                            | Reconciled from `systems/bob/services/cloudflared.nix` and `systems/bob/services/minecraft.nix`; the control planes are external.                                       |

# Agent workflow

For every code change:

1. Switch to `main`, fetch `origin`, update `main` from `origin/main`, and
   create a new branch. Prefix bug-fix branches with `fix/` and feature
   branches with `feat/`.
2. Implement the change and run the required formatting based on the languages found
   in this repo.
3. Commit the change locally before reviewing the diff.
4. Start parallel fresh agent sessions with no inherited implementation
   context (`fork_turns: "none"` or equivalent). Give each reviewer only these
   repository instructions, the original task requirements or acceptance
   criteria, and the current branch or pull-request diff against its base. Do
   not include the implementation conversation, plans, rationale, prior
   findings, or another reviewer's conclusions.

   Have each reviewer independently perform an adversarial review that actively
   tries to falsify the change's correctness. Assess:

   - bugs;
   - security;
   - code quality;
   - DRY violations; and
   - removable complexity.

   Synthesize and deduplicate their findings. Report only actionable issues
   with severity, file/line, and rationale. Address all issues raised by this
   review, commit the fixes, and repeat the clean-context adversarial review
   until clean before continuing.

5. Push the clean branch.
6. Open a pull request.
7. Wait for CI to pass and address any failures.
8. Notify the user only when the pull request is ready for review and merge.
