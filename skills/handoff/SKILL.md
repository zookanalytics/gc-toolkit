---
name: handoff
description: Use when the operator explicitly asks to handoff, reset, wrap up, recycle a session, hand a thread back to its canonical, get fresh context, or restart a coordination agent (mayor, mechanik, deacon) or a bead-host (the resident conversation for one work bead). Do not invoke from internal judgment that a handoff would be useful — propose it in conversation and let the operator decide.
---

# Handoff

> **Operator-initiated only.** Do not invoke this skill without the
> operator asking for it. If you believe a handoff would help, raise
> the suggestion in conversation and let the operator decide. The
> matching engine may surface this skill on near-matches; this
> guardrail is the second line of defense.

## Detect the session shape

This skill has three shapes. Pick one by reading `$GC_TEMPLATE`, checking
in order (most specific first):

- **Bead-host self-recycle path** — the resident conversation for one
  work bead: the `wake_mode = resume` bead-host bound to one bead (its
  `$GC_ALIAS` carries that bead id behind a rig prefix —
  `gc-toolkit.tk-6d0vb` for bead `tk-6d0vb`). `$GC_TEMPLATE`'s agent-name
  component is `bead-host` (e.g.
  `gc-toolkit.bead-host`). This is a **same-bead** recycle — the host
  restarts itself on the same bead with a fresh transcript, and the
  **bead** (its notes + takeaway) is the carry-forward: no mail, no
  cross-agent hand-up. Handle it entirely in **Bead-host self-recycle**
  below; the inventory / disposition / mail machinery the two cross-agent
  paths use does not apply.
- **Canonical path** — controller-restartable named sessions: the
  always-on coordination agents in this city (mayor, mechanik, deacon,
  boot, witness). Their `mode = "always"` declaration in `pack.toml`
  lets the controller stop and restart them cleanly when `gc handoff`
  fires. `$GC_TEMPLATE` does **not** end in `-thread` (it's the
  agent's name — `gc-toolkit.mayor`, or rig-scoped equivalents for
  witness/refinery). The transcript is replaced; durable state (beads,
  mail, work) survives.
- **Thread hand-up path** — operator-spawned thread sessions:
  `mayor-thread`, `mechanik-thread`, and any future `<role>-thread`
  variant. `$GC_TEMPLATE` ends in `-thread` (e.g.
  `gc-toolkit.mayor-thread`). Threads aren't controller-restartable —
  the operator started them and the operator ends them. There is no
  restart; any live discussion is handed *up* to the canonical sibling
  (`gc-toolkit.<role>`, derived from the template) and the thread
  session is closed.

If `$GC_TEMPLATE` falls outside all three shapes — an `mode = "on_demand"`
session like refinery, or anything else the operator wants handed off
— **stop and confirm before proceeding.** `gc handoff` will write the
mail but cannot restart the user-attended process, so the next-life
context is delayed until the operator manually restarts it. That
degraded path isn't what "handoff" usually means; surface the
difference and let the operator decide whether to proceed or pick a
different path.

If the operator wants a **no-questions-asked close** of a thread or
named session — no inventory, no carry-forward, just end the
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

The vehicle follows the handoff's **topology** — state travels by mail
only when it must cross agents; a same-bead recycle keeps it in the bead:

- **Bead-host self-recycle path** — *no mail.* The host restarts on its
  own bead, so the **bead itself** (notes + takeaway, refreshed before the
  reset) is the carry-forward and the source of truth. A HANDOFF mail
  would only duplicate what the bead already holds — and the bead, not a
  copy, is what the respawned host reads back.
- **Canonical path** — the controller replaces the transcript and the
  next-life agent reads the durable HANDOFF mail on its first action.
- **Thread hand-up path** — this thread's transcript ends; the canonical
  reads the HANDOFF mail on its next mail-check hook (which fires on
  the next prompt the operator sends to the canonical).

Where state *does* cross agents, prefer a thin "fresh context is in
bead X" pointer over a copied dump when the bead can hold the body.
Anything *not* carried — left out of the handoff body, or (for a
bead-host) not flushed to the bead — is intentionally forgotten.

## When the operator asks for it

The operator triggers this skill — not the agent's own judgment.
Recognize these phrasings as triggers:

**Bead-host self-recycle triggers** (current session is a bead-host —
`$GC_ALIAS` carries its bead id behind a rig prefix):

- "Recycle" / "recycle this conversation" / "recycle the context"
- "Reset context" / "fresh context" / "clean slate on this bead"
- "Restart this conversation with a clean window"

