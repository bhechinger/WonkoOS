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
}
