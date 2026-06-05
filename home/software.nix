{
  pkgs,
  config,
  ...
}:

{
  home.packages = with pkgs; [
    fastfetch
    mtr-gui
    rar
    p7zip
    qbittorrent
    irccloud
    dig
    kdePackages.qtsvg
    kdePackages.dolphin
    unzip
    irssi
    wine64
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
    poweralertd
    wl-clip-persist
    telegram-desktop
    signal-desktop
    discord
    slack
    age
    bubblewrap
    sops
    gimp
  ];

  programs = {
    firefox = {
      enable = true;
      configPath = "${config.xdg.configHome}/mozilla/firefox";
      policies.SearchEngines.Default = "DuckDuckGo";
    };
    # thunderbird.enable = true; # This is weird here, need to try again
    chromium.enable = true;
    obs-studio.enable = true;
    hyprshot = {
      enable = true;
      saveLocation = "$HOME/Pictures/Screenshots";
    };
  };

  services = {
    dropbox.enable = true;
  };
}
