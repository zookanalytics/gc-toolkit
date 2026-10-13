---
name: Keyless visits need one open visit per subject, not escalate.sh
description: Investigation of the closed gc-toolkit visits carrying no escalation_key — which paths file them, whether any should route through escalate.sh, their moot/benign rate — and the duplicate-visit defect it found in the formula copies of the gate-visit block, fixed alongside. Conclusion for tk-2jdh9l.
---

# Keyless visits need one open visit per subject, not escalate.sh

## Bottom line

The closed visits with no `escalation_key` come from the conversation channel,
the keyless copies of the shared `gate-visit` snippet. They are not an
`escalate.sh` bypass, and routing them through `escalate.sh` would not help.
What its verdict window catches is a situation re-filed after a person ruled it
moot or benign, and keyless visits are almost never re-filed that way.

The filing-time gate a conversation visit does need is one open visit per
subject, and only `gc-helm.sh open` had it. The four formula copies, in
`mol-visit`, `mol-first-reaction`, `mol-validate-close` and
`mol-feedback-distiller`, filed without looking. A step that ran twice therefore
filed two visits. `mol-first-reaction` did this on three subjects. Each subject
was held on one visit of its pair, and the other would go on asking after the
first was answered. A sitting had closed one extra as a duplicate; the other two
were folded into their twins on 2026-10-05.

The fix ships with this finding. Every formula copy now reuses the conversation
visit already open on its subject before it files, and never reuses an
escalation visit. `assets/scripts/gate-visit.test.sh` executes every formula
copy against both cases. PR #1043 landed first and replaced
`mol-first-reaction`'s copy with a human gate, so three formula copies carry the
check.

## The question

tk-x3elmf added a verdict window to `escalate.sh` and measured only the keyed
visits. This bead asks, of the closed visits carrying no `escalation_key`, which
paths file them, whether each should route through `escalate.sh`, and whether
any is a volume source worth gating.

## Who files keyless visits

When this was measured, six places created a `task_kind=visit` bead, and each
was a marked copy of the `gate-visit` snippet. Only `escalate.sh`'s copy stamps
`escalation_key`.

| filer | reached by | open-visit check at filing, before this change |
|---|---|---|
| `gc-helm.sh open` | operator board picks, `gate-visit-sweep`, `gc-visit-open.sh` | folds into any visit open on the subject; `engage` asking for a new visit passes `--allow-duplicate` |
| `mol-first-reaction` | the ruling and recommend exits | none |
| `mol-validate-close` | a proposed close that did not validate | none |
| `mol-visit` | "I want to talk about this", and converse filing a visit on another subject | none |
| `mol-feedback-distiller` | a contested learning rule | prose only ("skip if one is already open") |
| `escalate.sh` (keyed) | an agent escalating | one open visit per subject and key, plus the verdict window |

Keyless visits by filer, open and closed, read from the titles that name one:
first reaction 128, the board's default "operator pick" 92, `gate-visit-sweep`
29 and validate-close 4. The other 132 carry free-text titles, from `gc-helm.sh
open` with a reason, from `mol-visit`, and from producers since retired.

Nothing that renders or measures visits reads `escalation_key` apart from
`escalate.sh` itself. `services/` and `doctor/` carry no reference to it, and
`check-visit-outcome-recorded` scans every `task_kind=visit` bead.

## Measurement

As of 2026-10-05T17:52Z, from the gc-toolkit store (`gc bd list --status closed
--metadata-field task_kind=visit --limit 0`). The counts grow as visits close,
so the rates are what compares across runs.

| population | closed | moot+benign | rate |
|---|---|---|---|
| keyless | 321 | 33 | 10.3% |
| keyed (`escalate.sh`) | 642 | 360 | 56.1% |

**Re-filed after a verdict, the only case a verdict window catches.** Of 385
keyless visits (321 closed, 64 open), 10 were filed after the subject's most
recent closed visit was ruled moot or benign, and 5 of those inside the 24-hour
default window. Two of the five were operator board picks, which a window must
not mute. Two followed a moot verdict on a keyed escalation, which had asked a
different question about the same subject. One came from a witness producer
that no longer exists. A keyless verdict window would have had nothing live to
catch.

**`gate-visit-sweep`'s moot share.** 17 of its 28 closed visits read moot, and
all 28 were filed before 2026-09-21. Twelve of the 17 were closed in one
stale-visit sweep that day (tk-hexkmx): visits left open after their gate, a
since-retired signoff-cap gate, or their subject had closed. Four more were
closes `converse-claim` completed after a sitting stamped moot. The sweep has
filed one visit since. This is a one-time cleanup of a retired gate type, not a
live noise source.

## The defect: filing without looking

Subjects that held two keyless visits open at once:

| subject | visits, in filing order | filed | held on | the extra |
|---|---|---|---|---|
| tk-crwixa | tk-v55jpc, tk-g83dov | 2026-09-24 15:14Z and 15:19Z, both by the proactive-1 pool | tk-g83dov | tk-v55jpc open 11 days, folded into tk-g83dov 2026-10-05 |
| tk-kv146i | tk-hby3e0, tk-6hxc2s | 2026-09-18 17:25Z and 17:34Z, both by the proactive-2 pool | tk-6hxc2s | tk-hby3e0 open 17 days, folded into tk-6hxc2s 2026-10-05 |
| tk-88j8wj | tk-26mgvz, tk-3x9n6i | 2026-10-04 12:49Z and 12:53Z, two sessions | tk-26mgvz | tk-3x9n6i closed `duplicate` by a sitting the same day |

