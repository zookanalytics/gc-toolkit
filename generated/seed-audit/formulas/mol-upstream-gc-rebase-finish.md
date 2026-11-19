Formula: mol-upstream-gc-rebase-finish
Description: Finish a gascity rebase once the operator has answered the gate that asks them
to land it. No agent force-pushes the fork's main: `mol-upstream-gc-rebase`
ends by filing that gate on the rebase bead, assigned to the operator, and
arming the bead to run this formula once the gate clears.

Its one step runs the landing check, `rebase-landing.sh finish`, which reads
what the operator's push did and records the outcome on the bead. A bead whose
push landed closes with Gas City's work record of the landing
(`gc.work_outcome=shipped`), and the rig checkout follows when that discards
nothing. A bead whose push has not run is asked about again.
A bead whose main moved after the rebase goes back to its keeper with
`aborted_at=race-loss`. The script's header holds the rules.

Variables:
  {{binding_prefix}}: The binding the city imports gc-toolkit under, with its trailing dot. This sub-pack's formulas run on gc-toolkit's polecats, so gc sling pours them with that binding, and a step drops the dot to call the pack's scripts as gc <binding> scripts-dir prints them. (default=gc-toolkit.)

Steps (2):
  ├── mol-upstream-gc-rebase-finish.finish: Check the operator's push, then close the rebase bead, ask again, or hand it to the keeper
  └── mol-upstream-gc-rebase-finish.workflow-finalize: Finalize workflow [needs: mol-upstream-gc-rebase-finish.finish]
