---
name: Design-eval — adopt the oversight-rig pack (per-rig project-lead)
description: Composition / cost / escalation / maturity evaluation of gascity-packs oversight-rig v0.1.0 against the gc-toolkit roster, with a recommendation. Verdict — spike on one rig, on_demand, with a mail-to-mayor escalation override; do NOT roll out always-on city-wide, and do NOT treat it as the tk-2r8sp6 solution.
---

# Design-eval: adopt the `oversight-rig` pack (per-rig project-lead)

Evaluation for bead `tk-3s5uo`. **Design doc + recommendation only — no config
change in this bead.**

## Provenance

| Artifact | Producer | Source location (repo path + commit) | Surveyed at |
|---|---|---|---|
| `oversight-rig` pack (README, `pack.toml`) | gascity-packs | `gastownhall/gascity-packs:oversight-rig/` @ `a1490ecf90238f3af52ab2e7f24e30b5b62cbfc2` (v0.1.0) | 2026-06-24 |
| `project-lead` role | gascity-packs | `oversight-rig/agents/project-lead/{agent.toml,prompt.template.md,project-brief.template.md}` @ `a1490ecf9` | 2026-06-24 |
| Escalation machinery | gascity-packs | `oversight-rig/orders/{patrol-project-leads,escalate-rollups}.toml` + `assets/scripts/{nudge-project-leads,has-undelivered-escalates,deliver-rollup}.sh` @ `a1490ecf9` | 2026-06-24 |
| Release metadata | gascity-packs | `registry.toml` → `pack.release` v0.1.0, commit `a1490ecf9`, dated 2026-06-20 | 2026-06-24 |
| Our roster | gc-toolkit pack | `pack.toml`, `agents/mechanik/{agent.toml,prompt.template.md}`, `/home/zook/loomington/city.toml` | 2026-06-24 |
| Strategic context | gc-toolkit rig beads | `tk-2r8sp6` ("Make codex review a structural pipeline gate") | 2026-06-24 |
| RAM grounding | host | `free`, `ps -eo rss` (per-claude-session RSS), `/proc/meminfo` | 2026-06-24 |

## TL;DR / Recommendation

**Spike on ONE rig (`gc-toolkit`), `on_demand`, with a mail/nudge-to-mayor
escalation override. Do NOT adopt city-wide, do NOT run `always`, and do NOT
treat this as the `tk-2r8sp6` solution.**

Four findings drive the verdict:

1. **Escalation is dead out of the box.** The pack's entire outbound path is
   `extmsg` → Slack (`deliver-rollup.sh` POSTs to `/v0/city/.../extmsg/outbound`).
   We have **no Slack/extmsg adapter**. Without one, `severity:escalate` rollups
   are written but never delivered — they pile up undelivered and retry forever.
   The pack ships *only* the role + machinery, "not a Slack bridge" (README).
2. **`always` × 4 rigs is the wrong default for a RAM-constrained host.** That's
   ~1.4–2.0 GB permanently resident (measured per-session RSS ≈ 0.3–0.5 GB), and
   our supervisor self-recycles near 26.6/30 GB under load. The role is
   *stateless-by-design*, so `on_demand` is a natural fit — modulo a one-line
   patch to the patrol script.
3. **It does NOT solve `tk-2r8sp6`.** That goal is making *codex-review dispatch*
   a deterministic, head-SHA-keyed, **no-agent-in-the-loop** pipeline gate.
   `project-lead` is an LLM agent and explicitly stays out of PR review/publish.
   The one genuinely transferable idea is the pack's **condition-trigger
   delivery order** (mechanical, no relay agent) — a pattern we could lift for
   `tk-2r8sp6` *without* adopting this pack at all.
4. **v0.1.0 is 4 days old and one commit deep.** Auditable (we read it end-to-end)
   but unproven. Fine to spike behind a blast-radius wall; not fine to roll to
   four always-on sessions.

