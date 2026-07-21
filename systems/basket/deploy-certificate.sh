#!/bin/sh

set -eu
umask 077

DOMAIN=${BASKET_ACME_DOMAIN:-basket.4amlunch.net}
CERT_DIR=${BASKET_ACME_CERT_DIR:-/share/homes/admin/.acme.sh/deploy}
QTS_DIR=${BASKET_QTS_STUNNEL_DIR:-/etc/config/stunnel}
BACKUP_ROOT=${BASKET_ACME_BACKUP_DIR:-/share/homes/admin/.acme.sh/qts-backup}
QTS_RESTART=${BASKET_QTS_RESTART:-/etc/init.d/stunnel.sh}
QTS_HTTPS_PORT=${BASKET_QTS_HTTPS_PORT:-443}
SKIP_LIVE_CHECK=${BASKET_SKIP_LIVE_CHECK:-0}
SET_CERT_TYPE=${BASKET_QTS_SET_CERT_TYPE:-1}
ALLOW_NONROOT=${BASKET_ALLOW_NONROOT:-0}

SOURCE_KEY=$CERT_DIR/key.pem
SOURCE_CERT=$CERT_DIR/cert.pem
SOURCE_CA=$CERT_DIR/ca.pem
SOURCE_FULLCHAIN=$CERT_DIR/fullchain.pem
QTS_FILES="backup.key backup.cert stunnel.pem uca.pem"

say() {
  printf '%s\n' "$*"
}

fail() {
  say "ERROR: $*" >&2
  return 1
}

qts_error() {
  message=$1
  if [ -x /sbin/write_log ]; then
    /sbin/write_log "[basket ACME] $message" 1 >/dev/null 2>&1 || :
  fi
  say "ERROR: $message" >&2
}

require_root() {
  if [ "$ALLOW_NONROOT" != 1 ] && [ "$(id -u)" != 0 ]; then
    fail "run this command as root"
  fi
}

make_work_dir() {
  base=${TMPDIR:-/tmp}
  WORK_DIR=$(mktemp -d "$base/basket-cert.XXXXXX") || fail "could not create a temporary directory"
}

cleanup() {
  if [ -n "${STAGE_DIR:-}" ] && [ -d "$STAGE_DIR" ]; then
    rm -rf "$STAGE_DIR"
  fi
  if [ -n "${WORK_DIR:-}" ] && [ -d "$WORK_DIR" ]; then
    rm -rf "$WORK_DIR"
  fi
  if [ -n "${SELF_ROOT:-}" ] && [ -d "$SELF_ROOT" ]; then
    rm -rf "$SELF_ROOT"
  fi
}

validate_certificate() {
  for path in "$SOURCE_KEY" "$SOURCE_CERT" "$SOURCE_CA" "$SOURCE_FULLCHAIN"; do
    [ -s "$path" ] || fail "missing certificate input: $path" || return 1
  done

  openssl x509 -in "$SOURCE_CERT" -noout >/dev/null 2>&1 || fail "leaf certificate is not valid PEM" || return 1
  openssl x509 -in "$SOURCE_CA" -noout >/dev/null 2>&1 || fail "CA certificate is not valid PEM" || return 1
  openssl x509 -in "$SOURCE_CERT" -noout -checkhost "$DOMAIN" >/dev/null 2>&1 || fail "leaf certificate does not cover $DOMAIN" || return 1
  openssl x509 -in "$SOURCE_CERT" -noout -checkend 2592000 >/dev/null 2>&1 || fail "leaf certificate expires in less than 30 days" || return 1

  openssl x509 -in "$SOURCE_CERT" -pubkey -noout >"$WORK_DIR/cert.pub" 2>/dev/null || fail "could not read certificate public key" || return 1
  openssl pkey -in "$SOURCE_KEY" -pubout >"$WORK_DIR/key.pub" 2>/dev/null || fail "could not read private key" || return 1
  cmp -s "$WORK_DIR/cert.pub" "$WORK_DIR/key.pub" || fail "certificate and private key do not match" || return 1
}

backup_qts_certificate() {
  mkdir -p "$BACKUP_ROOT" || return 1
  chmod 700 "$BACKUP_ROOT" || return 1
  BACKUP_DIR=$BACKUP_ROOT/$(date +%Y%m%dT%H%M%S)-$$
  mkdir "$BACKUP_DIR" || return 1
  chmod 700 "$BACKUP_DIR" || return 1

  for name in backup.key backup.cert stunnel.pem; do
    [ -f "$QTS_DIR/$name" ] || fail "QTS certificate file is missing: $QTS_DIR/$name" || return 1
    cp -p "$QTS_DIR/$name" "$BACKUP_DIR/$name" || return 1
  done
  if [ -f "$QTS_DIR/uca.pem" ]; then
    cp -p "$QTS_DIR/uca.pem" "$BACKUP_DIR/uca.pem" || return 1
  fi
  if [ "$SET_CERT_TYPE" = 1 ]; then
    /sbin/getcfg "SSL Import" cert_type -f /etc/config/uLinux.conf -d 0 >"$BACKUP_DIR/cert_type" || return 1
  fi
}