**Canonical path triggers** (mayor, mechanik, deacon, boot, witness):

- "Handoff" / "let's handoff" / "do a handoff"
- "Fresh context" / "reset context" / "clean slate"
- "Wrap this up and reset" / "wrap up and start fresh"
- "Restart [mayor/mechanik/deacon] with a clean transcript"

**Thread hand-up path triggers** (current session is a `*-thread`):

- "Hand this back to [mayor/mechanik]" / "Hand up to the canonical"
- "We're done with this thread" / "Close out this thread"
- "Hand off these threads and close" / "Carry forward to canonical
  and end here"

Ambiguous cases — the operator says "let's wrap up" with no mention of
context, restart, or canonical — should be clarified before invoking.
Ask:

- On canonical: *"Do you want a handoff (fresh transcript) or just a
  summary in place?"*
- On a thread: *"Do you want to hand items up to the canonical
  [mayor/mechanik/deacon] before closing this thread, or close
  with nothing carried forward?"* (If they want the unconditional
  close, `bye` is the right tool, not this skill.)

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
`template-fragments/cycle-recycle.template.md`.

## Bead-host self-recycle

A bead-host hosts **one** bead, and that bead — not a mail, not the live
transcript — is its durable memory. Recycling is therefore *flush to the
bead, then restart fresh on the same bead*. Run it **only when the
operator asks** (triggers above); never auto-fire.

**1. Flush warm state to the bead.** The bead's notes + takeaway are what
the fresh session reads back, so refresh both — nothing in flight should
survive only in the transcript. A bead-host's `$GC_ALIAS` is prefixed
(e.g. `gc-toolkit.tk-6d0vb`), **not** the raw bead id, so derive the bead
from the session bead first and use `$BEAD` for every `gc bd` / takeaway
call:

```bash
BEAD=$(gc bd show "$GC_SESSION_ID" --json | jq -r '.[0].metadata.hosts_bead')
```

- **Takeaway** — re-stamp this bead's board headline (your usual per-turn
  takeaway call, targeting `$BEAD`) so it names exactly where this stands.
- **Note** — distill the in-flight reasoning a cold resume needs:

  ```bash
  gc bd update "$BEAD" --notes "$(cat <<'EOF'
  <what's being weighed, what's open, the next move — terse and resumable,
  the same shape as a handoff body but written into the bead>
  EOF
  )"
  ```

**2. Restart fresh on the same bead.**

```bash
gc session reset "$GC_SESSION_ID"  # reset the session; same bead stays attached (no close)
```

