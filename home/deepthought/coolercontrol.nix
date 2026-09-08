{ pkgs, ... }:
let
  refreshCookie = pkgs.writeShellScript "coolercontrol-refresh-cookie" ''
    set -eu

    password_path="/run/secrets/coolercontrol-admin-password"
    config_dir="$HOME/.config/org.coolercontrol.CoolerControl"
    config_file="$config_dir/CoolerControl.conf"
    webengine_cookie_db="$HOME/.local/share/org.coolercontrol.CoolerControl/CoolerControl/QtWebEngine/coolercontrol/Cookies"
    cookie_jar="''${XDG_RUNTIME_DIR:-/tmp}/coolercontrol-gui-cookie"
    url="https://127.0.0.1:11987"

    [ -r "$password_path" ] || exit 1
    auth_file="$(${pkgs.coreutils}/bin/mktemp "''${XDG_RUNTIME_DIR:-/tmp}/coolercontrol-gui-auth.XXXXXX")"
    trap 'rm -f "$auth_file"' EXIT

    for _ in $(seq 1 60); do
      if ${pkgs.curl}/bin/curl -fsk -X GET "$url/handshake" >/dev/null 2>&1; then
        break
      fi
      sleep 1
    done

    password="$(cat "$password_path")"
    printf 'machine 127.0.0.1 login CCAdmin password %s\n' "$password" > "$auth_file"
    chmod 600 "$auth_file"
    ${pkgs.curl}/bin/curl -fsk -c "$cookie_jar" --netrc-file "$auth_file" -X POST "$url/login" -H 'content-type: application/json' --data '{}' >/dev/null

    cookie="$(${pkgs.gawk}/bin/awk '$6 == "cc" { value = $7 } END { if (value != "") print value; else exit 1 }' "$cookie_jar")"
    expires="$(LC_ALL=C ${pkgs.coreutils}/bin/date -u -d '+1 year' '+%a, %d-%b-%Y %H:%M:%S GMT')"

    mkdir -p "$config_dir"
    ${pkgs.python3}/bin/python3 - "$config_file" "$webengine_cookie_db" "$cookie" "$expires" <<'PY'
    import sqlite3
    import sys
    import time
    from pathlib import Path

    config_file = Path(sys.argv[1])
    webengine_cookie_db = Path(sys.argv[2])
    cookie = sys.argv[3]
    expires = sys.argv[4]
    line = f'networkCookies="@ByteArray(cc={cookie}; HttpOnly; expires={expires}; domain=localhost; path=/\\n)"'

    if config_file.exists():
        lines = config_file.read_text().splitlines()
    else:
        lines = ["[General]"]

    if not any(item.strip() == "[General]" for item in lines):
        lines.insert(0, "[General]")

    for index, item in enumerate(lines):
        if item.startswith("networkCookies="):
            lines[index] = line
            break
    else:
        lines.append(line)

    config_file.write_text("\n".join(lines) + "\n")

    if webengine_cookie_db.exists():
        now = int((time.time() + 11644473600) * 1_000_000)
        expires_utc = now + 365 * 24 * 60 * 60 * 1_000_000
        with sqlite3.connect(webengine_cookie_db, timeout=1) as con:
            con.execute("DELETE FROM cookies WHERE host_key = 'localhost' AND name = 'cc'")
            con.execute(
                """
                INSERT INTO cookies (
                    creation_utc, host_key, top_frame_site_key, name, value, encrypted_value, path,
                    expires_utc, is_secure, is_httponly, last_access_utc, has_expires,
                    is_persistent, priority, samesite, source_scheme, source_port,
                    last_update_utc, source_type, has_cross_site_ancestor
                ) VALUES (?, 'localhost', ?, 'cc', ?, ?, '/', ?, 1, 1, ?, 1, 1, 1, 2, 2, 11987, ?, 0, 0)
                """,
                (now, "", cookie, b"", expires_utc, now, now),
            )
    PY
  '';
  launchCoolercontrol = pkgs.writeShellScript "coolercontrol-gui" ''
    ${refreshCookie} || true
    exec ${pkgs.coolercontrol.coolercontrol-gui}/bin/coolercontrol "$@"
  '';
in
{
  xdg.configFile."autostart/org.coolercontrol.CoolerControl.desktop" = {
    force = true;
    text = ''
      [Desktop Entry]
      Type=Application
      Name=CoolerControl
      Hidden=true
    '';
  };

  xdg.desktopEntries."org.coolercontrol.CoolerControl" = {
    name = "CoolerControl";
    exec = "${launchCoolercontrol}";
    icon = "org.coolercontrol.CoolerControl";
    terminal = false;
    type = "Application";
    startupNotify = true;
    categories = [ "Utility" ];
    settings = {
      Keywords = "cooling;fan control;pump control;";
      StartupWMClass = "org.coolercontrol.CoolerControl";
    };
  };

  systemd.user.services.coolercontrol = {
    Unit = {
      Description = "CoolerControl GUI";
      After = [ "graphical-session.target" ];
    };

    Service = {
      ExecStart = launchCoolercontrol;
    };

    Install.WantedBy = [ "xdg-desktop-autostart.target" ];
  };
}
