{ config, pkgs, ... }:

{
  # OpenZFS owns these native mountpoints; disko still provisions and mounts
  # them during installation.
  fileSystems = {
    "/var".enable = false;
    "/var/lib/docker".enable = false;
    "/home".enable = false;
  };

  # NFS mounts
  systemd = {
    mounts =
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
      ];

    automounts =
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
      ];

    services.zfs-import-basket = {
      description = "Import ZFS pool \"basket\" after iSCSI login";
      after = [
        "iscsi.service"
        "zfs-import.target"
        "zfs-mount.service"
      ];
      requires = [
        "iscsi.service"
        "zfs-mount.service"
      ];
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
            break
          fi

          if zpool import basket; then
            break
          fi

          echo "basket pool is not importable yet; waiting for iSCSI devices ($attempt/24)"
          udevadm settle --timeout=5 || true
          sleep 5
        done

        if ! zpool list -H -o name basket >/dev/null 2>&1; then
          zpool import basket
        fi

        while IFS=$'\t' read -r dataset mounted canmount; do
          if [ "$mounted" = "no" ] && [ "$canmount" = "on" ]; then
            zfs mount "$dataset"
          fi
        done < <(zfs list -H -o name,mounted,canmount -t filesystem -r basket)
      '';
    };
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
}