The marginal value for us is also smaller than the pack's pitch assumes: our
dispatch is *already* substantially structural (pool routing via
`default_sling_target`, formula pours, owned convoys). What `project-lead`
actually adds is the **per-rig triage judgment** slice — "which ready bead to
sling, what to escalate" — not raw dispatch mechanics.

---

## What the pack is (one-paragraph model)

`oversight-rig` adds one role — **`project-lead`**, `scope = "rig"`,
`mode = "always"`, one per rig — that disaggregates *project-level work scoping*
out of the mayor. Each tick (driven by a 15-min cooldown order that nudges the
sessions) the project-lead reads its rig's `blocked` / `in_progress` / `rollup`
beads plus `<rig>/.gc/project-brief.md`, then (a) **dispatches ready, in-scope
work in its own rig directly** and (b) writes structured **rollup beads** tagged
`severity:info` or `severity:escalate`. A separate **condition-trigger order**
(`escalate-rollups`) mechanically delivers undelivered `severity:escalate`
rollups via `extmsg` and labels them `delivered` — *no second agent decides
escalation-worthiness*. The mayor is unchanged and shrinks to cross-cutting
planning + handling escalations. The pack ships the role + orders + delivery
scripts only; it **requires a Slack/extmsg adapter** for the outbound/inbound
human channel.

---

## 1. Composition with our roster

### vs. mechanik — **no conflict (different altitude)**

`mechanik` is `scope = "city"`, `mode = "always"` — the **structural engineer**.
Its own prompt: *"You don't grind beads like a polecat — you analyze operational
patterns, design improvements, and implement structural changes to the city's
machinery."* It owns formulas, agent configs, **dispatch *patterns***, quality
gates, prompt engineering.

`project-lead` is `scope = "rig"` — an **operator** of the machinery for one rig:
it triages that rig's beads and slings ready work. It owns **dispatch
*execution*** for one rig, not the *design* of dispatch.

These are complementary, not duplicative: mechanik designs *how* work flows;
project-lead *flows* one rig's work through that design. The only seam to watch
is the word "dispatch" appearing in both charters — but mechanik's is
pattern/automation work (filed as beads, reviewed), project-lead's is per-bead
`gc sling`. No collision. Indeed, if we adopt project-lead, *mechanik* is the
right owner of the overlay that wires it in.

### vs. the mayor — **intentional overlap (this is the value prop)**

`project-lead` deliberately assumes the mayor's **per-rig work-triage-and-
dispatch** function. That overlap *is* the point (disaggregation). It is also
carefully bounded so it does **not** collide with what our mayor actually does:

- **Cross-rig routing stays mayor-owned** (prompt: *"In-rig convoys are yours;
  cross-rig convoys are mayor's"*).
- **Publish authority stays mayor-owned** — project-lead *"may NOT push, open,
  edit, or merge PRs — even for work it dispatches."* This preserves our
  polecat-publish-authority rule end-to-end, and leaves our mayor patches
  (`convoy-integration-branch-mayor`, `operator-next-step-trailing`) untouched.
- **Convoy graduation / integration-branch landing stays mayor-owned.**

So the carve-out is clean: project-lead takes *in-rig, ready, non-human-gated*
dispatch + triage; everything our mayor patches actually encode stays with the
mayor.

### Roster-name collision — **none**

`project-lead` does not collide with any existing roster name (mechanik, mayor,
polecat, refinery, witness, deacon, boot, dog, bead-host, proactive,
polecat-codex, `_polecat-gemini`, mayor-thread, mechanik-thread).

### Composition frictions to flag

- **The pack assumes a `gc-sling` wrapper** ("auto-injects `--nudge`") that we do
  not ship; the dispatch recipes would need adapting to our `gc sling`.
- **New per-rig artifact:** `<rig>/.gc/project-brief.md` must be authored and
  maintained for every rig under oversight. If it's missing the role refuses to
  improvise and escalates "needs onboarding."
- **Our dispatch is already structural.** Pool routing (`default_sling_target =
  "<rig>/gc-toolkit.polecat"`), formula pours, and owned convoys already handle
  the *mechanics* of routing filed work. project-lead's marginal contribution is
  the **judgment** layer (what's ready, what's blocked, what to escalate), which
  today is implicit/mayor-held. Real, but narrower than "the mayor does all
  triage" framing in the pack's README.

---

## 2. Cost (RAM / slots)

### What the pack provisions

`pack.toml` ships `[[named_session]] template = "project-lead", scope = "rig",
mode = "always"`. With our four non-HQ rigs (`gc-toolkit`, `signal-loom`,
`gascity`, `shutupandlisten`) that's **four always-on sessions** (HQ/`loomington`
is the city ledger, not a project rig — no project-lead needed).

