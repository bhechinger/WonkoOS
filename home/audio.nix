{ inputs, config, lib, pkgs, ... }:

{
  home.packages = with pkgs; [
    carla
    qpwgraph
    ardour
    lmms
    lsp-plugins
    show-midi
    audacious
    pavucontrol
    qjackctl
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
