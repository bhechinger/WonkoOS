.PHONY: hugepages-inputs boot switch build

hugepages-inputs:
	./scripts/generate_hugepages_inputs.sh

boot: hugepages-inputs
	nh os boot -H deepthought .

switch: hugepages-inputs
	nh os switch -H deepthought .

build: hugepages-inputs
	nh os build -H deepthought .
