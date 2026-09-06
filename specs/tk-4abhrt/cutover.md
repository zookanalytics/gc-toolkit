# converse cutover (tk-4abhrt): spawn on engagement, board as the attention channel

The converse routed-pool held a live pool claim per visit and dodged the
execution backstop with `nudge=""` + `idle_timeout=0`. An interactive
hold-for-operator sitting is not convergent pool work, so it should not sit in a
work pool at all (design: tk-d3k4qm). The original 3/3 plan — spawn and pin a
session per filed visit — failed three premises against source and live state
(specs/tk-4abhrt/cutover-blockers.md). The operator ruled: **spawn ON
ENGAGEMENT, not on filing.** This is that cutover.

## The model now

A visit is filed and PARKS on the helm board (`gc.routed_to=human`). Nothing
holds it; it waits in the operator's board backlog. The operator draws one off
the board and ENGAGES it: a manual `converse-<model>` sitting spawns, binds the
visit, and the operator converses. `gc-helm dismiss` (2/3) ends the sitting.

The board is the attention channel. `helm-svc board` gathers a bead as a
human anchor when `gc.routed_to == "human"` (exact match:
`services/helm/internal/source/beads.go`), and an open, un-ruled human anchor is
`Owed` — it shows in the operator's backlog (`services/helm/internal/board/derive.go`).
No CORE mechanism renudges a `routed_to=human` bead, and none is needed: the
board IS the durable surface the operator reads.

The session-to-visit binding is the load-bearing primitive that carries over. A
session from `gc session new converse-<model> --alias <visit> --no-attach` is
`session_origin=manual`: not `pool_managed`, exempt from every pool backstop, and
never cycled. `gc-helm engage` captures that session's runtime name from
`--json` and stamps it as the visit's `assignee`; the session's own
`gc hook --claim` then adopts the visit through the ready-assignment path
(`cmd/gc/cmd_hook_claim.go`) with no pool routing at all.

## What changed

1. **`gc-helm engage <bead> [--model opus|fable|codex] [--no-attach]`** — new verb
   in `assets/scripts/gc-helm.sh`. Resolves the sitting's visit (the bead itself
   when it is an open visit; else the one open visit tracking it; else files one),
   spawns the manual sitting, binds the visit to the session's name, and attaches.

2. **Visit routing → the board.** Every gate-visit producer sets
   `gc.routed_to=human` instead of the converse pool: the canonical block
   (`formulas/mol-visit.toml`) and its copies (`gc-helm.sh` open,
   `formulas/mol-first-reaction.toml`, `formulas/mol-feedback-distiller.toml`,
   `agents/proactive/prompt.template.md`). `assets/scripts/escalate.sh` — which
   files ~85 of the ~91 live converse-routed visits — defaults to `human` and
   still repoints stale converse routes to the board; `--pool` overrides it to a
   live pool. `assets/scripts/migrate-lane-states.sh` drops its explicit
   converse `--pool`.

3. **The board picker engages.** `assets/scripts/tmux-pick-helm.sh` (prefix+b)
   runs `gc-helm engage <id> --no-attach` on the picked row instead of
   `gc-helm open <id>`; the operator attaches from the session picker, the way a
   pool sitting was reached before.

4. **No pin.** A `session_origin=manual` converse-opus session survives both the
   config-drift restart and the ~5h max-session-age restart on its own:
   `wake_mode=resume` preserves the thread, and the session stays in the desired
   awake set as long as it is neither closed nor drained
   (`cmd/gc/compute_awake_set.go`). A pin is deliberately stripped from the
   age-restart blocker set (`cmd/gc/session_reconciler.go`) and buys a manual
   session only idle-sleep protection, which converse-opus does not configure.
   So the cutover adds no pin.

5. **The pool holds nothing.** With every producer routing to the board, the
   `gc-toolkit.converse` pool receives no demand and spawns no sessions
   (`min_active_sessions = 0`). The pool is retired in effect. Its
   `agents/converse/agent.toml` is retained pending the follow-up below, which
   removes it and reshapes the tests that read it — the config file's deletion is
   safely separable from the behavioral cutover and keeps this change's blast
   radius testable.

## Rollout runbook (Principle 5: live converse never breaks)

Order matters: engage and the board route land first, the backlog moves second,
and no step mass-spawns.

1. **Land this PR.** The engage verb, the board route, and the picker go live
   together. New visits park on the board and are engageable immediately;
   existing converse-routed visits are untouched and still reachable.
2. **Migrate the backlog.** Run `specs/tk-4abhrt/converse-backlog-repoint.sh`
   once per rig that carries a backlog — at cutover time `gc-toolkit` (~91) and
   `gascity` (1, when it resumes). It is a dry run by default; `--apply`
   re-points every open bead still on the retired pool to `gc.routed_to=human`.
   It is idempotent, so a transient bead on the retired route self-heals on a
   re-run.
3. **Follow-up: remove the config file.** Delete `agents/converse/agent.toml`
   and reshape `assets/scripts/converse-signoff.test.sh` and
   `assets/scripts/pool-demand-wiring.test.sh` (which assert the pool's
   held-sitting config) for the manual-sitting model. Safe once the backlog is
   confirmed empty.

## Follow-ups filed

- **tk-aebufc** — remove `agents/converse/agent.toml` and reshape its
  held-sitting config docs and tests (`converse-signoff.test.sh`,
  `pool-demand-wiring.test.sh`, `docs/gascity-human-engagement.md`, and the
  routing-tier docs) for the manual-sitting model (step 3 above).
- **tk-blytvt** — wire the helm-svc web "open conversation" action and its
  message to spawn-on-engagement; today it files a board-parked visit
  (engageable from the board) rather than spawning a sitting from the web.
- **tk-tiqqcv** — run the backlog migration post-merge (step 2 above).
