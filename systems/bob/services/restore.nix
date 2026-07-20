{ config, pkgs, ... }:

let
  bobRestore = pkgs.writeShellApplication {
    name = "bob-restore";
    runtimeInputs = with pkgs; [
      coreutils
      docker
      findutils
      gnugrep
      gnused
      rsync
      config.services.postgresql.package
      systemd
      util-linux
    ];
    text = builtins.readFile ../restore.sh;
  };
in
{
  environment.systemPackages = [ bobRestore ];
}