All three are `mol-first-reaction`'s "first reaction ready" visit. The first
filing in each pair completed: tk-v55jpc, tk-hby3e0 and tk-26mgvz each carry all
three stamps and a tracks edge, and tk-v55jpc's edge landed ten seconds after
its create. On tk-crwixa and tk-kv146i the reaction's disposition was stamped
after the second visit, which is the shape of the exit block running twice. The
formula tells the worker to re-run that block when `first-reaction-dispose.sh`
fails, and a step re-offered to a second session runs it again too. The block
filed whenever it ran.

The board folds both visits onto the subject's row. When the operator answers
the held one, the other keeps the subject showing as owed with the same ask.

## The fix

- Each formula copy of the `gate-visit` block lists the open and in_progress
  `task_kind=visit` beads and keeps the conversation visits, those with no
  `escalation_key`, that cover the subject. Coverage is `visit-identity.sh`'s
  `visit_covers`: the tracks edge, else the `gc.continuation_group` stamp. The
  block reuses the lowest id, the tiebreak converse's fold also uses, and files
  only when none matches.
- An escalation visit is never reused. `escalate.sh --retract` closes one as
  moot when its own situation clears, and the formula's question would close
  with it, unasked.
- A listing that does not read files anyway, and so does a block that cannot
  find `visit-identity.sh`, which also warns. A second visit is a bounded
  nuisance, and a visit never filed asks nobody.
- `gate-visit.test.sh` runs the canonical copy against eleven listing shapes and
  runs every formula copy against the reuse case and the escalation case. The
  suite fails on each of these mutants: main's three copies, and in a single copy
  dropping the escalation filter, the status filter, the `task_kind` check, the
  tracks-edge coverage, the lowest-id choice, or the reuse branch.
- A read-only run of the lookup against the live store found tk-g83dov for
  tk-crwixa, tk-6hxc2s for tk-kv146i and tk-26mgvz for tk-88j8wj, each the visit
  its subject is held on. It found nothing for tk-c22a1q and tk-p9549d, which
  have only escalation visits open.

PR #1043 (tk-q8fkah) landed first. It moved `mol-first-reaction` from filing a
visit to filing a human gate, which `gate-visit-sweep` turns into a visit
through `gc-helm.sh open`, the filer that already folds into an open visit. That
removed the copy where every duplicate came from, so this change leaves
`mol-first-reaction` as main has it, and the reuse check covers the other three
copies.

## Not changed, and why

- **No keyless filer routes through `escalate.sh`.** Its key collapses a
  recurring situation across subjects, and its window mutes a re-filed one. A
  conversation visit is one per subject, and the measurement above shows almost
  no re-filing for a window to mute.
- **`dead-molecule-dispose.sh` reads only keyed visits in its open-escalation
  guard, and that is correct.** The guard refuses to dispose a dead molecule
  while an open escalation visit tracks its root or work bead, because that
  visit is the release path of a held molecule. A `molecule-hold.sh` hold that
  waits on a person is always filed behind an `escalate.sh` visit, in the polecat
  doctrine and in every such hold in `mol-polecat-work` and `mol-validate`. The
  holds that wait on no person, a finished duplicate dispatch or blockers with a
  re-dispatch armed, file no visit. A keyless visit is never a hold's release
  path, and it outlives the molecule: the dispose closes only the root and its
  step beads, so a first reaction's gate, the visit filed for it, and the
  subject's hold stay intact.
- **The create in the formula copies is still two writes**, a create and then
  the stamps. tk-6t09b8 tracks making it one write, and tk-vxw40 tracks the same
  for `gc-helm.sh open`. A visit whose stamps never landed has no
  `gc.routed_to`, so it never reaches the board. A re-run past it files one
  visit the operator sees, not a second.

## Reproduce

Rates by population. This reads the live store, so the counts sit at or above
the snapshot above.

```bash
gc bd list --status closed --metadata-field task_kind=visit --limit 0 --json \
  | jq 'def mb: ((.metadata["gc.outcome"] // "") | ascii_downcase) as $o | $o == "moot" or $o == "benign";
        { keyless:    [.[] | select((.metadata.escalation_key // "") == "")] | length,
          keyless_mb: [.[] | select((.metadata.escalation_key // "") == "") | select(mb)] | length,
          keyed:      [.[] | select((.metadata.escalation_key // "") != "")] | length,
          keyed_mb:   [.[] | select((.metadata.escalation_key // "") != "") | select(mb)] | length }'
```

Subjects holding more than one open conversation visit:

```bash
gc bd list --status open,in_progress --metadata-field task_kind=visit --limit 0 --json \
  | jq -r '[.[] | select((.metadata.escalation_key // "") == "")]
           | group_by(.metadata["gc.continuation_group"] // "") | map(select(length > 1))
           | .[] | "\(.[0].metadata["gc.continuation_group"]): \(map(.id) | join(" "))"'
```
