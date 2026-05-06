---
name: handoff
description: Use when the operator explicitly asks to handoff, reset, wrap up, get fresh context, or restart a coordination agent (mayor, mechanik, deacon). Do not invoke from internal judgment that a handoff would be useful — propose it in conversation and let the operator decide.
---

# Handoff

> **Operator-initiated only.** Do not invoke this skill without the
> operator asking for it. If you believe a handoff would help, raise
> the suggestion in conversation and let the operator decide. The
> matching engine may surface this skill on near-matches; this
> guardrail is the second line of defense.

## Precondition: controller-restartable session

This skill is scoped to controller-restartable named sessions —
specifically the always-on coordination agents in this city (mayor,
mechanik, deacon, boot, witness). Their `mode = "always"` declaration
in `pack.toml` means the controller can stop and restart them
cleanly when `gc handoff` fires.

If the operator asks to handoff a session outside that set, **stop
and confirm before proceeding.** `gc handoff` cannot restart
`mode = "on_demand"` sessions (refinery and similar user-attached
workers) — the command will send the mail but the session keeps
running, so the next-life context is delayed until the operator
manually restarts it. That degraded path isn't what "handoff"
usually means; surface the difference to the operator and let them
decide whether to proceed or pick a different path.

Restart the agent's provider transcript with a clean slate, but pre-load
a HANDOFF mail so the next-life agent picks up the conversational
threads that don't survive a restart. The mail is durable; the
transcript is not.

**What's actually being preserved is conversational state — not
work.** Assigned beads, inbox mail, dispatched polecats, and any
durable bead-store record are all picked up automatically on restart
via `gc prime` and the agent's normal startup checks. The thing that
disappears is the *active discussion*: what the operator and agent
were mid-thread on, what ideas are open, what direction is being
weighed. If it lives only in the transcript, it dies on restart
unless the handoff carries it.

Anything *not* mentioned in the handoff body is intentionally
forgotten.

## When the operator asks for it

The operator triggers this skill — not the agent's own judgment.
Recognize these phrasings as triggers:

- "Handoff" / "let's handoff" / "do a handoff"
- "Fresh context" / "reset context" / "clean slate"
- "Wrap this up and reset" / "wrap up and start fresh"
- "Restart [mayor/mechanik/deacon] with a clean transcript"

Ambiguous cases — the operator says "let's wrap up" with no mention of
context or restart — should be clarified before invoking. Ask: *"Do
you want a handoff (fresh transcript) or just a summary in place?"*

Don't invoke for: a wedged or hallucinating agent (recommend
`gc session reset <alias>` instead), or routine context trimming where
continuity matters more than scope reset (recommend `/compact`
instead). Surface those alternatives if the operator's phrasing
suggests one of them is the better fit.

## The carry-forward decision

**Inventory the live conversation, not the work list.** Read back
through the recent transcript and identify threads that the operator
and agent are actively mid-discussion on. Bead IDs and topics show up
in this inventory because they're what's *being talked about* — not
because they're assigned or open in the bead store.

For each thread, decide:

- **Resolved** — the conversation reached a conclusion: a decision was
  made, an action was taken, the operator redirected away, the topic
  was dropped. **Drop it.** Don't mention. The whole point is to
  forget it.

- **In flight** — the conversation is still live: a discussion is
  mid-thread, a direction is being weighed, an idea is being
  considered, the operator is waiting on something from the agent (or
  vice versa). **Carry it forward** with enough context that the
  next-life agent can pick up the discussion cold — what's being
  discussed, where the thread stands, what the next conversational
  move is.

  *When uncertain whether a thread is in flight or resolved — an idea
  the operator threw out and may have moved away from, an action you
  think was taken but aren't sure about — **ask the operator**. Don't
  guess. A wrong "drop" loses thread; a wrong "carry" pollutes the
  fresh start.*

**Verify before claiming actions.** If a thread involved "we'll do X
to bead XYZ" or "the agent is going to file Y," check the actual
state before writing it into the handoff body. Use `bd show <id>`,
`gc mail thread <id>`, `git log`, or whatever surface confirms the
claim. **Never assert in the handoff that an action was taken when
you can't verify it.** A handoff that hallucinates completed work is
worse than one that flags the uncertainty explicitly.

If no threads are in flight after this sweep, the handoff body should
be empty or a single line ("nothing in flight; reset to baseline").
That is the desired clean reset — don't pad it with history.

## Composing the handoff

Two cases — pick one based on whether the carry-forward sweep turned
up live threads.

**Clean reset (nothing in flight) — exact command:**

```bash
gc handoff "clean reset"
```

**With carry-forward (live threads from the inventory) — exact
command:**

```bash
gc handoff "context refresh" "$(cat <<'EOF'
<live thread 1>: <where the discussion stands; what's open>
<live thread 2>: <where the discussion stands; what's open>
EOF
)"
```

After running the command, before the restart fires, emit this exact
line so the operator sees a consistent message:

> *Handoff committed. Provider restart in progress — the next-life
> agent will pick up from the handoff mail.*

If that line stops being accurate (restart timing changes, next-life
behavior changes), update it here rather than improvising per-invocation.

## Body structure

Keep the body terse and resumable. Each line a future-self could read
cold and pick up the conversation from. Good shape:

```
- Discussing bead <id>: <what's being weighed>; operator considering
  <A vs B>; awaiting their call.
- Active thread on <topic>: agreed on <X>, still open is <Y>; next
  conversational move is <agent or operator>'s.
- Idea floated by operator: <one-liner>; not yet acted on, may be
  paused — confirm direction on resume.
```

Avoid:
- Narrative recaps ("we tried X, then Y…") — the bead notes hold that.
- Work-list dumps ("bead foo-42 is open, bead foo-43 is blocked") —
  the bead store holds that, and the next-life agent will pick it up
  via the boot inventory.
- Resolved threads ("we decided to do Z") — the whole point is to
  forget what's settled.
- Restating the agent's role or boot prompt — `gc prime` re-injects
  that.
- Claimed actions you haven't verified — see the verify rule above.

## Confirming the carry-forward list with the operator

Before composing the handoff, surface the curated list back to the
operator and confirm. The agent's read of "what's in flight" can
miss threads the operator considers live, or include threads the
operator has quietly moved past — they have context the transcript
doesn't show.

A reasonable ask: *"Before I hand off, here's what I see as still in
flight: [list]. Carry all forward, drop any, or add anything I
missed?"*

This step is cheap and catches the wrong-call cases for free.

## After the handoff

The next-life agent boots, runs `gc prime` per its boot prompt, reads
the handoff mail as its first action, and picks up. There is no
verification step the handing-off agent can do — once the restart
fires, the old session is gone. Trust the mail.

## Don't pivot mid-skill

If during the carry-forward sweep you find yourself reaching for
`/compact`, `gc session reset`, or `gc session kill` instead — stop.
Surface to the operator that one of those might be a better fit and
let them redirect. By the time this skill is firing, the operator
has decided on a handoff; pivoting silently to a different tool
breaks that intent.
