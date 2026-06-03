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
    prismlauncher
    javaPackages.compiler.temurin-bin.jdk-25
    mcpelauncher-ui-qt
    unigine-superposition
    python314
    #python314Packages.pynvml
    #python314Packages.nvidia-ml-py
  ];

  programs = {
    mangohud = {
      enable = true;
      enableSessionWide = true;
      settings = {
        full = true;
        vsync = 0;
        no_display = true;
      };
    };
  };
}
