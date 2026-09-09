{ config, pkgs, ... }:

{
  imports = [
    ../common
    ./software.nix
  ];

  home.homeDirectory = "/Users/wonko";
  home.packages = [ pkgs.kitty ];
  home.file.".terminfo".source = "${pkgs.kitty.terminfo}/share/terminfo";
  programs.home-manager.enable = true;

  sops = {
    age.keyFile = "${config.home.homeDirectory}/Library/Application Support/sops/age/keys.txt";
    secrets.omnigraph-credentials = {
      sopsFile = ./secrets/omnigraph-credentials.sops;
      format = "binary";
      path = "${config.home.homeDirectory}/.omnigraph/credentials";
      mode = "0600";
    };
  };
}
