---
name: Review charter — what a dedicated reviewer holds a diff against
description: The few-KB architecture contract a small-context reviewer reads before the diff, plus the declared gate menu triage classifies over — each gate's name, when it applies, its method, the paths that make it mandatory, and whether it may be waived. Read it as a reviewer; parse it as a tool via assets/scripts/review-charter.sh.
---

# Review charter

A dedicated reviewer reads three things: this charter, the review bead, and
the diff. Never the whole repo. The charter is what makes that enough — it
carries the architecture contract in the space a small-context session can
hold, and it declares the gate menu triage classifies over.

## Scope

**Mandate.** The contract a reviewer holds a diff against, and the declared
gate menu with its mandatory paths and waiver warrants.

**Boundaries.** It restates nothing it can point at: the primitive list and
the invariant bindings are [component-model.md](component-model.md), the
system boundary and the six workflows are
[architecture.md](architecture.md), and the gate mechanics — markers, the
merge condition, the widening rule — are
[state-machine.md](state-machine.md). It does not hold the judgment content
of any one gate's method; each gate names its own method skill below.

## The layer map

Four parties, one data plane, and every durable fact is a bead
([architecture.md](architecture.md), "The boundary"). The pack is its six
workflows — work, review, merge, visit, feedback, patrol — and every
component belongs to one of them or is a declared shared primitive.

Four write paths carry the whole lifecycle, and each has exactly one writer:

| Writer | Owns |
|---|---|
| `assets/scripts/lifecycle.sh` | every lifecycle transition, as one atomic `bd update` with read-back |
| `assets/scripts/signoff.sh` | every gate verdict — `check.<g>` markers and the `check_set` widening |
| `assets/scripts/pr-open.sh` | opening a PR, against a green gate at the live head |
| `assets/scripts/merge.sh` | merging a PR, against a re-read authorization set |

A diff that writes lifecycle state, a gate marker, a PR open, or a merge from
anywhere else is a layer violation whatever else it does.

## The admission test

Four questions, from [component-model.md](component-model.md) §4. A change
that adds something must answer the one that applies:

- **A component** answers §1's "cost of not having it" column. A component
  that cannot is a repair pass for a writer that should be fixed instead —
  and the healer category is on the discard list.
- **A state** is declared in `lifecycle/lifecycle.toml` and names its writer
  in [state-machine.md](state-machine.md)'s transition table.
- **A metadata key** is state: it is registered in `lifecycle.toml`, or
  nothing downstream can be proven exhaustive over it.
- **An invariant** names the doctor check that fails when it stops being
  true, in the same change.

Two further shapes the model rejects by name: design a reader must extract
from a paragraph, and a rule that lives only in prose an agent is asked to
remember. A remedy belongs in code that runs.

## Gate menu

Triage is a classifier over this table and nothing else. It may add any gate
declared here, with a one-line justification per gate; it may not invent one.

<!-- Machine-read by assets/scripts/review-charter.sh, the one parser of this
     grammar. The rows are the table lines after the separator, up to the
     first line that is not a table row. Columns are positional: gate,
     applies when, method, mandatory paths, waivable. A mandatory path is an
     exact repo-relative path or a `dir/**` prefix, never a general glob;
     `-` declares none. Waivable is yes or no, and anything else reads no. -->

| Gate | Applies when | Method | Mandatory paths | Waivable |
|---|---|---|---|---|
| `codex` | always — the standing correctness review | `formulas/mol-review.toml` | `-` | no |
| `triage` | always — decides which of the rest apply | `skills/review-triage/SKILL.md` | `-` | no |
| `arch` | the diff changes a declared state space, a single writer, or the design authority; adds a component, a state, or a metadata key; or crosses a top-level directory | `skills/arch-review/SKILL.md` | `lifecycle/**` `assets/scripts/lifecycle.sh` `assets/scripts/signoff.sh` `assets/scripts/merge.sh` `docs/architecture.md` `docs/component-model.md` `docs/foundation.md` `docs/state-machine.md` | no |
| `demo` | the diff changes something the operator watches happen — a board surface, a tmux surface, a visit flow | `skills/gc-demo-script/SKILL.md` + `skills/demo-capture/SKILL.md` | `-` | yes |

`arch`'s mandatory paths are the places where a wrong change is expensive and
where "the diff crossed a layer" is not a judgment call: the state
declaration, the three single writers, and the four documents that hold the
design authority. `doctor/**` and `formulas/**` are deliberately absent —
their routine churn would make the mandate meaningless, so triage decides
them from the applies-when column.

## Mandatory rows and waivers

A mandatory row is a mechanical backstop for a triage miss, not triage's job.
`doctor/check-gate-integrity` re-derives each open anchor's branch diff and
warns when a mandated gate is missing from `check_set`.

The only sanctioned narrowing is a triage waiver, and only for a gate this
table marks waivable:

```bash
signoff.sh --review-bead <id> --verdict approve \
  --waive-gates demo --justification "docs-only change; nothing the operator watches happen"
```

`signoff.sh` refuses a waiver for a gate the charter does not mark waivable,
and refuses every waiver when no charter is readable — a narrowing warrant is
declared or it does not exist. Widening carries no such condition: adding a
gate is always safe, so an unreadable charter still permits `--add-gates`.

Waivers are expected to be rare. Both the add-rate and the waiver-rate are
one-line notes on the anchor (`triage-add:` / `triage-waive:`), which is what
makes gate inflation and waiver drift countable by the feedback distiller.

## When this charter is missing or stale

A missing or stale charter is the reviewer's first finding. It is filed as a
`task_kind=observation` bead into the feedback loop
([feedback-learning.md](feedback-learning.md)), with
`obs.category=charter-gap`, and the review proceeds on the fallback in
[`skills/review-triage/SKILL.md`](../skills/review-triage/SKILL.md): add
`arch` when the diff creates a file, crosses a top-level directory, or
changes a public interface. The charter is forced into existence by the
review that needs it.
