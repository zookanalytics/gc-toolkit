---
name: Cycle-recycle
description: The deterministic context recycle for long-running patrol agents — what fires it, which roles it gates to, when it defers, and why it never asks. Read it when you need the policy behind the cycle-recycle Stop hook.
---

# Cycle-recycle

Long-running patrol agents fill their context and keep going. Cycle-recycle
is the mechanism that recycles them before that becomes a problem, and it
is **deterministic and hook-enforced** — no agent decides whether to
recycle, and no agent runs a recycle sequence by hand.

The implementation is a Claude Code `Stop` hook at
`overlays/cycle-recycle/.claude/hooks/cycle-recycle.sh`, staged into an
agent's work dir by the `overlay_dir = "overlays/cycle-recycle"` patches in
`pack.toml`. This document is the policy behind it.

## Why a hook and not an instruction

The prose version of this rule used to live in the patrol formulas as
"apply cycle-recycle", and it degraded exactly as context filled: the
fuller the context, the less reliably the model ran the end-of-wisp check,
so context climbed and the check was skipped harder (tk-g8pfg). The harness
runs a `Stop` hook at the end of every turn regardless of model state, so
moving the check there makes it genuinely enforced.

This is the general shape — a remedy that depends on an agent choosing to
follow an instruction fails silently at exactly the moment it is needed.

## What fires it

At the end of every turn the hook, in order:

1. **Self-gates to patrol roles.** It derives the role from the trailing
   component of `GC_AGENT` and proceeds only for `witness`, `deacon`, and
   `refinery`. Every other agent — ephemeral polecats, converse sessions,
   mechanik — is a no-op, so a focused worker is never recycled
   mid-task.
2. **Measures context** from the session's own transcript. Every hook
   payload carries a `transcript_path`; the newest usage entry in that
   JSONL — prompt-side input tokens plus cache reads plus cache writes —
   is the session's live context size. It is the same quantity gascity
   injects on `UserPromptSubmit`, so the hook and the rest of the city
   agree on what "context size" means, and the measurement is local to the
   turn that triggered the hook rather than something another process has
   to publish.
3. **Compares against an absolute 200K threshold.** Under it — the common
   path — the hook exits cheaply.
4. **Over threshold**, writes a durable HANDOFF mail (`gc handoff`) and
   triggers a restart (`gc session reset`).

### Why 200K, absolutely rather than proportionally

200K is an absolute work-product threshold: 20% of a 1M window, and the
compaction edge of a 200K-window agent. Sizing it as a fraction of the
window would recycle a large-window agent far later in wall-clock terms
than a small-window one, for no reason connected to how much work the
agent has actually accumulated.

## When it defers

The over-threshold path is rare, and landing a reset at the wrong moment
is worse than landing it a turn later. `gc session reset` preserves
identity, alias, mail, and queued work but resets the conversation, so the
hook defers when:

- an **operator is attached** to watch or debug the pane; or
- the **refinery is mid git-op** — a rebase/merge in progress or a dirty
  tree, in either the refinery's own worktree or the rig's canonical
  checkout (`GC_RIG_ROOT`). Witness and deacon are idle pollers with no
  long git operations, so this guard is refinery-only. Untracked files are
  normal scratch and do not count.

The bias is **uncertain → skip**. Deferring only delays the recycle: the
hook re-checks next turn, and Claude's `PreCompact` hook remains the
reactive safety net at the model's own compaction edge. The same applies
when no `transcript_path` arrives, the transcript is unreadable, or it
carries no usage entry — the check skips silently rather than guessing.
There is no fallback heuristic.

## Whether it can fire

Every skip is silent, so a mechanism that can never fire looks exactly like
one that has had nothing to do. `doctor/check-recycle-capable` closes that
gap. It asserts the capability rather than the installation:

- A `Stop` event in the overlay's `settings.json` invokes the hook, and
  does not redirect its stdin. The transcript path arrives *on* stdin, so a
  wiring that starves it leaves a hook that measures nothing.
- The hook's own measurement reads the context size a transcript carries.
  The check drives the shipped script through `cycle-recycle.sh --measure`,
  which prints what the hook would compare against its threshold and acts
  on nothing, so a passing check is evidence about the hook rather than
  about a copy of its logic.
- No refinery's git-op defer guard has been continuously true past a bound
  (24h by default, `GC_DOCTOR_RECYCLE_LATCH_HOURS`). The guard cannot tell
  a rebase in flight from a tracked file nobody has committed, so the check
  ages it by the oldest currently-dirty path and names the file holding it.

The check is silent when the mechanism is healthy and merely idle. It reads
the rig's canonical checkout. The hook also defers on its own working
directory, which nothing outside that session can address. Whether a given
session's transcript is readable is a per-session fact the check cannot see
from outside; what it asserts is that the measurement chain works.

## Invariants

- **Never prompt the operator.** The threshold *is* the directive. No
  `AskUserQuestion` or other consent UI at the boundary — see
  `template-fragments/heartbeat-no-consent-ui.template.md`. Blocking a
  heartbeat on consent stalls patrol activity for as long as the prompt
  sits unanswered. That fragment is the wider rule and the hook is one
  instance of it: it prohibits blocking consent UI from a heartbeat agent
  about *anything*, not only about recycling. It is injected onto the same
  three roles this overlay is wired to, because a role that has the hook but
  not the doctrine has a boundary that will not prompt and an agent that was
  never told not to. **UNCHECKED**: no check asserts the two halves together.
- **Always exit 0**, so the `Stop` event is never blocked.
- **Keep stdout empty** — all diagnostics go to stderr, so Claude never
  parses a stray block decision.
- **Under threshold must stay cheap.** It is the common path: one bounded
  read of the transcript's newest 2MiB, and no network.

## Relationship to the handoff skill

Cycle-recycle legitimately chains `gc handoff` (state capture) followed by
`gc session reset` (restart trigger). That chaining is correct *here* and
is the reason the `handoff` skill's prohibition on `gc session reset` is
scoped to the operator-initiated carry-forward sweep it governs, rather
than being absolute. The two are different flows:

| | Cycle-recycle | `/handoff` |
|---|---|---|
| Trigger | context threshold, automatic | operator types it |
| Decides | the hook | the operator |
| Scope | witness, deacon, refinery | whoever was asked |

`/handoff` is operator-initiated: an agent does not propose it via consent
UI and does not invoke the skill from internal judgment.

## Wisp handling across the boundary

A generic `Stop` hook fires at a turn boundary that may be mid-wisp, and it
cannot reliably reconstruct the patrol formula's pour vars
(`binding_prefix`, `target_branch`, `rig_name`,
`default_merge_strategy`) — those live in the agent's own prompt, not in
the environment. So the hook does not attempt a pour. The inheriting
session re-establishes its wisp through its own Tier-2/3 startup-adopt
path, which pours or adopts with the correct vars. The trigger token count
travels in the HANDOFF body so the new session has that context before it
re-derives its wisp.

Pour-before-burn cycle-recycle can therefore leave an open wisp behind;
the startup-discovery fragments handle that case explicitly.

## Manual escape hatch

If a patrol agent needs to bail mid-task before the hook's turn-boundary
check fires, `gc runtime request-restart` is the manual route (these
sessions are `mode = "always"`, so the controller respawns them). The
automatic state-capturing recycle is the hook's job, not the agent's.
