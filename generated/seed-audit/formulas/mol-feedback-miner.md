Formula: mol-feedback-miner
Description: feedback miner — sweep THIS rig's recently merged/closed PR review threads and
record what they say as observation beads (the §1 contract in
specs/2026-08-learning-system/implementation-design.md). The miner is the
learning system's cold-capture surface, and it makes two captures:

- **The outside capture.** Every review post from outside the city becomes one
  condensed observation, `obs.category=outside-review`, whether or not it is
  about standing behavior. A post is outside when it carries no city mark and
  another login posted it, or when it is Claude Code's `/code-review` output
  posted under the city's own login. The distiller reads these observations as
  a set, for what the city's review missed (skills/learning-distill/SKILL.md).
- **The standing-behavior capture.** The city's own posts in the window, its
  reviewers' verdicts and findings among them, are read for corrective feedback
  about standing agent behavior that self-report missed.

The outside capture is the only one that reads an outside post, and the
standing-behavior capture reads only the city's own posts, so the miner never
files two observations of one post's point. `assets/scripts/feedback-miner.sh`
does the mechanical half: it reads the PRs, tells where each post came from,
flags a city post that lacks its mark, and files the observations. This
formula's agent does the reading: it condenses each outside post into a
statement and judges the city's posts.

It runs in EVERY importing rig — there is deliberately no home-rig gate
(decision D5): each rig mines its own repo into its own bead store, and the
distiller (a separate order) reads the observations cross-rig.

The miner files observations, and one patrol finding when a city post lacks its
mark. It never files a pattern bead or a prompt-update proposal, and never edits
a prompt, fragment, or skill. Recording is the whole job; judging is the
distiller's.

Precision over recall governs the standing-behavior capture, with the base rate
in view: most of the city's posts are about the diff in front of them, and are
NOT observations. Its distinction is generalizability: would this feedback
apply to future changes, not just this one? Its expected yield is zero or a few
beads a run, and a run filing many is a smell that the distinction is being
skipped. The outside capture has no such distinction: it files one observation
per outside post, so its count follows how much outside review the window saw.

Every step closes its own bead through `assets/scripts/step-close.sh --step
<step-id>` (resolved into `$SC` at the top of each shell block) — never any
other way, and never on an id read from the environment; the helper resolves
by (gc.root_bead_id, gc.step_ref) and refuses when it cannot prove which
molecule it is executing (then, and only then, pass `--root <root_bead_id>`
from your own `gc hook --claim --json`; the `--bead <bead_id>` from that same
claim is a hint inside that root, never a way to establish one).


Variables:
  {{max_obs_per_run}}: Maximum observation beads the standing-behavior capture files per run. Candidates beyond the cap are dropped with a logged count; the window re-covers them next run. The outside capture files one observation per outside post and has no cap. (default=10)
  {{miner_window_days}}: Sweep window in days: merged or closed PRs updated within the last N days are read, and earlier ones while the outside capture still owes them (outside_backfill_days). The standing-behavior capture reads the PRs that closed within the window. Windows overlap across runs by design — dedup on (obs.provenance, obs.category) makes re-reading a post idempotent, and the overlap is what makes a capped or interrupted run naturally resumable. (default=3)
  {{outside_backfill_days}}: How far back a rig's first run starts the outside capture. The rig's store records the day from which the capture still owes a read of every PR updated since, and every run reads back to it. After each run the day moves to the oldest last update among the PRs the run still owes, one that did not read or has an outside post not yet recorded, or to the run's own day when it owes none, so a back-fill one run could not finish, or a PR that did not read, is read again by the next run. (default=30)

Steps (3):
  ├── mol-feedback-miner.load-context: Prime, resolve the repo, and confirm gh is usable
  ├── mol-feedback-miner.mine-and-file: Sweep the window's PR conversations, condense the outside posts, judge the city's, and file observations [needs: mol-feedback-miner.load-context]
  └── mol-feedback-miner.workflow-finalize: Finalize workflow [needs: mol-feedback-miner.mine-and-file]
