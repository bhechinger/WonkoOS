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
