---
name: Cycle-recycle
description: The deterministic recycle for long-running patrol agents — what fires it (a context threshold, or a pack change under a live session), which roles it gates to, when it defers, what a session mid-turn does, and why it never asks. Read it when you need the policy behind the cycle-recycle hook.
---

# Cycle-recycle

Long-running patrol agents fill their context and keep going, and they keep
running the prompt and formula text they started with after the pack changes
under them. Cycle-recycle is the mechanism that recycles them before either
becomes a problem, and it is **deterministic and hook-enforced** — no agent
decides whether to recycle, and no agent runs a recycle sequence by hand.

The implementation is `overlays/cycle-recycle/.claude/hooks/cycle-recycle.sh`,
which runs as a Claude Code `Stop` hook and, with `--prompt`, as a
`UserPromptSubmit` hook. The `overlay_dir = "overlays/cycle-recycle"` patches
in `pack.toml` stage it into an agent's work dir. This document is the policy
behind it.

## Scope

**Mandate.** The automatic recycle of the long-running patrol roles: what
fires it, when it defers, what it does at the boundary, how its capability is
checked, and the invariants the hook keeps.

**Boundaries.** This is the policy, and the hook script is the implementation.
A handoff the operator asks for is the `handoff` skill's
(`skills/handoff/SKILL.md`). What becomes of the retiring session's scratch is
[scratch-reclaim.md](scratch-reclaim.md). The rule against consent UI from any
heartbeat agent, of which the hook is one instance, is
`template-fragments/heartbeat-no-consent-ui.template.md`. The overlay's other
`Stop` hook, which hands the deacon back a turn that ends between patrol
cycles and does print a block decision, is
[patrol-continue.md](patrol-continue.md).

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

At the end of every turn, and before every prompt, the hook, in order:

1. **Self-gates to patrol roles.** It derives the role from the trailing
   component of `GC_AGENT` and proceeds only for `witness`, `deacon`, and
   `refinery`. Every other agent — ephemeral polecats, converse sessions,
   mechanik — is a no-op, so a focused worker is never recycled
   mid-task.
2. **Measures context** from the session's own transcript, at a turn's end
   only. Every hook payload carries a `transcript_path`; the newest usage
   entry in that JSONL — prompt-side input tokens plus cache reads plus cache
   writes — is the session's live context size. It is the same quantity
   gascity injects on `UserPromptSubmit`, so the hook and the rest of the city
   agree on what "context size" means, and the measurement is local to the
   turn that triggered the hook rather than something another process has
   to publish. Before a prompt the context is what it was when the last turn
   ended, so the hook does not measure it there.
