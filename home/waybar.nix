{ pkgs, ... }:
let
  coolingStatus = pkgs.writeShellScript "waybar-cooling-status" ''
    cpu_uid="7febede677f5a27c6d57f4e861c5b2d0dfa83925bcb071314dc6132bf6fcfc16"
    gpu_uid="568337579da7d84e9da34a40400764635a1b25773ca66f11a4dcb7b2d03050fc"
    nct_uid="00a4da18625f56275c89e2fcd25a83c08c5ad3326452fa7e252fcc8a89c92493"

    read_hwmon_name() {
      if [ -r "$1/name" ]; then
        read -r name < "$1/name"
        printf '%s\n' "$name"
      fi
    }

    nct_hwmon=""
    for hwmon in /sys/class/hwmon/hwmon*; do
      [ "$(read_hwmon_name "$hwmon")" = "nct6798" ] || continue
      nct_hwmon="$hwmon"
      break
    done

    fan_pwm_percent() {
      pwm_path="$nct_hwmon/pwm$1"
      if [ -n "$nct_hwmon" ] && [ -r "$pwm_path" ]; then
        read -r pwm < "$pwm_path"
        printf '%s\n' "$(( (pwm * 100 + 127) / 255 ))"
      else
        printf '?\n'
      fi
    }

    cpu_temp="?"
    gpu_temp="?"
    fan2="?"
    fan5="?"
    fan7="?"

    cookie_dir="''${XDG_RUNTIME_DIR:-/tmp}"
    [ -w "$cookie_dir" ] || cookie_dir="/tmp"
    cookie_jar="$cookie_dir/waybar-coolercontrol-cookie"
    password_path="/run/secrets/coolercontrol-admin-password"
    coolercontrol_status="$(${pkgs.curl}/bin/curl -fsk -b "$cookie_jar" -X POST https://127.0.0.1:11987/status -H 'content-type: application/json' --data '{}' 2>/dev/null)"

    if ! printf '%s' "$coolercontrol_status" | ${pkgs.jq}/bin/jq -e '.devices' >/dev/null 2>&1 && [ -r "$password_path" ]; then
      coolercontrol_password="$(cat "$password_path")"
      auth_file="$(${pkgs.coreutils}/bin/mktemp "$cookie_dir/waybar-coolercontrol-auth.XXXXXX")"
      trap 'rm -f "$auth_file"' EXIT
      printf 'machine 127.0.0.1 login CCAdmin password %s\n' "$coolercontrol_password" > "$auth_file"
      chmod 600 "$auth_file"
      ${pkgs.curl}/bin/curl -fsk -c "$cookie_jar" --netrc-file "$auth_file" -X POST https://127.0.0.1:11987/login -H 'content-type: application/json' --data '{}' >/dev/null 2>&1
      coolercontrol_status="$(${pkgs.curl}/bin/curl -fsk -b "$cookie_jar" -X POST https://127.0.0.1:11987/status -H 'content-type: application/json' --data '{}' 2>/dev/null)"
    fi

    cc_value() {
      printf '%s' "$coolercontrol_status" | ${pkgs.jq}/bin/jq -er "$@" 2>/dev/null || printf '?\n'
    }

    if printf '%s' "$coolercontrol_status" | ${pkgs.jq}/bin/jq -e '.devices' >/dev/null 2>&1; then
      cpu_temp="$(cc_value --arg uid "$cpu_uid" '.devices[] | select(.uid == $uid) | .status_history[-1].temps[] | select(.name == "temp1") | ((.temp + 0.5) | floor)')"
      gpu_temp="$(cc_value --arg uid "$gpu_uid" '.devices[] | select(.uid == $uid) | .status_history[-1].temps[] | select(.name == "GPU Temp") | ((.temp + 0.5) | floor)')"
      fan2="$(cc_value --arg uid "$nct_uid" '.devices[] | select(.uid == $uid) | .status_history[-1].channels[] | select(.name == "fan2") | ((.duty + 0.5) | floor)')"
      fan5="$(cc_value --arg uid "$nct_uid" '.devices[] | select(.uid == $uid) | .status_history[-1].channels[] | select(.name == "fan5") | ((.duty + 0.5) | floor)')"
      fan7="$(cc_value --arg uid "$nct_uid" '.devices[] | select(.uid == $uid) | .status_history[-1].channels[] | select(.name == "fan7") | ((.duty + 0.5) | floor)')"
    fi

    if [ "$cpu_temp" = "?" ]; then
      for hwmon in /sys/class/hwmon/hwmon*; do
        [ "$(read_hwmon_name "$hwmon")" = "k10temp" ] || continue
        if [ -r "$hwmon/temp1_input" ]; then
          read -r raw_temp < "$hwmon/temp1_input"
          cpu_temp=$(( (raw_temp + 500) / 1000 ))
        fi
        break
      done
    fi

    [ "$fan2" != "?" ] || fan2="$(fan_pwm_percent 2)"
    [ "$fan5" != "?" ] || fan5="$(fan_pwm_percent 5)"
    [ "$fan7" != "?" ] || fan7="$(fan_pwm_percent 7)"

    fan_percent="$fan2"
    for fan in "$fan5" "$fan7"; do
      if [ "$fan_percent" = "?" ] || { [ "$fan" != "?" ] && [ "$fan" -gt "$fan_percent" ]; }; then
        fan_percent="$fan"
      fi
    done

    ${pkgs.jq}/bin/jq -cn \
      --arg text "CPU ''${cpu_temp}C GPU ''${gpu_temp}C FAN ''${fan_percent}%" \
      --arg tooltip "fan2: ''${fan2}%\nfan5: ''${fan5}%\nfan7: ''${fan7}%" \
      '{ text: $text, tooltip: $tooltip }'
  '';
