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
      type = "qsv";
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

  users.users.jellyfin.extraGroups = [
    "render"
    "video"
  ];
}
