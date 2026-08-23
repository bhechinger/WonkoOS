{ pkgs, ... }:

{
  home.packages = with pkgs; [
    blender
    godot
  ];
}
