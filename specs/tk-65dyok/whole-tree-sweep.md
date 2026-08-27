---
name: history-in-prose whole-tree sweep
description: What the history-in-prose detector reports when run over every tracked file in gc-toolkit, what those findings are, which false-positive classes were found and removed during calibration, and the two policy questions a wiring decision has to answer first.
---

# history-in-prose whole-tree sweep

## Scope

**Mandate.** The calibration exercise tk-65dyok's acceptance asks for: the
count `tools/lint-learned.d/history-in-prose.sh` produces over the whole
tree, and enough characterisation of those findings that someone deciding
whether to wire `lint_command` knows what they would be turning on.

**Boundaries.** This is the state of the tree when the detector shipped, not
a standing report. It does not propose wiring, and it is not the detector's
contract — that lives in the detector's own header.

## The exercise

```
./tools/lint-learned.d/history-in-prose.sh $(git ls-files)
```

437 tracked files, 12.5s wall. A gate-sized run of ten files is ~0.15s; the
runner hands changed files only, so this whole-tree number is the outer
bound, not the gate cost.

## The count

| | |
|---|---|
| findings | 466 |
| files with at least one | 95 of 437 |
| findings in `specs/` | 0 |

By marker: 332 bead ids, 95 absolute dates, 39 PR references.

By area, findings / files:

| Area | Findings | Files |
|---|---|---|
| `assets/` | 176 | 47 |
| `services/` | 117 | 20 |
| `docs/` | 116 | 10 |
| `agents/` | 25 | 2 |
| `packs/` | 12 | 7 |
| `tools/` | 10 | 2 |
| `formulas/` | 6 | 3 |
| `doctor/` | 3 | 3 |

Concentrated, not diffuse: eight files carry 207 of the 466, and 78 of the
95 files are source files whose findings are in comments.

## What the findings are

Sampled across every area and marker. They are citations of provenance in
living prose — the class the rule names:

```
assets/scripts/gc-helm.sh:157       # (tk-xypcy). Walk live graph.v2 steps in reverse
services/helm/web/src/styles.css:80  * Parked conversations (tk-2v08m). A second section
docs/gascity-packs.md:449            against `gc 1.4.1`, built from fork `origin/main` at `3983cc049`, 2026-08-13.)
tools/helm-surface-fixture.sh:498   # The regression this guards (PR #100 review): the docs/prompt advertised
```

No false positive survived the sampling. That is a statement about the
sample, not a proof about all 466.

## False-positive classes found during calibration, and removed

Each was found by reading the tree's own output, and each is now a detector
exemption with a test that pairs it against a positive control:

- **Markdown heading anchors.** `[Verification](#5-verification)` read as PR
  `#5`. Five findings in `docs/install.md` alone. The `#<n>` pattern now
  refuses a trailing `-`.
- **Generated files.** `services/helm/web/src/drill/gen/supervisor.d.ts`
  carries an upstream tool's `#1256` in a description string. A finding
  there names nothing the author can fix. Exempt by tier or header marker.
- **Pointers into specs.** `specs/tk-h9pq5/design-doc.md` in a comment names
  where the record lives, which is the rule working. Ten findings.

One tuning decision has a standing cost: `gc-` is both a store prefix and
this pack's command namespace (`gc-toolkit` alone appears 1506 times), so a
`gc-` id must carry a digit to be seen. All-alpha `gc-` ids are missed. That
is the false negative the rule prefers.

## Two questions a wiring decision has to answer

**The ledger docs.** `docs/gascity-human-engagement.md` (51) and
`docs/gascity-routing-model.md` (39) are 90 of the 466. Both are
upstream-tracking ledgers; the first says so in its own frontmatter — "every
claim carries its verification date". Their dates and upstream PR numbers
are load-bearing, and `docs/**` is in scope by design. Either those two
files are mis-tiered and belong in `specs/`, or the rule has a carve-out for
a doc whose subject is another repo's movement. The detector cannot decide
that, and the `.allow` file is line-shaped, not file-shaped, so it is a poor
fit for 90 lines.

**The existing tree.** The runner scopes to changed files, so wiring does
not force a cleanup. It does mean the next edit to any of these 95 files
arrives with findings attached — including files whose findings predate the
change. `tk-2plde` and its neighbours in `docs/lifecycle-composition.md`
sit in a table whose whole purpose is closed-work provenance.

## What this detector does not reach

tk-65dyok's acceptance names the tk-ijwsdl case alongside the PR#490
passages. The PR#490 passages are found, including the exact paragraph the
operator flagged: `agents/converse/prompt.template.md:277` (`2026-08-13`)
and `:281` (`tk-gvas6`).

The tk-ijwsdl case is not found, and cannot be. Its violation —
`assets/scripts/refinery-queue-nudge.test.sh` before 8f055f7 — is
marker-free:

```
# The guard was prose ("Nudge if needed") until a formula rewrite dropped it,
# which is why it is executable here: this test EXECUTES the real block
```

Incident history with no bead id, no PR number and no date, plus eight
section banners narrating the block below them. Running all seven
lint-learned detectors over that file reports nothing. Reaching it needs
narration detection, which tk-65dyok rules out in its own "Deliberate
non-goal" section, and for the stated reason: the false-positive rate would
get the detector switched off.

So this detector hardens the provenance-marker half of the comment-hygiene
rule. The narration half stays prose, in
`template-fragments/operator-profile.template.md`, and that bullet must not
be deleted as a hardened rule's bullet normally would be — the detector
replaces part of it, not all of it.
