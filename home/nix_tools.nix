{ pkgs, unstable-pkgs, ... }:

{
  home.packages = with pkgs; [
    nix-tree
    nix-top
    nix-web
    nixos-shell
    nix-index
    vulnix
    nurl
    nix-init
    statix
  ];

  programs = {
    direnv = {
      enable = true;
      nix-direnv.enable = true;
    };
  };
}
