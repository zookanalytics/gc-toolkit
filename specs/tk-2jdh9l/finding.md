---
name: Keyless closed visits — are they an escalate.sh bypass?
description: Investigation of the 312 closed gc-toolkit visits carrying no escalation_key — which paths file them, whether any should route through escalate.sh, and the moot/benign rate tk-x3elmf could not measure. Conclusion for tk-2jdh9l.
---

# Keyless closed visits are the intended visit family, not an escalate.sh bypass

## Bottom line

The closed visits with no `escalation_key` are the pack's conversation-and-board
visit family (the shared `gate-visit` snippet), deliberately separate from
`escalate.sh`'s keyed escalation path and adopted as the human-gate resolution
model in #655. They are keyless on purpose: each is one-per-subject, deduped by
`gc.continuation_group`. No producer should route through `escalate.sh`, and none
is an ungated volume source.

The premise behind the split-off worry inverts under measurement: the keyless
population's moot/benign rate is **~10%**, while the `escalate.sh`-keyed population
runs **~52%**. The noise lives in the keyed population, not the keyless one.

## The question (tk-2jdh9l, split from tk-x3elmf)

tk-x3elmf added a verdict window to `escalate.sh` and measured only the keyed
visits. This bead asks, of the closed visits carrying no `escalation_key`: which
paths file them, whether each should route through `escalate.sh`, and whether any
is a volume source worth gating. tk-x3elmf left this set's moot/benign rate unknown.

## Measurement

