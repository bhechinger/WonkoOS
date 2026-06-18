# Zed Unstable Watch Design

## Goal

Temporarily keep Zed pinned to the nixpkgs commit that contains `zed-editor` 1.7.2, then automatically switch back to the normal `unstable-nixpkgs` package once unstable has caught up.

## Behavior

A Home Manager user timer runs once per day. The timer starts a service that executes a generated script from the current Home Manager generation.

The script checks the version of `unstable-pkgs.zed-editor` from `./home`. If the version is lower than 1.7.2, it exits successfully and waits for the next timer run. If the version is 1.7.2 or newer, it edits the repo to remove the temporary `zed-nixpkgs` input/import/argument and changes `home/development.nix` back to `unstable-pkgs.zed-editor`.

After editing, the script formats the touched Nix files, refreshes the Home Manager flake lock, and runs `home-manager switch --flake ./home#wonko`. Because the edits remove the watcher module from the Home Manager config, the activation removes the timer and service after the successful switch.

## Components

- `home/zed-unstable-watch.nix`: defines the generated script, one-shot systemd user service, and daily timer.
- `home/flake.nix`: imports the watcher module while the temporary pin is active.
- `home/flake.nix`, `home/development.nix`, and `home/flake.lock`: are edited by the watcher when unstable catches up.

## Error Handling

The script uses strict shell mode and logs each major action through systemd. If evaluation or editing fails, the service exits non-zero and systemd records the failure. The timer remains installed so the next daily run can retry after transient network or lock issues.

## Verification

Manual verification should confirm:

- `unstable-pkgs.zed-editor.version` can be evaluated.
- The Home Manager activation package builds with the timer module enabled.
- The generated script contains the expected repo path and target version.
- Current Zed still resolves to 1.7.2 from the pinned input until unstable catches up.
