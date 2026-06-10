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

  xdg.configFile."pipewire/pipewire.conf.d/10-null-sink.conf" = {
    force = true;
    text = ''
      context.objects = [
          {   factory = adapter
              args = {
                 factory.name     = support.null-audio-sink
                 node.name        = "System Sounds"
                 node.description = "System Sounds"
                 media.class      = Audio/Sink
                 object.linger    = true
                 audio.position   = [ FL FR ]
                 monitor.channel-volumes = true
              }
          }
          {   factory = adapter
              args = {
                 factory.name     = support.null-audio-sink
                 node.name        = "Games"
                 node.description = "Games"
                 media.class      = Audio/Sink
                 object.linger    = true
                 audio.position   = [ FL FR ]
                 monitor.channel-volumes = true
              }
          }
          {   factory = adapter
              args = {
                 factory.name     = support.null-audio-sink
                 node.name        = "Music"
                 node.description = "Music"
                 media.class      = Audio/Sink
                 object.linger    = true
                 audio.position   = [ FL FR ]
                 monitor.channel-volumes = true
              }
          }
      ]
    '';
  };

  xdg.configFile."pipewire/pipewire.conf.d/11-null-source.conf" = {
    force = true;
    text = ''
      context.objects = [
          {   factory = adapter
              args = {
                 factory.name     = support.null-audio-sink
                 node.name        = "Ardour"
                 node.description = "Ardour"
                 media.class      = Audio/Source/Virtual
                 object.linger    = true
                 audio.position   = [ FL FR ]
                 monitor.channel-volumes = true
              }
          }
      ]
    '';
  };

  xdg.configFile."wireplumber/wireplumber.conf.d/52-battletech-games.conf".text = ''
    stream.rules = [
      {
        matches = [
          {
            application.process.binary = "BattleTech"
            media.class = "Stream/Output/Audio"
          }
        ]
        actions = {
          update-props = {
            target.object = "Games"
            node.dont-move = true
            state.restore-target = false
          }
        }
      }
    ]
  '';

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
  };
}
