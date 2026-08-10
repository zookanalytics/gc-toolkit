---
name: Spec for the polecat done-sequence --append-notes correction
description: Why the impl done sequence destroyed bead notes on every handoff, what gc-toolkit patched locally, and the exact upstream sites a future gastown-pack change would have to touch.
---

# Polecat done sequence: `--notes` destroys prior bead notes

## Scope

**Mandate.** The record of the tk-t41dq fix: the defect, the sites, the
local remedy gc-toolkit shipped, and the upstream target if anyone later
decides to engage.

**Boundaries.** Only the **impl** done sequence. The non-impl (review /
research / investigation) done sequence keeps `--notes` deliberately —
see [Not a blanket rule](#not-a-blanket-rule).

## The defect

The impl done sequence writes the handoff note with `--notes`:

```bash
gc bd update <work-bead> \
  --set-metadata branch=$(git branch --show-current) \
  --set-metadata target=main \
  --notes "Implemented: <brief summary>"
```

`--notes` **replaces**. `bd` says so itself on every run:

```
warning: tk-5cgyk: --notes replaced existing notes (use --append-notes to preserve history)
```

So every polecat handoff destroys whatever notes the bead already carried.

## Why it is worth fixing

Hit live on **tk-5cgyk** (2026-08-10). What that handoff erased was the
mayor's dispatch note: the routing diagnosis, a requirement added to the
fix after the bead was filed, and a correction aimed at the deacon
("this is not a regression of tk-gi2pc"). All of it went at the exact
moment the bead was handed to the refinery — immediately before the
readers who most needed it. It was recovered by hand out of
`tk.dolt_history_issues` and rewritten.

## Why it survived

The loss is invisible from inside the sequence. The update succeeds, the
handoff works, the branch merges. Nothing downstream can notice a note it
never saw, because no record survives that the note was ever there. The
`bd` warning is real and accurate, but it goes to a shell nobody reads
again — the done sequence is the last thing a polecat runs before
`drain-ack`.

## Sites

Six, across four files. The base done sequence is duplicated: the polecat
reads both copies as one instruction, so fixing one leaves the other live.

**Upstream — `gastownhall/gascity-packs`, pin
`sha:33d3a430a67d1782ad364556cb566bdb01d0afe3`** (the pin `pack.toml`
imports; not writable from this rig):

| File | Lines | Copy |
|---|---|---|
| `gastown/template-fragments/approval-fallacy.template.md` | 35, 52 | `approval-fallacy-polecat` → "### The Done Sequence", near the top of the prompt |
| `gastown/agents/polecat/prompt.template.md` | 277, 294 | "## FINAL REMINDER: RUN THE DONE SEQUENCE", at the bottom |
| `gastown/formulas/mol-polecat-work.toml` | 364, 410 | the `submit-and-exit` step |

In each pair the first line is `--notes "Branch ready: ..."` in the
`auto_push=false` halt-at-branch-ready arm, and the second is
`--notes "Implemented: ..."` in the handoff itself. Both carry the same
hazard.

**Local — this pack:**

| File | Site |
|---|---|
| `agents/_polecat-gemini/prompt.template.md` | its own FINAL REMINDER copy (`--notes "Implemented: ..."`) |

## What shipped

gc-toolkit does not mirror the gastown polecat prompt — it reuses the
base template verbatim and appends named fragments
(`docs/gascity-packs.md` §7: a same-named local fragment **shadows** base
and freezes it, and `doctor/check-base-artifact-collision` makes a
shadowed `{{ define }}` name a hard error). So the local remedy is an
appended override, not an edit:

1. **`template-fragments/polecat-append-notes.template.md`** — supersedes
   the `--notes` in both base copies and in the formula step, with the
   reason the correction exists.
2. **Wired into all three injection points**: `pack.toml`'s
   `[[patches.agent]] name = "polecat"`, `agents/polecat-codex/agent.toml`
   (`inject_fragments`, hand-synced with no propagation), and
   `agents/_polecat-gemini/prompt.template.md`.
3. **`agents/_polecat-gemini/prompt.template.md`** — its own literal
   corrected directly; it owns that text.
4. **`doctor/check-polecat-fragment-sync`** — asserts that every native
   pool sharing the base polecat prompt injects the same fragment set as
   the `pack.toml` patch. Without it the fix half-rots the first time
   someone updates one list and not the other, and a pool missing a
   fragment does not fail: it primes cleanly and runs the unpatched base
   doctrine.

## Not a blanket rule

`--notes` is correct where a bead's notes are a **single-valued
artifact** rather than a history field. A review bead is the case:
`assets/scripts/pre-open-resolve.sh` reads the review bead's notes and
replays them verbatim as the PR's codex-signoff comment. Appending there
would splice stale rounds into that comment. The non-impl done sequence
in `template-fragments/polecat-non-impl-done.template.md` keeps `--notes`
for that reason.

The impl work bead is the opposite: several writers and no consumer that
requires exactly one entry. `pre-open-resolve.sh` renders those notes into
the PR body under "## Implementation notes" as free text, so a preserved
dispatch note simply reaches the PR too — which is the point.

The rest of the pack already reads it that way. Every other writer to a
work bead's notes uses `--append-notes` today:
`assets/scripts/check-set-heal.sh` at three repair sites, and
`formulas/mol-refinery-patrol.toml` on the rework hand-back. The done
sequence was the one destructive writer into a field everything else
treats as history — which is also why the loss looked like nothing was
wrong: the surrounding convention was already correct.

## Upstream

Per `template-fragments/upstream-engagement.template.md`, this is
**option 2 (local patch)**: the correction is carried here and the base
pack is left alone. It is deliberately *not* escalated to option 3 — the
public footprint of an upstream PR is an operator call, not a polecat's.
The table above is the durable target if that call is ever made; once the
base copies are fixed, this fragment can be retired and
`doctor/check-polecat-fragment-sync` keeps its value independently.
