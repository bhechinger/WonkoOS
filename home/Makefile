.PHONY: build switch update
switch:
	nh home switch .. -c deepthought --no-nom
	hyprctl reload

build:
	nh home build .. -c deepthought --no-nom

update:
	nix flake update auto-splice --flake ..
