# Audit: `gc session reset` vs `gc handoff` usage in instructions

**Bead:** tk-my4za
**Author:** gc-toolkit.rictus (resumed from gc-toolkit.furiosa WIP)
**Branch:** `polecat/tk-my4za`
**Date:** 2026-05-07

## Decision rule

- `gc session reset` → `KillSessionWithProcesses` — destroys the whole tmux
  session (and any co-located panes/windows: scratch clones, helper panes).
  Right choice only when destroying the whole session is genuinely intended.
- `gc handoff` → `respawn-pane` (`gascity/internal/runtime/tmux/tmux.go:2833`)
  — pane-scoped restart of the agent process. Preserves co-located tmux state.
  Default for "restart the agent."

Reset should be the rare case; handoff should be the default for routine
restart.

## Provenance

| Doc-type or artifact | Producer | Source location | Surveyed at |
|----------------------|----------|-----------------|-------------|
| Pack pages (gc-toolkit) | gc-toolkit pack | `polecat/tk-my4za` @ `0c142b1` | 2026-05-07 |
| Agent prompts (gc-toolkit) | gc-toolkit pack | `polecat/tk-my4za` @ `0c142b1` | 2026-05-07 |
| Skill files (gc-toolkit) | gc-toolkit pack | `polecat/tk-my4za` @ `0c142b1` | 2026-05-07 |
| Formula files (gc-toolkit) | gc-toolkit pack | `polecat/tk-my4za` @ `0c142b1` | 2026-05-07 |
| Template fragments (gc-toolkit) | gc-toolkit pack | `polecat/tk-my4za` @ `0c142b1` | 2026-05-07 |
| Asset scripts (gc-toolkit) | gc-toolkit pack | `polecat/tk-my4za` @ `0c142b1` | 2026-05-07 |
| Pack pages (gascity, read-only) | gascity upstream | `rigs/gascity` @ `c7cd79f` | 2026-05-07 |
| CLI reference (gascity, read-only) | gascity upstream | `rigs/gascity/docs/reference/cli.md` @ `c7cd79f` | 2026-05-07 |
| Engineering docs (gascity, read-only) | gascity upstream | `rigs/gascity/engdocs/` @ `c7cd79f` | 2026-05-07 |
| City file | city-level | `loomington/city.toml` (md5 `4b2d61e9...`) | 2026-05-07 |
| Live `gc prime` injection paths | template-fragments + agents/*/prompt.template.md | gc-toolkit pack @ `0c142b1` | 2026-05-07 |
| `gc handoff` source (verification) | gascity upstream | `rigs/gascity/cmd/gc/cmd_handoff.go`, `internal/runtime/tmux/tmux.go:2833` @ `c7cd79f` | 2026-05-07 |

## 1. Inventory

### 1a. gc-toolkit pack (this rig — owned, modify directly)

| File | Line | Surrounding context | Type |
|------|------|---------------------|------|
| `skills/handoff/SKILL.md` | 63 | `Don't invoke for: a wedged or hallucinating agent (recommend \`gc session reset <alias>\` instead)` | Recommendation in alternative-list |
| `skills/handoff/SKILL.md` | 189 | `If during the carry-forward sweep you find yourself reaching for \`/compact\`, \`gc session reset\`, or \`gc session kill\` instead — stop.` | Enumerated alternative |
| `docs/gas-city-reference.md` | 1095 | `gc session reset <name>     # Hard restart: kills host tmux session (use only when destroying co-located state is intended; for routine "restart the agent," prefer \`gc handoff\`)` | CLI cheatsheet entry — already updated by furiosa WIP |
| `docs/gas-city-reference.md` | 1125 | `gc handoff [<target>]                      # Restart the agent (pane-scoped; preserves co-located tmux state); default for "fresh transcript"` | CLI cheatsheet entry — already updated by furiosa WIP |
| `docs/design/consult-session-feasibility.md` | 44–50 | `\`gc handoff\` is the pane-scoped "restart the agent" primitive (preserves co-located tmux state); \`gc session reset\` is the host-session-destroying variant for the rare cases where a clean process tree is required. Either preserves the bead.` | Design-doc explanation — already updated by furiosa WIP |
| `assets/scripts/tmux-spawn-scratch.sh` | 18 | `# They survive \`gc session reset <host>\` (which kills only the host tmux session — not the sibling)` | Architectural comment |
| `assets/scripts/tmux-spawn-scratch.sh` | 84 | `#    Sibling-session model: scratches must survive \`gc session reset <host>\`, which destroys the entire host tmux session (not just pane :^.0).` | Architectural comment |

Negative finding: every agent prompt template
(`agents/{mayor,deacon,witness,refinery,boot,polecat,architect,concierge,
mechanik,consult-host}/prompt.template.md`) and every operational template
fragment (`template-fragments/{cycle-recycle,operational-awareness,
propulsion,...}.template.md`) and every patrol formula
(`formulas/mol-{deacon,witness,refinery}-patrol.toml`) **already** uses
`gc handoff` for the routine-restart path. None recommend
`gc session reset` for routine restart.

### 1b. gascity pack (rigs/gascity — read-only in this bead)

Filtered to text-and-instruction occurrences (excludes `cmd/gc/cmd_session_reset*.go`,
`cmd/gc/session_circuit_breaker.go`, `cmd/gc/session_circuit_breaker_test.go`,
`test/acceptance/...` — those are the command implementation and its tests,
not user-facing instructions).

| File | Line | Surrounding context | Type |
|------|------|---------------------|------|
| `docs/reference/cli.md` | 2178 | `\| [gc session reset](#gc-session-reset) \| Restart a session fresh while preserving the bead \|` | CLI table summary |
| `docs/reference/cli.md` | 2377–2390 | Full `gc session reset` reference page: `Request a fresh restart for an existing session without closing its bead.` | CLI reference page |
| `engdocs/design/worker-conformance.md` | 1523 | `managed fresh-restart requests (\`gc session reset\`, runtime \`request-restart\`, self-handoff restart persistence) now route through \`worker.Handle.Reset\`` | Internal design doc |
| `cmd/gc/session_circuit_breaker.go` | 489 | `Supervisor will NOT respawn. Run \`gc session reset %s\` to clear.` | Operator-facing error message (recovery prompt for tripped breaker) |
| `CHANGELOG.md` | 34 | `\`gc session reset\` now documents its named-session circuit-breaker behavior:` | Historical changelog |
| `examples/...` | (multiple) | Reference example packs | Out-of-scope template content |

### 1c. City-level (`loomington/`)

| File | Line | Surrounding context | Type |
|------|------|---------------------|------|
| `city.toml` | — | No occurrences | (none) |
| `loomington/CLAUDE.md` | — | File does not exist | (none) |

The only top-level files are `city.toml`, `pack.toml`, `probe.out`, and
`rigs/`. None reference `gc session reset`.

### 1d. Live `gc prime` injection paths

`gc prime <agent>` reads `agents/<name>/prompt.template.md` plus the
template fragments declared in `pack.toml` `[global] session_live` and
`global_fragments`. Surveyed:

- All ten gc-toolkit agent prompts (see 1a — all already on `gc handoff`)
- All template fragments under `template-fragments/` (`cycle-recycle`,
  `operational-awareness`, `propulsion`, `command-glossary`,
  `following-mol`, `architecture`, `tdd-discipline`, `capability-ledger`,
  `mayor-concierge-redirect`, `approval-fallacy`, `scratch-clone-guard`)
- city.toml `global_fragments = ["command-glossary", "operational-awareness"]`

No `gc session reset` recommendations are injected via these paths today.
The cycle/recycle and operational-awareness fragments already prescribe
`gc handoff` for the routine cycle path.

## 2. Classification

### gc-toolkit (in-scope, owned)

| Occurrence | Classification | Reason |
|------------|---------------|--------|
| `skills/handoff/SKILL.md:63` | **Keep as reset** | The handoff skill is *correctly* directing the operator to `gc session reset` for a *wedged/hallucinating* agent — that's the case where you genuinely want to destroy and rebuild the process tree without preserving transcript. Handoff would attempt to compose carry-forward from an agent that can't reliably do so. Reset is the right tool for that intent. |
| `skills/handoff/SKILL.md:189` | **Keep as reset** | This is enumerating the alternatives the operator might pivot to mid-skill (`/compact`, `gc session reset`, `gc session kill`) and instructing the agent *not* to silently switch. The mention of reset here is by-name reference, not a recommendation to use it for routine restart. |
| `docs/gas-city-reference.md:1095` | **Switch to handoff (already applied)** | CLI cheatsheet originally said `gc session reset <name>     # Restart fresh, preserve bead`. Furiosa's WIP rewrote it to flag the host-tmux-destroying behavior and steer routine restart to `gc handoff`. Aligns with the rule. |
| `docs/gas-city-reference.md:1125` | **Switch to handoff (already applied)** | CLI cheatsheet originally said `gc handoff [<target>]                      # Hand off to another agent`. Furiosa's WIP rewrote it to make handoff's pane-scoped, preserve-co-located-state semantics explicit, and to mark it the default for "fresh transcript." |
| `docs/design/consult-session-feasibility.md:44–50` | **Switch to handoff (already applied)** | Design doc originally listed reset as the only "re-engage with current bead state" primitive. Furiosa's WIP added handoff as the pane-scoped default and reset as the rare destructive variant. |
| `assets/scripts/tmux-spawn-scratch.sh:18` | **Keep as reset** | Architectural comment explaining *why* the sibling-session model exists — it's a behavioural description of what reset does, not a recommendation for operators. |
| `assets/scripts/tmux-spawn-scratch.sh:84` | **Keep as reset** | Same as line 18. (Note: tk-mjvm9 will revert the sibling-session model after this bead lands; modifying these comments here would conflict with that follow-up.) |

### gascity (read-only — listed for upstream-PR consideration in §4)

See §4. None are flagged as requiring local modification in this bead.

### City-level

No occurrences — nothing to classify.

### gc prime injection

Already handoff-aligned — nothing to classify.

## 3. Applied changes (on `polecat/tk-my4za`)

1. `docs/gas-city-reference.md` — line 1095 reset row now flags the host-tmux
   destruction and steers routine restart to `gc handoff`; line 1125 handoff
   row now describes pane-scoped semantics and "default for fresh transcript."
2. `docs/design/consult-session-feasibility.md` — session-lifecycle bullet
   now positions handoff as the pane-scoped restart primitive and reset as
   the rare destructive variant.

Both edits originated as in-progress work on `gc-toolkit.furiosa` (peer
polecat that crashed mid-task at 2026-05-07 19:01 UTC). Captured as a patch
from furiosa's worktree and committed onto this branch as
`docs(reset-vs-handoff): inherit furiosa's WIP edits` (`0c142b1`).

No further local changes needed: every other gc-toolkit instruction surface
(agent prompts, template fragments, formulas, skills) already uses
`gc handoff` for the routine-restart path. The `skills/handoff/SKILL.md`
references to reset are intentional ("use reset when handoff isn't right";
"don't silently pivot to reset/compact/kill").

## 4. Upstream-PR candidates (gascity)

These would clarify the reset-vs-handoff distinction in upstream
documentation. **Each is a separate operator decision** — they are *not*
modified in this bead.

| File | Line | Suggested change | Priority |
|------|------|------------------|----------|
| `rigs/gascity/docs/reference/cli.md` | 2178 (table) | Update one-liner from `Restart a session fresh while preserving the bead` to flag that reset destroys the host tmux session, and recommend `gc handoff` for routine restart. | High — directly contradicts the new local guidance for operators reading upstream docs. |
| `rigs/gascity/docs/reference/cli.md` | 2377–2390 (page) | Add a "When to use" note: prefer `gc handoff` for routine "restart the agent"; reset is for tripped circuit breakers and intentional whole-session teardown. | High — pairs with the table summary update. |
| `rigs/gascity/cmd/gc/session_circuit_breaker.go` | 489 (error message) | The recovery prompt `Run \`gc session reset %s\` to clear.` is *correct* for a tripped breaker (reset clears the breaker; handoff does not). **No change recommended** — listed for completeness. | (Keep) |
| `rigs/gascity/engdocs/design/worker-conformance.md` | 1523 | Internal design doc grouping reset alongside `request-restart` and self-handoff. **No change recommended** — accurate technical description of routing. | (Keep) |
| `rigs/gascity/CHANGELOG.md` | 34 | Historical entry. **No change recommended.** | (Keep) |

The gascity examples directory (`examples/gastown/packs/...`) was surveyed
and found to already use `gc handoff` (e.g., `overlay/.claude/settings.json`
runs `gc handoff --auto "context cycle"`). No upstream changes recommended
in `examples/` either.

## 5. Open / ambiguous cases

| Item | Why ambiguous | Suggested operator decision |
|------|---------------|------------------------------|
| `agents/deacon/prompt.template.md:160` — "Request target restart" → `gc session kill <target>` | Out of audit scope (concerns `gc session kill`, not `gc session reset`). But operationally the right tool when also delivering carry-forward is `gc handoff --target <target>` — which kills the controller-restartable target *and* posts handoff mail. Worth a follow-up. | File a follow-up bead to switch deacon's "Request target restart" line to `gc handoff --target <target>` (or document that kill-only is intentional when there's no carry-forward to deliver). |
| `assets/scripts/tmux-spawn-scratch.sh` lines 18 and 84 | Comments accurately describe today's behaviour, but the dependent bead **tk-mjvm9** ("Move scratch clones back into the agent's main tmux session") will revert the sibling-session model. Editing these lines now would conflict with that follow-up. | No edit in this bead. tk-mjvm9 owns updating these comments after it reverts the sibling-session model. |

## 6. Verification — probe handoff against a sample agent

The verification done here is **code-level** rather than running a destructive
remote handoff. Reasons: (a) running `gc handoff --target <agent>` would
restart another agent in the city; that's intrusive for an audit verification.
(b) running self-handoff would destroy this polecat's session before it can
finalise the audit.

Verified the documented claims by reading the implementation:

- `gc handoff` source — `rigs/gascity/cmd/gc/cmd_handoff.go` and
  `--help` output. Self-handoff path: send mail + `gc runtime
  request-restart`. Remote handoff path (`--target`): send mail +
  `gc session kill <target>`. Both end-state via the controller's restart
  reconciliation.
- The pane-scoped restart claim resolves through
  `internal/runtime/tmux/tmux.go:2833 RespawnPane` → `tmux respawn-pane -k`
  (kills only the pane process tree; tmux session, other windows/panes,
  and the operator's tmux client all persist).
- Reset's whole-session destruction resolves through
  `KillSessionWithProcesses` (referenced by the dependent bead tk-mjvm9 —
  "Changing gascity-core behavior (`KillSessionWithProcesses` semantics
  stay)"), which kills the entire tmux session.

Conclusion: the local doc updates accurately reflect upstream behaviour.
A live destructive probe is left for tk-mjvm9 follow-up (which will need
to actually demonstrate handoff preserving scratch windows).

## 7. Out-of-scope reminders

- Modifying gascity-core code (upstream candidates only — see §4)
- Re-arguing the session-reset scope decision (closed in tk-2ezog)
- Heavy CI / pre-merge gates (gc-toolkit holds a low bar)
- Moving scratches back into the main session (sibling bead **tk-mjvm9**,
  blocked by this bead — must land before that work begins)
