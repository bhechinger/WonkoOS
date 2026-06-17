# Saffire FFADO Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the Focusrite Saffire Pro 24 from PipeWire's ALSA FireWire nodes to PipeWire's FFADO driver while preserving Ardour startup readiness and static audio routing.

**Architecture:** Keep PipeWire, WirePlumber, JACK compatibility, and the existing Ardour session model. Add a dedicated Saffire FFADO PipeWire module fragment, stop applying Saffire-specific ALSA WirePlumber policy, and update readiness checks to validate FFADO nodes and ports instead of ALSA FireWire nodes.

**Tech Stack:** NixOS, Home Manager, PipeWire 1.6.x, WirePlumber Lua scripts, FFADO 2.4.9, musnix, shell smoke tests.

---

## Current Context

- `systems/deepthought/audio.nix` already enables `musnix.ffado.enable = true`.
- `systems/deepthought/audio.nix` still applies Saffire-specific `monitor.alsa.rules` headroom policy to `alsa_(input|output).firewire-0x00130e0401c04de0.*`.
- `home/audio.nix` currently has uncommitted readiness-helper changes and has commented out the old AudioFire FFADO fragment.
- `home/wireplumber/saffire-clock.conf` is ALSA-specific and matches the current `alsa_output.firewire-...` and `alsa_input.firewire-...` nodes.
- `home/wireplumber/audio-routes.lua` already routes Ardour to `Pro24-004de0:*` port aliases, which may continue to work under FFADO, but this must be verified after activation.
- `tests/audio-readiness.sh` currently checks for readiness-helper structure, not FFADO-specific names.

## File Structure

- Create `home/pipewire/saffire-ffado.conf`: dedicated PipeWire FFADO module config for the Saffire Pro 24.
- Modify `home/audio.nix`: install the Saffire FFADO config, stop referencing the old AudioFire config, and update Ardour readiness checks from ALSA FireWire nodes to FFADO nodes.
- Modify `systems/deepthought/audio.nix`: remove Saffire-specific ALSA headroom policy while keeping global PipeWire ALSA support for other devices.
- Modify `home/wireplumber/saffire-clock.conf`: remove or disable obsolete ALSA node priority rules for the Saffire.
- Modify `tests/audio-readiness.sh`: make the smoke test assert FFADO readiness and reject Saffire ALSA node names.

### Task 1: Add FFADO-Specific Readiness Test Expectations

**Files:**
- Modify: `tests/audio-readiness.sh`

- [ ] **Step 1: Replace the smoke test with FFADO-specific checks**

Replace `tests/audio-readiness.sh` with:

```sh
#!/usr/bin/env sh
set -eu

audio_nix="${1:-home/audio.nix}"

fail() {
  printf 'audio-readiness: %s\n' "$*" >&2
  exit 1
}

grep -Fq 'node_ready()' "$audio_nix" ||
  fail 'ardour readiness helper must check expected PipeWire node properties'

grep -Fq 'saffire_nodes_ready()' "$audio_nix" ||
  fail 'ardour readiness helper must require ready Saffire nodes'

grep -Fq 'saffire_ffado_output' "$audio_nix" ||
  fail 'ardour readiness helper must target the Saffire FFADO output node'

grep -Fq 'saffire_ffado_input' "$audio_nix" ||
  fail 'ardour readiness helper must target the Saffire FFADO input node'

grep -Fq 'api.ffado' "$audio_nix" ||
  fail 'ardour readiness helper must identify FFADO-backed nodes'

grep -Fq 'readiness_failures()' "$audio_nix" ||
  fail 'ardour readiness helper must report missing readiness conditions'

grep -Fq 'required_consecutive_ready_checks=2' "$audio_nix" ||
  fail 'ardour readiness helper must require stable readiness across two polls'

if grep -Fq 'alsa_output.firewire-0x00130e0401c04de0' "$audio_nix"; then
  fail 'ardour readiness helper must not target the Saffire ALSA output node'
fi

if grep -Fq 'alsa_input.firewire-0x00130e0401c04de0' "$audio_nix"; then
  fail 'ardour readiness helper must not target the Saffire ALSA input node'
fi

if grep -Fq 'min_boot_age_seconds' "$audio_nix"; then
  fail 'ardour readiness helper must not use a static boot-age delay'
fi

if grep -Fq 'wait_for_saffire_boot_settle' "$audio_nix"; then
  fail 'ardour readiness helper must not call a static Saffire settle sleep'
fi

if grep -Fq '.info.state == "running"' "$audio_nix"; then
  fail 'ardour readiness helper must not require idle PipeWire nodes to be running'
fi

printf 'audio-readiness: ok\n'
```

