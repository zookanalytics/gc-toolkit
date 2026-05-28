{{ define "convoy-integration-branch-mayor" }}
## Sharing input artifacts across N polecats

When a dispatch needs a shared input artifact (a decisions doc, a
research synthesis, a spec) visible to multiple polecats before any
have produced work worth merging, do **not** commit the artifact
directly to the rig's default branch. That violates the
branch-based-dispatch principle (decided in `tk-w7mjt`) and was the
shape of the 2026-05-06 shortcut incident (`7453fa4`).

The supported path is an **owned convoy with an integration branch**:

```bash
# 1. Create owned convoy with integration branch as target.
CONVOY=$(gc convoy create "<initiative>" --owned \
    --target "integration/<convoy-id>" --json | jq -r .convoy_id)

# 2. Push the integration branch with the shared artifact (in the rig).
git -C <rig-root> fetch --prune origin
git -C <rig-root> checkout -b "integration/<convoy-id>" origin/main
# add + commit the shared artifact, then:
git -C <rig-root> push -u origin "integration/<convoy-id>"

# 3. File child work beads, link to convoy, sling normally.
WORK=$(gc bd create "<task>" -t task --json | jq -r .id)
gc bd dep add "$WORK" "$CONVOY" --type=parent-child
gc sling <rig>/polecat "$WORK"   # inherits metadata.target via convoy walk
```

Children inherit `metadata.target = integration/<convoy-id>` via the
convoy-ancestor walk in `gc sling`, so polecats branch from
`origin/integration/<convoy-id>` and the refinery merges polecat work
back to the integration branch — never to main. When all children
close, file a graduation bead that squash-merges
`integration/<convoy-id>` to main, then `gc convoy land <convoy-id>`.

**Per-invocation override (alternative):** instead of (or in addition
to) the convoy target, `gc sling <target> <bead> --var
base_branch=integration/<convoy-id>` points a single dispatch at any
ref. Explicit `--var` always wins over the auto-compute.

**Anti-pattern:** `git checkout main && git add specs/<bead>/...md &&
git commit && git push`. Do not commit bead-local content directly to
main — see `tk-w7mjt` and the 7453fa4 incident.
{{ end }}
