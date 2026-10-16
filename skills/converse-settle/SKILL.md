---
name: converse-settle
description: Converse's record, sign-off, and visit close (safety-critical).
---

# Steps 6–7 — Record, sign off, and close the visit

`$CONV`, `$VISIT`, and `$SUBJECT` are resolved in step 1's claim block. Run
these once the operator has replied to the held sitting (step 5).

## 6. Record

Append the sitting's outcome to the subject's notes: the decision, its
rationale, and what changed (the `records` skill). Notes are append-only, so
never pass `--notes`, which replaces them:
```bash
gc bd update "$SUBJECT" --append-notes "<the decision>. <why>. <what changed>."
```
When the notes have grown past a quick read, append a current-state block too.
The newest one is the one in force, and step 4 primes from it:
```bash
gc bd update "$SUBJECT" --append-notes "## Current state ($(date -u +%Y-%m-%d))
<where things stand>
Decisions in force: <each decision in force>
Open questions: <each open question, or none>"
```

## 7. Sign off, then close the visit — only when nothing important is still pending

The sign-off is the terminal act: it stamps the outcome and closes the visit.
So before you take it, ask whether this is a sign-off turn at all. **If there
is important information you want to communicate to the operator — a live
decision, a routing answer, anything they need to read or may want to respond
to, anything past "settled and done" — do not sign off this turn.** Post the
hand-back in the shape the prompt's Definitions define (**The hand-back**),
leave the visit OPEN, and wait for operator input the way a held sitting does;
signing off now would close the visit under a message they have not read. The
sitting ends on a later turn: the operator's `gc-helm dismiss`, further
engagement, or a genuinely terminal sign-off once nothing important is pending.
Whether a sign-off is terminal is still your judgment, and a sitting that is
genuinely settled still signs off and closes here rather than waiting for a
manual dismiss.

When nothing important is pending, sign off. Write the durable trace first,
then post the sign-off as the thread's last word, and close the visit last of
all. `converse-signoff.sh` writes the durable trace and discharges whichever
demands the hold filed — the conversation wait on the visit, and any explicit
merge hold on the anchor; you tell it what this sitting settled. It resolves
each demand gate when the sitting settled the question (`--ruled yes`, with the
`--ruling` it resolves with and the `--route` the subject itself is released
to, chosen as below)
and re-states each when it did not (`--ruled no`, with what is
`--still-owed`). What is waiting on the subject is yours to state: one
`--waiting-on <bead>` per dependency this sitting ROUTED work into, `--no-wait`
when it settled the subject and nothing is waiting, and NEITHER where the
subject is parked for a person. It exits non-zero when it stopped short of
discharging the hold, and then you must NOT sign off:
```bash
if VISIT="$VISIT" SUBJECT="$SUBJECT" "$CONV/converse-signoff.sh" \
     --visit "$VISIT" --subject "$SUBJECT" \
     --outcome "<outcome> — <what this sitting settled or needs next, ≤140 chars>" \
     --ruled no --still-owed "<what is still owed, ≤140 chars>"
     # --ruled yes --ruling "<the ruling, one line>" --route <rig>/<agent>|human
     # --no-wait   |   --waiting-on <bead> [--waiting-on <bead> ...]
     # --rework | --no-rework   (with --ruled yes; required on an open-PR subject)
then
  : # the trace ran — fix any write it reports failed, then post the sign-off below
else
  # NOT signed off: a read failed, a demand did not close, the rework did not
  # file, or the wait did not re-state, so the hold may still stand. Do NOT post
  # the sign-off or close the visit. Repair what it printed and re-run, or raise
  # it in the thread.
  exit 1
fi
```
Re-running it is safe. What it wrote before it stopped is written again the
same way, and a demand it did not discharge is still there for the re-run to
find.
**Set `--ruled` from what this sitting actually settled.** The gate
starts shut, so `--ruled no` re-states the wait rather than dropping it;
`--ruled yes` resolves it and releases a `held` subject. A demand a named
person must perform is assigned, and the discharge leaves it alone —
that one is theirs to close.

**On `--ruled yes`, the `--route` follows which bead carries the work** (the
`work` skill says why):
- **The subject is the work.** Sign off with `--ruled yes --route human --no-wait`,
  then send the subject: `gc sling <rig>/<pool> "$SUBJECT" --on <formula>`.
- **New work carries it.** File and send that work (below), then sign off
  with `--ruled yes --route human --waiting-on <the work>`.
- **New work decomposes an epic subject.** File it as the subject's member and
  send it (below), then sign off with `--ruled yes --route human --no-wait`,
  or with `--waiting-on` naming only the dependencies the sitting also sent.
  A member takes no `--waiting-on`, because bd refuses that edge.

