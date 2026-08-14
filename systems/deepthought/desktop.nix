{ unstable-pkgs, ... }:
{
  programs = {
    hyprland = {
      enable = true;
      package = unstable-pkgs.hyprland;
      portalPackage = unstable-pkgs.xdg-desktop-portal-hyprland;
      withUWSM = true;
      xwayland.enable = true;
    };
    # The NixOS kdeconnect module opens the required TCP/UDP 1714-1764
    # firewall ranges when enabled.
    kdeconnect.enable = true;
    evince.enable = true;
  };
}
