{
  pkgs,
  config,
  ...
}:

let
  qnap = pkgs.rustPlatform.buildRustPackage rec {
    pname = "qnap";
    version = "0.1.12";
    src = pkgs.fetchFromGitHub {
      owner = "rvben";
      repo = "qnap-cli";
      tag = "v${version}";
      hash = "sha256-Xz75WZeztKHhs3PYsUu38fRBY2YsgCBbml1Lv9yCbfI=";
    };
    cargoHash = "sha256-DKtJ8IPCYq3fOdHZCcpl2mxMKCRho9AmiTol0egpyc8=";
    env.NO_COLOR = "1";
  };
in
{
  home.packages = with pkgs; [
    ncdu
    xlsclients
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
    vlc
    telegram-desktop
    signal-desktop
    discord
    slack
    age
    sops
    gimp
    inxi
    mesa-demos
    whatsie
    qnap
  ];

  programs = {
    firefox = {
      enable = true;
      configPath = "${config.xdg.configHome}/mozilla/firefox";
      policies.Preferences."media.setsinkid.enabled" = {
        Value = false;
        Status = "locked";
      };
      policies.SearchEngines.Default = "DuckDuckGo";
    };
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