Use `gc session reset`, **not** `gc handoff`: the bead already holds the
carry-forward from step 1, so a HANDOFF mail would only duplicate it.
(That is the reason — *avoid needless mail* — not a claim that `gc
handoff` can't restart a bead-host. It can.)

**3. Rehydrate is automatic.** The respawned host re-primes (`gc prime`)
and re-reads the bead through its **"On Resume" card**, picking up from
the refreshed notes + takeaway. Only live conversational continuity drops
— which is the whole point of a recycle.

**Boundaries.** Operator-invoked only; never self-measure context to
decide when to fire — gascity owns that signal. The automatic net is
unchanged and separate: Claude Code's PreCompact hook still runs `gc
handoff --auto` at the model's compaction edge if context fills while the
operator is away. If the operator wants to keep the live transcript
rather than reset it, `/compact` is the lighter in-place alternative —
surface that instead.

## The carry-forward decision

This step is shared by the two **cross-agent** paths (canonical and thread
hand-up); a bead-host self-recycle skips it — its carry-forward is the
bead, handled above. Inventory first, then apply the path-specific
disposition rules below.

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

**Path-specific disposition for in-flight threads.**

- **Canonical path** — every in-flight thread carries forward into the
  single HANDOFF mail to self. There is no per-thread choice; the
  next-life agent picks up the same conversation, so the question is
  only "is it still live?"

- **Thread hand-up path** — per-thread disposition. For each in-flight
  thread the operator picks one of:
  - **`canonical`** — relevant to the canonical's ongoing work;
    include in the hand-up mail to `gc-toolkit.<role>`.
  - **`drop`** — live in this thread's transcript but not worth
    carrying up; the canonical doesn't need to pick it up.
  - **`fresh-window`** *(deferred — separate bead)* — same role,
    fresh transcript, this topic carried. Not yet implemented; if the
    operator asks for it, surface that it's a future shape and
    suggest either canonical or drop for now.

**Verify before claiming actions.** If a thread involved "we'll do X
to bead XYZ" or "the agent is going to file Y," check the actual
state before writing it into the handoff body. Use `bd show <id>`,
`gc mail thread <id>`, `git log`, or whatever surface confirms the
claim. **Never assert in the handoff that an action was taken when
you can't verify it.** A handoff that hallucinates completed work is
worse than one that flags the uncertainty explicitly.

If nothing remains after this sweep:

- **Canonical path** — the handoff body should be empty or a single
  line ("nothing in flight; reset to baseline"). That is the desired
  clean reset — don't pad it with history.
- **Thread hand-up path** — no canonical-flagged items means no mail.
  Skip composition entirely and go straight to `gc session close`.

## Composing the handoff

### Canonical path

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

### Thread hand-up path

The canonical address is the thread template with `-thread` stripped.
Derive it via shell parameter expansion so the command works for any
`<role>-thread`:

```bash
canonical="${GC_TEMPLATE%-thread}"   # gc-toolkit.mayor-thread -> gc-toolkit.mayor
```

Two cases — pick one based on whether any in-flight items were flagged
`canonical` in the disposition step.

**Nothing flagged canonical (all dropped or no items in flight) — skip
the mail; close this thread:**

```bash
gc session close "$GC_ALIAS"
```

**At least one item flagged canonical — mail the canonical, then
close this thread:**

```bash
gc mail send "$canonical" \
  -s "HANDOFF (from thread $GC_ALIAS): <one-line topic>" \
  -m "$(cat <<'EOF'
<flagged item 1>: <where the discussion stands; what's open>
<flagged item 2>: <where the discussion stands; what's open>
EOF
)"
gc session close "$GC_ALIAS"
```

`<one-line topic>` is the thread's focus area — a few words the
canonical can read in its inbox listing and know what conversation is
being handed up (e.g. "handoff skill thread-aware scope", not
"various items").

After running the command(s), before the close fires, emit this exact
line so the operator sees a consistent message:

> *Hand-up committed. Closing this thread — the canonical
> [mayor/mechanik/...] will pick up the carry-forward on its next
> prompt-submit hook.*

(Substitute the actual canonical role.) If no mail was sent, swap
"Hand-up committed" for "Nothing to carry forward." Same shape, same
intent — give the operator one consistent end-of-skill line.

If that line stops being accurate (hook timing changes, close
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

The ask is path-shaped:

- **Canonical path** — *"Before I hand off, here's what I see as still
  in flight: [list]. Carry all forward, drop any, or add anything I
  missed?"*

- **Thread hand-up path** — surface each item with a proposed
  disposition (`canonical` / `drop`) and confirm: *"Before I hand up
  and close this thread, here's what I see as still in flight: [list,
  each with my proposed disposition]. Any I should re-flag, or
  anything I missed?"* If you have low confidence on a disposition,
  flag the uncertainty rather than asserting a default.

This step is cheap and catches the wrong-call cases for free.

## After the handoff

**Canonical path.** The next-life agent boots, runs `gc prime` per
its boot prompt, reads the handoff mail as its first action, and picks
up. There is no verification step the handing-off agent can do — once
the restart fires, the old session is gone. Trust the mail.

**Thread hand-up path.** The thread session closes (its bead
transitions to closed via `gc session close`). The canonical does not
restart — it picks up the carry-forward mail on its next mail-check
hook (which fires on the next prompt the operator sends to the
canonical). The hand-up mail is durable in the bead store; trust it
the same way. If the operator wants to verify the mail landed before
the close fires, `gc mail thread <id>` against the just-sent mail bead
shows it queued for the canonical.

## Don't pivot mid-skill

If during the **operator-initiated carry-forward sweep** you find
yourself reaching for `/compact`, `gc session reset`, `gc session
kill`, or (on a thread) `bye` instead — stop. Surface to the operator
that one of those might be a better fit and let them redirect. By the
time this skill is firing, the operator has decided on a thoughtful
close-out; pivoting silently to a different tool breaks that intent.
On a thread specifically: `bye` is the right tool *before* this skill
fires when the operator wants the unconditional close. Once
inventory is underway, finish the inventory and use `gc session
close` from the composed flow.

This is specific to the carry-forward sweep flow, not a blanket
prohibition on `gc session reset`. The **bead-host self-recycle** above
legitimately uses it — operator-invoked, `gc session reset "$GC_SESSION_ID"` is
the restart, no mail. Cycle-recycle likewise chains `gc handoff` then
`gc session reset` to recycle on-demand named coords without operator
`/clear`, documented in `template-fragments/cycle-recycle.template.md`.
Both are allowed.
