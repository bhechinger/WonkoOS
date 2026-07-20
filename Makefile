.PHONY: hugepages-inputs boot switch build deploy-bob

HOST := $(shell hostname -s)

hugepages-inputs:
	./scripts/generate_hugepages_inputs.sh

boot: hugepages-inputs
	nh os boot -H $(HOST) .

switch: hugepages-inputs
	nh os switch -H $(HOST) .

build: hugepages-inputs
	nh os build -H $(HOST) .

deploy-bob:
	nh os switch -H bob --target-host wonko@bob.4amlunch.net --elevation-strategy passwordless .
