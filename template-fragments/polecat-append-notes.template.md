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

**This is not "notes are append-only everywhere."** A review bead's notes
are a single-valued artifact — `pre-open-resolve.sh` replays them verbatim
as the PR's codex-signoff comment — so the non-impl verdict writes keep
`--notes` on purpose. The rule here is scoped to the impl done sequence,
where notes are a history field with more than one writer.
{{ end }}
