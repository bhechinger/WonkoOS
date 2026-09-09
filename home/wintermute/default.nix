{
  config,
  lib,
  pkgs,
  ...
}:

{
  imports = [
    ../common
    ./software.nix
  ];

  home.homeDirectory = "/Users/wonko";
  home.packages = [ pkgs.kitty ];
  home.file.".terminfo".source = "${pkgs.kitty.terminfo}/share/terminfo";
  launchd.agents.sops-nix.config = {
    StandardOutPath = lib.mkForce "${config.home.homeDirectory}/Library/Logs/sops-nix.stdout.log";
    StandardErrorPath = lib.mkForce "${config.home.homeDirectory}/Library/Logs/sops-nix.stderr.log";
  };
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
