{ pkgs, ... }:
let
  refreshCookie = pkgs.writeShellScript "coolercontrol-refresh-cookie" ''
    set -eu

    password_path="/run/secrets/coolercontrol-admin-password"
    config_dir="$HOME/.config/org.coolercontrol.CoolerControl"
    config_file="$config_dir/CoolerControl.conf"
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
    expires="$(${pkgs.coreutils}/bin/date -u -d '+1 year' '+%a, %d-%b-%Y %H:%M:%S GMT')"

    mkdir -p "$config_dir"
    ${pkgs.python3}/bin/python3 - "$config_file" "$cookie" "$expires" <<'PY'
    import sys
    from pathlib import Path

    config_file = Path(sys.argv[1])
    cookie = sys.argv[2]
    expires = sys.argv[3]
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
    PY
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

  systemd.user.services.coolercontrol-refresh-cookie = {
    Unit = {
      Description = "Refresh CoolerControl GUI session cookie";
      After = [ "graphical-session.target" ];
    };

    Service = {
      Type = "oneshot";
      ExecStart = refreshCookie;
    };
  };

  systemd.user.services.coolercontrol = {
    Unit = {
      Description = "CoolerControl GUI";
      After = [
        "coolercontrol-refresh-cookie.service"
        "graphical-session.target"
      ];
      Requires = [ "coolercontrol-refresh-cookie.service" ];
    };

    Service = {
      ExecStart = "${pkgs.coolercontrol.coolercontrol-gui}/bin/coolercontrol";
      Restart = "on-failure";
      RestartSec = 5;
    };

    Install.WantedBy = [ "xdg-desktop-autostart.target" ];
  };
}
