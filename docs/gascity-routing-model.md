---
name: Gas City routing model
description: How `gc sling`, direct assignee, and `gc sling --reassign` differ — and which fields each lane is supposed to set, per the PR #1736 ruling.
---

# Gas City routing model: sling vs assignee vs `--reassign`

**Slot in `gascity-reference.md`:** new "Local supplements" section.
The existing "Architecture & concepts" entries link to upstream URLs;
this doc is local-authored prose with no upstream counterpart, so a
dedicated section is cleaner than tagging it `(gc-toolkit local)`
inside an otherwise upstream-only list.

## Provenance

| Doc-type or artifact | Producer | Source location | Surveyed at |
| --- | --- | --- | --- |
| PR #1736 closing comment (maintainer ruling) | julianknutsen | https://github.com/gastownhall/gascity/pull/1736 | 2026-05-21 |
| PR #1841 — `--reassign` flag (merged 2026-05-12) | gastownhall/gascity | https://github.com/gastownhall/gascity/pull/1841 (merge commit `44fcee6af60277f87aaa063f72dafeff7f705966`) | 2026-05-21 |
| `TestDoSling_Reassign_NoOpWhenAlreadyEmpty` | gastown source | `rigs/gascity/internal/sling/sling_test.go:3809` (added in `043e61ea6cb99a9f89657e292c9459be8620714c`, observed at upstream/main `19a0bb201eb6d1723a10eecdae20371bd8ceeb17`) | 2026-05-21 |
| Gastown polecat agent prompt | gastown source | `rigs/gascity/examples/gastown/packs/gastown/agents/polecat/prompt.template.md` (last touched in `b519e6e7f0ab4b7b3dbcb4ff4a2b1d30c77d2a86`, observed at upstream/main `19a0bb201eb6d1723a10eecdae20371bd8ceeb17`) | 2026-05-21 |
| Gastown refinery formula | gastown source | `rigs/gascity/examples/gastown/packs/gastown/formulas/mol-refinery-patrol.toml` (last touched in `015a8b2bdde94a635fc852e37a36c2bf9b65dfb3`, observed at upstream/main `19a0bb201eb6d1723a10eecdae20371bd8ceeb17`) | 2026-05-21 |
| Upstream tutorial `docs/tutorials/06-beads.md` — **superseded by PR #1736 ruling, not yet updated** | gastownhall/gascity | https://github.com/gastownhall/gascity/blob/19a0bb201eb6d1723a10eecdae20371bd8ceeb17/docs/tutorials/06-beads.md (last touched in `eac98595e701008087f7ee6acecbf55d5dca7794`) | 2026-05-21 |
| Upstream CLI reference (`--reassign` row only) | gastownhall/gascity | `rigs/gascity/docs/reference/cli.md:2789` at upstream/main `19a0bb201eb6d1723a10eecdae20371bd8ceeb17` | 2026-05-21 |

## The maintainer's ruling

From julianknutsen's PR #1736 closing comment (verbatim):

> The default sling path should not generally stamp both. assignee and
> gc.routed_to are not duplicates… Keep gc sling as queue/template
> routing: gc.routed_to=\<target\>, no assignee by default.
>
> Clean up the Gastown polecat/refinery formula and prompt text that
> currently says to set both assignee and gc.routed_to; that is bad
> hygiene and can become stale-route confusion later.

The three lanes below are the resulting model.

## The three lanes

### Lane 1 — `gc sling <target> <bead>`: queue / template routing

- **When to use:** routing a bead to a pool, queue, or template — the
  cases where any worker matching the target is acceptable. This is
  the default sling path and the dispatch shape used by mayor,
  mechanik, deacon, and refinery when handing work back to the
  polecat pool.
- **Sets:** `metadata.gc.routed_to=<target>`. Convoy-ancestor walk
  may also resolve and stamp `metadata.target` (integration branch).
  Leaves `assignee` empty.
- **CLI example:**
  ```bash
  gc sling gc-toolkit/gc-toolkit.polecat tk-abcde
  ```
- **Does NOT:** set `assignee`. The reconciler picks an available
  worker from the pool by matching `gc.routed_to`.

### Lane 2 — `bd update <bead> --assignee <named-session>`: direct named-session delivery

- **When to use:** the work must land on one specific named session
  (e.g., a polecat resuming its own bead, mechanik claiming its own
  wisp, mail addressed to a specific identity). When you write the
  named session's identity, you're saying "this work, this agent,
  no fan-out."
- **Sets:** `assignee=<named-session-identity>`. Leaves
  `gc.routed_to` empty.
- **CLI example:**
  ```bash
  bd update tk-abcde --assignee gc-toolkit/gc-toolkit.slit
  ```
