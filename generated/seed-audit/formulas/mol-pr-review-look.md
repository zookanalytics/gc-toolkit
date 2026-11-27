Formula: mol-pr-review-look
Description: A review run's fresh look (formulas/mol-pr-review.toml): a session that is never
the round's ruler reads the whole review once the run's account calls for it,
at every third round, when the round's must-fix findings stop falling or one
comes back a second time, and at the run's last round by its bound. It sends the
review on to its next round, or stops it for a person's answer with one framed
question. The run's rule-and-repair bonds one look through its on_complete
fan-out, with the vars below, on the run's review pool, so the round's ruler,
who runs on the repair pool, never takes it. A look that stops the review files
its question on the bead that owns the PR and closes failed hard, which ends the
run's loop at that round without its check (formula-spec-v2.md, section 3.1).
A look is compiled when it is bonded, from the pack installed then, so it reads
its run only through the store, never through text the run was poured with. The
design is specs/tk-vdyedm5/design.md.


Variables:
  {{binding_prefix}}: The binding the city imports the pack under, with its trailing dot: the prefix of the pack's skill names, and with no dot the name of its commands. The bond passes it, as a bond compiles with only the vars it lists. (default=gc-toolkit.)
  {{head}}: The head the round judged, whose rulings the look follows. (default=)
  {{review_target}}: The pool the look runs on, the run's review pool. (default=)

Steps (2):
  ├── mol-pr-review-look.main.look: Take a fresh look at the review of 
  └── mol-pr-review-look.workflow-finalize: Finalize workflow [needs: mol-pr-review-look.main.look]
