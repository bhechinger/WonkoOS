{ inputs, config, lib, pkgs, ... }:

{
  # Load nvidia driver for Xorg and Wayland
  services.xserver.videoDrivers = ["nvidia"];


  hardware = {
    graphics = {
      enable = true;
      enable32Bit = true;
    };

    nvidia = {
      modesetting.enable = true;
      powerManagement.enable = false;
      powerManagement.finegrained = false;

      # Use the NVidia open source kernel module (not to be confused with the
      # independent third-party "nouveau" open source driver).
      # Support is limited to the Turing and later architectures. Full list of
      # supported GPUs is at:
      # https://github.com/NVIDIA/open-gpu-kernel-modules#compatible-gpus
      # Only available from driver 515.43.04+
      # Currently alpha-quality/buggy, so false is currently the recommended setting.
      open = true;

      nvidiaSettings = true;

      #package = config.boot.kernelPackages.nvidiaPackages.beta;
      package = config.boot.kernelPackages.nvidiaPackages.mkDriver {
        version = "595.58.03";
        sha256_64bit = "sha256-jA1Plnt5MsSrVxQnKu6BAzkrCnAskq+lVRdtNiBYKfk=";
        sha256_aarch64 = "sha256-hzzIKY1Te8QkCBWR+H5k1FB/HK1UgGhai6cl3wEaPT8=";
        openSha256 = "sha256-6LvJyT0cMXGS290Dh8hd9rc+nYZqBzDIlItOFk8S4n8=";
        settingsSha256 = "sha256-2vLF5Evl2D6tRQJo0uUyY3tpWqjvJQ0/Rpxan3NOD3c=";
        persistencedSha256 = "sha256-AtjM/ml/ngZil8DMYNH+P111ohuk9mWw5t4z7CHjPWw=";
      };
    };

    sane = {
      enable = true;
      extraBackends = [ pkgs.hplipWithPlugin ];
      disabledDefaultBackends = [ "escl" "v4l" ];
    };
  };
}
