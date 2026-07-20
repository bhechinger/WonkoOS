{ bobRestoreMarker, ... }:

{
  services.nfs.server = {
    enable = true;
    exports = ''
      /home/docker/paperless/consume 10.42.0.10(rw,sync,no_subtree_check,root_squash)
      /home/docker/paperless/export 10.42.0.10(rw,sync,no_subtree_check,root_squash)
    '';
  };

  systemd.services."nfs-server".unitConfig.ConditionPathExists = bobRestoreMarker;
}
