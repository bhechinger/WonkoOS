{ inputs, config, ... }:

{
  fileSystems."/" =
    { device = "zpool/root";
      fsType = "zfs";
      options = [ "zfsutil" ];
    };

  fileSystems."/nix" =
    { device = "zpool/nix";
      fsType = "zfs";
      options = [ "zfsutil" ];
    };

  fileSystems."/var" =
    { device = "zpool/var";
      fsType = "zfs";
      options = [ "zfsutil" ];
    };

  fileSystems."/home" =
    { device = "tank/home";
      fsType = "zfs";
      options = [ "zfsutil" ];
    };

  fileSystems."/boot" =
    { device = "/dev/disk/by-id/nvme-WDC_WDS100T2B0C-00PXH0_21281Y459408-part1";
      fsType = "vfat";
      options = [ "fmask=0022" "dmask=0022" ];
    };

  swapDevices = [{
    device = "/dev/disk/by-id/nvme-WDC_WDS100T2B0C-00PXH0_21281Y459408-part2";
  }];

  # NFS mounts
  #systemd.mounts = let commonMountOptions = {
  #  type = "nfs";
  #  mountConfig = {
  #    Options = "noatime";
  #  };
  #};
#
#  in
#
#  [
#    (commonMountOptions // {
#      what = "basket.4amlunch.net:/Brian";
#      where = "/mnt/Brian";
#    })
#
#    (commonMountOptions // {
#      what = "basket.4amlunch.net:/NetShare";
#      where = "/mnt/NetShare";
#    })
#
#    (commonMountOptions // {
#      what = "basket.4amlunch.net:/homes";
#      where = "/mnt/homes";
#    })
#
#    (commonMountOptions // {
#      what = "bob.4amlunch.net:/home/docker/paperless/consume";
#      where = "/mnt/paperless/consume";
#    })
#
#    (commonMountOptions // {
#      what = "bob.4amlunch.net:/home/docker/paperless/export";
#      where = "/mnt/paperless/export";
#    })
#  ];
#
#  systemd.automounts = let commonAutoMountOptions = {
#    wantedBy = [ "multi-user.target" ];
#    automountConfig = {
#      TimeoutIdleSec = "600";
#    };
#  };
#
#  in
#
#  [
#    (commonAutoMountOptions // { where = "/mnt/Brian"; })
#    (commonAutoMountOptions // { where = "/mnt/NetShare"; })
#    (commonAutoMountOptions // { where = "/mnt/homes"; })
#    (commonAutoMountOptions // { where = "/mnt/paperless/consume"; })
#    (commonAutoMountOptions // { where = "/mnt/paperless/export"; })
#  ];

  services = {
    zfs = {
      autoScrub.enable = true;
      trim.enable = true;
    };

    openiscsi = {
      enable = true;
      name = "iqn.1996-04.de.suse:01:456e953a9ed4";
    };
  };
}
