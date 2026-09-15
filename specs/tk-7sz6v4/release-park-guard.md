---
name: The release-park disposition guard, and why it is scoped to the park
description: Why gc-helm.sh takeaway refuses a park with no disposition only when --release parks a bead for a person with no existing blocker, which callers moved with it, and which adjacent writers were left for follow-up.
---

# The release-park disposition guard

`tk-s4fg87` proposal §1/§5 and Phase 1 require that a hold be a `blocks` edge,
never prose alone, and that `gc-helm.sh takeaway` "refuse a silent prose-only
park." This bead builds that writer guard and moves the in-repo callers it
would otherwise break.

## What the guard is

`cmd_takeaway` refuses, before any write, a `--release` that parks a bead for a
person — an open anchor, no `--route` — carrying no open blocker, unless the
call names its disposition with `--waiting-on <bead>` (the wait as an edge) or
`--no-wait` (nothing waits, `gc.takeaway_settled=1`). The refusal exits 2 and
writes nothing.

Three cases are exempt, because none leaves an unedged hold:

- **A dispatch** (`--release --route <pool>`) hands the bead to a pool, where it
  is claimable and moving. Its route is its disposition. `first-reaction-dispose`
  actionable already passes `--no-wait` here; the guard requires nothing of it.
- **A bead already held by an open blocker.** The wait is an existing edge, so
  the park sits beside it rather than minting a prose-only hold. The guard reads
  the blockers the way the route-delegation probe does and allows the park when
  one is present; an unreadable probe allows it too, and the future
  `doctor/check-wait-is-an-edge` still reports a truly edgeless one.
- **A bare headline** (no `--release`) changes no state, and a closed anchor
  takes only the quiesce.

## Why the park, not every takeaway

The bead names "any takeaway **that leaves the bead held**." Only `--release`
parks — reopen, unassign, route. A bare `takeaway` stamps a board headline and
changes no lifecycle field; a converse sitting stamps one beside a `demand`
bead that carries the edge, and the converse agent prompt directs an EMPTY
disposition "where the subject is parked for a person" — the converse
demand+edge conversion is `tk-0slbb6` / Phase 2, not this bead. A universal
"every takeaway names a disposition" guard would refuse that live path and the
`(UNSETTLED)` behaviour the settled-key pairing already relies on, where a bare
takeaway clears `gc.takeaway_settled` so no prior sitting's `1` answers for the
park that follows. Scoping the guard to the park refuses the I1 source — a
`--release` that leaves a person a bead held on prose — and leaves both intact.

## Callers moved with the guard

- **`first-reaction-dispose.sh` ruling arm** passed neither flag, on purpose:
  the visit was to be reported by `check-wait-is-an-edge` as an unedged wait.
  It now passes `--waiting-on <visit>`, so the subject waits on the visit as a
  `blocks` edge, and the "the edge is the hold" verification that the blocked
  arm runs now covers the ruling arm too — a ruling whose visit edge did not
  land fails the exit rather than closing over an unheld bead. The visit is
  held to the same-store check the blocked arm's waits are.
- **`tools/helm-surface-fixture.sh`** release smoke passes `--no-wait`.

## Left for follow-up

Filed as `tk-re21ok` (the visit-park edge and the converse doc):

- **The visit-park writers** (`escalate.sh` and `gc-helm.sh cmd_open` share one
  `gate-visit` block; `pr-facts.sh` abandon/retarget file their visit through
  `escalate.sh`) stamp `gc.routed_to=human` with a `tracks` edge and give the
  subject no `blocks` edge onto the visit. Making the visit gate the subject is
  proposal Phase 1 for `escalate.sh`, but it carries the §1 shape-law risk — a
  subject with `parent-child` children would cascade — which Phase 2 owns, and
  the guard does not touch these paths. Filed separately.
- **`molecule-hold.sh`** writes `blocked_reason` and relies on the molecule's
  existing dependency edges to hold the step, so it does not mint an unedged
  hold; the bead's premise that it "writes blocked_reason with no edge" does not
  hold against the code. No change.
- **The converse prompt** (`agents/converse/prompt.template.md`) documents a
  stand-down ruling as `takeaway <anchor> "<ruling>" --release` with no
  disposition, which the guard now refuses; the polecat doctrine already uses
  `--release --no-wait`. Editing it re-renders `generated/seed-audit`, which is
  stale on `main` for unrelated inputs in this checkout, so the fix belongs in a
  change that owns the render. Filed with the visit-park work.
- **Failing loudly on a cross-store `--waiting-on` target** (proposal Phase 1)
  is not in this bead and is unchanged.
