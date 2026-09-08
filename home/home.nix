{ pkgs, ... }:
let
  username = "wonko";
in
{
  home = {
    inherit username;
    homeDirectory = if pkgs.stdenv.isDarwin then "/Users/${username}" else "/home/${username}";

    stateVersion = "25.11";
  };

  manual.manpages.enable = false;
}