in
{
  programs = {
    waybar = {
      enable = true;
      systemd = {
        enable = true;
        targets = [ "hyprland-session.target" ];
      };
      settings = {
        mainBar = {
          layer = "top";
          position = "top";
          height = 30;
          spacing = 4;
          output = [
            "Virtual-1"
            "DP-2"
          ];
          modules-left = [
            "custom/media"
          ];
          modules-right = [
            "idle_inhibitor"
            "pulseaudio"
            "cpu"
            "memory"
            "custom/cooling"
            "clock"
            "tray"
          ];

          keyboard-state = {
            numlock = true;
            capslock = true;
            format = "{name} {icon}";
            format-icons = {
              locked = "";
              unlocked = "";
            };
          };
          mpd = {
            format = "{stateIcon} {consumeIcon}{randomIcon}{repeatIcon}{singleIcon}{artist} - {album} - {title} ({elapsedTime:%M:%S}/{totalTime:%M:%S}) ⸨{songPosition}|{queueLength}⸩ {volume}% ";
            format-disconnected = "Disconnected ";
            format-stopped = "{consumeIcon}{randomIcon}{repeatIcon}{singleIcon}Stopped ";
            unknown-tag = "N/A";
            interval = 5;
            consume-icons = {
              on = " ";
            };
            random-icons = {
              off = "<span color=\"#f53c3c\"></span> ";
              on = " ";
            };
            repeat-icons = {
              on = " ";
            };
            single-icons = {
              on = "1 ";
            };
            state-icons = {
              paused = "";
              playing = "";
            };
            tooltip-format = "MPD (connected)";
            tooltip-format-disconnected = "MPD (disconnected)";
          };
          idle_inhibitor = {
            format = "{icon}";
            format-icons = {
              activated = "";
              deactivated = "";
            };
          };
          tray = {
            spacing = 10;
          };

          clock = {
            timezone = "Europe/Lisbon";
            format = "{:%Y-%m-%d %H:%M}";
            tooltip-format = "<big>{:%Y %B}</big>\n<tt><small>{calendar}</small></tt>";
            format-alt = "{:%Y-%m-%d}";
          };

          cpu = {
            format = "{usage}% ";
            tooltip = false;
          };

          memory = {
            format = "{}% ";
          };

          "custom/cooling" = {
            exec = coolingStatus;
            interval = 5;
            return-type = "json";
            tooltip = true;
          };

          temperature = {
            critical-threshold = 80;
            format = "{temperatureC}°C {icon}";
            format-icons = [
              ""
              ""
              ""
            ];
          };

          backlight = {
            format = "{percent}% {icon}";
            format-icons = [
              ""
              ""
              ""
              ""
              ""
              ""
              ""
              ""
              ""
            ];
          };

          battery = {
            states = {
              warning = 30;
              critical = 15;
            };
            format = "{capacity}% {icon}";
            format-full = "{capacity}% {icon}";
            format-charging = "{capacity}% ";
            format-plugged = "{capacity}% ";
            format-alt = "{time} {icon}";
            format-icons = [
              ""
              ""
              ""
              ""
              ""
            ];
          };

          pulseaudio = {
            format = "{volume}% {icon} {format_source}";
            format-bluetooth = "{volume}% {icon} {format_source}";
            format-bluetooth-muted = " {icon} {format_source}";
            format-muted = " {format_source}";
            format-source = "{volume}% ";
            format-source-muted = "";
            format-icons = {
              headphone = "";
              hands-free = "";
              headset = "";
              phone = "";
              portable = "";
              car = "";
              default = [
                ""
                ""
                ""
              ];
            };
            on-click = "pavucontrol";
          };

          "custom/media" = {
            format = " {}";
            escape = true;
            exec = "${pkgs.playerctl}/bin/playerctl --player=spotify metadata --format '{{artist}} - {{title}}'";
            exec-if = "${pkgs.playerctl}/bin/playerctl --player=spotify status";
            interval = 5;
            max-length = 60;
            tooltip = false;
            on-click = "${pkgs.playerctl}/bin/playerctl --player=spotify play-pause";
            on-click-right = "${pkgs.playerctl}/bin/playerctl --player=spotify next";
          };

        };
      };
    };
  };
}
