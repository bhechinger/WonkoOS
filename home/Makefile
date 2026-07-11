.PHONY: build switch update
switch:
	nh home switch ..
	hyprctl reload

build:
	nh home build ..

update:
	nix flake update auto-splice --flake ..
