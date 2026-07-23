.PHONY: hugepages-inputs boot switch build build-bob deploy-bob

HOST := $(shell hostname -s)

hugepages-inputs:
	./scripts/generate_hugepages_inputs.sh

boot: hugepages-inputs
	nh os boot -H $(HOST) .

switch: hugepages-inputs
	nh os switch -H $(HOST) .

build: hugepages-inputs
	nh os build -H $(HOST) .

build-bob:
	nh os build -H bob --diff never .
	#nix copy --to ssh-ng://wonko@bob.4amlunch.net ./result
	#ssh wonko@bob.4amlunch.net nix store diff-closures /run/current-system "$$(readlink -f result)"

deploy-bob: build-bob
	nh os switch -H bob --target-host wonko@bob.4amlunch.net --elevation-strategy passwordless .
