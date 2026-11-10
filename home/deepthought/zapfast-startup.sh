#!/bin/sh
set -eu

# Finish the smartcard PIN prompt before ZapFast starts its timed D-Bus request.
for properties in "${PASSWORD_STORE_DIR:-$HOME/.password-store}"/secret_service/*/*.properties; do
  [ -f "$properties" ] || continue
  if jq -e '."org.freedesktop.Secret.Item.Attributes".service == "rocks.zapfast.ZapFast"' "$properties" >/dev/null; then
    gpg --quiet --decrypt "${properties%.properties}.gpg" >/dev/null
  fi
done

exec zapfast "$@"
