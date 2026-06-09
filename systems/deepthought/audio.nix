{
  inputs,
  config,
  lib,
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
      wireplumber.extraConfig."51-saffire-headroom" = {
        "monitor.alsa.rules" = [
          {
            matches = [
              {
                "node.name" = "~alsa_(input|output).firewire-0x00130e0401c04de0.*";
              }
            ];
            actions.update-props = {
              "api.alsa.headroom" = 1024;
            };
          }
        ];
      };
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

  environment.systemPackages = with pkgs; [
    alsa-utils
    alsa-lib
    pulseaudioFull
  ];
}
