#!/usr/bin/env bash

set -uo pipefail
umask 077

result=/tmp/xchg
checks=$result/checks.tsv
summary=$result/summary.txt
restore_source=/var/tmp/bob-backup
failures=0
install -d "$result"
exec > >(tee "$result/test.log") 2>&1

finish() {
  local status=$?
  set +e
  systemctl --no-pager --all > "$result/systemd-units.txt"
  systemctl --no-pager --failed > "$result/systemd-failed.txt"
  docker ps --all --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' \
    > "$result/docker-ps.txt" 2>&1
  {
    echo "Bob disposable restore test"
    echo "UTC: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "Failed checks: $failures"
    echo
    echo "Expected isolation-related degradation (not test failures):"
    echo "- Cloudflare Tunnel cannot reach the Internet."
    echo "- Tailscale and ZeroTier cannot reach their control planes."
    echo "- Proton Mail Bridge cannot reach Proton."
    echo "- UniFi adoption, Plex media on NAS, and external SMTP are unavailable."
  } > "$summary"
  rm -rf "$restore_source"
  if (( status == 0 && failures == 0 )); then
    touch "$result/PASS"
    rm -f "$result/FAIL"
  else
    touch "$result/FAIL"
    rm -f "$result/PASS"
  fi
  sync
  systemctl poweroff --no-block
}
trap finish EXIT

record() {
  local outcome=$1 name=$2 detail=${3:-}
  printf '%s\t%s\t%s\n' "$outcome" "$name" "$detail" | tee -a "$checks"
}

check() {
  local name=$1
  shift
  if "$@"; then
    record PASS "$name"
  else
    record FAIL "$name"
    failures=$((failures + 1))
  fi
}

container_running() {
  [[ $(docker inspect --format '{{.State.Running}}' "$1" 2>/dev/null) == true ]]
}

container_absent() {
  ! docker container inspect "$1" >/dev/null 2>&1
}

port_listening() {
  ss -lnt | awk '{print $4}' | grep -Eq "(^|[:.])$1$"
}

http_ready() {
  local url=$1 attempts=${2:-120}
  local attempt
  for ((attempt = 0; attempt < attempts; attempt++)); do
    if curl --insecure --silent --max-time 5 --output /dev/null "$url"; then
      return 0
    fi
    sleep 5
  done
  return 1
}

