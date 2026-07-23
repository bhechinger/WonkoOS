{ config, ... }:

{
  sops.secrets.vyprvpn-auth = {
    sopsFile = ./secrets/vyprvpn.sops;
    format = "yaml";
    key = "auth";
    mode = "0400";
  };

  systemd.network.links."10-primary-trunk" = {
    matchConfig.MACAddress = "9c:6b:00:c0:c8:58";
    linkConfig.Name = "primary-trunk";
  };

  networking = {
    hostName = "deepthought";
    hostId = "8425e349";
    domain = "4amlunch.net";
    useDHCP = false;
    bridges = {
      "trunk" = {
        interfaces = [ "primary-trunk" ];
      };
    };
    vlans = {
      internal = {
        id = 420;
        interface = "trunk";
      };
    };
    interfaces = {
      internal.useDHCP = true;
      internal.ipv4.addresses = [
        {
          address = "10.42.0.10";
          prefixLength = 24;
        }
      ];
    };
    defaultGateway = "10.42.0.1";
    dhcpcd.extraConfig = ''
      interface internal
        ipv6only
    '';
    nameservers = [
      "10.42.0.1"
      "10.42.0.2"
    ];
    extraHosts = ''
      10.42.0.30 basket.4amlunch.net basket
    '';
    firewall = {
      enable = true;
      allowedTCPPorts = [
        22
        1234
      ];
      interfaces.internal.allowedTCPPorts = [ 9100 ];
    };
  };

  services = {
    openvpn.servers.vyprvpn-miami = {
      config = "config ${./openvpn/vyprvpn-miami.ovpn}";
      authUserPass = config.sops.secrets.vyprvpn-auth.path;
      autoStart = false;
      updateResolvConf = true;
      up = ''
        if [ -z "''${nameserver:-}" ]; then
          echo "VyprVPN did not push a DNS server" >&2
          exit 1
        fi
      '';
    };
    openssh = {
      enable = true;
      settings = {
        KbdInteractiveAuthentication = false;
        PasswordAuthentication = false;
        PermitRootLogin = "no";
      };
    };
    zerotierone = {
      enable = true;
      joinNetworks = [ "a84ac5c10a853bc1" ];
    };
  };

  systemd.services.openvpn-vyprvpn-miami = {
    requires = [ "sops-install-secrets.service" ];
    after = [ "sops-install-secrets.service" ];
  };
}
