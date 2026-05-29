.PHONY: update
switch:
	nh home switch .
	hyprctl reload

build:
	nh home build .

update:
	nix flake lock --update-input auto-splice
