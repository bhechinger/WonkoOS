{
  config,
  lib,
  pkgs,
  ...
}:
let
  audioPipewire = pkgs.pipewire;
  jack2 = pkgs.jack2;
  saffireSink = "saffire_jack_sink";
  saffireSource = "saffire_jack_source";
  saffirePortChecks = ''
    has_port "$saffire_source:capture_AUX0" &&
      has_port "$saffire_source:capture_AUX4" &&
      has_port "$saffire_source:capture_AUX5" &&
      has_port "$saffire_sink:playback_FL" &&
      has_port "$saffire_sink:playback_FR"
  '';

  ardourPipewire = pkgs.symlinkJoin {
    name = "ardour-pipewire";
    paths = [ pkgs.ardour ];
    buildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/ardour9 \
        --prefix LD_LIBRARY_PATH : ${audioPipewire.jack}/lib
    '';
  };

  ardourPipewireReady = pkgs.writeShellApplication {
    name = "ardour-pipewire-ready";
    runtimeInputs = with pkgs; [
      coreutils
      gnugrep
      jq
      audioPipewire
    ];
    text = ''
      set -euo pipefail

      saffire_sink=${lib.escapeShellArg saffireSink}
      saffire_source=${lib.escapeShellArg saffireSource}
      max_wait_seconds=90
      poll_interval_seconds=2
      required_consecutive_ready_checks=2

      log() {
        printf 'ardour-pipewire-ready: %s\n' "$*" >&2
      }

      pipewire_responds() {
        timeout 3 pw-link -io >/dev/null 2>&1
      }

      has_port() {
        timeout 3 pw-link -io 2>/dev/null | grep -Fqx "$1"
      }

      node_ready() {
        local node_name="$1"
        local media_class="$2"
        local channels="$3"

        timeout 3 pw-dump |
          jq -e \
            --arg node_name "$node_name" \
            --arg media_class "$media_class" \
            --argjson channels "$channels" '
            any(.[]; .type == "PipeWire:Interface:Node" and
              .info.props["node.name"] == $node_name and
              .info.props["media.class"] == $media_class and
              .info.props["audio.channels"] == $channels)
          ' >/dev/null
      }

      saffire_nodes_ready() {
        node_ready "$saffire_sink" "Audio/Sink" 8 &&
          node_ready "$saffire_source" "Audio/Source" 16
      }

      saffire_ports_exist() {
        ${saffirePortChecks}
      }

      midi_ports_exist() {
        has_port "Midi-Bridge:nanoKONTROL2: _ CTRL (capture)" &&
          has_port "Midi-Bridge:nanoKONTROL2: _ CTRL (playback)"
      }

      readiness_failures() {
        if ! pipewire_responds; then
          printf '%s\n' "PipeWire is not responding to pw-link"
        fi

        if ! saffire_nodes_ready; then
          printf '%s\n' "Saffire playback/capture nodes are not ready"
        fi

        if ! saffire_ports_exist; then
          printf '%s\n' "required Saffire audio ports are missing"
        fi

        if ! midi_ports_exist; then
          printf '%s\n' "nanoKONTROL PipeWire MIDI ports are missing"
        fi

        return 0
      }

      wait_until_ready() {
        local consecutive_ready_checks=0
        local deadline
        local failures
        local last_failures=""
        deadline="$(($(date +%s) + max_wait_seconds))"

        while test "$(date +%s)" -lt "$deadline"; do
          failures="$(readiness_failures)"

          if test -z "$failures"; then
            consecutive_ready_checks="$((consecutive_ready_checks + 1))"

            if test "$consecutive_ready_checks" -ge "$required_consecutive_ready_checks"; then
              return 0
            fi
          else
            consecutive_ready_checks=0

            if test "$failures" != "$last_failures"; then
              log "waiting for readiness conditions: $(printf '%s' "$failures" | tr '\n' ';')"
              last_failures="$failures"
            fi
          fi

          sleep "$poll_interval_seconds"
        done

        failures="$(readiness_failures)"
        if test -n "$failures"; then
          log "readiness still failing: $(printf '%s' "$failures" | tr '\n' ';')"
        fi

        return 1
      }

      if wait_until_ready; then
        log "PipeWire Saffire audio and MIDI ports are ready"
        exit 0
      fi

      log "Saffire audio/MIDI port readiness failed"
      exit 1
    '';
  };

  saffireJackTunnelArgs = ''
    {
      jack.library = "libjack.so.0"
      jack.server = saffire
      jack.client-name = SaffirePro24
      jack.connect = true
      tunnel.mode = duplex
      node.group = saffire-jack-group
      source.props = {
        node.name = saffire_jack_source
        node.nick = "Pro24-004de0"
        node.description = "Saffire Pro 24 JACK Source"
        priority.driver = 100
        priority.session = 1
        audio.channels = 16
        audio.position = [ AUX0 AUX1 AUX2 AUX3 AUX4 AUX5 AUX6 AUX7 AUX8 AUX9 AUX10 AUX11 AUX12 AUX13 AUX14 AUX15 ]
        midi.ports = 1
      }
      sink.props = {
        node.name = saffire_jack_sink
        node.nick = "Pro24-004de0"
        node.description = "Saffire Pro 24 JACK Sink"
        priority.driver = 2000
        priority.session = 1
        audio.channels = 8
        audio.position = [ FL FR RL RR FC LFE SL SR ]
        midi.ports = 1
      }
    }
  '';

  saffireJackTunnelReady = pkgs.writeShellApplication {
    name = "saffire-jack-tunnel-ready";
    runtimeInputs = with pkgs; [
      coreutils
      jq
      audioPipewire
    ];
    text = ''
      set -euo pipefail

      for _ in $(seq 1 5); do
        if timeout 3 pw-dump | jq -e '
          any(.[]; .type == "PipeWire:Interface:Node" and .info.props["node.name"] == "${saffireSource}") and
          any(.[]; .type == "PipeWire:Interface:Node" and .info.props["node.name"] == "${saffireSink}")
        ' >/dev/null; then
          exit 0
        fi
        sleep 1
      done

      exit 1
    '';
  };

  battletechGamesRule = builtins.readFile ./wireplumber/battletech-games.conf;
  audioRoutesRule = builtins.readFile ./wireplumber/audio-routes.conf;
  audioRoutesScript = builtins.readFile ./wireplumber/audio-routes.lua;
  alsaClockRule = builtins.readFile ./wireplumber/alsa-clock.conf;

