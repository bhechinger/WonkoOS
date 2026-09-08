{ inputs, ... }:

{
  imports = [
    inputs.determinate.homeManagerModules.default
    inputs.spotify-midi-control.homeManagerModules.default
    ../common
    ./zsh.nix
    ./atuin.nix
    ./audio.nix
    ./development.nix
    ./greptile.nix
    ./kubernetes.nix
    ./software.nix
    ./desktop.nix
    ./nix_tools.nix
    ./zenith.nix
    ./games.nix
    ./gamedev.nix
  ];

  home.homeDirectory = "/home/wonko";
}
