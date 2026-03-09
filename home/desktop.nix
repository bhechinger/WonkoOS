{ pkgs, ... }:
{
  imports = [
    ./hyprland.nix
    ./waybar.nix
    ./hyprlock.nix
  ];

  home = {
    packages = with pkgs; [
      swww
      grimblast
      hyprpicker
      grim
      slurp
      wl-clip-persist
      cliphist
      wf-recorder
      glib
      wayland
      direnv
      wofi
      bibata-cursors

      fira-code
      fira-code-symbols
      font-awesome
      liberation_ttf
      mplus-outline-fonts.githubRelease
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-color-emoji
      proggyfonts
    ] ++ builtins.filter lib.attrsets.isDerivation (builtins.attrValues pkgs.nerd-fonts);

    pointerCursor = {
      package = pkgs.bibata-cursors;
      name = "Bibata-Modern-Ice";
      size = 24;
    };
  };

  fonts.fontconfig.enable = true;

  systemd.user.targets.hyprland-session.Unit.Wants = [
    "xdg-desktop-autostart.target"
  ];
 }
