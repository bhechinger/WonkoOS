.PHONY: update
update:
	nix flake lock --update-input auto-splice

switch:
	nh home switch .
	hyprctl reload

build:
	nh home build .
