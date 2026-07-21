#!/bin/sh

set -eu
umask 077

# QTS sudo -i preserves these markers; acme.sh otherwise rejects the already-root shell.
unset SUDO_COMMAND SUDO_USER SUDO_UID SUDO_GID

ACME_VERSION=3.1.2
ACME_SHA256=a51511ad0e2912be45125cf189401e4ae776ca1a29d5768f020a1e35a9560186
ACME_URL=https://github.com/acmesh-official/acme.sh/archive/refs/tags/$ACME_VERSION.tar.gz
DOMAIN=basket.4amlunch.net
ACCOUNT_EMAIL=wonko@4amlunch.net
ACME_HOME=/share/homes/admin/.acme.sh
ACME=$ACME_HOME/acme.sh
DEPLOY_DIR=$ACME_HOME/deploy
DEPLOY_HOOK=$ACME_HOME/deploy-certificate.sh
QPKG_CONF=/etc/config/qpkg.conf
QTS_CRONTAB=/etc/config/crontab
CRON_MARKER='# basket-acme-renewal'
DEVICE_TOOL=/mnt/ext/opt/MyCloudNas/bin/qcloud_device_tool

say() {
  printf '%s\n' "$*"
}

fail() {
  say "ERROR: $*" >&2
  return 1
}

cleanup() {
  if [ -n "${TOKEN_FILE_TO_REMOVE:-}" ] && [ -f "$TOKEN_FILE_TO_REMOVE" ]; then
    rm -f "$TOKEN_FILE_TO_REMOVE"
  fi
  if [ -n "${DOWNLOAD_DIR:-}" ] && [ -d "$DOWNLOAD_DIR" ]; then
    rm -rf "$DOWNLOAD_DIR"
  fi
  if [ -n "${CRON_TEMP:-}" ] && [ -f "$CRON_TEMP" ]; then
    rm -f "$CRON_TEMP"
  fi
  if [ -n "${STAGING_DIR:-}" ] && [ -d "$STAGING_DIR" ]; then
    rm -rf "$STAGING_DIR"
  fi
}

require_root() {
  [ "$(id -u)" = 0 ] || fail "run this command as root"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "required command is missing: $1"
}

installed_version() {
  [ -x "$ACME" ] || return 1
  "$ACME" --version 2>/dev/null | sed -n 's/^v//p' | tail -n 1
}

install_pinned_acme() {
  current=$(installed_version || :)
  if [ "$current" = "$ACME_VERSION" ]; then
    say "acme.sh $ACME_VERSION is already installed."
    return 0
  fi

  DOWNLOAD_DIR=$(mktemp -d "/tmp/basket-acme.$ACME_VERSION.XXXXXX") || return 1
  archive=$DOWNLOAD_DIR/acme.sh.tar.gz
  say "Installing pinned acme.sh $ACME_VERSION."
  curl -fsSL "$ACME_URL" -o "$archive"
  actual=$(sha256sum "$archive" | awk '{print $1}')
  [ "$actual" = "$ACME_SHA256" ] || fail "acme.sh archive checksum mismatch" || return 1
  tar -xzf "$archive" -C "$DOWNLOAD_DIR"
  mkdir -p "$ACME_HOME"
  chmod 700 "$ACME_HOME"
  (
    cd "$DOWNLOAD_DIR/acme.sh-$ACME_VERSION"
    sh ./acme.sh --install \
      --home "$ACME_HOME" \
      --config-home "$ACME_HOME" \
      --accountemail "$ACCOUNT_EMAIL" \
      --no-cron \
      --no-profile
  )
  [ "$(installed_version)" = "$ACME_VERSION" ] || fail "installed acme.sh version is not $ACME_VERSION" || return 1

  "$ACME" --home "$ACME_HOME" --config-home "$ACME_HOME" \
    --set-default-ca --server letsencrypt --auto-upgrade 0
  chmod 700 "$ACME_HOME"
  [ ! -f "$ACME_HOME/account.conf" ] || chmod 600 "$ACME_HOME/account.conf"
}

issue_staging_certificate() {
  STAGING_DIR=$ACME_HOME/staging
  rm -rf "$STAGING_DIR"
  mkdir -p "$STAGING_DIR/certs"
  chmod 700 "$STAGING_DIR" "$STAGING_DIR/certs"
  say "Testing Cloudflare DNS-01 against Let's Encrypt staging."
  CF_Token=$CF_TOKEN "$ACME" --issue \
    --home "$ACME_HOME" \
    --config-home "$STAGING_DIR" \
    --cert-home "$STAGING_DIR/certs" \
    --server letsencrypt \
    --staging \
    --dns dns_cf \
    --domain "$DOMAIN" \
    --keylength 2048 \
    --accountemail "$ACCOUNT_EMAIL" \
    --auto-upgrade 0
  rm -rf "$STAGING_DIR"
  STAGING_DIR=
}

