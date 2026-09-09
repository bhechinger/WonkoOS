.PHONY: check-host hugepages-inputs refresh-pwppp refresh-gigglesomething refresh-packwiz boot switch build build-deepthought deploy-deepthought boot-deepthought build-bob deploy-bob boot-bob build-wintermute deploy-wintermute boot-wintermute build-minecraft stage-minecraft deploy-minecraft rollback-minecraft
.PHONY: build-pwppp build-gigglesomething stage-pwppp stage-gigglesomething deploy-pwppp deploy-gigglesomething rollback-pwppp rollback-gigglesomething

override SHELL := /bin/sh
ifneq ($(wildcard /proc/sys/kernel/hostname),)
override HOST := $(firstword $(subst ., ,$(file </proc/sys/kernel/hostname)))
else
override HOST := $(shell /bin/hostname -s)
endif
SUPPORTED_HOSTS := deepthought bob wintermute
BOB := wonko@bob.4amlunch.net
BOB_SSH := ssh -F /home/wonko/.ssh/config -o ControlMaster=no -o ControlPath=none -T $(BOB)
WINTERMUTE := wonko@wintermute.lan
WINTERMUTE_SSHOPTS := -F /dev/null -o BatchMode=yes
WINTERMUTE_SSH := ssh $(WINTERMUTE_SSHOPTS) -T $(WINTERMUTE)
WINTERMUTE_STORE := ssh-ng://$(WINTERMUTE)
WINTERMUTE_HOME := .\#homeConfigurations.wintermute.activationPackage
ifeq ($(HOST),wintermute)
WINTERMUTE_BUILD := nix build $(WINTERMUTE_HOME) --no-link --print-out-paths
WINTERMUTE_ACTIVATE = "$$generation/activate"
else
WINTERMUTE_BUILD := NIX_SSHOPTS='$(WINTERMUTE_SSHOPTS)' nix build --eval-store daemon --store $(WINTERMUTE_STORE) $(WINTERMUTE_HOME) --no-link --print-out-paths
WINTERMUTE_ACTIVATE = $(WINTERMUTE_SSH) "$$generation/activate"
endif
MINECRAFT_PROFILE := /nix/var/nix/profiles/per-user/root/minecraft

check-host:
	@if [ "$(HOST)" != "deepthought" ] && [ "$(HOST)" != "bob" ] && [ "$(HOST)" != "wintermute" ]; then \
		printf '%s\n' "Unsupported host '$(HOST)'; expected one of: $(SUPPORTED_HOSTS)." >&2; \
		exit 2; \
	fi

hugepages-inputs:
	./scripts/generate_hugepages_inputs.sh

ifneq ($(filter $(HOST),deepthought bob),)
refresh-pwppp refresh-gigglesomething: refresh-%:
	cd systems/bob/minecraft/$* && nix shell ../../../..#nixosConfigurations.bob.pkgs.packwiz -c packwiz refresh
	@set -eu; \
	output="$$(nix build --impure --expr 'let pkgs = (builtins.getFlake (toString ./.)).nixosConfigurations.bob.pkgs; in pkgs.fetchPackwizModpack { src = ./systems/bob/minecraft/$*; side = "server"; packHash = pkgs.lib.fakeHash; }' --no-link 2>&1 || :)"; \
	hash="$$(printf '%s\n' "$$output" | sed -n 's/^ *got: *\(sha256-[A-Za-z0-9+/]\{43\}=\)$$/\1/p')"; \
	test -n "$$hash" || { printf '%s\n' "$$output" >&2; exit 1; }; \
	sed -i "/pname = \"$*-server\"/,/^  };/s|packHash = \".*\";|packHash = \"$$hash\";|" systems/bob/services/minecraft.nix; \
	echo "Updated $* packHash to $$hash"
else
refresh-pwppp refresh-gigglesomething:
	$(error Only deepthought or bob may run this target (current host: $(HOST)).)
endif

refresh-packwiz: refresh-pwppp refresh-gigglesomething

build: check-host
	@$(MAKE) --no-print-directory build-$(HOST)

switch: check-host
	@$(MAKE) --no-print-directory deploy-$(HOST)

boot: check-host
	@$(MAKE) --no-print-directory boot-$(HOST)

ifeq ($(HOST),deepthought)
build-deepthought:
	@$(MAKE) --no-print-directory hugepages-inputs
	nh os build -H deepthought .
	nh home build . -c deepthought

