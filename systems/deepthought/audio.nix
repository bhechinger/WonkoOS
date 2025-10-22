{ inputs, config, lib, pkgs, ... }:

{
  security.rtkit.enable = true;

  musnix = {
    enable = true;
    ffado.enable = true;
    soundcardPciId = "08:00.0";
    #kernel = {
    #    realtime = true;
    #    packages = pkgs.linuxPackages_6_8_rt;
    #};
    rtcqs.enable = true;
    rtirq = {
      resetAll = 1;
      prioLow = 0;
      enable = true;
      nameList = "rtc0 firewire_ohci";
    };
  };

  services = {
    pipewire = {
      enable = true;
      audio.enable = true;
      wireplumber.enable = true;
      alsa = {
        enable = true;
        support32Bit = true;
      };
      pulse.enable = true;
      jack.enable = true;
      socketActivation = true;
    };
  };

  environment.systemPackages = with pkgs; [
    ffado
    alsa-utils
    ardour
    spotify
    alsa-lib
    libjack2
    jack2
    qjackctl
    pavucontrol
    jack_capture
    pulseaudioFull
    audacious
    qpwgraph
    show-midi
    #mopidy
    #mopidy-bandcamp
    #mopidy-iris
    #mopidy-notify
    #mopidy-spotify
    #mopidy-soundcloud
    lmms
    lsp-plugins
  ];
}
