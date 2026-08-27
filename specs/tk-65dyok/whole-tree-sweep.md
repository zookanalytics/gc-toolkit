---
name: history-in-prose whole-tree sweep
description: What the history-in-prose detector reports when run over every tracked file in gc-toolkit, what those findings are, which false-positive classes calibration removed and which one it kept, and the two policy questions a wiring decision has to answer first.
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

445 tracked files, 13s wall. A gate-sized run of ten files is ~0.15s; the
runner hands changed files only, so this whole-tree number is the outer
bound, not the gate cost.

## The count

| | |
|---|---|
| findings | 450 |
| files with at least one | 96 of 445 |
| findings in `specs/` | 0 |

By marker: 317 bead ids, 91 absolute dates, 42 PR references.

By area, findings / files:

| Area | Findings | Files |
|---|---|---|
| `assets/` | 182 | 49 |
| `services/` | 117 | 20 |
| `docs/` | 117 | 10 |
| `packs/` | 12 | 7 |
| `tools/` | 10 | 2 |
| `formulas/` | 6 | 3 |
| `doctor/` | 3 | 3 |
| `agents/` | 2 | 1 |
| `pack.toml` | 1 | 1 |

Concentrated, not diffuse: eight files carry 194 of the 450, and 80 of the
96 files are source files whose findings are in comments.

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
sample, not a proof about all 450.

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

## Where the comment leader is also a marker

`#` opens a comment and also spells a PR reference, so the comment scanner
keeps it and hands `#<n>` to the check the way the markdown scanner already
did. Three findings in the tree depend on it:

```
assets/scripts/quota-park-nudge.test.sh:172   • Merged PR #242. Queue is empty.
assets/scripts/tmux-pick-session.test.sh:170  "title": "landing PR #497"
assets/scripts/tmux-pick-session.test.sh:319  has "$APIMENU" '│ landing PR #497'
```

All three are real PR numbers in fixture text rather than in an authored
comment. The scanner reads any whitespace-preceded `#` as a comment leader
and has no notion of a heredoc or a string literal, so it cannot separate
the two. The same blindness already governs every other marker, and
narrowing it to line-initial `#` would buy those three back at the cost of
the trailing-comment shape, which is the commoner one. They are left as
findings.

## The store prefixes

The detector matches six. Five are the live city stores `gc rig list --json`
reports: `lx`, `tk`, `sl`, `gc` and `su`. The sixth is `ga`, the upstream
gascity store, whose ids the two tracking ledgers named below cite. `lx` is
the city's own store, so it also spells session ids and mail wisps; those
cite provenance in prose the same way a work-bead id does.

Two of the six collide with a namespace and carry a standing cost. `gc-` is
also this pack's command namespace, and `gc-toolkit` alone appears 1684
times. `lx-` is the shape tests use for synthetic session names, and the
comments in `assets/scripts/quota-park-nudge.test.sh` carry nine of them.
Both prefixes therefore require a digit in the suffix to be read as an id,
which costs the all-alpha ids of those two stores. That is the false
negative the rule prefers.

The set is mechanical, so it drifts silently when a store joins or leaves.
`assets/scripts/history-in-prose.test.sh` pins it from both sides: a fixture
per prefix, so dropping one fails, and a control on a prefix no store uses,
so inventing one fails.

## Two questions a wiring decision has to answer

**The ledger docs.** `docs/gascity-human-engagement.md` (51) and
`docs/gascity-routing-model.md` (39) are 90 of the 450. Both are
upstream-tracking ledgers; the first says so in its own frontmatter — "every
claim carries its verification date". Their dates, upstream PR numbers and
`ga-` ids are load-bearing, and `docs/**` is in scope by design. Either
those two files are mis-tiered and belong in `specs/`, or the rule has a
carve-out for a doc whose subject is another repo's movement. The detector
cannot decide that, and the `.allow` file is line-shaped, not file-shaped,
so it is a poor fit for 90 lines.

**The existing tree.** The runner scopes to changed files, so wiring does
not force a cleanup. It does mean the next edit to any of these 96 files
arrives with findings attached — including files whose findings predate the
change. Six of them are in `docs/lifecycle-composition.md`, in a table whose
whole purpose is closed-work provenance: the bead ids there are in inline
code and exempt, but the PR numbers and closure dates beside them are not.

## What this detector does not reach

tk-65dyok's acceptance names the tk-ijwsdl case alongside the PR#490
passages. The PR#490 passages are found. They are no longer in the tree —
PR#490 landed and removed them, so `agents/converse/prompt.template.md` is
now clean and the check runs against the blob that carried them:

```
git show 2e43853:agents/converse/prompt.template.md
```

23 findings, among them the exact paragraph the operator flagged: line 277
(`2026-08-13`) and line 281 (`tk-gvas6`). The two findings `agents/` still
reports are dates in `agents/proactive/PROVENANCE.md`.

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
