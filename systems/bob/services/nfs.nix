{ config, pkgs, ... }:

let
  basketMounts = [
    "nfs-NixCache.mount"
    "nfs-Plex.mount"
    "nfs-Restic.mount"
    "nfs-Torrents.mount"
  ];
in

{
  services.nfs = {
    settings.nfsd = {
      vers3 = false;
      vers4 = true;
    };
    server = {
      enable = true;
      exports = ''
        /var/lib/paperless/consume 10.42.0.10(rw,sync,no_subtree_check,all_squash,anonuid=${toString config.ids.uids.paperless},anongid=${toString config.ids.gids.paperless})
        /var/lib/paperless/export 10.42.0.10(rw,sync,no_subtree_check,all_squash,anonuid=${toString config.ids.uids.paperless},anongid=${toString config.ids.gids.paperless})
      '';
      hostName = "10.42.0.2";
    };
  };

  systemd.services.basket-nfs-ready = {
    description = "Wait for Basket's NFS service";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    before = basketMounts;
    requiredBy = basketMounts;
    script = ''
      until ${pkgs.rpcbind}/bin/rpcinfo -T tcp 10.42.0.30 nfs 4 >/dev/null 2>&1; do
        ${pkgs.coreutils}/bin/sleep 5
      done
    '';
    serviceConfig = {
      Type = "oneshot";
      TimeoutStartSec = "infinity";
    };
  };
}
