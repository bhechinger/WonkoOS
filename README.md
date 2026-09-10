# WonkoOS

This is the NixOS configuration of all (eventually) my machines.

## Build and deploy

Clone the repository to `~/nix/WonkoOS` on Deepthought, Bob, and Wintermute.
From the repository root, the common commands select the local host using its
short hostname:

```sh
make build
make switch
make boot
```

`make build` and `make switch` manage NixOS plus Home Manager on Deepthought,
NixOS on Bob, and Home Manager on Wintermute. `make boot` applies only to the
two NixOS hosts and fails explicitly on Wintermute.

Deepthought may build and deploy the other hosts with `make build-bob`,
`make deploy-bob`, `make build-wintermute`, and `make deploy-wintermute`. Bob
and Wintermute may use only their own explicit host targets; cross-host targets
fail before invoking Nix or SSH.

## Generations and input updates

`make generations` lists the local host's retained NixOS and Home Manager
generations with the WonkoOS revision and any associated GitHub pull request.
Older generations without revision metadata are shown as legacy generations.

Run `make update` from a clean `main` branch to update every flake input. It
creates and validates a lockfile-only branch, opens and merges its pull request,
deletes the branch, then returns to an updated `main`. The merge is an atomic
compare-and-swap of the validated commit and base. If it fails or `main`
advances, the update branch and its pushed commit remain available for
inspection.

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