Store-wide, closed visits (`--limit 0`, so not capped at the default page — the
split-off's "100" was that cap):

| population | count | moot+benign | rate |
|---|---|---|---|
| all closed visits | 886 | — | — |
| keyless (no `escalation_key`) | 312 | 30 | **9.6%** |
| keyed (`escalate.sh`) | 574 | 298 | **51.9%** |

Keyless outcomes are dominated by real dispositions: routed 51, settled 49, ruled
39, disposed 22 — moot is only 28, benign 2. Keyed outcomes are dominated by moot
220 + benign 78 (+ unrecorded 109).

Reproduce (the preface prints to stderr, so a bare pipe to jq is clean):

```bash
gc bd list --status closed --limit 0 --json \
  | jq '[.[] | select((.metadata.task_kind // "")=="visit")]
        | {keyless:[.[]|select((.metadata.escalation_key // "")=="")]|length,
           keyless_mootbenign:[.[]|select((.metadata.escalation_key // "")=="")
             |select(((.metadata["gc.outcome"]//"")|ascii_downcase)|.=="moot" or .=="benign")]|length,
           keyed:[.[]|select((.metadata.escalation_key // "")!="")]|length}'
```

Keyless filers (by `created_by` role): operator board picks 142, proactive pool
77, `order:gate-visit-sweep` 28, witness 12, polecat 10, mayor 8, converse ~15,
the rest in ones and twos. By month created: Aug 86, Sep 207, Oct 19.

## The two visit families (the structural fact)

There is one visit-filing snippet (`gate-visit`), copied verbatim into six
canonical locations and guarded by `assets/scripts/gate-visit.test.sh`. Only
`escalate.sh`'s copy adds `escalation_key`. Every other copy is keyless by
construction — it stamps `gc.routed_to=human`, `gc.continuation_group=<subject>`,
`task_kind=visit`, and a `tracks` edge, nothing more.

- **Keyed (`escalate.sh`):** keeps exactly one open visit per *situation key* and
  carries the verdict window that suppresses re-raising a situation a human already
  ruled moot/benign (`escalate.sh:296-305,368-382`). This serves a *recurring*
  escalation that is not one-per-subject — an agent that keeps hitting the same
  blocker, a cross-subject bucket like `witness-refinery-queue`.
- **Keyless (`gate-visit` family):** one conversation or decision per *subject*,
  deduped by `gc.continuation_group` and by the snippet/`gc-helm.sh open` refusing
  a second open visit on a bead. The subject is the key; there is no recurring
  cross-subject situation to collapse and no re-raise to suppress.

## Keyless producers, and why none routes through escalate.sh

| producer | file | trigger / volume | dedup grain | route through escalate.sh? |
|---|---|---|---|---|
| `gc-helm.sh open` | `gc-helm.sh:1800` | operator board pick (142 "Zook Bot") | one open visit per bead, refused otherwise | **No** — this is the human filing *to* the agents; `escalate.sh` is an agent escalating *to* a human. Backwards. |
| `mol-first-reaction` | `mol-first-reaction.toml:496` | per intake item, on the `proactive-scan-sling` cadence; the human-decision minority exit | once per bead (already-reacted guard `:111-123`), `continuation_group=<subject>` | **No** — it reacts once per bead, so there is no re-raise for a verdict window to catch; per-subject is the correct grain. |
| `mol-validate-close` | `mol-validate-close.toml:128` | a proposed close that failed validation (downstream of first-reaction) | per subject | **No** — same per-subject grain. |
| `mol-visit` | `mol-visit.toml:44` | on-demand "I want to talk about this" | per subject | **No** — a one-off conversation. |
| `mol-feedback-distiller` | `mol-feedback-distiller.toml:541` | a contested learning rule (rare) | one live visit per contested pattern | **No** — already deduped per pattern. |

`order:gate-visit-sweep` (28 visits, 61% moot) files through `gc-helm.sh open` and
dedups via `gc.gate_visit` stamped on the gate — a sound, deliberate idempotence
key (not `escalation_key`, and deliberately not "is a visit open now"; the script
header explains why). Its high moot rate is the gate *clearing* — the human gate
resolved by other means — which is success, the opposite of `escalate.sh`'s moot
(a false-alarm blocker). The one apparent duplicate (two visits on `tk-mq9bvj`) was
filed 20h apart, the second after the first had closed: the documented
`unset gc.gate_visit` re-offer, not a dedup gap.

Every keyless producer dedups at the per-subject grain, which is the right grain
for a one-per-subject conversation or a once-per-bead decision. `escalation_key`
adds the cross-subject collapse and the re-raise verdict window — machinery for a
shape none of these producers has.

## What keyless visits do not participate in

Readers of `escalation_key`, and whether a keyless visit's absence from them matters:

- `escalate.sh`'s own per-key dedup + verdict window (`:296-305,368-382`) — correctly
  scoped to its own keys; not a global measurement with a gap.
- `finding.sh:496` per-finding reuse — findings file *through* `escalate.sh`, so they
  are keyed; not affected.
- `pr-facts.sh:395,732` PR-situation lookup — not applicable to conversation/decision
  visits.
- `converse-fold.sh:76,92` fold topic — keyless visits fall back to folding by subject
  (coarser), a graceful degradation, not a drop.
- `dead-molecule-dispose.sh:326` GUARD 3 "every escalation answered" — refuses to
  dispose a molecule while an *open keyed* visit tracks it. See follow-up below.
- `mol-witness-patrol.toml:804` refinery-queue reconcile — keyed on its own
  `witness-refinery-queue`; not a general reader.

The Go board (`services/helm`, `services/gctk`) reads none of `escalation_key`; it
keys visits on `task_kind` + `gc.continuation_group`, so keyless visits render on the
board normally, and `check-visit-outcome-recorded` scans all closed visits, not a
keyed subset. There is no shipped per-filer measurement blind to the keyless family.

## Conclusion

No code change is warranted to route a keyless producer through `escalate.sh` or to
add gating: each producer already dedups at the correct (per-subject) grain, and the
keyless population is lower-noise than the keyed one. The accompanying change states
the two-family distinction in `docs/gascity-human-engagement.md`, which described the
keyless gate→visit channel but never named the parallel keyed `escalate.sh` channel —
the silence that let a keyless population read as an ungated bypass.

## One follow-up candidate (out of scope here)

`dead-molecule-dispose.sh` GUARD 3 protects only *keyed* open visits. Whether a
keyless `mol-first-reaction` human-decision visit could be lost when its first-reaction
molecule is disposed is worth a bounded check. It is plausibly safe — that visit parks
the *subject* on the board (`gc.routed_to=human`) independent of the molecule's life —
but the claim was not verified here and does not belong to this bead's question.
