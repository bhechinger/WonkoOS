{ config, ... }:

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
}
