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
      min_boot_age_seconds=300
      max_wait_seconds=90
      poll_interval_seconds=2

      log() {
        printf 'ardour-pipewire-ready: %s\n' "$*" >&2
      }

      pipewire_responds() {
        timeout 3 pw-link -io >/dev/null 2>&1
      }

      has_port() {
        timeout 3 pw-link -io 2>/dev/null | grep -Fqx "$1"
      }

      wait_for_saffire_boot_settle() {
        local uptime_seconds
        local remaining_seconds

        read -r uptime_seconds _ < /proc/uptime
        uptime_seconds="''${uptime_seconds%.*}"

        if test "$uptime_seconds" -ge "$min_boot_age_seconds"; then
          return 0
        fi

        remaining_seconds="$((min_boot_age_seconds - uptime_seconds))"
        log "waiting $remaining_seconds seconds for FireWire Saffire to settle after boot"
        sleep "$remaining_seconds"
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

      wait_until_ready() {
        local deadline
        deadline="$(($(date +%s) + max_wait_seconds))"

        while test "$(date +%s)" -lt "$deadline"; do
          if pipewire_responds &&
             saffire_ports_exist &&
             midi_ports_exist; then
            return 0
          fi

          sleep "$poll_interval_seconds"
        done

        return 1
      }

      wait_for_saffire_boot_settle

      if wait_until_ready; then
        log "PipeWire Saffire audio and MIDI ports are ready"
        exit 0
      fi

      log "Saffire audio/MIDI port readiness failed"
      exit 1
    '';
  };

  spotifyMidiControlReady = pkgs.writeShellApplication {
    name = "spotify-midi-control-ready";
    runtimeInputs = with pkgs; [
      coreutils
      gnugrep
      pipewire
    ];
    text = ''
      set -euo pipefail

      max_wait_seconds=90
      poll_interval_seconds=2
      nanokontrol_port="Midi-Bridge:nanoKONTROL2: _ CTRL (capture)"

      log() {
        printf 'spotify-midi-control-ready: %s\n' "$*" >&2
      }

      pipewire_responds() {
        timeout 3 pw-link -io >/dev/null 2>&1
      }

      has_port() {
        timeout 3 pw-link -io 2>/dev/null | grep -Fqx "$1"
      }

      deadline="$(($(date +%s) + max_wait_seconds))"

      while test "$(date +%s)" -lt "$deadline"; do
        if pipewire_responds && has_port "$nanokontrol_port"; then
          log "nanoKONTROL PipeWire MIDI port is ready"
          exit 0
        fi

        sleep "$poll_interval_seconds"
      done

      log "nanoKONTROL PipeWire MIDI port did not become ready"
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
        TimeoutStartSec = 420;
        TimeoutStopSec = 120;
      };

      Install.WantedBy = [ "hyprland-session.target" ];
    };

    spotify-midi-control = {
      Unit = {
        Wants = [
          "pipewire.service"
          "wireplumber.service"
        ];
        After = [
          "pipewire.service"
          "wireplumber.service"
        ];
        PartOf = [
          "pipewire.service"
          "wireplumber.service"
        ];
      };

      Service = {
        ExecStartPre = "${spotifyMidiControlReady}/bin/spotify-midi-control-ready";
        # Recover after PipeWire/WirePlumber churn even when the helper exits cleanly.
        Restart = "always";
        RestartSec = 5;
      };
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