3. **Compares against an absolute 200K threshold.**
4. **Checks for pack drift** when the context does not recycle the session:
   a pack file its prompt or patrol formula comes from changed on disk after
   its first prompt ([Pack drift](#pack-drift)). With neither, the common
   path, the hook exits cheaply.
5. **Recycles**: it writes a durable HANDOFF mail (`gc handoff`), reaps the
   retiring session's scratch (`scratch-reap.sh --session`, since the recycle
   abandons that tree whole — docs/scratch-reclaim.md), and triggers a restart
   (`gc session reset`). Before a prompt it then blocks the prompt
   ([Before a prompt](#before-a-prompt)).

### Why 200K, absolutely rather than proportionally

200K is an absolute work-product threshold: 20% of a 1M window, and the
compaction edge of a 200K-window agent. Sizing it as a fraction of the
window would recycle a large-window agent far later in wall-clock terms
than a small-window one, for no reason connected to how much work the
agent has actually accumulated.

## Pack drift

A patrol session holds text the pack can change under it. Gas City renders
the role's prompt, fragments included, once, at launch. The session reads its
patrol formula's steps as it reaches them, and after many iterations it runs
the commands it remembers, and the scratch scripts it built from older step
text, rather than the step text in front of it. A change on main reaches the
pack checkout when `reconcile-rig-checkouts` fast-forwards it, and Gas City
restarts no session for it: its drift fingerprint deliberately excludes the
prompt and reads no formula
([the Gas City search](../specs/tk-8g0nrte/gas-city-search.md)). A restarted
session gets a new conversation and a new scratch tree, so it starts from the
current text.

### What it watches

For a role, the hook watches its prompt template
(`agents/<role>/prompt.template.md`), every fragment under
`template-fragments/`, and its patrol formula
(`formulas/mol-<role>-patrol.toml`). It reads them in the pack checkout: in
`GC_RIG_ROOT` when that carries the role's formula, and otherwise in
`$GC_CITY_PATH/rigs/gc-toolkit`. Every fragment is watched, not only the ones
the role's prompt includes, so a fragment edit restarts each patrol session
whether or not its prompt includes that fragment. That costs a restart now and
then, and spares the hook a reader of template includes.

The hook scripts and their settings are not watched. Gas City stages the
overlay into the work dir on its reconcile tick, each hook run reads the staged
script, and Claude Code applies a settings edit to a running session.

### The signal

A watched file has drifted when its mtime is later than the session's first
prompt, the transcript's first timestamped record, and not later than now. A
fast-forward rewrites only the files whose content changed, so a file's mtime
is when its new content reached the checkout. Gas City's own pack-drift check
for the supervisor reads the same signal: the newest file mtime under a pack
root against the time the supervisor parsed it. An mtime later than now counts
as no change, so a file stamped in the future cannot recycle a session on
every turn. The first prompt follows the launch's render by seconds, and a
change inside that window goes unseen until the next one.

### When it checks, and a session mid-turn

The check runs at every turn's end and before every prompt. The witness and the
deacon close each patrol cycle at a turn's end, where the check recycles a
drifted session, or in Gas City's fresh restart onto their next wisp, which
starts from the current text, so a change reaches them within the cycle it
lands in. The refinery's turns start from a nudge, and it waits idle between
them, which is when a change usually lands, so the check before its next prompt
is the one that reaches it.

A session mid-turn keeps the text it has until that turn ends. The hook never
ends a turn early, for the reason it defers under an attached operator or a
refinery git op: a restart mid-turn interrupts the work in hand. The check at
that turn's end recycles the session, so its next turn runs the new text.

### Before a prompt

Under `--prompt`, a drifted session recycles before the prompt reaches the
model. The hook sends the HANDOFF mail, which carries the prompt's text,
requests the restart, and then blocks the prompt, so the old text never acts
on it. The restarted session starts from the current prompt, adopts its wisp,
reads its inbox and works its queue. The hook blocks only once
`gc session reset` succeeds: a blocked prompt with no restart behind it would
leave the session idle on the old text, dropping every prompt it is sent. A
HANDOFF that fails to send does not hold the block, because the requested
restart would end a turn let through mid-command; the prompt's text then stays
in the old session's transcript, where Claude Code writes a blocked prompt. The
HANDOFF does not carry what Gas City's own `UserPromptSubmit` hooks inject
into that prompt, such as drained nudges; the restarted session's startup
reconcile and inbox stand in for them.

### Which named sessions it covers

The overlay serves the named sessions that run a patrol formula unattended:
the refinery, the witness and the deacon. Mechanik, the other named session,
holds the operator's standing conversation. A restart on a pack change would
end that conversation under the operator, so mechanik takes a change at its
next restart, which the operator starts (`skills/handoff/SKILL.md`).

## When it defers

The recycle path is rare, and landing a reset at the wrong moment is worse
than landing it a turn later. `gc session reset` preserves identity, alias,
mail, and queued work but resets the conversation, so the hook defers either
recycle when:

- an **operator is attached** to watch or debug the pane; or
- the **refinery is mid git-op** — a rebase/merge in progress or a dirty
  tree, in either the refinery's own worktree or the rig's canonical
  checkout (`GC_RIG_ROOT`). Witness and deacon are idle pollers with no
  long git operations, so this guard is refinery-only. Untracked files are
  normal scratch and do not count.

The bias is **uncertain → skip**. Deferring only delays the recycle: the
hook re-checks next turn, and Claude's `PreCompact` hook remains the
reactive safety net at the model's own compaction edge. Before a prompt, a
deferral lets the prompt through. The same applies when no `transcript_path`
arrives, the transcript is unreadable, it carries no usage entry or no
timestamped record, or no pack checkout carries the role's formula — the
check skips silently rather than guessing. There is no fallback heuristic.

## Whether it can fire

Every skip is silent, so a mechanism that can never fire looks exactly like
one that has had nothing to do. `doctor/check-recycle-capable` closes that
gap. It asserts the capability rather than the installation:

- A `Stop` event in the overlay's `settings.json` invokes the hook, and
  does not redirect its stdin. The transcript path arrives *on* stdin, so a
  wiring that starves it leaves a hook that measures nothing.
- A `UserPromptSubmit` event invokes the hook with `--prompt`, with its stdin
  intact as well. Without it, a change that lands while a patrol session waits
  between turns reaches its next turn unseen.
- The hook's own measurement reads the context size a transcript carries.
  The check drives the shipped script through `cycle-recycle.sh --measure`,
  which prints what the hook would compare against its threshold and acts
  on nothing, so a passing check is evidence about the hook rather than
  about a copy of its logic.
- The hook's own drift check sees a changed pack file. The check drives
  `cycle-recycle.sh --drift refinery`, which prints the watched files it finds
  changed and acts on nothing, on a fixture pack whose patrol formula was
  written after a transcript's first prompt.
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
  never told not to. `doctor/check-cycle-recycle-hook` asserts the two halves
  stay in step: the set of roles carrying the overlay and the set injecting the
  fragment must be equal, so a role cannot end up with the hook but not the
  doctrine, or the doctrine but not the hook.
- **Always exit 0**, so a failing hook never blocks the `Stop` event or a
  prompt.
- **Keep stdout empty** — all diagnostics go to stderr, so Claude never
  parses a stray block decision. The one block decision is the one the hook
  means, before a prompt once the restart is requested.
- **Nothing to recycle must stay cheap.** It is the common path: one bounded
  read of the transcript's newest 2MiB, one of its first records, one `stat`
  over the watched files, and no network.

## Relationship to the handoff skill

Cycle-recycle legitimately chains `gc handoff` (state capture) followed by
`gc session reset` (restart trigger). That chaining is correct *here* and
is the reason the `handoff` skill's prohibition on `gc session reset` is
scoped to the operator-initiated carry-forward sweep it governs, rather
than being absolute. The two are different flows:

| | Cycle-recycle | `/handoff` |
|---|---|---|
| Trigger | context threshold or pack drift, automatic | operator types it |
| Decides | the hook | the operator |
| Scope | witness, deacon, refinery | whoever was asked |

`/handoff` is operator-initiated: an agent does not propose it via consent
UI and does not invoke the skill from internal judgment.

## Wisp handling across the boundary

A generic hook fires at a turn boundary that may be mid-wisp, and it
cannot reliably reconstruct the patrol formula's pour vars
(`binding_prefix`, `target_branch`, `rig_name`) — those live in the agent's
own prompt, not in the environment. So the hook does not attempt a pour.
The inheriting session re-establishes its wisp through its own Tier-2/3
startup-adopt path, which pours or adopts with the correct vars. The HANDOFF
names the trigger, the token count or the changed files, so the new session
has that context before it re-derives its wisp.

Pour-before-burn cycle-recycle can therefore leave an open wisp behind;
the startup-discovery fragments handle that case explicitly.

## Manual escape hatch

If a patrol agent needs to bail mid-task before the hook's turn-boundary
check fires, `gc runtime request-restart` is the manual route (these
sessions are `mode = "always"`, so the controller respawns them). The
automatic state-capturing recycle is the hook's job, not the agent's.
