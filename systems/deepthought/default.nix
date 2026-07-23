{ inputs, ... }:

{
  imports = [
    inputs.determinate.nixosModules.default
    inputs.musnix.nixosModules.musnix
    inputs.disko.nixosModules.disko
    inputs.sops-nix.nixosModules.sops

    ../../common/nix-cache-client.nix
    ../hardware/deepthought.nix
    ./zfs.nix
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
    ./restic.nix
    ./atuin.nix
    ./audio.nix
  ];
}
