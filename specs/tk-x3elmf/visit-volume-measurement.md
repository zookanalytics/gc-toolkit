---
name: What witness visit volume is actually made of (2026-09-02)
description: The measurement tk-x3elmf asked for before designing — what fraction of witness-filed visits close moot or benign, how that compares with every other filer, and the two mechanisms the numbers point at. Read it to check the thresholds the fix ships with, or to re-run the counts before changing them.
---

# What witness visit volume is actually made of

**Measured 2026-09-02 against the live `gc-toolkit` store.** Every number
carries the command that produces it. All of them read a store that keeps
growing, so re-run before acting on any of them.

The bead was filed on an operator report that the witness's "directions are
wrong and send way too many here". Both halves hold: the directions are wrong
in a specific, fixable way, and most of what they file is waste. What does not
hold is the bead's own framing that the witness is the dominant source of
converse sittings. It is neither the largest filer nor the one with the worst
hit rate, and that changes where the fix has to go.

## The witness is not an outlier by rate

```bash
gc bd list --status closed --json > /tmp/closed.json   # the rig preamble is on stderr
jq -r '
def bucket: if startswith("witness-") then "witness"
  elif startswith("doctor-") then "deacon/doctor"
  elif startswith("polecat-") then "polecat"
  elif startswith("refinery-") or startswith("pr-") then "refinery"
  else "other" end;
[.[]? | select((.metadata.task_kind // "") == "visit")
      | select((.metadata.escalation_key // "") != "")
      | {b: (.metadata.escalation_key | bucket),
         wasted: (((.metadata["gc.outcome"] // "") | . == "moot" or . == "benign"))}]
| group_by(.b) | map({bucket: .[0].b, total: length, wasted: (map(select(.wasted)) | length)})
| .[] | "\(.bucket) \(.wasted)/\(.total)"' /tmp/closed.json
```

| filer | closed visits | closed moot or benign |
|---|---|---|
| refinery | 33 | 26 (78%) |
| polecat | 13 | 9 (69%) |
| deacon/doctor | 72 | 45 (62%) |
| witness | 22 | 12 (54%) |
| other keyed | 42 | 18 (42%) |

`moot` and `benign` are the converse role's two "no human was needed" verdicts
(`agents/converse/prompt.template.md`): moot means the premise no longer holds,
benign means it holds but needs nobody.

The witness has the lowest moot rate of the four named patrols, and it is not
the largest source either — the deacon's doctor sweep files three times as
many. So "the witness files too many" is not a claim about its judgment being
worse than its peers, and a threshold tuned only on the witness would leave
most of the volume untouched.

What is true is that the witness's own recent volume is mostly waste:

```bash
jq '[.[]? | select((.metadata.task_kind // "") == "visit")
          | select((.metadata.escalation_key // "") | startswith("witness-"))
          | select(.created_at >= "2026-09-01")]
    | {total: length,
       wasted: ([.[] | select((.metadata["gc.outcome"] // "") as $o | $o == "moot" or $o == "benign")] | length),
       crash_loop: ([.[] | select(.metadata.escalation_key == "witness-crash-loop")] | length)}' /tmp/closed.json
```

18 visits over 2026-09-01..02, 10 of them moot or benign. 12 of the 18 carry
one key, `witness-crash-loop`, and 6 of those 12 closed moot.

## Mechanism 1: the crash-loop detector is a mark, not a rate

`formulas/mol-witness-patrol.toml` directed the witness to stamp
`recovered=true` on every recovery and to read a repeat recovery of a bead
already carrying it as a crash loop. Nothing clears the flag, and it records
neither a time nor a count.

```bash
for st in open in_progress closed; do
  gc bd list --status "$st" --json | sed '/^gc bd:/d' \
  | jq -r '.[]? | select((.metadata.recovered // "") != "") | .id'
done | sort -u | wc -l
```

109 beads carry it, the oldest created 2026-05-07. The crash-loop population is
therefore every bead the rig has ever recovered, and it only grows. Two
recoveries three days apart escalate identically to two five minutes apart.

The visit bodies say so in the witness's own words. `tk-frelxn` and `tk-am9afo`
both read "recovered a second time (owning session ..., closed/drained)", and
`tk-fz1g7x` asks a human to "check whether polecat-2 pool sessions are
crash-looping specifically on this bead's rework, not just recycling normally".
That last question is the one the detector was supposed to answer before
spending the sitting. A pool session that finishes and drains closes normally,
which leaves its bead owned by a closed session — the same shape a crash
leaves. All three closed moot.

## Mechanism 2: a verdict suppresses nothing

