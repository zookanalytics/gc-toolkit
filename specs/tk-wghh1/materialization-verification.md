---
name: signoff-review materialization verification
description: What was and was not verifiable pre-merge about the signoff-review skill reaching both the claude and codex skill sinks, and the one check to run once the branch lands.
---

# signoff-review materialization verification (tk-wghh1)

The branch adds `skills/signoff-review/SKILL.md` and claims the method
becomes available to **any** polecat holding a review bead, under either
provider. The pre-open signoff for this branch (review bead `tk-2kzru`)
flagged that the live half of that claim is not observable before the
branch merges. This note records what the evidence does cover, and the
check that closes the rest.

## Why it is not fully checkable pre-merge

Skill materialization reads the rig checkout that the city has
registered — not a branch worktree. Every path `gc skill list` reports
resolves under `/home/zook/loomington/rigs/gc-toolkit/`, so a skill
added on `polecat/tk-wghh1` is invisible to it until the branch is on
that checkout. Making it visible early would mean editing the canonical
checkout, which polecats must not do.

So a branch-local `gc skill list` smoke is not available here, and none
was invented for this branch.

## What was verified pre-merge

Observed 2026-08-02 against the canonical checkout at `5e44209`:

- `skills/` holds five skill directories: `demo-capture`,
  `filing-documentation`, `gc-demo-script`, `handoff`, `session-title`.
- `.claude/skills/` and `.codex/skills/` each contain **exactly** those
  five, as `gc-toolkit.<dir-name>` symlinks pointing at
  `rigs/gc-toolkit/skills/<dir-name>`.
- `pack.toml` names no skills. Materialization keys off the pack-root
  `skills/<name>/SKILL.md` layout, not per-skill registration, and is
  uniform across both vendor sinks.

A new pack-root skill directory is therefore the whole of what the
mechanism consumes: `skills/signoff-review/` has the same shape as the
five that demonstrably reach both sinks. That is structural evidence,
not an observation of this skill materializing.

## The post-merge check

Once the branch lands and the sinks refresh (`gc start`), one command
settles it:

```bash
ls -d /home/zook/loomington/rigs/gc-toolkit/.claude/skills/gc-toolkit.signoff-review \
      /home/zook/loomington/rigs/gc-toolkit/.codex/skills/gc-toolkit.signoff-review
```

Both paths present — symlinked to `skills/signoff-review` — confirms the
claim. If either is missing, the skill is filed correctly but a sink is
not picking it up, which is a materializer question rather than a defect
in this branch's content.
