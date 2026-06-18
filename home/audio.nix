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

  ardourPipewireReady = pkgs.writeShellApplication {
    name = "ardour-pipewire-ready";
    runtimeInputs = with pkgs; [
      coreutils
      gnugrep
      jq
      pipewire
    ];
    text = ''
      set -euo pipefail

      saffire_sink="alsa_output.firewire-0x00130e0401c04de0.multichannel-output"
      saffire_source="alsa_input.firewire-0x00130e0401c04de0.multichannel-input"
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
        local pcm_stream="$3"

        timeout 3 pw-dump |
          jq -e \
            --arg node_name "$node_name" \
            --arg media_class "$media_class" \
            --arg pcm_stream "$pcm_stream" '
            any(.[]; .type == "PipeWire:Interface:Node" and
              .info.props["node.name"] == $node_name and
              .info.props["media.class"] == $media_class and
              .info.props["device.bus"] == "firewire" and
              .info.props["api.alsa.pcm.stream"] == $pcm_stream)
          ' >/dev/null
      }

      saffire_nodes_ready() {
        node_ready "$saffire_sink" "Audio/Sink" "playback" &&
          node_ready "$saffire_source" "Audio/Source" "capture"
      }

      saffire_ports_exist() {
        has_port "$saffire_source:capture_AUX0" &&
          has_port "$saffire_source:capture_AUX4" &&
          has_port "$saffire_source:capture_AUX5" &&
          has_port "alsa_output.firewire-0x00130e0401c04de0.multichannel-output:playback_FL" &&
          has_port "alsa_output.firewire-0x00130e0401c04de0.multichannel-output:playback_FR"
      }

      midi_ports_exist() {
        has_port "Midi-Bridge:nanoKONTROL2: _ CTRL (capture)"
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
          printf '%s\n' "nanoKONTROL PipeWire MIDI port is missing"
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

  battletechGamesRule = builtins.readFile ./wireplumber/battletech-games.conf;
  # audiofireFfadoRule = builtins.readFile ./pipewire/audiofire-ffado.conf;
  audioRoutesRule = builtins.readFile ./wireplumber/audio-routes.conf;
  audioRoutesScript = builtins.readFile ./wireplumber/audio-routes.lua;
  # midiRoutesRule = builtins.readFile ./wireplumber/midi-routes.conf;
  # midiRoutesScript = builtins.readFile ./wireplumber/midi-routes.lua;
  saffireClockRule = builtins.readFile ./wireplumber/saffire-clock.conf;

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
  xdg.configFile."autostart/pulseaudio.desktop" = {
    force = true;
    text = ''
      [Desktop Entry]
      Hidden=true
      Name=PulseAudio Sound System
      Type=Application
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

  systemd.user.services = {
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

  xdg.configFile."pipewire/pipewire.conf.d/10-null-sink.conf" = {
    force = true;
    text = builtins.readFile ./pipewire/10-null-sink.conf;
  };

  xdg.configFile."pipewire/pipewire.conf.d/11-null-source.conf" = {
    force = true;
    text = builtins.readFile ./pipewire/11-null-source.conf;
  };

  xdg.dataFile."wireplumber/scripts/audio-routes.lua".text = audioRoutesScript;
  xdg.configFile."wireplumber/wireplumber.conf.d/50-audio-routes.conf".text = audioRoutesRule;
  # xdg.dataFile."wireplumber/scripts/midi-routes.lua".text = midiRoutesScript;
  # xdg.configFile."wireplumber/wireplumber.conf.d/50-midi-routes.conf".text = midiRoutesRule;

  xdg.configFile."pipewire/client.conf.d/52-battletech-games.conf".text = battletechGamesRule;
  xdg.configFile."pipewire/pipewire-pulse.conf.d/52-battletech-games.conf".text = battletechGamesRule;
  xdg.configFile."wireplumber/wireplumber.conf.d/52-battletech-games.conf".text = battletechGamesRule;

  # xdg.configFile."pipewire/pipewire.conf.d/51-audiofire-ffado.conf".text = audiofireFfadoRule;
  xdg.configFile."wireplumber/wireplumber.conf.d/51-saffire-clock.conf".text = saffireClockRule;

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
