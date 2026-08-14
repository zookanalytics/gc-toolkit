---
name: Design — a converse loop that can answer a visit with "no"
description: Why the converse role held a sitting about a benign open PR (tk-mndjz), and the two rules added to fix it — a claim-time premise re-check and a first-class silent exit. Records what was deliberately NOT changed (the detector, the filers), why the silent path stamps no takeaway, and where the boundary between a silent close and the tk-bzm86 sign-off contract is drawn.
---

# Design: a converse loop that can answer a visit with "no"

Design record for `tk-mndjz` (P1, operator-reported 2026-08-13).
Companion to `specs/tk-bzm86/design-doc.md`, which established that a
sitting must end out loud; this records the case that rule does not
reach, and why the two now have to be read together.

## The complaint

> *"PR 55 not being approved is a completely acceptable state that
> should not cause anything else. I am being harassed by something that
> is in a known open state. SOMETHING IS HORRIBLY BROKEN WITH THE
> CONVERSE MODEL IF THIS IS THE ATTENTION BEING SURFACED TO ME."*

A converse sitting was held to ask the operator to decide about an open
PR that was simply awaiting their review. That is their own review queue,
handed back to them as a decision to make.

## What happened (visit su-331y, rig shutupandlisten)

| When | What |
|---|---|
| 2026-08-12T02:49Z | The detector files visit su-331y on workflow root su-ykfw. Premise: *"no `triage.hold` and no `gc.takeaway` on the root"*. True at that moment. |
| 2026-08-12T05:01Z | Converse visit su-h32f dispositions the same root and stamps `triage.hold`, naming the wait (operator review of PR #55). su-331y's premise is now false — two hours after it was filed. |
| 2026-08-13T17:43Z | A converse session claims the stale su-331y ~1.5 days later. It rebuilds state, **sees** the hold in force, **sees** the underlying condition is a benign open PR — and holds a sitting anyway. |

The diagnosis worked. The loop had nowhere to put it.

## What is not at fault

**The detector is correct and was not changed.**
`assets/scripts/detect-stalled-workflows.sh:409` already suppresses any
root or anchor carrying `triage.hold` or `gc.takeaway`, and the rationale
at lines 373–380 records a deliberate choice *not* to treat
`merge_result=pull_request` as terminal — doing so once hid two live
stalls. su-ykfw was already silenced by its hold. Tightening the filing
side to prevent this would trade a false positive for false negatives,
which is the trade that comment exists to refuse.

**The filers in general were not changed.** A premise is true when it is
filed and tested against a world that keeps moving; no filer can know
what will be true when the visit is claimed. Staleness is intrinsic to an
asynchronous signal, so it belongs to the *claimant* to detect. This is
the load-bearing scoping decision of the whole fix: the remedy lives
entirely in `agents/converse/prompt.template.md`.

## The two missing rules

1. **No claim-time premise re-validation.** The old step 3 (*Prime*) says
   rebuild the SUBJECT's state. Nothing told the agent to re-check the
   VISIT's OWN premise. Step 1 had a concurrency guard for sibling holds
   but no staleness guard.
2. **No benign exit.** The loop had exactly one output shape: escalate to
   the human. *Hold* was unconditional — prep, stamp, post, wait. With no
   path for "this turned out to need no human", an agent that correctly
   diagnosed a non-problem still spent the operator's attention reporting
   it. Every claimed visit became a sitting.

Rule 2 is what the operator is naming. Rule 1 is how this instance
reached it.

## What shipped

A new **step 2, Re-check the premise**, and a renumbered loop (now 1–8).

- **Placed before the rename, not just before the prep.** `gc session
  rename` is operator-visible surface. A visit that closes silently must
  not have moved the operator's session title either — otherwise the
  exit is silent in the thread and noisy everywhere else.
- **Two outcomes, kept distinct.** `moot` (the premise no longer holds)
  and `benign` (it holds but needs no human). The bead proposed either;
  both shipped, because collapsing them would make the durable record
  unable to say which of two quite different things happened — a signal
  that expired, versus a signal that was never worth raising.
- **The canonical case is named in the prompt.** An open PR awaiting the
  operator's review. This is the one example that must survive future
  edits, because it is the instance that was actually mishandled.
- **Gated on a *named* state, not a quiet one.** The failure mode of a
  new silent exit is swallowing real signals, which is a worse bug than
  the one being fixed. The prompt requires pointing at the stamp or the
  state that makes the condition benign, and says plainly: *uncertain is
  not benign*. When you cannot tell, you hold the sitting.
- **Non-empty is the test.** An empty `triage.hold` is a *cleared* hold,
  not a hold — the same tri-state the detector reads. The prompt's
  snippet was run against all three shapes (absent metadata, empty
  stamp, non-empty stamp) before shipping.

### The silent path stamps no takeaway — deliberately

Steps 5 and 7 both stamp the subject's takeaway, so symmetry argues for a
third stamp here. It would be wrong. A takeaway is the subject's headline
of what it **NEEDS**: it is what the board renders, and what the stall
detector reads as a named wait. Stamping one for a visit that needs
nobody re-surfaces exactly what this exit suppresses, one surface further
out — and it would additionally let a converse visit silence a *future*
stall report as a side effect of deciding it had nothing to say.

The silent close therefore writes one `--append-notes` line to the
subject and nothing else. That is not a new pattern: the `folded` exit in
step 1 has always worked this way.

Because "add the stamp for consistency" is a plausible future edit that
would keep every pre-existing assertion green, it is pinned by a test
(below) rather than by a comment.

## The boundary with tk-bzm86

The two contracts read as contradictions when met apart:

- tk-bzm86: *never end a sitting without a sign-off.*
- tk-mndjz: *close silently, post nothing.*

The resolution is **whether a framing was ever posted**. The sign-off
exists because an unanswered `Next (yours):` left in a thread that then
vanishes reads as a crash rather than a completion. A visit that closed
before any framing was posted asked the operator nothing, so there is no
question in the thread to abandon and nothing for silence to be mistaken
for. That boundary is written into the sign-off step itself — the place
an editor will be standing when the two rules appear to collide — along
with an explicit instruction not to generalise it back into "every close
ends out loud".

## Test

`assets/scripts/converse-signoff.test.sh` (hermetic; reads the repo, no
gc/city/network) now guards both bugs, deliberately in one file: the fix
for each is the cause of the other if read alone. Added:

- the re-check exists, and its line precedes both the rename and the prep;
- both outcome words are named, the exit posts nothing, and the
  anti-swallow gate (*uncertain is not benign*) survives;
- the silent close is **extracted as a block** and asserted on what it
  does *not* contain — no takeaway — as well as what it must: an
  append-note, a verified `gc.outcome` read-back, and a close of the
  visit only;
- the opening summary and the `Visit` definition carry the rule, since
  page one outranks a rule further down (the same reasoning the existing
  `Hold`-definition assertions rest on);
- the sign-off rule is scoped to a *held* sitting;
- **numbering integrity** — the loop is contiguous 1..N and every
  `step N` cross-reference resolves. Inserting a step renumbers every
  reference after it, and a stale pointer sends the role to the wrong
  step with nothing at runtime to notice.

Each new assertion was negative-controlled by mutating a copy of the
prompt and confirming it goes red. The one that matters most:
a symmetry-tidy that adds a takeaway stamp *with* its own resolver and
guard keeps all 61 other assertions green and is caught by the
no-takeaway assertion alone.

## Central docs corrected

`docs/gascity-human-engagement.md` asserted that *"every deliberate close
ends with a sign-off block"* and, in the definition of a visit, that it
closes *"out loud"*. Both are false as written once a visit can close
silently (and were already slightly overstated by the `folded` path).
Both now carry the boundary. Central docs are authoritative — leaving
either would have made the doc the bug.

## Related

- `su-59z4` — fold rule misfires on standing subjects; filed the same
  turn, not addressed here.
- `su-lst2` — superseded wrong-store duplicate of this bead.
- Instance: visit `su-331y`, subject `su-vehr`, root `su-ykfw` (rig
  shutupandlisten).
