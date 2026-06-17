{ pkgs, ... }:
{
  programs = {
    hyprland = {
      enable = true;
      withUWSM = true;
      xwayland.enable = true;
    };
    # The NixOS kdeconnect module opens the required TCP/UDP 1714-1764
    # firewall ranges when enabled.
    kdeconnect.enable = true;
    evince.enable = true;
  };

  xdg.portal = {
    enable = true;
    extraPortals = with pkgs; [ xdg-desktop-portal-hyprland ];
  };
}
