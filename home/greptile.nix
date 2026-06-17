{ pkgs, ... }:

let
  # Greptile is distributed as a pre-built JavaScript bundle. The fixed-output
  # hash pins the trusted release artifact, but the wrapper runs it with normal
  # user-session filesystem and network access.
  greptileJs = pkgs.fetchurl {
    url = "https://github.com/greptileai/cli/releases/download/v3.1.1/greptile.js";
    hash = "sha256-uDdlopk8n43t9C559zoxcq3XDyCmUE0vLww27Kr40LU=";
  };

  greptile = pkgs.writeShellApplication {
    name = "greptile";
    runtimeInputs = [ pkgs.nodejs_22 ];
    text = ''
      exec node ${greptileJs} "$@"
    '';
  };
in
{
  home.packages = [ greptile ];
}
