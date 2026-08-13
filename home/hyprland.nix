{
  lib,
  pkgs,
  unstable-pkgs,
  ...
}:
let
  browser = "firefox";
  terminal = "kitty";
  telegram = lib.getExe pkgs.telegram-desktop;
in
{
  home.packages = with pkgs; [
    kdePackages.ark
    kdePackages.gwenview
    libreoffice-qt
  ];

  systemd.user.targets.hyprland-session.Unit.Wants = [
    "xdg-desktop-autostart.target"
  ];
  systemd.user.targets.hyprland-session.Unit.Before = [
    "xdg-desktop-autostart.target"
  ];

  xdg = {
    configFile."mimeapps.list".force = true;
    configFile."menus/applications.menu".text = ''
      <!DOCTYPE Menu PUBLIC "-//freedesktop//DTD Menu 1.0//EN"
        "http://www.freedesktop.org/standards/menu-spec/menu-1.0.dtd">
      <Menu>
        <Name>Applications</Name>
        <DefaultAppDirs/>
        <DefaultDirectoryDirs/>
        <DefaultMergeDirs/>
        <Include>
          <All/>
        </Include>
      </Menu>
    '';
    mimeApps = {
      enable = true;
      defaultApplications = {
        "application/x-krita" = "org.kde.krita.desktop";
        "image/x-xcf" = "gimp.desktop";
        "inode/directory" = "org.kde.dolphin.desktop";
        "text/plain" = "dev.zed.Zed.desktop";
        "x-scheme-handler/jetbrains" = "jetbrains-toolbox.desktop";
        "x-scheme-handler/jetbrains-gateway" = "jetbrains-gateway.desktop";
      };
      defaultApplicationPackages = with pkgs; [
        kdePackages.gwenview
        evince
        kdePackages.ark
        libreoffice-qt
        audacious
        vlc
        firefox
        unstable-pkgs.zed-editor
        thunderbird
        telegram-desktop
        signal-desktop
        slack
        heroic
        r2modman
        gimp
        inkscape
        krita
      ];
    };
  };

  wayland.windowManager.hyprland.configType = "hyprlang";
  wayland.windowManager.hyprland = {
    enable = true;
    package = null;
    portalPackage = null;

    xwayland = {
      enable = true;
      # hidpi = true;
    };
    systemd.enable = true;
    settings = {
      "debug:disable_logs" = false;
      "$mainMod" = "SUPER";
      "$shiftMod" = "SHIFT";
      "$fileManager" = "dolphin";
      "$menu" = "wofi --show drun";

      # autostart
      exec-once = [
        #"wl-paste --watch cliphist store &"
        #"swaync &"
        #"vicinae server &"
        "hyprctl setcursor Bibata-Modern-Ice 24 &"

        # "${terminal} --gtk-single-instance=true --quit-after-last-window-closed=false --initial-window=false"
        "[workspace 1 silent] ${browser}"
        "[workspace 3 silent] ${terminal}"

        "[workspace special:chat silent] slack"
        "[workspace special:chat silent] discord"
        "[workspace special:chat silent] sed -i 's/^windowTheme=.*/windowTheme=dark/' \"$HOME/.config/org.keshavnrj.ubuntu/WhatSie.conf\"; exec whatsie"
        "[workspace special:chat silent] irccloud"
        #"[workspace special:chat silent] kitty --class irssi -T irssi irssi"

        #"[workspace special:chat2 silent] thunderbird"
        "[workspace special:chat2 silent] signal-desktop"
        "[workspace special:chat2 silent] ${telegram}"

        "[workspace special:audio silent] qpwgraph -d"

        #"[workspace special:games silent] steam"
        #"[workspace special:games silent] r2modman"
      ];

      input = {
        kb_layout = "us";
        kb_options = "ctrl:nocaps";
        numlock_by_default = true;
        repeat_delay = 300;
        follow_mouse = 1;
        float_switch_override_focus = 0;
        mouse_refocus = 0;
        sensitivity = 0;
        touchpad = {
          natural_scroll = false;
        };
      };

      general = {
        layout = "dwindle";
        gaps_in = 0;
        gaps_out = 2;
        border_size = 2;
        "col.active_border" = "rgb(98971A) rgb(CC241D) 45deg";
        "col.inactive_border" = "0x00000000";
        # border_part_of_window = false;
      };

      misc = {
        disable_autoreload = true;
        disable_hyprland_logo = true;
        always_follow_on_dnd = true;
        layers_hog_keyboard_focus = true;
        animate_manual_resizes = false;
        enable_swallow = true;
        focus_on_activate = true;
        middle_click_paste = false;
      };

      dwindle = {
        force_split = 2;
        special_scale_factor = 1.0;
        split_width_multiplier = 1.0;
        use_active_for_splits = true;
        preserve_split = "yes";
      };

      master = {
        new_status = "master";
        special_scale_factor = 1;
      };

      decoration = {
        rounding = 0;
        # active_opacity = 0.90;
        # inactive_opacity = 0.90;
        # fullscreen_opacity = 1.0;

        blur = {
          enabled = true;
          size = 3;
          passes = 2;
          brightness = 1;
          contrast = 1.4;
          ignore_opacity = true;
          noise = 0;
          new_optimizations = true;
          xray = true;
        };

        shadow = {
          enabled = true;

          offset = "0 2";
          range = 20;
          render_power = 3;
          color = "rgba(00000055)";
        };
      };

      animations = {
        enabled = true;

        bezier = [
          "fluent_decel, 0, 0.2, 0.4, 1"
          "easeOutCirc, 0, 0.55, 0.45, 1"
          "easeOutCubic, 0.33, 1, 0.68, 1"
          "fade_curve, 0, 0.55, 0.45, 1"
        ];

        animation = [
          # name, enable, speed, curve, style

          # Windows
          "windowsIn,   0, 4, easeOutCubic,  popin 20%" # window open
          "windowsOut,  0, 4, fluent_decel,  popin 80%" # window close.
          "windowsMove, 1, 2, fluent_decel, slide" # everything in between, moving, dragging, resizing.

          # Fade
          "fadeIn,      1, 3,   fade_curve" # fade in (open) -> layers and windows
          "fadeOut,     1, 3,   fade_curve" # fade out (close) -> layers and windows
          "fadeSwitch,  0, 1,   easeOutCirc" # fade on changing activewindow and its opacity
          "fadeShadow,  1, 10,  easeOutCirc" # fade on changing activewindow for shadows
          "fadeDim,     1, 4,   fluent_decel" # the easing of the dimming of inactive windows
          # "border,      1, 2.7, easeOutCirc"  # for animating the border's color switch speed
          # "borderangle, 1, 30,  fluent_decel, once" # for animating the border's gradient angle - styles: once (default), loop
          "workspaces,  1, 4,   easeOutCubic, fade" # styles: slide, slidevert, fade, slidefade, slidefadevert
        ];
      };

      binds = {
        movefocus_cycles_fullscreen = true;
        allow_workspace_cycles = true;
      };

      bind = [
        # keybindings
        "SUPER, Tab, workspace, previous"
        "$mainMod, Return, exec, ${terminal}"
        "$mainMod, Q, killactive,"
        #"$mainMod, M, exit," # This is dangerous, so no.
        "$mainMod, E, exec, $fileManager"
        "$mainMod, V, togglefloating,"
        "$mainMod, Space, exec, $menu"
        "$mainMod, P, pseudo, # dwindle"
        "$mainMod, J, layoutmsg, togglesplit # dwindle"
        "$mainMod, l, exec, lock-screen"
        "$mainMod, F, fullscreen"
        "$mainMod, left, movefocus, l"
        "$mainMod, right, movefocus, r"
        "$mainMod, up, movefocus, u"
        "$mainMod, down, movefocus, d"
        "$mainMod, 1, workspace, 1"
        "$mainMod, 2, workspace, 2"
        "$mainMod, 3, workspace, 3"
        "$mainMod, 4, workspace, 4"
        "$mainMod, 5, workspace, 5"
        "$mainMod, 6, workspace, 6"
        "$mainMod, 7, workspace, 7"
        "$mainMod, 8, workspace, 8"
        "$mainMod, 9, workspace, 9"
        "$mainMod, 0, workspace, 10"
        "$mainMod CTRL, left, workspace, -1"
        "$mainMod CTRL, right, workspace, +1"
        "$mainMod CTRL SHIFT, left, movetoworkspace, -1"
        "$mainMod CTRL SHIFT, right, movetoworkspace, +1"
        "$mainMod SHIFT, left, movewindow, l"
        "$mainMod SHIFT, right, movewindow, r"
        "$mainMod SHIFT, up, movewindow, u"
        "$mainMod SHIFT, down, movewindow, d"
        "$mainMod SHIFT, 1, movetoworkspace, 1"
        "$mainMod SHIFT, 2, movetoworkspace, 2"
        "$mainMod SHIFT, 3, movetoworkspace, 3"
        "$mainMod SHIFT, 4, movetoworkspace, 4"
        "$mainMod SHIFT, 5, movetoworkspace, 5"
        "$mainMod SHIFT, 6, movetoworkspace, 6"
        "$mainMod SHIFT, 7, movetoworkspace, 7"
        "$mainMod SHIFT, 8, movetoworkspace, 8"
        "$mainMod SHIFT, 9, movetoworkspace, 9"
        "$mainMod SHIFT, 0, movetoworkspace, 10"
        "$mainMod, Z, togglespecialworkspace, chat"
        "$mainMod, A, togglespecialworkspace, chat2"
        "$mainMod, X, togglespecialworkspace, audio"
        "$mainMod, G, togglespecialworkspace, games"
        "$mainMod, PRINT, exec, hyprshot -m window"
        ", PRINT, exec, hyprshot -m output"
        "$shiftMod, PRINT, exec, hyprshot -m region"
        "$mainMod, mouse_down, workspace, e+1"
        "$mainMod, mouse_up, workspace, e-1"
      ];

      # mouse binding
      bindm = [
        "$mainMod, mouse:272, movewindow"
        "$mainMod, mouse:273, resizewindow"
      ];

      # windowrule
      windowrule = [
        "workspace special:chat, match:class Slack"
        "workspace special:chat, match:class discord"
        "workspace special:chat, match:class com.ktechpit.whatsie"
        "workspace special:chat, match:class IRCCloud"
        "workspace special:chat2 silent, match:class thunderbird"
        "workspace special:chat2, match:class Signal"
        "workspace special:chat2, match:class org.telegram.desktop"
        "workspace special:audio, match:class Ardour"
        "workspace special:audio, match:class org.rncbc.qpwgraph"
        "workspace special:games, match:class steam"
        "suppress_event activate, match:class steam"
        "workspace special:games, match:class r2modman"
        "suppress_event maximize, match:class .*"
        "no_focus on, match:class ^$, match:title ^$, match:xwayland 1, match:float 1, match:fullscreen 0, match:pin 0"

      ];

      layerrule = [
        "dim_around on, match:namespace vicinae"
        "dim_around on, match:namespace rofi"
        "dim_around on, match:namespace swaync-control-center"
      ];

      # No gaps when only
      workspace = [
        "w[t1], gapsout:0, gapsin:0"
        "w[tg1], gapsout:0, gapsin:0"
        "f[1], gapsout:0, gapsin:0"
      ];

      monitor = [
        "=,preferred,auto,auto"
        "Virtual-1,1920x1080@60,0x0,1"
      ];

      xwayland = {
        force_zero_scaling = true;
      };
    };
  };
}
