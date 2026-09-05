---
name: check-set-heal-visibility-test-is-slow-not-hung
description: "check-set-heal-visibility.test.sh takes ~15 min and looks hung with duplicate check-set-heal.sh processes — let it finish, don't kill it"
metadata: 
  node_type: memory
  type: project
  originSessionId: af8d4422-7dba-4d22-9fb8-5b92f70597e2
  modified: 2026-08-02T18:40:38.512Z
---

`assets/scripts/check-set-heal-visibility.test.sh` (gc-toolkit) runs ~15
minutes and completes cleanly (244 assertions as of 2026-08-02). Mid-run it
looks hung: the log stalls for minutes at a time and `ps` shows two or three
identical `bash .../check-set-heal.sh --default codex ...` processes.

Both symptoms are benign:

- The duplicate processes are **command-substitution forks** of the one
  invocation — `$(...)` forks a copy of the script's bash, and `ps` shows the
  child with identical argv. `run_heal` only ever starts one.
- The long stall is the **`PAGE` fixture** (Run 7d), which builds 201 beads and
  drives them through a shell `gc` stub that shells out to `awk` per field. It
  is O(n²) shell work, not a deadlock.

`reconcile-merged-prs.test.sh` is the same shape at ~3-4 minutes — over the
common 120s cap, under any real hang.

**Why:** a pre-open codex review (tk-pka2d) killed both runs at a 120s cap,
reported them as "hung with nested check-set-heal.sh children" and shipped
findings whose verification never completed. Whoever inherits that review has
to re-run them to know anything.

**How to apply:** budget 900-1500s and run them in the background, then read
the tail. Do not kill on a stalled log or on duplicate PIDs — check whether the
log is still growing over a few minutes instead. Concurrent heavy tests steal
CPU and make both worse, so run one at a time when timing matters. See
[[dont-edit-files-under-a-running-background-test]] — the files are also off
limits for edits while a run is in flight.
