# Private Harmonia Cache for `deepthought`

## Summary

Run Harmonia directly on an x86_64 Linux/systemd cache host, serving its
`/nix/store` at `http://cache.4amlunch.internal:5000`. Restrict the port to
`deepthought` (`10.42.0.10`), use a signing key protected by systemd
credentials, and add its public key to the existing NixOS cache settings.

## Cache Host

- Create the private DNS record `cache.4amlunch.internal` pointing to the
  cache host's LAN/VPN address.
- Install Nix with the official multi-user installer, then install Harmonia in
  a stable system profile:
  `nix profile install --profile /nix/var/nix/profiles/harmonia nixpkgs#harmonia`.
- Generate `cache.4amlunch.internal-1`, store the secret as
  `/etc/harmonia/cache.key` owned by root and mode `0600`, and record the
  derived public key for the client. Use `nix key generate-secret` and
  `nix key convert-secret-to-public`.
- Create `/etc/harmonia/harmonia.toml` with:
  - `bind = "0.0.0.0:5000"`
  - `priority = 30`
  - `enable_compression = false` to retain resumable downloads.
- Add a `harmonia.service` systemd unit running the profile binary as
  `DynamicUser=yes`, with `CONFIG_FILE`, `HOME=/run/harmonia`, and
  `LoadCredential=sign-key:/etc/harmonia/cache.key`; pass it as
  `SIGN_KEY_PATHS=%d/sign-key`. Enable restart-on-failure and basic filesystem
  hardening (`ProtectSystem=strict`, `ProtectHome=true`, `PrivateTmp=true`,
  `NoNewPrivileges=true`).
- Permit TCP/5000 only from `10.42.0.10`; do not expose this HTTP service
  beyond the LAN/VPN.

## NixOS Client

- Update `systems/deepthought/system.nix` to prepend
  `http://cache.4amlunch.internal:5000` to the existing `substituters` and
  `trusted-substituters` lists.
- Add the generated `cache.4amlunch.internal-1:<public-key>` to
  `trusted-public-keys`; retain the existing FlakeHub/Determinate entries.
- Do not add flake-level cache hints: this cache is private to `deepthought`.

## Population, Retention, and Verification

- Clone this repository on the cache host. After each intended `flake.lock`
  update, build `.#nixosConfigurations.deepthought.config.system.build.toplevel`
  there before deploying on `deepthought`.
- Do not enable automated GC or a build scheduler initially. The cache is
  best-effort; manually run Nix garbage collection only when space requires it.
- Verify the service locally, then from `deepthought`, with
  `curl http://cache.4amlunch.internal:5000/nix-cache-info`.
- Build a store path on the cache host that is absent on `deepthought`; then
  build the identical flake output on `deepthought` with Nix debug logging and
  confirm it downloads from `cache.4amlunch.internal` and accepts the signature.
- Run `nix flake check` after the NixOS setting edit.

## Assumptions

- The cache host is x86_64 Linux with systemd and is on the trusted
  `10.42.0.0/24` LAN/VPN.
- `deepthought` is the only client, and the cache host is the only builder.
- Skipped: Docker, reverse proxy/TLS, CI, metrics, remote builders, and
  automatic pruning. Add those only if the cache moves beyond the private
  network or manual prebuilds become burdensome.
