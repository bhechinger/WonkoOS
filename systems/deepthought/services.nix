{
  lib,
  pkgs,
  ...
}:

{
  services = {
    prometheus.exporters.node = {
      enable = true;
      enabledCollectors = [
        "processes"
        "systemd"
      ];
      listenAddress = "10.42.0.10";
      openFirewall = false;
    };

    prometheus.exporters.nvidia-gpu = {
      enable = true;
      listenAddress = "10.42.0.10";
      openFirewall = false;
    };

    alloy = {
      enable = true;
      extraFlags = [ "--server.http.listen-addr=127.0.0.1:12345" ];
    };

    pcscd.enable = true;

    udev = {
      extraRules = ''
        SUBSYSTEM=="usbmon", GROUP="wireshark", MODE="0640"
      '';
    };
    avahi = {
      enable = true;
      nssmdns4 = true;
      nssmdns6 = true;
      publish = {
        enable = true;
        addresses = true;
        userServices = true;
      };
    };

    displayManager = {
      sddm = {
        enable = true;
        wayland.enable = true;
      };
    };

    printing = {
      enable = true;
      drivers = [
        pkgs.hplipWithPlugin
        pkgs.brlaser
        pkgs.brgenml1lpr
        pkgs.brgenml1cupswrapper
      ];
    };

    # NixOS enables rpcbind for NFS mounts by default; these clients use NFSv4.
    rpcbind.enable = lib.mkForce false;
  };

  environment.etc."alloy/config.alloy".text = ''
    loki.write "bob" {
      endpoint {
        url = "http://10.42.0.2:3100/loki/api/v1/push"
      }
    }

    loki.relabel "journal" {
      forward_to = []

      rule {
        source_labels = ["__journal__systemd_unit"]
        target_label = "unit"
      }
    }

    loki.source.journal "system" {
      labels = {"host" = "deepthought", "job" = "systemd-journal"}
      max_age = "1h"
      relabel_rules = loki.relabel.journal.rules
      forward_to = [loki.write.bob.receiver]
    }
  '';

  systemd.services.attic-watch-store = {
    description = "Upload new Nix store paths to Attic";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    script = ''
      ${pkgs.coreutils}/bin/install -D -m 0400 "$CREDENTIALS_DIRECTORY/attic-config" "$RUNTIME_DIRECTORY/attic/config.toml"
      export XDG_CONFIG_HOME="$RUNTIME_DIRECTORY"
      exec ${lib.getExe pkgs.attic-client} watch-store internal
    '';
    serviceConfig = {
      DynamicUser = true;
      LoadCredential = "attic-config:/home/wonko/.config/attic/config.toml";
      Restart = "always";
      RestartSec = "30s";
      RuntimeDirectory = "attic-watch-store";
    };
  };
}
