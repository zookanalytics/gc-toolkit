---
name: Work-bead description delivery — derivation and split
description: Why a filed bead's description could stop reaching the polecat that works it, which half of tk-osf13's diagnosis held up under verification, and why the fix is split between a pack-side hook (shipped here) and a gascity-side change to the sling note (filed cross-rig).
---

# Work-bead description delivery

tk-osf13 reported two defects: a bead's description never reaches the
polecat, and the remedy `gc sling` recommends (`--var context_path=…`)
is consumed by no formula. Both were verified against the shipped
sources. Both are real, and **both were reported one notch stronger
than the evidence supports** — the precise shape of each is what
determines where the fix belongs, so it is recorded here before the
remedy.

## What was verified

**Claim 1 — the description is dropped.** The five reads the bead cites
are exactly as described. `mol-polecat-work.toml` reads the work bead at
lines 92, 122, 156, 329 and 353, and every one is jq-filtered to a
single metadata field (`work_dir`, `branch`, `rejection_reason`,
`auto_push`). Nothing there renders the description.

But the formula extends `mol-polecat-base`, and the base's
`load-context` step (the first step) says, in prose:

```bash
gc bd show "$WORK_BEAD_ID"           # Full issue details
```

That is unfiltered, and it delivers the description. So "never reaches
the polecat" is too strong: on the intended path it does reach the
worker. The defect is narrower and worse-behaved than "never":

1. **Delivery happens once, in step 1.** The `implement` step — the step
   that consumes the requirements — never re-reads the bead. It derives
   `WORK_BEAD_ID` only to name it in commit subjects and escalation
   mail, and its instruction is "do the actual implementation work."
2. **graph.v2 materializes each step as its own bead.** A session that
   is respawned mid-workflow and claims `implement` directly never ran
   `load-context`, so the description was never in its context at all.
3. **It is an instruction, so it degrades silently.** Nothing downstream
   can distinguish work done against a full spec from work done against
   a title. The reviewer sees a diff, not the absence of a read.

This pack has already paid for the same failure class twice: the soft
"apply cycle-recycle" prose that stopped firing exactly as context
filled (tk-g8pfg), and the done sequence's `--notes` that silently
destroyed the mayor's dispatch note on every handoff (tk-t41dq). The
lesson each time was to move the remedy into code.

**Claim 2 — the suggested `--var` is inert.** `context_path` and
`requirements_path` appear in no gastown `mol-*` formula (0 of 8), which
is what the bead's grep over the gc-toolkit rig found. They are not dead
city-wide, though: the **gascity pack** consumes both, and declares them
properly — `gascity/formulas/do-work.formula.toml:18` opens
`[vars.context_path]`, and eight further `*.formula.toml` files
(`build-base`, `planning-base`, `code-review-base`,
`implementation-item-base`, `build-from-review-base`,
`same-session-implement`, `github-pr-review`, `gap-analysis`) do the
same.

So the note is not advice that nothing implements. It is advice that is
**emitted unconditionally, for a formula family that cannot consume
it.** `internal/sling/sling_core.go:457` (gascity) suppresses the note
only when the operator already passed one of the two vars; it never asks
whether the *resolved formula* declares either. Following the advice on
a `mol-polecat-work` dispatch is therefore strictly worse than ignoring
it: the note goes away, and nothing is delivered.

## What ships here

A Claude `PostToolUse` hook, `overlays/work-context/`, wired onto the
polecat pool via `overlay_dir` in `pack.toml`. It fires after every claim
the polecat makes, resolves the claimed bead to its work bead (claimed
step → `gc.root_bead_id` → `gc.input_convoy_id` → the convoy's single
tracked member), and injects that bead's title and description as
`additionalContext`.

**Why a hook and not a prompt fragment.** A fragment would be a second
instruction competing with the one already in `load-context`, and would
fail the same way — hardest exactly when context is fullest. The harness
runs a hook regardless of model state.

**Why `PostToolUse`.** It is the only event that can fire *after* the
claim within the same turn, and a polecat's whole workflow is usually
one turn: `SessionStart` and the first `UserPromptSubmit` both run
before `gc hook --claim` has named a bead, so neither can see the work
bead. Support is confirmed in the running client — Claude Code 2.1.231
carries `hookEventName:"PostToolUse",additionalContext:`.

Two traps in the hook are load-bearing and are pinned by tests, because
each would make it fail **silently** (it exits 0 and prints nothing by
design, so neither is observable at runtime):

- Bash's `tool_response` is an **object**, so jq's `tojson` re-escapes
  the JSON the command printed and the bead id arrives as
  `\"bead_id\":\"tk-…\"`. A scanner written against a bare string matches
  nothing, forever. Removing the unescape breaks 8 assertions in
  `assets/scripts/work-context-hook.test.sh`; that is what the case
  exists to prove.
- `cut -c` truncates per **line**, so it does not bound a multi-line
  description at all. Only a whole-payload cap (`head -c`) does.

`doctor/check-work-context-hook` guards the wiring, and scores code with
comments stripped — both the hook and the check explain these traps in
prose, so a comment-inclusive grep would score the explanation as the
fix and stay green after the code line was deleted.

**Scope limits, stated plainly.** The overlay is Claude-only, so the
`polecat-codex` pool (`provider = "codex"`) is unaffected; the hook
self-gates on `GC_TEMPLATE` and the claude provider, so staging it
anywhere else is a no-op. Delivery stays best-effort by construction —
if Dolt is slow or the resolution fails, the hook stays silent and
`load-context`'s `gc bd show` remains the fallback, exactly as it works
today. This adds a floor; it removes nothing.

## What is filed cross-rig

The note lives in the `gc` binary, whose source is the **gascity** rig —
a different repo, which a gc-toolkit polecat cannot push to. The
behaviour-and-advice agreement the bead asks for is therefore filed
there as **gc-dzh3f**: suppress the note when the resolved formula
declares neither `context_path` nor `requirements_path`, or point it at
that formula's actual delivery mechanism. The patch site is
`attachedBeadInstructionsDroppedHint`
(`internal/sling/sling_core.go:443`, hint text at :457, called at :426
and :464), whose suppression test at :448-452 keys only on the
operator's vars and never on the resolved formula. The test named in
that bead is a dispatch of a `mol-*` formula asserting the note is
absent, paired with a gascity-pack formula asserting it is still
present.

Until that lands, this pack's hook makes the note's *premise* false for
gc-toolkit polecats: the description does reach the worker, whether or
not the operator passes a var that this formula family cannot read.
