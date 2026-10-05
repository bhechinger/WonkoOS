_:

{
  virtualisation = {
    containers.enable = true;
    docker = {
      autoPrune = {
        enable = true;
        flags = [
          "--all"
        ];
      };
      enable = true;
      storageDriver = "zfs";
      daemon.settings."log-driver" = "json-file";
    };
    podman = {
      enable = true;
    };
    libvirtd = {
      enable = true;
      qemu = {
        swtpm.enable = true;
      };
    };
    spiceUSBRedirection.enable = true;
  };
}
