---
name: Decision record — lesson-capture approach (tk-63qgj)
description: Why gc-toolkit adopted neither PR #88 nor compound-engineering's ce-compound for lesson capture, what happened to each, and the transferable lesson about pack changes that depend on an un-taken manual wiring step. Read when asking what became of #88 or ce-compound, or why the shipped answer was a third mechanism.
---

# Decision: lesson-capture approach — neither A nor B, superseded by #291

**Subject bead:** `tk-63qgj` (type `decision`, filed 2026-07-22) — "which
lesson-capture mechanism gc-toolkit adopts, plus a disposition for PR #88."

**Decided:** 2026-08-22 by the operator, in a converse sitting on visit
`tk-934cr`. **Recorded by:** `tk-nhttl`.

This is a retrospective record, not a fresh comparison. Both options had already
been disposed of by events before the decision was taken; what was missing was
the written record the bead's Acceptance asks for. The comparison was
deliberately not reopened and compound-engineering was deliberately not
re-surveyed — see the provenance table's last row for what that leaves unchecked.

## Provenance

| Doc-type or artifact | Producer | Source location (URL or repo path + commit SHA) | Surveyed at |
|---|---|---|---|
| Decision bead + operator ruling | converse (visit `tk-934cr`), operator | bead `tk-63qgj` description + notes, "Sitting 1 — DECIDED" | 2026-08-22T22:00Z |
| Pull request (Option A) | polecat, anchor `tk-7druqk` | https://github.com/zookanalytics/gc-toolkit/pull/88 — CLOSED, head `polecat/tk-7druqk` @ `9207893` | 2026-08-22T22:13Z |
| Option A fragment source | same | `template-fragments/lesson-capture.template.md` @ `9207893` (branch only; never on main) | 2026-08-22T22:13Z |
| Pull request (adopted mechanism) | gc-toolkit | https://github.com/zookanalytics/gc-toolkit/pull/291 — MERGED, squash `c7b7a6af` | 2026-08-22T22:13Z |
| #291 wiring sites | gc-toolkit | this repo @ `2d87f91` (cited `83d2471` is an ancestor; line numbers unchanged) | 2026-08-22T22:13Z |
| #291 prior-art survey | gc-toolkit | `specs/2026-08-learning-system/prior-art.md` @ `2d87f91` | 2026-08-22T22:13Z |
| City configuration | city repo (not this repo) | `$GC_CITY/city.toml` at current HEAD — zero `ce-compound` occurrences; removal commits `1335d575`, `a68a29b0` | 2026-08-22T22:13Z |
| Option B skill (`ce-compound`) | compound-engineering (external) | **not surveyed in this pass.** Pin `5b7c5c13` is quoted from `tk-63qgj`'s own description, not re-fetched | last surveyed 2026-07-22, per `tk-63qgj` |

## Outcome

**Neither Option A nor Option B.** The answer was a third mechanism that shipped:
PR **#291** *"learning: feedback-learning system — capture, distill, promote,
retire"*, MERGED 2026-08-11T08:00:30Z (`c7b7a6af`).

Both options were disposed of by events eight days apart, and **neither was
disposed of by this decision**. The decision's only real content is the
recognition of that, plus the record itself.

## Disposition of Option A — PR #88

**CLOSED 2026-08-10T22:58:43Z as superseded by #291.** Not merged, not rebased,
and it stays closed.

The close was preceded by a documented point-by-point triage: 9 substantive
claims in #88, of which 7 were covered by #291 or deliberately reversed by it.
The remaining 2 were divergences — the agent-local auto-memory write, and
central-store filing — and they were **recorded forward onto #291 rather than
lost**. That carry-forward is the pattern this record reuses for its own open
divergence below.

The work is preserved and reopenable:

- branch `polecat/tk-7druqk` is untouched on origin at `9207893`;
- anchor bead `tk-7druqk` is closed and carries `gc.superseded_by=tk-uicmw`.

**No rebase.** The disposition the bead asked for is close-as-superseded, and it
has already been executed.

## Disposition of Option B — compound-engineering `ce-compound`

**Removed from the city on 2026-08-03 by a hygiene sweep** — commit `1335d575`
*"city: purge orphaned skill sinks (compound-engineering, superpowers)"*
(2026-08-03 00:42:45Z), itself preceded by `a68a29b0` *"city: stop worker pools
picking their method from the skill catalog"* (2026-08-02 16:12:33Z). There are
zero occurrences of `ce-compound` or `compound-engineering` in `city.toml` today.

**State this honestly: B was removed, not chosen against.** The sweep was
general city hygiene aimed at orphaned skill sinks; it was not an assessment of
B's merits, it predates #88's triage by eight days, and it makes no reference to
this decision. B lost its trial deployment as a side effect of unrelated
cleanup. What that leaves unsettled is recorded as an open divergence below.

