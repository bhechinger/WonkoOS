{ config, lib, pkgs, ... }:

{
  networking = {
    hostName = "deepthought";
    hostId = "8425e349";
    domain = "4amlunch.internal";
    useDHCP = false;
    bridges = {
      "trunk" = {
        interfaces = [ "enp9s0" ];
      };
      #"storage" = {
      #  interfaces = [ "enp5s0" ];
      #};
    };
    vlans = {
      internal = { id=420; interface="trunk"; };
    };
    interfaces = {
      internal.ipv4.addresses = [{
        address = "10.42.0.10";
        prefixLength = 24;
      }];
      #storage.ipv4.addresses = [{
      #  address = "192.168.99.229";
      #  prefixLength = 24;
      #}];
    };
    defaultGateway = "10.42.0.1";
    nameservers = [ "10.42.0.1" ];
    #extraHosts = ''
    #  192.168.99.30 basket.4amlunch.net basket
    #'';
    firewall.enable = false;
  };

  services.openssh.enable = true;
}
