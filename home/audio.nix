{
  config,
  lib,
  pipewire-src,
  pkgs,
  unstable-pkgs,
  ...
}:
let
  ffadoPipewire = import ../common/pipewire-ffado {
    pkgs = unstable-pkgs;
    inherit pipewire-src;
  };

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
        --prefix LD_LIBRARY_PATH : ${ffadoPipewire.jack}/lib
    '';
  };

  ardourPipewireReady = pkgs.writeShellApplication {
    name = "ardour-pipewire-ready";
    runtimeInputs = with pkgs; [
      coreutils
      gnugrep
      jq
      ffadoPipewire
    ];
    text = ''
      set -euo pipefail

      saffire_sink="saffire_ffado_output"
      saffire_source="saffire_ffado_input"
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

        timeout 3 pw-dump |
          jq -e \
            --arg node_name "$node_name" \
            --arg media_class "$media_class" '
            any(.[]; .type == "PipeWire:Interface:Node" and
              .info.props["node.name"] == $node_name and
              .info.props["media.class"] == $media_class and
              .info.props["node.group"] == "saffire-ffado-group")
          ' >/dev/null
      }

      saffire_nodes_ready() {
        node_ready "$saffire_sink" "Audio/Sink" &&
          node_ready "$saffire_source" "Audio/Source"
      }

      saffire_ports_exist() {
        has_port "$saffire_source:00130e0401c04de0_1394/Out:01 (Anlg/In:03)_out" &&
          has_port "$saffire_source:00130e0401c04de0_1394/Out:05 (SPDIF/In:01)_out" &&
          has_port "$saffire_source:00130e0401c04de0_1394/Out:06 (SPDIF/In:02)_out" &&
          has_port "$saffire_sink:00130e0401c04de0_1394/In:01 (Mixer/In:17)_in" &&
          has_port "$saffire_sink:00130e0401c04de0_1394/In:02 (Mixer/In:18)_in"
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
    ffadoPipewire.jack
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
      "pipewire/pipewire.conf.d/20-firewire-ffado.conf".source = ./pipewire/firewire-ffado.conf;
      "wireplumber/wireplumber.conf.d/50-audio-routes.conf".text = audioRoutesRule;
      "pipewire/client.conf.d/52-battletech-games.conf".text = battletechGamesRule;
      "pipewire/pipewire-pulse.conf.d/52-battletech-games.conf".text = battletechGamesRule;
      "wireplumber/wireplumber.conf.d/52-battletech-games.conf".text = battletechGamesRule;
      "wireplumber/wireplumber.conf.d/51-saffire-clock.conf".text = saffireClockRule;
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
        Environment = "PIPEWIRE_LATENCY=256/48000";
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
