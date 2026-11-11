# wabba weewa

Imported from `~/Downloads/WhatSie/wabba_weewa.zip` (SHA-256
`fe7aad10ade2bc9e51c6e3ca86003edec1942822757f7f797b1dba2dce0d5177`).
The source export has no version; the managed pack starts at `1.0.0`.
`wabba-weewa-manifest.json` retains its original 83 CurseForge file references.
The client artifact is checked against those references and the Minecraft and
Forge versions before deployment. Imported text uses LF line endings.

The server uses Minecraft 1.20.1, Forge 47.4.28, Java 17, and a new world with
seed `6086272851766572427`. Join at `wabba-weewa.4amlunch.net`; download the
client pack at `https://minecraft.4amlunch.net/packs/wabba-weewa/wabba-weewa.zip`.
The client keeps all supplied mods and shaders; client components are excluded
from the dedicated server. The existing Species 3.5 structure repair is also
applied to this server's copy of the mod.

The server uses the shared online-mode whitelist, its own ZFS dataset at
`/var/lib/minecraft/wabba-weewa`, and the existing Minecraft snapshots and
Restic backups. Its backend is `127.0.0.13:25568`, and RCON is on port `25577`.

From Deepthought, use `make deploy-wabba-weewa` for subsequent pack updates.
For first deployment, create `zpool/var/minecraft/wabba-weewa`, stage and set
the `minecraft-wabba-weewa` profile, then deploy Bob's NixOS configuration.
The server must start with the configured seed before any world is generated.