deploy-deepthought:
	@$(MAKE) --no-print-directory hugepages-inputs
	nh os switch -H deepthought .
	nh home switch . -c deepthought

boot-deepthought:
	@$(MAKE) --no-print-directory hugepages-inputs
	nh os boot -H deepthought .
else
build-deepthought deploy-deepthought boot-deepthought:
	$(error This target must run on deepthought (current host: $(HOST)).)
endif

ifneq ($(filter $(HOST),deepthought bob),)
ifeq ($(HOST),bob)
build-bob deploy-bob boot-bob: hugepages-inputs
endif

build-bob:
	nh os build -H bob --diff never .
	#nix copy --to ssh-ng://wonko@bob.4amlunch.net ./result
	#ssh wonko@bob.4amlunch.net nix store diff-closures /run/current-system "$$(readlink -f result)"

ifeq ($(HOST),bob)
deploy-bob:
	nh os switch -H bob --diff never .

boot-bob:
	nh os boot -H bob --diff never .
else
deploy-bob: build-bob
	NIX_SSHOPTS='-F /home/wonko/.ssh/config -o ControlMaster=no -o ControlPath=none' nix copy --no-check-sigs --to ssh-ng://$(BOB) ./result
	$(BOB_SSH) sudo --non-interactive "$$(readlink -f result)/bin/switch-to-configuration" switch
	$(BOB_SSH) sudo --non-interactive nix build --no-link --profile /nix/var/nix/profiles/system "$$(readlink -f result)"
	$(BOB_SSH) sudo --non-interactive "$$(readlink -f result)/bin/switch-to-configuration" boot

boot-bob:
	$(error This target must run on bob (current host: $(HOST)).)
endif
else
build-bob deploy-bob boot-bob:
	$(error Only deepthought or bob may run this target (current host: $(HOST)).)
endif

ifneq ($(filter $(HOST),deepthought wintermute),)
build-wintermute:
	@$(WINTERMUTE_BUILD)

deploy-wintermute:
	@set -eu; \
	generation="$$( $(WINTERMUTE_BUILD) )"; \
	$(WINTERMUTE_ACTIVATE)
else
build-wintermute deploy-wintermute:
	$(error Only deepthought or wintermute may run this target (current host: $(HOST)).)
endif

boot-wintermute:
	$(error Wintermute uses Home Manager; make boot is unsupported.)

ifneq ($(filter $(HOST),deepthought bob),)
build-pwppp build-gigglesomething: build-%: refresh-%
	nix build .#nixosConfigurations.bob.config.system.build.minecraftDeployments.$* --out-link result-minecraft-$*

stage-pwppp stage-gigglesomething: stage-%: build-%
	@new="$$(readlink -f result-minecraft-$*)"; \
	old="$$($(BOB_SSH) readlink -f $(MINECRAFT_PROFILE)-$* 2>/dev/null || :)"; \
	if [ "$$new" = "$$old" ]; then \
		echo "$*: unchanged; skipping stage"; \
	else \
		nix copy --no-check-sigs --to ssh-ng://$(BOB) ./result-minecraft-$*; \
	fi

deploy-pwppp deploy-gigglesomething: deploy-%: stage-%
	@new="$$(readlink -f result-minecraft-$*)"; \
	old="$$($(BOB_SSH) readlink -f $(MINECRAFT_PROFILE)-$* 2>/dev/null || :)"; \
	if [ "$$new" = "$$old" ]; then \
		echo "$*: unchanged; skipping deploy"; \
	else \
		$(BOB_SSH) sudo nix-env --profile $(MINECRAFT_PROFILE)-$* --set "$$new" && \
		$(BOB_SSH) sudo systemctl restart minecraft-server-$*.service; \
	fi

rollback-pwppp rollback-gigglesomething: rollback-%:
	ssh $(BOB) sudo nix-env --profile $(MINECRAFT_PROFILE)-$* --rollback
	ssh $(BOB) sudo systemctl restart minecraft-server-$*.service
else
build-pwppp build-gigglesomething stage-pwppp stage-gigglesomething deploy-pwppp deploy-gigglesomething rollback-pwppp rollback-gigglesomething:
	$(error Only deepthought or bob may run this target (current host: $(HOST)).)
endif

build-minecraft: build-pwppp build-gigglesomething

stage-minecraft: stage-pwppp stage-gigglesomething

deploy-minecraft: deploy-pwppp deploy-gigglesomething

rollback-minecraft: rollback-pwppp rollback-gigglesomething
