{
  # Disko appends its rebooted VM to driver.machines, which is a computed copy
  # in this NixOS test driver. Register it in the backing list so cleanup stops
  # QEMU and its serial thread after the test.
  disko.tests.bootCommands = ''
    if machine not in driver.machines_qemu:
        driver.machines_qemu.append(machine)
  '';

  disko.devices = {
    disk.os = {
      device = "/dev/disk/by-id/nvme-eui.6479a741b05004c5";
      type = "disk";
      content = {
        type = "gpt";
        partitions = {
          ESP = {
            size = "1G";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = [
                "fmask=0022"
                "dmask=0022"
              ];
            };
          };
          swap = {
            size = "1G";
            content.type = "swap";
          };
          zfs = {
            size = "100%";
            content = {
              type = "zfs";
              pool = "zpool";
            };
          };
        };
      };
    };

    zpool.zpool = {
      type = "zpool";
      options.ashift = "12";
      rootFsOptions = {
        acltype = "posixacl";
        atime = "off";
        compression = "zstd";
        mountpoint = "none";
        xattr = "sa";
      };
      datasets = {
        root = {
          type = "zfs_fs";
          mountpoint = "/";
          options.mountpoint = "legacy";
        };
        nix = {
          type = "zfs_fs";
          mountpoint = "/nix";
          options.mountpoint = "legacy";
        };
        var = {
          type = "zfs_fs";
          mountpoint = "/var";
        };
        docker = {
          type = "zfs_fs";
          mountpoint = "/var/lib/docker";
        };
        plex = {
          type = "zfs_fs";
          mountpoint = "/var/lib/plexmediaserver";
          options.recordsize = "16K";
        };
        home = {
          type = "zfs_fs";
          mountpoint = "/home";
        };
        postgres = {
          type = "zfs_fs";
          mountpoint = "/home/docker/pgsql";
          options.recordsize = "16K";
        };
      };
    };
  };

  # OpenZFS owns the native mountpoints; disko still creates them.
  fileSystems = {
    "/var".enable = false;
    "/var/lib/docker".enable = false;
    "/var/lib/plexmediaserver".enable = false;
    "/home".enable = false;
    "/home/docker/pgsql".enable = false;
  };
}
