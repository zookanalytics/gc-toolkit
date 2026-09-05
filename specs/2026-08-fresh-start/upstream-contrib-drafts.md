---
name: Upstream contribution drafts — build-factory trial findings
description: Ready-to-file issue drafts for upstream defects, each with reproduction and a proposed fix — five surfaced by the 2026-08-08 build-factory trial (evidence in build-factory-trial-reactions.md), two by the same-day live-adoption validator run (evidence in live-adoption-findings.md), and later entries appended as they are found. For the operator to file against gastownhall/gascity-packs (or gascity core where noted) at their leisure; bodies are self-contained.
---

# Upstream contribution drafts

Drafts 1–5: defects surfaced by one `build-basic` run (2026-08-08, split
city/rig layout, gascity pack 0.4.0 `f69ec02`). Evidence:
[build-factory-trial-reactions.md](build-factory-trial-reactions.md).
Drafts 6–7: defects surfaced by the 2026-08-08 live-adoption validator
run. Evidence: [live-adoption-findings.md](live-adoption-findings.md).
Draft 8: the lease primitive's adoption review. Evidence:
[../tk-eotd6/lease-adoption.md](../tk-eotd6/lease-adoption.md).
Ordered by severity within each batch. Each body below is self-contained
for filing.

## 1. `build-basic`'s artifact gate silently never runs in a split city/rig layout

