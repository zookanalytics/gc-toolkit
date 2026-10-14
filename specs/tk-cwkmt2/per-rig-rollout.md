---
name: Per-rig review-check index rollout
description: tk-cwkmt2's decision record — which review checks each city rig declares in its review-checks.toml, why, the extensions needed, and the per-rig beads that land them.
---

# Per-rig review-check index rollout

tk-cwkmt2 has two deliverables. The rig-agnostic naming convention for review
configuration is documented centrally in `docs/review-config.md`. The per-rig
check indexes are rolled out to the city's other rigs. This record holds the
per-rig judgment and the reason the rollout is decomposed.

## Why the rollout is one bead per rig

A rig's `review-checks.toml`, and any `docs/review-<check>.md` extension, is read
from the commit under review in that rig's own repository
(`git show <oid>:review-checks.toml`). It is not pack content and is not seeded
from gc-toolkit — `review-checks.toml` lies outside the paths the
`generated/seed-audit` render reads. A gc-toolkit PR therefore cannot carry
another rig's index. The rollout is one self-contained work bead per rig, filed
in that rig's store and dispatched to its polecat pool on `mol-polecat-work`.
This record and `docs/review-config.md` are the gc-toolkit-side deliverable; the
indexes land through the per-rig beads and each rig's own review.

loomington (HQ) is not in the rollout: it has no `[[rigs]]` entry in
`city.toml`, no refinery, and runs no review gates. gc-toolkit's own index
already landed with tk-3h9mzz.

## The checks

`correctness` and `triage` are the forced baseline and run on every anchor
regardless of the index. The index makes the specialist checks available for
triage to add:

- `demo` — the operator-watched surface was recorded doing the thing.
- `arch` — the change fits the architecture, and any architecture move is
  justified and documented in the same PR.
- `pm` — the change solves the right user problem and presents it so the
  operator can judge.

A specialist check reads a reference doc at a conventional path (`arch`:
`docs/architecture.md` and `docs/architecture/`; `pm`: `docs/product-goals.md`).
A rig whose reference lives elsewhere points the check there with a
`docs/review-<check>.md` extension.

## Per-rig judgment

| Rig | Check set | demo | arch | pm | Extension | Bead |
|---|---|---|---|---|---|---|
| signal-loom | correctness, triage, demo, arch, pm | yes | yes | yes | none | sl-sk5rw |
| gascity | correctness, triage, arch | no | yes | no | docs/review-arch.md | gc-7dr9l |
| shutupandlisten | correctness, triage, demo, arch, pm | yes | yes | yes | docs/review-arch.md | su-v9hyy |
| sprintshow | correctness, triage | no | no | no | none | ss-04a |

**signal-loom** (`sl-sk5rw`) — the Inkling authoring web app, a full end-user
product. `demo`: a Next.js app with Playwright e2e. `arch`: substantial docs
under `docs/architecture.md`, `docs/adr/`, `docs/rebuild-architecture.md`, which
the arch check reads out of the box, so no extension. `pm`: `docs/brief.md`,
`docs/prd.md`, `docs/go_to_market.md`. Follow-up left to the bead: the PM check
reads `docs/product-goals.md`, which signal-loom lacks, so it adds one or a
`docs/review-pm.md` pointing at the product docs it has.

**gascity** (`gc-7dr9l`) — the orchestration engine: a Go monorepo with a CLI
and a REST/SSE control plane, no in-repo UI. `demo` excluded (no operator-watched
surface in the repo; the managed dashboard's code lives elsewhere). `pm`
excluded (developer infrastructure, no product-goals doc, no end-user features; a
candidate if gascity later defines product goals). `arch` included — deep docs
under `engdocs/architecture/` and `docs/reference/` — and because those are not
at `docs/architecture.md`, the bead also authors a `docs/review-arch.md`
extension pointing the check there.

**shutupandlisten** (`su-v9hyy`) — a voice-mode end-user product shipping several
watched surfaces. `demo`: an iOS app, a web harness, demo mp4s. `arch`: the spine
is `CONCEPTS.md` plus `spec/turn-state-machine.md` and `spec/turn-vectors/`; not
at `docs/architecture.md`, so the bead authors a `docs/review-arch.md` pointing
there. `pm`: product-evaluation docs (`docs/usefulness-bar.md`,
`docs/ios-product-evaluation.md`); same `docs/product-goals.md` follow-up as
signal-loom.

**sprintshow** (`ss-04a`) — a small TypeScript demo-capture library with no
operator-watched surface of its own, no architecture docs, and no product
surface. Its considered set is the baseline. An explicit baseline index (rather
than no index) stops triage filing a "missing index" finding every review and
records the baseline as deliberate. Revisit if it grows a watched surface,
architecture docs, or product goals.

## Status

All four are filed and dispatched to their rig's `gc-toolkit.polecat` pool with
`mol-polecat-work` attached: sl-sk5rw (workflow sl-g9t0f), gc-7dr9l (gc-8u9qg),
su-v9hyy (su-rti8y), ss-04a (ss-50s). They are not gated on this PR: the
convention is already live — the review machinery reads it now, and
`specs/tk-3h9mzz/review-gates-foundation.md` and gc-toolkit's own
`review-checks.toml` are the reference each bead cites.
