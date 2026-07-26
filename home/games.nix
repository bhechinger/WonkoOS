{
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
    prismlauncher
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
}
