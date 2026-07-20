{
  config,
  inputs,
  lib,
  modulesPath,
  pkgs,
  ...
}:

let
  wonkoKeys = import ../../common/wonko-keys.nix;
  hugepages = import ../../common/hugepages.nix (import ./hugepages-inputs.nix);
in
{
  imports = [
    inputs.determinate.nixosModules.default
    inputs.disko.nixosModules.disko
    inputs.sops-nix.nixosModules.sops
    (modulesPath + "/installer/scan/not-detected.nix")
    ./disko.nix
    ./networking.nix
    ./services
    ./vm-test.nix
  ];

  boot = {
    initrd.availableKernelModules = [
      "ahci"
      "nvme"
      "sd_mod"
      "usb_storage"
      "xhci_pci"
    ];
    kernel = { inherit (hugepages) sysctl; };
    kernelModules = [ "kvm-intel" ];
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };
    supportedFilesystems = [ "nfs" ];
    zfs = {
      devNodes = lib.mkDefault "/dev/disk/by-partuuid";
      extraPools = [ "zpool" ];
      forceImportRoot = false;
    };
  };

  hardware = {
    cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
    enableRedistributableFirmware = true;
    graphics.enable = true;
  };

  nix = {
    settings = {
      experimental-features = [
        "flakes"
        "nix-command"
      ];
      trusted-users = [
        "root"
        "wonko"
        "@wheel"
      ];
    };
  };

  nixpkgs = {
    config.allowUnfree = true;
    hostPlatform = lib.mkDefault "x86_64-linux";
  };

  security.sudo.wheelNeedsPassword = false;

  programs.nh.enable = true;
  programs.vim = {
    enable = true;
    defaultEditor = true;
  };
  programs.zsh.enable = true;

  services = {
    openssh = {
      enable = true;
      settings = {
        KbdInteractiveAuthentication = false;
        PasswordAuthentication = false;
        PermitRootLogin = "no";
      };
    };
    zfs = {
      autoScrub.enable = true;
      trim.enable = true;
    };
  };

  users = {
    mutableUsers = false;
    users.wonko = {
      description = "Brian Hechinger";
      extraGroups = [
        "docker"
        "wheel"
      ];
      isNormalUser = true;
      linger = true;
      openssh.authorizedKeys.keys = wonkoKeys;
      shell = pkgs.zsh;
      uid = 1000;
    };
  };

  environment.systemPackages = with pkgs; [
    git
    gh
    gnumake
    kitty.terminfo
    rsync
    tmux
  ];

  i18n.defaultLocale = "en_US.UTF-8";
  time.timeZone = "Europe/Lisbon";
  zramSwap.enable = true;

  system.stateVersion = "26.05";
}
