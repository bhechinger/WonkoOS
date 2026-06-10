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

  ardourDefaultRelink = pkgs.writeShellScript "ardour-default-relink" ''
    set -u

    pw_link="${pkgs.pipewire}/bin/pw-link"
    grep="${pkgs.gnugrep}/bin/grep"
    sleep="${pkgs.coreutils}/bin/sleep"

    has_output() {
      "$pw_link" -o | "$grep" -Fxq "$1"
    }

    has_input() {
      "$pw_link" -i | "$grep" -Fxq "$1"
    }

    wait_for_graph() {
      count=0
      while [ "$count" -lt 40 ]; do
        if has_output "ardour:Master/audio_out 1" \
          && has_input "alsa_output.firewire-0x00130e0401c04de0.multichannel-output:playback_FL" \
          && has_input "ardour:MIDI Control In"; then
          return 0
        fi
        count=$((count + 1))
        "$sleep" 0.5
      done
      return 0
    }

    link() {
      "$pw_link" "$1" "$2" 2>/dev/null || true
    }

    wait_for_graph

    link "System Sounds:monitor_FL" "ardour:System/audio_in 1"
    link "System Sounds:monitor_FR" "ardour:System/audio_in 2"
    link "Games:monitor_FL" "ardour:Games/audio_in 1"
    link "Games:monitor_FR" "ardour:Games/audio_in 2"
    link "Music:monitor_FL" "ardour:Music/audio_in 1"
    link "Music:monitor_FR" "ardour:Music/audio_in 2"

    link "alsa_input.firewire-0x00130e0401c04de0.multichannel-input:capture_AUX0" "ardour:Mic/audio_in 1"
    link "Midi-Bridge:nanoKONTROL2: _ CTRL (capture)" "ardour:MIDI Control In"

    link "ardour:Master/audio_out 1" "alsa_output.firewire-0x00130e0401c04de0.multichannel-output:playback_FL"
    link "ardour:Master/audio_out 2" "alsa_output.firewire-0x00130e0401c04de0.multichannel-output:playback_FR"
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
      ExecStartPost = "${ardourDefaultRelink}";
      KillSignal = "SIGINT";
      Restart = "on-failure";
      RestartSec = 5;
      SuccessExitStatus = "SIGINT";
      TimeoutStopSec = 120;
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
  };
}
