# Staging host runbook — gc-next on a fresh macOS city

The operator's stage-1 plan, written from known truth: a macOS host
running Gas City **from upstream main (not the fork)** — deliberately, as
the strongest test of O1's compose-as-shipped claim — with the
Signal-Loom rig's real bead history imported. Install facts below were
extracted from the Gas City repo's own docs at clone `3e629ad`
(`docs/getting-started/installation.md`, `docs/tutorials/01`,
`docs/reference/cli.md`, pack-spec §1.2.3); everything marked *(verify)*
is a doc-trails-main risk to confirm on the host.

**Scope of this first run: observe-first.** It validates chains, demand,
conversation turns, build-and-handoff, doctor, and the stage-1 list. It
does **not** validate landing end-to-end — the merge/gating script family
is a PORTS.md pending item, so hand-offs are *expected to queue at
gating*; that is the designed state, not a routing bug. And until the
old city's Signal-Loom rig is paused, this host must have **no ability to
act on shared PRs** (§5).

## 1. Host setup (macOS)

```bash
brew install tmux jq git dolt beads flock gh icu4c   # flock is NOT shipped by macOS
# dolt >= 2.1.0 final (CI pins 2.1.7); bd >= 1.0.0 (pin v1.1.0); Go 1.26+
git clone https://github.com/gastownhall/gascity.git && cd gascity
make install          # -> $(GOPATH)/bin/gc; Makefile handles Darwin icu4c CGO flags
command gc version    # `command`: Oh My Zsh aliases gc to git commit
```

macOS notes from the docs: the supervisor installs as a launchd agent
(`~/Library/LaunchAgents/com.gascity.supervisor.plist`) at `gc init`;
after rebuilding gc, `gc service restart`. Optional codesigning
(`GC_SIGN_IDENTITY` / `GC_ADHOC_SIGN=1`) keeps TCC grants across
rebuilds.

## 2. City creation

```bash
gc init ~/nx-city --default-provider claude
# no `gc up` exists: the supervisor starts the city before init returns.
gc status && gc dashboard      # SPA on http://127.0.0.1:8372
```

The bundled core pack arrives automatically (control-dispatcher included
— its serve loop is materialized by the controller on demand; **do not
start it by hand**, and `stopped` in `gc status` while idle is normal).
Orders fire from the controller. `gc doctor --fix` restores builtin
imports if anything is missing.

**Codex provider** (wright-codex needs it): register in `city.toml` —
`[providers.codex]` with `base = "builtin:codex"` *(verify the builtin
name on the host)* — and confirm the Codex CLI is installed and
authenticated before expecting review demand to be served.

## 3. Wire gc-next

Clone this repo on the host (say `~/src/gc-toolkit`), then in the city's
`city.toml`:

```toml
[[rigs]]
name = "signal-loom"
# prefix MUST match the old city's Signal-Loom prefix — bead IDs resolve
# through it. Read it off the old city's config before creating anything.

[rigs.imports.gc-next]
source = "~/src/gc-toolkit/packs/gc-next"   # (verify: relative-vs-absolute path resolution)

[agent_defaults]
default_sling_formula = "mol-nx-work"   # the stage-4 repoint, done at birth (fresh-city path)
```

Then `gc doctor --fix` and expect the `check-nx-*` suite in the output.
Two staging gates stay **off** until wanted: `GC_NX_STATUS` (status bar)
and `GC_NX_OUTRIDER_ENABLED` (first reactions) — both default inert.

**Merge strategy — flagged gap:** upstream documents **no config-level
default**; `--merge direct|mr|local` is per-invocation (`gc sling`,
`gc convoy create`). gc-toolkit's own history assumed a city default via
env (`GC_DEFAULT_MERGE_STRATEGY`, set in wright/outrider `[env]`).
*(verify which one the current main actually honors; until then, pass
`--merge mr` explicitly on anything that matters.)*

## 4. Import the Signal-Loom beads

The sanctioned move path (cli.md `gc rig add --adopt`): copy the rig's
fully-initialized `.beads/` (must contain `metadata.json` and
`config.yaml`) into the project checkout on the new host, then:

```bash
git clone <signal-loom-repo> ~/src/signal-loom
cp -R <old-host>/signal-loom/.beads ~/src/signal-loom/.beads   # rsync/scp from the old rig dir
gc rig add ~/src/signal-loom --name signal-loom --prefix <same-as-old> --adopt
gc doctor
```

