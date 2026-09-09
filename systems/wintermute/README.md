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
logical PostgreSQL dump, preserve its four configuration files, and capture the
current Podman inventory. Run every block below in the same zsh session; the
first command makes later failures stop the cutover:

```sh
set -euo pipefail
umask 077
migration_dir="$HOME/Backups/WonkoOS/wintermute-homebrew-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$migration_dir/config" "$migration_dir/launch-agents" \
  "$migration_dir/postgresql-config"
cp "$HOME/.zprofile" "$HOME/.gitconfig" "$migration_dir/config/"
cp "$HOME/.gnupg/gpg-agent.conf" "$migration_dir/config/"
cp "$HOME/.config/atuin/config.toml" "$migration_dir/config/"
cp "$HOME/.config/skhd/skhdrc" "$HOME/.config/yabai/yabairc" \
  "$migration_dir/config/"
cp "$HOME/Library/LaunchAgents/homebrew.mxcl.atuin.plist" \
  "$HOME/Library/LaunchAgents/homebrew.mxcl.postgresql@14.plist" \
  "$HOME/Library/LaunchAgents/com.koekeishiya.skhd.plist" \
  "$HOME/Library/LaunchAgents/com.koekeishiya.yabai.plist" \
  "$migration_dir/launch-agents/"
for file in postgresql.conf postgresql.auto.conf pg_hba.conf pg_ident.conf; do
  /usr/bin/install -m 0600 "/opt/homebrew/var/postgresql@14/$file" \
    "$migration_dir/postgresql-config/$file"
done
capture_podman_inventory() {
  local podman_cli="$1" prefix="$2"
  "$podman_cli" machine list --format '{{.Name}}' | \
    /usr/bin/sort >"${prefix}-machines.txt"
  while IFS= read -r machine; do
    "$podman_cli" machine inspect "$machine" --format \
      '{{.Name}}|{{.Resources.CPUs}}|{{.Resources.DiskSize}}|{{.Resources.Memory}}|{{.SSHConfig.Port}}|{{.SSHConfig.RemoteUsername}}|{{.UserModeNetworking}}|{{.Rootful}}|{{.Rosetta}}'
  done <"${prefix}-machines.txt" | /usr/bin/sort >"${prefix}-machine-configs.txt"
  "$podman_cli" system connection list --format \
    '{{.Name}}|{{.URI}}|{{.Default}}|{{.ReadWrite}}' | \
    /usr/bin/sort >"${prefix}-connections.txt"
  "$podman_cli" ps -a --format '{{.ID}}|{{.Names}}|{{.Image}}' | \
    /usr/bin/sort >"${prefix}-containers.txt"
}
compare_podman_inventory() {
  local podman_cli="$1" prefix="$2" inventory
  capture_podman_inventory "$podman_cli" "$prefix"
  for inventory in machines machine-configs connections containers; do
    /usr/bin/cmp "$migration_dir/podman-original-${inventory}.txt" \
      "${prefix}-${inventory}.txt"
  done
}
old_podman=/opt/podman/bin/podman
podman_initial_state="$("$old_podman" machine inspect --format '{{.State}}')"
podman_started_for_inventory=0
restore_podman_state() {
  if [ "$podman_started_for_inventory" -eq 1 ]; then
    "$old_podman" machine stop
  fi
}
trap restore_podman_state EXIT
case "$podman_initial_state" in
  running) ;;
  stopped)
    podman_started_for_inventory=1
    "$old_podman" machine start
    ;;
  *) exit 1 ;;
esac
printf '%s\n' "$podman_initial_state" >"$migration_dir/podman-initial-state.txt"
capture_podman_inventory "$old_podman" "$migration_dir/podman-original"
restore_podman_state
podman_started_for_inventory=0
trap - EXIT
test "$("$old_podman" machine inspect --format '{{.State}}')" = \
  "$podman_initial_state"
```

The inventory step temporarily starts a stopped default Podman VM and restores
its original state before continuing.

Stop every application that can use PostgreSQL and keep it stopped until the
cutover is accepted. Confirm there are no client sessions, unload the old
agent, and restart the source only on a private socket. Capture the dump and
data inventory from that quiescent source before stopping it again:

```sh
postgres_bin=/opt/homebrew/opt/postgresql@14/bin
postgres_source=/opt/homebrew/var/postgresql@14
postgres_data="$HOME/.local/share/postgresql/14"
test "$("$postgres_bin/psql" -d postgres -Atqc \
  "select current_setting('data_directory');")" = "$postgres_source"
test "$("$postgres_bin/psql" -d postgres -Atqc \
  "select count(*) from pg_stat_activity where pid <> pg_backend_pid() and backend_type = 'client backend';")" = 0
postgres_socket=
postgres_source_running=0
nix_postgres=
nix_postgres_socket=
nix_postgres_running=0
postgres_new=
postgres_cutover_accepted=0
restore_postgres_cutover() {
  local original_exit=$?
  local attempt domain="gui/$(id -u)" quarantine rollback_exit=0
  local safe_to_restart=1 socket_dir
  local nix_label="$domain/org.nix-community.home.postgresql-14"
  local old_label="$domain/homebrew.mxcl.postgresql@14"
  if [ "$#" -gt 0 ]; then
    original_exit="$1"
  fi
  trap - EXIT
  if [ "$nix_postgres_running" -eq 1 ]; then
    if "$nix_postgres/pg_ctl" -D "$postgres_new" status >/dev/null 2>&1; then
      "$nix_postgres/pg_ctl" -D "$postgres_new" -m fast stop || \
        rollback_exit=1
    fi
  fi
  if [ "$postgres_source_running" -eq 1 ]; then
    if "$postgres_bin/pg_ctl" -D "$postgres_source" status \
      >/dev/null 2>&1; then
      if ! "$postgres_bin/pg_ctl" -D "$postgres_source" -m fast stop; then
        rollback_exit=1
        safe_to_restart=0
      fi
    fi
  fi
  for socket_dir in "$nix_postgres_socket" "$postgres_socket"; do
    if [ -n "$socket_dir" ] && [ -d "$socket_dir" ]; then
      rmdir "$socket_dir" || rollback_exit=1
    fi
  done
  if [ "$safe_to_restart" -eq 1 ]; then
    if launchctl print "$nix_label" >/dev/null 2>&1; then
      if ! launchctl bootout "$domain" \
        "$HOME/Library/LaunchAgents/org.nix-community.home.postgresql-14.plist"; then
        rollback_exit=1
        safe_to_restart=0
      fi
    fi
  fi
  if [ "$safe_to_restart" -eq 1 ] && [ -n "$postgres_new" ] &&
    [[ -e "$postgres_new" || -L "$postgres_new" ]]; then
    quarantine="$migration_dir/postgresql-14-new-unaccepted"
    if [[ -e "$quarantine" || -L "$quarantine" ]]; then
      rollback_exit=1
    else
      mv "$postgres_new" "$quarantine" || rollback_exit=1
    fi
  fi
  if [ "$safe_to_restart" -eq 1 ] &&
    [[ -e "$postgres_data" || -L "$postgres_data" ]]; then
    quarantine="$migration_dir/postgresql-14-unaccepted"
    if [[ -e "$quarantine" || -L "$quarantine" ]]; then
      rollback_exit=1
    else
      mv "$postgres_data" "$quarantine" || rollback_exit=1
    fi
  fi
  if [ "$safe_to_restart" -eq 1 ]; then
    if launchctl print "$old_label" >/dev/null 2>&1; then
      launchctl kickstart -k "$old_label" || rollback_exit=1
    else
      launchctl bootstrap "$domain" \
        "$HOME/Library/LaunchAgents/homebrew.mxcl.postgresql@14.plist" || \
        rollback_exit=1
    fi
  fi
  if [ "$safe_to_restart" -eq 1 ]; then
    for attempt in {1..30}; do
      "$postgres_bin/pg_isready" -d postgres >/dev/null && break
      sleep 1
    done
    "$postgres_bin/pg_isready" -d postgres >/dev/null || rollback_exit=1
    test "$("$postgres_bin/psql" -d postgres -Atqc \
      "select current_setting('data_directory');")" = "$postgres_source" || \
      rollback_exit=1
  fi
  if [ "$rollback_exit" -ne 0 ]; then
    echo 'Failed to restore the original PostgreSQL service' >&2
  fi
  if [ "$original_exit" -ne 0 ]; then
    return "$original_exit"
  fi
  return "$rollback_exit"
}
trap restore_postgres_cutover EXIT
launchctl bootout "gui/$(id -u)" "$HOME/Library/LaunchAgents/homebrew.mxcl.postgresql@14.plist"
"$postgres_bin/pg_controldata" "$postgres_source" | \
  grep 'Database cluster state:.*shut down'
postgres_socket="$(mktemp -d /tmp/wonko-pg-source.XXXXXX)"
postgres_source_running=1
"$postgres_bin/pg_ctl" -D "$postgres_source" \
  -l "$migration_dir/postgresql-source.log" \
  -o "-c data_directory=$postgres_source -k $postgres_socket -h '' -p 55431" start
"$postgres_bin/psql" -h "$postgres_socket" -p 55431 -d postgres -AtF '|' -c \
  "select datname, pg_get_userbyid(datdba), encoding, datcollate, datctype, datistemplate, datallowconn, datconnlimit from pg_database order by datname;" \
  >"$migration_dir/postgresql-databases.txt"
"$postgres_bin/psql" -h "$postgres_socket" -p 55431 -d postgres -AtF '|' -c \
  "select rolname, rolsuper, rolinherit, rolcreaterole, rolcreatedb, rolcanlogin, rolreplication, rolbypassrls, rolconnlimit, coalesce(rolvaliduntil::text, ''), md5(coalesce(rolpassword, '')) from pg_authid where rolname not like 'pg_%' order by rolname;" \
  >"$migration_dir/postgresql-roles.txt"
"$postgres_bin/psql" -h "$postgres_socket" -p 55431 -d postgres -AtF '|' -c \
  "select name, setting from pg_settings where source = 'configuration file' order by name;" \
  >"$migration_dir/postgresql-settings.txt"
"$postgres_bin/psql" -h "$postgres_socket" -p 55431 -d atuin -AtF '|' -c \
  "select (select count(*) from public.users), (select count(*) from public.history), (select count(*) from public.records), (select count(*) from public.sessions), (select count(*) from public.store);" \
  >"$migration_dir/atuin-counts.txt"
"$postgres_bin/pg_dumpall" -h "$postgres_socket" -p 55431 \
  >"$migration_dir/postgresql-14.sql"
"$postgres_bin/pg_ctl" -D "$postgres_source" -m fast stop
postgres_source_running=0
rmdir "$postgres_socket"
postgres_socket=
"$postgres_bin/pg_controldata" "$postgres_source" | \
  grep 'Database cluster state:.*shut down'
test ! -e "$postgres_data"

for agent in homebrew.mxcl.atuin com.koekeishiya.skhd com.koekeishiya.yabai; do
  if launchctl print "gui/$(id -u)/$agent" >/dev/null 2>&1; then
    launchctl bootout "gui/$(id -u)" "$HOME/Library/LaunchAgents/$agent.plist"
  fi
  ! launchctl print "gui/$(id -u)/$agent" >/dev/null 2>&1
done
atuin_socket="$HOME/.local/share/atuin/atuin.sock"
if [ -S "$atuin_socket" ]; then
  test -z "$(/usr/sbin/lsof -nP "$atuin_socket")"
  rm -f "$atuin_socket"
fi
mv "$HOME/.zshrc" "$HOME/.zshenv" "$migration_dir/config/"
```