- [ ] **Step 2: Run the test and confirm it fails before implementation**

Run:

```bash
sh tests/audio-readiness.sh
```

Expected: FAIL with `ardour readiness helper must target the Saffire FFADO output node`.

- [ ] **Step 3: Commit the failing test**

```bash
git add tests/audio-readiness.sh
git commit -m "test saffire ffado readiness expectations"
```

### Task 2: Add the Saffire FFADO PipeWire Fragment

**Files:**
- Create: `home/pipewire/saffire-ffado.conf`
- Modify: `home/audio.nix`

- [ ] **Step 1: Create the Saffire FFADO config**

Create `home/pipewire/saffire-ffado.conf`:

```spa
context.modules = [
  {
    name = libpipewire-module-ffado-driver
    args = {
      driver.mode = duplex
      ffado.devices = [ "hw:1" ]
      ffado.period-size = 1024
      ffado.period-num = 3
      ffado.sample-rate = 48000
      ffado.realtime = true
      ffado.rtprio = 93
      sink.props = {
        node.name = "saffire_ffado_output"
        node.description = "Saffire Pro 24 FFADO Output"
        priority.driver = 4000
        priority.session = 4000
      }
      source.props = {
        node.name = "saffire_ffado_input"
        node.description = "Saffire Pro 24 FFADO Input"
        priority.driver = 200
        priority.session = 200
      }
    }
    flags = [ ifexists nofail ]
  }
]
```

- [ ] **Step 2: Wire the fragment into Home Manager**

In `home/audio.nix`, replace:

```nix
  # audiofireFfadoRule = builtins.readFile ./pipewire/audiofire-ffado.conf;
```

with:

```nix
  saffireFfadoRule = builtins.readFile ./pipewire/saffire-ffado.conf;
```

Then replace:

```nix
  # xdg.configFile."pipewire/pipewire.conf.d/51-audiofire-ffado.conf".text = audiofireFfadoRule;
```

with:

```nix
  xdg.configFile."pipewire/pipewire.conf.d/52-saffire-ffado.conf".text = saffireFfadoRule;
```

- [ ] **Step 3: Verify Home Manager evaluation includes the fragment**

Run:

```bash
nix eval ./home#homeConfigurations.wonko.activationPackage.drvPath
```

Expected: command exits 0 and prints a Nix store derivation path ending in `.drv`.

- [ ] **Step 4: Commit the FFADO fragment wiring**

```bash
git add home/audio.nix home/pipewire/saffire-ffado.conf
git commit -m "add saffire ffado pipewire module"
```

### Task 3: Convert Ardour Readiness From ALSA to FFADO

**Files:**
- Modify: `home/audio.nix`
- Test: `tests/audio-readiness.sh`

- [ ] **Step 1: Update readiness node names**

In the `ardourPipewireReady` script inside `home/audio.nix`, replace:

```sh
      saffire_sink="alsa_output.firewire-0x00130e0401c04de0.multichannel-output"
      saffire_source="alsa_input.firewire-0x00130e0401c04de0.multichannel-input"
```

with:

```sh
      saffire_sink="saffire_ffado_output"
      saffire_source="saffire_ffado_input"
```

- [ ] **Step 2: Update the node readiness predicate**

Replace the current `node_ready()` body with:

```sh
      node_ready() {
        local node_name="$1"
        local media_class="$2"

        timeout 3 pw-dump |
          jq -e \
            --arg node_name "$node_name" \
            --arg media_class "$media_class" '
            any(.[]; .type == "PipeWire:Interface:Node" and
              .info.props["node.name"] == $node_name and
              .info.props["media.class"] == $media_class and
              (.info.props["api.ffado.path"]? or .info.props["api.ffado.device"]? or .info.props["api.ffado.id"]?))
          ' >/dev/null
      }
```

- [ ] **Step 3: Update `saffire_nodes_ready()`**

Replace:

```sh
      saffire_nodes_ready() {
        node_ready "$saffire_sink" "Audio/Sink" "playback" &&
          node_ready "$saffire_source" "Audio/Source" "capture"
      }
```

with:

```sh
      saffire_nodes_ready() {
        node_ready "$saffire_sink" "Audio/Sink" &&
          node_ready "$saffire_source" "Audio/Source"
      }
```

- [ ] **Step 4: Update Saffire port checks**

Replace `saffire_ports_exist()` with:

