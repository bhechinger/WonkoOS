---
name: omnigraph-context
description: Maintain durable OmniGraph context for substantive work in any local project. Use at the start and end of project tasks to recall and record decisions, active work, outcomes, and reusable facts; do not use for trivial conversation or when the user says not to persist the task.
---

# OmniGraph context

Use the globally configured `omnigraph` CLI. Its default server is `bob`.

## Select context

Resolve the Git root, or the current directory outside Git, to a physical path.
Choose the graph and context prefix by the first matching rule:

- `/home/wonko/projects/Gevulot/**`: graph `gevulot`, prefix `gevulot:`.
- `/home/wonko/nix/**`: graph `nix`, prefix `nix:`.
- Everything else: graph `projects`, prefix `project:<key>:`, where `key` is
  the first 16 lowercase hex characters of the SHA-256 of the origin URL, or
  of the physical project path when no origin exists.

At the start of substantive work, explicitly query `recent_context` from the
selected graph with its prefix as the `project` parameter. Also query
`recent_context` from `shared` with `shared:` as that parameter. Always pass
`--graph` and `--json`; use only relevant results.

## Persist context

This skill is standing permission to persist concise context created by the
user's authorized work. Record a `remember_context` entry after substantive
work or a material state change. Include only durable facts, decisions,
constraints, blockers, and outcomes needed by a future agent. Use a unique slug
formed from the selected prefix plus `ctx-<UTC epoch nanoseconds>`, `act-writer`
as the actor, and the current UTC date for `at`.

Write to the selected graph by default. Write to `shared` with prefix `shared:`
only when the user explicitly says the information should apply across scopes.
Never copy scoped records into another graph. A new company-specific directory
requires a matching graph and routing rule in the Bob configuration.

Read the graph commit id with `--json` before mutating and pass it with
`--if-commit`. On exit code 4, re-read and reconcile once; do not blindly retry.

Never store credentials, private keys, tokens, personal data, raw transcripts,
hidden reasoning, or verbose tool output. Honor any request not to persist or
to correct context; append a correction rather than rewriting history.
