{ pkgs, ... }:
{
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
