.PHONY: hugepages-inputs refresh-pwppp refresh-gigglesomething refresh-packwiz boot switch build build-bob deploy-bob build-minecraft stage-minecraft deploy-minecraft rollback-minecraft
.PHONY: build-pwppp build-gigglesomething stage-pwppp stage-gigglesomething deploy-pwppp deploy-gigglesomething rollback-pwppp rollback-gigglesomething

HOST := $(shell hostname -s)
BOB := wonko@bob.4amlunch.net
BOB_SSH := ssh -F /home/wonko/.ssh/config -o ControlMaster=no -o ControlPath=none -T $(BOB)
MINECRAFT_PROFILE := /nix/var/nix/profiles/per-user/root/minecraft

hugepages-inputs:
	./scripts/generate_hugepages_inputs.sh

refresh-pwppp refresh-gigglesomething: refresh-%:
	cd systems/bob/minecraft/$* && nix shell ../../../..#nixosConfigurations.bob.pkgs.packwiz -c packwiz refresh
	@set -eu; \
	output="$$(nix build --impure --expr 'let pkgs = (builtins.getFlake (toString ./.)).nixosConfigurations.bob.pkgs; in pkgs.fetchPackwizModpack { src = ./systems/bob/minecraft/$*; side = "server"; packHash = pkgs.lib.fakeHash; }' --no-link 2>&1 || :)"; \
	hash="$$(printf '%s\n' "$$output" | sed -n 's/^ *got: *\(sha256-[A-Za-z0-9+/]\{43\}=\)$$/\1/p')"; \
	test -n "$$hash" || { printf '%s\n' "$$output" >&2; exit 1; }; \
	sed -i "/pname = \"$*-server\"/,/^  };/s|packHash = \".*\";|packHash = \"$$hash\";|" systems/bob/services/minecraft.nix; \
	echo "Updated $* packHash to $$hash"

refresh-packwiz: refresh-pwppp refresh-gigglesomething

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
	NIX_SSHOPTS='-F /home/wonko/.ssh/config -o ControlMaster=no -o ControlPath=none' nix copy --no-check-sigs --to ssh-ng://$(BOB) ./result
	$(BOB_SSH) sudo --non-interactive "$$(readlink -f result)/bin/switch-to-configuration" switch
	$(BOB_SSH) sudo --non-interactive nix build --no-link --profile /nix/var/nix/profiles/system "$$(readlink -f result)"
	$(BOB_SSH) sudo --non-interactive "$$(readlink -f result)/bin/switch-to-configuration" boot

build-pwppp build-gigglesomething: build-%: refresh-%
	nix build .#nixosConfigurations.bob.config.system.build.minecraftDeployments.$* --out-link result-minecraft-$*

stage-pwppp stage-gigglesomething: stage-%: build-%
	nix copy --no-check-sigs --to ssh-ng://$(BOB) ./result-minecraft-$*
	ssh $(BOB) sudo nix-env --profile $(MINECRAFT_PROFILE)-$* --set "$$(readlink -f result-minecraft-$*)"

deploy-pwppp deploy-gigglesomething: deploy-%: stage-%
	ssh $(BOB) sudo systemctl restart minecraft-server-$*.service

rollback-pwppp rollback-gigglesomething: rollback-%:
	ssh $(BOB) sudo nix-env --profile $(MINECRAFT_PROFILE)-$* --rollback
	ssh $(BOB) sudo systemctl restart minecraft-server-$*.service

build-minecraft: build-pwppp build-gigglesomething

stage-minecraft: stage-pwppp stage-gigglesomething

deploy-minecraft: deploy-pwppp deploy-gigglesomething

rollback-minecraft: rollback-pwppp rollback-gigglesomething
