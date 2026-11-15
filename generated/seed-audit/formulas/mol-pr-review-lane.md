Formula: mol-pr-review-lane
Description: One lane of a review run (formulas/mol-pr-review.toml): the check triage picked
at a head, run by the check's own method at that head in a worktree of its own,
which writes its verdict and findings as its output. The run's triage bonds one
lane per check it picks, through its on_complete fan-out, with the vars below,
so each lane's text names its check and head. A lane is compiled when it is
bonded, from the pack installed then, so it reads its run only through the
store and the run's workspace, never through text the run was poured with.


Variables:
  {{binding_name}}: The same binding with no dot, which names the pack's commands (gc <binding_name> scripts-dir). (default=gc-toolkit)
  {{binding_prefix}}: The binding the city imports the pack under, with its trailing dot: the prefix of the pack's skill names. (default=gc-toolkit.)
  {{check}}: The check this lane runs, a name from the check index at the head. (default=)
  {{head}}: The head the lane reviews, the head triage judged. (default=)
  {{review_target}}: The pool the lane runs on, the run's review pool. (default=)

Steps (2):
  ├── mol-pr-review-lane.main.lane: Review  as the  lane
  └── mol-pr-review-lane.workflow-finalize: Finalize workflow [needs: mol-pr-review-lane.main.lane]