issue_production_certificate() {
  say "Issuing the production certificate for $DOMAIN without deploying it."
  CF_Token=$CF_TOKEN "$ACME" --issue \
    --home "$ACME_HOME" \
    --config-home "$ACME_HOME" \
    --server letsencrypt \
    --dns dns_cf \
    --domain "$DOMAIN" \
    --keylength 2048 \
    --accountemail "$ACCOUNT_EMAIL" \
    --auto-upgrade 0
  chmod 700 "$ACME_HOME"
  chmod 600 "$ACME_HOME/account.conf"
  openssl x509 -in "$ACME_HOME/$DOMAIN/$DOMAIN.cer" -noout \
    -checkhost "$DOMAIN" -checkend 2592000 >/dev/null 2>&1 || fail "issued certificate validation failed" || return 1
}

prepare() {
  require_root
  token_file=${1:-}
  [ -n "$token_file" ] || fail "usage: $0 prepare TOKEN_FILE" || return 2
  [ -s "$token_file" ] || fail "Cloudflare token file is missing or empty: $token_file" || return 1
  TOKEN_FILE_TO_REMOVE=$token_file
  CF_TOKEN=$(sed -n '1p' "$token_file")
  [ -n "$CF_TOKEN" ] || fail "Cloudflare token file is empty" || return 1

  for command in curl sha256sum tar awk sed openssl; do
    require_command "$command"
  done
  install_pinned_acme
  issue_staging_certificate
  issue_production_certificate
  unset CF_TOKEN
  say "Production certificate issued. The one-time token file has been removed; run disable-cloud next."
}

production_certificate_is_ready() {
  cert=$ACME_HOME/$DOMAIN/$DOMAIN.cer
  [ -s "$cert" ] || fail "issue the production certificate before disabling myQNAPcloud" || return 1
  openssl x509 -in "$cert" -noout -checkhost "$DOMAIN" -checkend 2592000 >/dev/null 2>&1 || fail "the prepared certificate is invalid or too close to expiry" || return 1
}

wait_until_unbound() {
  attempts=0
  while [ "$attempts" -lt 12 ]; do
    attempts=$((attempts + 1))
    status=$(/sbin/getcfg "QNAP ID Service" STATUS -f /etc/config/qid.conf -d 0)
    [ "$status" != 3 ] && return 0
    sleep 5
  done
  return 1
}

disable_qpkg() {
  name=$1
  start_script=$2
  "$start_script" stop >/dev/null 2>&1 || :
  /sbin/qpkg_cli --disable "$name" >/dev/null 2>&1 || /sbin/setcfg "$name" Enable FALSE -f "$QPKG_CONF"
  /sbin/setcfg "$name" Enable FALSE -f "$QPKG_CONF"
}

stop_myqnapcloud_upnp_client() {
  /sbin/setcfg UPnP_Global Enable FALSE -f /etc/config/upnpc.conf
  /sbin/daemon_mgr upnpcd stop "/sbin/upnpcd -i 300 &" >/dev/null 2>&1 || :
  attempts=0
  while [ -n "$(/bin/pidof upnpcd 2>/dev/null || :)" ] && [ "$attempts" -lt 10 ]; do
    /usr/bin/killall upnpcd >/dev/null 2>&1 || :
    attempts=$((attempts + 1))
    sleep 1
  done
}

disable_cloud() {
  require_root
  production_certificate_is_ready
  [ -x "$DEVICE_TOOL" ] || fail "myQNAPcloud device tool is missing" || return 1

  status=$(/sbin/getcfg "QNAP ID Service" STATUS -f /etc/config/qid.conf -d 0)
  if [ "$status" = 3 ]; then
    say "Unregistering basket from myQNAPcloud."
    "$DEVICE_TOOL" unbind_device >/dev/null
    wait_until_unbound || fail "myQNAPcloud still reports basket as registered" || return 1
    # QTS releases/restores its myQNAPcloud certificate asynchronously.
    sleep 12
  fi

  say "Disabling the myQNAPcloud certificate and device packages."
  disable_qpkg QcloudSSLCertificate /mnt/ext/opt/QcloudSSLCertificate/QcloudSSLCertificate.sh
  disable_qpkg MyCloudNas /mnt/ext/opt/MyCloudNas/MyCloudNas.sh
  /usr/bin/qevent unsubscribe -a HAManager -e role_change -s QcloudSSLCertificate -S /etc/init.d/QcloudSSLCertificate.sh >/dev/null 2>&1 || :
  /usr/bin/qevent unsubscribe -a HAManager -e role_change -s MyCloudNas -S /etc/init.d/MyCloudNas.sh >/dev/null 2>&1 || :
  /usr/bin/qevent unsubscribe -a HAManager -e ha_status_change -s MyCloudNas -S /etc/init.d/MyCloudNas.sh >/dev/null 2>&1 || :
  stop_myqnapcloud_upnp_client
  sed -i '/ssl_agent_cli/d' "$QTS_CRONTAB"
  /usr/bin/crontab "$QTS_CRONTAB" -c /tmp/cron/crontabs
  say "myQNAPcloud is unregistered and disabled. The QNAP media UPnP services were left untouched."
}

