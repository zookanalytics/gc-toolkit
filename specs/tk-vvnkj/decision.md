---
name: Decision — where the health-instruments boundary lives
description: Why the `gc doctor` bound ships as a targeted gc-toolkit fragment injected into mayor and mechanik, rather than as a city.toml-elected replacement of gastown's operational-awareness fragment. Read before changing how that fragment is wired.
---

# Decision — where the health-instruments boundary lives

**Bead:** tk-vvnkj. **Decided:** 2026-08-22. **Predecessor:** tk-julp3
(bounded the grant in the mechanik prompt body). **Sibling:** tk-lpf9g
(whether a gc-toolkit fragment can override an imported one — answered yes).

## What was already decided before this bead

The operator ruled the *shape*: **a fragment**, not prose re-stated in each
consuming prompt body, and not mechanik-only. That ruling is on the bead and
is not revisited here.

What the ruling explicitly left open — "pick with the diff in hand and record
which and why" — is which of two additive/replacing shapes to build:

- **REPLACE** — carry a gc-toolkit copy of gastown's `operational-awareness`
  under a distinct name, with the bound folded in, and swap the entry in
  `city.toml` `[agent_defaults].append_fragments`.
- **ADDITIVE** — keep consuming gastown's fragment untouched and inject a
  small gc-toolkit boundary fragment beside it.

This document records the pick and the evidence.

## Decision

**ADDITIVE, wired through gc-toolkit's own injection surfaces** — not through
`city.toml`.

- `template-fragments/health-instruments-boundary.template.md` — the bound.
- `pack.toml` `[[patches.agent]] name = "mayor"` → `inject_fragments_append`
  gains `"health-instruments-boundary"`. The mayor's prompt is gastown's and
  is not forked; this is the same fragment-append overlay the mayor already
  receives five other doctrines through.
- `agents/mechanik/prompt.template.md` — the bullet tk-julp3 landed is
  replaced by `{{ template "health-instruments-boundary" . }}`, so the text
  exists in exactly one place. Same mechanism `upstream-engagement` already
  uses in that file.

`city.toml` is not touched. Gastown's fragment is not touched.

## Why ADDITIVE over REPLACE

**1. REPLACE freezes 126 lines to bound one bullet.** Gastown's
`operational-awareness` is not a thin wrapper — it carries identity, the
five-step Dolt diagnostic ladder with its exit-code and timeout reasoning, the
nudge-vs-mail rule, and the mail lifecycle. All of it is actively maintained
upstream and safety-critical. A local copy stops receiving upstream fixes, and
the failure is silent: the fragment still renders, it is just stale. That is
the cost `docs/gascity-packs.md` §7 names for shadowing, paid against the one
file in the city that tells every agent what to do when the data plane is
sick.

**2. REPLACE's mis-order failure is city-wide; ADDITIVE's is one paragraph.**
`cmd/gc/prompt.go:198-211` skips an unresolvable fragment name with a stderr
line and continues. Under REPLACE the old name is *removed* from the list, so
a swap that lands before the file exists renders every agent in the city with
no operational-awareness block at all — no Dolt triage ladder, no
untrusted-instructions guidance. Under ADDITIVE the grant fragment stays
listed and the worst case is a missing boundary paragraph.

**3. Decisive, and new since the ruling: the deacon.**
`[agent_defaults].append_fragments` reaches **every** agent in the city,
including the deacon. The deacon *owns* the health instruments — its
diagnostics step is the scheduled `gc doctor` pass that this boundary points
at. Injecting "the instruments are not yours; a clean queue needs no
corroboration" into the deacon's own prompt is at best noise in the wrong
prompt and at worst a self-contradiction it has to resolve mid-patrol. Any
city-wide election has this problem regardless of REPLACE vs ADDITIVE; only a
targeted injection avoids it.

Verified per agent against a synthetic city importing this branch
(`gc prime <agent> --city <synth> --strict`):

| agent | carries the grant | carries the bound |
|---|---|---|
| mayor | yes | **yes** |
| mechanik | yes | **yes** |
| deacon | yes | no — it owns the instruments |
| polecat, refinery, witness, converse | yes | no |

## What this costs, stated plainly

The grant lives in gastown's file and the bound lives in ours: two files, one
subject. That is inherent to bounding text you do not own, and it is one
paragraph against 126 lines. The alternative — one file, ours, frozen — buys
adjacency at the price of every future upstream fix to the Dolt ladder.

Adding a role later is a one-line change to its `inject_fragments_append` (an
imported agent) or one `{{ template }}` call (a native gc-toolkit agent).
Converse was considered and left out: the observed behaviour was the mayor's
and the mechanik's, and the bead scopes both.

## Not done here

- **No doctor check pins the wiring.** `doctor/check-operator-next-step-wiring`
  is the precedent for one — it asserts a fragment reaches a declared roster
  through any of the three injection surfaces and records a per-role yes/no
  with reasons. It would fit this fragment exactly, including the deacon's
  deliberate "no". It was not built because the bead does not ask for it and
  every other mayor fragment lives without one; the roster above is the
  declaration a future check would encode.
- **`city.toml` is untouched**, so nothing about this change is pending on the
  town repo. That was the sequencing hazard the bead's implementation note was
  written for; choosing gc-toolkit's own injection surfaces removes it rather
  than managing it.
