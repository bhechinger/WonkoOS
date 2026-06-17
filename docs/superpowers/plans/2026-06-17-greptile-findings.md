# Greptile Findings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Address the findings raised by Greptile's review of the current WonkoOS configuration.

**Architecture:** Keep the fixes local to the modules Greptile identified. Make implicit NixOS module behavior explicit where it prevents future false positives, remove risky Docker prune behavior, and document the Codex sandbox trade-off at the point where the override is defined.

**Tech Stack:** Nix flakes, NixOS modules, Home Manager flake overlay, Greptile CLI.

---

## Greptile Run Context

Greptile cannot review a clean `main` branch against itself. The full-repo synthetic empty-base attempt failed because Greptile requires shared real history and did not return retrievable findings. The usable review was run against the largest valid real-history range:

```bash
greptile review -b 6fceece --agent --json
```

Findings:

- P1: `systems/deepthought/atuin.nix` may leave Atuin enabled without a PostgreSQL database/user.
- P2: `systems/deepthought/virtualization.nix` uses Docker auto-prune with `--volumes`.
- P2: `home/flake.nix` disables Codex bubblewrap and landlock isolation without documenting the trade-off.

Local verification showed the Atuin P1 is a false positive for the pinned NixOS module because `services.atuin.database.createLocally` defaults to `true` and contributes the `atuin` PostgreSQL user/database.

## File Structure

- Modify `systems/deepthought/atuin.nix`: explicitly set Atuin's local PostgreSQL database creation behavior and add a short comment explaining why this is intentional.
- Modify `systems/deepthought/virtualization.nix`: remove `--volumes` from Docker auto-prune flags.
- Modify `home/flake.nix`: add a focused comment above the Codex sandbox override explaining the NixOS compatibility trade-off and residual risk.

### Task 1: Make Atuin Database Creation Explicit

**Files:**
- Modify: `systems/deepthought/atuin.nix`

- [ ] **Step 1: Confirm the current merged Atuin/PostgreSQL behavior**

Run:

```bash
nix eval .#nixosConfigurations.deepthought.config.services.atuin.database.createLocally
nix eval .#nixosConfigurations.deepthought.config.services.postgresql.ensureDatabases
nix eval .#nixosConfigurations.deepthought.config.services.postgresql.ensureUsers --json
```

Expected:

```text
true
[ "wonko" "atuin" ]
[{"ensureClauses":{"login":true,"superuser":true},"ensureDBOwnership":true,"name":"wonko"},{"ensureClauses":{},"ensureDBOwnership":true,"name":"atuin"}]
```

- [ ] **Step 2: Edit Atuin config**

In `systems/deepthought/atuin.nix`, replace the `services.atuin` block with:

```nix
    atuin = {
      enable = true;
      openRegistration = true;

      # Keep the default PostgreSQL backend and make the implicit module behavior
      # explicit: this creates the local atuin database and database owner.
      database.createLocally = true;
    };
```

- [ ] **Step 3: Format the file**

Run:

```bash
nixfmt systems/deepthought/atuin.nix
```

Expected: command exits 0.

- [ ] **Step 4: Re-run the merged option checks**

Run:

```bash
nix eval .#nixosConfigurations.deepthought.config.services.atuin.database.createLocally
nix eval .#nixosConfigurations.deepthought.config.services.postgresql.ensureDatabases
nix eval .#nixosConfigurations.deepthought.config.services.postgresql.ensureUsers --json
```

Expected:

```text
true
[ "wonko" "atuin" ]
[{"ensureClauses":{"login":true,"superuser":true},"ensureDBOwnership":true,"name":"wonko"},{"ensureClauses":{},"ensureDBOwnership":true,"name":"atuin"}]
```

- [ ] **Step 5: Commit**

```bash
git add systems/deepthought/atuin.nix
git commit -m "document atuin local database creation"
```

### Task 2: Stop Docker Auto-Prune From Deleting Volumes

**Files:**
- Modify: `systems/deepthought/virtualization.nix`

- [ ] **Step 1: Confirm current prune flags**

Run:

```bash
nix eval .#nixosConfigurations.deepthought.config.virtualisation.docker.autoPrune.flags
```

Expected before the edit:

```text
[ "--all" "--volumes" ]
```

- [ ] **Step 2: Edit Docker auto-prune flags**

In `systems/deepthought/virtualization.nix`, replace:

```nix
        flags = [
          "--all"
          "--volumes"
        ];
```

with:

```nix
        flags = [
          "--all"
        ];
```

- [ ] **Step 3: Format the file**

Run:

```bash
nixfmt systems/deepthought/virtualization.nix
```

Expected: command exits 0.

- [ ] **Step 4: Verify volumes are no longer pruned**

Run:

```bash
nix eval .#nixosConfigurations.deepthought.config.virtualisation.docker.autoPrune.flags
```

Expected:

```text
[ "--all" ]
```

- [ ] **Step 5: Commit**

```bash
git add systems/deepthought/virtualization.nix
git commit -m "avoid pruning docker volumes automatically"
```

### Task 3: Document Codex Sandbox Override

**Files:**
- Modify: `home/flake.nix`

- [ ] **Step 1: Edit the Codex overlay comment**

In `home/flake.nix`, add this comment immediately above `codex = prev.codex.overrideAttrs (old: {`:

```nix
            # Codex's upstream Linux sandbox currently conflicts with this NixOS
            # setup, so the bwrap and landlock checks are patched out below. The
            # wrapper still drops Linux capabilities with setpriv, but Codex
            # subprocesses are intentionally not filesystem/network sandboxed here.
```

- [ ] **Step 2: Format the file**

Run:

```bash
nixfmt home/flake.nix
```

Expected: command exits 0.

- [ ] **Step 3: Verify the Home Manager configuration still evaluates**

Run:

```bash
nix eval ./home#homeConfigurations.wonko.activationPackage.drvPath
```

Expected: command exits 0 and prints a Nix store derivation path ending in `.drv`.

- [ ] **Step 4: Commit**

```bash
git add home/flake.nix
git commit -m "document codex sandbox override"
```

### Task 4: Final Validation

**Files:**
- No additional edits.

- [ ] **Step 1: Format all touched Nix files**

Run:

```bash
nixfmt systems/deepthought/atuin.nix systems/deepthought/virtualization.nix home/flake.nix
```

Expected: command exits 0.

- [ ] **Step 2: Build the NixOS system configuration**

Run:

```bash
nix build .#nixosConfigurations.deepthought.config.system.build.toplevel
```

Expected: command exits 0.

- [ ] **Step 3: Build the Home Manager activation package**

Run:

```bash
nix build ./home#homeConfigurations.wonko.activationPackage
```

Expected: command exits 0.

- [ ] **Step 4: Re-run Greptile on the same real-history range**

Run:

```bash
greptile review -b 6fceece --agent --json
```

Expected: no P1 Atuin finding, no Docker `--volumes` finding, and no undocumented Codex sandbox override finding.
