{ inputs, ... }:

{
  imports = [
    inputs.determinate.nixosModules.default
    inputs.musnix.nixosModules.musnix
    inputs.disko.nixosModules.disko
    inputs.sops-nix.nixosModules.sops

    ../hardware/deepthought.nix
    #./zfs.nix
    ./networking.nix
    ./users.nix
    ./filesystems.nix
    ./software.nix
    ./services.nix
    ./system.nix
    ./virtualization.nix
    ./hardware.nix
    ./desktop.nix
    ./postgresql.nix
    ./atuin.nix
    ./audio.nix
    ./vpns.nix
  ];
}
