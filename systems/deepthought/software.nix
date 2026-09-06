{
  pkgs,
  unstable-pkgs,
  ...
}:

{

  environment = {
    systemPackages = with pkgs; [
      pkg-config
      mokutil
      vulkan-tools
      dxvk
      home-manager
      i2c-tools
      inetutils
      nix-top
      nvme-cli
      zsh-nix-shell
      nixfmt
      pciutils
      usbutils
      lshw
      spaceship-prompt
      fuse
      fzf
      gnupg
      man
      screen
      sedutil
      jq
      yq
      openssl
      wget
      backblaze-b2
      rclone
      nfs-utils
      lsof
      file
      ripgrep
      gnumake
      btop
      kitty
      zsh-autocomplete
    ];
  };

  programs = {
    gamemode.enable = true;
    gamescope = {
      enable = true;
      args = [
        "-f"
        "-W 2560"
        "-H 1440"
        "--mangoapp"
        "--adaptive-sync"
        "--rt"
      ];
    };
    extra-container.enable = true;
    htop.enable = true;
    iotop.enable = true;
    less.enable = true;
    starship.enable = true;
    traceroute.enable = true;
    usbtop.enable = true;
    wireshark = {
      enable = true;
      package = pkgs.wireshark;
    };
    thunderbird.enable = true;
    mosh.enable = true;
    tmux.enable = true;
    dconf.enable = true; # virt-manager requires dconf to remember settings
    virt-manager.enable = true;

    steam = {
      enable = true;
      protontricks.enable = true;
      extraCompatPackages = [ unstable-pkgs.proton-ge-bin ];
    };

    nix-ld = {
      enable = true;
    };

    neovim = {
      enable = true;
      defaultEditor = true;
      vimAlias = true;
      viAlias = true;
    };

    gnupg.agent = {
      enable = true;
      enableSSHSupport = true;
      pinentryPackage = pkgs.pinentry-gnome3;
    };

    zsh = {
      enable = true;
    };

    nh = {
      enable = true;
      clean.enable = true;
      clean.extraArgs = "--keep-since 4d --keep 3";
      flake = "/home/wonko/nix/WonkoOS";
    };
  };
}
