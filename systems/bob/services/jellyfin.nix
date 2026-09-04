{ pkgs, ... }:

{
  hardware.graphics.extraPackages = with pkgs; [
    intel-compute-runtime-legacy1
    intel-media-driver
  ];

  services.jellyfin = {
    enable = true;
    forceEncodingConfig = true;
    openFirewall = false;
    hardwareAcceleration = {
      enable = true;
      device = "/dev/dri/renderD128";
      type = "vaapi";
    };
    transcoding = {
      enableHardwareEncoding = true;
      hardwareDecodingCodecs = {
        h264 = true;
        hevc = true;
        hevc10bit = true;
        mpeg2 = true;
        vc1 = true;
        vp8 = true;
        vp9 = true;
      };
      hardwareEncodingCodecs.hevc = true;
    };
  };

  systemd.services.jellyfin.environment.JELLYFIN_PublishedServerUrl = "https://jellyfin.4amlunch.net";

  users.users.jellyfin.extraGroups = [
    "render"
    "video"
  ];
}
