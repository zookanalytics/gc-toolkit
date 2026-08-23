---
name: handoff
description: Use when the operator explicitly asks to handoff, reset, wrap up, recycle a session, get fresh context, or restart a coordination agent (mayor, mechanik, deacon). Do not invoke from internal judgment that a handoff would be useful — propose it in conversation and let the operator decide.
---

# Handoff

> **Operator-initiated only.** Do not invoke this skill without the
> operator asking for it. If you believe a handoff would help, raise
> the suggestion in conversation and let the operator decide. The
> matching engine may surface this skill on near-matches; this
> guardrail is the second line of defense.

## Detect the session shape

This skill has one shape. Confirm you are in it by reading
`$GC_TEMPLATE`:

- **Canonical path** — controller-restartable named sessions: the
  always-on coordination agents in this city (mayor, mechanik, deacon,
  boot, witness). Their `mode = "always"` declaration in `pack.toml`
  lets the controller stop and restart them cleanly when `gc handoff`
  fires. `$GC_TEMPLATE` is the agent's name — `gc-toolkit.mayor`, or
  rig-scoped equivalents for witness/refinery. The transcript is
  replaced; durable state (beads, mail, work) survives.

If `$GC_TEMPLATE` falls outside that shape — a `mode = "on_demand"`
session like refinery, or anything else the operator wants handed off
— **stop and confirm before proceeding.** `gc handoff` will write the
mail but cannot restart the user-attended process, so the next-life
context is delayed until the operator manually restarts it. That
degraded path isn't what "handoff" usually means; surface the
difference and let the operator decide whether to proceed or pick a
different path.

If the operator wants a **no-questions-asked close** of a named
session — no inventory, no carry-forward, just end the
conversation — that is the `bye` shell helper (`! bye`), not this
skill. The handoff skill is for the thoughtful close-out flow that
preserves in-flight discussion.

## What's being preserved

**Conversational state, not work.** Assigned beads, inbox mail,
dispatched polecats, and any durable bead-store record are picked up
automatically on the next-life agent's startup checks (`gc prime`,
boot inventory, etc.). The thing that disappears is the *active
discussion*: what the operator and agent were mid-thread on, what
ideas are open, what direction is being weighed. If it lives only in
the transcript, it dies unless the handoff carries it.

The vehicle is the HANDOFF mail: the controller replaces the transcript
and the next-life agent reads that mail on its first action.

Anything *not* mentioned in the handoff body is intentionally
forgotten.

## When the operator asks for it

The operator triggers this skill — not the agent's own judgment.
Recognize these phrasings as triggers:

**Triggers** (mayor, mechanik, deacon, boot, witness):

- "Handoff" / "let's handoff" / "do a handoff"
- "Fresh context" / "reset context" / "clean slate"
- "Wrap this up and reset" / "wrap up and start fresh"
- "Restart [mayor/mechanik/deacon] with a clean transcript"

Ambiguous cases — the operator says "let's wrap up" with no mention of
context or restart — should be clarified before invoking. Ask: *"Do you
want a handoff (fresh transcript) or just a summary in place?"* (If
they want an unconditional close with nothing carried forward, `bye` is
the right tool, not this skill.)

Don't invoke for: a wedged or hallucinating agent (recommend
`gc session reset <alias>` instead — reset is correct here because
handoff would block on the frozen runtime), or routine context
trimming where continuity matters more than scope reset (recommend
`/compact` instead). Surface those alternatives if the operator's
phrasing suggests one of them is the better fit.

The wedged-agent carve-out is specific to the **operator-initiated
carry-forward sweep** flow this skill governs. Cycle-recycle is a
different flow: it legitimately chains `gc handoff` (state-capture)
followed by `gc session reset` (restart-trigger) for on-demand named
sessions, and that chaining is correct there. See
`docs/cycle-recycle.md`.

(A conversation about one work bead — a converse session holding a
visit — needs no recycle path here: its carry-forward is the subject
bead's record. Write the takeaway and a durable note to the subject
bead, close the visit, and let the session drain; the next visit
reconstitutes the conversation from the record.)

## The carry-forward decision

**Inventory the live conversation, not the work list.** Read back
through the recent transcript and identify threads that the operator
and agent are actively mid-discussion on. Bead IDs and topics show up
in this inventory because they're what's *being talked about* — not
because they're assigned or open in the bead store.

For each thread, decide first whether it is **Resolved** or **In
flight**:

- **Resolved** — the conversation reached a conclusion: a decision was
  made, an action was taken, the operator redirected away, the topic
  was dropped. **Drop it.** Don't mention. The whole point is to
  forget it.

- **In flight** — the conversation is still live: a discussion is
  mid-thread, a direction is being weighed, an idea is being
  considered, the operator is waiting on something from the agent (or
  vice versa). Carry-forward eligible — see disposition below.

  *When uncertain whether a thread is in flight or resolved — an idea
  the operator threw out and may have moved away from, an action you
  think was taken but aren't sure about — **ask the operator**. Don't
  guess. A wrong "drop" loses thread; a wrong "carry" pollutes the
  fresh start.*

**Disposition for in-flight threads.** Every in-flight thread carries
forward into the single HANDOFF mail to self. There is no per-thread
choice; the next-life agent picks up the same conversation, so the
question is only "is it still live?"

**Verify before claiming actions.** If a thread involved "we'll do X
to bead XYZ" or "the agent is going to file Y," check the actual
state before writing it into the handoff body. Use `bd show <id>`,
`gc mail thread <id>`, `git log`, or whatever surface confirms the
claim. **Never assert in the handoff that an action was taken when
you can't verify it.** A handoff that hallucinates completed work is
worse than one that flags the uncertainty explicitly.

If nothing remains after this sweep, the handoff body should be empty
or a single line ("nothing in flight; reset to baseline"). That is the
desired clean reset — don't pad it with history.

## Composing the handoff

Two cases — pick one based on whether the carry-forward sweep turned
up live threads.

**Clean reset (nothing in flight) — exact command:**

```bash
gc handoff -- "clean reset"
```

**With carry-forward (live threads from the inventory) — exact
command:**

```bash
gc handoff -- "context refresh" "$(cat <<'EOF'
<live thread 1>: <where the discussion stands; what's open>
<live thread 2>: <where the discussion stands; what's open>
EOF
)"
```

The `--` terminates flag parsing so the body can start with `-`
(markdown bullets, bead IDs like `- gc-9czy7 (...)`, etc.) without
pflag treating it as a flag bundle.

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

The ask: *"Before I hand off, here's what I see as still in flight:
[list]. Carry all forward, drop any, or add anything I missed?"*

This step is cheap and catches the wrong-call cases for free.

## After the handoff

The next-life agent boots, runs `gc prime` per its boot prompt, reads
the handoff mail as its first action, and picks up. There is no
verification step the handing-off agent can do — once the restart
fires, the old session is gone. Trust the mail.

## Don't pivot mid-skill

If during the **operator-initiated carry-forward sweep** you find
yourself reaching for `/compact`, `gc session reset`, `gc session
kill`, or `bye` instead — stop. Surface to the operator that one of
those might be a better fit and let them redirect. By the time this
skill is firing, the operator has decided on a thoughtful close-out;
pivoting silently to a different tool breaks that intent. `bye` is the
right tool *before* this skill fires when the operator wants the
unconditional close; once inventory is underway, finish the inventory
and use the composed flow.

This is specific to the carry-forward sweep flow, not a blanket
prohibition on `gc session reset` (cycle-recycle, for one, legitimately
chains it after `gc handoff`; see above).
