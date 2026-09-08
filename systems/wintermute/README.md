# Wintermute

Wintermute is the Apple Silicon macOS laptop. Nix is installed independently;
the `homeConfigurations.wintermute` Home Manager profile manages Codex, its
GitHub MCP helper, Node.js, OmniGraph, Kitty and its terminfo, development
tools, desktop applications, shell integrations, user launch agents, and
Codex's OmniGraph allow rule.

Codex owns `~/.codex/config.toml` and `~/.codex/auth.json`. Home Manager must
not replace them because they contain machine-specific project paths, plugin
state, and authentication.

From this repository on Deepthought, build or deploy the profile directly in
Wintermute's Nix store with:

```sh
make build-wintermute
make deploy-wintermute
```

The deploy target activates the exact generation returned by the build target;
Wintermute does not need a repository checkout.

Point the `command` in Codex's existing `[mcp_servers.github]` configuration at
the managed helper once per config reset, preserving every other setting:

```toml
[mcp_servers.github]
command = "codex-github-mcp"
```

Verify the setup with:

```sh
codex --version
codex login status
gh auth status
infocmp -x xterm-kitty
omnigraph query recent_context --graph nix --params '{"project":"nix:wonkoos:"}' --json
```

## Homebrew retirement

Home Manager replaces every requested Homebrew formula and the Google Cloud
CLI, Podman Desktop, and Signal casks. Stremio remains manually managed in
`/Applications/Stremio.app`. Homebrew dependencies are not listed separately;
they are supplied by the Nix closures that need them.

The first deployment needs a guarded cutover because the existing shell files
conflict with Home Manager links and PostgreSQL, skhd, and Yabai are still
running from `/opt/homebrew`. Create a dated backup outside that prefix, save a
logical PostgreSQL dump, and capture the current Podman inventory:

```sh
migration_dir="$HOME/Backups/WonkoOS/wintermute-homebrew-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$migration_dir/config" "$migration_dir/launch-agents"
cp "$HOME/.gitconfig" "$migration_dir/config/"
cp "$HOME/.gnupg/gpg-agent.conf" "$migration_dir/config/"
cp "$HOME/Library/LaunchAgents/homebrew.mxcl.atuin.plist" \
  "$HOME/Library/LaunchAgents/homebrew.mxcl.postgresql@14.plist" \
  "$HOME/Library/LaunchAgents/com.koekeishiya.skhd.plist" \
  "$HOME/Library/LaunchAgents/com.koekeishiya.yabai.plist" \
  "$migration_dir/launch-agents/"
/opt/homebrew/opt/postgresql@14/bin/pg_dumpall >"$migration_dir/postgresql-14.sql"
/opt/podman/bin/podman machine list >"$migration_dir/podman-machines.txt"
/opt/podman/bin/podman system connection list >"$migration_dir/podman-connections.txt"
/opt/podman/bin/podman ps -a >"$migration_dir/podman-containers.txt"
```

Confirm PostgreSQL has no other client sessions, unload the old agents, verify
that PostgreSQL stopped cleanly, and copy its same-major cluster to the path
used by the Nix launch agent:

```sh
test "$(/opt/homebrew/opt/postgresql@14/bin/psql -d postgres -Atqc \
  "select count(*) from pg_stat_activity where pid <> pg_backend_pid() and backend_type = 'client backend';")" = 0
launchctl bootout "gui/$(id -u)" "$HOME/Library/LaunchAgents/homebrew.mxcl.postgresql@14.plist"
/opt/homebrew/opt/postgresql@14/bin/pg_controldata /opt/homebrew/var/postgresql@14 | \
  grep 'Database cluster state:.*shut down'
test ! -e "$HOME/.local/share/postgresql/14"
mkdir -p "$HOME/.local/share/postgresql"
ditto /opt/homebrew/var/postgresql@14 "$HOME/.local/share/postgresql/14"

for agent in homebrew.mxcl.atuin com.koekeishiya.skhd com.koekeishiya.yabai; do
  launchctl bootout "gui/$(id -u)" "$HOME/Library/LaunchAgents/$agent.plist" 2>/dev/null || true
done
mv "$HOME/.zprofile" "$HOME/.zshrc" "$HOME/.zshenv" "$migration_dir/config/"
```

Deploy from Deepthought with `make deploy-wintermute`. Then replace the two
remaining Homebrew paths in user-owned configuration without replacing the
rest of either file:

```sh
git config --global --unset-all credential.https://github.com.helper || true
git config --global --add credential.https://github.com.helper ''
git config --global --add credential.https://github.com.helper '!gh auth git-credential'
git config --global --unset-all credential.https://gist.github.com.helper || true
git config --global --add credential.https://gist.github.com.helper ''
git config --global --add credential.https://gist.github.com.helper '!gh auth git-credential'
sed -i '' 's|^pinentry-program .*|pinentry-program /Users/wonko/.nix-profile/bin/pinentry-mac|' \
  "$HOME/.gnupg/gpg-agent.conf"
gpgconf --kill gpg-agent
```

Yabai's scripting addition needs a digest-restricted sudoers entry for the
immutable Nix binary. Recreate this entry after every Yabai package update:

```sh
yabai_path="$(readlink "$HOME/.nix-profile/bin/yabai")"
yabai_hash="$(shasum -a 256 "$yabai_path" | awk '{print $1}')"
sudoers_file="$(mktemp)"
printf 'wonko ALL = (root) NOPASSWD: sha256:%s %s --load-sa\n' \
  "$yabai_hash" "$yabai_path" >"$sudoers_file"
sudo visudo -cf "$sudoers_file"
sudo install -o root -g wheel -m 0440 "$sudoers_file" /private/etc/sudoers.d/yabai
rm "$sudoers_file"
sudo "$yabai_path" --uninstall-sa 2>/dev/null || true
sudo "$yabai_path" --install-sa
sudo "$yabai_path" --load-sa
launchctl kickstart -k "gui/$(id -u)/org.nix-community.home.yabai"
launchctl kickstart -k "gui/$(id -u)/org.nix-community.home.skhd"
```

If macOS requests it, authorize the Nix-profile Yabai and skhd executables in
Privacy & Security > Accessibility before continuing.

Before deleting anything, verify the Nix PostgreSQL cluster, Podman machine,
Yabai/skhd, GPG pinentry, Google Cloud CLI, Signal, Podman Desktop, Kitty, and
Stremio after a fresh login. If any check fails, restore the saved shell files,
unload the Nix agents, and reload the saved launch agents; do not uninstall
Homebrew.

Once the cutover passes, download and inspect Homebrew's official uninstaller,
run its dry-run against the explicit Apple Silicon prefix, and then run it:

```sh
curl -fsSLo /tmp/homebrew-uninstall.sh \
  https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh
less /tmp/homebrew-uninstall.sh
NONINTERACTIVE=1 /bin/bash /tmp/homebrew-uninstall.sh --dry-run --path=/opt/homebrew
NONINTERACTIVE=1 /bin/bash /tmp/homebrew-uninstall.sh --path=/opt/homebrew
```

Remove only the verified obsolete files. Preserve `~/.config/gcloud`,
`~/.rustup`, `~/.cargo`, `~/.ipfs`, `~/.local/share/containers`,
`~/.config/containers`, all application-support data, the PostgreSQL backup,
and `/Applications/Stremio.app`.

```sh
rm -f "$HOME/Library/LaunchAgents/homebrew.mxcl.atuin.plist" \
  "$HOME/Library/LaunchAgents/homebrew.mxcl.postgresql@14.plist" \
  "$HOME/Library/LaunchAgents/com.koekeishiya.skhd.plist" \
  "$HOME/Library/LaunchAgents/com.koekeishiya.yabai.plist"
sudo rm -rf "/Applications/Podman Desktop.app" "/Applications/Signal.app"
rm -rf "$HOME/Library/Caches/Homebrew" "$HOME/Library/Logs/Homebrew"
sudo rm -f /etc/paths.d/homebrew

sudo launchctl bootout system /Library/LaunchDaemons/com.github.containers.podman.helper-wonko.plist 2>/dev/null || true
sudo rm -f /Library/LaunchDaemons/com.github.containers.podman.helper-wonko.plist \
  /private/var/run/podman-helper-wonko.socket
sudo rm -rf /opt/podman /usr/local/podman/helper/wonko
sudo rmdir /usr/local/podman/helper /usr/local/podman 2>/dev/null || true
sudo pkgutil --forget com.redhat.podman

rm -rf "$HOME/.Trash/nix-managed-tool-cleanup-20260908/homebrew-kitty-cask" \
  "$HOME/.Trash/nix-managed-tool-cleanup-20260908/homebrew-kitty-bin-link" \
  "$HOME/.Trash/nix-managed-tool-cleanup-20260908/homebrew-kitten-bin-link" \
  "$HOME/.Trash/nix-managed-tool-cleanup-20260908/homebrew-kitty-0.44.0.app"
```

The migration is complete only when `brew` no longer resolves, `/opt/homebrew`
and `/etc/paths.d/homebrew` are absent, no active shell/Git/GPG/launchd file
references `/opt/homebrew`, the Nix agents survive a logout, and Stremio still
launches from `/Applications/Stremio.app`.