stage_certificate() {
  STAGE_DIR=$QTS_DIR/.basket-acme.$$
  mkdir "$STAGE_DIR" || return 1
  chmod 700 "$STAGE_DIR" || return 1

  cp "$SOURCE_KEY" "$STAGE_DIR/backup.key" || return 1
  cp "$SOURCE_CERT" "$STAGE_DIR/backup.cert" || return 1
  cp "$SOURCE_CA" "$STAGE_DIR/uca.pem" || return 1
  cat "$SOURCE_KEY" "$SOURCE_CERT" >"$STAGE_DIR/stunnel.pem" || return 1
  chmod 600 "$STAGE_DIR/backup.key" "$STAGE_DIR/backup.cert" "$STAGE_DIR/uca.pem" "$STAGE_DIR/stunnel.pem" || return 1
}

install_staged_certificate() {
  for name in $QTS_FILES; do
    mv "$STAGE_DIR/$name" "$QTS_DIR/$name" || return 1
  done
  rmdir "$STAGE_DIR" || return 1
  STAGE_DIR=

  if [ "$SET_CERT_TYPE" = 1 ]; then
    /sbin/setcfg "SSL Import" cert_type 2 || return 1
  fi
  "$QTS_RESTART" restart
}

certificate_fingerprint() {
  openssl x509 -in "$1" -noout -fingerprint -sha256 2>/dev/null
}

live_certificate_matches() {
  [ "$SKIP_LIVE_CHECK" = 1 ] && return 0

  wanted=$(certificate_fingerprint "$SOURCE_CERT") || return 1
  attempts=0
  while [ "$attempts" -lt 15 ]; do
    attempts=$((attempts + 1))
    if printf '\n' | openssl s_client -connect "127.0.0.1:$QTS_HTTPS_PORT" -servername "$DOMAIN" 2>/dev/null | openssl x509 -outform PEM >"$WORK_DIR/live.pem" 2>/dev/null; then
      served=$(certificate_fingerprint "$WORK_DIR/live.pem") || served=
      if [ "$served" = "$wanted" ] && openssl x509 -in "$WORK_DIR/live.pem" -noout -checkhost "$DOMAIN" -checkend 2592000 >/dev/null 2>&1; then
        return 0
      fi
    fi
    sleep 1
  done
  return 1
}

restore_backup() {
  restored=0
  if [ -n "${BACKUP_DIR:-}" ] && [ -d "$BACKUP_DIR" ]; then
    for name in $QTS_FILES; do
      if [ -f "$BACKUP_DIR/$name" ]; then
        cp -p "$BACKUP_DIR/$name" "$QTS_DIR/$name" || restored=1
      else
        rm -f "$QTS_DIR/$name" || restored=1
      fi
    done
    if [ "$SET_CERT_TYPE" = 1 ] && [ -s "$BACKUP_DIR/cert_type" ]; then
      old_cert_type=$(cat "$BACKUP_DIR/cert_type")
      /sbin/setcfg "SSL Import" cert_type "$old_cert_type" || restored=1
    fi
    "$QTS_RESTART" restart >/dev/null 2>&1 || restored=1
  else
    restored=1
  fi
  return "$restored"
}

deploy() {
  require_root || return 1
  make_work_dir || return 1
  validate_certificate || return 1
  backup_qts_certificate || return 1
  stage_certificate || {
    qts_error "could not stage the new certificate; QTS was not changed"
    return 1
  }

  if ! install_staged_certificate; then
    qts_error "certificate installation or QTS HTTPS restart failed; restoring the previous certificate"
    restore_backup || qts_error "automatic certificate rollback also failed"
    return 1
  fi
  if ! live_certificate_matches; then
    qts_error "QTS HTTPS did not present the new $DOMAIN certificate; restoring the previous certificate"
    restore_backup || qts_error "automatic certificate rollback also failed"
    return 1
  fi

  say "Installed and verified the QTS HTTPS certificate for $DOMAIN."
}

check() {
  make_work_dir || return 1
  validate_certificate || return 1
  if ! live_certificate_matches; then
    fail "QTS HTTPS is not presenting the installed $DOMAIN certificate" || return 1
  fi
  say "The stored and live QTS certificates for $DOMAIN match and are valid for at least 30 days."
}

write_restart_helper() {
  path=$1
  status=$2
  {
    printf '%s\n' '#!/bin/sh'
    printf 'exit %s\n' "$status"
  } >"$path"
  chmod 700 "$path"
}

seed_qts_files() {
  marker=$1
  for name in $QTS_FILES; do
    printf '%s:%s\n' "$marker" "$name" >"$SELF_QTS/$name"
  done
}

assert_qts_files() {
  marker=$1
  for name in backup.key backup.cert stunnel.pem; do
    expected=$marker:$name
    actual=$(cat "$SELF_QTS/$name")
    [ "$actual" = "$expected" ] || fail "self-test expected $name to be restored" || return 1
  done
}

