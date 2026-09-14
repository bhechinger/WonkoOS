{
  config,
  lib,
  pkgs,
  ...
}:
{
  home.activation.useArdourAlsa = lib.hm.dag.entryBetween [ "reloadSystemd" ] [ "writeBoundary" ] ''
    ARDOUR_CONFIG=${lib.escapeShellArg "${config.xdg.configHome}/ardour9/config"}
    if test -f "$ARDOUR_CONFIG"; then
      ${pkgs.gnused}/bin/sed -E -i \
        -e '/<State backend=/ s/active="[01]"/active="0"/' \
        -e '/<State backend="ALSA"/ s/active="0"/active="1"/' \
        "$ARDOUR_CONFIG"
    fi
  '';

  home.packages = with pkgs; [
    carla
    qpwgraph
    ardour
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
      "wireplumber/wireplumber.conf.d/51-alsa-clock.conf".text =
        builtins.readFile ./wireplumber/alsa-clock.conf;
    };

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
      settings.Keywords = "PipeWire;MIDI;ALSA;Qt;";
    };
  };

  systemd.user.services.ardour-default = {
    Unit = {
      Description = "Ardour Default session";
      Wants = [ "wireplumber.service" ];
      After = [ "wireplumber.service" ];
      PartOf = [ "hyprland-session.target" ];
    };

    Service = {
      ExecStart = "${pkgs.ardour}/bin/ardour9 /home/wonko/Default";
      KillSignal = "SIGINT";
      Restart = "on-failure";
      RestartSec = 5;
      SuccessExitStatus = "SIGINT";
      TimeoutStopSec = 120;
    };

    Install.WantedBy = [ "hyprland-session.target" ];
  };

  services.spotify-midi-control = {
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
}
