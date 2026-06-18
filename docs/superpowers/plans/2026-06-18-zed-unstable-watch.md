# Zed Unstable Watch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a daily Home Manager user timer that switches Zed back to `unstable-pkgs.zed-editor` once unstable has Zed 1.7.2 or newer, then removes itself.

**Architecture:** A dedicated Home Manager module defines a generated shell script, one-shot user service, and daily user timer. The script evaluates unstable Zed, edits the temporary pin out of the repo when ready, formats and relocks the Home Manager flake, then runs `home-manager switch --flake ./home#wonko`.

**Tech Stack:** Nix flakes, Home Manager, systemd user timers, POSIX shell via `writeShellApplication`.

---

### Task 1: Add Watcher Module

**Files:**
- Create: `home/zed-unstable-watch.nix`
- Modify: `home/flake.nix`

- [ ] Add `home/zed-unstable-watch.nix` with a generated script, user service, and daily timer.
- [ ] Import `./zed-unstable-watch.nix` from `home/flake.nix`.
- [ ] Run `nixfmt home/zed-unstable-watch.nix home/flake.nix`.

### Task 2: Verify Build and Script

**Files:**
- Verify: `home/zed-unstable-watch.nix`

- [ ] Run `nix eval --raw ./home#homeConfigurations.wonko.config.systemd.user.timers.zed-unstable-watch.Timer.OnCalendar`.
- [ ] Run `nix build ./home#homeConfigurations.wonko.activationPackage --out-link result`.
- [ ] Activate with `./result/activate`.
- [ ] Verify `systemctl --user list-timers --all zed-unstable-watch.timer`.

### Task 3: Final State Check

**Files:**
- Verify: `home/flake.nix`
- Verify: `home/development.nix`
- Verify: `home/flake.lock`

- [ ] Confirm `zeditor --version` still reports 1.7.2 from the temporary pin.
- [ ] Confirm git diff only contains the Zed pin plus the watcher and docs.
