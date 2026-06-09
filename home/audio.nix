{ pkgs, ... }:
{
  home.packages = with pkgs; [
    carla
    qpwgraph
    ardour
    pipewire.jack
    rnnoise-plugin.lv2
    lmms
    lsp-plugins
    show-midi
    audacious
    pavucontrol
    spotify
  ];

  home.file.".local/share/applications/ardour9.desktop".text = ''
    [Desktop Entry]
    Name=Ardour
    Comment=Ardour Digital Audio Workstation
    Exec=${pkgs.pipewire.jack}/bin/pw-jack ${pkgs.ardour}/bin/ardour9 /home/wonko/Default
    Icon=ardour9
    Terminal=false
    MimeType=application/x-ardour;
    Type=Application
    Categories=AudioVideo;Audio;AudioEditing;X-Recorders;X-Multitrack;X-Jack;
    StartupWMClass=Ardour
    X-NSM-Capable=true
    X-NSM-Exec=${pkgs.pipewire.jack}/bin/pw-jack ${pkgs.ardour}/bin/ardour9
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