Deploy from Deepthought with `make deploy-wintermute`. Then replace the
remaining obsolete paths in user-owned configuration without replacing the
rest of those files:

```sh
git config --global --unset-all credential.https://github.com.helper || true
git config --global --add credential.https://github.com.helper ''
git config --global --add credential.https://github.com.helper '!gh auth git-credential'
git config --global --unset-all credential.https://gist.github.com.helper || true
git config --global --add credential.https://gist.github.com.helper ''
git config --global --add credential.https://gist.github.com.helper '!gh auth git-credential'
sed -i '' 's|^pinentry-program .*|pinentry-program /Users/wonko/.nix-profile/bin/pinentry-mac|' \
  "$HOME/.gnupg/gpg-agent.conf"
sed -i '' 's|/Applications/kitty.app/Contents/MacOS/kitty|/Users/wonko/.nix-profile/bin/kitty|' \
  "$HOME/.config/skhd/skhdrc"
sed -i '' '/\/opt\/homebrew\/bin\/brew shellenv/d' "$HOME/.zprofile"
path_line='export PATH="$HOME/.nix-profile/bin:$PATH"'
grep -Fqx "$path_line" "$HOME/.zprofile" || \
  printf '\n%s\n' "$path_line" >>"$HOME/.zprofile"
path=("${(@)path:#/opt/homebrew/*}")
path=("$HOME/.nix-profile/bin" "${(@)path:#/opt/podman/*}")
typeset -U path
export PATH
rehash
gpgconf --kill gpg-agent
test "$(/bin/zsh -lic 'command -v git')" = "$HOME/.nix-profile/bin/git"
```

