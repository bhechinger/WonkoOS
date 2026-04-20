{ pkgs, unstable-pkgs, ... }:

{
  home.packages = with pkgs; [
    rar
    p7zip
    codex
    unstable-pkgs.mame
    qbittorrent
    irccloud
    dig
    kdePackages.qtsvg
    kdePackages.dolphin
    unzip
    irssi
    wine64
    blockbench
    kdePackages.bluedevil
    #coolercontrol.coolercontrol-liqctld
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
    hyprshot
    poweralertd
    wl-clip-persist
    swww
    r2modman
    telegram-desktop
    signal-desktop
    discord
    slack
    prismlauncher
    #temurin-bin
    javaPackages.compiler.temurin-bin.jdk-25
    mcpelauncher-ui-qt
  ];

  programs = {
    firefox.enable = true;
    # thunderbird.enable = true; # This is weird here, need to try again
    chromium.enable = true;
    obs-studio.enable = true;
    mangohud = {
      enable = true;
      enableSessionWide = true;
      settings = {
        full = true;
	vsync = 0;
	no_display = true;
      };
    };
  };

  services = {
    dropbox.enable = true;
  };
}
