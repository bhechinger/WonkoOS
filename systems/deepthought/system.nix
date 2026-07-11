{
  pkgs,
  inputs,
  ...
}:

let
  hugepages = import ../../common/hugepages.nix (import ./hugepages-inputs.nix);
  legacyPkgs = import inputs.linux_7_0 {
    system = pkgs.stdenv.hostPlatform.system;
    config.allowUnfree = true;
  };
in
{
  boot = {
    loader = {
      systemd-boot = {
        enable = true;
        memtest86.enable = true;
      };
      efi.canTouchEfiVariables = true;
    };
    initrd = {
      availableKernelModules = [
        "ahci"
        "xhci_pci"
        "virtio_pci"
        "sr_mod"
        "virtio_blk"
        "firewire_ohci"
        "firewire_core"
      ];
      kernelModules = [
        "ahci"
        "xhci_pci"
        "virtio_pci"
        "sr_mod"
        "virtio_blk"
        "firewire_ohci"
        "firewire_core"
      ];
      luks.mitigateDMAAttacks = false;
    };
    supportedFilesystems = [ "nfs" ];
    kernel = {
      inherit (hugepages) sysctl;
    };
    kernelParams = [
      "mitigations=off"
      "preempt=full"
      "nohz_full=all"
    ];
    kernelModules = [
      "kvm-amd"
      "firewire-ohci"
    ];
    blacklistedKernelModules = [
      "snd_fireworks"
    ];
    extraModprobeConfig = ''
      options firewire-ohci quirks=0x14
    '';
    extraModulePackages = [ ];
    # kernelPackages = pkgs.linuxPackages_xanmod_latest;
    # kernelPackages = pkgs.linuxPackages_6_18;
    # 7.0 is EOL; pinned solely until ZFS supports a maintained 7.x kernel.
    kernelPackages = legacyPkgs.linuxPackages_7_0;
    zfs = {
      package = legacyPkgs.zfs_2_4;
      forceImportRoot = false;
      extraPools = [
        "zpool"
        "tank"
      ];
      devNodes = "/dev/disk/by-partuuid";
    };
  };

  time.timeZone = "Europe/Lisbon";

  i18n = {
    defaultLocale = "en_US.UTF-8";
    extraLocaleSettings = {
      LC_ADDRESS = "pt_PT.UTF-8";
      LC_IDENTIFICATION = "pt_PT.UTF-8";
      LC_MEASUREMENT = "pt_PT.UTF-8";
      LC_MONETARY = "pt_PT.UTF-8";
      LC_NAME = "pt_PT.UTF-8";
      LC_NUMERIC = "pt_PT.UTF-8";
      LC_PAPER = "pt_PT.UTF-8";
      LC_TELEPHONE = "pt_PT.UTF-8";
      LC_TIME = "pt_PT.UTF-8";
    };
  };

  zramSwap.enable = true;

  nix = {
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      trusted-users = [
        "root"
        "wonko"
        "@wheel"
      ];
      substituters = [
        "https://install.determinate.systems"
      ];
      trusted-substituters = [
        "https://install.determinate.systems"
      ];
      trusted-public-keys = [
        "cache.flakehub.com-3:hJuILl5sVK4iKm86JzgdXW12Y2Hwd5G07qKtHTOcDCM="
      ];
    };
  };

  nixpkgs.config.allowUnfree = true;

  environment = {
    variables.EDITOR = "nvim";
    sessionVariables = {
      #WLR_NO_HARDWARE_CURSORS = "1";
      NIXOS_OZONE_WL = "1";
    };
    etc = {
      "fuse.conf" = {
        text = ''
          # add user_allow_other for s3fs
          user_allow_other
        '';
        mode = "0644";
      };
    };
  };

  system.stateVersion = "25.05";
}
