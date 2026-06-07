# Binding report: bead-host agent + durable 1:1 bead↔session link (`tk-husu6`)

**Bead:** `tk-husu6` — *Binding: bead-host agent + durable 1:1 bead↔session link*
(child of `tk-n19tp` / epic `tk-q4xaj`, *Bead-Universe Operating Model v1*)
**Branch:** `polecat/tk-husu6` → `integration/bead-universe-v1`
**Phase:** 1 — Binding (the spine). Gated by P0 spike `tk-oml75` (decision **A2**:
binding is the cheap metadata assembly; the durable-state store A3 is NOT pulled
into Phase 1).
**Design refs:** design-doc.md Key Components 1–2, Phase 1; operator refinement
on `tk-husu6` (reverse link is the source of truth).

---

## TL;DR — what shipped

1. **`agents/bead-host/`** — a new city-scoped agent: `consult-host`'s per-bead
   shape (alias = bead id → 1:1 for free) with **`wake_mode = resume`** (carry the
   conversation; the proven `mayor-thread` mechanism) and **`idle_timeout = 8h`**
   (suspend, don't die). Purely interactive: never claims pool work, never a sling
   target. `agent.toml` + `prompt.template.md` + `PROVENANCE.md`.
2. **`tools/gc-bead-host.sh`** — the `gc bead-host <id>` "thin sugar": spawn-or-
   resume the host and write the durable link **atomically on host creation**, plus
   `resolve` / `link` / `unlink` / `lineage` subcommands.
3. **The durable binding** — metadata-only, no schema migration (below).
4. **`tools/bead-host-binding-fixture.sh`** — the automatable half of the
   5-assertion gate (21 assertions, all passing), runnable by a polecat (no live
   sessions). The live half is the operator checklist at the end of this doc.

---

## The binding contract

Metadata-only — beads store metadata as a free-form `map[string]string`, so new
keys cost nothing and there is **no schema migration**. The link spans two
ledgers because the two beads live in two ledgers:

| Side | Bead | Ledger | Keys |
|---|---|---|---|
| **Reverse** (source of truth) | the **session** bead | HQ `lx` (type=session) | `hosts_bead = <work-bead-id>` |
| **Forward** (optional cache) | the **work** bead | rig `tk` | `host_session = <session-bead-id>`, `host_session_name = <session_name>`, `host_session_epoch = <continuation_epoch>` |
| **Lineage** (0..N / replay hook) | the **work** bead | rig `tk` | `gc.session_lineage = <JSON array of {session,name,epoch,at}>` |

**Keyed on the STABLE session identity, never the ephemeral tmux name.** The
stable identity is the **session bead id** + **`session_name`** + **`continuation_
epoch`**. The tmux name goes stale on drain; these do not. `continuation_epoch`
stays *constant* across resume-mode wakes (it bumps only on a `fresh` wake or an
explicit reset), while `generation` bumps on *every* wake — so a change in epoch
is exactly "the conversation lineage was reset," which is what the forward cache's
`host_session_epoch` records and what `gc.session_lineage` accumulates.

**Why reverse-as-source-of-truth** (operator refinement): a *searchable reverse*
link "lays the 1:0..N door open with no schema change" — a bead with zero or many
hosts is just a different search result — while v1 *behaviour* stays 1:1. The
forward pointer is a perf cache only; deleting it never loses the binding.

**Atomicity.** `bd` has no cross-bead transaction, so `gc-bead-host.sh link`
writes the **reverse (source-of-truth) link first**, then the forward cache, then
the lineage, and every write is **idempotent**. A partial failure leaves the
source of truth intact and the whole operation is safe to re-run. The reverse
link alone is sufficient to resolve a host; the forward cache and lineage are
reconstructable from it.

---

## Reverse search — the one implementation caveat

The design specifies reverse resolution as `ListByMetadata hosts_bead=<bead>`.
**That `ListByMetadata` is a Go internal** (`internal/session/metadata_candidates.go:
ExactMetadataSessionCandidates`) used by the controller — it is **not exposed
through any `gc bd` / `gc session` CLI**. Concretely:

- Session beads (`issue_type=session`) live in the HQ `lx` ledger and are
  **addressable by id** (`gc bd show <id>` / `gc bd update <id> --set-metadata`
  both prefix-route to `lx`), **but**
- `gc bd list` **filters the `session` type out entirely** — even with
  `--include-infra` (which only covers agent/rig/role/message). So
  `gc bd list --metadata-field "hosts_bead=<bead>"` **never returns a session
  bead**. (Verified against persistent session beads in `lx.issues`.)

So `gc-bead-host.sh resolve` realizes the reverse search over the only available
CLI surface: it **enumerates `gc session list --json`** (the lone command that
lists session beads — exposing id/alias/session_name/template/state) and
**confirms each candidate's `hosts_bead` by id**, with the forward cache on the
work bead as the O(1) fast path. For v1 (alias = bead id) the enumeration is
**prefiltered** by `alias == <bead>` (a cheap candidate filter, never proof of
hosting) and then **resolved strictly** by confirming the explicit
`hosts_bead == <bead>` source of truth by id — so a still-live session merely
*aliased* to the bead (e.g. after `unlink`, before its session is torn down)
does **not** resolve, and `unlink` genuinely unbinds a live host.

`unlink` runs the same reverse search to find what to clear: it removes the
`hosts_bead` source of truth on every session bead still bound to the work bead,
located via the reverse search and **not** via the forward cache — so a partial
`link` (reverse written, forward not), a manually cleared cache, or the documented
"perf cache only" case still unbinds cleanly. Both surfaces are used: `gc bd list
--metadata-field hosts_bead=<bead>` for listable beads (the design's ListByMetadata)
and the `gc session list` enumerate-and-confirm for real session beads. Depending
on the forward cache here was the PR#98 regression (a missing cache left the reverse
link dangling, so `resolve` kept finding the host and `up` re-woke it).

The fixture proves the design's *intended* mechanism (`ListByMetadata
hosts_bead=X`) works on **listable** beads, so the mechanism itself is verified;
only the *session-bead surface* is missing. **Follow-up `tk-3gga1`** (discovered
here): add a native `gc session list --metadata-field` (or `gc bd
--include-sessions`) so reverse resolution is a single indexed query instead of
enumerate-and-confirm.

---

## The 5-assertion gate — method and status

| # | Assertion | Status | How |
|---|---|---|---|
| 1 | create + dual-link resolves both ways | **AUTOMATED** | fixture: `link` writes reverse+forward; both read back; `resolve` + `ListByMetadata` both find the host |
| 2 | resume carries a distinctive marker across suspend/wake | **OPERATOR** | needs a live LLM host — checklist step 2–3 |
| 3 | survives forced drain/respawn (links persist; resume-carries OR logged-degraded fresh re-prime) | **AUTOMATED (link half)** / OPERATOR (fidelity half) | fixture: links survive a simulated respawn (generation 1→2, epoch preserved) + still resolve; the resume-carries-vs-degraded half is checklist step 4 |
| 4 | reverse-resolvable after drain (search finds the bead's host(s)) | **AUTOMATED** | fixture: `ListByMetadata hosts_bead=X` + `resolve` both find the host; survives the epoch bump |
| 5 | resume reflects a change made DURING suspend (not a stale snapshot) | **AUTOMATED (data half)** / OPERATOR (conversational half) | fixture: a mid-suspend note appears in a freshly-read fed slice; the live host re-reading it on resume is checklist step 5 |
| + | lineage carried from day one (0..N hook) | **AUTOMATED** | fixture: 1 entry after bind, appends on re-bind at a new epoch, idempotent at the same epoch |

The automated half runs with **no live sessions** — a polecat may run it (the
`tk-oml75` / `tk-k9s0k` precedent: a polecat must not spawn/reset live-city
sessions). Run it:

```bash
tools/bead-host-binding-fixture.sh        # 21 assertions; exit 0 iff all pass
```

It creates two throwaway `task` beads (titled `FIXTURE: …`) as stand-ins, links
them, asserts the contract, and closes them on exit. No session beads, no live
city mutation.

**Honesty note (carried from the spike):** assertion 3 passes on *either*
resume-carries *or* the logged-degraded fresh re-prime, so the *automated* link
half does not by itself prove resume *fidelity* across a drain — that is the P0
spike's measurement (`tk-oml75`, decided A2) and the operator checklist below.

---

## Operator confirmatory checklist (the live half)

Run after this PR merges and `gc reload` has loaded the `bead-host` agent. This
is the live-session half of assertions 2, 3, and 5 — modeled on the `tk-oml75`
§C probe, now against the **shipped** agent + tool. Use a real, low-stakes bead.

```bash
cd /home/zook/loomington
BEAD=<a-real-low-stakes-bead-id>

# 1. Create the host + write the durable link (one command).
tools/gc-bead-host.sh up "$BEAD"            # spawn-or-resume + dual-link
tools/gc-bead-host.sh resolve "$BEAD"       # prints: <session-id> <name> <alias> <state>
gc bd show "$(tools/gc-bead-host.sh resolve "$BEAD" | cut -f1)" --json \
  | jq '.[0].metadata.hosts_bead'           # == "$BEAD"  (reverse link, source of truth)
gc bd show "$BEAD" --json | jq '.[0].metadata | {host_session, host_session_name, host_session_epoch, "gc.session_lineage"}'

# 2. Advance once with a distinctive marker (assertion 2 setup).
MARK="PURPLE-NARWHAL-$$"
gc session nudge "$BEAD" "Remember this codeword verbatim for later: $MARK. Acknowledge."
sleep 20; gc session peek "$BEAD" --lines 20      # expect acknowledgement

# 3. Suspend, then wake and check recall (assertion 2).
gc session suspend "$BEAD"; sleep 5
gc session wake "$BEAD"
gc session nudge "$BEAD" "What codeword did I ask you to remember? Quote it exactly."
sleep 25; gc session peek "$BEAD" --lines 25      # PASS iff it quotes $MARK verbatim

# 4. Forced drain/respawn (assertion 3): kill the runtime, confirm links persist
#    and the host re-wakes (resume-carries, OR a logged 'fresh' re-prime).
gc session kill "$BEAD"
tools/gc-bead-host.sh resolve "$BEAD"             # links still resolve (metadata survived)
gc session wake "$BEAD"
gc session nudge "$BEAD" "Recall the codeword again, exactly."
sleep 25; gc session peek "$BEAD" --lines 25

# 5. Resume-reflects-reality (assertion 5): mutate the bead WHILE suspended,
#    then wake — the host's first act (its nudge) is to re-read the bead.
gc session suspend "$BEAD"; sleep 5
gc bd update "$BEAD" --notes "DURING-SUSPEND change: $MARK-2"
gc session wake "$BEAD"
gc session nudge "$BEAD" "Anything change on your bead while you were away? Re-read and tell me."
sleep 25; gc session peek "$BEAD" --lines 25      # PASS iff it reports the new note

# 6. Cleanup.
gc session close "$BEAD"
tools/gc-bead-host.sh unlink "$BEAD"
```

**Pass criteria:** steps 3 and 4 recall `$MARK` verbatim (or step 4 shows a
*logged* `fresh` re-prime, not a silent blank); step 5 reports the during-suspend
change. A silent blank in step 3 ⇒ resume did not carry; attach the transcript
and re-open A2-vs-A3 (`tk-oml75` §C pass criteria).

**Retention TTL (Open Q #2):** repeat steps 1–3 but leave the host suspended for
**days** before waking. Still recalls `$MARK` ⇒ fine; cold/blank ⇒ that suspend
exceeds the provider transcript-retention window — record the duration; this is
the *only* input that flips A2→A3 (the `gc.session_lineage` hook makes that flip
cheap).

---

## Using it

```bash
tools/gc-bead-host.sh up <bead-id>        # land in a bead: create-or-resume its host
tools/gc-bead-host.sh resolve <bead-id>   # which session hosts this bead?
tools/gc-bead-host.sh lineage <bead-id>   # which sessions have hosted it?
```

In Phase 3 the `gc attention open <bead>` launcher becomes the pick-a-row front
door over the same `up` path (design Key Component 4); the binding written here
is what it resolves and resumes.
