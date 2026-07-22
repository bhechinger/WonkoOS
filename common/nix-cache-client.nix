{ lib, pkgs, ... }:

let
  endpoint = "https://cache.4amlunch.net/internal";
in
{
  environment.systemPackages = [ pkgs.attic-client ];

  nix.settings = {
    substituters = lib.mkAfter [ endpoint ];
    trusted-substituters = [ endpoint ];
    trusted-public-keys = [ "internal:71s87pJDYLG9Ruu6BxjTC4wZzxneZXqc2U3da6/C2PI=" ];
  };
}
