Formula: mol-feedback-miner
Description: feedback miner — sweep THIS rig's recently merged/closed PR review threads for
corrective feedback about *standing* agent behavior and record each hit as one
observation bead (the §1 contract in
specs/2026-08-learning-system/implementation-design.md). The miner is the
learning system's cold-capture surface: it catches the feedback that
in-conversation self-report missed. It runs in EVERY importing rig — there is
deliberately no home-rig gate (decision D5): each rig mines its own repo into
its own bead store, and the distiller (a separate order) reads the
observations cross-rig.

The miner files observations ONLY — never pattern beads, never prompt-update
proposals, never an edit to a prompt, fragment, or skill. Recording is the
whole job; judging is the distiller's.

Precision over recall, with the base rate in view: most review comments are
about the diff in front of the reviewer — a bug, a wrong approach, ordinary
discussion — and are NOT observations. The capture distinction is
generalizability: would this feedback apply to future changes, not just this
one? The expected yield of a run is zero or a few beads; a run filing many
observations is a smell that the distinction is being skipped, not a good
harvest.

Every step closes its own bead through `assets/scripts/step-close.sh --step
<step-id>` (resolved into `$SC` at the top of each shell block) — never any
other way, and never on an id read from the environment; the helper resolves
by (gc.root_bead_id, gc.step_ref) and refuses when it cannot prove which
molecule it is executing (then, and only then, pass `--root <root_bead_id>`
from your own `gc hook --claim --json`; the `--bead <bead_id>` from that same
claim is a hint inside that root, never a way to establish one).


Variables:
  {{max_obs_per_run}}: Maximum observation beads to file per run. Candidates beyond the cap are dropped with a logged count; the window re-covers them next run. (default=10)
  {{miner_window_days}}: Sweep window in days: PRs merged or closed within the last N days are read. Windows overlap across runs by design — dedup on (obs.provenance, obs.category) makes re-reading a comment idempotent, and the overlap is what makes a capped or interrupted run naturally resumable. (default=3)

Steps (3):
  ├── mol-feedback-miner.load-context: Prime, resolve the repo, and confirm gh is usable
  ├── mol-feedback-miner.mine-and-file: Sweep the window's PR conversations, classify, dedup, and file observations [needs: mol-feedback-miner.load-context]
  └── mol-feedback-miner.workflow-finalize: Finalize workflow [needs: mol-feedback-miner.mine-and-file]