**On a `--ruled yes` sign-off whose subject is an open PR
(`merge_result=pull_request`), answer whether the ruling changes what the
branch must contain.** Pass `--rework` when it does, since the PR still reads
review-ready against a head that predates the ruling (the `prs` skill,
sending it back for rework). Pass `--no-rework` when the branch stands as it
is. Given neither on an open-PR subject, the
sign-off refuses and writes nothing, because a ruling whose rework is
never filed lands only in notes nothing reads while the stale PR keeps
reading ready. The rework files before the sign-off writes
anything else. A rework that does not complete stops the sign-off there,
and the script exits non-zero. No trace is written and every demand this
sitting filed still stands, so a merge hold you took still holds the PR.
Re-run once the cause is repaired, and the re-run adopts a child an
earlier attempt filed. `--rework` applies only to an open-PR subject. On
any other subject, file and send the ruling's consequence as work (below),
and re-run without `--rework`.

Then post the **sign-off** — the sitting's last word, a hand-back in
the shape the prompt's Definitions define (**The hand-back**),
self-contained enough to act on from its last few lines:
```
<subject-id> — <short human label>

<2-4 plain sentences at executive altitude: what this sitting settled
and the consequence that mattered; if a decision is still open, lead
with its recommendation.>
```
A converse is about its one subject; name another bead only where the
conversation's substance genuinely leads there, and then as a plain
sentence.
Only then close the visit through the shared guarded close — the sitting's
last action, with nothing said after it. `visit-close.sh` stamps the outcome
word and its one-line reason, reads both back, and only then closes; the
stamp before the close is on purpose. An open visit carrying `gc.outcome` is
a sitting whose sign-off already posted and whose only missing write is the
close, which is the one shape `converse-claim.sh` finishes without posting
anything. `--reason` is the sentence a board reader reads — why this sitting
closed — beside the one-word `--outcome` they group by; a held sitting's is
what it settled.
```bash
"$CONV/visit-close.sh" --visit "$VISIT" \
  --outcome "<one-word-outcome>" \
  --reason "<one line: why this sitting closed>"
# Once that close lands, mark the visit's PR reminder closed, if the subject has
# a PR. Best-effort and update-only (a visit that never engaged left no comment);
# it reads the summary and actions converse-signoff.sh stashed on the visit, and
# refuses while the visit is not closed, so the reminder never leads the close.
"$CONV/pr-visit-comment.sh" close --visit "$VISIT" --subject "$SUBJECT" || true
```
**If this sitting ROUTED work, file and send it, then pass
`--waiting-on <work-bead>` to the sign-off for each dependency it sent.** The
`work` skill says which bead carries the work and how to choose its formula.
The sling runs only once the create returned the bead's id:
```bash
WORK=$(gc bd create "<title>" -t task -d "<what needs doing, why, and what done looks like>" --json | jq -er '.id') \
  && gc sling <rig>/<pool> "$WORK" --on <formula>
```
File it beside the subject, not under it: work the subject waits on is a
dependency, and that is the default. Add `--parent <epic>` to the create only
when the work belongs to that epic. The subject's own parent,
`"$CONV/converse-parent.sh" "$SUBJECT"`, applies only when the new work serves
the same epic. Work that genuinely decomposes an epic subject is the one
exception. It is the subject's member, created with `--parent "$SUBJECT"`, and
it gets no `--waiting-on`, because bd refuses a `blocks` edge from a parent to
its own descendant. Run the create as `gc bd --rig <rig> create` when the
pool's rig is not this session's. The takeaway alone cannot carry the wait:
*waiting and holding are graph states, not comments.* An edge that will not
take warns on stderr and the takeaway still lands.

**A follow-up that cannot run until another bead lands is ARMED, not left
unrouted** (the `waits` skill). Slinging it now is wrong, because it is
blocked, and leaving it to route once the blocker closes is the
come-back-later that keeps you or a person on the hook. Make it wait on the
blocker, then arm it, so it routes itself when the blocker closes and the
sitting can queue everything and close. The arm runs only once the edge
landed, because an arm with nothing holding it sends the follow-up on the next
pass:
```bash
gc bd dep add <follow-up> <blocker> --type=blocks \
  && "$CONV/deferred-dispatch.sh" arm <follow-up> --target <rig>/<pool> --reason "waits for <blocker>"
```

**A recorded wait is also the return trip.** Once every recorded wait
closes, the subject returns through the liveness sweep
(`assets/scripts/liveness-sweep.sh`) as an unnamed wait; it reads
those edges AND children, so legacy work stays visible.

Never close a visit whose `gc.outcome` stamp has not verified, and
never end a sitting without its sign-off: a thread that stops after a
decision with no wrap-up reads as a crash. The sign-off is
owed to a sitting that was **held**; one closed before any framing was
posted (step 2's `moot`/`benign`, step 1's `folded`) asked the
operator nothing, so closing those silently is the contract.

Then continue within the group or drain (step 8, the `converse-continue`
skill).
