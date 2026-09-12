{
  pkgs,
  ...
}:

let
  hugepages = import ../../common/hugepages.nix (import ./hugepages-inputs.nix);
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
        "vfio_pci"
        "firewire_core"
      ];
      systemd.services.bind-audiofire-vfio = {
        description = "Bind AudioFire FireWire controller to VFIO";
        wantedBy = [ "sysinit.target" ];
        before = [ "systemd-udev-trigger.service" ];
        after = [ "systemd-modules-load.service" ];
        unitConfig.DefaultDependencies = false;
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        # Both FireWire controllers have the same PCI ID, so isolate the
        # AudioFire controller by its stable slot before udev loads firewire_ohci.
        script = ''
          if [ -d /sys/bus/pci/devices/0000:06:00.0 ]; then
            echo vfio-pci > /sys/bus/pci/devices/0000:06:00.0/driver_override
            echo 0000:06:00.0 > /sys/bus/pci/drivers_probe
          fi
        '';
      };
      luks.mitigateDMAAttacks = false;
    };
    supportedFilesystems = [ "nfs" ];
    kernel = {
      inherit (hugepages) sysctl;
    };
    kernelParams = [
      "amd_iommu=on"
      "iommu=pt"
      "mitigations=off"
      "preempt=full"
      "nohz_full=all"
    ];
    kernelModules = [
      "kvm-amd"
      "firewire-ohci"
    ];
    extraModprobeConfig = ''
      options firewire-ohci quirks=0x14
    '';
    extraModulePackages = [ ];
    # kernelPackages = pkgs.linuxPackages_xanmod_latest;
    # kernelPackages = pkgs.linuxPackages_6_18;
    kernelPackages = pkgs.linuxPackages_7_2;
    zfs = {
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
