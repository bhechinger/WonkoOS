{ inputs, config, lib, pkgs, ... }:

{
  services = {
    openvpn.servers = {
      vyprVPN-Miami = {
        config = '' config /home/wonko/.openvpn/vyprvpn/OpenVPN256/USA-Miami.ovpn '';
        autoStart = false;
      };
      #neuralrack = {
      #  config = '' config /home/wonko/.openvpn/neuralrack.ovpn '';
      #  autoStart = true;
      #};
    };
  };
}
