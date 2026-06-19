{
  pkgs,
  lib,
  ...
}:

let
  jackSampleRate = 48000;
  jackPeriodSize = 2048;
  jackPeriods = 3;
  jackRealtimePriority = 88;
in
{
  musnix = {
    enable = true;
    ffado.enable = true;
    soundcardPciId = "06:00.0";
    rtcqs.enable = true;
    rtirq = {
      resetAll = 1;
      prioLow = 0;
      enable = true;
      highList = "firewire_ohci";
      nameList = "rtc0";
    };
  };

  services = {
    pipewire = {
      enable = false;
      audio.enable = false;
      wireplumber.enable = false;
      alsa.enable = false;
      pulse.enable = false;
      jack.enable = false;
    };

    jack = {
      jackd = {
        enable = true;
        extraOptions = [
          "-R"
          "-P"
          (toString jackRealtimePriority)
          "-dfirewire"
          "-v"
          "6"
          "-r"
          (toString jackSampleRate)
          "-p"
          (toString jackPeriodSize)
          "-n"
          (toString jackPeriods)
        ];
        session = lib.mkForce "";
      };
      alsa.enable = false;
      loopback.enable = false;
    };
  };

  systemd.services.jack = {
    after = [ "rtirq.service" ];
    wants = [ "rtirq.service" ];
    wantedBy = [ "multi-user.target" ];
  };

  systemd.services.rtirq.after = lib.mkForce [ "sysinit.target" ];

  systemd.services."user@".serviceConfig = {
    LimitMEMLOCK = "infinity";
    LimitRTPRIO = 95;
    LimitNICE = "-11";
    RestrictRealtime = false;
  };

  environment.systemPackages = with pkgs; [
    alsa-utils
    ffado
    ffado-mixer
    jack2
    jack-example-tools
    qjackctl
  ];
}
