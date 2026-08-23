Formula: mol-do-work
Description: Simple work formula — read the bead, do what it says, close it.

This is the minimal work lifecycle for coding agents. No git branching,
no worktree isolation, no refinery handoff. The agent reads the bead's
description, implements the solution in the current working directory,
and closes the bead when done.

Use this for demos and simple single-agent workflows. For production
multi-agent setups with worktree isolation, use mol-polecat-commit
instead (or mol-polecat-work from the gastown pack for full refinery
review).

## Variables

| Variable | Source | Description |
|----------|--------|-------------|
| convoy_id | runtime | Input convoy tracking the single work bead |


Steps (3):
  ├── mol-do-work.do-work: Read assignment, implement, verify, commit, and close
  ├── mol-do-work.drain: Close drain step and signal completion [needs: mol-do-work.do-work]
  └── mol-do-work.workflow-finalize: Finalize workflow [needs: mol-do-work.drain]
