{ lib, ... }:

let
  servicePorts = {
    allowedTCPPorts = [
      22
      25
      53
      80
      88
      135
      139
      389
      443
      445
      464
      636
      1025
      1143
      2049
      3005
      3268
      3269
      6789
      8001
      8080
      8324
      8443
      8843
      8880
      8989
      9117
      32400
      32469
      49152
      49153
      49154
      64738
    ];
    allowedUDPPorts = [
      53
      88
      123
      137
      138
      389
      464
      1900
      3478
      5353
      5514
      9993
      10001
      32410
      32411
      32412
      32413
      32414
      41641
      64738
    ];
  };
in
{
  systemd.network.links = {
    "10-primary" = {
      matchConfig.MACAddress = "1c:69:7a:6e:8a:ef";
      linkConfig.Name = "primary";
    };
  };

  systemd.network.wait-online = {
    anyInterface = false;
    extraArgs = [ "--interface=internal:routable" ];
    timeout = 15;
  };

  networking = {
    hostName = "bob";
    hostId = "b0b00420";
    domain = "4amlunch.net";
    useDHCP = false;
    useNetworkd = true;

    vlans = {
      "vlan.410" = {
        id = 410;
        interface = "primary";
      };
      "vlan.420" = {
        id = 420;
        interface = "primary";
      };
    };

    bridges = {
      guest.interfaces = [ "vlan.410" ];
      internal.interfaces = [ "vlan.420" ];
      management.interfaces = [ "primary" ];
    };

    interfaces = {
      internal.ipv4.addresses = [
        {
          address = "10.42.0.2";
          prefixLength = 24;
        }
      ];
      management.ipv4.addresses = [
        {
          address = "10.42.11.2";
          prefixLength = 24;
        }
      ];
    };

    defaultGateway = {
      address = "10.42.0.1";
      interface = "internal";
    };
    nameservers = [ "10.42.0.1" ];
    search = [
      "4amlunch.internal"
      "4amlunch.net"
    ];
    extraHosts = ''
      10.42.0.30 basket.4amlunch.net basket
    '';

    firewall = {
      enable = true;
      allowedTCPPorts = lib.mkForce [ ];
      allowedUDPPorts = lib.mkForce [ ];
      interfaces = {
        internal = servicePorts;
        tailscale0 = servicePorts;
        ztnfaeb6wl = servicePorts;
        management = {
          allowedTCPPorts = [ 8080 ];
          allowedUDPPorts = [
            1900
            3478
            5514
            10001
          ];
        };
      };
    };
  };
}
