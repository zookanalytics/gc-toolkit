---
name: Review charter — the gate menu a reviewer holds a diff against
description: The declared gate menu a review-triage session classifies over — each gate's name, when it applies, and its method. Read it as a reviewer; parse it as a tool via assets/scripts/review-charter.sh.
---

# Review charter

A dedicated reviewer reads three things: this charter, the review bead, and
the diff. Never the whole repo. The charter declares the gate menu triage
classifies over, so a small-context session can decide which reviews a change
needs without reading the whole system.

## Gate menu

Triage is a classifier over this table and nothing else. It may add any gate
declared here, through `signoff.sh --add-gates`; it may not invent one.

<!-- Machine-read by assets/scripts/review-charter.sh, the one parser of this
     grammar. The rows are the table lines after the separator, up to the
     first line that is not a table row. Columns are positional: gate, applies
     when, method, mandatory paths. A mandatory path is an exact repo-relative
     path or a `dir/**` prefix, never a general glob; `-` declares none. The
     parser validates this header before reading any row and refuses a menu
     whose columns were reordered or added, so the format cannot drift under
     the parse without failing loudly. -->

| Gate | Applies when | Method | Mandatory paths |
|---|---|---|---|
| `codex` | always — the standing correctness review | `formulas/mol-review.toml` | `-` |
| `triage` | always — decides which of the rest apply | `skills/review-triage/SKILL.md` | `-` |
| `demo` | the diff changes something the operator watches happen — a board surface, a tmux surface, a visit flow | `skills/gc-demo-script/SKILL.md` + `skills/demo-capture/SKILL.md` | `-` |

A mandatory row takes the judgment out of one decision: when the diff touches
a path the row declares, the gate is added whatever the applies-when column
would have argued. No gate declares one today; a gate whose miss is expensive
declares its paths here.

Every gate added is a one-line `triage-add:` note on the anchor, which is what
makes gate inflation countable by the feedback distiller.

### Why the menu is a table one parser reads

The menu is a human-readable table because the same artifact serves both
readers: a reviewer classifies over it by eye, and
`assets/scripts/review-charter.sh` parses it. One source keeps the two from
drifting. That script is the only reader of the grammar — the triage method,
`signoff.sh --add-gates`, and the dispatch body all go through it — so the
format is understood in exactly one place.

The parser tolerates formatting that does not change meaning: case, extra
spaces, and column alignment all read the same. What it does not tolerate is a
change to which columns exist or their order, because the parse is positional —
a reordered or inserted column would read a cell into the wrong field. So it
checks the header names the four columns, in order, before it trusts a row, and
refuses a menu that does not, naming the mismatch. A column change fails loudly
at the parser and its test rather than shipping a silent misread, which is what
keeps a positional parse of a hand-edited table safe.

## When this charter is missing or stale

A missing or stale charter is the reviewer's first finding. It is filed as a
`task_kind=observation` bead into the feedback loop
([feedback-learning.md](feedback-learning.md)), with
`obs.category=charter-gap`, and the review proceeds on the fallback in
[`skills/review-triage/SKILL.md`](../skills/review-triage/SKILL.md): with no
menu to classify over, triage widens nothing and the standing `codex` review
still runs. The charter is forced into existence by the review that needs it.
