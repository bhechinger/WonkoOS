{
  config,
  lib,
  pkgs,
  unstable-pkgs,
  ...
}:
let
  audioPipewire = unstable-pkgs.pipewire.override { ffadoSupport = false; };
  saffireSink = "alsa_output.firewire-0x00130e0401c04de0.multichannel-output";
  saffireSource = "alsa_input.firewire-0x00130e0401c04de0.multichannel-input";
  saffireNodeProperties = ''.info.props["device.bus"] == "firewire" and .info.props["api.alsa.pcm.stream"] == $pcm_stream'';
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
      gnused
      jq
      audioPipewire
    ];
    text = ''
      set -euo pipefail

      ardour_config=${lib.escapeShellArg "${config.xdg.configHome}/ardour9/config"}
      saffire_sink=${lib.escapeShellArg saffireSink}
      saffire_source=${lib.escapeShellArg saffireSource}
      max_wait_seconds=90
      poll_interval_seconds=2
      required_consecutive_ready_checks=2

      if test -f "$ardour_config"; then
        sed -E -i \
          -e '/<State backend=/ s/active="[01]"/active="0"/' \
          -e '\|<State backend="JACK/Pipewire"| s/active="0"/active="1"/' \
          -e '/<Option name="work-around-jack-no-copy-optimization"/d' \
          -e '/<Config>/a\    <Option name="work-around-jack-no-copy-optimization" value="0"/>' \
          "$ardour_config"
      fi

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
              ${saffireNodeProperties})
          ' >/dev/null
      }

      saffire_nodes_ready() {
        node_ready "$saffire_sink" "Audio/Sink" "playback" &&
          node_ready "$saffire_source" "Audio/Source" "capture"
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

  ardourGracefulStop = pkgs.writeShellApplication {
    name = "ardour-graceful-stop";
    runtimeInputs = with pkgs; [
      coreutils
      hyprland
      jq
    ];
    derivationArgs.postCheck = ''
      test_dir="$(mktemp -d)"
      test_pid=""
      cleanup() {
        if test -n "$test_pid"; then
          kill "$test_pid" 2>/dev/null || true
        fi
        rm -rf "$test_dir"
      }
      trap cleanup EXIT

      cat >"$test_dir/hyprctl" <<'EOF'
      #!/bin/sh
      case "$*" in
        "-j clients")
          if test "$ARDOUR_TEST_PERMANENT_FAILURE" = 1; then
            printf '[]\n'
            exit 0
          fi
          if test ! -e "$ARDOUR_TEST_STATE"; then
            printf 'dirty' >"$ARDOUR_TEST_STATE"
            printf '[]\n'
            exit 0
          fi
          title="Default - Ardour"
          if test "$(cat "$ARDOUR_TEST_STATE")" = dirty; then
            title="*$title"
          fi
          jq -nc --argjson pid "$ARDOUR_TEST_PID" --arg title "$title" \
            '[{pid: $pid, address: "0xtest", class: "Ardour", title: $title}]'
          ;;
        *'hl.dispatch(hl.dsp.send_shortcut({mods = "CTRL", key = "S", window = "address:0xtest"}))'*)
          if test ! -e "$ARDOUR_TEST_STATE-save-retried"; then
            touch "$ARDOUR_TEST_STATE-save-retried"
            printf 'save-failed\n' >>"$ARDOUR_TEST_LOG"
            printf 'warning: simulated failure\n'
            exit 0
          fi
          printf 'clean' >"$ARDOUR_TEST_STATE"
          printf 'save\n' >>"$ARDOUR_TEST_LOG"
          printf 'ok\n'
          ;;
        *'hl.dispatch(hl.dsp.send_shortcut({mods = "CTRL", key = "Q", window = "address:0xtest"}))'*)
          if test ! -e "$ARDOUR_TEST_STATE-quit-retried"; then
            touch "$ARDOUR_TEST_STATE-quit-retried"
            printf 'quit-failed\n' >>"$ARDOUR_TEST_LOG"
            printf 'warning: simulated failure\n'
            exit 0
          fi
          printf 'quit\n' >>"$ARDOUR_TEST_LOG"
          kill "$ARDOUR_TEST_PID"
          printf 'ok\n'
          ;;
        *) exit 1 ;;
      esac
      EOF
      chmod +x "$test_dir/hyprctl"

      sleep 30 &
      test_pid="$!"
      ARDOUR_HYPRCTL="$test_dir/hyprctl" \
        ARDOUR_TEST_STATE="$test_dir/state" \
        ARDOUR_TEST_LOG="$test_dir/log" \
        ARDOUR_TEST_PID="$test_pid" \
        "$target" "$test_pid"
      test "$(cat "$test_dir/log")" = "$(printf 'save-failed\nsave\nquit-failed\nquit')"

      sleep 30 &
      test_pid="$!"
      if ARDOUR_HYPRCTL="$test_dir/hyprctl" \
        ARDOUR_STOP_TIMEOUT_SECONDS=1 \
        ARDOUR_TEST_PERMANENT_FAILURE=1 \
        ARDOUR_TEST_STATE="$test_dir/state" \
        ARDOUR_TEST_LOG="$test_dir/log" \
        ARDOUR_TEST_PID="$test_pid" \
        "$target" "$test_pid"; then
        echo "expected a persistent Hyprland failure to time out" >&2
        exit 1
      fi
    '';
    text = ''
      pid="$1"
      hyprctl_command="''${ARDOUR_HYPRCTL:-hyprctl}"
      timeout_seconds="''${ARDOUR_STOP_TIMEOUT_SECONDS:-20}"
      deadline="$((SECONDS + timeout_seconds))"

      client() {
        "$hyprctl_command" -j clients |
          jq -r --argjson pid "$pid" '
            first(.[] | select(.pid == $pid and .class == "Ardour") |
              [.address, .title] | @tsv) // empty
          '
      }

      log() {
        printf 'ardour-graceful-stop: %s\n' "$*" >&2
      }

      check_deadline() {
        if test "$SECONDS" -ge "$deadline"; then
          log "graceful stop timed out after $timeout_seconds seconds; forcing a restart"
          exit 1
        fi
      }

      send_shortcut() {
        local key="$1"
        local response
        response="$("$hyprctl_command" eval \
          "return hl.dispatch(hl.dsp.send_shortcut({mods = \"CTRL\", key = \"$key\", window = \"address:$address\"}))")"
        test "$response" = ok
      }

      client_info=""
      while kill -0 "$pid" 2>/dev/null; do
        client_info="$(client 2>/dev/null || true)"
        if test -n "$client_info"; then
          break
        fi
        check_deadline
        sleep 1
      done

      if ! kill -0 "$pid" 2>/dev/null; then
        exit 0
      fi

      address="''${client_info%%$'\t'*}"
      until send_shortcut S; do
        if ! kill -0 "$pid" 2>/dev/null; then
          exit 0
        fi
        client_info="$(client 2>/dev/null || true)"
        if test -n "$client_info"; then
          address="''${client_info%%$'\t'*}"
        fi
        check_deadline
        sleep 1
      done

      title=""
      while kill -0 "$pid" 2>/dev/null; do
        client_info="$(client 2>/dev/null || true)"
        title="''${client_info#*$'\t'}"
        if test -n "$client_info" && [[ "$title" != \** ]]; then
          break
        fi

        check_deadline
        sleep 0.25
      done

      if ! kill -0 "$pid" 2>/dev/null; then
        exit 0
      fi

      address="''${client_info%%$'\t'*}"
      until send_shortcut Q; do
        if ! kill -0 "$pid" 2>/dev/null; then
          exit 0
        fi
        client_info="$(client 2>/dev/null || true)"
        if test -n "$client_info"; then
          address="''${client_info%%$'\t'*}"
        fi
        check_deadline
        sleep 1
      done

      while kill -0 "$pid" 2>/dev/null; do
        check_deadline
        sleep 0.25
      done
    '';
  };

  battletechGamesRule = builtins.readFile ./wireplumber/battletech-games.conf;
  audioRoutesRule = builtins.readFile ./wireplumber/audio-routes.conf;
  audioRoutesScript = builtins.readFile ./wireplumber/audio-routes.lua;
  alsaClockRule = builtins.readFile ./wireplumber/alsa-clock.conf;

in
{
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
    ardour-default = {
      Unit = {
        Description = "Ardour Default session";
        Wants = [
          "pipewire.service"
          "wireplumber.service"
        ];
        After = [
          "graphical-session.target"
          "pipewire.service"
          "wireplumber.service"
        ];
        PartOf = [
          "hyprland-session.target"
          "wireplumber.service"
        ];
      };

      Service = {
        ExecStartPre = "${ardourPipewireReady}/bin/ardour-pipewire-ready";
        ExecStart = "${ardourPipewire}/bin/ardour9 /home/wonko/Default";
        ExecStop = "${ardourGracefulStop}/bin/ardour-graceful-stop $MAINPID";
        KillSignal = "SIGKILL";
        Restart = "on-failure";
        RestartSec = 5;
        TimeoutStartSec = 600;
        TimeoutStopSec = 30;
      };

      Install.WantedBy = [ "hyprland-session.target" ];
    };

    spotify-midi-control.Unit = {
      Wants = [ "wireplumber.service" ];
      After = [ "wireplumber.service" ];
      PartOf = [ "wireplumber.service" ];
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
