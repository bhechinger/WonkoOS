{
  pkgs,
  ...
}:

{
  security.rtkit.enable = true;

  musnix = {
    enable = true;
    ffado.enable = true;
    soundcardPciId = "06:00.0";
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

  systemd.user.services = {
    pipewire.serviceConfig = {
      LimitMEMLOCK = "infinity";
      LimitRTPRIO = 95;
      LimitNICE = "-11";
      RestrictRealtime = false;
    };
    pipewire-pulse.serviceConfig = {
      LimitMEMLOCK = "infinity";
      LimitRTPRIO = 95;
      LimitNICE = "-11";
      RestrictRealtime = false;
    };
    wireplumber.serviceConfig = {
      LimitMEMLOCK = "infinity";
      LimitRTPRIO = 95;
      LimitNICE = "-11";
      RestrictRealtime = false;
    };
  };

  systemd.services."user@".serviceConfig = {
    LimitMEMLOCK = "infinity";
    LimitRTPRIO = 95;
    LimitNICE = "-11";
    RestrictRealtime = false;
  };

  environment.systemPackages = with pkgs; [
    alsa-utils
    alsa-lib
    pulseaudioFull
  ];
}
