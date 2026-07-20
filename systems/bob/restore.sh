set -euo pipefail

if [[ ${EUID} -ne 0 || $# -ne 1 ]]; then
  echo "usage: sudo bob-restore /nfs/Brian/bob-backups/TIMESTAMP" >&2
  exit 2
fi

backup=${1%/}
source_root=$backup/rootfs
marker=/var/lib/bob-restored
image_archive=$backup/metadata/images/active-images.tar

[[ -d $source_root ]] || { echo "missing backup root: $source_root" >&2; exit 1; }
[[ -e $backup/metadata/COMPLETE ]] || { echo "backup is incomplete: missing metadata/COMPLETE" >&2; exit 1; }
[[ -s $image_archive ]] || { echo "missing container image archive: $image_archive" >&2; exit 1; }
[[ ! -e $marker ]] || { echo "restore already completed: $marker exists" >&2; exit 1; }
(
  cd "$backup/metadata/images"
  sha256sum --check active-images.tar.sha256
)

for path in \
  home/docker/jackett \
  home/docker/paperless \
  home/docker/pgsql/paperless \
  home/docker/reverse \
  home/unifi/config \
  home/wonko/docker/paperless.env \
  var/lib/cloudflared/tunnel.env \
  var/lib/docker/volumes/protonmail/_data \
  var/lib/plexmediaserver \
  var/lib/rtorrent \
  var/lib/rutorrent \
  var/lib/sonarr; do
  [[ -e $source_root/$path ]] || { echo "required backup path is missing: $path" >&2; exit 1; }
done

mumble_config=$source_root/etc/mumble-server.ini
grep -Eq '^[[:space:]]*serverpassword[[:space:]]*=' "$mumble_config" || {
  echo "Mumble server password setting is missing" >&2
  exit 1
}
password=$(sed -n 's/^[[:space:]]*serverpassword[[:space:]]*=[[:space:]]*//p' "$mumble_config" | tail -n 1)

systemctl stop \
  cloudflared-tunnel.service \
  docker-protonmail-bridge.service \
  docker-unifi-controller.service \
  jackett.service \
  nginx.service \
  paperless-consumer.service \
  paperless-scheduler.service \
  paperless-task-queue.service \
  paperless-web.service \
  phpfpm-rutorrent.service \
  plex.service \
  murmur.service \
  postgresql.service \
  postfix.service \
  redis-paperless.service \
  rtorrent.service \
  sonarr.service \
  nfs-server.service \
  tailscaled.service \
  zerotierone.service

docker image load --input "$image_archive" >/dev/null

rsync -aHAX --numeric-ids --relative \
  "$source_root"/./home/docker/reverse \
  "$source_root"/./home/docker/paperless \
  "$source_root"/./home/docker/pgsql/paperless \
  "$source_root"/./home/docker/jackett \
  "$source_root"/./home/unifi/config \
  "$source_root"/./home/wonko/docker/paperless.env \
  "$source_root"/./var/lib/cloudflared/tunnel.env \
  "$source_root"/./var/lib/plexmediaserver \
  "$source_root"/./var/lib/rtorrent \
  "$source_root"/./var/lib/rutorrent \
  "$source_root"/./var/lib/sonarr \
  "$source_root"/./var/lib/mumble-server \
  "$source_root"/./var/lib/nfs \
  "$source_root"/./var/lib/tailscale \
  "$source_root"/./var/lib/zerotier-one \
  /

docker volume create protonmail >/dev/null
protonmail=$(docker volume inspect --format '{{ .Mountpoint }}' protonmail)
rsync -aHAX --numeric-ids "$source_root/var/lib/docker/volumes/protonmail/_data/" "$protonmail/"

install -d -m 0750 -o murmur -g murmur /var/lib/mumble-server
if [[ -e /var/lib/mumble-server/mumble-server.sqlite && ! -e /var/lib/mumble-server/murmur.sqlite ]]; then
  cp -a /var/lib/mumble-server/mumble-server.sqlite /var/lib/mumble-server/murmur.sqlite
fi
password=${password//\\/\\\\}
password=${password//\"/\\\"}
printf 'MURMURD_PASSWORD="%s"\n' "$password" > /var/lib/mumble-server/murmurd.env
chmod 0600 /var/lib/mumble-server/murmurd.env
chown -R murmur:murmur /var/lib/mumble-server
chown -R plex:plex /var/lib/plexmediaserver
chown -R media:media /home/docker/jackett
chown -R paperless:paperless /home/docker/paperless
chown -R postgres:postgres /home/docker/pgsql/paperless
chown -R media:nginx /var/lib/rtorrent
chown root:nginx \
  /home/docker/reverse/certs \
  /home/docker/reverse/certs/4amlunch.net \
  /home/docker/reverse/certs/4amlunch.net/{fullchain,privkey}.pem
chmod 0750 /home/docker/reverse/certs /home/docker/reverse/certs/4amlunch.net
chmod 0640 /home/docker/reverse/certs/4amlunch.net/{fullchain,privkey}.pem
chown -R rutorrent:rutorrent /var/lib/rutorrent
chown root:rutorrent /var/lib/rutorrent
chmod 0751 /var/lib/rutorrent
chown -R media:media /var/lib/sonarr
chown root:root /var/lib/cloudflared/tunnel.env
chmod 0600 /var/lib/cloudflared/tunnel.env
chown root:nginx /var/lib/rutorrent/htpasswd
chmod 0640 /var/lib/rutorrent/htpasswd

printf '%s\n' \
  'DO $$ BEGIN IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '\''postgres'\'') THEN CREATE ROLE postgres WITH LOGIN SUPERUSER; END IF; END $$;' |
  runuser -u postgres -- postgres --single -D /home/docker/pgsql/paperless postgres >/dev/null

restore_failed() {
  rm -f "$marker"
  echo "service startup failed; restore marker removed so the restore can be retried" >&2
  exit 1
}

touch "$marker"
systemctl start postgresql.service || restore_failed
for database in paperless postgres template1; do
  if [[ $(runuser -u postgres -- psql -d postgres -Atc \
    "SELECT datcollversion IS DISTINCT FROM pg_database_collation_actual_version(oid) FROM pg_database WHERE datname = '$database'") == t ]]; then
    runuser -u postgres -- reindexdb --dbname="$database" || restore_failed
    runuser -u postgres -- psql -d postgres -v ON_ERROR_STOP=1 \
      -c "ALTER DATABASE \"$database\" REFRESH COLLATION VERSION;" || restore_failed
  fi
done

systemctl start \
  tailscaled.service \
  zerotierone.service \
  nfs-server.service \
  postfix.service \
  murmur.service \
  plex.service \
  redis-paperless.service \
  paperless-consumer.service \
  paperless-scheduler.service \
  paperless-task-queue.service \
  paperless-web.service \
  jackett.service \
  rtorrent.service \
  phpfpm-rutorrent.service \
  sonarr.service \
  nginx.service \
  cloudflared-tunnel.service \
  docker-protonmail-bridge.service \
  docker-unifi-controller.service || restore_failed

echo "restore complete"
systemctl --no-pager --failed || true
docker ps --format 'table {{.Names}}\t{{.Status}}'
