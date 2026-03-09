{ inputs, config, pkgs, ... }:

{
  fileSystems."/" = {
    device = "zpool/root";
    fsType = "zfs";
    options = [ "zfsutil" ];
  };

  fileSystems."/nix" = {
    device = "zpool/nix";
    fsType = "zfs";
    options = [ "zfsutil" ];
  };

  fileSystems."/var" = {
    device = "zpool/var";
    fsType = "zfs";
    options = [ "zfsutil" ];
  };

  fileSystems."/home" = {
    device = "tank/home";
    fsType = "zfs";
    options = [ "zfsutil" ];
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-id/nvme-WDC_WDS100T2B0C-00PXH0_21281Y459408-part1";
    fsType = "vfat";
    options = [ "fmask=0022" "dmask=0022" ];
  };

  #fileSystems."/backups" = {
  #  device = "backups";  # Replace with the correct device path after iSCSI login you cloud also do /dev/disk/by-uuid/<UUID-of-device>
  #  fsType = "zfs";  # Or the correct filesystem type
  #  options = [ "zfsutil" "_netdev" "nofail" ];  # Ensures network is up before mounting and wont fail to boot if it cant connect
  #};

  swapDevices = [{
    device = "/dev/disk/by-id/nvme-WDC_WDS100T2B0C-00PXH0_21281Y459408-part2";
  }];

  # NFS mounts
  systemd.mounts = let commonMountOptions = {
    type = "nfs";
    mountConfig = {
      Options = "noatime";
    };
  };

  in

  [
    (commonMountOptions // {
      what = "basket.4amlunch.net:/Brian";
     where = "/basket/Brian";
    })

    (commonMountOptions // {
      what = "basket.4amlunch.net:/NetShare";
      where = "/basket/NetShare";
    })

    (commonMountOptions // {
      what = "basket.4amlunch.net:/homes";
      where = "/basket/homes";
    })

    #(commonMountOptions // {
    #  what = "bob.4amlunch.net:/home/docker/paperless/consume";
    #  where = "/basket/paperless/consume";
    #})

    #(commonMountOptions // {
    #  what = "bob.4amlunch.net:/home/docker/paperless/export";
    #  where = "/basket/paperless/export";
    #})
  ];

  systemd.automounts = let commonAutoMountOptions = {
    wantedBy = [ "multi-user.target" ];
    automountConfig = {
      TimeoutIdleSec = "600";
    };
  };

  in

  [
    (commonAutoMountOptions // { where = "/basket/Brian"; })
    (commonAutoMountOptions // { where = "/basket/NetShare"; })
    (commonAutoMountOptions // { where = "/basket/homes"; })
    #(commonAutoMountOptions // { where = "/basket/paperless/consume"; })
    #(commonAutoMountOptions // { where = "/basket/paperless/export"; })
  ];

  services = {
    zfs = {
      autoScrub.enable = true;
      trim.enable = true;
    };

    openiscsi = {
      enable = true;
      name = "iqn.2020-08.internal.4amlunch.deepthought:desktop";
      discoverPortal = "10.42.0.30";
    };
  };
  #
  # Custom systemd service for logging in to a specific iSCSI target, you can name the service whatever youd like
  #systemd.services.iscsi-login-lingames = {
  #  description = "Login to iSCSI target iqn.2004-04.com.qnap:ts-453d:iscsi.basket.5de5ba";
  #  after = [ "network.target" "iscsid.service" ];
  #  wants = [ "iscsid.service" ];
  #  serviceConfig = {
  #    ExecStartPre = "${pkgs.openiscsi}/bin/iscsiadm -m discovery -t sendtargets -p basket.4amlunch.net";
  #    ExecStart = "${pkgs.openiscsi}/bin/iscsiadm -m node -T iqn.2004-04.com.qnap:ts-453d:iscsi.basket.5de5ba -p basket.4amlunch.net --login";
  #    ExecStop = "${pkgs.openiscsi}/bin/iscsiadm -m node -T iqn.2004-04.com.qnap:ts-453d:iscsi.basket.5de5ba -p basket.4amlunch.net --logout";
  #    Restart = "on-failure";
  #    RemainAfterExit = true;
  #  };
  #  wantedBy = [ "multi-user.target" ];
  #};

}
