---
name: Gas City search — the patrols' move onto orders, with a witness woken only for mail
description: The search behind each surface design tk-1tfzr71.158 adds: the primitive looked for in Gas City, bd and Gas Town, and why it does not cover the need. Read it when building one of the design's units, or when a review asks why a surface is the pack's.
---

# Gas City search for design tk-1tfzr71.158

Gas City is read at upstream main c7eb6d2f43 (2026-11-16) and Gas Town at
gascity-packs 7f86098c04ea, whose witness and deacon formulas are
byte-identical at packs main 0f07496d2fa4. A path without a repository is Gas
City's. Each entry names the surface the design adds, what was searched for,
and the gap.

## The doctor order, `gctk doctor run`, and its event

**Searched.** An order that runs `gc doctor`: none of core's orders
(`internal/bootstrap/packs/core/orders/`), none of the dolt pack's
(`examples/bd/dolt/orders/`), and none of Gas Town's, whose `orders/` holds only
`digest-generate.toml` (gascity-packs `gastown/orders/`). Gas Town's deacon runs
`gc doctor` inside its system-health step and mails `mayor/`
(`gastown/formulas/mol-deacon-patrol.toml`, system-health). A doctor result
Gas City keeps: `gc doctor --json` prints its report and stores nothing
(`cmd/gc/cmd_doctor.go`), and the supervisor's API has no doctor route among
its routes (`internal/api/openapi.json`). An exec order is Gas City's shape for
mechanical work: "An exec order runs the script on the orchestrator — no agent,
no LLM, no work beads" (`docs/tutorials/07-orders.md`, Formula orders vs. exec
orders).

**Where a run's result lives.** Gas City's event log is a platform object the
supervisor serves (`GET /v0/city/{cityName}/events`, filtered by `type` and
returned newest first, `EventListInput`, `internal/api/huma_types_events.go`),
and `gc event emit <type> --payload <json>` records "a custom event to the city
event log" (`cmd/gc/cmd_event_emit.go`). One event per run is the run's record,
and the newest one is what doctor finds now, so no record per check and no
bead is needed. A keyed problem record would hold one row per check, which the
operator ruled out for doctor.

**Gap.** Running doctor on a schedule and recording its run where a surface can
read it. The order and the event are native, and the verb is the part no
primitive does: it carries each failure's first time from the previous run's
event and marks what the accepted file names.

## `doctor/accepted.toml`

**Searched.** A way to rule a check's warning accepted: `[doctor]` config has
size thresholds, the nested-worktree toggle and local checks, and no way to
mute or acknowledge a check (`DoctorConfig`, `internal/config/config.go`), and
`gc doctor` takes no flag that does (`newDoctorCmd`, `cmd/gc/cmd_doctor.go`:
`--fix`, `--verbose`, `--json`, `--check-timeout`, `--check`).

**Gap.** A reviewed list of accepted checks, with each ruling and an optional
time a check may fail before it shows. It is data the doctor verb reads. Gas
City's pack discovery reads only directories under `doctor/` and skips a file
(`DiscoverPackDoctors`, `internal/config/doctor_discovery.go`), so the file is
no check.

## Each monitor order's last good run

**Searched.** `gc order history <name>` lists a run's tracking bead
(`cmd/gc/cmd_order.go`), and this city deletes a closed tracking bead 30
minutes after its close (`[beads.policies.order_tracking]` in the town's
`city.toml`). Gas City's `order-firing-current` check reads each order's last
firing from the event log's tail and then its run history
(`internal/doctor/checks_order_firing.go`), and its `order-outcome-healthy`
check counts trailing `order.failed` events and warns at three
(`internal/doctor/checks_order_outcome.go`). An exec run that exits 0 records
`order.completed` (`dispatchExec`, `cmd/gc/order_dispatch.go`).

**Gap.** Showing each monitor's last good run beside doctor's results. The
verb reads the newest `order.completed` per monitor into the run's event, and
the lateness verdicts stay Gas City's two checks.

## The orders that look and the orders that act

**Searched.** A native salvage of a dead owner's worktree, and a native way to
split a read from its act:

- Core's orphan sweep releases the claim and does "No worktree salvage —
  cities that staff a work-health patrol role (e.g. the gastown pack's witness)
  handle that separately" (`internal/bootstrap/packs/core/orders/orphan-sweep.toml:5-6`).
- `gc worktree cleanup` removes only a worktree `gc worktree ensure` made, with
  its attempt id and generation, and refuses a dirty one or unpushed commits
  (`gc worktree cleanup --help`). The polecats' worktrees are cut with git.
- The controller's closed-bead worktree reaper reaches closed beads only
  (`reapClosedBeadWorktrees`, `cmd/gc/bead_worktree_reaper.go`).
- Gas Town's witness salvages in its step text, through keys that differ from
  ours (gascity-packs `gastown/formulas/mol-witness-patrol.toml:324-462`).
- An order's `trigger = "event"` fires on a named event type, with a cursor and
  at-least-once delivery (`docs/tutorials/07-orders.md`, event), and the run is
  told nothing of the event: an exec order's environment carries the pack, rig
  and store variables and its outcome file (`orderExecEnvWithError`,
  `cmd/gc/order_store.go`). Four of the city's orders already use the trigger.
- A `condition` order runs a check before its exec, but the check runs on every
  dispatch pass and holds the pass until it returns
  (`docs/tutorials/07-orders.md`, condition), which suits no store read across
  every rig.

**Gap.** None for salvage. Gas City releases a dead session's claim, and the
session that next claims the work resumes in the worktree its `work_dir`
records (`work-setup.sh`, `work-enter.sh`), so the design builds no salvage, as
the operator ruled in conversation tk-5deozip. For the seat and queue checks,
a read in one order and its act in another: a cooldown order looks and records
an event with `gc event emit`, and an event order acts after reading again.
Each verb releases nothing. Overlapping runs need no lock of their own, because
each act's writes are guarded or change nothing the second time.

## `gctk session progress`

**Searched.** The session-liveness design's search for a seat that prints while
its work stands still (`specs/tk-1tfzr71.137/design.md`, section 11) found no
Gas City reader of a session's own writes, and the work ladder paces only a
quiet pool seat (`ladderGoverns`, `cmd/gc/work_ladder_lane.go`). This design
adds no rule to it. It moves `seat-progress.sh` into gctk with a pass over every
rig's claims, split into the look and the act above, which is growth AGENTS.md
sends into gctk.

## `gctk refinery stuck` and `gctk mail finding`

**Searched.** Gas Town's check-refinery nudges the refinery and mails
`QUEUE_HEALTH` (W:1123), and doctor's `pool-idle-routed-work` reports routed
work a pool leaves while an instance idles, which is not the refinery's
assigned inbound queue. `gc mail` reads, peeks, archives and marks mail, and
turns none into a record, and Gas Town's check-inbox mails `mayor/` (W:115).

**Gap.** Each verb is one tested call for a block of step text (rule 2), over
the native calls named, and adds no rule the block does not already hold.

## The witness, woken by its mail

**Searched.** A named session that runs only when it has something to do: a
named session's `mode = "on_demand"`, which the pack's refinery and Product
Owner already use (`pack.toml`), and `gc mail send --notify`, which requests a
recipient turn and, in a managed city, a wake for a recipient that is not
running ("Unread mail alone does not request a wake", `newMailSendCmd`,
`cmd/gc/cmd_mail.go`; the notice's `WakeIfNeeded` policy, `mailNotifyOpPolicy`,
`cmd/gc/cmd_nudge.go`).

**Gap.** None. The witness composes both, and the change is config and prompt
text.

## The rework's own key, `rework_reason`

**Searched.** A key that tells a new rework from a bead sent back to the pool.
Gas Town's refinery writes `rejection_reason` on a bead it sends back, and core's
`spawn-storm-detect` reads that key, or `recovered`, on a ready unassigned bead
as a return, counting each change of its `updated_at`
(`internal/bootstrap/packs/core/assets/scripts/spawn-storm-detect.sh`, step 3).
The detector's one setting is its threshold, `SPAWN_STORM_THRESHOLD`, which a
city sets through an order override's `env` (`OrderOverride.Env`,
`internal/config/config.go`). No Gas City or bd key names a new task that
resumes a reviewed branch.

**Gap.** The pack files a rework as a new bead, so it is never a return, and
Gas Town's key on it reads as one. The pack records a rework's reason under its
own key and leaves `rejection_reason` to a bead the refinery sends back. A
threshold cannot tell the two apart, and a detector that counted only a return
is the ask the design leaves to the operator.