- **Does NOT:** set `gc.routed_to`. The named session's hook query
  finds the work via assignee, not via routed metadata.

### Lane 3 — `gc sling <target> <bead> --reassign`: combined unassign + route

- **When to use:** park-then-handoff transitions — a human or named
  session was working on the bead, the work is now bouncing back to a
  pool. The single flag clears the prior assignee and routes in one
  step so the bead is never momentarily double-stamped. Added in
  PR #1841 (merged 2026-05-12) to make this transition atomic from
  the caller's perspective.
- **Sets:** `metadata.gc.routed_to=<target>` and clears `assignee`
  to empty.
- **CLI example:**
  ```bash
  gc sling gc-toolkit/gc-toolkit.polecat tk-abcde --reassign
  ```
- **Does NOT:** stamp a new assignee. The combined behavior is *clear*
  + *route*, never *clear* + *re-assign-to-someone-else*.

#### `--reassign` idempotency

`TestDoSling_Reassign_NoOpWhenAlreadyEmpty`
(`rigs/gascity/internal/sling/sling_test.go:3809`) pins the
contract: when `assignee` is already empty, `--reassign` is a no-op
on the assignee field — no error, no spurious update. Callers that
don't know the bead's prior state can pass `--reassign`
unconditionally and trust the routing call to be safe.

## Implications: sites in this fork that still set both fields

The maintainer's PR #1736 closing comment flagged that the gastown
polecat/refinery prompt and formula text "currently says to set both
assignee and gc.routed_to" and asked for cleanup. This section is
the audit hook for a future cleanup bead — it does not change source.

### Bad-pattern sites (set both `assignee` and `gc.routed_to` to the same target)

- `rigs/gascity/examples/gastown/packs/gastown/agents/polecat/prompt.template.md:215`
  — polecat done sequence (`gc bd update <work-bead> --status=open
  --assignee="$REFINERY_TARGET" --set-metadata
  gc.routed_to="$REFINERY_TARGET"`).
- `rigs/gascity/examples/gastown/packs/gastown/formulas/mol-polecat-work.toml:226`
  — same pattern in the formula step; lines 235–237 carry an
  explainer that explicitly tells the agent to "Update both
  `assignee` AND `gc.routed_to` so the reconciler stops…" — this
  prose itself is the wording the maintainer asked to clean up.
- `rigs/gc-toolkit/agents/_polecat-gemini/prompt.template.md:205`
  — disabled in this fork (parent directory begins with `_`) but
  retains the bad pattern; the cleanup should include it so a future
  re-enable doesn't reintroduce the heresy.
- `rigs/gc-toolkit/agents/polecat-codex/` — no local prompt; the
  agent shares the gastown polecat prompt by reference (see
  `rigs/gc-toolkit/agents/polecat-codex/agent.toml`'s
  `prompt_template = "//.gc/system/packs/gastown/agents/polecat/prompt.template.md"`
  line). A single upstream fix propagates here; no separate gc-toolkit
  edit is needed for codex polecats.

### Correct-pattern sites (clear `assignee`, set `gc.routed_to` — the Lane 3 equivalent)

These are NOT cleanup targets; they implement the park-then-handoff
shape correctly with two field updates instead of the `--reassign`
shorthand.

- `rigs/gascity/examples/gastown/packs/gastown/formulas/mol-refinery-patrol.toml`
  at lines 203/205, 275/277, 329/331 — refinery rejection paths.
- `rigs/gc-toolkit/formulas/mol-refinery-patrol.toml` at lines
  164/166, 236/238, 296/298 — same pattern, gc-toolkit-local
  refinery patrol formula.

A future cleanup bead could mechanically rewrite these to use
`gc sling --reassign` for parity with the maintainer-blessed shape,
but the *semantics* are already correct.

See also auto-memory [[feedback_refinery_rejection_clears_assignee]],
which captures the refinery's current behavior of clearing the
assignee on rejection. That memory still accurately describes
refinery's behavior under the new model and stays as-is.

## Note: upstream tutorial wording

`docs/tutorials/06-beads.md` (upstream) still says, at line ~389:

> Work is routed to an agent (via assignee or `gc.routed_to`
> metadata)

This conflates Lanes 1 and 2 as parallel routing paths. It is
superseded by the PR #1736 ruling and is expected to be updated by
upstream on its own schedule. Per the gc-toolkit
`upstream-engagement` posture, we do not pre-empt that update; this
local doc is authoritative inside gc-toolkit until upstream catches
up. The upstream `docs/reference/cli.md` already covers the
mechanical `--reassign` flag (one table row at `cli.md:2789`); it
does not cover the broader three-lane model.
