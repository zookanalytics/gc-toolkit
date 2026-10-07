---
name: Review Configuration Conventions
description: The function-named files a rig provides for the review system — the check index and per-check method extensions — where they live, and how the review machinery reads them.
---

# Review configuration

A rig tells the review system which checks to run, and how, through two files it
keeps in its own repository: the check index and, where a check needs it, a
method extension. Both are named for their function and both are read from the
commit under review, so a branch is judged against the configuration it carries.
A rig that provides neither still gets the forced baseline review.

## Scope

**Mandate.** The configuration files a rig provides for the review system: their
names, where they live, the rule that decides when a file is named for a check,
and how the review machinery reads them.

**Boundaries.** This does not cover the review machinery itself — the index
parser (`assets/scripts/review-checks.sh`), the dispatch composer
(`assets/scripts/review-dispatch-body.sh`), and the check methods
(`formulas/mol-review.toml` and the `skills/review-*` method skills) are pack
content. Nor does it decide which checks a given rig declares; that judgment
lives in each rig's own index.

## The check index: `review-checks.toml`

The check index is `review-checks.toml` at the repository root. It declares the
checks the repository makes available to review. For each check it carries
mechanical facts only: the check name, a pointer to the method that governs the
check, and one line of purpose.

```toml
[checks.correctness]
method = "formulas/mol-review.toml"
purpose = "Is the change correct and safe as merged?"

[checks.arch]
method = "skills/review-arch/SKILL.md"
purpose = "Does the change fit the architecture, and is any architecture change justified and documented in the same PR?"
```

The index carries no judgment. There is no applies-when column: when a check
applies is a judgment the check's method states in prose, which triage reads.
Keeping judgment out of the index is what lets it stay a small data file.

`assets/scripts/review-checks.sh` is the one parser of this grammar. Every
reader goes through it — the triage method, `signoff.sh`, and the index tests —
so they all read the same rows.

The forced baseline is `correctness` and `triage`. Both run on every anchor that
does not opt out, whether or not an index is present. The index's job is to make
the specialist checks available, so that triage may widen an anchor's check set
to add any check the index declares. A repository with no index offers only the
baseline, and the missing index is a finding triage files, not an error that
stops the review.

## A check's method extension: `docs/review-<check>.md`

A check's method has two layers. The generic method is pack content that every
rig installing the pack gets: the per-check arm in `review-dispatch-body.sh`
and, for correctness, the steps of `mol-review.toml`. A rig may add a local
extension at `docs/review-<check>.md` in its own repository — `docs/review-arch.md`
for the arch check, `docs/review-pm.md` for the PM check. The dispatch note
appends the extension to the generic method text. The extension adds; it never
replaces, and absent is the common case.

An extension earns its place when a rig needs to point a check at reference docs
the generic method would not find on its own, or to add method guidance specific
to that rig.

## Reference docs a check reads

A specialist check reads reference documentation before it judges, and its
generic method names a conventional location for that reference. The arch check
reads `docs/architecture.md` and the `docs/architecture/` directory it anchors;
the PM check reads `docs/product-goals.md`. These are ordinary repository docs.

When a rig keeps the reference somewhere other than the conventional path — an
architecture spread across `engdocs/architecture/`, say — its
`docs/review-<check>.md` extension names where the check should read instead. A
reference missing at the reviewed commit is a gap the check notes, not a reason
to pass or fail the change.

## Named for function

A review-configuration file is named for what it does. A file carries a check
name only when its content is that one check's: `docs/review-arch.md` holds the
arch method extension and nothing else. The check index serves every check, so
it is named for its function, `review-checks.toml`, not for any one check.

## Read from the reviewed commit

Every file here is read pinned to the commit under review, through
`git show <reviewed_oid>:<path>`, never from the working tree or the installed
skill catalog. A branch is judged against the index and the methods its own
commit declares, so a rig that tightens a check's method tightens it for the
commits made after the change, not for work already in flight. This is also why
a method extension is a plain repository file rather than a skill: a skill loads
from the installed catalog, which cannot be pinned to the diff's commit.

## Summary

| File | Location | Read by | Carries |
|---|---|---|---|
| `review-checks.toml` | repo root | `review-checks.sh` | the checks the repo makes available: name, method pointer, purpose |
| `docs/review-<check>.md` | rig repo | `review-dispatch-body.sh` | a rig's additions to one check's generic method |
| reference docs (`docs/architecture.md`, `docs/product-goals.md`, …) | rig repo | the check's method | the material the check judges against |
