{ pkgs, ... }:
{
  home.packages = with pkgs; [
    ardour
    carla
    ffado-mixer
    jack2
    jack-example-tools
    qjackctl
    rnnoise-plugin.lv2
    lmms
    lsp-plugins
    show-midi
    audacious
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

  xdg.desktopEntries."org.rncbc.qjackctl" = {
    name = "QjackCtl";
    genericName = "JACK Control";
    comment = "JACK Audio Connection Kit Qt GUI interface";
    exec = "qjackctl";
    icon = "org.rncbc.qjackctl";
    terminal = false;
    startupNotify = true;
    categories = [
      "AudioVideo"
      "Audio"
      "Midi"
      "X-Alsa"
      "X-Jack"
      "Qt"
    ];
    settings = {
      Keywords = "JACK;MIDI;ALSA;Qt;";
    };
  };

  services.spotify-midi-control.enable = false;
}
