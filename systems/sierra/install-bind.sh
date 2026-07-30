#!/bin/sh

set -eu
umask 077

ZONES='lan.4amlunch.net 0.42.10.in-addr.arpa 11.42.10.in-addr.arpa'
TEMPLATE=${SIERRA_ROOT:-}/usr/local/opnsense/service/templates/OPNsense/Bind/named.conf
NAMED_CONF=${SIERRA_ROOT:-}/usr/local/etc/namedb/named.conf
CUSTOM_DIR=${SIERRA_ROOT:-}/usr/local/etc/namedb/named.conf.d
DYNAMIC_DIR=${SIERRA_ROOT:-}/usr/local/etc/namedb/dynamic
CUSTOM_CONF=$CUSTOM_DIR/10-kea-zones.conf
TTL_LINE='        max-ncache-ttl 300;'
SYNTH_LINE='        synth-from-dnssec no;'
TTL_ANCHOR="{% if helpers.exists('OPNsense.bind.general.dnssecvalidation') and OPNsense.bind.general.dnssecvalidation != '' %}"
NAMED_CHECKCONF=${NAMED_CHECKCONF:-named-checkconf}
NAMED_CHECKZONE=${NAMED_CHECKZONE:-named-checkzone}
RNDC=${RNDC:-rndc}

say() {
  printf '%s\n' "$*"
}

fail() {
  say "ERROR: $*" >&2
  return 1
}

require_root() {
  if [ -z "${SIERRA_ROOT:-}" ] && [ "$(id -u)" != 0 ]; then
    fail "run this command as root"
    return 1
  fi
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    fail "required command is missing: $1"
    return 1
  fi
}

install_file() {
  mode=$1
  owner=$2
  group=$3
  source=$4
  target=$5

  if [ -n "${SIERRA_ROOT:-}" ]; then
    install -m "$mode" "$source" "$target"
  else
    install -o "$owner" -g "$group" -m "$mode" "$source" "$target"
  fi
}

make_dynamic_dir() {
  if [ -n "${SIERRA_ROOT:-}" ]; then
    install -d -m 0750 "$DYNAMIC_DIR"
  else
    install -d -o bind -g bind -m 0750 "$DYNAMIC_DIR"
  fi
}

render_custom_config() {
  for zone in $ZONES; do
    cat <<EOF
zone "$zone" {
        type primary;
        file "$DYNAMIC_DIR/$zone.db";
        allow-transfer { bob_secondary; };
        allow-query { trusted_lan; };
        update-policy { grant rndc-key zonesub ANY; };
};
EOF
  done
}

install_custom_config() {
  install -d -m 0755 "$CUSTOM_DIR"
  temporary=$(mktemp "${TMPDIR:-/tmp}/sierra-bind-conf.XXXXXX")
  render_custom_config >"$temporary"
  if [ ! -f "$CUSTOM_CONF" ] || ! cmp -s "$temporary" "$CUSTOM_CONF"; then
    install_file 0644 root wheel "$temporary" "$CUSTOM_CONF"
  fi
  rm -f "$temporary"
}

install_zone_files() {
  seed_dir=${1:-}
  make_dynamic_dir

  for zone in $ZONES; do
    target=$DYNAMIC_DIR/$zone.db
    if [ -f "$target" ]; then
      "$NAMED_CHECKZONE" -j "$zone" "$target" >/dev/null
      continue
    fi

    if [ -z "$seed_dir" ]; then
      fail "missing $target and no seed directory was supplied"
      return 1
    fi
    seed=$seed_dir/$zone.db
    if [ ! -f "$seed" ]; then
      fail "missing recovery seed: $seed"
      return 1
    fi
    "$NAMED_CHECKZONE" "$zone" "$seed" >/dev/null
    install_file 0640 bind bind "$seed" "$target"
  done
}

patch_template() {
  if [ ! -f "$TEMPLATE" ]; then
    fail "BIND template is missing: $TEMPLATE"
    return 1
  fi

  ttl_count=$(grep -Fxc "$TTL_LINE" "$TEMPLATE" || :)
  synth_count=$(grep -Fxc "$SYNTH_LINE" "$TEMPLATE" || :)
  if [ "$ttl_count" -gt 1 ]; then
    fail "BIND template contains duplicate max-ncache-ttl settings"
    return 1
  fi
  if [ "$synth_count" -gt 1 ]; then
    fail "BIND template contains duplicate synth-from-dnssec settings"
    return 1
  fi
  if [ "$ttl_count" -eq 1 ] && [ "$synth_count" -eq 1 ]; then
    return 0
  fi

  anchor_count=$(grep -Fxc "$TTL_ANCHOR" "$TEMPLATE" || :)
  if [ "$anchor_count" -ne 1 ]; then
    fail "OPNsense BIND template changed; max-ncache-ttl anchor not found exactly once"
    return 1
  fi

  add_ttl=0
  add_synth=0
  if [ "$ttl_count" -eq 0 ]; then
    add_ttl=1
  fi
  if [ "$synth_count" -eq 0 ]; then
    add_synth=1
  fi

  temporary=$(mktemp "${TMPDIR:-/tmp}/sierra-bind-template.XXXXXX")
  awk -v anchor="$TTL_ANCHOR" -v ttl="$TTL_LINE" -v synth="$SYNTH_LINE" \
    -v add_ttl="$add_ttl" -v add_synth="$add_synth" '
    $0 == anchor {
      if (add_ttl) print ttl
      if (add_synth) print synth
    }
    { print }
  ' "$TEMPLATE" >"$temporary"
  install_file 0644 root wheel "$temporary" "$TEMPLATE"
  rm -f "$temporary"
}