### Measured RAM

| Quantity | Value (2026-06-24) |
|---|---|
| Host total | 30.6 GB |
| Available now (light fleet) | 18.8 GB |
| Supervisor self-recycle threshold (stated) | ~26.6 / 30 GB under heavy load |
| Per claude session RSS (measured range) | 0.28 – 0.50 GB |
| 23 live claude procs, aggregate RSS | 7.9 GB |
| **4 always-on project-leads (added baseline)** | **~1.4 – 2.0 GB, permanently resident** |

The cost that matters is not the headline number but that it is **fixed and
always-resident** — subtracted from peak headroom even when a rig is idle. We
are not RAM-bound *now* (light fleet), but the constraint bites at peak, exactly
when an extra ~2 GB baseline pulls the 26.6 GB recycle threshold closer.

### Can it run `on_demand`? **Yes — and it's the right lever for us.**

The role is **stateless by design** — the prompt forbids holding context across
ticks: *"Hold context across ticks. Re-derive everything from beads + brief."*
A fresh `on_demand` wake every tick aligns perfectly with that contract; nothing
is lost by draining between ticks.

**One blocker, one small fix.** The cadence driver `nudge-project-leads.sh`
enumerates only `state == "active"` sessions:

```
gc session list --json | jq '... select(.template == $t and .state == "active") ...'
```

A drained `on_demand` session is not "active", so it would be **skipped** — the
triage cadence silently stops. Fix: a one-line overlay so the patrol step
**wakes before nudging** (`gc session wake <session>` for each templated
project-lead, then nudge), or change `mode` to `on_demand` and have the order
`exec` wake-then-nudge. Small, well-contained patch in our pack overlay.

**`on_demand` trade-off:** steady-state RAM drops to ~0 (resident only during
the brief triage tick every 15 min), at the cost of a per-wake spawn +
fresh-`gc prime` token burn × 4 rigs × 96 ticks/day. We are RAM-constrained, not
visibly token-constrained, so trading tokens for RAM is correct.

**Minor caveat:** drained `on_demand` sessions are invisible to the tmux session
picker (`prefix+S`) per our `tmux-pick-session.md` doctrine — the operator can't
jump to a sleeping project-lead. Acceptable.

---

## 3. Escalation without a Slack bridge

### The machinery is 100% extmsg→Slack

`deliver-rollup.sh` is the *only* outbound path. It:

- requires `GC_API_BASE_URL` + `GC_CITY_NAME`;
- resolves a per-rig channel from an **active extmsg binding** (`gc slack
  bind-room`), or falls back to `GC_OVERSIGHT_*` env vars (`provider="slack"`,
  `account_id`, `conversation_id`, …);
- `curl`s a JSON payload to `${GC_API_BASE_URL}/v0/city/${GC_CITY_NAME}/extmsg/outbound`;
- labels the bead `delivered` only on HTTP success, else *"will retry next tick."*

Rollup bodies are even authored in **Slack mrkdwn** (`*bold*`, `_italic_`,
`<url|label>`) because they are "posted to Slack verbatim."

