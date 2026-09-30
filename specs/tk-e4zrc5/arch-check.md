---
name: The arch check — the Architect's method and reference-docs convention
description: Design record for the arch specialist review check on gc-toolkit — what the Architect judges, the two verdict shapes, the enforce-not-edit rule, and the settled reference-docs convention (docs/architecture.md plus the docs/architecture/ owned directory). Read to see why the arch check reads the architecture first and where its stewarded docs live.
---

# The arch check

The `arch` check is the first specialist review check after the forced baseline
(`correctness`, `triage`). Its persona is the Architect: the active steward,
gatekeeper, and owner of the repo's high-level architecture, holding each change
accountable to architectural discipline and pushing back on architectural harm
rather than waving it through. It lands as content within the review-gates model
the foundation set (`specs/tk-3h9mzz/review-gates-foundation.md`) — a specialist
check is an index row, a generic method, and an optional rig extension, and the
arch check is exactly those three.

## What the Architect does

The check reads the architecture reference docs first, then judges the diff
against them. That order is the point: a review cannot hold a change to the
architecture without having read the architecture. It judges two things —
whether the change leverages the existing architecture, and whether it changes
the architecture; if it does, whether that change is justified and reflected in
the architecture docs in the same PR.

The verdict is binary — `signoff.sh` writes `approve` or `request-changes`, and
there is no "approve on a condition": a requirement that must hold before approval
is a precondition, and a change that has not met it earns `request-changes`.

- **Approve.** The change fits the architecture: it either leaves the
  architecture unchanged, or moves it with justification and the matching
  architecture-doc update in this same PR. The diff is where an architecture
  change becomes visible to a human, so the record moves with the code.
- **Request changes.** Every other case — the architecture moved but its doc
  update is not in this PR (send it back to land the doc here), or the move is
  well-documented but a design fitting the architecture already in place would
  not have needed it (send it back to the drawing board).

The check enforces; it never edits. It conditions its verdict and files
findings, and the doc update lands in the reviewed PR, not from the review.

Architectural issues the Architect finds but this change did not cause are filed
as new beads. Independent drift in the architecture docs is one such case — the
finding files that maintenance as its own work. When the change aggravates an
existing pattern — a third instance that complicates the architecture — the
Architect judges whether to fix it here (low impact, a simple refactor;
`request-changes` carries it) or file a followup bead for a broad rearchitecture
that belongs in its own PR. Anything deferred is named in the verdict body, which
`signoff.sh` posts to the PR, so the deferral is visible where the change lands.

## Deliverables

- **Index row** — `[checks.arch]` in `review-checks.toml`, pointing at the
  generic method and stating the check's purpose.
- **Generic method** — `skills/review-arch/SKILL.md`, carrying the persona, the
  read-first discipline, the two verdicts, the enforce-not-edit rule, and the
  out-of-scope-finding rule. It is pack content: every rig that installs the pack
  gets it. The `arch)` arm in `assets/scripts/review-dispatch-body.sh` summarizes
  it and points the reviewer at it, the way the `triage` and `demo` arms point at
  their skills; the arm is also where the optional rig extension is appended.
- **Reference-docs convention** — settled below.

## The reference-docs convention

The Architect stewards `docs/architecture.md` — the 30,000-ft, human- and
generic-LLM-facing guide — plus an owned directory, `docs/architecture/`. That
location follows `docs/file-structure.md`: a topic promotes from
`docs/<topic>.md` to a `docs/<topic>/` directory when sibling sub-topics warrant
it, so the architecture topic's owned directory is `docs/architecture/`. The
Architect has autonomy over what lives there, guided by the documentation's
goals — useful to the reviewing agent itself, communicates the big picture,
provides foundation. Some files there may be agent-facing only; one or two are
the human- or generic-LLM-facing documents. This work settles the location; it
does not populate the directory — that is the Architect's to grow.

A rig may extend the generic method with `docs/review-arch.md` in its own repo,
read from the reviewed commit and appended to the generic arm, never overriding
it (the composition model from `specs/tk-3h9mzz/`). A rig whose architecture
docs live elsewhere names them there; gc-toolkit's live at the convention
location, so gc-toolkit ships no extension.

## Why this change needs no architecture-doc update

Applying the Architect's own test to this change: adding a specialist check does
not alter the architecture. The foundation already established the check model,
the widenable `check_set`, and the seam for specialist checks; this work fills
one declared seam with content — an index row and a method skill the dispatch arm
summarizes — and changes neither the merge predicate nor how a lane's green is
derived. The architecture
docs already speak of "every declared check" generically, so they stay true as
written.
