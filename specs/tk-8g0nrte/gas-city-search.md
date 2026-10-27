---
name: Gas City search for restarting a patrol session whose prompt or formula changed
description: The search the arch check asks for before cycle-recycle gains a drift trigger, a --prompt mode wired to UserPromptSubmit and a --drift probe. What Gas City ships for a live session whose prompt or formula changed on disk, read at named upstream commits and on the city's installed build, the Claude Code hook behavior the change relies on, and why the pack composes gc handoff and gc session reset from its own hook instead. Read it when checking whether the drift trigger can move onto a Gas City primitive.
---

# Gas City search for restarting a patrol session whose prompt or formula changed

A named patrol session runs the prompt Gas City rendered when it launched and
the patrol formula steps it has read since. When a change on main reaches the
pack checkout, nothing restarts the session, so it keeps running the old text.
The refinery did this for hours after the one-bead PR model changed its
find-work step: it kept the select it remembered, and scratch scripts it had
built from older step text, and took landing beads that the new step leaves
alone.

This change gives the cycle-recycle hook a second trigger. A session recycles
when a pack file its prompt or patrol formula comes from changed on disk after
the session's first prompt. The hook checks at every turn's end, as a `Stop`
hook, and before every prompt, as a `UserPromptSubmit` hook run with
`--prompt`. Before a prompt, it blocks the prompt once the restart is requested,
and the HANDOFF mail carries the prompt's text. `cycle-recycle.sh --drift
<role>` prints what the check finds and acts on nothing, and
`doctor/check-recycle-capable` drives it, as it drives `--measure`. So the arch
check asks what Gas City already ships for that need
([review-arch.md](../../docs/review-arch.md#the-checks), check 1).

Gas City ships no restart for a session whose prompt or formula changed. Its
drift fingerprint leaves the prompt out on purpose and reads no formula. The
one command that compares a running formula with the disk needs a hash that the
patrol's pour does not stamp. The change composes what Gas City does ship: the
hook events Gas City itself uses around a turn, `gc handoff` and
`gc session reset`.

## The need

- A live named patrol session (the refinery, the witness and the deacon)
  restarts once its prompt template, a fragment, or its patrol formula changed
  in the pack checkout after it started, so its next turn runs the new text.
- A session idle between turns when the change lands, which is the refinery's
  usual state, restarts before its next prompt acts.
- A session mid-turn is not interrupted. It finishes the turn on the text it
  has.
- Nothing restarts when nothing changed.

## Where the search looked

Each was read on 2026-10-27:

- Gas City at main `5ee67e887d87`, which differs from the
  `45563e2abf21` read in full only in a process-table test and a release-gate
  note. The search covered its source for the session fingerprint, the
  reconciler's restart and timer decisions, session priming, formula hashing,
  pack drift, and the hooks it installs for a Claude session.
- The city's installed build, `gc` 1.4.3 at the fork commit `e03752646`. Every
  symbol below is present there too.
- The Claude Code hooks reference and settings page, for what a
  `UserPromptSubmit` block does and when a hook edit reaches a running session.

## What Gas City ships near the need

### The config-drift restart

The reconciler drains and restarts a session whose core fingerprint moved
(package runtime, `CoreFingerprint` and `ConfigFingerprint`). The fingerprint
hashes the launch command, lifecycle, an allow-list of environment keys,
`pre_start`, session setup, the overlay directory's path, the provider overlay
slots, copy files, startup-dialog and mouse settings, and the restart-policy
keys of `FingerprintExtra`. It leaves out `PromptSuffix`, which carries the
rendered prompt, and the package's partition test names the reason: "volatile
beacon text, deliberately excluded". The overlay is hashed by its path, not its
content. Copy files are hashed by content only where Gas City probes them (the
city's scripts directory and some providers' hook files), and none of those is
a prompt template or a formula. So a prompt or formula edit restarts nothing,
and changing that is a change to Gas City, which the pack does not campaign
for ([foundation.md](../../docs/foundation.md#boundaries)).

### `gc formula version-check`

`gc formula version-check <bead-id>` (package main,
`newFormulaVersionCheckCmd`, upstream since `488b3d800`, #1608) compares a
molecule bead's `gc.formula_hash` with the formula compiled from disk. Its
help says "Use this to detect whether a running session's formula has been
updated since it was spawned." It does not serve the need, for four reasons:

- The patrol wisps are poured with `gc bd mol wisp --root-only`, which is bd's
  pour. It stamps neither `gc.formula_hash` nor the formula reference the
  command looks the formula up by. On 2026-10-27 the live refinery and witness
  wisps carried only `gc.rig`, `gc.session_name` and `gc.work_dir`.
- Each iteration pours its wisp from the formula on disk, so a wisp's hash
  matches the disk while the session still runs older text it remembers. The
  drift that matters is against the session's start, not the wisp's pour.
- It exits 1 on a divergence and on every error alike. A bead that does not
  exist exits 1 with no output, so a caller cannot tell a change from a failed
  read.
- It judges the formula only, never the prompt.

### The startup prompt's hash

The session converger keeps a `prompt_hash` beside its priming markers (package
main, `deriveConvergeActions` and `attemptEligible`). A changed hash makes an
unconfirmed startup-prompt delivery eligible again. It restarts no confirmed
session, and the converger's own comment says its action list is "exercised
only by tests until Stage 3 wires the act loop".

### The max-age restart

`max_session_age` stops a session past its age (package session,
`DecideMaxSessionAge`), but the decision defers while the session holds assigned
work, and a patrol session always holds its wisp. Any agent that sets it also
refuses the v2 reconciler (package main, `v2LatchRefusals`). It restarts on age
whether or not anything changed.

### Idle sleep

Gas Town's refinery sets `sleep_after_idle`, so an idle refinery sleeps and
wakes into a fresh session. The config loader rejects the setting for an
always-mode named session ([agent-types.md](../../docs/gascity/agent-types.md#an-always-mode-session-cannot-idle-sleep)),
so it cannot reach the witness or the deacon. On the refinery it restarts after
every idle stretch whether or not anything changed, and a change that lands
inside the idle window still reaches the next nudge's turn.

### Pack drift for the supervisor

`DetectPackDrift` (package main) reports the pack roots whose newest file mtime
is later than the time the supervisor parsed them, and `gc start` uses it to
say the running supervisor is stale. It judges the supervisor process, not a
session. The hook reads the same signal against a session's first prompt.

### The hook events and the restart verbs

For a Claude session, Gas City installs its own `UserPromptSubmit` hooks
(`gc nudge drain --inject` and `gc mail check --inject`) and a `PreCompact`
hook that runs `gc handoff --auto`. Before a turn starts is the platform's own
place to act on a session. `gc handoff` sends the session's HANDOFF mail to
itself and, for a controller-restartable session, requests the restart.
`gc session reset` requests a fresh restart that keeps the session's identity,
alias, mail and queued work. The hook composes these and nothing else.

## Claude Code behavior the change relies on

Read in the hooks reference and the settings page on 2026-10-26:

- A `UserPromptSubmit` block "stops the prompt before it reaches Claude", and
  its reason is "Shown to the user when `decision` is `"block"`. Not added to
  context." The block message ends with the original prompt, and Claude Code
  writes it to the transcript.
- What happens to the `additionalContext` another `UserPromptSubmit` hook
  returns for a prompt that a sibling blocks is not documented. The
  cycle-recycle policy therefore says only that the HANDOFF does not carry it.
- The `UserPromptSubmit` input carries the submitted text as `prompt`, beside
  `transcript_path`.
- "Direct edits to hooks in settings files are normally picked up
  automatically by the file watcher", and the settings page says Claude Code
  "applies most edits to the running session without a restart, including
  edits to `permissions`, `hooks`". So the hook does not watch its own
  settings, and the `UserPromptSubmit` wiring this change adds reaches a live
  session once Gas City stages the overlay again.

## What the change adds

It adds no pack noun. There is no new bead kind, lifecycle state or metadata
key, so it takes no warrant ([warrants.md](../../docs/warrants.md)). The
surface is a trigger inside a hook the pack already ships, the `--prompt` and
`--drift` modes of that script, a `UserPromptSubmit` entry in the overlay's
settings, and two arms in an existing doctor check. The answer changes when
Gas City restarts a live session whose rendered prompt or patrol formula
changed. The drift trigger then goes, and the hook keeps its context trigger.
