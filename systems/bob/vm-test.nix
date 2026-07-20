{ lib, pkgs, ... }:

let
  guestTest = pkgs.writeShellApplication {
    name = "bob-vm-guest-test";
    runtimeInputs = with pkgs; [
      coreutils
      curl
      docker
      findutils
      gawk
      gnugrep
      gnutar
      iproute2
      postgresql_16
      redis
      systemd
      util-linux
      zstd
    ];
    text = builtins.readFile ./vm-guest-test.sh;
  };
in
{
  virtualisation.vmVariant = {
    boot.zfs.extraPools = lib.mkForce [ ];

    networking = {
      bridges = lib.mkForce { };
      defaultGateway = lib.mkForce null;
      domain = lib.mkForce "test.invalid";
      extraHosts = lib.mkForce "";
      firewall.enable = lib.mkForce false;
      hostName = lib.mkForce "bob-vm";
      interfaces = lib.mkForce { };
      nameservers = lib.mkForce [ ];
      search = lib.mkForce [ ];
      useDHCP = lib.mkForce true;
      useNetworkd = lib.mkForce false;
      vlans = lib.mkForce { };
    };

    services = {
      openssh.enable = lib.mkForce false;
      timesyncd.enable = lib.mkForce false;
      zfs.autoScrub.enable = lib.mkForce false;
      zfs.trim.enable = lib.mkForce false;
    };

    systemd = {
      network = {
        links = lib.mkForce { };
        wait-online.enable = lib.mkForce false;
      };
      services.bob-vm-test = {
        after = [
          "docker.service"
          "tmp-shared.mount"
          "tmp-xchg.mount"
        ];
        requires = [
          "docker.service"
          "tmp-shared.mount"
          "tmp-xchg.mount"
        ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          ExecStart = lib.getExe guestTest;
          TimeoutStartSec = "infinity";
          Type = "oneshot";
        };
      };
    };

    virtualisation = {
      cores = 4;
      diskSize = 65536;
      docker.storageDriver = lib.mkForce "overlay2";
      fileSystems."/tmp/shared".options = lib.mkAfter [ "ro" ];
      graphics = false;
      memorySize = 12288;
      restrictNetwork = true;
    };
  };
}
