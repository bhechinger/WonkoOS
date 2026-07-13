{ lib, pkgs, ... }:
{
  imports = [
    ./hyprland.nix
    ./waybar.nix
    ./hyprlock.nix
    ./coolercontrol.nix
  ];

  home = {
    packages =
      with pkgs;
      [
        grimblast
        hyprcursor
        hyprpicker
        hyprsysteminfo
        hyprsunset
        hyprland-qt-support
        hyprpwcenter
        hyprshutdown
        hyprutils
        grim
        slurp
        cliphist
        wf-recorder
        glib
        wayland
        wofi
        bibata-cursors
        system-config-printer
        yubioath-flutter

        fira-code
        fira-code-symbols
        font-awesome
        liberation_ttf
        mplus-outline-fonts.githubRelease
        noto-fonts
        noto-fonts-cjk-sans
        noto-fonts-color-emoji
        proggyfonts
        libnotify
      ]
      ++ builtins.filter lib.attrsets.isDerivation (builtins.attrValues pkgs.nerd-fonts);

    pointerCursor = {
      package = pkgs.bibata-cursors;
      name = "Bibata-Modern-Ice";
      size = 24;
    };
  };

  services = {
    hyprpolkitagent.enable = true;
    kdeconnect = {
      enable = true;
      indicator = true;
    };
    pass-secret-service.enable = true;
    mako.enable = true;
    awww.enable = true;
    wl-clip-persist = {
      enable = true;
      clipboardType = "both";
      systemdTargets = [ "hyprland-session.target" ];
    };
  };

  programs.password-store.enable = true;

  fonts.fontconfig.enable = true;

  systemd.user.services.pass-secret-service.Install.Alias = [
    "dbus-org.freedesktop.secrets.service"
  ];
}
