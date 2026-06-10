{ pkgs, ... }:
let
  ardourPipewire = pkgs.symlinkJoin {
    name = "ardour-pipewire";
    paths = [ pkgs.ardour ];
    buildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/ardour9 \
        --prefix LD_LIBRARY_PATH : ${pkgs.pipewire.jack}/lib
    '';
  };

  ardourRelink = pkgs.writeShellScript "ardour-relink" ''
    set -u

    pw_link=${pkgs.pipewire}/bin/pw-link

    link() {
      "$pw_link" "$1" "$2" 2>/dev/null || true
    }

    unlink() {
      "$pw_link" -d "$1" "$2" 2>/dev/null || true
    }

    while true; do
      link "System Sounds:monitor_FL" "ardour:System/audio_in 1"
      link "System Sounds:monitor_FR" "ardour:System/audio_in 2"
      link "Games:monitor_FL" "ardour:Games/audio_in 1"
      link "Games:monitor_FR" "ardour:Games/audio_in 2"
      link "Music:monitor_FL" "ardour:Music/audio_in 1"
      link "Music:monitor_FR" "ardour:Music/audio_in 2"
      link "alsa_input.firewire-0x00130e0401c04de0.multichannel-input:capture_AUX0" "ardour:Mic/audio_in 1"
      link "Midi-Bridge:nanoKONTROL2: _ CTRL (capture)" "ardour:MIDI Control In"
      link "Midi-Bridge:nanoKONTROL2: _ CTRL (capture)" "spotify-midi-control:input_1"
      link "ardour:Master/audio_out 1" "alsa_output.firewire-0x00130e0401c04de0.multichannel-output:playback_FL"
      link "ardour:Master/audio_out 2" "alsa_output.firewire-0x00130e0401c04de0.multichannel-output:playback_FR"

      link "Firefox:output_FL" "ardour:System/audio_in 1"
      link "Firefox:output_FR" "ardour:System/audio_in 2"
      unlink "Firefox:output_FL" "System Sounds:playback_FL"
      unlink "Firefox:output_FR" "System Sounds:playback_FR"

      link "spotify:output_FL" "ardour:Music/audio_in 1"
      link "spotify:output_FR" "ardour:Music/audio_in 2"
      unlink "spotify:output_FL" "Music:playback_FL"
      unlink "spotify:output_FR" "Music:playback_FR"

      sleep 2
    done
  '';

  battletechGamesRule = ''
    stream.rules = [
      {
        matches = [
          {
            application.name = "BattleTech"
            media.class = "Stream/Output/Audio"
          }
          {
            node.name = "BattleTech"
            media.class = "Stream/Output/Audio"
          }
          {
            application.process.binary = "BattleTech"
            media.class = "Stream/Output/Audio"
          }
        ]
        actions = {
          update-props = {
            target.object = "Games"
            node.dont-move = true
            state.restore-target = false
          }
        }
      }
    ]
  '';

  saffireClockRule = ''
    monitor.alsa.rules = [
      {
        matches = [
          {
            node.name = "alsa_output.firewire-0x00130e0401c04de0.multichannel-output"
          }
        ]
        actions = {
          update-props = {
            priority.driver = 3000
            priority.session = 3000
          }
        }
      }
      {
        matches = [
          {
            node.name = "alsa_input.firewire-0x00130e0401c04de0.multichannel-input"
          }
          {
            node.name = "alsa_input.usb-HD_Web_Camera_HD_Web_Camera_Ucamera001-02.mono-fallback"
          }
        ]
        actions = {
          update-props = {
            priority.driver = 100
          }
        }
      }
    ]
  '';

