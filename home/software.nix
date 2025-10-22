{ pkgs, ... }:

{
  home.packages = with pkgs; [
    blockbench
    kdePackages.bluedevil
    coolercontrol.coolercontrol-liqctld
    coolercontrol.coolercontrold
    droidcam
    fluxcd
    fractal
    i2c-tools
    inetutils
    inkscape
    krename
    krita
    azahar
    mindustry
    nix-top
    nix-web
    nixos-shell
    nvme-cli
    obexftp
    openobex
    orca
    pinentry-all
    sslscan
    #usbip-linux
    #usbmuxd2-unstable
    #ventoy
    vlc
    vulnix
    hyprshot
    poweralertd
    wl-clip-persist
    swww
    r2modman
    qpwgraph
    ardour
    telegram-desktop
    signal-desktop
    discord
    slack
    prismlauncher
    gamescope
  ];

  programs = {
    firefox.enable = true;
    # thunderbird.enable = true; # This is weird here, need to try again
    chromium.enable = true;
    obs-studio.enable = true;
  };
}
