#!/usr/bin/env bash

set -euo pipefail
umask 077

if [[ ${EUID} -ne 0 || $# -ne 1 ]]; then
  echo "usage: sudo bash backup.sh /nfs/Brian" >&2
  exit 2
fi

destination=${1%/}
timestamp=$(date -u +%Y%m%dT%H%M%SZ)
backup=$destination/bob-backups/$timestamp
rootfs=$backup/rootfs
metadata=$backup/metadata

[[ ! -e $backup ]] || { echo "backup path already exists: $backup" >&2; exit 1; }

[[ $(findmnt -n -o SOURCE -T "$destination") == "10.42.0.30:/Brian" ]] || {
  echo "$destination is not on 10.42.0.30:/Brian" >&2
  exit 1
}
(( $(df --output=avail -B1 "$destination" | tail -n 1) >= 20 * 1024 * 1024 * 1024 )) || {
  echo "$destination has less than 20 GiB free" >&2
  exit 1
}

compose_files=(
  /home/wonko/docker/docker-compose.yaml
  /home/wonko/unifi/docker-compose.yaml
)
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
  /etc/postfix
  /var/spool/postfix
  /etc/exports
  /var/lib/nfs
  /etc/libvirt
  /var/lib/libvirt
  /var/lib/machines
  /var/lib/tailscale
  /var/lib/zerotier-one
  /var/snap/canonical-livepatch
)
for path in "${paths[@]}"; do
  [[ -e $path ]] || { echo "missing backup path: $path" >&2; exit 1; }
done

install -d "$rootfs" "$metadata/images"
systemctl --no-pager --all > "$metadata/systemctl-before.txt"
docker ps --no-trunc > "$metadata/docker-before.txt"
findmnt > "$metadata/findmnt.txt"
df -h > "$metadata/df.txt"

mapfile -t images < <(docker ps --format '{{.Image}}' | sort -u)
(( ${#images[@]} > 0 )) || { echo "no running container images found" >&2; exit 1; }
printf '%s\n' "${images[@]}" > "$metadata/images/active-images.txt"
docker image inspect --format '{{.Id}} {{join .RepoTags ","}} {{join .RepoDigests ","}}' \
  "${images[@]}" > "$metadata/images/active-image-digests.txt"
docker image save --output "$metadata/images/active-images.tar" "${images[@]}"
(
  cd "$metadata/images"
  sha256sum active-images.tar > active-images.tar.sha256
)

stop_if_active() {
  local unit
  for unit in "$@"; do
    if systemctl is-active --quiet "$unit"; then
      systemctl stop "$unit"
    fi
  done
}

stop_if_active nfs-server.service nfs-kernel-server.service
for file in "${compose_files[@]}"; do
  docker compose -f "$file" stop
done
stop_if_active docker.service docker.socket containerd.service
stop_if_active \
  plexmediaserver.service mumble-server.service postfix.service \
  libvirtd.service libvirt-guests.service tailscaled.service \
  zerotier-one.service ntp.service snap.canonical-livepatch.canonical-livepatchd.service

rsync -aHAX --numeric-ids --relative "${paths[@]/#//.}" "$rootfs/"

verification=$(rsync -aHAXn --numeric-ids --itemize-changes --relative "${paths[@]/#//.}" "$rootfs/")
[[ -z $verification ]] || {
  printf '%s\n' "$verification" > "$metadata/rsync-verification-failed.txt"
  echo "backup verification found differences" >&2
  exit 1
}

systemctl --no-pager --failed > "$metadata/systemctl-after.txt" || true
sync
touch "$metadata/COMPLETE"
sync
echo "backup complete: $backup"
echo "application services remain stopped"
