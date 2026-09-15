{
  pkgs,
  unstable-pkgs,
  ...
}:
let
  audioPipewire = unstable-pkgs.pipewire.override { ffadoSupport = false; };
in
{
  security.rtkit.enable = true;

  musnix = {
    enable = true;
    soundcardPciId = "07:00.0";
    rtcqs.enable = true;
    rtirq = {
      resetAll = 1;
      prioLow = 0;
      enable = true;
      nameList = "rtc0 firewire_ohci";
    };
  };

  boot.blacklistedKernelModules = [ "snd_fireworks" ];

  services = {
    pipewire = {
      enable = true;
      package = audioPipewire;
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
              "api.alsa.period-size" = 1024;
              "api.alsa.period-num" = 3;
              "api.alsa.headroom" = 1024;
            };
          }
          {
            matches = [
              {
                "node.name" = "alsa_input.firewire-0x00130e0401c04de0.multichannel-input";
              }
            ];
            actions.update-props."audio.position" = [
              "AUX0"
              "AUX1"
              "AUX2"
              "AUX3"
              "AUX4"
              "AUX5"
              "AUX6"
              "AUX7"
              "AUX8"
              "AUX9"
              "AUX10"
              "AUX11"
              "AUX12"
              "AUX13"
              "AUX14"
              "AUX15"
            ];
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
