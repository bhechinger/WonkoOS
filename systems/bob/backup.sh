#!/usr/bin/env bash

set -euo pipefail
umask 077

leave_stopped=0
if [[ ${1:-} == --leave-stopped ]]; then
  leave_stopped=1
  shift
fi

if [[ ${EUID} -ne 0 || $# -ne 1 ]]; then
  echo "usage: sudo bash backup.sh [--leave-stopped] /nfs/Brian" >&2
  exit 2
fi

destination=${1%/}
timestamp=$(date -u +%Y%m%dT%H%M%SZ)
backup=$destination/bob-backups/$timestamp
rootfs=$backup/rootfs
metadata=$backup/metadata
shutdown_started=0
backup_complete=0

[[ ! -e $backup ]] || { echo "backup path already exists: $backup" >&2; exit 1; }

check_mount() {
  local path=$1 source=$2
  [[ $(findmnt -n -o SOURCE -T "$path") == "$source" ]] || {
    echo "$path is not on $source" >&2
    exit 1
  }
}

check_mount "$destination" "10.42.0.30:/Brian"
probe=$(mktemp "$destination/.bob-backup-write-test.XXXXXX")
rm -f "$probe"
(( $(df --output=avail -B1 "$destination" | tail -n 1) >= 20 * 1024 * 1024 * 1024 )) || {
  echo "$destination has less than 20 GiB free" >&2
  exit 1
}

compose_files=(
  /home/wonko/docker/docker-compose.yaml
  /home/wonko/unifi/docker-compose.yaml
)
compose_names=(main unifi)
for file in "${compose_files[@]}"; do
  [[ -f $file ]] || { echo "missing Compose file: $file" >&2; exit 1; }
done

paths=(
  /home/docker/reverse
  /home/docker/paperless
  /home/docker/pgsql/paperless
  /home/docker/redis
  /home/docker/jackett
  /home/unifi/config
  /home/wonko/docker/docker-compose.yaml
  /home/wonko/docker/.env
  /home/wonko/docker/paperless.env
  /home/wonko/docker/data/geoip
  /home/wonko/unifi/docker-compose.yaml
  /var/lib/docker/volumes/protonmail/_data
  /var/lib/plexmediaserver
  /etc/mumble-server.ini
  /var/lib/mumble-server
  /etc/exports
  /var/lib/nfs
  /var/lib/tailscale
  /var/lib/zerotier-one
)
for path in "${paths[@]}"; do
  [[ -e $path ]] || { echo "missing backup path: $path" >&2; exit 1; }
done

native_units=(
  plexmediaserver.service
  mumble-server.service
  postfix.service
  nfs-server.service
  nfs-kernel-server.service
  tailscaled.service
  zerotier-one.service
  ntp.service
)

install -d -m 0700 "$backup" "$rootfs" "$metadata" "$metadata/images"
systemctl --no-pager --all > "$metadata/systemctl-before.txt"
systemctl --failed --plain --no-legend | awk '{print $1}' | sort -u > "$metadata/failed-before.txt" || true
docker ps --no-trunc > "$metadata/docker-before.txt"
docker ps --format '{{.Names}}' | sort -u > "$metadata/containers-running-before.txt"
findmnt > "$metadata/findmnt.txt"
df -h > "$metadata/df.txt"

: > "$metadata/native-units-active.txt"
for unit in "${native_units[@]}"; do
  if systemctl is-active --quiet "$unit"; then
    printf '%s\n' "$unit" >> "$metadata/native-units-active.txt"
  fi
done

for index in "${!compose_files[@]}"; do
  docker compose -f "${compose_files[$index]}" ps --services --status running \
    | sort -u > "$metadata/compose-${compose_names[$index]}-running.txt"
done

mapfile -t images < <(docker ps --format '{{.Image}}' | sort -u)
(( ${#images[@]} > 0 )) || { echo "no running container images found" >&2; exit 1; }
printf '%s\n' "${images[@]}" > "$metadata/images/active-images.txt"
docker image inspect --format '{{.Id}} {{json .RepoTags}} {{json .RepoDigests}}' \
  "${images[@]}" > "$metadata/images/active-image-digests.txt"
docker image save --output "$metadata/images/active-images.tar" "${images[@]}"
(
  cd "$metadata/images"
  sha256sum active-images.tar > active-images.tar.sha256
)

restart_source() {
  local failed=0 index unit
  local -a services active_units

  systemctl start docker.service || failed=1
  for index in "${!compose_files[@]}"; do
    mapfile -t services < "$metadata/compose-${compose_names[$index]}-running.txt"
    if (( ${#services[@]} > 0 )); then
      docker compose -f "${compose_files[$index]}" start "${services[@]}" || failed=1
    fi
  done

  mapfile -t active_units < "$metadata/native-units-active.txt"
  for unit in "${active_units[@]}"; do
    systemctl start "$unit" || failed=1
  done

  sleep 5
  if ! docker ps --format '{{.Names}}' | sort -u > "$metadata/containers-running-after.txt"; then
    failed=1
  fi
  if ! diff -u "$metadata/containers-running-before.txt" "$metadata/containers-running-after.txt" \
    > "$metadata/container-state.diff"; then
    failed=1
  else
    rm -f "$metadata/container-state.diff"
  fi

  for unit in "${active_units[@]}"; do
    if ! systemctl is-active --quiet "$unit"; then
      printf '%s\n' "$unit" >> "$metadata/native-units-not-restarted.txt"
      failed=1
    fi
  done

  if ! systemctl --failed --plain --no-legend | awk '{print $1}' | sort -u \
    > "$metadata/failed-after.txt"; then
    failed=1
  fi
  if ! comm -13 "$metadata/failed-before.txt" "$metadata/failed-after.txt" \
    > "$metadata/new-failed-units.txt"; then
    failed=1
  elif [[ -s $metadata/new-failed-units.txt ]]; then
    failed=1
  elif [[ ! -s $metadata/new-failed-units.txt ]]; then
    rm -f "$metadata/new-failed-units.txt"
  fi
  systemctl --no-pager --all > "$metadata/systemctl-after.txt" || failed=1
  docker ps --no-trunc > "$metadata/docker-after.txt" || failed=1

  if (( failed == 0 && backup_complete == 1 )); then
    if ! touch "$metadata/SOURCE-RESTARTED" || ! sync; then
      failed=1
    fi
  fi
  return "$failed"
}

on_exit() {
  local status=$?
  trap - EXIT
  trap '' INT TERM
  if (( shutdown_started == 1 )); then
    if (( leave_stopped == 1 && backup_complete == 1 && status == 0 )); then
      if touch "$metadata/SOURCE-STOPPED" && sync; then
        echo "leaving Bob's recorded service state stopped"
        exit 0
      fi
      echo "could not record Bob's stopped state; restoring services" >&2
      status=1
    fi
    rm -f "$metadata/SOURCE-STOPPED" || true
    echo "restoring Bob's original service state"
    if ! restart_source; then
      echo "Bob's original service state was not fully restored; inspect $metadata" >&2
      status=1
    fi
  fi
  exit "$status"
}
trap on_exit EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

shutdown_started=1
mapfile -t active_units < "$metadata/native-units-active.txt"
for unit in "${active_units[@]}"; do
  systemctl stop "$unit"
done
for index in "${!compose_files[@]}"; do
  mapfile -t services < "$metadata/compose-${compose_names[$index]}-running.txt"
  if (( ${#services[@]} > 0 )); then
    docker compose -f "${compose_files[$index]}" stop "${services[@]}"
  fi
done
systemctl stop docker.service docker.socket containerd.service

plex_sqlite='/usr/lib/plexmediaserver/Plex SQLite'
plex_databases=(
  '/var/lib/plexmediaserver/Library/Application Support/Plex Media Server/Plug-in Support/Databases/com.plexapp.plugins.library.db'
  '/var/lib/plexmediaserver/Library/Application Support/Plex Media Server/Plug-in Support/Databases/com.plexapp.plugins.library.blobs.db'
)
[[ -x $plex_sqlite ]] || { echo "missing Plex SQLite: $plex_sqlite" >&2; exit 1; }
for index in "${!plex_databases[@]}"; do
  database=${plex_databases[$index]}
  [[ -s $database ]] || { echo "missing or empty Plex database: $database" >&2; exit 1; }
  "$plex_sqlite" "$database" 'PRAGMA quick_check;' > "$metadata/plex-database-$index-check.txt"
  [[ $(< "$metadata/plex-database-$index-check.txt") == "ok" ]] || {
    echo "Plex database check failed: $database" >&2
    exit 1
  }
done

rsync -aHAX --numeric-ids --relative "${paths[@]/#//.}" "$rootfs/"

verification=$(rsync -aHAXn --numeric-ids --itemize-changes --relative "${paths[@]/#//.}" "$rootfs/")
[[ -z $verification ]] || {
  printf '%s\n' "$verification" > "$metadata/rsync-verification-failed.txt"
  echo "backup verification found differences" >&2
  exit 1
}

sync
touch "$metadata/COMPLETE"
backup_complete=1
sync
echo "backup data complete: $backup"
