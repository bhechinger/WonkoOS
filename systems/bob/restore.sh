set -euo pipefail

if [[ ${EUID} -ne 0 || $# -ne 1 ]]; then
  echo "usage: sudo bob-restore /nfs/Brian/bob-backups/TIMESTAMP" >&2
  exit 2
fi

backup=${1%/}
source_root=$backup/rootfs
marker=/var/lib/bob-restored
ad_image=$backup/metadata/images/wonko-samba-dc-test3.tar

[[ -d $source_root ]] || { echo "missing backup root: $source_root" >&2; exit 1; }
[[ -s $ad_image ]] || { echo "missing custom Samba image: $ad_image" >&2; exit 1; }
[[ ! -e $marker ]] || { echo "restore already completed: $marker exists" >&2; exit 1; }

for path in \
  home/docker/paperless \
  home/docker/pgsql/paperless \
  home/samba/lib \
  home/unifi/config \
  var/lib/docker/volumes/protonmail/_data \
  var/lib/plexmediaserver; do
  [[ -e $source_root/$path ]] || { echo "required backup path is missing: $path" >&2; exit 1; }
done

systemctl stop compose-main.service compose-unifi.service compose-ad.service \
  plex.service murmur.service postfix.service nfs-server.service \
  tailscaled.service zerotierone.service libvirtd.service 2>/dev/null || true

docker image load --input "$ad_image" >/dev/null

rsync -aHAX --numeric-ids --relative \
  "$source_root"/./home/docker/reverse \
  "$source_root"/./home/docker/paperless \
  "$source_root"/./home/docker/pgsql/paperless \
  "$source_root"/./home/docker/redis \
  "$source_root"/./home/docker/jackett \
  "$source_root"/./home/unifi/config \
  "$source_root"/./home/samba/etc \
  "$source_root"/./home/samba/lib \
  "$source_root"/./home/wonko/docker/docker-compose.yaml \
  "$source_root"/./home/wonko/docker/.env \
  "$source_root"/./home/wonko/docker/paperless.env \
  "$source_root"/./home/wonko/docker/data/geoip \
  "$source_root"/./home/wonko/unifi/docker-compose.yaml \
  "$source_root"/./home/wonko/AD/docker-compose.yaml \
  "$source_root"/./home/wonko/AD/samba-admin-password \
  "$source_root"/./home/wonko/AD/ad_console \
  "$source_root"/./var/lib/plexmediaserver \
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
password=$(sed -n 's/^[[:space:]]*serverpassword[[:space:]]*=[[:space:]]*//p' "$source_root/etc/mumble-server.ini" | tail -n 1)
password=${password//\\/\\\\}
password=${password//\"/\\\"}
printf 'MURMURD_PASSWORD="%s"\n' "$password" > /var/lib/mumble-server/murmurd.env
chmod 0600 /var/lib/mumble-server/murmurd.env
chown -R murmur:murmur /var/lib/mumble-server
chown -R plex:plex /var/lib/plexmediaserver

install -d -m 0700 /var/lib/bob-legacy/etc /var/lib/bob-legacy/var/spool
rsync -aHAX --numeric-ids "$source_root/etc/postfix/" /var/lib/bob-legacy/etc/postfix/
rsync -aHAX --numeric-ids "$source_root/etc/libvirt/" /var/lib/bob-legacy/etc/libvirt/
rsync -aHAX --numeric-ids "$source_root/var/spool/postfix/" /var/lib/bob-legacy/var/spool/postfix/

touch "$marker"
start_failed=0
systemctl start tailscaled.service zerotierone.service nfs-server.service postfix.service murmur.service plex.service || start_failed=1
systemctl start compose-ad.service compose-main.service compose-unifi.service || start_failed=1

echo "restore complete; legacy Postfix/libvirt files are retained under /var/lib/bob-legacy"
systemctl --no-pager --failed || true
docker ps --format 'table {{.Names}}\t{{.Status}}'
exit "$start_failed"
