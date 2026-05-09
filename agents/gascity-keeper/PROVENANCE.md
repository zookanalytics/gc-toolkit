# Agent: gascity-keeper

**Status:** native
**Source:** N/A (gc-toolkit-original)
**Drift:** N/A

## Goals

Operator-facing conversational front-end for the gascity rig's upstream
lifecycle. Knows the `origin/upstream` fork convention, the operator-gated
PR rule, and the two `mol-upstream-gc-…` mols. Dispatches polecats for
mechanical work; handles the conversational tail (rebase summary surfacing,
PR title/body refinement, ready-to-paste `gh` commands) itself.

## Why we built this

Two recurring upstream-lifecycle workflows for gascity's fork
(zookanalytics/gascity → gastownhall/gascity) needed agent support without
ceding the operator's "is this PR-worthy?" judgment to the harness:

1. **Sync from upstream** — rebase `origin/main` onto `upstream/main`,
   drop already-landed commits, run tests, install, push.
2. **Prep an upstream PR** — extract a single local-fork commit, scrub
   city-internal references from the message, push a feature branch,
   draft PR title/body for operator review.

A general-purpose polecat could run the mechanical parts of either
workflow, but the conversational tail (review the PR draft, decide on a
companion issue, paste the final `gh` command) is what the keeper owns.

## Notes

Rig-scoped to gascity, on-demand only — no `[[named_session]]` entry in
`pack.toml`. Matches the concierge / architect / consult-host pattern:
spawned by an operator command, prime-sweeps for handback beads, surfaces
artifacts when engaged, drains on idle.

Part of the gascity-management family (`mol-upstream-gc-…` mols + this
keeper). If the family grows past 3-4 mols, extract to a sub-pack loaded
only into the gascity rig.

## Related artifacts

- `formulas/mol-upstream-gc-rebase.toml` — the rebase mol the keeper
  dispatches on "rebase from upstream" / "sync from upstream" commands.
- `formulas/mol-upstream-gc-pr-prep.toml` — the PR-prep mol the keeper
  dispatches on "prep PR for &lt;sha&gt;" commands; this mol hands the
  bead back to the keeper for the title/body conversation.
- `docs/gascity-local-patching.md` — the operator-level doc the keeper
  references on prime; describes when local-patching is appropriate and
  the bar for promoting a commit to an upstream PR candidate.