```sh
      saffire_ports_exist() {
        has_port "Pro24-004de0:capture_AUX0" &&
          has_port "Pro24-004de0:capture_AUX4" &&
          has_port "Pro24-004de0:capture_AUX5" &&
          has_port "Pro24-004de0:playback_FL" &&
          has_port "Pro24-004de0:playback_FR"
      }
```

- [ ] **Step 5: Run the readiness smoke test**

Run:

```bash
sh tests/audio-readiness.sh
```

Expected:

```text
audio-readiness: ok
```

- [ ] **Step 6: Commit the readiness conversion**

```bash
git add home/audio.nix tests/audio-readiness.sh
git commit -m "convert saffire readiness to ffado"
```

### Task 4: Remove Obsolete Saffire ALSA Policy

**Files:**
- Modify: `systems/deepthought/audio.nix`
- Modify: `home/wireplumber/saffire-clock.conf`

- [ ] **Step 1: Remove Saffire-specific ALSA headroom**

In `systems/deepthought/audio.nix`, delete this block:

```nix
      wireplumber.extraConfig."51-saffire-headroom" = {
        "monitor.alsa.rules" = [
          {
            matches = [
              {
                "node.name" = "~alsa_(input|output).firewire-0x00130e0401c04de0.*";
              }
            ];
            actions.update-props = {
              "api.alsa.headroom" = 1024;
            };
          }
        ];
      };
```

Keep this block unchanged because other ALSA devices can still use PipeWire ALSA support:

```nix
      alsa = {
        enable = true;
        support32Bit = true;
      };
```

- [ ] **Step 2: Disable the obsolete ALSA clock-priority file**

Replace `home/wireplumber/saffire-clock.conf` with:

```spa
# Saffire is driven by PipeWire's FFADO module. The former monitor.alsa rules
# intentionally stay disabled because the ALSA FireWire nodes should not own
# Saffire clock priority anymore.
```

- [ ] **Step 3: Format the Nix files**

Run:

```bash
nixfmt systems/deepthought/audio.nix home/audio.nix
```

Expected: command exits 0.

- [ ] **Step 4: Verify the NixOS system evaluates**

Run:

```bash
nix eval .#nixosConfigurations.deepthought.config.system.build.toplevel.drvPath
```

Expected: command exits 0 and prints a Nix store derivation path ending in `.drv`.

- [ ] **Step 5: Commit policy cleanup**

```bash
git add systems/deepthought/audio.nix home/wireplumber/saffire-clock.conf home/audio.nix
git commit -m "remove saffire alsa policy"
```

### Task 5: Activate and Verify Live FFADO Ports

**Files:**
- Modify only if live port aliases differ: `home/wireplumber/audio-routes.lua`
- Modify only if live node properties differ: `home/audio.nix`

- [ ] **Step 1: Build the system and Home Manager configurations**

Run:

```bash
nix build .#nixosConfigurations.deepthought.config.system.build.toplevel
nix build ./home#homeConfigurations.wonko.activationPackage
```

Expected: both commands exit 0.

- [ ] **Step 2: Switch the configuration**

Run:

```bash
make switch
```

Expected: command exits 0.

- [ ] **Step 3: Restart user audio services**

Run:

```bash
systemctl --user restart pipewire.service wireplumber.service pipewire-pulse.service
```

Expected: command exits 0.

- [ ] **Step 4: Confirm the FFADO module is loaded and ALSA Saffire nodes are gone**

Run:

```bash
pw-dump | jq -r '.[] | select(.type == "PipeWire:Interface:Node") | .info.props["node.name"]' | grep -E 'saffire_ffado|firewire-0x00130e0401c04de0'
```

Expected:

```text
saffire_ffado_output
saffire_ffado_input
```

No `alsa_output.firewire-0x00130e0401c04de0...` or `alsa_input.firewire-0x00130e0401c04de0...` lines should appear.

- [ ] **Step 5: Confirm the port aliases used by static routing**

Run:

```bash
pw-link -io | grep -E '^Pro24-004de0:(capture_AUX0|capture_AUX4|capture_AUX5|playback_FL|playback_FR)$'
```

Expected:

```text
Pro24-004de0:capture_AUX0
Pro24-004de0:capture_AUX4
Pro24-004de0:capture_AUX5
Pro24-004de0:playback_FL
Pro24-004de0:playback_FR
```

- [ ] **Step 6: If FFADO changed aliases, update static routes**

If Step 5 prints different aliases, replace only the Saffire entries in `home/wireplumber/audio-routes.lua`. For example, if FFADO exposes `saffire_ffado_input:capture_AUX0` and `saffire_ffado_output:playback_FL`, replace:

```lua
  { output = "ardour:Master/audio_out 1",     input = "Pro24-004de0:playback_FL" },
  { output = "ardour:Master/audio_out 2",     input = "Pro24-004de0:playback_FR" },
  { output = "ardour:auditioner/audio_out 1", input = "Pro24-004de0:playback_FL" },
  { output = "ardour:auditioner/audio_out 2", input = "Pro24-004de0:playback_FR" },
  { output = "ardour:Click/audio_out 1",      input = "Pro24-004de0:playback_FL" },
  { output = "ardour:Click/audio_out 2",      input = "Pro24-004de0:playback_FR" },
  { output = "Pro24-004de0:capture_AUX0",     input = "ardour:Mic/audio_in 1" },
  { output = "Pro24-004de0:capture_AUX4",     input = "ardour:Mac/audio_in 1" },
  { output = "Pro24-004de0:capture_AUX5",     input = "ardour:Mac/audio_in 2" },
```

with:

```lua
  { output = "ardour:Master/audio_out 1",     input = "saffire_ffado_output:playback_FL" },
  { output = "ardour:Master/audio_out 2",     input = "saffire_ffado_output:playback_FR" },
  { output = "ardour:auditioner/audio_out 1", input = "saffire_ffado_output:playback_FL" },
  { output = "ardour:auditioner/audio_out 2", input = "saffire_ffado_output:playback_FR" },
  { output = "ardour:Click/audio_out 1",      input = "saffire_ffado_output:playback_FL" },
  { output = "ardour:Click/audio_out 2",      input = "saffire_ffado_output:playback_FR" },
  { output = "saffire_ffado_input:capture_AUX0", input = "ardour:Mic/audio_in 1" },
  { output = "saffire_ffado_input:capture_AUX4", input = "ardour:Mac/audio_in 1" },
  { output = "saffire_ffado_input:capture_AUX5", input = "ardour:Mac/audio_in 2" },
```

- [ ] **Step 7: Verify Ardour readiness**

Run:

```bash
ardour-pipewire-ready
```

Expected:

```text
ardour-pipewire-ready: PipeWire Saffire audio and MIDI ports are ready
```

- [ ] **Step 8: Commit any live alias fixes**

If Task 5 Step 6 changed files, run:

```bash
git add home/wireplumber/audio-routes.lua home/audio.nix
git commit -m "match saffire ffado live port aliases"
```

If no files changed, skip this commit.

### Task 6: Final Validation

**Files:**
- No additional edits.

- [ ] **Step 1: Run local smoke tests**

Run:

```bash
sh tests/audio-readiness.sh
```

Expected:

```text
audio-readiness: ok
```

- [ ] **Step 2: Build both configuration outputs**

Run:

```bash
nix build .#nixosConfigurations.deepthought.config.system.build.toplevel
nix build ./home#homeConfigurations.wonko.activationPackage
```

Expected: both commands exit 0.

- [ ] **Step 3: Confirm no committed config targets Saffire ALSA FireWire nodes**

Run:

```bash
rg -n 'alsa_(input|output)\.firewire-0x00130e0401c04de0|monitor\.alsa\.rules.*saffire|api\.alsa\.headroom' home systems tests
```

Expected: no output.

- [ ] **Step 4: Confirm FFADO config remains present**

Run:

```bash
rg -n 'saffire_ffado|libpipewire-module-ffado-driver|ffado.devices' home systems tests
```

Expected output includes:

```text
home/pipewire/saffire-ffado.conf
home/audio.nix
tests/audio-readiness.sh
```

- [ ] **Step 5: Commit final validation metadata if needed**

If validation required small fixes, commit them:

```bash
git add home systems tests
git commit -m "validate saffire ffado conversion"
```

If no files changed, skip this commit.

## Design Notes

- Do not disable global `services.pipewire.alsa`; only remove Saffire-specific ALSA node policy. Other devices and 32-bit ALSA clients still depend on it.
- Keep `musnix.ffado.enable = true`; it is already part of the system-level low-latency audio setup.
- Keep the old `home/pipewire/audiofire-ffado.conf` file untouched unless a separate cleanup is requested. It is unrelated hardware and currently not installed by Home Manager after the conversion.
- The plan assumes `hw:1` is the correct FFADO device selector because a prior generated Home Manager fragment used it. If live activation fails to create `saffire_ffado_output` and `saffire_ffado_input`, run `ffado-test ListDevices` and update `ffado.devices` to the detected selector before continuing.
