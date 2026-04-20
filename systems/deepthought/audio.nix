{ inputs, config, lib, pkgs, ... }:

{
  security.rtkit.enable = true;

  musnix = {
    enable = true;
    ffado.enable = true;
    soundcardPciId = "08:00.0";
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
    alsa-utils
    alsa-lib
    libjack2
    jack2
    jack_capture
    pulseaudioFull
  ];
}
