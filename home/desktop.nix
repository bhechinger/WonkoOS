{ lib, pkgs, ... }:
{
  imports = [
    ./hyprland.nix
    ./waybar.nix
    ./hyprlock.nix
  ];

  home = {
    packages =
      with pkgs;
      [
        awww
        grimblast
        hyprpicker
        grim
        slurp
        wl-clip-persist
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
    kdeconnect = {
      enable = true;
      indicator = true;
    };
    pass-secret-service.enable = true;
    mako.enable = true;
  };

  programs.password-store.enable = true;

  fonts.fontconfig.enable = true;

  systemd.user.targets.hyprland-session.Unit.Wants = [
    "xdg-desktop-autostart.target"
  ];

  systemd.user.services.pass-secret-service.Install.Alias = [
    "dbus-org.freedesktop.secrets.service"
  ];
}
