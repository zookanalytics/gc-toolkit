# Agent: keeper (in pack: gascity-keeper)

**Status:** native
**Source:** N/A (gc-toolkit-original)
**Drift:** N/A

Bare name `keeper` inside the `gascity-keeper` sub-pack. Qualified
externally as `<binding>.keeper` (e.g., `gascity/gascity-keeper.keeper`
when the gascity rig imports this pack under binding `gascity-keeper`).

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

Rig-scoped, on-demand. The sub-pack's `[[named_session]]` block declares
`scope = "rig"` + `mode = "on_demand"`, so the keeper materialises in
whichever rig imports `gascity-keeper` (currently only `gascity`). Matches
the concierge / architect / consult-host lifecycle pattern: spawned by an
operator command (or routed handback bead), prime-sweeps, surfaces
artifacts when engaged, drains on idle.

Originally shipped under `rigs/gc-toolkit/agents/gascity-keeper/` with the
"extract to a sub-pack if the mol family grows past 3-4 mols" rider. The
family now carries four mols (`mol-upstream-gc-{rebase,rebase-rework,
pr-prep,sync}`) plus the rebase doctrine and refinery overlay, so the
extraction landed under `rigs/gc-toolkit/packs/gascity-keeper/`. The
sibling `formulas/`, `template-fragments/`, and `patches/` directories
hold the rest of the bundle.

## Related artifacts

- `formulas/mol-upstream-gc-rebase.toml` — the rebase mol the keeper
  dispatches on "rebase from upstream" / "sync from upstream" commands.
- `formulas/mol-upstream-gc-rebase-rework.toml` — the focused rework mol
  the rebase polecat dispatches per conflicted kept commit; the keeper
  doesn't dispatch this directly but participates in the re-pour loop
  via the `rebase_in_progress` handback.
- `formulas/mol-upstream-gc-pr-prep.toml` — the PR-prep mol the keeper
  dispatches on "prep PR for &lt;sha&gt;" commands; this mol hands the
  bead back to the keeper for the title/body conversation.
- `docs/gascity-local-patching.md` — the operator-level doc the keeper
  references on prime; describes when local-patching is appropriate and
  the bar for promoting a commit to an upstream PR candidate.
- `docs/gascity-agents.md` → "Keeping an `on_demand` session up
  (pin / attach / unpin)" — why this on-demand keeper drains on idle and
  how to keep it up interactively (pin → attach → unpin) instead of just
  `wake`-ing it.
