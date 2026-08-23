{
  self,
  lib,
  pkgs,
}:

let
  config = self.nixosConfigurations.deepthought.config;
  activeMounts = map (filesystem: filesystem.mountPoint) config.system.build.fileSystems;
  basketMountUnits = [
    "basket.mount"
    "basket-wonko.mount"
    "home-wonko-Documents.mount"
    "home-wonko-projects.mount"
  ];
in
assert
  builtins.attrNames config.disko.devices.disk == [
    "os"
    "tank"
  ];
assert
  builtins.attrNames config.disko.devices.zpool == [
    "tank"
    "zpool"
  ];
assert config.disko.devices.zpool.zpool.datasets.root.options.mountpoint == "legacy";
assert config.disko.devices.zpool.zpool.datasets.nix.options.mountpoint == "legacy";
assert config.disko.devices.zpool.zpool.datasets.var.mountpoint == "/var";
assert config.disko.devices.zpool.zpool.datasets.docker.mountpoint == "/var/lib/docker";
assert config.disko.devices.zpool.tank.datasets.home.mountpoint == "/home";
assert lib.all (mountpoint: lib.elem mountpoint activeMounts) [
  "/"
  "/boot"
  "/nix"
];
assert lib.all (mountpoint: !lib.elem mountpoint activeMounts) [
  "/var"
  "/var/lib/docker"
  "/home"
];
assert !lib.elem "basket" config.boot.zfs.extraPools;
assert lib.hasInfix "zpool export basket" config.systemd.services.zfs-import-basket.preStop;
assert lib.all (
  unit:
  lib.hasInfix "After=zfs-import-basket.service" config.systemd.units.${unit}.text
  && lib.hasInfix "Requires=zfs-import-basket.service" config.systemd.units.${unit}.text
) basketMountUnits;
pkgs.runCommand "storage-layout-test" { } ''
  touch "$out"
''
