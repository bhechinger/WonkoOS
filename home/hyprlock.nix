{ pkgs, unstable-pkgs, ... }:
let
  lockScreen = pkgs.writeShellScriptBin "lock-screen" ''
    if pgrep -x hyprlock >/dev/null; then
      exit 0
    fi

    exec hyprlock
  '';
in
{
  home.packages = [ lockScreen ];

  services.hypridle = {
    enable = true;
    package = unstable-pkgs.hypridle;
    systemdTarget = "hyprland-session.target";
    settings = {
      general = {
        after_sleep_cmd = "hyprctl dispatch dpms on";
        before_sleep_cmd = "${lockScreen}/bin/lock-screen";
        ignore_dbus_inhibit = false;
        lock_cmd = "${lockScreen}/bin/lock-screen";
      };

      listener = [
        {
          timeout = 600;
          on-timeout = "pgrep -x hyprlock >/dev/null && hyprctl dispatch dpms off";
          on-resume = "hyprctl dispatch dpms on";
        }
        {
          timeout = 1200;
          on-timeout = "${lockScreen}/bin/lock-screen";
        }
        {
          timeout = 1800;
          on-timeout = "hyprctl dispatch dpms off";
          on-resume = "hyprctl dispatch dpms on";
        }
      ];
    };
  };

  programs = {
    hyprlock = {
      enable = true;
      package = unstable-pkgs.hyprlock;
      settings = {
        general = {
          hide_cursor = true;
          ignore_empty_input = true;
        };

        animations = {
          enabled = true;
          fade_in = {
            duration = 300;
            bezier = "easeOutQuint";
          };
          fade_out = {
            duration = 300;
            bezier = "easeOutQuint";
          };
        };

        background = [
          {
            path = "screenshot";
            blur_passes = 3;
            blur_size = 8;
          }
        ];

        input-field = [
          {
            size = "200, 50";
            position = "0, -80";
            monitor = "";
            dots_center = true;
            fade_on_empty = false;
            font_color = "rgb(202, 211, 245)";
            inner_color = "rgb(91, 96, 120)";
            outer_color = "rgb(24, 25, 38)";
            outline_thickness = 5;
            placeholder_text = "'<span foreground=\"##cad3f5\">Password...</span>'";
            shadow_passes = 2;
          }
        ];
      };
    };
  };
}
