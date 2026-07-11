{
  lib,
  pkgs,
  ...
}:

{
  services = {
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
}
