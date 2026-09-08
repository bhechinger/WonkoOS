.PHONY: build switch update
switch:
	nh home switch .. -c deepthought
	hyprctl reload

build:
	nh home build .. -c deepthought

update:
	nix flake update auto-splice --flake ..
