#{ disks ? [ "/dev/nvme0n1" ], ... }: {
{ disks ? [ "/dev/vda" ], ... }: {
  disko.devices = {
    disk = {
      one = {
        type = "disk";
        device = builtins.elemAt disks 0;
        content = {
          type = "table";
          format = "gpt";
          partitions = [
            {
              name = "boot";
              start = "0";
              end = "100M";
              fs-type = "fat32";
              bootable = true;
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
              };
            }
            {
              name = "primary";
              start = "100M";
              end = "100%";
              content = {
                type = "lvm_pv";
                vg = "pool";
              };
            }
          ];
        };
      };
    };
    lvm_vg = {
      pool = {
        type = "lvm_vg";
        lvs = {
          root = {
            size = "150M";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
              mountOptions = [
                "defaults"
              ];
            };
          };
          sierra = {
            size = "50G";
          };
        };
      };
    };
  };
}