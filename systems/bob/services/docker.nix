{
  lib,
  pkgs,
  ...
}:

let
  dockerFirewall = pkgs.writeShellApplication {
    name = "bob-docker-firewall";
    runtimeInputs = [ pkgs.iptables ];
    text = ''
      chain=BOB-DOCKER

      iptables -w -N "$chain" 2>/dev/null || true
      iptables -w -F "$chain"
      if ! iptables -w -C DOCKER-USER -j "$chain" 2>/dev/null; then
        iptables -w -I DOCKER-USER 1 -j "$chain"
      fi

      iptables -w -A "$chain" -i management -p tcp \
        -m conntrack --ctorigdstport 8080 -j ACCEPT
      for port in 3478 10001 1900 5514; do
        iptables -w -A "$chain" -i management -p udp \
          -m conntrack --ctorigdstport "$port" -j ACCEPT
      done
      iptables -w -A "$chain" -i management -j DROP
    '';
  };
in
{
  virtualisation = {
    docker = {
      enable = true;
      storageDriver = "zfs";
    };
    oci-containers.backend = "docker";
  };

  systemd.services.docker.postStart = lib.getExe dockerFirewall;
}