in
{
  home.packages = with pkgs; [
    carla
    qpwgraph
    ardourPipewire
    pipewire.jack
    rnnoise-plugin.lv2
    lmms
    lsp-plugins
    show-midi
    audacious
    pavucontrol
    spotify
  ];
  xdg.configFile."autostart/org.rncbc.qpwgraph.desktop" = {
    force = true;
    text = ''
      [Desktop Entry]
      Categories=AudioVideo;Audio;Video;Midi;X-Alsa;X-PipeWire;Qt;
      Comment=qpwgraph is a PipeWire graph Qt GUI interface
      Exec=qpwgraph -d -m
      GenericName=PipeWire Graph Viewer
      Icon=org.rncbc.qpwgraph
      Keywords=PipeWire;MIDI;ALSA;JACK;Qt;
      Name=qpwgraph
      StartupNotify=true
      Terminal=false
      Type=Application
      Version=1.0
    '';
  };

  xdg.desktopEntries."org.rncbc.qpwgraph" = {
    name = "qpwgraph";
    genericName = "PipeWire Graph Viewer";
    comment = "qpwgraph is a PipeWire graph Qt GUI interface";
    exec = "qpwgraph -d";
    icon = "org.rncbc.qpwgraph";
    terminal = false;
    startupNotify = true;
    categories = [
      "AudioVideo"
      "Audio"
      "Video"
      "Midi"
      "X-Alsa"
      "X-PipeWire"
      "Qt"
    ];
    settings = {
      Keywords = "PipeWire;MIDI;ALSA;JACK;Qt;";
    };
  };

  systemd.user.services.ardour-default = {
    Unit = {
      Description = "Ardour Default session";
      Wants = [
        "pipewire.service"
        "wireplumber.service"
      ];
      After = [
        "pipewire.service"
        "wireplumber.service"
      ];
      PartOf = [
        "hyprland-session.target"
        "pipewire.service"
        "wireplumber.service"
      ];
    };

    Service = {
      ExecStartPre = "${pkgs.coreutils}/bin/sleep 5";
      ExecStart = "${ardourPipewire}/bin/ardour9 /home/wonko/Default";
      KillSignal = "SIGINT";
      Restart = "on-failure";
      RestartSec = 5;
      SuccessExitStatus = "SIGINT";
      TimeoutStopSec = 120;
    };

    Install.WantedBy = [ "hyprland-session.target" ];
  };

  systemd.user.services.ardour-relink = {
    Unit = {
      Description = "Keep Ardour's default PipeWire links in place";
      Wants = [
        "pipewire.service"
        "wireplumber.service"
        "ardour-default.service"
      ];
      After = [
        "pipewire.service"
        "wireplumber.service"
        "ardour-default.service"
      ];
      PartOf = [
        "hyprland-session.target"
        "pipewire.service"
        "wireplumber.service"
      ];
    };

    Service = {
      ExecStart = "${ardourRelink}";
      Restart = "always";
      RestartSec = 1;
    };

    Install.WantedBy = [ "hyprland-session.target" ];
  };

  xdg.configFile."pipewire/pipewire.conf.d/10-null-sink.conf" = {
    force = true;
    text = ''
      context.objects = [
          {   factory = adapter
              args = {
                 factory.name     = support.null-audio-sink
                 node.name        = "System Sounds"
                 node.description = "System Sounds"
                 media.class      = Audio/Sink
                 object.linger    = true
                 audio.position   = [ FL FR ]
                 monitor.channel-volumes = true
              }
          }
          {   factory = adapter
              args = {
                 factory.name     = support.null-audio-sink
                 node.name        = "Games"
                 node.description = "Games"
                 media.class      = Audio/Sink
                 object.linger    = true
                 audio.position   = [ FL FR ]
                 monitor.channel-volumes = true
              }
          }
          {   factory = adapter
              args = {
                 factory.name     = support.null-audio-sink
                 node.name        = "Music"
                 node.description = "Music"
                 media.class      = Audio/Sink
                 object.linger    = true
                 audio.position   = [ FL FR ]
                 monitor.channel-volumes = true
              }
          }
      ]
    '';
  };

  xdg.configFile."pipewire/pipewire.conf.d/11-null-source.conf" = {
    force = true;
    text = ''
      context.objects = [
          {   factory = adapter
              args = {
                 factory.name     = support.null-audio-sink
                 node.name        = "Ardour"
                 node.description = "Ardour"
                 media.class      = Audio/Source/Virtual
                 object.linger    = true
                 audio.position   = [ FL FR ]
                 monitor.channel-volumes = true
              }
          }
      ]
    '';
  };

  xdg.configFile."wireplumber/wireplumber.conf.d/51-saffire-clock.conf".text = saffireClockRule;

  # I don't know why all three of these are required, but it doesn't work without them.
  xdg.configFile."pipewire/client.conf.d/52-battletech-games.conf".text = battletechGamesRule;
  xdg.configFile."pipewire/pipewire-pulse.conf.d/52-battletech-games.conf".text = battletechGamesRule;
  xdg.configFile."wireplumber/wireplumber.conf.d/52-battletech-games.conf".text = battletechGamesRule;

  services = {
    spotifyd = {
      enable = true;
      settings = {
        global = {
          bitrate = 320;
          username = "";
          password = "";
          backend = "pulseaudio";
          device = "pipewire";
          control = "pipewire";
          device_type = "computer";
          device_name = "deepthought";
        };
      };
    };
    spotify-midi-control = {
      enable = true;
      backend = "pipewire";

      midiCommands = {
        play = [
          176
          41
          127
        ];
        pause = [
          176
          42
          127
        ];
        previous = [
          176
          58
          127
        ];
        next = [
          176
          59
          127
        ];
      };
    };
  };
}
