{
  lib,
  pkgs,
  unstable-pkgs,
  ...
}:

{
  home.packages = with pkgs; [
    chiaki-ng
    ryubing
    unstable-pkgs.mame
    mindustry
    r2modman
    heroic
    (prismlauncher.override {
      additionalLibs = [ libXi ];
    })
    javaPackages.compiler.temurin-bin.jdk-25
    mcpelauncher-ui-qt
    unigine-superposition
    python314
  ];

  programs = {
    mangohud = {
      enable = true;
      enableSessionWide = true;
      settings = {
        full = true;
        media_player = false;
        vsync = 0;
        no_display = true;
      };
    };
  };

  systemd.user = {
    paths.dualsense-touchpad-button = {
      Unit = {
        Description = "Watch for the DualSense touchpad button";
        PartOf = [ "hyprland-session.target" ];
      };
      Path.PathExists = "/dev/input/dualsense-touchpad";
      Install.WantedBy = [ "hyprland-session.target" ];
    };

    services.dualsense-touchpad-button = {
      Unit = {
        Description = "Expose the DualSense touchpad button as F24";
        PartOf = [ "hyprland-session.target" ];
      };
      Service = {
        ExecStart = "${lib.getExe pkgs.evsieve} --input /dev/input/dualsense-touchpad persist=reopen --map btn:left key:f24 --output key:f24 name=dualsense-touchpad-button";
        Restart = "on-failure";
        RestartSec = 2;
      };
    };
  };
}
