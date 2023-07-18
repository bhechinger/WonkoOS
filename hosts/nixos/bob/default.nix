{
  imports = [
    ../../common/global
    ../../common/users/wonko.nix

    ./hardware-configuration.nix
    ./filesystems.nix

    (import ./partitions.nix {
#      disks = [ "/dev/nvme0n1" ];
      disks = [ "/dev/vda" ];
    })

    # Services that only run on bob
    ./services/
  ];

  # Machine ids
  networking = {
    hostName = "bob";
    hostId = "3f3fb897";
    domain = "4amlunch.net";
    dhcpcd.enable = false;
    usePredictableInterfaceNames = false;
    interfaces.eth0.ipv4.addresses = [{
      address = "10.42.11.99";
      prefixLength = 24;
    }];
    vlans = {
      external = { id=100; interface="eth0"; };
      internal = { id=420; interface="eth0"; };
      guest = { id=410; interface="eth0"; };
    };
    interfaces.internal.ipv4.addresses = [{
      address = "10.42.0.99";
      prefixLength = 24;
    }];
    defaultGateway = "10.42.0.1";
    nameservers = [ "10.42.0.2" "10.42.0.10" "10.42.0.12" ];

    firewall.enable = false; # I will look into this later
  };
  environment.etc.machine-id.text = "d9571439c8a34e34b89727b73bad3587"; # TODO: what is this?

  # Docker service deamon
  virtualisation.docker.enable = true;

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  system.stateVersion = "23.05";

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
}
