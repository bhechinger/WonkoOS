{ config, pkgs, ... }:

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

  fileSystems."/var/lib/docker" = {
    device = "zpool/docker";
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
    options = [
      "fmask=0022"
      "dmask=0022"
    ];
  };

  swapDevices = [
    {
      device = "/dev/disk/by-id/nvme-WDC_WDS100T2B0C-00PXH0_21281Y459408-part2";
    }
  ];

  # NFS mounts
  systemd.mounts =
    let
      commonMountOptions = {
        type = "nfs4";
        mountConfig = {
          Options = "noatime";
        };
      };

    in

    [
      (
        commonMountOptions
        // {
          what = "basket.4amlunch.net:/Brian";
          where = "/nfs/Brian";
        }
      )

      (
        commonMountOptions
        // {
          what = "basket.4amlunch.net:/NetShare";
          where = "/nfs/NetShare";
        }
      )

      (
        commonMountOptions
        // {
          what = "basket.4amlunch.net:/homes";
          where = "/nfs/homes";
        }
      )

      #(commonMountOptions // {
      #  what = "bob.4amlunch.net:/home/docker/paperless/consume";
      #  where = "/nfs/paperless/consume";
      #})

      #(commonMountOptions // {
      #  what = "bob.4amlunch.net:/home/docker/paperless/export";
      #  where = "/nfs/paperless/export";
      #})
    ];

  systemd.automounts =
    let
      commonAutoMountOptions = {
        wantedBy = [ "multi-user.target" ];
        automountConfig = {
          TimeoutIdleSec = "600";
        };
      };

    in

    [
      (commonAutoMountOptions // { where = "/nfs/Brian"; })
      (commonAutoMountOptions // { where = "/nfs/NetShare"; })
      (commonAutoMountOptions // { where = "/nfs/homes"; })
      #(commonAutoMountOptions // { where = "/nfs/paperless/consume"; })
      #(commonAutoMountOptions // { where = "/nfs/paperless/export"; })
    ];

  systemd.services.zfs-import-basket = {
    description = "Import ZFS pool \"basket\" after iSCSI login";
    after = [
      "iscsi.service"
      "zfs-import.target"
    ];
    requires = [ "iscsi.service" ];
    wantedBy = [ "multi-user.target" ];
    path = [
      config.boot.zfs.package
      pkgs.systemd
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      for attempt in $(seq 1 24); do
        if zpool list -H -o name basket >/dev/null 2>&1; then
          exit 0
        fi

        if zpool import -N basket; then
          exit 0
        fi

        echo "basket pool is not importable yet; waiting for iSCSI devices ($attempt/24)"
        udevadm settle --timeout=5 || true
        sleep 5
      done

      zpool import -N basket
    '';
  };

  services = {
    zfs = {
      autoScrub.enable = true;
      trim.enable = true;
    };

    openiscsi = {
      enable = true;
      enableAutoLoginOut = true;
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
