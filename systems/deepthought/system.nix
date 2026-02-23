{ inputs, config, lib, pkgs, ... }:

{
  nix = {
    settings.experimental-features = [ "nix-command" "flakes" ];
  };

  boot = {
    loader = {
      grub.memtest86.enable = true;
      grub.extraConfig = ''
        GRUB_CMDLINE_LINUX_DEFAULT=""
      '';
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };
    initrd = {
      availableKernelModules = [ "ahci" "xhci_pci" "virtio_pci" "sr_mod" "virtio_blk" "firewire_ohci" "firewire_core" ];
      kernelModules = [ "ahci" "xhci_pci" "virtio_pci" "sr_mod" "virtio_blk" "firewire_ohci" "firewire_core" ];
      luks.mitigateDMAAttacks = false;
    };
    supportedFilesystems = [ "nfs" ];
    kernelParams = [ "mitigations=off" "preempt=full" "nohz_full=all" "threadirqs" ];
    kernelModules = [ "kvm-amd" ];
    extraModulePackages = [ ];
    # kernelPackages = pkgs.linuxPackages_xanmod_latest;
    kernelPackages = pkgs.linuxPackages_6_16;
    zfs = {
      extraPools = [ "zpool" "tank" ];
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
    #gc = {
    #  automatic = true;
    #  options = "--delete-older-than 7d";
    #};
    settings = {
      substituters = [
        "https://hyprland.cachix.org"
        "https://install.determinate.systems"
      ];
      trusted-substituters = [
        "https://hyprland.cachix.org"
        "https://install.determinate.systems"
      ];
      trusted-public-keys = [
        "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
        "cache.flakehub.com-3:hJuILl5sVK4iKm86JzgdXW12Y2Hwd5G07qKtHTOcDCM="
      ];
    };
  };

  nixpkgs.config = {
    allowUnfree = true;
    permittedInsecurePackages = [
     "electron-25.9.0"
    ];
    packageOverrides = pkgs: {
      xsaneGimp = pkgs.xsane.override { gimpSupport = true; };
    };
  };

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
