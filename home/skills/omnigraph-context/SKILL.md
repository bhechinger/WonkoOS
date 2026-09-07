---
name: omnigraph-context
description: Maintain durable OmniGraph context for substantive work in any local project. Use at the start and end of project tasks to recall and record decisions, active work, outcomes, and reusable facts; do not use for trivial conversation or when the user says not to persist the task.
---

# OmniGraph context

Use the globally configured `omnigraph` CLI. Its default server is `bob`.

## Select context

Derive the project graph from the Git remote repository name: remove `.git`,
lowercase it, replace runs of non-alphanumeric characters with `-`, and trim
dashes. Fall back to the Git root directory name when there is no remote.

At the start of substantive project work, query `recent_context`, `ready`, and
`blocked` from that graph and query `recent_context` from `shared`, all with
`--json`. Use only relevant results. If the project graph does not exist, stop
persistence and tell the user it must be declared on Bob; never substitute a
different project graph.

## Persist context

This skill is standing permission to persist concise context created by the
user's authorized work. Record a `remember_context` entry after substantive
work or a material state change. Include only durable facts, decisions,
constraints, blockers, and outcomes needed by a future agent. Use a unique slug
such as `<project>-ctx-<UTC epoch>`, `act-admin` as the actor, and the current
UTC date for `at`.

Write to the project graph by default. Write to `shared` only when the user
explicitly says the information should apply across projects. Never copy
project records into another project graph.

Read the graph commit id with `--json` before mutating and pass it with
`--if-commit`. On exit code 4, re-read and reconcile once; do not blindly retry.

Never store credentials, private keys, tokens, personal data, raw transcripts,
hidden reasoning, or verbose tool output. Honor any request not to persist or
to correct context; append a correction rather than rewriting history.
