{{ define "polecat-non-impl-done" }}
## Non-impl done sequence override

**This section supersedes the FINAL REMINDER, the "ABSOLUTE
RESTRICTION: No Bead Closing", and the "CRITICAL: Never Close
Beads" prohibition for tasks that produce no commits** — PR
reviews, research syntheses, and investigations that end in bead
notes.

The "no closing" rules exist because impl-task closure must come
from the refinery after a verified merge; non-impl tasks have
nothing for the refinery to verify, so the polecat closes the
bead itself.

### Why an override is needed

The unconditional impl done sequence (push branch, set
`metadata.branch`/`target`, hand to refinery) strands non-impl
beads: refinery sees a branch with no commits ahead of the target,
rejects the merge, and the bead loiters open until a human closes
it.

### Detect at done time

```bash
TARGET=$(gc bd show <work-bead> --json | jq -r '.[0].metadata.target // "{{ .DefaultBranch }}"')
COMMITS=$(git rev-list "origin/$TARGET..HEAD" --count 2>/dev/null || echo 0)
```

If `COMMITS > 0`: run the impl done sequence in the FINAL REMINDER
above. If `COMMITS == 0`: run the non-impl done sequence below
instead. The "Never Close Beads" prohibition is lifted for this one
case — polecats close non-impl beads themselves because there is
nothing for the refinery to merge.

### Non-impl done sequence

The artifact is already where it belongs (`gh pr review` for
reviews, `gc bd update --notes` for research, etc.). Do NOT set
`metadata.branch`, do NOT set `metadata.target`, do NOT route to
refinery.

```bash
# 1. Stamp task-specific metadata (review_id, pr_url, verdict, etc.)
gc bd update <work-bead> --set-metadata <task-specific fields>
# 2. Close the bead with a reason describing the task kind.
gc bd close <work-bead> --reason "<review|research|investigation> complete"
gc runtime drain-ack
exit
```
{{ end }}
