{
  inputs,
  config,
  lib,
  pkgs,
  ...
}:

{
  virtualisation = {
    containers.enable = true;
    docker = {
      autoPrune.enable = true;
      enable = true;
      #enableNvidia = true;
      storageDriver = "zfs";
    };
    podman.enable = true;
    libvirtd = {
      enable = true;
      qemu = {
        swtpm.enable = true;
      };
    };
    spiceUSBRedirection.enable = true;
    #waydroid.enable = true;
  };
}
