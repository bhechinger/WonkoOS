# Internal Attic cache on Bob

Bob runs Attic at `https://cache.4amlunch.net`. Internal hosts pull without
credentials and may push after a one-time `attic login`. Basket stores the
compressed cache payload over NFS; Bob keeps the disposable SQLite metadata
under `/var/lib/atticd`.

## Basket prerequisite

In QTS, create the `NixCache` shared folder on a dedicated volume with a
1 TiB quota. Create a dedicated `nix-cache` user/group with access only to that
share, then export it over NFSv4 with these settings:

- client: `10.42.0.2`
- access: read/write
- squash: all users, mapped to `nix-cache`
- security: `sys`

Confirm from Deepthought before deploying Bob:

```sh
showmount -e basket.4amlunch.net | grep -F '/NixCache 10.42.0.2'
```

## Bootstrap

Deploy Bob from Deepthought, then create the cache with a short-lived
administrator token:

```sh
make deploy-bob
ssh -F /dev/null wonko@bob.4amlunch.net

admin_token=$(sudo atticd-atticadm make-token \
  --sub bootstrap --validity 1h \
  --create-cache internal \
  --configure-cache internal \
  --configure-cache-retention internal)
attic login internal https://cache.4amlunch.net "$admin_token"
attic cache create internal --public --priority 50 \
  --upstream-cache-key-name cache.nixos.org-1 \
  --upstream-cache-key-name cache.flakehub.com-3
attic cache configure internal --retention-period '1 year'
attic cache info internal
unset admin_token
```

The public key is recorded in `common/nix-cache-client.nix`. Deploy Bob and
Deepthought, then make one shared writer token for trusted internal hosts:

```sh
writer_token=$(sudo atticd-atticadm make-token \
  --sub internal-writers --validity 10y \
  --pull internal --push internal)
attic login internal https://cache.4amlunch.net "$writer_token"
unset writer_token
```

Run the same `attic login` on each additional publishing host. Never commit a
token; public reads need only the substituter URL and public signing key.

## Publish and verify

`attic push` includes the closure by default:

```sh
nix build .#nixosConfigurations.deepthought.config.system.build.toplevel
attic push internal ./result
curl https://cache.4amlunch.net/internal/nix-cache-info
```

Check the service and storage from Deepthought:

```sh
ssh -F /dev/null wonko@bob.4amlunch.net \
  'systemctl status atticd nginx nfs-NixCache.automount && findmnt /nfs/NixCache'
dig +short cache.4amlunch.net
dig @1.1.1.1 +short cache.4amlunch.net
```

The internal lookup must return `10.42.0.2`; the public lookup must be empty.
Attic garbage-collects entries unused for one year every 12 hours. The cache is
not backed up: if `/var/lib/atticd/server.db` is lost, clear `NixCache` on
Basket and repeat the bootstrap.
