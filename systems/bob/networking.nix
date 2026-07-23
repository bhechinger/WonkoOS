{ lib, ... }:

let
  applicationPorts = {
    allowedTCPPorts = [
      22
      53
      80
      443
      2049
      3100
      4317
      4318
      6789
      8443
      32400
      32469
      64738
    ];
    allowedUDPPorts = [
      53
      1900
      5353
      9993
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
      "vlan.420" = {
        id = 420;
        interface = "primary";
      };
    };

    bridges = {
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
    nameservers = [
      "10.42.0.1"
      "10.42.0.2"
    ];
    search = [ "4amlunch.net" ];
    extraHosts = ''
      10.42.0.30 basket.4amlunch.net basket
    '';

    firewall = {
      enable = true;
      allowedTCPPorts = lib.mkForce [ ];
      allowedUDPPorts = lib.mkForce [ ];
      interfaces = {
        internal = applicationPorts;
        tailscale0 = {
          allowedTCPPorts = [
            22
            80
            443
            8443
            32400
            64738
          ];
          allowedUDPPorts = [ 64738 ];
        };
        ztnfaeb6wl = {
          allowedTCPPorts = [
            22
            80
            443
            8443
            32400
            64738
          ];
          allowedUDPPorts = [ 64738 ];
        };
        management = {
          allowedTCPPorts = [
            53
            8080
          ];
          allowedUDPPorts = [
            53
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
