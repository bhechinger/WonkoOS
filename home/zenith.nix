{ auto-splice, pkgs, ... }:

{
  home.packages = [
    auto-splice.packages.${pkgs.system}.auto-splice
  ];
}
