# Repository instructions

The repository may be edited, tested, committed, and pushed from `deepthought`,
`bob`, or `wintermute`. Only `deepthought` may build or deploy another host;
`bob` and `wintermute` may build and deploy only themselves.

## Scope and routing

Only `bob` and `deepthought` are NixOS flake configurations in this repository.
Treat the host named below as the operational owner of its services.

- `sierra` owns the gateway, DHCP, and authoritative internal DNS. Use
  `systems/sierra/README.md` and `systems/sierra/*.sh`; administer it over SSH.
  Make DNS changes only on Sierra's primary, never on Bob's secondary.
- `bob` owns the server workloads. Use `systems/bob/README.md` and
  `systems/bob/services/`; deploy them from Bob itself or from `deepthought`.
- `deepthought` is the workstation and cross-host build/deployment host. Use
  `systems/deepthought/`, `home/`, and the root `Makefile`.
- `wintermute` is the Apple Silicon macOS laptop. Use
  `systems/wintermute/README.md` and `homeConfigurations.wintermute`; deploy it
  from Wintermute itself or from `deepthought`.
- `basket` owns NAS storage and its HTTPS endpoint. Use
  `systems/basket/README.md` and `systems/basket/*.sh`; administer it over SSH.
- Cloudflare and Playit are external control planes reconciled from
  `systems/bob/services/cloudflared.nix` and
  `systems/bob/services/minecraft.nix`.

# Agent workflow

## Automated flake updates

`make update` is a user-operated, non-agent workflow. Agents must not run,
review, or manage it unless the user explicitly requests that involvement.
Pull requests created by this target are exempt from the workflow below only
when their sole changed file is `flake.lock`; any additional change requires
the full workflow.

For every code change:

1. Switch to `main`, fetch `origin`, update `main` from `origin/main`, and
   create a new branch. Prefix bug-fix branches with `fix/` and feature
   branches with `feat/`.
2. Implement the change and run the required formatting based on the languages
   found in this repo.
3. Commit the change locally before reviewing the diff.
4. Start parallel fresh agent sessions with no inherited implementation
   context (`fork_turns: "none"` or equivalent). Give each reviewer only these
   repository instructions, the original task requirements or acceptance
   criteria, and the current branch or pull-request diff against its base. Do
   not include the implementation conversation, plans, rationale, prior
   findings, or another reviewer's conclusions.

   Have each reviewer independently perform an adversarial review that actively
   tries to falsify the change's correctness. Assess:

   - bugs;
   - security;
   - code quality;
   - DRY violations; and
   - removable complexity.

   Synthesize and deduplicate their findings. Report only actionable issues
   with severity, file/line, and rationale. Address all issues raised by this
   review, commit the fixes, and repeat the clean-context adversarial review
   until clean before continuing.

5. Push the clean branch.
6. Open a pull request.
7. Wait for CI to pass and address any failures.
8. Notify the user only when the pull request is ready for review and merge.