### Where escalation lands for us today: **nowhere**

We have **no Slack/extmsg adapter** in `city.toml` (confirmed — the only
`extmsg` strings on disk are inside the `gascity` *source we fork*, not our
config). Out of the box:

```
project-lead writes severity:escalate rollup
  → has-undelivered-escalates.sh fires the order
    → deliver-rollup.sh runs → no extmsg endpoint / no binding → FAILS
      → bead stays undelivered → retried every tick, forever, unseen
```

That is a **silent escalation failure**: the human is never paged, and the
"audit trail" beads accumulate. This is the single biggest blocker to adoption.

### Two ways to make escalation land — and what each costs

1. **Adopt a Slack stack** (`slack-full`/`slack-channel`/`slack-mini` + extmsg
   outbound + per-rig `bind-room`). This is what the pack expects, and gives the
   pack's headline property: **deterministic escalation to a human channel with
   no relay agent.** Cost: stand up + operate a Slack integration we don't have
   today — a much larger commitment than this eval's scope.
2. **Override the delivery to mail/nudge the mayor.** Replace `deliver-rollup.sh`
   with a variant that `gc mail send mayor` / `gc session nudge mayor` for each
   undelivered escalate rollup. Cheap; uses channels we already run.

### Does it relieve the mayor, or add a layer?

- The pack's "**no relay agent**" benefit is real *only when escalations go to a
  human channel* (option 1). Route them to the **mayor** (option 2) and you've
  reintroduced an agent into the escalation loop — a different one (mayor as
  *escalation handler*, not *dispatch relay*).
- Even so, it's a **net relief** *if* the mayor's current per-rig **routine
  triage** volume is high: project-lead absorbs the routine, and only genuine
  `severity:escalate` items reach the mayor. That is precisely the intended
  division of labor (mayor = escalations + cross-cutting). The relief is real to
  the exact degree that routine triage currently consumes the mayor — which the
  spike is designed to measure.

### Relationship to `tk-2r8sp6` (read this carefully)

The bead framing — *"targets the structural-dispatch goal in tk-2r8sp6 (review
dispatch should be structural, not mail-to-mayor relay)"* — conflates two
different bottlenecks:

- **`tk-2r8sp6` is about *codex-review* dispatch:** make it a deterministic,
  **head-SHA-keyed, idempotent, no-agent-in-the-loop** pipeline gate (the PR#80
  incident: 7 review beads on one head, an LLM flipping a clean head to
  REQUEST_CHANGES). `project-lead` is an LLM agent and **explicitly stays out of
  PR review/publish** — it does *not* make codex review structural. Review
  dispatch is a refinery concern; adopting oversight-rig leaves `tk-2r8sp6`
  exactly where it is.
- **The transferable idea:** oversight-rig's `escalate-rollups` order *is* the
  structural pattern `tk-2r8sp6` wants — a `condition` trigger that mechanically
  acts on a bead label with **no second agent deciding**. We could lift that
  pattern (condition-trigger order keyed on a head-SHA review bead) to satisfy
  `tk-2r8sp6` **without adopting `project-lead` at all.** That is the most
  valuable thing this pack teaches us, and it's orthogonal to the role.

---

## 4. Maturity

| Signal | Value |
|---|---|
| Version | v0.1.0 (only release in `registry.toml`) |
| Commit history under `oversight-rig/` | **one** commit, `a1490ecf9` |
| First (and only) commit date | 2026-06-20 — **4 days** before this eval |
| Bug-fix / iteration history | none |
| Evidence of production use beyond author | none |

**Auditable but unproven.** The pack is small and fully legible — 1 agent, 2
orders, 4 scripts, 1 brief template, all read end-to-end for this eval — which
*lowers* black-box risk. But the *behavior* is untested at scale, and there are
concrete immaturity smells:

- `deliver-rollup.sh` assumes a `gc slack bind-room` / `extmsg/outbound` surface
  we'd have to stand up to use as designed.
