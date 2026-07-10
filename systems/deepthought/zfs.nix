{
  disko.devices = {
    disk = {
      os = {
        device = "/dev/disk/by-id/nvme-WDC_WDS100T2B0C-00PXH0_21281Y459408";
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
              size = "8G";
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
      tank = {
        device = "/dev/disk/by-id/nvme-WDS200T1XHE-00AFY0_21143L800578";
        type = "disk";
        content = {
          type = "zfs";
          pool = "tank";
        };
      };
    };
    zpool = {
      zpool = {
        type = "zpool";
        options.ashift = "12";
        rootFsOptions = {
          compression = "zstd";
          mountpoint = "none";
          xattr = "sa";
          acltype = "posixacl";
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
        };
      };
      tank = {
        type = "zpool";
        options.ashift = "12";
        rootFsOptions = {
          compression = "on";
          mountpoint = "none";
          xattr = "sa";
          acltype = "posixacl";
        };
        datasets.home = {
          type = "zfs_fs";
          mountpoint = "/home";
        };
      };
    };
  };
}
