# Sierra BIND

Sierra is the primary for `4amlunch.net`, `lan.4amlunch.net`, and the
`10.42.0.0/24` and `10.42.11.0/24` reverse zones. OPNsense owns the static
`4amlunch.net` zone; Kea updates the other three zones with RFC 2136.

The OPNsense BIND plugin regenerates every modeled primary zone during a
reconfigure. Dynamic zones therefore live in BIND's supported custom
configuration directory, where template reloads cannot overwrite their zone
files or desynchronize their journals. The installer also patches the plugin
template to cap recursive negative answers at 300 seconds and disable
aggressive DNSSEC negative synthesis, which otherwise reuses long-lived NSEC
and SOA records outside that cap.

## Test and stage

Run all Bob commands from `deepthought`.

```sh
nix shell nixpkgs#bind nixpkgs#shellcheck -c sh -c \
  'shellcheck -s sh systems/sierra/install-bind.sh && systems/sierra/install-bind.sh --self-test'

recovery=$(mktemp -d /tmp/sierra-bind-recovery.XXXXXX)
for zone in lan.4amlunch.net 0.42.10.in-addr.arpa 11.42.10.in-addr.arpa; do
  ssh -F /dev/null -o BatchMode=yes bob "
    bin=\$(dirname \$(sudo -n readlink -f /proc/\$(systemctl show bind.service -p MainPID --value)/exe))
    sudo -n \$bin/named-compilezone -q -f raw -j -F text -o - '$zone' '/var/lib/named/$zone.db'
  " >"$recovery/$zone.db"
done

scp -F /dev/null systems/sierra/install-bind.sh sierra:/tmp/install-bind.sh
scp -F /dev/null -r "$recovery" sierra:/tmp/sierra-bind-recovery
ssh -F /dev/null -t sierra
```

On Sierra, become root, back up the appliance state, and stage the custom
configuration. The installer validates all seeds and will not overwrite an
existing dynamic zone.

```sh
sudo -i
sh -c '
set -eu
backup=/root/sierra-bind-backup-$(date +%Y%m%dT%H%M%S)
mkdir -m 700 "$backup"
cp -p /conf/config.xml /usr/local/etc/namedb/named.conf "$backup/"
cp -Rp /usr/local/etc/namedb/primary /usr/local/etc/namedb/named.conf.d "$backup/"
/tmp/install-bind.sh install /tmp/sierra-bind-recovery
'
```

In OPNsense, delete the static records belonging to these three domains, then
delete the domains themselves without applying between deletions:

- `lan.4amlunch.net.`
- `0.42.10.in-addr.arpa.`
- `11.42.10.in-addr.arpa.`

There are currently nine static records: the NS records plus Bob, Sierra, and
Basket PTR records. They are already present in the recovered zone files.
Apply BIND once after all twelve objects are deleted.

## Verify

```sh
sh /tmp/install-bind.sh check

sh -c '
for zone in 4amlunch.net lan.4amlunch.net 0.42.10.in-addr.arpa 11.42.10.in-addr.arpa; do
  dig @127.0.0.1 "$zone" SOA +noall +comments +answer
done

rndc flush
dig @127.0.0.1 sierra-check-one.invalid A +noall +authority
dig @127.0.0.1 sierra-check-two.invalid A +noall +authority
'
```

All SOAs must be authoritative and have a 300-second negative field. The fresh
and immediately repeated `.invalid` answers must both have a TTL no greater
than 300.

Create and remove a short-lived signed TXT record in each dynamic zone, with a
full OPNsense BIND reconfigure between creation and removal. This is the
regression test: each record and zone must survive the reconfigure, and Bob's
secondary serials must converge afterward.

Kea has `update-on-renew` enabled. Online lease names missing from Bob's
recovery snapshot should return within one 4000-second lease cycle; sleeping
or offline clients return on their next DHCP request.

## Upgrades and rollback

Run `install` and `check` after every `os-bind` upgrade. `install` reapplies
the negative-cache template safeguards if necessary and otherwise leaves live
zone data alone. It fails instead of guessing if the upstream template anchor
changes.

If BIND does not start, restore `/conf/config.xml` from the timestamped backup,
move `10-kea-zones.conf` out of `named.conf.d`, and apply BIND again. Do not
delete the saved zone or journal files; Bob remains the fallback resolver while
Sierra is repaired.
