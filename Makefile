.PHONY: check-host hugepages-inputs refresh-pwppp refresh-gigglesomething refresh-packwiz boot switch build build-deepthought deploy-deepthought boot-deepthought build-bob deploy-bob boot-bob build-wintermute deploy-wintermute boot-wintermute build-minecraft stage-minecraft deploy-minecraft rollback-minecraft
.PHONY: build-pwppp build-gigglesomething stage-pwppp stage-gigglesomething deploy-pwppp deploy-gigglesomething rollback-pwppp rollback-gigglesomething

override HOST := $(shell hostname -s)
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

override define require_host
$(if $(filter $(HOST),deepthought $(1)),,$(error Only deepthought or $(1) may run this target (current host: $(HOST)).))
endef

override define require_self
$(if $(filter $(HOST),$(1)),,$(error This target must run on $(1) (current host: $(HOST)).))
endef

check-host:
	@if [ "$(HOST)" != "deepthought" ] && [ "$(HOST)" != "bob" ] && [ "$(HOST)" != "wintermute" ]; then \
		printf '%s\n' "Unsupported host '$(HOST)'; expected one of: $(SUPPORTED_HOSTS)." >&2; \
		exit 2; \
	fi

hugepages-inputs:
	./scripts/generate_hugepages_inputs.sh

refresh-pwppp refresh-gigglesomething: refresh-%:
	$(call require_host,bob)
	cd systems/bob/minecraft/$* && nix shell ../../../..#nixosConfigurations.bob.pkgs.packwiz -c packwiz refresh
	@set -eu; \
	output="$$(nix build --impure --expr 'let pkgs = (builtins.getFlake (toString ./.)).nixosConfigurations.bob.pkgs; in pkgs.fetchPackwizModpack { src = ./systems/bob/minecraft/$*; side = "server"; packHash = pkgs.lib.fakeHash; }' --no-link 2>&1 || :)"; \
	hash="$$(printf '%s\n' "$$output" | sed -n 's/^ *got: *\(sha256-[A-Za-z0-9+/]\{43\}=\)$$/\1/p')"; \
	test -n "$$hash" || { printf '%s\n' "$$output" >&2; exit 1; }; \
	sed -i "/pname = \"$*-server\"/,/^  };/s|packHash = \".*\";|packHash = \"$$hash\";|" systems/bob/services/minecraft.nix; \
	echo "Updated $* packHash to $$hash"

refresh-packwiz: refresh-pwppp refresh-gigglesomething

build: check-host
	@$(MAKE) --no-print-directory build-$(HOST)

switch: check-host
	@$(MAKE) --no-print-directory deploy-$(HOST)

boot: check-host
	@$(MAKE) --no-print-directory boot-$(HOST)

build-deepthought:
	$(call require_self,deepthought)
	@$(MAKE) --no-print-directory hugepages-inputs
	nh os build -H deepthought .
	nh home build . -c deepthought

deploy-deepthought:
	$(call require_self,deepthought)
	@$(MAKE) --no-print-directory hugepages-inputs
	nh os switch -H deepthought .
	nh home switch . -c deepthought

boot-deepthought:
	$(call require_self,deepthought)
	@$(MAKE) --no-print-directory hugepages-inputs
	nh os boot -H deepthought .

ifeq ($(HOST),bob)
build-bob deploy-bob boot-bob: hugepages-inputs
endif

build-bob:
	$(call require_host,bob)
	nh os build -H bob --diff never .
	#nix copy --to ssh-ng://wonko@bob.4amlunch.net ./result
	#ssh wonko@bob.4amlunch.net nix store diff-closures /run/current-system "$$(readlink -f result)"

ifeq ($(HOST),bob)
deploy-bob:
	$(call require_host,bob)
	nh os switch -H bob --diff never .
else
deploy-bob: build-bob
	$(call require_host,bob)
	NIX_SSHOPTS='-F /home/wonko/.ssh/config -o ControlMaster=no -o ControlPath=none' nix copy --no-check-sigs --to ssh-ng://$(BOB) ./result
	$(BOB_SSH) sudo --non-interactive "$$(readlink -f result)/bin/switch-to-configuration" switch
	$(BOB_SSH) sudo --non-interactive nix build --no-link --profile /nix/var/nix/profiles/system "$$(readlink -f result)"
	$(BOB_SSH) sudo --non-interactive "$$(readlink -f result)/bin/switch-to-configuration" boot
endif

boot-bob:
	$(call require_self,bob)
	nh os boot -H bob --diff never .

build-wintermute:
	$(call require_host,wintermute)
	@$(WINTERMUTE_BUILD)

deploy-wintermute:
	$(call require_host,wintermute)
	@set -eu; \
	generation="$$( $(WINTERMUTE_BUILD) )"; \
	$(WINTERMUTE_ACTIVATE)

boot-wintermute:
	@printf '%s\n' "Wintermute uses Home Manager; make boot is unsupported." >&2
	@exit 2

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
	$(call require_host,bob)
	ssh $(BOB) sudo nix-env --profile $(MINECRAFT_PROFILE)-$* --rollback
	ssh $(BOB) sudo systemctl restart minecraft-server-$*.service

build-minecraft: build-pwppp build-gigglesomething

stage-minecraft: stage-pwppp stage-gigglesomething

deploy-minecraft: deploy-pwppp deploy-gigglesomething

rollback-minecraft: rollback-pwppp rollback-gigglesomething
