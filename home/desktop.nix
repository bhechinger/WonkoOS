{ pkgs, ... }:
let
  browser = "firefox";
  terminal = "kitty";
in
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
    ];

    pointerCursor = {
      package = pkgs.bibata-cursors;
      name = "Bibata-Modern-Ice";
      size = 24;
    };
  };

  systemd.user.targets.hyprland-session.Unit.Wants = [
    "xdg-desktop-autostart.target"
  ];
 }