## The transferable lesson: why #88 never took effect

#88 is often described as having shipped inert because its fragment was never
added to `append_fragments`. **True in effect — but not by oversight.** The
fragment documented its own activation, in a comment at the top of the file
instructing the consuming city to wire it by hand:

```
{{/*
Activation (deliberately NOT applied at ship time): add "lesson-capture"
to the consuming city's [agent_defaults] append_fragments in city.toml —
    append_fragments = ["command-glossary", "operational-awareness", "lesson-capture"]
Deferred because city.toml edits drift session CoreFingerprints and drain
detached manual sessions; the operator/mechanik wires it at a safe moment
after merge. Provenance: thread lo-d5by, 2026-06-03 (correction→bake-in v1).
*/}}
```

The deferral was deliberate and the stated reason was sound. It was still fatal:
#88 was **designed to require a second, manual `city.toml` move**, and nobody
ever made it. Even had #88 merged, no agent's behavior would have changed until
someone performed a step that lived only in a comment inside the artifact it
gated.

That is precisely the failure #291 avoided, by activating through native
template includes that take effect the moment the pack is consumed — no
second move, nothing for anyone to forget.

**The lesson:** *a pack change that depends on an un-taken manual wiring step is
indistinguishable, from the outside, from one that never landed.* A good reason
for deferring the wiring does not change that. If a change must be wired
separately, the wiring is part of the change — not a follow-up, and not a note
to a reader who may never arrive.

## Evidence #291 is wired, not inert

Verified in this repo at `2d87f91`:

- `agents/converse/prompt.template.md:423` — `{{ template "file-feedback-observations" . }}`
- `agents/mechanik/prompt.template.md:209` — same include
- `agents/polecat-codex/agent.toml:56`, and `pack.toml:107,153`
- artifacts present: `docs/feedback-learning.md`,
  `formulas/mol-feedback-{distiller,miner}.toml`,
  `orders/feedback-{distiller,miner}.toml`,
  `skills/learning-distill/SKILL.md`,
  `template-fragments/file-feedback-observations.template.md`,
  `specs/2026-08-learning-system/`
- `feedback-miner` is live as a registered order on all four rigs (gascity,
  gc-toolkit, shutupandlisten, signal-loom), on a 48h cooldown

One qualification, verified 2026-08-22T22:13Z and recorded rather than smoothed
over: `feedback-distiller` ships as `orders/feedback-distiller.toml` and is
present in the live rig checkout alongside the miner, but it does **not** appear
in `gc order list`, whereas the miner — structurally identical in its `[order]`
block — does. (The live listing also reports the miner at 48h where both files
declare `interval = "24h"`, suggesting the listing resolves orders from a
different source than `rigs/<rig>/orders/`.) Whether that is deliberate or a
registration gap was out of scope for this record and is not diagnosed here.
Capture (the miner and the template includes) is demonstrably live either way;
the distiller's live registration is the one link in #291's chain this record
does not attest. Flagged deliberately — asserting it registered, on the strength
of a file existing, would repeat the exact failure this document warns about.

## Open divergence: Option B's authoring flow was never assessed

Recorded as an **open divergence with a forward pointer**, not as a rejected
option — the same treatment #88's triage gave its own two divergences. The
subject bead explicitly allowed a hybrid, and this record does not close that
door.

What is known:

- **B was genuinely never compared.** #291's prior-art survey
  (`specs/2026-08-learning-system/prior-art.md`) covers 20+ mechanisms and never
  names `ce-compound`. Neither does `docs/feedback-learning.md`.
- **Its closest surveyed analogue is Aider's `CONVENTIONS.md`**
  (prior-art.md §1.5), characterized there as: *"No scoping, no capture, no
  retirement — the minimal baseline all other systems improve on."*
- **B's shape lands on three of that survey's five named anti-patterns.**
  `ce-compound` — document a recently solved problem → `CONCEPTS.md` shared
  vocabulary — matches #2 *append-only memory with no decay pressure*, #4
  *capture without provenance or outcome tracking*, and #5 *storing transcripts
  instead of distillations* (prior-art.md §"Anti-patterns observed"). A merits
  assessment would most likely find B dominated.

What remains genuinely unassessed is **B's trigger**, not its storage model: a
human authoring at the moment of solving, as against #291's rubric-driven
distillation from observation beads. That trigger is orthogonal to the three
anti-patterns above, and it is the piece a hybrid would graft on.

**Available if wanted, at the cost of a scoped graft-check.** Nothing currently
depends on it, and no bead is open against it.

## Acceptance

Satisfied when this file is on `main`. `tk-63qgj` wants nothing else.
