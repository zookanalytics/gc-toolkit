---
name: handoff
description: Use when the operator explicitly asks to handoff, reset, wrap up, recycle a session, get fresh context, or restart a coordination agent (mechanik, deacon, witness). Do not invoke from internal judgment that a handoff would be useful — propose it in conversation and let the operator decide.
---

# Handoff

> **Operator-initiated only.** Do not invoke this skill without the
> operator asking for it. If you believe a handoff would help, raise the
> suggestion in conversation and let the operator decide.

## Detect the session shape

This skill has one shape. Confirm you are in it by reading `$GC_TEMPLATE`:

- **Canonical path** — controller-restartable named sessions: the
  always-on coordination agents in this city (mechanik, deacon, witness).
  Their `mode = "always"` declaration lets the controller stop and restart
  them cleanly when `gc handoff` fires. The transcript is replaced;
  durable state (beads, mail, work) survives.

If `$GC_TEMPLATE` falls outside that shape — a `mode = "on_demand"`
session, or anything else — **stop and confirm before proceeding.**
`gc handoff` will write the mail but cannot restart the user-attended
process, so the next-life context is delayed until the operator manually
restarts it. Surface the difference and let the operator decide.

If the operator wants a **no-questions-asked close** — no inventory, no
carry-forward — that is the `bye` shell helper (`! bye`), not this skill.

## What's being preserved

**Conversational state, not work.** Assigned beads, inbox mail, dispatched
polecats, and durable bead-store records are picked up automatically by
the next-life agent's startup checks. What disappears is the *active
discussion*: what the operator and agent were mid-thread on. If it lives
only in the transcript, it dies unless the handoff carries it.

The vehicle is the HANDOFF mail: the controller replaces the transcript
and the next-life agent reads that mail on its first action. Anything
*not* mentioned in the handoff body is intentionally forgotten.

## When the operator asks for it

Recognize as triggers: "handoff", "fresh context" / "reset context" /
"clean slate", "wrap this up and reset", "restart [mechanik/deacon] with a
clean transcript". Ambiguous phrasings ("let's wrap up" alone) get
clarified first: *"Do you want a handoff (fresh transcript) or just a
summary in place?"*

Don't invoke for: a wedged or hallucinating agent (recommend
`gc session reset <alias>` — handoff would block on the frozen runtime),
or routine context trimming where continuity matters more than scope
reset (recommend `/compact`).

The wedged-agent carve-out is specific to this operator-initiated
carry-forward flow. Cycle-recycle is a different flow: it legitimately
chains `gc handoff` then `gc session reset` for patrol sessions — see
`docs/cycle-recycle.md`.

(A conversation about one work bead — a converse session holding a visit —
needs no recycle path here: its carry-forward is the subject bead's
record. Write the takeaway and a durable note, close the visit, and let
the session drain; the next visit reconstitutes from the record.)

## The carry-forward decision

**Inventory the live conversation, not the work list.** Read back through
the recent transcript and identify threads the operator and agent are
actively mid-discussion on. For each, decide:

- **Resolved** — a decision was made, an action taken, the topic dropped.
  **Drop it.** The whole point is to forget it.
- **In flight** — a discussion is mid-thread, a direction being weighed,
  someone waiting on the other. Carries forward into the single HANDOFF
  mail — the only question is "is it still live?"

When uncertain, **ask the operator**. Don't guess: a wrong "drop" loses a
thread; a wrong "carry" pollutes the fresh start.

**Verify before claiming actions.** If a thread involved "we'll do X to
bead XYZ", check the actual state (`bd show`, `git log`, mail) before
writing it into the handoff body. Never assert an action was taken when
you can't verify it — a handoff that hallucinates completed work is worse
than one that flags the uncertainty.

If nothing remains, the body is a single line ("nothing in flight; reset
to baseline"). That is the desired clean reset — don't pad it.

## Confirming the list with the operator

Before composing, surface the curated list: *"Before I hand off, here's
what I see as still in flight: [list]. Carry all forward, drop any, or add
anything I missed?"* The operator has context the transcript doesn't show;
this step is cheap and catches the wrong calls for free.

## Composing the handoff

**Clean reset (nothing in flight):**

```bash
gc handoff -- "clean reset"
```

**With carry-forward:**

```bash
gc handoff -- "context refresh" "$(cat <<'EOF'
<live thread 1>: <where the discussion stands; what's open>
<live thread 2>: <where the discussion stands; what's open>
EOF
)"
```

The `--` terminates flag parsing so the body can start with `-` (markdown
bullets, bead IDs) without pflag treating it as a flag bundle.

After running the command, emit this exact line:

> *Handoff committed. Provider restart in progress — the next-life agent
> will pick up from the handoff mail.*

If that line stops being accurate, update it here rather than improvising
per-invocation.

## Body structure

Terse and resumable — each line a future-self could read cold:

```
- Discussing bead <id>: <what's being weighed>; operator considering
  <A vs B>; awaiting their call.
- Active thread on <topic>: agreed on <X>, still open is <Y>; next
  conversational move is <agent or operator>'s.
- Idea floated by operator: <one-liner>; not yet acted on — confirm
  direction on resume.
```

Avoid: narrative recaps (bead notes hold that); work-list dumps (the bead
store holds that); resolved threads (the point is to forget them);
restating the boot prompt (`gc prime` re-injects it); unverified claimed
actions.

## After the handoff

The next-life agent boots, runs `gc prime`, reads the handoff mail first,
and picks up. There is no verification step for the handing-off agent —
once the restart fires, the old session is gone. Trust the mail.

## Don't pivot mid-skill

If mid-sweep you find yourself reaching for `/compact`,
`gc session reset`, `gc session kill`, or `bye` — stop and surface the
alternative to the operator. By the time this skill fires, the operator
chose a thoughtful close-out; pivoting silently breaks that intent. (Not
a blanket prohibition on `gc session reset` — cycle-recycle legitimately
chains it after `gc handoff`.)