`assets/scripts/escalate.sh` dedups on `--status=open,in_progress`, so a closed
visit contributes no suppression at all. `gc.outcome` is stamped by converse
and, before this bead, read by nothing in the filing path.

```bash
jq -r '
[.[]? | select((.metadata.task_kind // "") == "visit")
      | select((.metadata.escalation_key // "") != "")
      | {k: .metadata.escalation_key, s: (.metadata["gc.continuation_group"] // "-"),
         c: .created_at, cl: (.closed_at // ""), o: (.metadata["gc.outcome"] // "")}]
| group_by(.k + " " + .s) | map(sort_by(.c))
| map(. as $g | [range(1; ($g | length)) | {prev: $g[. - 1], cur: $g[.]}]) | add // []
| map(select(.prev.cl != "" and .cur.c > .prev.cl))
| map({key: .cur.k, prev_outcome: .prev.o,
       gap_h: ((((.cur.c | fromdateiso8601) - (.prev.cl | fromdateiso8601)) / 360 | round) / 10)})
| sort_by(.gap_h) | .[]
| "\(.gap_h)h \(.prev_outcome) \(.key)"' /tmp/closed.json
```

44 visits were filed after a prior visit for the same key and subject had
already closed. 29 of those followed a `moot` or `benign` verdict: a human
looked, said no action was needed, and the same detector raised the same
situation again.

The gaps between the verdict and the re-file are strongly bimodal.

| gap from prior close | count | who |
|---|---|---|
| under 5 hours | 21 | all `doctor-*` on `tk-mcrtpz` |
| ~21.6 hours | 2 | `witness-crash-loop` |
| 74 hours and over | 6 | mixed |

There is nothing at all between 21.7 and 74.3 hours.

## What the numbers argue for

Two changes, both at filing time, because a premise re-checked at claim time
has already cost the sitting the operator sees.

**A 24-hour verdict window in `escalate.sh`.** A situation a sitting closed
moot or benign is not re-filed for `GC_ESCALATE_VERDICT_WINDOW` seconds
(default 86400). 24 hours sits inside the 52-hour empty band above, so it
suppresses 23 of the 29 observed re-files and lets every gap of 74 hours or
more through. The newest closed visit for the situation decides, taken by
timestamp across the whole closed set rather than a page of it — the busiest
(key, subject) already carries 19 closed visits, enough that a truncated
listing could return an older verdict as the latest. Only when that newest
visit is moot or benign does the window suppress; every other outcome means
the sitting acted, so the next occurrence stands on different ground and an
older moot behind a newer ruling cannot mute it. A situation that has
genuinely changed takes a new `--key`, which is already the rule at
the top of that script, so the window cannot trap a new signal behind an old
answer. Suppressed repeats are tallied on the visit that earned the verdict
(`escalation.recurrences`) rather than dropped, which is both the audit trail
and the evidence for moving the window later.

The window is shared by every filer, not just the witness, because the defect
is in the shared writer. On these numbers the deacon's doctor sweep is its
largest beneficiary.

**A 6-hour recurrence window for `witness-crash-loop`.** The witness now
records `recovered_at` and `recovered_count` alongside `recovered=true`, and
escalates only when the previous recovery falls inside `CRASH_LOOP_WINDOW`
(default 21600). This window is not measured, because the instrument that would
measure it is the thing being added: no recovery before this change recorded
when it happened. It is set from the shape of the work instead — the patrol
cycles every 10 minutes and a polecat's claim-to-submit cycle runs in hours, so
a bead re-orphaned inside 6 hours is coming back faster than one work cycle.
`recovered_count` is what makes a later, measured choice possible.

A bead carrying only the legacy flag has no recurrence evidence at all. It
stamps a first timestamp and escalates nothing, which drains the 109 in one
pass instead of escalating all of them.

A bead recovered many times with every gap outside the window is a bead that
keeps coming back rather than one that is looping. That is a different signal
and it is deliberately not this key; `recovered_count` records it so the case
can be built on evidence.

## What this does not address

Two findings are carved out rather than fixed here, each with its own bead.

**tk-2jdh9l** — 100 closed visits carry no `escalation_key` at all. They were
filed by paths that never call `escalate.sh`, so neither the open-visit dedup
nor the verdict window reaches them, and every rate above is blind to them.

**tk-ge15u5** — whether a bead whose work already reached an open PR should be
recovered as an orphan at all. That is a question about recovery, not about
filing. `tk-n85511` is the live instance: a bead on an approved, clean PR was
recovered and escalated as a crash loop, and the sitting closed it moot.