cloud_is_disabled() {
  failed=0
  for name in MyCloudNas QcloudSSLCertificate; do
    enabled=$(/sbin/getcfg "$name" Enable -f "$QPKG_CONF" -d FALSE)
    if [ "$enabled" != FALSE ]; then
      say "ERROR: QPKG is not disabled: $name" >&2
      failed=1
    fi
  done
  status=$(/sbin/getcfg "QNAP ID Service" STATUS -f /etc/config/qid.conf -d 0)
  if [ "$status" = 3 ]; then
    say "ERROR: basket is still registered with myQNAPcloud" >&2
    failed=1
  fi
  upnp=$(/sbin/getcfg UPnP_Global Enable -f /etc/config/upnpc.conf -d FALSE)
  if [ "$upnp" != FALSE ]; then
    say "ERROR: myQNAPcloud automatic router configuration is enabled" >&2
    failed=1
  fi
  if [ -n "$(/bin/pidof upnpcd 2>/dev/null || :)" ]; then
    say "ERROR: myQNAPcloud UPnP client is still running" >&2
    failed=1
  fi
  if grep 'ssl_agent_cli' "$QTS_CRONTAB" >/dev/null 2>&1; then
    say "ERROR: myQNAPcloud certificate renewal remains in cron" >&2
    failed=1
  fi
  [ "$failed" = 0 ]
}

install_renewal_cron() {
  CRON_TEMP=$(mktemp /tmp/basket-crontab.XXXXXX)
  grep -v "$CRON_MARKER" "$QTS_CRONTAB" >"$CRON_TEMP" || :
  printf '%s\n' "17 03 * * * $ACME --cron --home $ACME_HOME --config-home $ACME_HOME > $ACME_HOME/cron.log 2>&1 || /sbin/write_log '[basket ACME] certificate renewal failed' 1 $CRON_MARKER" >>"$CRON_TEMP"
  cp "$CRON_TEMP" "$QTS_CRONTAB"
  /usr/bin/crontab "$QTS_CRONTAB" -c /tmp/cron/crontabs
  rm -f "$CRON_TEMP"
  CRON_TEMP=
}

activate() {
  require_root
  cloud_is_disabled || fail "refusing to deploy until myQNAPcloud is fully disabled" || return 1
  production_certificate_is_ready
  [ -f "$SCRIPT_DIR/deploy-certificate.sh" ] || fail "deploy-certificate.sh must be beside this installer" || return 1

  mkdir -p "$DEPLOY_DIR"
  chmod 700 "$DEPLOY_DIR"
  cp "$SCRIPT_DIR/deploy-certificate.sh" "$DEPLOY_HOOK"
  chmod 700 "$DEPLOY_HOOK"
  "$ACME" --install-cert \
    --home "$ACME_HOME" \
    --config-home "$ACME_HOME" \
    --domain "$DOMAIN" \
    --key-file "$DEPLOY_DIR/key.pem" \
    --cert-file "$DEPLOY_DIR/cert.pem" \
    --ca-file "$DEPLOY_DIR/ca.pem" \
    --fullchain-file "$DEPLOY_DIR/fullchain.pem" \
    --reloadcmd "$DEPLOY_HOOK" \
    --auto-upgrade 0
  "$DEPLOY_HOOK" --check
  install_renewal_cron
  say "Certificate deployment and renewal are active."
}

check() {
  require_root
  [ "$(installed_version || :)" = "$ACME_VERSION" ] || fail "acme.sh is missing or is not pinned at $ACME_VERSION" || return 1
  cloud_is_disabled || return 1
  [ -x "$DEPLOY_HOOK" ] || fail "certificate deploy hook is not installed" || return 1
  "$DEPLOY_HOOK" --check
  count=$(grep -c "$CRON_MARKER" "$QTS_CRONTAB" || :)
  [ "$count" = 1 ] || fail "expected exactly one basket ACME cron entry, found $count" || return 1
  say "basket ACME and myQNAPcloud checks passed."
}

SCRIPT_DIR=$(
  unset CDPATH
  cd "$(dirname "$0")"
  pwd
)
TOKEN_FILE_TO_REMOVE=
DOWNLOAD_DIR=
CRON_TEMP=
STAGING_DIR=
trap cleanup EXIT HUP INT TERM

case ${1:-} in
  prepare)
    shift
    prepare "$@"
    ;;
  disable-cloud)
    [ "$#" = 1 ] || fail "usage: $0 disable-cloud" || exit 2
    disable_cloud
    ;;
  activate)
    [ "$#" = 1 ] || fail "usage: $0 activate" || exit 2
    activate
    ;;
  check)
    [ "$#" = 1 ] || fail "usage: $0 check" || exit 2
    check
    ;;
  *)
    fail "usage: $0 {prepare TOKEN_FILE|disable-cloud|activate|check}"
    exit 2
    ;;
esac