install_bind() {
  require_root
  for command in awk cmp grep install mktemp "$NAMED_CHECKZONE"; do
    require_command "$command"
  done
  install_zone_files "${1:-}"
  install_custom_config
  patch_template
  say "Sierra BIND custom zones and 300-second negative-cache safeguards are staged."
  say "Remove the three dynamic zones from the OPNsense model, reconfigure BIND once, then run: $0 check"
}

check_bind() {
  require_root
  for command in cmp grep mktemp "$NAMED_CHECKCONF" "$NAMED_CHECKZONE" "$RNDC"; do
    require_command "$command"
  done

  if [ "$(grep -Fxc "$TTL_LINE" "$TEMPLATE" || :)" -ne 1 ]; then
    fail "BIND template does not contain exactly one 300-second negative-cache cap"
    return 1
  fi
  if [ "$(grep -Fxc "$SYNTH_LINE" "$TEMPLATE" || :)" -ne 1 ]; then
    fail "BIND template does not disable aggressive DNSSEC negative synthesis"
    return 1
  fi
  if [ "$(grep -Fxc "$TTL_LINE" "$NAMED_CONF" || :)" -ne 1 ]; then
    fail "generated named.conf does not contain the 300-second negative-cache cap"
    return 1
  fi
  if [ "$(grep -Fxc "$SYNTH_LINE" "$NAMED_CONF" || :)" -ne 1 ]; then
    fail "generated named.conf does not disable aggressive DNSSEC negative synthesis"
    return 1
  fi

  temporary=$(mktemp "${TMPDIR:-/tmp}/sierra-bind-check.XXXXXX")
  render_custom_config >"$temporary"
  if ! cmp -s "$temporary" "$CUSTOM_CONF"; then
    fail "custom BIND configuration differs from the installer"
    return 1
  fi
  rm -f "$temporary"

  "$NAMED_CHECKCONF" -z "$NAMED_CONF" >/dev/null
  for zone in $ZONES; do
    "$NAMED_CHECKZONE" -j "$zone" "$DYNAMIC_DIR/$zone.db" >/dev/null
    "$RNDC" zonestatus "$zone" >/dev/null
  done
  say "Sierra BIND configuration, dynamic zones, and negative-cache safeguards are healthy."
}

self_test() {
  require_command awk
  require_command cmp
  require_command grep
  require_command install
  require_command mktemp
  require_command "$NAMED_CHECKZONE"

  test_root=$(mktemp -d "${TMPDIR:-/tmp}/sierra-bind-test.XXXXXX")
  trap 'rm -rf "$test_root"' EXIT HUP INT TERM
  SIERRA_ROOT=$test_root
  TEMPLATE=$test_root/usr/local/opnsense/service/templates/OPNsense/Bind/named.conf
  CUSTOM_DIR=$test_root/usr/local/etc/namedb/named.conf.d
  DYNAMIC_DIR=$test_root/usr/local/etc/namedb/dynamic
  CUSTOM_CONF=$CUSTOM_DIR/10-kea-zones.conf
  seeds=$test_root/seeds
  install -d "$(dirname "$TEMPLATE")" "$seeds"
  printf '%s\n' "$TTL_ANCHOR" >"$TEMPLATE"

  for zone in $ZONES; do
    cat >"$seeds/$zone.db" <<'EOF'
$TTL 300
@ IN SOA sierra.4amlunch.net. hostmaster.4amlunch.net. ( 1 21600 3600 3542400 300 )
@ IN NS sierra.4amlunch.net.
@ IN NS bob.4amlunch.net.
EOF
  done

  install_zone_files "$seeds"
  install_custom_config
  patch_template
  [ "$(grep -Fxc "$TTL_LINE" "$TEMPLATE")" -eq 1 ]
  [ "$(grep -Fxc "$SYNTH_LINE" "$TEMPLATE")" -eq 1 ]

  printf '%s\n' '; live data' >>"$DYNAMIC_DIR/lan.4amlunch.net.db"
  install_zone_files "$seeds"
  grep -Fqx '; live data' "$DYNAMIC_DIR/lan.4amlunch.net.db"

  patch_template
  [ "$(grep -Fxc "$TTL_LINE" "$TEMPLATE")" -eq 1 ]
  [ "$(grep -Fxc "$SYNTH_LINE" "$TEMPLATE")" -eq 1 ]
  printf '%s\n' 'template changed' >"$TEMPLATE"
  if patch_template >/dev/null 2>&1; then
    fail "template patch should reject a missing anchor"
  fi

  rm -rf "$test_root"
  trap - EXIT HUP INT TERM
  say "Sierra BIND installer self-test passed."
}

case ${1:-} in
  install)
    shift
    [ "$#" -le 1 ] || fail "usage: $0 install [SEED_DIR]"
    install_bind "${1:-}"
    ;;
  check)
    [ "$#" -eq 1 ] || fail "usage: $0 check"
    check_bind
    ;;
  --self-test)
    [ "$#" -eq 1 ] || fail "usage: $0 --self-test"
    self_test
    ;;
  *)
    fail "usage: $0 {install [SEED_DIR]|check|--self-test}"
    ;;
esac
