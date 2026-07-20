{
  imports = [
    ./avahi.nix
    ./cloudflared.nix
    ./docker.nix
    ./jackett.nix
    ./media.nix
    ./murmur.nix
    ./nfs.nix
    ./nginx.nix
    ./opnsense-dns.nix
    ./paperless.nix
    ./plex.nix
    ./postfix.nix
    ./postgresql.nix
    ./protonmail-bridge.nix
    ./restore.nix
    ./rtorrent.nix
    ./rutorrent.nix
    ./sonarr.nix
    ./tailscale.nix
    ./timesyncd.nix
    ./unifi-controller.nix
    ./zerotier.nix
  ];

  _module.args.bobRestoreMarker = "/var/lib/bob-restored";
}