Initialize a fresh cluster with the Nix PostgreSQL binaries in a temporary
directory, restore the dump, and move it into the launch agent's watched path
only after the restore succeeds. `initdb` creates the existing `wonko`
superuser, so the restore removes only that role's duplicate `CREATE` statement
and retains its dumped attributes:

```sh
nix_postgres="$HOME/.nix-profile/bin"
postgres_new="${postgres_data}.new"
test ! -e "$postgres_data" && test ! -e "$postgres_new"
mkdir -p "$(dirname "$postgres_data")"
"$nix_postgres/initdb" -D "$postgres_new" --encoding=UTF8 \
  --locale=en_US.UTF-8 --username=wonko
for file in postgresql.conf postgresql.auto.conf pg_hba.conf pg_ident.conf; do
  /usr/bin/install -m 0600 "$migration_dir/postgresql-config/$file" \
    "$postgres_new/$file"
done
nix_postgres_socket="$(mktemp -d /tmp/wonko-pg-nix.XXXXXX)"
nix_postgres_running=1
"$nix_postgres/pg_ctl" -D "$postgres_new" \
  -l "$migration_dir/postgresql-restore.log" \
  -o "-c data_directory=$postgres_new -k $nix_postgres_socket -h '' -p 55432" start
test "$("$nix_postgres/psql" -h "$nix_postgres_socket" -p 55432 \
  -U wonko -d postgres -Atqc "select current_setting('data_directory');")" = \
  "$postgres_new"
/usr/bin/sed '/^CREATE ROLE wonko;$/d' \
  "$migration_dir/postgresql-14.sql" | \
  "$nix_postgres/psql" -h "$nix_postgres_socket" -p 55432 \
    -U wonko -d postgres -X -v ON_ERROR_STOP=1
"$nix_postgres/psql" -h "$nix_postgres_socket" -p 55432 \
  -U wonko -d postgres -AtF '|' -c \
  "select datname, pg_get_userbyid(datdba), encoding, datcollate, datctype, datistemplate, datallowconn, datconnlimit from pg_database order by datname;" \
  >"$migration_dir/postgresql-databases-restored.txt"
"$nix_postgres/psql" -h "$nix_postgres_socket" -p 55432 \
  -U wonko -d postgres -AtF '|' -c \
  "select rolname, rolsuper, rolinherit, rolcreaterole, rolcreatedb, rolcanlogin, rolreplication, rolbypassrls, rolconnlimit, coalesce(rolvaliduntil::text, ''), md5(coalesce(rolpassword, '')) from pg_authid where rolname not like 'pg_%' order by rolname;" \
  >"$migration_dir/postgresql-roles-restored.txt"
"$nix_postgres/psql" -h "$nix_postgres_socket" -p 55432 \
  -U wonko -d postgres -AtF '|' -c \
  "select name, setting from pg_settings where source = 'configuration file' order by name;" \
  >"$migration_dir/postgresql-settings-restored.txt"
"$nix_postgres/psql" -h "$nix_postgres_socket" -p 55432 \
  -U wonko -d atuin -AtF '|' -c \
  "select (select count(*) from public.users), (select count(*) from public.history), (select count(*) from public.records), (select count(*) from public.sessions), (select count(*) from public.store);" \
  >"$migration_dir/atuin-counts-restored.txt"
/usr/bin/cmp "$migration_dir/postgresql-databases.txt" \
  "$migration_dir/postgresql-databases-restored.txt"
/usr/bin/cmp "$migration_dir/postgresql-roles.txt" \
  "$migration_dir/postgresql-roles-restored.txt"
/usr/bin/cmp "$migration_dir/postgresql-settings.txt" \
  "$migration_dir/postgresql-settings-restored.txt"
/usr/bin/cmp "$migration_dir/atuin-counts.txt" \
  "$migration_dir/atuin-counts-restored.txt"
"$nix_postgres/pg_ctl" -D "$postgres_new" -m fast stop
nix_postgres_running=0
rmdir "$nix_postgres_socket"
nix_postgres_socket=
mv "$postgres_new" "$postgres_data"
launchctl kickstart -k "gui/$(id -u)/org.nix-community.home.postgresql-14"
for attempt in {1..30}; do
  "$nix_postgres/pg_isready" -d postgres && break
  sleep 1
done
"$nix_postgres/pg_isready" -d postgres
test "$("$nix_postgres/psql" -d postgres -Atqc \
  "select current_setting('data_directory');")" = "$postgres_data"
ps -p "$(head -n 1 "$postgres_data/postmaster.pid")" -o command= | \
  grep '^/nix/store/.*-postgresql-14\..*/bin/postgres'
```