in
{
  home.activation.disableArdourJackNoCopyWorkaround = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    ARDOUR_CONFIG=${lib.escapeShellArg "${config.xdg.configHome}/ardour9/config"}
    if test -f "$ARDOUR_CONFIG"; then
      ${pkgs.gnused}/bin/sed -i \
        -e '/<Option name="work-around-jack-no-copy-optimization"/d' \
        -e '/<Config>/a\    <Option name="work-around-jack-no-copy-optimization" value="0"/>' \
        "$ARDOUR_CONFIG"
    fi
  '';

  home.packages = with pkgs; [
    carla
    qpwgraph
    ardourPipewire
    audioPipewire.jack
    rnnoise-plugin.lv2
    lmms
    lsp-plugins
    show-midi
    audacious
    pavucontrol
    spotify
  ];
  xdg = {
    configFile = {
      "autostart/pulseaudio.desktop" = {
        force = true;
        text = ''
          [Desktop Entry]
          Hidden=true
          Name=PulseAudio Sound System
          Type=Application
        '';
      };
      "pipewire/pipewire.conf.d/10-null-sink.conf" = {
        force = true;
        text = builtins.readFile ./pipewire/10-null-sink.conf;
      };
      "pipewire/pipewire.conf.d/11-null-source.conf" = {
        force = true;
        text = builtins.readFile ./pipewire/11-null-source.conf;
      };
      "pipewire/pipewire.conf.d/20-audiofire-jack.conf".text = ''
        module.jackdbus-detect.args = {
          jack.library = "libjack.so.0"
          jack.client-name = "AudioFire4"
          jack.connect = true
          tunnel.mode = duplex
          audio.channels = 6
          audio.position = [ AUX0 AUX1 AUX2 AUX3 AUX4 AUX5 ]
          source.props = {
            node.name = audiofire_jack_source
            node.description = "AudioFire4 JACK Source"
            priority.session = 1
            midi.ports = 1
          }
          sink.props = {
            node.name = audiofire_jack_sink
            node.description = "AudioFire4 JACK Sink"
            priority.session = 1
            midi.ports = 1
          }
        }
      '';
      "systemd/user/pipewire.service.d/20-audiofire-jack.conf".text = ''
        [Service]
        Environment="LIBJACK_PATH=${jack2}/lib"
      '';
      "wireplumber/wireplumber.conf.d/50-audio-routes.conf".text = audioRoutesRule;
      "pipewire/client.conf.d/52-battletech-games.conf".text = battletechGamesRule;
      "pipewire/pipewire-pulse.conf.d/52-battletech-games.conf".text = battletechGamesRule;
      "wireplumber/wireplumber.conf.d/52-battletech-games.conf".text = battletechGamesRule;
      "wireplumber/wireplumber.conf.d/51-alsa-clock.conf".text = alsaClockRule;
    };

    dataFile."wireplumber/scripts/audio-routes.lua".text = audioRoutesScript;

    desktopEntries."org.rncbc.qpwgraph" = {
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
      settings.Keywords = "PipeWire;MIDI;ALSA;JACK;Qt;";
    };
  };

  systemd.user.services = {
    audiofire-jack = {
      Unit = {
        Description = "AudioFire4 JACK/FFADO server";
        Requires = [ "pipewire.service" ];
        After = [ "pipewire.service" ];
      };

      Service = {
        Type = "dbus";
        BusName = "org.jackaudio.service";
        Environment = "LD_LIBRARY_PATH=${jack2}/lib";
        ExecStart = "${jack2}/bin/jackdbus auto";
        ExecStartPost = [
          "${jack2}/bin/jack_control ds firewire"
          "${jack2}/bin/jack_control dps device guid:0x0014866faf73b593"
          "${jack2}/bin/jack_control dps period 128"
          "${jack2}/bin/jack_control dps nperiods 3"
          "${jack2}/bin/jack_control dps rate 48000"
          "${jack2}/bin/jack_control dps duplex true"
          "${jack2}/bin/jack_control dps verbose 3"
          "${jack2}/bin/jack_control eps realtime-priority 88"
          "${jack2}/bin/jack_control start"
        ];
        ExecStop = [
          "-${jack2}/bin/jack_control stop"
          "-${jack2}/bin/jack_control exit"
        ];
        TimeoutStartSec = 30;
        TimeoutStopSec = 30;
      };
    };

    saffire-jack = {
      Unit = {
        Description = "Saffire Pro 24 JACK/FFADO server";
        Requires = [ "pipewire.service" ];
        Wants = [ "saffire-jack-tunnel.service" ];
        After = [ "pipewire.service" ];
        Before = [ "saffire-jack-tunnel.service" ];
      };

      Service = {
        Environment = "LD_LIBRARY_PATH=${jack2}/lib";
        ExecStart = "${jack2}/bin/jackd --name saffire --realtime --realtime-priority 88 -d firewire --device guid:0x00130e0401c04de0 --period 256 --nperiods 2 --rate 48000 --duplex --verbose 3";
        TimeoutStartSec = 30;
        TimeoutStopSec = 30;
      };

      Install.WantedBy = [ "hyprland-session.target" ];
    };

    saffire-jack-tunnel = {
      Unit = {
        Description = "PipeWire tunnel for the Saffire JACK server";
        BindsTo = [ "saffire-jack.service" ];
        Requires = [ "pipewire.service" ];
        After = [
          "pipewire.service"
          "saffire-jack.service"
        ];
      };

      Service = {
        Environment = "LIBJACK_PATH=${jack2}/lib";
        ExecStart = "${audioPipewire}/bin/pw-cli --monitor load-module libpipewire-module-jack-tunnel ${
          lib.escapeShellArg (lib.replaceStrings [ "\n" ] [ " " ] saffireJackTunnelArgs)
        }";
        ExecStartPost = "${saffireJackTunnelReady}/bin/saffire-jack-tunnel-ready";
        Restart = "on-failure";
        RestartSec = 1;
        TimeoutStartSec = 30;
        TimeoutStopSec = 10;
      };
    };

    ardour-default = {
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
        ];
      };

      Service = {
        ExecStartPre = "${ardourPipewireReady}/bin/ardour-pipewire-ready";
        ExecStart = "${ardourPipewire}/bin/ardour9 /home/wonko/Default";
        KillSignal = "SIGINT";
        Restart = "on-failure";
        RestartSec = 5;
        SuccessExitStatus = "SIGINT";
        TimeoutStartSec = 600;
        TimeoutStopSec = 120;
      };

      Install.WantedBy = [ "hyprland-session.target" ];
    };
  };

  services = {
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
