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
      pipewire
    ];
    text = ''
      set -euo pipefail

      saffire_source="alsa_input.firewire-0x00130e0401c04de0.multichannel-input"
      probe_file="''${TMPDIR:-/tmp}/ardour-saffire-readiness.wav"
      min_probe_bytes=4096
      max_wait_seconds=90
      poll_interval_seconds=2

      log() {
        printf 'ardour-pipewire-ready: %s\n' "$*" >&2
      }

      systemctl_user() {
        local runtime_dir
        local bus_address

        runtime_dir="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
        bus_address="''${DBUS_SESSION_BUS_ADDRESS:-unix:path=$runtime_dir/bus}"

        XDG_RUNTIME_DIR="$runtime_dir" \
          DBUS_SESSION_BUS_ADDRESS="$bus_address" \
          env -u NOTIFY_SOCKET /run/current-system/sw/bin/systemctl --user "$@"
      }

      pipewire_responds() {
        pw-cli info 0 >/dev/null 2>&1
      }

      has_port() {
        pw-link -io 2>/dev/null | grep -Fqx "$1"
      }

      saffire_ports_exist() {
        has_port "$saffire_source:capture_AUX0" &&
          has_port "$saffire_source:capture_AUX4" &&
          has_port "$saffire_source:capture_AUX5" &&
          has_port "alsa_output.firewire-0x00130e0401c04de0.multichannel-output:playback_FL" &&
          has_port "alsa_output.firewire-0x00130e0401c04de0.multichannel-output:playback_FR"
      }

      midi_ports_exist() {
        has_port "Midi-Bridge:Pro24-004de0: MIDI 1 (capture)" &&
          has_port "Midi-Bridge:nanoKONTROL2: _ CTRL (capture)"
      }

      saffire_capture_delivers_buffers() {
        rm -f "$probe_file"

        timeout 5 pw-record \
          --target "$saffire_source" \
          --channels 16 \
          --rate 48000 \
          --format s32 \
          "$probe_file" >/dev/null 2>&1 || true

        test -f "$probe_file" || return 1

        local probe_bytes
        probe_bytes="$(wc -c < "$probe_file")"
        rm -f "$probe_file"

        test "$probe_bytes" -gt "$min_probe_bytes"
      }

      wait_until_ready() {
        local deadline
        local capture_failures=0
        deadline="$(($(date +%s) + max_wait_seconds))"

        while test "$(date +%s)" -lt "$deadline"; do
          if pipewire_responds &&
             saffire_ports_exist &&
             midi_ports_exist; then
            if saffire_capture_delivers_buffers; then
              return 0
            fi

            capture_failures="$((capture_failures + 1))"
            if test "$capture_failures" -ge 3; then
              return 1
            fi
          else
            capture_failures=0
          fi

          sleep "$poll_interval_seconds"
        done

        return 1
      }

      restart_pipewire_stack() {
        local attempt

        for attempt in 1 2 3 4 5; do
          if systemctl_user restart pipewire.service pipewire-pulse.service wireplumber.service; then
            return 0
          fi

          log "PipeWire restart attempt $attempt failed; retrying"
          sleep 1
        done

        return 1
      }

      if wait_until_ready; then
        log "PipeWire Saffire audio and MIDI are ready"
        exit 0
      fi

      log "PipeWire graph did not become usable; restarting user PipeWire stack once"
      restart_pipewire_stack
      sleep 3

      if wait_until_ready; then
        log "PipeWire Saffire audio and MIDI recovered after restart"
        exit 0
      fi

      log "Saffire audio/MIDI readiness failed"
      exit 1
    '';
  };

  battletechGamesRule = builtins.readFile ./wireplumber/battletech-games.conf;
  #audiofireFfadoRule = builtins.readFile ./pipewire/audiofire-ffado.conf;
  audioRoutesRule = builtins.readFile ./wireplumber/audio-routes.conf;
  audioRoutesScript = builtins.readFile ./wireplumber/audio-routes.lua;
  midiRoutesRule = builtins.readFile ./wireplumber/midi-routes.conf;
  midiRoutesScript = builtins.readFile ./wireplumber/midi-routes.lua;
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
      ];
    };

    Service = {
      ExecStartPre = "${ardourPipewireReady}/bin/ardour-pipewire-ready";
      ExecStart = "${ardourPipewire}/bin/ardour9 /home/wonko/Default";
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
    text = builtins.readFile ./pipewire/10-null-sink.conf;
  };

  xdg.configFile."pipewire/pipewire.conf.d/11-null-source.conf" = {
    force = true;
    text = builtins.readFile ./pipewire/11-null-source.conf;
  };

  xdg.dataFile."wireplumber/scripts/audio-routes.lua".text = audioRoutesScript;
  xdg.configFile."wireplumber/wireplumber.conf.d/50-audio-routes.conf".text = audioRoutesRule;
  xdg.dataFile."wireplumber/scripts/midi-routes.lua".text = midiRoutesScript;
  xdg.configFile."wireplumber/wireplumber.conf.d/50-midi-routes.conf".text = midiRoutesRule;

  xdg.configFile."pipewire/client.conf.d/52-battletech-games.conf".text = battletechGamesRule;
  xdg.configFile."pipewire/pipewire-pulse.conf.d/52-battletech-games.conf".text = battletechGamesRule;
  xdg.configFile."wireplumber/wireplumber.conf.d/52-battletech-games.conf".text = battletechGamesRule;

  #xdg.configFile."pipewire/pipewire.conf.d/51-audiofire-ffado.conf".text = audiofireFfadoRule;
  xdg.configFile."wireplumber/wireplumber.conf.d/51-saffire-clock.conf".text = saffireClockRule;

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
