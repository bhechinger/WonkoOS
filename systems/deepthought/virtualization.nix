{ inputs, config, lib, pkgs, ... }:

{
  virtualisation = {
    containers.enable = true;
    multipass.enable = true;
    docker = {
        autoPrune.enable = true;
        enable = true;
        #enableNvidia = true;
        storageDriver = "zfs";
    };
    libvirtd = {
      enable = true;
      qemu = {
        swtpm.enable = true;
        ovmf = {
          enable = true;
	        packages = [ pkgs.OVMFFull.fd ];
        };
      };
    };
    spiceUSBRedirection.enable = true;
    #waydroid.enable = true;
  };
}