Yabai's optional scripting addition needs Filesystem Protections, Debugging
Restrictions, and NVRAM Protection disabled as described in the
[upstream Apple Silicon instructions](https://github.com/asmvik/yabai/wiki/Disabling-System-Integrity-Protection),
plus the arm64e preview ABI boot argument. Check both before configuring it:

```sh
sip_status="$(csrutil status)"
boot_args="$(nvram boot-args 2>/dev/null || true)"
printf '%s\n%s\n' "$sip_status" "$boot_args"
yabai_sip_ready=0
if [[ "$sip_status" == *'System Integrity Protection status: disabled.'* ]] ||
  [[ "$sip_status" == *'Filesystem Protections: disabled'* &&
    "$sip_status" == *'Debugging Restrictions: disabled'* &&
    "$sip_status" == *'NVRAM Protections: disabled'* ]]; then
  yabai_sip_ready=1
fi
if (( yabai_sip_ready )) &&
  printf '%s\n' "$boot_args" | \
    grep -E '(^|[[:space:]])-arm64e_preview_abi([[:space:]]|$)' >/dev/null; then
  yabai_sa_ready=1
else
  yabai_sa_ready=0
  echo 'Skipping the Yabai scripting addition; core Yabai remains available.'
fi
```

Authenticated Root can remain enabled. If `csrutil status` does not show the
three required protections disabled, or the boot-argument check fails, the
commands set `yabai_sa_ready=0`; core Yabai continues to work, and changing
those recovery-mode security settings is a separate decision. In either case,
first archive and remove any existing Yabai sudoers rule. The eligible path
below recreates it for the current immutable Nix binary:

```sh
yabai_sudoers=/private/etc/sudoers.d/yabai
if [[ -e "$yabai_sudoers" || -L "$yabai_sudoers" ]]; then
  sudo cp "$yabai_sudoers" "$migration_dir/config/yabai-sudoers"
  sudo rm -f "$yabai_sudoers"
fi
```

When `yabai_sa_ready=1`, give the immutable Nix binary a digest-restricted
sudoers entry. Recreate this entry after every Yabai package update. In Yabai
7.1.25, `--load-sa` installs and loads the addition; there is no separate
`--install-sa` option:

```sh
if (( yabai_sa_ready )); then
  yabai_path="$(readlink "$HOME/.nix-profile/bin/yabai")"
  yabai_hash="$(shasum -a 256 "$yabai_path" | awk '{print $1}')"
  sudoers_file="$(mktemp)"
  printf 'wonko ALL = (root) NOPASSWD: sha256:%s %s --load-sa\n' \
    "$yabai_hash" "$yabai_path" >"$sudoers_file"
  sudo visudo -cf "$sudoers_file"
  sudo install -o root -g wheel -m 0440 "$sudoers_file" \
    /private/etc/sudoers.d/yabai
  rm "$sudoers_file"
  sudo "$yabai_path" --uninstall-sa 2>/dev/null || true
  sudo "$yabai_path" --load-sa
fi
```

Restart and verify the managed agents whether or not the scripting addition is
enabled:

```sh
launchctl kickstart -k "gui/$(id -u)/org.nix-community.home.yabai"
launchctl kickstart -k "gui/$(id -u)/org.nix-community.home.skhd"
yabai -m query --spaces >/dev/null
```

If macOS requests it, authorize the Nix-profile Yabai and skhd executables in
Privacy & Security > Accessibility before continuing.

Before deleting anything, use only read-only PostgreSQL checks and keep its
clients stopped. Restart the existing Podman VM with the Nix CLI so the test
cannot pass only because an old process is still alive:

```sh
podman="$HOME/.nix-profile/bin/podman"
restore_nix_podman_state() {
  local original_exit=$?
  local current_state exit_to_preserve restored_state restore_exit=0
  trap - EXIT
  if current_state="$("$podman" machine inspect --format '{{.State}}' \
    2>/dev/null)"; then
    if [ "$podman_initial_state" = stopped ] && \
      [ "$current_state" != stopped ]; then
      "$podman" machine stop || restore_exit=1
    elif [ "$podman_initial_state" = running ] && \
      [ "$current_state" != running ]; then
      "$podman" machine start || restore_exit=1
    fi
  else
    restore_exit=1
  fi
  if [ "$restore_exit" -eq 0 ] &&
    restored_state="$("$podman" machine inspect --format '{{.State}}' \
      2>/dev/null)"; then
    [ "$restored_state" = "$podman_initial_state" ] || restore_exit=1
  else
    restore_exit=1
  fi
  if [ "$restore_exit" -ne 0 ]; then
    printf 'Failed to restore Podman machine state to %s\n' \
      "$podman_initial_state" >&2
  fi
  exit_to_preserve="$original_exit"
  if [ "$exit_to_preserve" -eq 0 ]; then
    exit_to_preserve="$restore_exit"
  fi
  if [ "$postgres_cutover_accepted" -eq 0 ]; then
    restore_postgres_cutover "$exit_to_preserve"
    return $?
  fi
  return "$exit_to_preserve"
}
trap restore_nix_podman_state EXIT
if [ "$("$podman" machine inspect --format '{{.State}}')" = running ]; then
  "$podman" machine stop
fi
test "$("$podman" machine inspect --format '{{.State}}')" = stopped
"$podman" machine start
"$podman" info
"$podman" ps -a
compare_podman_inventory "$podman" "$migration_dir/podman-nix-before-purge"
```

Also verify the Nix PostgreSQL cluster, Yabai/skhd, Atuin daemon, GPG pinentry,
Google Cloud CLI, Signal, Podman Desktop, Kitty, and Stremio. The Nix Podman
package does not provide the privileged Docker-compatible
`/var/run/docker.sock`; stop here if anything requires that socket.

```sh
verify_nix_cutover() {
  local expected_podman_state="$1"
  local agent command executable nix_profile="$HOME/.nix-profile/bin"
  for command in atuin gcloud git gpg-connect-agent pg_isready pinentry-mac \
    podman psql skhd yabai; do
    test "$(command -v "$command")" = "$nix_profile/$command"
  done
  for agent in atuin-daemon skhd yabai postgresql-14; do
    launchctl print "gui/$(id -u)/org.nix-community.home.$agent" | \
      grep 'state = running' >/dev/null
  done
  "$nix_profile/atuin" daemon status >/dev/null
  "$nix_profile/gpg-connect-agent" updatestartuptty /bye | grep -qx OK
  grep -Fqx \
    'pinentry-program /Users/wonko/.nix-profile/bin/pinentry-mac' \
    "$HOME/.gnupg/gpg-agent.conf"
  "$nix_profile/gcloud" --version >/dev/null
  infocmp -x xterm-kitty >/dev/null
  "$nix_profile/yabai" -m query --spaces >/dev/null
  "$nix_profile/pg_isready" -d postgres >/dev/null
  test "$("$nix_profile/psql" -d postgres -Atqc \
    "select current_setting('data_directory');")" = \
    "$HOME/.local/share/postgresql/14"
  test "$("$nix_profile/podman" machine inspect --format '{{.State}}')" = \
    "$expected_podman_state"
  for executable in \
    "$HOME/Applications/Home Manager Apps/Podman Desktop.app/Contents/MacOS/Podman Desktop" \
    "$HOME/Applications/Home Manager Apps/Signal.app/Contents/MacOS/Signal" \
    "$HOME/Applications/Home Manager Apps/kitty.app/Contents/MacOS/kitty" \
    /Applications/Stremio.app/Contents/MacOS/Stremio; do
    test -x "$executable"
    file "$executable" | grep 'Mach-O 64-bit executable arm64' >/dev/null
  done
}
verify_nix_cutover running
postgres_cutover_accepted=1

verify_legacy_retired() {
  local exit_code file grep_exit legacy_service_output
  local git_config launchd_config receipts
  local nix_profile="$HOME/.nix-profile/bin"
  if command -v brew >/dev/null; then
    return 1
  fi
  for file in /opt/homebrew /etc/paths.d/homebrew /opt/podman \
    /usr/local/podman /usr/local/podman/helper/wonko \
    /Library/LaunchDaemons/com.github.containers.podman.helper-wonko.plist \
    /private/var/run/podman-helper-wonko.socket /etc/paths.d/podman-pkg \
    /usr/local/etc/man.d/podman.man.conf /var/run/docker.sock; do
    [[ ! -e "$file" && ! -L "$file" ]] || return 1
  done
  [[ "$PATH" != *'/opt/homebrew'* && "$PATH" != *'/opt/podman'* ]] || \
    return 1
  git_config="$("$nix_profile/git" config --global --list --show-origin)" || \
    return 1
  launchd_config="$(launchctl print "gui/$(id -u)")" || return 1
  if [[ "$git_config" == *'/opt/homebrew'* ||
    "$launchd_config" == *'/opt/homebrew'* ||
    "$launchd_config" == *'/opt/podman'* ]]; then
    return 1
  fi
  for file in "$HOME/.zprofile" "$HOME/.zshrc" "$HOME/.zshenv" \
    "$HOME/.gnupg/gpg-agent.conf" "$HOME/.config/skhd/skhdrc" \
    "$HOME/.config/yabai/yabairc"; do
    if [ -e "$file" ]; then
      grep_exit=0
      grep -E '/opt/(homebrew|podman)' "$file" >/dev/null || grep_exit=$?
      case "$grep_exit" in
        0) return 1 ;;
        1) ;;
        *) return "$grep_exit" ;;
      esac
    fi
  done
  exit_code=0
  legacy_service_output="$(launchctl print \
    system/com.github.containers.podman.helper-wonko 2>&1)" || exit_code=$?
  case "$exit_code" in
    0) return 1 ;;
    113)
      [[ "$legacy_service_output" == \
        *'Could not find service "com.github.containers.podman.helper-wonko"'* \
      ]] || return 1
      ;;
    *) return 1 ;;
  esac
  receipts="$(pkgutil --pkgs)" || return 1
  receipts=$'\n'"$receipts"$'\n'
  [[ "$receipts" != *$'\ncom.redhat.podman\n'* ]] || return 1
}
```

If a check fails before PostgreSQL accepts writes, restore the saved shell
files, unload the Nix agents, and reload the saved launch agents; do not
uninstall Homebrew. If the Nix cluster has accepted a write, do not reload the
old PostgreSQL agent: stop clients and reconcile or dump the Nix cluster first.

Confirm the login shell and the manually managed Stremio bundle do not depend
on Homebrew. The conditional handles Wintermute if its account is ever switched
to Homebrew zsh before this migration runs:

```sh
user_shell="$(dscl . -read /Users/wonko UserShell | awk '{print $2}')"
if [ "$user_shell" = /opt/homebrew/bin/zsh ]; then
  sudo dscl . -change /Users/wonko UserShell "$user_shell" /bin/zsh
fi
test "$(dscl . -read /Users/wonko UserShell | awk '{print $2}')" = /bin/zsh
test -d /Applications/Stremio.app && test ! -L /Applications/Stremio.app
```

Once the cutover passes, download and inspect Homebrew's official uninstaller,
run its dry-run against the explicit Apple Silicon prefix, and then run it:

```sh
curl -fsSLo /tmp/homebrew-uninstall.sh \
  https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh
less /tmp/homebrew-uninstall.sh
NONINTERACTIVE=1 /bin/bash /tmp/homebrew-uninstall.sh --dry-run --path=/opt/homebrew
NONINTERACTIVE=1 /bin/bash /tmp/homebrew-uninstall.sh --path=/opt/homebrew
```

The uninstaller preserves files that were not installed by Homebrew. Inspect
any remaining prefix contents and confirm that every entry is obsolete before
continuing with the removal block:

```sh
if [ -d /opt/homebrew ]; then
  find /opt/homebrew -mindepth 1 -print
fi
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

sudo /usr/local/podman/helper/wonko/podman-mac-helper uninstall
test ! -e /var/run/docker.sock && test ! -L /var/run/docker.sock
sudo launchctl bootout system /Library/LaunchDaemons/com.github.containers.podman.helper-wonko.plist 2>/dev/null || true
sudo rm -f /Library/LaunchDaemons/com.github.containers.podman.helper-wonko.plist \
  /private/var/run/podman-helper-wonko.socket
sudo rm -rf /opt/podman /usr/local/podman/helper/wonko
sudo rmdir /usr/local/podman/helper /usr/local/podman 2>/dev/null || true
sudo rm -f /etc/paths.d/podman-pkg /usr/local/etc/man.d/podman.man.conf
sudo pkgutil --forget com.redhat.podman

if [ -d /opt/homebrew ]; then
  rm -rf /opt/homebrew/*(DN)
  test -z "$(ls -A /opt/homebrew)"
  sudo rmdir /opt/homebrew
fi

"$podman" machine stop
"$podman" machine start
"$podman" info
"$podman" ps -a
compare_podman_inventory "$podman" "$migration_dir/podman-nix-after-purge"
if [ "$podman_initial_state" = stopped ]; then
  "$podman" machine stop
fi
test "$("$podman" machine inspect --format '{{.State}}')" = \
  "$podman_initial_state"
verify_nix_cutover "$podman_initial_state"
verify_legacy_retired
trap - EXIT

rm -rf "$HOME/.Trash/nix-managed-tool-cleanup-20260908/homebrew-kitty-cask" \
  "$HOME/.Trash/nix-managed-tool-cleanup-20260908/homebrew-kitty-bin-link" \
  "$HOME/.Trash/nix-managed-tool-cleanup-20260908/homebrew-kitten-bin-link" \
  "$HOME/.Trash/nix-managed-tool-cleanup-20260908/homebrew-kitty-0.44.0.app"
```

Log out and back in, re-enable `set -euo pipefail`, set `migration_dir` to the
dated backup created at the start, and reload the original Podman state:

```sh
set -euo pipefail
migration_dir="$HOME/Backups/WonkoOS/wintermute-homebrew-YYYYMMDD-HHMMSS"
podman_initial_state="$(<"$migration_dir/podman-initial-state.txt")"
```

Then rerun the `verify_nix_cutover` and `verify_legacy_retired` definitions
above followed by `verify_nix_cutover "$podman_initial_state"` and
`verify_legacy_retired`. This confirms that launchd did not merely preserve
the processes from the migration session.

The migration is complete only when `brew` no longer resolves, `/opt/homebrew`
and `/etc/paths.d/homebrew` are absent, no active shell/Git/GPG/launchd file
references `/opt/homebrew`, the Nix agents survive a logout, and Stremio still
exists intact at `/Applications/Stremio.app`.
