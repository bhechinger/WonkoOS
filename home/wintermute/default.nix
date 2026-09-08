{ pkgs, ... }:

{
  imports = [ ../common ];

  home.homeDirectory = "/Users/wonko";
  home.packages = [ pkgs.kitty ];
  home.file.".terminfo".source = "${pkgs.kitty.terminfo}/share/terminfo";
  programs.home-manager.enable = true;
}
