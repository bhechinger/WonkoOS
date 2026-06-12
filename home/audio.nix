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

  battletechGamesRule = builtins.readFile ./wireplumber/battletech-games.conf;
  #audiofireFfadoRule = builtins.readFile ./pipewire/audiofire-ffado.conf;
  # routeToArdourRule = builtins.readFile ./wireplumber/route-to-ardour.conf;
  # routeToArdourScript = builtins.readFile ./wireplumber/route-to-ardour.lua;
  audioRoutesRule = builtins.readFile ./wireplumber/audio-routes.conf;
  audioRoutesScript = builtins.readFile ./wireplumber/audio-routes.lua;
  #routeMidiToSpotifyRule = builtins.readFile ./wireplumber/route-midi-to-spotify.conf;
  #routeMidiToSpotifyScript = builtins.readFile ./wireplumber/route-midi-to-spotify.lua;
  #saffireClockRule = builtins.readFile ./wireplumber/saffire-clock.conf;

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
  xdg.configFile."autostart/org.rncbc.qpwgraph.desktop" = {
    force = true;
    text = ''
      [Desktop Entry]
      Categories=AudioVideo;Audio;Video;Midi;X-Alsa;X-PipeWire;Qt;
      Comment=qpwgraph is a PipeWire graph Qt GUI interface
      Exec=qpwgraph -d -m
      GenericName=PipeWire Graph Viewer
      Icon=org.rncbc.qpwgraph
      Keywords=PipeWire;MIDI;ALSA;JACK;Qt;
      Name=qpwgraph
      StartupNotify=true
      Terminal=false
      Type=Application
      Version=1.0
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
        "pipewire.service"
      ];
    };

    Service = {
      ExecStartPre = "${pkgs.coreutils}/bin/sleep 5";
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

  #xdg.configFile."pipewire/pipewire.conf.d/51-audiofire-ffado.conf".text = audiofireFfadoRule;

  # xdg.dataFile."wireplumber/scripts/route-to-ardour.lua".text = routeToArdourScript;
  xdg.dataFile."wireplumber/scripts/audio-routes.lua".text = audioRoutesScript;
  # xdg.dataFile."wireplumber/scripts/route-midi-to-spotify.lua".text = routeMidiToSpotifyScript;

  # xdg.configFile."wireplumber/wireplumber.conf.d/50-route-to-ardour.conf".text = routeToArdourRule;
  #xdg.configFile."wireplumber/wireplumber.conf.d/50-route-midi-to-spotify.conf".text =
  #  routeMidiToSpotifyRule;
  #xdg.configFile."wireplumber/wireplumber.conf.d/51-saffire-clock.conf".text = saffireClockRule;
  xdg.configFile."wireplumber/wireplumber.conf.d/50-audio-routes.conf".text = audioRoutesRule;

  # I don't know why all three of these are required, but it doesn't work without them.
  xdg.configFile."pipewire/client.conf.d/52-battletech-games.conf".text = battletechGamesRule;
  xdg.configFile."pipewire/pipewire-pulse.conf.d/52-battletech-games.conf".text = battletechGamesRule;
  xdg.configFile."wireplumber/wireplumber.conf.d/52-battletech-games.conf".text = battletechGamesRule;

  systemd.user.services.spotify-midi-control.Unit.PartOf = [ "pipewire.service" ];

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
