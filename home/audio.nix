{
  config,
  lib,
  pipewire-src,
  pkgs,
  unstable-pkgs,
  useSaffireFfado,
  ...
}:
let
  ffadoPipewire = import ../common/pipewire-ffado {
    pkgs = unstable-pkgs;
    inherit pipewire-src;
  };
  audioPipewire = if useSaffireFfado then ffadoPipewire else pkgs.pipewire;
  saffireSink =
    if useSaffireFfado then
      "saffire_ffado_output"
    else
      "alsa_output.firewire-0x00130e0401c04de0.multichannel-output";
  saffireSource =
    if useSaffireFfado then
      "saffire_ffado_input"
    else
      "alsa_input.firewire-0x00130e0401c04de0.multichannel-input";
  saffireNodeProperties =
    if useSaffireFfado then
      ''.info.props["node.group"] == "saffire-ffado-group"''
    else
      ''.info.props["device.bus"] == "firewire" and .info.props["api.alsa.pcm.stream"] == $pcm_stream'';
  saffirePortChecks =
    if useSaffireFfado then
      ''
        has_port "$saffire_source:00130e0401c04de0_1394/Out:01 (Anlg/In:03)_out" &&
          has_port "$saffire_source:00130e0401c04de0_1394/Out:05 (SPDIF/In:01)_out" &&
          has_port "$saffire_source:00130e0401c04de0_1394/Out:06 (SPDIF/In:02)_out" &&
          has_port "$saffire_sink:00130e0401c04de0_1394/In:01 (Mixer/In:17)_in" &&
          has_port "$saffire_sink:00130e0401c04de0_1394/In:02 (Mixer/In:18)_in"
      ''
    else
      ''
        has_port "$saffire_source:capture_AUX0" &&
          has_port "$saffire_source:capture_AUX4" &&
          has_port "$saffire_source:capture_AUX5" &&
          has_port "$saffire_sink:playback_FL" &&
          has_port "$saffire_sink:playback_FR"
      '';

  audiofirePipewireConfig = pkgs.runCommand "audiofire-pipewire-config" { } ''
    mkdir -p "$out/pipewire.conf.d"
    ln -s ${ffadoPipewire}/share/pipewire/pipewire.conf "$out/pipewire.conf"
    ln -s ${./pipewire/audiofire-ffado.conf} "$out/pipewire.conf.d/20-audiofire-ffado.conf"
  '';

  audiofireFfadoHost = pkgs.writeShellApplication {
    name = "audiofire-ffado-host";
    runtimeInputs = [
      ffadoPipewire
      pkgs.coreutils
      pkgs.jq
    ];
    text = ''
      for _ in $(seq 1 90); do
        if timeout 3 pw-dump 2>/dev/null |
          jq -e '
            any(.[]; .type == "PipeWire:Interface:Node" and
              .info.props["node.name"] == "saffire_ffado_output" and
              .info.state == "running") and
            any(.[]; .type == "PipeWire:Interface:Node" and
              .info.props["node.name"] == "saffire_ffado_input" and
              .info.state == "running")
          ' >/dev/null
        then
          sleep 5
          export PIPEWIRE_CONFIG_DIR=${audiofirePipewireConfig}
          exec pipewire
        fi
        sleep 1
      done

      echo "audiofire-ffado-host: production PipeWire did not become ready" >&2
      exit 1
    '';
  };

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

  cleanupGoogleMeetPipewireClients = pkgs.writeShellApplication {
    name = "cleanup-google-meet-pipewire-clients";
    runtimeInputs = with pkgs; [
      coreutils
      jq
      pipewire
    ];
    text = ''
      pw-dump |
        jq -r '.[] | select(.type == "PipeWire:Interface:Node" and ((.info.props["media.name"] // "") | test("^Meet( - [a-z]{3}-[a-z]{4}-[a-z]{3})?$"))) | .id' |
        xargs --no-run-if-empty --max-args=1 pw-cli destroy 2>/dev/null
    '';
  };

  ffadoFailureMonitor = pkgs.writeShellApplication {
    name = "ffado-failure-monitor";
    runtimeInputs = with pkgs; [
      coreutils
      gawk
      gnugrep
      systemd
    ];
    text = ''
      set -u

      runtime_dir="''${XDG_RUNTIME_DIR:?}/ffado-failure-monitor"
      state_dir="''${XDG_STATE_HOME:-$HOME/.local/state}/ffado-diagnostics"
      sample_file="$runtime_dir/samples.log"
      previous_sample_file="$runtime_dir/samples.previous.log"
      saffire_guid="0x00130e0401c04de0"
      saffire_irq=""
      pipewire_pid=""

      mkdir -p "$runtime_dir" "$state_dir"
      : >"$sample_file"

      find_saffire_irq() {
        local controller_dir
        local guid_file

        for guid_file in /sys/bus/firewire/devices/fw*/guid; do
          if grep -Fqx "$saffire_guid" "$guid_file" 2>/dev/null; then
            controller_dir="$(dirname "$(readlink -f "$guid_file")")"
            while test "$controller_dir" != /sys; do
              if test -r "$controller_dir/irq"; then
                cat "$controller_dir/irq"
                return 0
              fi
              controller_dir="$(dirname "$controller_dir")"
            done
          fi
        done
        return 1
      }

      sample_state() {
        local comm
        local irq_total
        local runtime
        local scheduler_wait
        local stat_fields
        local state
        local switches
        local task_dir
        local uptime

        if test -z "$saffire_irq"; then
          saffire_irq="$(find_saffire_irq || true)"
        fi
        irq_total=unavailable
        if test -n "$saffire_irq"; then
          irq_total="$(
            awk -v irq="$saffire_irq:" '
              $1 == irq {
                total = 0
                for (field = 2; field <= NF && $field ~ /^[0-9]+$/; field++)
                  total += $field
                print total
              }
            ' /proc/interrupts
          )"
          irq_total="''${irq_total:-unavailable}"
        fi

        if test -z "$pipewire_pid" || test "$pipewire_pid" = 0 ||
          ! test -d "/proc/$pipewire_pid/task"
        then
          pipewire_pid="$(
            systemctl --user show pipewire.service --property=MainPID --value 2>/dev/null ||
              true
          )"
        fi
        read -r uptime _ </proc/uptime
        printf 'monotonic=%s irq=%s irq-total=%s pipewire-pid=%s' \
          "$uptime" "''${saffire_irq:-unavailable}" "$irq_total" \
          "''${pipewire_pid:-unavailable}"

        if test -n "$pipewire_pid" && test "$pipewire_pid" != 0 &&
          test -d "/proc/$pipewire_pid/task"
        then
          for task_dir in "/proc/$pipewire_pid"/task/*; do
            read -r comm <"$task_dir/comm" || continue
            case "$comm" in
              FW_ISORCV | FW_ISOXMT | data-loop.*)
                read -r runtime scheduler_wait switches <"$task_dir/schedstat" || continue
                read -r stat_fields <"$task_dir/stat" || continue
                stat_fields="''${stat_fields#*) }"
                state="''${stat_fields%% *}"
                printf ' thread=%s,%s,%s,%s,%s,%s' \
                  "''${task_dir##*/}" "$comm" "$state" "$runtime" "$scheduler_wait" "$switches"
                ;;
            esac
          done
        fi
        printf '\n'
      }

      sample_loop() {
        local samples=0

        while true; do
          sample_state >>"$sample_file"
          samples="$((samples + 1))"
          if test "$samples" -ge 4096; then
            mv -f "$sample_file" "$previous_sample_file"
            : >"$sample_file"
            samples=0
          fi
          sleep 0.25
        done
      }

      save_snapshot() {
        local output
        local stamp

        stamp="$(date --utc +%Y%m%dT%H%M%SZ)"
        output="$state_dir/ffado-failure-$stamp.log"
        sleep 2
        {
          printf 'FFADO transport failure snapshot %s\n\n' "$stamp"
          printf '%s\n' '=== FireWire IRQ and realtime-thread samples ==='
          tail -n 80 "$previous_sample_file" "$sample_file" 2>/dev/null || true
          printf '\n%s\n' '=== PipeWire journal (last 20 seconds) ==='
          journalctl --user --unit=pipewire.service --since='-20 seconds' \
            --no-pager --output=short-monotonic
        } >"$output"
        printf 'saved FFADO failure evidence to %s\n' "$output"
      }

      sample_loop &
      sampler_pid="$!"
      trap 'kill "$sampler_pid" 2>/dev/null || true' EXIT INT TERM

      last_snapshot=0
      while IFS= read -r line; do
        case "$line" in
          *"FFADO error"*)
            now="$(date +%s)"
            if test "$((now - last_snapshot))" -ge 10; then
              last_snapshot="$now"
              save_snapshot
            fi
            ;;
        esac
      done < <(
        journalctl --user --unit=pipewire.service --follow --lines=0 \
          --output=short-monotonic
      )
    '';
  };

  battletechGamesRule = builtins.readFile ./wireplumber/battletech-games.conf;
  audioRoutesRule = builtins.readFile ./wireplumber/audio-routes.conf;
  audioRoutesScript = builtins.readFile ./wireplumber/audio-routes.lua;
  saffireClockRule = builtins.readFile ./wireplumber/saffire-clock.conf;

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
    cleanupGoogleMeetPipewireClients
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
      "wireplumber/wireplumber.conf.d/51-saffire-clock.conf".text = saffireClockRule;
    }
    // lib.optionalAttrs useSaffireFfado {
      "pipewire/pipewire.conf.d/20-firewire-ffado.conf".source = ./pipewire/firewire-ffado.conf;
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
      }
      // lib.optionalAttrs useSaffireFfado {
        Environment = "PIPEWIRE_LATENCY=256/48000";
      };

      Install.WantedBy = [ "hyprland-session.target" ];
    };
  }
  // lib.optionalAttrs useSaffireFfado {
    ffado-failure-monitor = {
      Unit = {
        Description = "Capture evidence around fatal PipeWire/FFADO transport failures";
        Wants = [ "pipewire.service" ];
        After = [ "pipewire.service" ];
      };

      Service = {
        ExecStart = "${ffadoFailureMonitor}/bin/ffado-failure-monitor";
        Restart = "always";
        RestartSec = 2;
      };

      Install.WantedBy = [ "default.target" ];
    };

    audiofire-ffado-export = {
      Unit = {
        Description = "Export AudioFire4 FFADO nodes into production PipeWire";
        Requires = [ "pipewire.service" ];
        After = [ "pipewire.service" ];
        PartOf = [ "pipewire.service" ];
      };

      Service = {
        ExecStart = "${audiofireFfadoHost}/bin/audiofire-ffado-host";
        Restart = "on-failure";
        RestartSec = 5;
        LimitMEMLOCK = "infinity";
        LimitRTPRIO = 95;
        LimitNICE = "-11";
      };

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
