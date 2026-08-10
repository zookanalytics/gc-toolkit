{{ define "polecat-append-notes" }}
### Done-sequence notes are APPENDED, never replaced

**This section supersedes every `--notes` in the done sequence above** —
both copies of it (`### The Done Sequence` near the top and
`## FINAL REMINDER: RUN THE DONE SEQUENCE` at the bottom) and the same
text again in the `mol-polecat-work` `submit-and-exit` step. They are one
instruction written three times, so the correction applies to all three.

Wherever the done sequence writes `--notes`, write `--append-notes`:

```bash
# WRONG — destroys whatever was already in notes
gc bd update <work-bead> \
  --set-metadata branch=$(git branch --show-current) \
  --set-metadata target={{ .DefaultBranch }} \
  --notes "Implemented: <brief summary>"

# RIGHT
gc bd update <work-bead> \
  --set-metadata branch=$(git branch --show-current) \
  --set-metadata target={{ .DefaultBranch }} \
  --append-notes "Implemented: <brief summary>"
```

The same substitution applies to the `auto_push=false` halt-at-branch-ready
arm (`--notes "Branch ready: ..."` → `--append-notes "Branch ready: ..."`).

**Why.** `--notes` REPLACES; only `--append-notes` preserves history. `bd`
says so on every run — `warning: <bead>: --notes replaced existing notes
(use --append-notes to preserve history)` — but the done sequence is the
last thing a polecat runs, so nobody reads that shell again.

What gets destroyed is not scratch. A work bead reaching the done sequence
routinely carries the mayor's dispatch note: the routing diagnosis, extra
requirements added after the bead was filed, corrections aimed at the
deacon or the reviewer. `--notes` erases all of it at the exact moment the
bead is handed to the refinery — i.e. immediately before the people who
most need it read it. Recovering it means hand-querying
`dolt_history_issues`.

The loss is invisible from inside the sequence: the update succeeds, the
handoff works, the branch merges. Nothing downstream can notice a note it
never saw, because no record survives that it was ever there.

Everything else that writes a work bead's notes already appends —
`check-set-heal.sh` at its repair sites, the refinery patrol on a rework
hand-back. The done sequence was the one destructive writer into a field
the rest of the system treats as history.

**The non-impl done sequence follows the same rule** — its verdict and
findings writes append too, and the fragment below says so at each site.
They were briefly carved out on the grounds that a review bead's notes are
a single-valued artifact, because `pre-open-resolve.sh` replays that field
verbatim as the PR's codex-signoff comment. The replay is real; the
carve-out did not follow from it (tk-q9e9y):

- A review bead's notes have a **second writer**. `signoff_retry_release`
  appends the "gate unrecorded" diagnostic to the same field and re-offers
  the same bead, so the next round's replacing verdict erases the only
  in-bead record of why the previous round failed.
- Appending splices nothing stale into that comment. Each re-gate mints a
  **fresh** review bead and the replay takes the newest one, so rounds
  never accumulate in one bead's notes — except on that retry path, where
  the accumulated entries all describe the PR being opened.
- Research and investigation beads are not replayed by anything, and their
  notes **are** the deliverable. Replacing them is the original data-loss
  bug (tk-6kf6r), not an exception to it.

What the verbatim replay does require is that a pre-open verdict be
**self-contained** — written to read correctly as an opening PR comment,
not as a diff against the entry above it.
{{ end }}
