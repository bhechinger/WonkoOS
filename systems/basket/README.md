# basket HTTPS certificate

`basket` obtains its own exact-name certificate for `basket.4amlunch.net` with
acme.sh and Cloudflare DNS-01. It does not copy or depend on `bob`'s wildcard
certificate, does not need an inbound Internet port, and does not publish the
NAS through myQNAPcloud.

The installer pins acme.sh 3.1.2 by release archive SHA-256 and disables its
auto-updater. QTS's persistent certificate files remain the deployment target,
so QTS still owns HTTPS while acme.sh owns issuance and renewal.

## Network prerequisites

- Internal DNS resolves `basket.4amlunch.net` to `10.42.0.30`.
- Public DNS has no A, AAAA, or CNAME record for `basket.4amlunch.net`. ACME
  creates only a short-lived `_acme-challenge` TXT record.
- OPNsense has no WAN NAT, port-forward, or UPnP mapping to `10.42.0.30` or the
  management address `10.42.11.50`. If OPNsense UPnP is needed for other hosts,
  deny these two addresses rather than disabling it globally.
- The NAS can make outbound HTTPS and DNS requests.

QTS services continue to listen on the trusted LAN. The no-external-access
guarantee is enforced at the gateway, not by exposing an ACME HTTP challenge.

## Bootstrap

Do all work involving `systems/bob` on `deepthought`. The existing encrypted
Cloudflare token is reused only as an issuance credential; no `bob` certificate
or private key is copied to the NAS.

First, on `deepthought`, test and copy the scripts:

```sh
systems/basket/deploy-certificate.sh --self-test
ssh -F /dev/null wonko@basket 'mkdir -p /share/homes/wonko/basket-acme && chmod 700 /share/homes/wonko/basket-acme'
scp -F /dev/null systems/basket/install-acme.sh systems/basket/deploy-certificate.sh \
  wonko@basket:/share/homes/wonko/basket-acme/
```

Copy the SOPS-managed runtime token from `bob` into a temporary mode-600 file
without displaying it, then transfer it to `basket`. Run these commands only on
`deepthought`:

```sh
basket_token=$(mktemp /tmp/basket-cloudflare-token.XXXXXX)
chmod 600 "$basket_token"
ssh -F /dev/null -o BatchMode=yes wonko@bob \
  'sudo -n /run/current-system/sw/bin/cat /run/secrets/cloudflare-acme-token' \
  >"$basket_token"
scp -F /dev/null -p "$basket_token" wonko@basket:/share/homes/wonko/.basket-cloudflare-token
rm -f "$basket_token"
```

Log in to the NAS, become root, and run the phases in order:

```sh
ssh -F /dev/null -t wonko@basket
sudo -i
cd /share/homes/wonko/basket-acme
chmod 700 install-acme.sh deploy-certificate.sh
./install-acme.sh prepare /share/homes/wonko/.basket-cloudflare-token
./install-acme.sh disable-cloud
./install-acme.sh activate
./install-acme.sh check
```

`prepare` consumes and removes the transferred token file, performs a Let's
Encrypt staging DNS-01 issuance, and then issues the production certificate
without installing it. The credential is retained only in root-readable
`/share/homes/admin/.acme.sh/account.conf` for renewal.

`disable-cloud` unregisters the NAS, waits for QTS's delayed certificate-release
hook, disables both `MyCloudNas` and `QcloudSSLCertificate`, removes the vendor
renewal cron entry, and stops only the myQNAPcloud `upnpcd` client. It deliberately
leaves the QNAP media UPnP services alone.

`activate` copies the stable key, leaf, intermediate, and full-chain files into
the private ACME deployment directory and invokes the transactional QTS deploy
hook. It adds one persistent QTS cron entry at 03:17; renewal output overwrites
`/share/homes/admin/.acme.sh/cron.log`, and a failed deployment is also written
to the QTS event log.

## Verification

From `deepthought`, verify internal naming and the served certificate:

```sh
getent ahostsv4 basket.4amlunch.net
openssl s_client -connect basket.4amlunch.net:443 -servername basket.4amlunch.net </dev/null 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates -ext subjectAltName
dig @1.1.1.1 +short A basket.4amlunch.net
dig @1.1.1.1 +short AAAA basket.4amlunch.net
dig @1.1.1.1 +short CNAME basket.4amlunch.net
```

The three public DNS queries should be empty. Also verify the OPNsense NAT and
UPnP state directly; a valid certificate is not evidence that the NAS is private.

After the next normal QTS reboot or firmware update, rerun:

```sh
sudo /share/homes/wonko/basket-acme/install-acme.sh check
```

No forced reboot is part of the rollout.

## Failure handling

The deploy hook validates the hostname, 30-day remaining lifetime, and key match
before touching QTS. It saves each prior QTS certificate set under
`/share/homes/admin/.acme.sh/qts-backup/`, restarts QTS HTTPS, compares the live
loopback certificate fingerprint, and restores the saved set if restart or live
verification fails. Do not manually replace the four files while the hook is
running.
