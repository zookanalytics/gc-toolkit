---
name: converse-closeout-collapse
description: The decisions behind collapsing converse closeout to a plain close — what the early-retire was, what was kept, and where the change diverged from the directive's literal text.
---

# Collapsing converse closeout to a single primitive

The directive: make closing the visit the whole act, so the DONE band is a
pure closed-timestamp window query with no per-row state, and reduce or remove
`gc-helm dismiss`. This records the decisions the directive delegated, and the
one place the code diverged from its literal wording.

## Two subsystems, not one

`gc.dismissed_at` and `gc.outcome=dismissed` read as one "dismissed" concept,
but two different subsystems consumed them, and the collapse removes only one:

- **The DONE band** (`services/helm/internal/source/beads.go`, gatherRig's
  closed pass) read `gc.dismissed_at` through the `dismissed()` helper to
  retire a closed anchor's row early. That was the early-retire this change
  removes: the helper and the two closed-pass skips are gone, and the band now
  carries no per-row state.
- **The sittings section** (`services/helm/internal/source/facts.go`,
  `newSitting`) reads `gc.outcome` into `Sitting.Outcome` — the OUTCOME column,
  "what a closed sitting closed on." Every visit-close path stamps it
  (`converse-close-out.sh`: moot/benign; `signoff.sh`: recorded/superseded;
  the agent's own sign-off). It is not the early-retire, and the collapse
  keeps it.

## Decisions

**Kept `gc.outcome=dismissed`.** The directive lists "the dismissed_at /
outcome stamping" together as the early-retire to delete, but the code shows
the outcome word feeds the sittings OUTCOME column, a live surface the collapse
does not touch. Dropping it would regress a dismissed sitting to a blank "—"
outcome, inconsistent with every other close path. So `cmd_dismiss` keeps the
outcome-stamp-then-close precondition; only the `gc.dismissed_at` writes go.

**Removed the early-retire whole.** The two closed-pass skips and the
`dismissed()` helper in beads.go; the `gc.dismissed_at` stamps in `cmd_dismiss`
on both the subject and each closed visit. With them gone the DONE band carries
no per-row state.

**Removed the board's "dismiss to clear" affordance.** The tile NEEDS phrase
(`board/derive.go`), the terminal legend (`cmd/helm-svc/board.go`), and the
web legend (`web/src/App.tsx`) advertised a manual clear that no longer exists.
They now say a row ages out of the window on its own. This was not in the
directive's explicit list, but it is the "no per-row clear" decision applied to
the surfaces that named the old one.

**Reduced `gc-helm dismiss`, did not remove it.** Its only caller is the
operator, via the copyable control the converse prompt prints. It stays as the
operator's ergonomic "end this sitting": subject inference, visit-id
resolution, and the close. What it no longer does is touch the board.

**Actor-guard: the operator's close path force-closes, unchanged.** bd's
close-authority guard lives in the external `bd` binary, not this repo, so
changing the guard is out of scope. `cmd_dismiss` keeps its plain-close-then-
`--force` ladder.

## Migration

Beads closed before this change still carry `gc.dismissed_at`. The marker is
now inert: a previously-dismissed row within the window reappears in the DONE
band and ages out on the clock like any other. If the band feels cluttered,
shorten `GC_HELM_DONE_WINDOW`; there is no per-row clear.