- The prompt references a `gc-sling` wrapper that is not part of the pack.
- Rollup bodies must match an **exact** template in **Slack mrkdwn** or *"your
  rollup will not be deliverable"* — an LLM emitting format-exact beads every
  tick is a standing reliability risk.

Posture: spike behind a blast-radius wall (one rig, `on_demand`); revisit
always-on / city-wide only after the pack matures past v0.1.0 *and* the spike
shows value.

---

## 5. Recommendation

**Spike `oversight-rig` on `gc-toolkit` only, `on_demand`, with a
mail/nudge-to-mayor escalation override. Decline the always-on × 4 city-wide
rollout. Do not treat this as the `tk-2r8sp6` solution.**

### Why spike rather than decline outright

A contained spike is cheap (one rig, `on_demand` ≈ ~0.5 GB transient, zero Slack
dependency) and answers the one question the desk-analysis can't: **does per-rig
triage disaggregation measurably reduce the mayor's load for *us*, given our
already-structural dispatch?** That's worth a bounded experiment. A full
city-wide always-on rollout is not, on today's evidence.

### Why not adopt as-shipped

- Escalation path is dead without Slack (§3) — needs an override or a whole Slack
  stack.
- `always` × 4 erodes peak RAM headroom we can't spare (§2).
- v0.1.0 / 4-day-old / 1-commit (§4).
- Doesn't move the headline strategic goal `tk-2r8sp6` (§3).

### Concrete spike plan (a follow-up impl bead, not this one)

1. **Rig:** `gc-toolkit` (best-understood, highest bead volume, blast radius we
   control).
2. **Import** `oversight-rig` at pin `a1490ecf90238f3af52ab2e7f24e30b5b62cbfc2`
   (v0.1.0) **for that one rig only**, via `[rigs.imports]` in `city.toml`.
3. **Override `mode = "on_demand"`** and overlay `nudge-project-leads.sh` to
   **wake-before-nudge** (§2) so the cadence survives draining.
4. **Override escalation delivery:** replace `deliver-rollup.sh` with a
   mail/nudge-to-mayor variant (§3 option 2). **Do not pull in a Slack pack for
   the spike.**
5. **Author** `rigs/gc-toolkit/.gc/project-brief.md` from the template.
6. **Run ~1–2 weeks.** Success metrics:
   - mayor's per-rig triage/dispatch actions for `gc-toolkit` measurably drop;
   - project-lead rollups surface *real, actionable* items (low false-escalate
     rate — watch for format-drift / undeliverable beads);
   - no RAM regression at peak.
7. **Decide** at spike-end: extend to other rigs (and settle the
   Slack-vs-mail-to-mayor escalation-channel question), or remove.

### Orthogonal win to capture regardless

Independent of adopting the role, lift the **condition-trigger delivery-order
pattern** (mechanical action on a bead label, no relay agent) as the
implementation model for `tk-2r8sp6`'s structural codex-review gate. That is the
durable lesson from this pack and does not require importing it.

---

## Appendix — install delta if we proceed with the spike

| Step | Artifact | Owner |
|---|---|---|
| Import (one rig) | `city.toml` `[rigs.imports.oversight-rig]` @ `a1490ecf9` | mechanik (city.toml direct-edit) |
| `mode = on_demand` | `[[named_session]]` override | mechanik |
| Wake-before-nudge | overlay of `nudge-project-leads.sh` (or order `exec`) | dispatched polecat |
| Escalation → mayor | overlay of `deliver-rollup.sh` → `gc mail`/`gc session nudge mayor` | dispatched polecat |
| Per-rig brief | `rigs/gc-toolkit/.gc/project-brief.md` | mechanik + operator |
| Reload | `gc supervisor reload` | mechanik |

**Not required for the spike:** any Slack/`slack-*` pack, `extmsg` outbound
config, `GC_OVERSIGHT_*` env vars, `gc slack bind-room`.