`--adopt` adopts the existing store, skips init, and runs a
non-destructive config sync for managed-Dolt rigs. (JSONL archive and
`dolt backup sync` exist as fallbacks; the directory copy + adopt is the
documented primary.)

### 4a. The re-route pass — imported beads carry dead routing

Every open bead stamped with old-world routing matches nothing here
(exact-match read side): work routed to `signal-loom/gc-toolkit.polecat`
or assigned to sessions that no longer exist will sit silently. After
adopt, run a sweep — draft below, **verify per-command on the host
before trusting it** (it is written from the CLI contract, not from a
run):

| Old state | Transform |
|---|---|
| open, `gc.routed_to=signal-loom/gc-toolkit.polecat` (or bare `gc-toolkit.polecat`) | re-stamp `gc.routed_to=signal-loom/gc-next.wright` |
| open, routed to `gc-toolkit.proactive` | clear routing (outrider is gated off; re-flag later if wanted) |
| `in_progress`, assignee = any old session | the session is gone: `--status=open --assignee=` and re-route to `signal-loom/gc-next.wright` (the witness-recovery shape) |
| gating anchors (`merge_result` set, assignee/route empty) | **leave untouched** — detached-by-design; the (ported) lander machinery reads the same fields |
| open, `gc.routed_to=human` | convert to a turn when conversations go live (ruling #17), or leave parked for the liveness sweep to card |
| closed beads | never touched — history does not un-happen |

```bash
# DRAFT — dry-run first (print, don't write), and verify flag shapes.
gc bd list --db ~/src/signal-loom/.beads --status=open --json |
  jq -r '.[] | select((.metadata["gc.routed_to"] // "") | test("gc-toolkit\\.polecat$")) | .id' |
  while read -r id; do
    gc bd update "$id" --set-metadata "gc.routed_to=signal-loom/gc-next.wright"
  done
```

## 5. The observe-first guard (two landers, one repo)

Until the old city's Signal-Loom rig is **paused**, both cities believe
they own the same PRs. The single-writer guarantee is per-city; nothing
defends against a second city. For the first run:

- give this host **no push credential** to the Signal-Loom remote (gh
  unauthenticated or a read-only token), and
- do not port/enable the merge machinery yet (it is ports-pending
  anyway).

Give the host teeth only after the old rig is suspended
(`--start-suspended` exists on `gc rig add` if you want the new rig
inert at registration instead).

## 6. First-run checklist, in order

1. `gc doctor --fix` clean (core + `check-nx-*`).
2. **Chains seed**: the `nx-patrol-anchor` order fires within the hour
   (or force one round: sling `mol-nx-patrol-anchor` at
   `signal-loom/gc-next.sentry`); `check-nx-patrol-chain-liveness` goes
   green.
3. **A sentry cycle turns**: claims its cycle bead, orients against the
   imported history (the re-route pass gives it real orphans to find),
   files its successor, drains.
4. **Build-and-handoff**: file one small test bead routed to
   `signal-loom/gc-next.wright`; watch demand spawn a wright, build on a
   worktree, hand off; the anchor queues at gating (expected — see
   scope).
5. **A conversation**: run `mol-nx-turn` against any imported bead;
   watch a converse session spawn, self-title, rebuild the slice, and
   hold; ratify something trivial; confirm the outcome lands in the
   subject's notes and only the turn closes; file a second turn while
   warm (vacuum) and a third after drain (cold reconstitute).
6. **The stage-1 verification list** (implementation-notes.md, nine
   items — two already source-answered, run-once confirmations): most
   matter here, especially pour-time `run_target` resolution (does a
   materialized `mol-nx-work` step get claimed?), the same-layer
   `[[patches.agent]]` overlay staging onto converse, and the v1
   `condition` gating in the health patrol.
7. Then decide: port the merge family and give the host teeth, or file
   findings first.

## 7. What "it works" means for this run

Chains stay live unbabysat across a day (anchor + liveness check
agreeing); imported history is claimable and honest (no silent
sits-forever beads after the re-route pass); a conversation survives
warm→cold against a real bead; the stage-1 unknowns become knowns. Every
failure found here is a finding to file against the branch — the whole
point of running on stock upstream main is that "works only on the fork"
is itself a result.
