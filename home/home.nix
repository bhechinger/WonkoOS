{ ... }:
let
  username = "wonko";
in
{
  home = {
    inherit username;
    homeDirectory = "/home/${username}";

    stateVersion = "25.11";
  };

  manual.manpages.enable = false;
}
