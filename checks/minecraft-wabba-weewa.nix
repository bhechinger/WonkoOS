{
  self,
  lib,
  pkgs,
}:
let
  config = self.nixosConfigurations.bob.config;
  minecraftProfile = name: "/nix/var/nix/profiles/per-user/root/minecraft-${name}";
  wabbaWeewa = config.services.minecraft-servers.servers.wabba-weewa;
  wabbaWeewaService = config.systemd.services.minecraft-server-wabba-weewa;
  wabbaWeewaWhitelist = config.systemd.services.minecraft-whitelist-wabba-weewa;
  bobDatasets = config.disko.devices.zpool.zpool.datasets;
  mcRouter = config.systemd.services.mc-router;
in
assert wabbaWeewa.enable && wabbaWeewa.autoStart;
assert wabbaWeewa.serverProperties.server-ip == "127.0.0.13";
assert wabbaWeewa.serverProperties.server-port == 25568;
assert wabbaWeewa.serverProperties.level-seed == "6086272851766572427";
assert lib.hasPrefix "wabba weewa\\n" wabbaWeewa.serverProperties.motd;
assert wabbaWeewa.serverProperties.online-mode;
assert wabbaWeewa.serverProperties.white-list && wabbaWeewa.serverProperties.enforce-whitelist;
assert wabbaWeewa.serverProperties.enable-rcon;
assert wabbaWeewa.serverProperties."rcon.port" == 25577;
assert wabbaWeewa.serverProperties."rcon.password" == "@RCON_PASSWORD@";
assert wabbaWeewa.symlinks.mods == "${minecraftProfile "wabba-weewa"}/mods";
assert wabbaWeewa.files.config == "${minecraftProfile "wabba-weewa"}/config";
assert
  wabbaWeewa.files."server.properties" == "${minecraftProfile "wabba-weewa"}/server.properties";
assert !wabbaWeewaService.restartIfChanged;
assert wabbaWeewaService.serviceConfig.MemoryMax == "7G";
assert wabbaWeewaService.serviceConfig.ProtectSystem == "strict";
assert lib.elem "minecraft-whitelist-wabba-weewa.service" wabbaWeewaService.wants;
assert wabbaWeewaWhitelist.partOf == [ "minecraft-server-wabba-weewa.service" ];
assert
  config.services.nginx.virtualHosts."minecraft.4amlunch.net".locations."/packs/wabba-weewa/".alias
  == "${minecraftProfile "wabba-weewa"}/site/";
assert lib.isDerivation config.system.build.minecraftDeployments.wabba-weewa;
assert bobDatasets."var/minecraft/wabba-weewa".mountpoint == "/var/lib/minecraft/wabba-weewa";
assert lib.hasInfix "wabba-weewa.4amlunch.net=127.0.0.13:25568" mcRouter.serviceConfig.ExecStart;
assert lib.elem "/var/lib/minecraft/wabba-weewa/.zfs/snapshot/restic"
  config.services.restic.backups.minecraft.paths;
pkgs.runCommand "minecraft-wabba-weewa-policy" { nativeBuildInputs = [ pkgs.python3 ]; } ''
  python ${./minecraft-backup-save-test.py} \
    ${config.services.sanoid.datasets."zpool/var/minecraft".pre_snapshot_script} \
    ${config.services.sanoid.datasets."zpool/var/minecraft".post_snapshot_script} \
    ${config.sops.templates.minecraft-environment.path} \
    ${lib.getExe pkgs.mcrcon}
  touch "$out"
''
