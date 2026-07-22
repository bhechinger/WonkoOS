# Deferred configuration findings

These findings were reviewed on 2026-07-11 and deliberately deferred. Their
implementations remain unchanged.

## EOL kernel and disabled mitigations

`deepthought` pins Linux 7.0 and ZFS 2.4 from `linux_7_0`, while also passing
`mitigations=off`. This leaves the host without a maintained kernel security
stream and disables CPU vulnerability mitigations.

Review when ZFS supports a maintained kernel suitable for the audio workload,
or sooner if the host's threat model changes.

## Runtime-derived hugepage configuration

The Make targets sample SysV shared-memory state into
`systems/deepthought/hugepages-inputs.nix`, while the hugepage check requires
the resulting count to remain exactly 72. A legitimate workload or kernel
change can therefore update the input and immediately fail the check.

Review when the generated input changes, a build fails the exact-count
assertion, or hugepage requirements are recalibrated.

## Complete Nerd Font set

Home Manager installs all 70 Nerd Font derivations, adding approximately 4 GiB
to the closure. This is intentional for now.

Review when store usage matters or the required terminal/editor fonts are
known well enough to select explicitly.

## UniFi OS Server migration

As of 2026-07-21, Bob runs the healthy NixOS-native UniFi Network Server
10.2.105. Ubiquiti now recommends UniFi OS Server for self-hosting, but its
[Linux deployment](https://help.ui.com/hc/en-us/articles/34210126298775-Self-Hosting-UniFi)
requires systemd and Podman, installs mutable host services, and is not
packaged by Nixpkgs. Installing it directly would conflict with Bob's
declarative service model, so the current Network Server remains unchanged.

Review when Nixpkgs gains a maintained UniFi OS Server module, a reproducible
NixOS solution becomes available, Ubiquiti announces a firm Network Server
end-of-support date or stops security fixes, or required device firmware or
features no longer work with the current server. Prefer a maintained NixOS
module; otherwise use an isolated supported VM or UniFi appliance rather than
the imperative installer on Bob. Keep administration local or VPN-only.
