Formula: mol-review-leg
Description: Generic review-leg helper for planning workflows.

Use this when a coordinator wants to fan out analysis work to polecats without
feature-branch/refinery behavior. The assignment bead description contains the
actual review prompt; this formula standardizes how the worker returns results:

1. Read the bead and any referenced artifacts
2. Perform the requested analysis
3. Persist the FULL report to the bead notes
4. Mail the coordinator recorded on the bead metadata
5. Close the bead and drain the session

Review legs are analysis-only. Do not create synthetic/test beads, route new
work, assign or reassign unrelated beads, or run live mutation experiments to
"observe" behavior. The only allowed bead mutations are the formula-prescribed
updates to the review bead itself, the completion mail, and the final drain ack.
When the assignment contains a plan, checklist, or procedure, treat that text as
the subject being reviewed. Do not execute those listed steps unless the
assignment explicitly says this review leg must execute them.

This keeps review findings durable in beads instead of transient pane output
or per-worktree scratch files.


Steps (4):
  ├── mol-review-leg.load-assignment: Read the review assignment and metadata
  ├── mol-review-leg.write-report: Perform the analysis and store the full report on the bead [needs: mol-review-leg.load-assignment]
  ├── mol-review-leg.notify-close: Notify the coordinator, close the bead, and drain [needs: mol-review-leg.write-report]
  └── mol-review-leg.workflow-finalize: Finalize workflow [needs: mol-review-leg.notify-close]
