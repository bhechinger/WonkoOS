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
  home/docker/paperless \
  home/docker/pgsql/paperless \
  home/unifi/config \
  var/lib/docker/volumes/protonmail/_data \
  var/lib/plexmediaserver; do
  [[ -e $source_root/$path ]] || { echo "required backup path is missing: $path" >&2; exit 1; }
done

mumble_config=$source_root/etc/mumble-server.ini
grep -Eq '^[[:space:]]*serverpassword[[:space:]]*=' "$mumble_config" || {
  echo "Mumble server password setting is missing" >&2
  exit 1
}
password=$(sed -n 's/^[[:space:]]*serverpassword[[:space:]]*=[[:space:]]*//p' "$mumble_config" | tail -n 1)

systemctl stop compose-main.service compose-unifi.service \
  plex.service murmur.service postfix.service nfs-server.service \
  tailscaled.service zerotierone.service

docker image load --input "$image_archive" >/dev/null

rsync -aHAX --numeric-ids --relative \
  "$source_root"/./home/docker/reverse \
  "$source_root"/./home/docker/paperless \
  "$source_root"/./home/docker/pgsql/paperless \
  "$source_root"/./home/docker/redis \
  "$source_root"/./home/docker/jackett \
  "$source_root"/./home/unifi/config \
  "$source_root"/./home/wonko/docker/docker-compose.yaml \
  "$source_root"/./home/wonko/docker/.env \
  "$source_root"/./home/wonko/docker/paperless.env \
  "$source_root"/./home/wonko/docker/data/geoip \
  "$source_root"/./home/wonko/unifi/docker-compose.yaml \
  "$source_root"/./var/lib/plexmediaserver \
  "$source_root"/./var/lib/mumble-server \
  "$source_root"/./var/lib/nfs \
  "$source_root"/./var/lib/tailscale \
  "$source_root"/./var/lib/zerotier-one \
  /

rm -f /home/docker/reverse/config/conf.d/{rancher,rutorrent,sonarr}.conf

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

touch "$marker"
if ! systemctl start tailscaled.service zerotierone.service nfs-server.service postfix.service murmur.service plex.service \
  || ! systemctl start compose-main.service compose-unifi.service; then
  rm -f "$marker"
  echo "service startup failed; restore marker removed so the restore can be retried" >&2
  exit 1
fi

echo "restore complete"
systemctl --no-pager --failed || true
docker ps --format 'table {{.Names}}\t{{.Status}}'
