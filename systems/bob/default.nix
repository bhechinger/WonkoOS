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
    ../../common/nix-cache-client.nix
    ./disko.nix
    ./networking.nix
    ./services
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
    config.allowUnfreePredicate =
      pkg:
      builtins.elem (lib.getName pkg) [
        "mongodb"
        "neoforge"
        "plexmediaserver"
        "unifi-controller"
      ];
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

  sops = {
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    useSystemdActivation = true;
  };

  users = {
    mutableUsers = false;
    users.wonko = {
      description = "Brian Hechinger";
      extraGroups = [ "wheel" ];
      isNormalUser = true;
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
  swapDevices = lib.mkForce [
    {
      device = "/dev/disk/by-partuuid/1ad95369-76dd-45cb-bf83-e84637ff25de";
      randomEncryption.enable = true;
    }
  ];
  zramSwap.enable = true;

  system.stateVersion = "26.05";
}
