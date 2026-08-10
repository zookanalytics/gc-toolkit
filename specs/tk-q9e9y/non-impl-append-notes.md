---
name: Spec for extending --append-notes to the non-impl done sequence
description: Why the review/research/investigation done sequence stopped using the destructive --notes flag, and why the single-valued-artifact carve-out that had exempted it did not hold.
---

# Non-impl done sequence: `--notes` destroys the deliverable

## Scope

**Mandate.** The record of the tk-q9e9y fix: the surviving half of the
`--notes` data-loss defect, the argument that had exempted it, why that
argument fails, and what shipped.

**Boundaries.** Only the **non-impl** (review / research / investigation)
done sequence. The impl half landed earlier under tk-t41dq — see
`specs/tk-t41dq/done-sequence-append-notes.md`, whose "Not a blanket rule"
section this work supersedes. The `gc bd update --help` wording is a
gascity-core string, not pack, and is reported rather than fixed here.

## The defect

`gc bd update --notes` **replaces**; `--append-notes` appends. The
non-impl done sequence in
`template-fragments/polecat-non-impl-done.template.md` instructed the
replacing flag at four sites — the pre-open verdict write (twice) and the
research/investigation findings write (twice).

These are the beads whose **notes are the deliverable**. An impl bead's
output is its diff, so a clobbered note there costs context; a research
bead's output *is* the note, so a clobbered note there costs the work.

Observed live on **tk-6kf6r** (2026-07-22): an 11,397-char audit
deliverable was written at 07:58:25 and replaced at 07:59:14 by a 469-char
handoff summary — which then said "see the audit note", pointing at text
the same command had just deleted. Recovered by hand out of
`tk.dolt_history_issues`.

## The carve-out, and why it does not hold

tk-t41dq fixed the impl half and deliberately left this one, on the
grounds that a review bead's notes are a **single-valued artifact**:
`assets/scripts/pre-open-resolve.sh:691` reads that field and replays it
verbatim as the PR's codex-signoff comment, so appending "would splice
stale rounds into that comment."

The replay is real. The conclusion does not follow from it, for three
independent reasons.

**1. The field already has a second writer, and it appends.**
`signoff_retry_release` — in the same fragment — appends the "gate
unrecorded" diagnostic to the same review bead's notes and then re-offers
**that same bead** to another polecat. Under `--notes`, the next round's
verdict erases the only in-bead record of why the previous round's gate
failed to record. That is the exact invisible-loss shape the impl fix was
written to end, on the one path where a review bead is genuinely
long-lived. The premise "single-valued artifact" was false as shipped.

**2. Appending splices nothing stale.** Rounds do not accumulate in one
bead's notes: a `REQUEST_CHANGES` verdict closes its review bead and the
re-gate mints a **fresh** one, and `pre-open-resolve.sh` selects the
newest review bead under the anchor (`sort_by(.updated_at) | last`). The
one path that accumulates within a single bead is the retry above — where
every entry describes the very PR being opened, so replaying them is
informative rather than stale. The hazard the carve-out was protecting
against is not reachable by the architecture that surrounds it.

**3. Research and investigation beads are not replayed by anything.**
`pre-open-resolve.sh` filters on `task_kind=review` plus `anchor_bead`.
Two of the four sites (lines 109 and 114 as they stood) are the
research/investigation instruction, where no verbatim-replay consumer
exists at all and the notes are simply the deliverable. The carve-out's
own justification never covered them.

What the verbatim replay *does* require is that a pre-open verdict be
**self-contained** — written to read correctly as an opening PR comment
rather than as a diff against whatever precedes it. That is a constraint
on how the verdict is written, not on which flag writes it.

## What shipped

| File | Change |
|---|---|
| `template-fragments/polecat-non-impl-done.template.md` | four `--notes` → `--append-notes`, plus a short note at the pre-open verdict site naming the second writer and the self-contained requirement |
| `template-fragments/polecat-append-notes.template.md` | the carve-out paragraph replaced with the corrected rule and its three reasons |
| `specs/tk-t41dq/done-sequence-append-notes.md` | superseded marker on "Not a blanket rule"; boundary line corrected |

Correcting `polecat-append-notes` is not optional cleanup. Both fragments
render into the **same** polecat prompt — `pack.toml`'s
`[[patches.agent]] name = "polecat"` orders `polecat-append-notes` before
`polecat-non-impl-done`, and `agents/polecat-codex/agent.toml` carries the
same pair. Fixing only the instruction sites would have shipped a prompt
that tells the reader to append at each site and, a few thousand tokens
earlier, that the non-impl verdict writes keep `--notes` **on purpose**. A
fix a later reader can talk themselves out of is not a fix.

No new prose was added to `polecat-non-impl-done` beyond the one note:
`specs/tk-23wdf/context-budget-ledger.md` measures that fragment at 70,043
bytes, 68.3% of the polecat prompt, and recommends narrowing it. The
reasoning lives here and in the 2.5 KB fragment the ledger marks KEEP.

## The `--help` wording: already fixed upstream

tk-q9e9y's third strand was that `gc bd update --help` documents `--notes`
as "Additional notes" — wording that implies APPEND and steers a reader to
the destructive flag. The routing note carried it forward as still open,
to be reported rather than PR'd, since it is a **gascity-core** string and
not pack.

That claim is **stale**. As of the binary in this city on 2026-08-10:

```
--append-notes string   Append to existing notes (with newline separator)
--notes string          Additional notes (replaces existing notes; use --append-notes to append)
```

The parenthetical now names both the destructive behaviour and the
alternative. Nothing is owed upstream and no cross-rig bead was filed; the
gascity rig carries no open bead on this wording either. Verified before
reporting, per the standing rule that a remembered defect is re-checked
against live state before it is acted on.

That closes the last of the three strands the bead described.
