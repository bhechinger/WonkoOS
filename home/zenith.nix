{ auto-splice, pkgs, ... }:

{
  home.packages = [
    auto-splice.packages.${pkgs.stdenv.hostPlatform.system}.auto-splice
  ];
}