self_test() {
  SELF_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/basket-cert-selftest.XXXXXX") || return 1
  SELF_CERT=$SELF_ROOT/cert
  SELF_QTS=$SELF_ROOT/qts
  SELF_BACKUP=$SELF_ROOT/backups
  mkdir "$SELF_CERT" "$SELF_QTS" "$SELF_BACKUP"

  openssl req -x509 -newkey rsa:2048 -nodes -days 90 \
    -subj "/CN=$DOMAIN" -addext "subjectAltName=DNS:$DOMAIN" \
    -keyout "$SELF_CERT/key.pem" -out "$SELF_CERT/cert.pem" >/dev/null 2>&1
  cp "$SELF_CERT/cert.pem" "$SELF_CERT/ca.pem"
  cp "$SELF_CERT/cert.pem" "$SELF_CERT/fullchain.pem"
  write_restart_helper "$SELF_ROOT/restart-ok" 0
  write_restart_helper "$SELF_ROOT/restart-fail" 1

  seed_qts_files success-old
  rm -f "$SELF_QTS/uca.pem"
  BASKET_ACME_CERT_DIR=$SELF_CERT \
    BASKET_QTS_STUNNEL_DIR=$SELF_QTS \
    BASKET_ACME_BACKUP_DIR=$SELF_BACKUP \
    BASKET_QTS_RESTART=$SELF_ROOT/restart-ok \
    BASKET_SKIP_LIVE_CHECK=1 \
    BASKET_QTS_SET_CERT_TYPE=0 \
    BASKET_ALLOW_NONROOT=1 \
    "$SCRIPT_PATH" >/dev/null
  cmp -s "$SELF_CERT/key.pem" "$SELF_QTS/backup.key" || fail "self-test did not install the key" || return 1
  cmp -s "$SELF_CERT/cert.pem" "$SELF_QTS/backup.cert" || fail "self-test did not install the certificate" || return 1
  cmp -s "$SELF_CERT/ca.pem" "$SELF_QTS/uca.pem" || fail "self-test did not install the missing CA chain" || return 1

  cp "$SELF_CERT/key.pem" "$SELF_ROOT/right-key.pem"
  openssl genrsa -out "$SELF_CERT/key.pem" 2048 >/dev/null 2>&1
  if BASKET_ACME_CERT_DIR=$SELF_CERT \
    BASKET_QTS_STUNNEL_DIR=$SELF_QTS \
    BASKET_ACME_BACKUP_DIR=$SELF_BACKUP \
    BASKET_QTS_RESTART=$SELF_ROOT/restart-ok \
    BASKET_SKIP_LIVE_CHECK=1 \
    BASKET_QTS_SET_CERT_TYPE=0 \
    BASKET_ALLOW_NONROOT=1 \
    "$SCRIPT_PATH" >/dev/null 2>&1; then
    fail "self-test accepted a mismatched private key" || return 1
  fi
  cmp -s "$SELF_ROOT/right-key.pem" "$SELF_QTS/backup.key" || fail "mismatched-key self-test changed QTS" || return 1
  cmp -s "$SELF_CERT/cert.pem" "$SELF_QTS/backup.cert" || fail "mismatched-key self-test changed QTS" || return 1

  cp "$SELF_ROOT/right-key.pem" "$SELF_CERT/key.pem"
  seed_qts_files rollback-old
  rm -f "$SELF_QTS/uca.pem"
  if BASKET_ACME_CERT_DIR=$SELF_CERT \
    BASKET_QTS_STUNNEL_DIR=$SELF_QTS \
    BASKET_ACME_BACKUP_DIR=$SELF_BACKUP \
    BASKET_QTS_RESTART=$SELF_ROOT/restart-fail \
    BASKET_SKIP_LIVE_CHECK=1 \
    BASKET_QTS_SET_CERT_TYPE=0 \
    BASKET_ALLOW_NONROOT=1 \
    "$SCRIPT_PATH" >/dev/null 2>&1; then
    fail "self-test accepted a failed QTS restart" || return 1
  fi
  assert_qts_files rollback-old
  [ ! -e "$SELF_QTS/uca.pem" ] || fail "self-test did not restore the missing CA chain state" || return 1

  rm -rf "$SELF_ROOT"
  SELF_ROOT=
  say "Certificate deploy self-test passed."
}

SCRIPT_DIR=$(
  unset CDPATH
  cd "$(dirname "$0")"
  pwd
)
SCRIPT_PATH=$SCRIPT_DIR/$(basename "$0")
WORK_DIR=
STAGE_DIR=
BACKUP_DIR=
SELF_ROOT=
trap cleanup EXIT HUP INT TERM

case ${1:-deploy} in
  deploy)
    deploy
    ;;
  --check)
    check
    ;;
  --self-test)
    self_test
    ;;
  *)
    fail "usage: $0 [deploy|--check|--self-test]"
    exit 2
    ;;
esac