rutorrent_auth_required() {
  [[ $(curl --insecure --silent --max-time 5 \
    --output /dev/null --write-out '%{http_code}' \
    --resolve rutorrent.4amlunch.net:443:127.0.0.1 \
    https://rutorrent.4amlunch.net/) == 401 ]]
}

rutorrent_auth_works() {
  local user password code
  user=$(sed -n 's/:.*//p' /var/lib/rutorrent/htpasswd | head -n 1)
  password=$(cat /var/lib/rutorrent/initial-password)
  code=$(curl --insecure --silent --max-time 5 \
    --user "$user:$password" --output /dev/null --write-out '%{http_code}' \
    --resolve rutorrent.4amlunch.net:443:127.0.0.1 \
    https://rutorrent.4amlunch.net/)
  unset password
  [[ $code == 200 ]]
}

postgres_role_ready() {
  [[ $(sudo -u postgres psql -d postgres -Atc \
    "SELECT rolsuper AND rolcanlogin FROM pg_roles WHERE rolname = 'postgres'") == t ]]
}

postgres_collations_current() {
  [[ $(sudo -u postgres psql -d postgres -Atc \
    'SELECT count(*) FROM pg_database WHERE datallowconn AND datcollversion IS DISTINCT FROM pg_database_collation_actual_version(oid)') == 0 ]]
}

: > "$checks"
if ! mountpoint --quiet /tmp/shared || ! mountpoint --quiet /tmp/xchg; then
  record FAIL shared-directories "required 9p mount is unavailable"
  failures=$((failures + 1))
  exit 1
fi
if findmnt -n -o OPTIONS /tmp/shared | tr ',' '\n' | grep -qx ro; then
  record PASS backup-share-read-only
else
  record FAIL backup-share-read-only
  failures=$((failures + 1))
fi

if ! (cd /tmp/shared && sha256sum --check backup.tar.zst.sha256); then
  record FAIL staged-backup-checksum
  failures=$((failures + 1))
  exit 1
fi
record PASS staged-backup-checksum

install -d "$restore_source"
install -d /nfs/Plex/Shows /nfs/Torrents
if ! zstd -dc /tmp/shared/backup.tar.zst \
  | tar --acls --xattrs --numeric-owner -xf - -C "$restore_source"; then
  record FAIL staged-backup-extraction
  failures=$((failures + 1))
  exit 1
fi
record PASS staged-backup-extraction

if /run/current-system/sw/bin/bob-restore "$restore_source"; then
  record PASS bob-restore
else
  record FAIL bob-restore
  failures=$((failures + 1))
  exit 1
fi
rm -rf "$restore_source"
check restore-marker test -e /var/lib/bob-restored

for unit in \
  docker.service plex.service murmur.service postfix.service nfs-server.service \
  avahi-daemon.service tailscaled.service zerotierone.service \
  docker-protonmail-bridge.service docker-unifi-controller.service \
  jackett.service nginx.service paperless-consumer.service \
  paperless-scheduler.service paperless-task-queue.service paperless-web.service \
  phpfpm-rutorrent.service postgresql.service redis-paperless.service \
  rtorrent.service sonarr.service; do
  check "unit:$unit" systemctl is-active --quiet "$unit"
done

for container in protonmail-bridge unifi-controller; do
  check "container:$container" container_running "$container"
done
check container-absent:sonarr container_absent sonarr
check container-absent:rutorrent container_absent rutorrent
check postgres-readiness pg_isready
check postgres-role postgres_role_ready
check postgres-collations postgres_collations_current
check redis-readiness redis-cli -s /run/redis-paperless/redis.sock ping
check service-uids test "$(id -u avahi)" -ne "$(id -u media)"
check rtorrent-socket-group test "$(stat -c %G /run/rtorrent/rpc.sock)" = nginx

check plex-http http_ready http://127.0.0.1:32400/identity 60
check plex-library-database test -s \
  '/var/lib/plexmediaserver/Library/Application Support/Plex Media Server/Plug-in Support/Databases/com.plexapp.plugins.library.db'
check plex-blobs-database test -s \
  '/var/lib/plexmediaserver/Library/Application Support/Plex Media Server/Plug-in Support/Databases/com.plexapp.plugins.library.blobs.db'
check murmur-port port_listening 64738
check postfix-port port_listening 25
check nfs-consume-export grep -Fq '/home/docker/paperless/consume' /var/lib/nfs/etab
check nfs-export-export grep -Fq '/home/docker/paperless/export' /var/lib/nfs/etab

check reverse-http http_ready http://127.0.0.1/ 24
check paperless-http http_ready http://127.0.0.1:8001/ 24
check jackett-http http_ready http://127.0.0.1:9117/ 24
check sonarr-http http_ready http://127.0.0.1:8989/ 24
check rutorrent-https-auth rutorrent_auth_required
check rutorrent-https-login rutorrent_auth_works
check unifi-https http_ready https://127.0.0.1:8443/ 60

if protonmail=$(docker volume inspect --format '{{.Mountpoint}}' protonmail 2>/dev/null) \
  && find "$protonmail" -mindepth 1 -print -quit | grep -q .; then
  record PASS protonmail-volume
else
  record FAIL protonmail-volume
  failures=$((failures + 1))
fi

check expected-degraded-unit:cloudflared-tunnel \
  systemctl is-enabled --quiet cloudflared-tunnel.service

if systemctl --failed --plain --no-legend | grep -q .; then
  record FAIL unexpected-failed-units
  failures=$((failures + 1))
else
  record PASS unexpected-failed-units
fi

(( failures == 0 ))
