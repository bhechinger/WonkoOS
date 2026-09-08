# WonkoOS

This is the NixOS configuration of all (eventually) my machines.

## Storage installation

The `deepthought` disko layout manages only the two local NVMe drives. It never
manages the remote iSCSI `basket` pool. Normal NixOS rebuilds do not run disko.

From an installer, mount and reinstall an existing layout without formatting:

```sh
sudo nix run .#disko-install -- \
  --mode mount \
  --flake .#deepthought \
  --disk os /dev/disk/by-id/nvme-WDC_WDS100T2B0C-00PXH0_21281Y459408 \
  --disk tank /dev/disk/by-id/nvme-WDS200T1XHE-00AFY0_21143L800578
```

For blank replacement drives, inspect the command first:

```sh
sudo nix run .#disko-install -- \
  --dry-run \
  --mode format \
  --flake .#deepthought \
  --disk os /dev/disk/by-id/OS_DISK \
  --disk tank /dev/disk/by-id/TANK_DISK
```

Remove `--dry-run` only when both target drives are blank or disposable. Do not
use disko's `destroy` mode for repair or reinstallation.

## Storage layout

The native-mount migration is complete. NixOS mounts `/` and `/nix` from ZFS
datasets whose `mountpoint` property is `legacy`. OpenZFS mounts `/var`,
`/var/lib/docker`, and `/home` natively. Do not repeat the migration commands
retained in Git history.

Verify the active layout with:

```sh
for mountpoint in / /nix /var /var/lib/docker /home; do findmnt "$mountpoint"; done
zfs mount
systemctl --failed
```

`zfs-import-basket.service` imports the remote pool after local ZFS mounts are
ready and ZFS mounts its datasets under `/basket` and `/home/wonko`.

## Codex GitHub authentication

Home Manager installs a local `codex-github-mcp` server that obtains the
current GitHub CLI token only inside the MCP child process. The migration from
URL and `bearer_token_env_var` configuration is complete. Keep this command
configuration in `~/.codex/config.toml`:

```toml
[mcp_servers.github]
command = "codex-github-mcp"
```

Keep the existing per-tool approval table below it. Use `gh auth login` to
repair authentication if needed. The Codex launcher excludes GitHub token
variables from tool subprocesses.
