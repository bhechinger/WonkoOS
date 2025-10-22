{ inputs, config, lib, pkgs, ... }:

{
  services = {
    #keybase.enable = true;
    #flatpak.enable = true;

    udev = {
      extraRules = ''
        SUBSYSTEM=="usbmon", GROUP="wireshark", MODE="0640"
      '';
    };

    #zerotierone = {
    #  enable = true;
    #  joinNetworks = [
    #    "a84ac5c10a853bc1"
    #  ];
    #  localConf = {};
    #};

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
      ];
    };

    openssh.enable = true;
    rpcbind.enable = true; # needed for NFS

    #hardware = {
    #  openrgb = {
    #    enable = true;
    #	    motherboard = "amd";
    #  };
    #};

    #sunshine = {
    #  enable = true;
    #  autoStart = true;
    #  openFirewall = true;
    #  capSysAdmin = true;
    #  applications = {
    #    apps = [
    #      {
    #        name = "1440p Desktop";
    #        exclude-global-prep-cmd = false;
    #        auto-detach = true;
    #      }
    #      {
    #        name = "1080p Desktop";
    #        prep-cmd = [
    #          {
    #            do = "${pkgs.kdePackages.libkscreen}/bin/kscreen-doctor output.DP-0.mode.1920x1080@60";
    #            undo = "${pkgs.kdePackages.libkscreen}/bin/kscreen-doctor output.DP-0.mode.2560x1440@144";
    #          }
    #        ];
    #        exclude-global-prep-cmd = "false";
    #        auto-detach = "true";
    #      }
    #      {
    #        name = "Pixel Desktop";
    #        prep-cmd = [
    #          {
    #            do = "${pkgs.kdePackages.libkscreen}/bin/kscreen-doctor output.DP-0.mode.2400x1080@120";
    #            undo = "${pkgs.kdePackages.libkscreen}/bin/kscreen-doctor output.DP-0.mode.2560x1440@144";
    #          }
    #        ];
    #        exclude-global-prep-cmd = false;
    #        auto-detach = true;
    #      }
    #    ];
    #  };
    #};
  };
}