**Repo:** gastownhall/gascity-packs · **severity: high** (silent loss of
the factory's main quality mechanism)

> **Body draft:** In a city whose rigs are not rooted at the city root,
> every `[steps.check]` in `build-base.formula.toml` fails to start and
> the chain proceeds ungated. The check path
> `.gc/scripts/checks/build-artifact-valid.sh` is relative and resolves
> against the **rig root**, but `.gc/scripts/` exists only at the city
> root: each stage logs a control-quarantine
> (`lstat …/<rig>/.gc/scripts: no such file or directory`) and the
> workflow continues, so all four artifacts pass without schema
> validation and the 3-attempt repair loop is inert. Nothing in the run
> surfaces this as a failure. Compounding: the pack ships the scripts
> and `github-issue-fix`'s workflow installs them
> (`cp -R {{pack_root}}/assets/scripts .gc/scripts`), but `build-basic`'s
> `prepare` step never does. **Proposed fix:** install the check scripts
> in `build-basic`'s prepare (mirroring github-issue-fix), or resolve
> check paths against the pack/city root; and make a check that cannot
> start fail the step rather than quarantine-and-continue.

The silent-failure core of this is fixed in `gascity`. `internal/dispatch/ralph.go`
resolves the check against the city/script root instead of forcing it under the
rig subtree, and a check that cannot start is now a step-failing `GateError`
rather than a quarantine-and-continue. The packs side is unchanged: the check
path is still relative and `build-basic`'s prepare still does not install the
scripts. A missing check now fails the chain loudly, though, so this is a
low-severity packs cleanup, not a silent loss of the quality gate.

## 2. `decompose` proceeds past a `changes_required` review verdict

**Repo:** gastownhall/gascity-packs · **severity: high** (the review
stage looks load-bearing and is not)

> **Body draft:** In `build-base.formula.toml`, `decompose` declares
> `needs = ["plan-review"]` but nothing reads the review artifact's
> `status`/verdict, so a `changes_required` verdict is structurally
> advisory: decomposition reads the plan exactly as written and files
> beads from it. In our run the reviewer knew this and edited the plan
> in place as its only way to prevent a false finding from becoming an
> implementation bead. **Proposed fix:** gate `decompose` on the review
> verdict (block or loop on `changes_required`), or document explicitly
> that review is advisory and the sanctioned gate is external. If
> data-driven gating is planned, this is a natural first member.

## 3. Misleading sling-time warning about bead context (invites a stage-destroying "fix")

**Repo:** gastownhall/gascity (warning text) · **severity: medium**

> **Body draft:** Slinging a bead at `build-basic` prints a warning that
> the bead description "is not carried into the formula's rendered
> context … the formula's brainstorm will not see them." The description
> *does* arrive — via the auto-created input convoy — and our
> requirements stage demonstrably read material referenced only from the
> bead body. The warning is worse than inaccurate: the obvious operator
> correction is `--var requirements_path=<doc>`, which makes the factory
> *reuse* that document as the requirements artifact and silently skip
> the requirements stage. **Proposed fix:** reword the warning for
> formulas that create an input convoy, and document the distinction
> between `context_path` (extra context) and the stage-skipping
> `*_path` vars.

The warning text is unchanged, but it no longer fires on a normal sling.
`internal/sling/sling_core.go` gates it behind
`attachedBeadInstructionsDroppedHint`, which returns nothing when `gc.var.issue`
is auto-stamped (the default) or a `context_path`/`requirements_path` is passed.
The false alarm that invited the stage-destroying `--var requirements_path=<doc>`
correction is gone; only the reword itself is still worth filing.

## 4. Decomposer claims "per the headless contract" under `interaction_mode=interactive`

**Repo:** gastownhall/gascity-packs · **severity: low** (mode plumbing
or prompt bug; misleads audits)

> **Body draft:** With the workflow configured
> `interaction_mode=interactive`, the decompose stage recorded decisions
> "rather than asked, per the headless contract." Either the var is not
> reaching the stage prompts, or the stage text defaults to headless
> phrasing regardless of mode. Small, but it makes run records claim a
> mode the operator did not set. **Proposed fix:** thread the actual
> `interaction_mode` value into stage prompts (or their rendered
> headers) so stages cite the configured mode.

This is fixed in the current pack sources. The "per the headless contract"
phrasing is gone, and `interaction_mode` is threaded into the stage prompts;
`build-basic/requirements.md`, for one, asks only when the mode is interactive.
Nothing to file against what we run.

## 5. `validate_build_artifact.py` hard-requires PyYAML, undeclared

**Repo:** gastownhall/gascity-packs · **severity: low**

> **Body draft:** The manual fallback validator exits
> `error: PyYAML is required`; nothing declares the dependency and no
> stdlib fallback exists, so on hosts without PyYAML both the automated
> gate (issue 1) and the manual fallback are unavailable — and in our
> run a stage *claimed* validation had run when it could not have.
> **Proposed fix:** declare the dependency (or vendor a minimal
> frontmatter parser), and make the validator's absence loud in the
> stages that reference it.

## 6. `prompt_template` `<pack>//<subpath>` fails to resolve under the retired-materialization model and silently renders a 16-line generic stub

**Repo:** gastownhall/gascity · **severity: high** (silent correctness
failure — an agent runs real work with none of its doctrine)

> **Body draft:** An agent whose `prompt_template` uses the cross-pack
> `<pack>//<subpath>` form (e.g.
> `"gastown//agents/polecat/prompt.template.md"`) has the reference
> resolved against the **pack directory** (`<pack-root>/gastown/…`)
> rather than the import cache. Under the retired-materialization model
> that path never exists. Worse, resolution failure does not fail config
> load — the agent silently renders the 16-line generic stub ("You are
> an agent in a Gas City workspace. Claim available work and execute
> it."), so a codex polecat would claim real implementation work with
> none of its convoy, non-impl-done, or file-work-records doctrine.
> Evidence (validator F-03): `gc doctor` shows only `config-refs`
> warnings (`prompt_template … not found`) while rendered prompt sizes
> tell the real story — the correctly-resolved polecat renders 1540
> lines, the two cross-pack agents render 16. Survives `gc import
> install`, so it is not a lock-state problem. **Proposed fix:** resolve
> `<pack>//<subpath>` against the import cache under the
> retired-materialization model, and make an unresolvable
> `prompt_template` **fail config load** rather than fall back to the
> stub — the fallback converts a wiring error into a silently degraded
> agent.

Fixed in our fork by `gc-wvjrm` (#62), which ships in the running `gc`. A
`<pack>//<subpath>` agent path ref resolves against the imported-pack closure
(`internal/config/pack_qualified_path.go`), and an unresolvable ref fails config
load instead of rendering the stub. The fix is fork-only, so upstream still
carries this: the draft stands for upstream, and our commit is the patch to
offer with it.

## 7. `gc bd ready --json` intermittently emits invalid JSON under concurrent agent writes

**Repo:** gastownhall/gascity · **severity: medium** (transient, but
each occurrence costs consumers a full pass)

> **Body draft:** Under concurrent agent writes, `gc bd ready --json`
> intermittently emits invalid JSON — unescaped control characters
> (`jq: parse error: Invalid string: control characters from U+0000
> through U+001F must be escaped`). Observed twice within a minute
> (validator F-26); not reproducible on demand — five consecutive runs
> afterwards were clean and byte-identical (305558 bytes, 85 items),
> and the same payload redirected to a file parsed fine, so it is a
> transient torn read under write pressure, not a poison bead.
> Consequence: any consumer with a fail-safe (e.g. a
> `jq -e 'type=="array"'` guard) correctly aborts and files nothing —
> which on a cooldown-driven cadence means a full pass is silently lost
> per occurrence. **Proposed fix:** make the JSON emission read from a
> consistent snapshot (or serialize/escape output atomically) so a
> concurrent write cannot tear the payload mid-emit.

The consumer path is fixed. On a federated or split city the default
`work_query` reads through the in-process `gc ready` (`cmd/gc/cmd_ready.go`),
which marshals a complete snapshot with `json.Marshal` (control characters
always escaped) and emits it in one write, so a concurrent write cannot tear it.
A raw `gc bd ready --json` still forwards to the `bd` binary and can still tear,
but the split-city consumer the trial hit no longer does. File only if the raw
passthrough is the concern.

## 8. `gc bd heartbeat` cannot refresh a claim `gc hook --claim` recorded under a session id

**Repo:** gastownhall/gascity · **severity: high** (a claim recorded under a
session id — the pool-worker path — cannot refresh its own lease, so that
bead reads expired within five minutes and `bd reclaim` cannot tell its live
holder from a dead one) · fixed in our fork by `gc-ox80c` (#177), still live upstream

> **Body draft:** the assignee `gc hook --claim` records depends on the
> session. For a pool worker it is the session **id** (`lx-ojs28`), while
> `BEADS_ACTOR` in that same session is the session **name**
> (`gc-toolkit--gc-toolkit__polecat-1-pool`). `gc bd heartbeat` forwards to
> bd's native owner-only `heartbeat`, which matches actor to assignee under
> `actorMatches` — byte-identical, or equal after canonicalizing separators
> — and a session id and a session name satisfy neither, so the holder's own
> heartbeat is refused: `Error: heartbeat tk-eotd6: issue already claimed by
> lx-ojs28`. Re-running the identical command as `BEADS_ACTOR=lx-ojs28 gc bd
> heartbeat tk-eotd6` succeeds and moves `lease_expires_at` from 08:00:10Z to
> 08:05:09Z, so the identity comparison is the whole of the refusal. A
> session whose `BEADS_ACTOR` already equals the recorded assignee — a named
> agent, whose claim records its alias/agent form — heartbeats its own claim
> unaffected; the gap is the session-identity path. The claim side already
> resolves it: `cmd/gc/cmd_hook_claim.go` uses the bead's current assignee as
> the claim actor, commenting that `BEADS_ACTOR` may be the runtime name, the
> session bead id, or an alias and that bd's `--claim` requires a match.
> `rewriteBdHeartbeatArgs` in `cmd/gc/cmd_bd.go` validates the id and forwards
> with the ambient actor, applying no such resolution. The TTL offers no way
> around it: `issueops.DefaultLeaseTTL` is a five-minute constant reachable
> only through the `WithLeaseTTL` context key, which no `cmd/bd` path carries.
> **Proposed fix:** have `gc bd heartbeat` resolve the actor the way the claim
> path does — read the bead's current assignee and heartbeat as that identity
> when it is one this session owns.

Not included in this draft: the original form of this entry also reported
that the pool reconciler retries reassign indefinitely on a held bead
whose lease has expired, instead of taking the `bd reclaim` path its own
error text recommends. The current code does not do this, upstream
included. The release path is liveness-driven, not lease-driven, and it
reopens rather than reassigns. `releaseOrphanedPoolAssignments` releases a
pool-routed bead only when no open session bead maps to its assignee
(`liveOpenSessionAssignmentExists`), clearing it to `open`/unassigned
through a conditional `ReleaseIfCurrent` or a live-rechecked write. There
is no reassign, so no owner-only refusal to loop on, and an unreadable
liveness or work-state read fails closed rather than releasing live work.
`releaseConfirmedOrphanSessionWork` is the tie-break for a seat already
confirmed dead. The reported loop is absent; nothing to file.

The same entry previously reported `gc bd heartbeat` as a no-op on the
lease fields. That is fixed: gc no longer rewrites the verb into a
`gc.last_heartbeat_at` metadata write and forwards to bd's native
heartbeat, which is why the refusal above is now an identity error rather
than a silent success.
