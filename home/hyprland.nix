{
  hyprlandFix,
  lib,
  pkgs,
  unstable-pkgs,
  ...
}:
let
  browser = "firefox";
  hyprlandFixReleaseCheck = pkgs.writeShellApplication {
    name = "hyprland-fix-release-check";
    text = ''
      release_json="$(${lib.getExe pkgs.curl} --fail --silent --show-error --location --retry 3 \
        https://api.github.com/repos/hyprwm/Hyprland/releases/latest)"
      release="$(printf '%s' "$release_json" | ${lib.getExe pkgs.jq} --exit-status --raw-output .tag_name)"
      tmp="$(${lib.getExe' pkgs.coreutils "mktemp"} -d)"
      trap '${lib.getExe' pkgs.coreutils "rm"} -rf "$tmp"' EXIT

      ${lib.getExe' pkgs.coreutils "mkdir"} -p "$tmp/source/src/output"
      ${lib.getExe pkgs.curl} --fail --silent --show-error --location --retry 3 \
        --output "$tmp/source/src/output/Monitor.cpp" \
        "https://raw.githubusercontent.com/hyprwm/Hyprland/$release/src/output/Monitor.cpp"
      ${lib.getExe pkgs.curl} --fail --silent --show-error --location --retry 3 \
        --output "$tmp/fix.patch" \
        "https://github.com/hyprwm/Hyprland/commit/${hyprlandFix}.patch"

      if ${lib.getExe pkgs.git} -C "$tmp/source" apply --reverse --check \
        --include=src/output/Monitor.cpp "$tmp/fix.patch" >/dev/null 2>&1; then
        message="Hyprland $release contains ${hyprlandFix}; update unstable-nixpkgs and verify its unpatched package before removing the temporary override and release check."
        printf '%s\n' "$message"
        ${lib.getExe pkgs.libnotify} "Hyprland fix released" "$message" || true
      fi
    '';
  };
  terminal = "kitty";
  telegram = lib.getExe pkgs.telegram-desktop;
  luaInline = lib.generators.mkLuaInline;
  toLua = lib.generators.toLua { };
  bind = key: dispatcher: {
    _args = [
      key
      (luaInline dispatcher)
    ];
  };
  mouseBind = key: dispatcher: {
    _args = [
      key
      (luaInline dispatcher)
      { mouse = true; }
    ];
  };
  main = key: luaInline ''mainMod .. " + ${key}"'';
  curve = name: points: {
    _args = [
      name
      {
        type = "bezier";
        inherit points;
      }
    ];
  };
  animation =
    leaf: enabled: speed: bezier: style:
    {
      inherit
        leaf
        enabled
        speed
        bezier
        ;
    }
    // lib.optionalAttrs (style != null) { inherit style; };
  workspaceWindowRule = class: workspace: {
    match.class = class;
    inherit workspace;
  };
  dimLayer = namespace: {
    match.namespace = namespace;
    dim_around = true;
  };
  noGaps = workspace: {
    inherit workspace;
    gaps_out = 0;
    gaps_in = 0;
  };
  autostart = [
    { command = "hyprctl setcursor Bibata-Modern-Ice 24"; }
    {
      command = browser;
      rules.workspace = "1 silent";
    }
    {
      command = terminal;
      rules.workspace = "3 silent";
    }
    {
      command = "slack";
      rules.workspace = "special:chat silent";
    }
    {
      command = "discord";
      rules.workspace = "special:chat silent";
    }
    {
      command = ''sed -i 's/^windowTheme=.*/windowTheme=dark/' "$HOME/.config/org.keshavnrj.ubuntu/WhatSie.conf"; exec whatsie'';
      rules.workspace = "special:chat silent";
    }
    {
      command = "irccloud";
      rules.workspace = "special:chat silent";
    }
    {
      command = "signal-desktop";
      rules.workspace = "special:chat2 silent";
    }
    {
      command = telegram;
      rules.workspace = "special:chat2 silent";
    }
    {
      command = "qpwgraph -d";
      rules.workspace = "special:audio silent";
    }
  ];
  renderAutostart =
    {
      command,
      rules ? null,
    }:
    "  hl.exec_cmd(${toLua command}${lib.optionalString (rules != null) ", ${toLua rules}"})\n";
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
  systemd.user.services.hyprland-fix-release-check = {
    Unit.Description = "Check whether Hyprland has released the orphaned-workspace fix";
    Service = {
      Type = "oneshot";
      ExecStart = lib.getExe hyprlandFixReleaseCheck;
    };
  };
  systemd.user.timers.hyprland-fix-release-check = {
    Unit.Description = "Weekly Hyprland orphaned-workspace fix release check";
    Timer = {
      OnCalendar = "Sun *-*-* 12:00:00";
      Persistent = true;
      RandomizedDelaySec = "1h";
    };
    Install.WantedBy = [ "timers.target" ];
  };

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

  wayland.windowManager.hyprland = {
    enable = true;
    configType = "lua";
    package = null;
    portalPackage = null;

    xwayland.enable = true;
    systemd.enable = true;
    settings = {
      mainMod._var = "SUPER";
      terminal._var = terminal;
      fileManager._var = "dolphin";
      menu._var = "wofi --show drun";

      config = {
        debug.disable_logs = false;
        input = {
          kb_layout = "us";
          kb_options = "ctrl:nocaps";
          numlock_by_default = true;
          repeat_delay = 300;
          follow_mouse = 1;
          float_switch_override_focus = 0;
          mouse_refocus = false;
          sensitivity = 0;
          touchpad.natural_scroll = false;
        };
        general = {
          layout = "dwindle";
          gaps_in = 0;
          gaps_out = 2;
          border_size = 2;
          col = {
            active_border = {
              colors = [
                "rgb(98971A)"
                "rgb(CC241D)"
              ];
              angle = 45;
            };
            inactive_border = "rgba(00000000)";
          };
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
          preserve_split = true;
        };
        master = {
          new_status = "master";
          special_scale_factor = 1;
        };
        decoration = {
          rounding = 0;
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
            offset = [
              0
              2
            ];
            range = 20;
            render_power = 3;
            color = "rgba(00000055)";
          };
        };
        animations.enabled = true;
        binds = {
          movefocus_cycles_fullscreen = true;
          allow_workspace_cycles = true;
        };
        xwayland.force_zero_scaling = true;
      };

      curve = [
        (curve "fluent_decel" [
          [
            0
            0.2
          ]
          [
            0.4
            1
          ]
        ])
        (curve "easeOutCirc" [
          [
            0
            0.55
          ]
          [
            0.45
            1
          ]
        ])
        (curve "easeOutCubic" [
          [
            0.33
            1
          ]
          [
            0.68
            1
          ]
        ])
        (curve "fade_curve" [
          [
            0
            0.55
          ]
          [
            0.45
            1
          ]
        ])
      ];

      animation = [
        (animation "windowsIn" false 4 "easeOutCubic" "popin 20%")
        (animation "windowsOut" false 4 "fluent_decel" "popin 80%")
        (animation "windowsMove" true 2 "fluent_decel" "slide")
        (animation "fadeIn" true 3 "fade_curve" null)
        (animation "fadeOut" true 3 "fade_curve" null)
        (animation "fadeSwitch" false 1 "easeOutCirc" null)
        (animation "fadeShadow" true 10 "easeOutCirc" null)
        (animation "fadeDim" true 4 "fluent_decel" null)
        (animation "workspaces" true 4 "easeOutCubic" "fade")
      ];

      bind = [
        (bind "SUPER + Tab" ''hl.dsp.focus({ workspace = "previous" })'')
        (bind (main "Return") "hl.dsp.exec_cmd(terminal)")
        (bind (main "Q") "hl.dsp.window.close()")
        (bind (main "E") "hl.dsp.exec_cmd(fileManager)")
        (bind (main "V") ''hl.dsp.window.float({ action = "toggle" })'')
        (bind (main "Space") "hl.dsp.exec_cmd(menu)")
        (bind (main "P") "hl.dsp.window.pseudo()")
        (bind (main "J") ''hl.dsp.layout("togglesplit")'')
        (bind (main "l") ''hl.dsp.exec_cmd("lock-screen")'')
        (bind (main "F") "hl.dsp.window.fullscreen()")
        (bind (main "left") ''hl.dsp.focus({ direction = "left" })'')
        (bind (main "right") ''hl.dsp.focus({ direction = "right" })'')
        (bind (main "up") ''hl.dsp.focus({ direction = "up" })'')
        (bind (main "down") ''hl.dsp.focus({ direction = "down" })'')
        (bind (main "CTRL + left") ''hl.dsp.focus({ workspace = "-1" })'')
        (bind (main "CTRL + right") ''hl.dsp.focus({ workspace = "+1" })'')
        (bind (main "CTRL + SHIFT + left") ''hl.dsp.window.move({ workspace = "-1" })'')
        (bind (main "CTRL + SHIFT + right") ''hl.dsp.window.move({ workspace = "+1" })'')
        (bind (main "SHIFT + left") ''hl.dsp.window.move({ direction = "left" })'')
        (bind (main "SHIFT + right") ''hl.dsp.window.move({ direction = "right" })'')
        (bind (main "SHIFT + up") ''hl.dsp.window.move({ direction = "up" })'')
        (bind (main "SHIFT + down") ''hl.dsp.window.move({ direction = "down" })'')
        (bind (main "Z") ''hl.dsp.workspace.toggle_special("chat")'')
        (bind (main "A") ''hl.dsp.workspace.toggle_special("chat2")'')
        (bind (main "X") ''hl.dsp.workspace.toggle_special("audio")'')
        (bind (main "G") ''hl.dsp.workspace.toggle_special("games")'')
        (bind (main "PRINT") ''hl.dsp.exec_cmd("hyprshot -m window")'')
        (bind "PRINT" ''hl.dsp.exec_cmd("hyprshot -m output")'')
        (bind "SHIFT + PRINT" ''hl.dsp.exec_cmd("hyprshot -m region")'')
        (bind (main "mouse_down") ''hl.dsp.focus({ workspace = "e+1" })'')
        (bind (main "mouse_up") ''hl.dsp.focus({ workspace = "e-1" })'')
        (mouseBind (main "mouse:272") "hl.dsp.window.drag()")
        (mouseBind (main "mouse:273") "hl.dsp.window.resize()")
      ];

      window_rule = [
        (workspaceWindowRule "Slack" "special:chat")
        (workspaceWindowRule "discord" "special:chat")
        (workspaceWindowRule "com.ktechpit.whatsie" "special:chat")
        (workspaceWindowRule "IRCCloud" "special:chat")
        (workspaceWindowRule "thunderbird" "special:chat2 silent")
        (workspaceWindowRule "Signal" "special:chat2")
        (workspaceWindowRule "org.telegram.desktop" "special:chat2")
        (workspaceWindowRule "Ardour" "special:audio")
        (workspaceWindowRule "org.rncbc.qpwgraph" "special:audio")
        (workspaceWindowRule "steam" "special:games")
        {
          match.class = "steam";
          suppress_event = "activate";
        }
        (workspaceWindowRule "r2modman" "special:games")
        {
          match.class = ".*";
          suppress_event = "maximize";
        }
        {
          match = {
            class = "^$";
            title = "^$";
            xwayland = true;
            float = true;
            fullscreen = false;
            pin = false;
          };
          no_focus = true;
        }
      ];

      layer_rule = [
        (dimLayer "vicinae")
        (dimLayer "rofi")
        (dimLayer "swaync-control-center")
      ];

      workspace_rule = [
        (noGaps "w[t1]")
        (noGaps "w[tg1]")
        (noGaps "f[1]")
      ];

      monitor = [
        {
          output = "";
          mode = "preferred";
          position = "auto";
          scale = "auto";
        }
        {
          output = "Virtual-1";
          mode = "1920x1080@60";
          position = "0x0";
          scale = 1;
        }
      ];
    };

    extraConfig = ''
      for workspace = 1, 10 do
        local key = workspace % 10
        hl.bind(mainMod .. " + " .. key, hl.dsp.focus({ workspace = workspace }))
        hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = workspace }))
      end

      hl.on("hyprland.start", function()
      ${lib.concatMapStrings renderAutostart autostart}end)
    '';
  };
}
