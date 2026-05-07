---
name: Integration-branch dispatch probe
description: End-to-end probe for the owned-convoy + integration-branch dispatch convention adopted in tk-jkesf. Validates the recipe documented in the mechanik and mayor prompts and the refinery hint in mol-refinery-patrol.
---

# Integration-branch dispatch probe (tk-jkesf)

This is the end-to-end probe per the bead's acceptance criteria. It
validates the convention documented in the mechanik prompt, mayor
prompt, polecat/refinery prompts, and `mol-refinery-patrol`.

## What was validated in-implementation

These were exercised inside the implementation polecat session
(`gc-toolkit.slit`) and are documented here for the audit trail:

1. **R4 hint match logic.** The bash `case "$TARGET" in
   integration/*)` pattern fires for `integration/<anything>` and does
   **not** false-positive for substrings like `feature/integration-X`.
   Verified directly with bash.
2. **Sling-time `--var base_branch=<ref>` acceptance.** `gc sling
   --dry-run gc-toolkit/gc-toolkit.polecat --formula -t … --var
   base_branch=integration/probe-test mol-polecat-work` accepts the
   override without error. The polecat would branch from
   `origin/integration/probe-test` per the formula's `workspace-setup`
   step, which already uses `{{base_branch}}`.
3. **Prompt template rendering.** The mechanik, mayor, polecat, and
   refinery prompt templates render cleanly with the new sections
   (verified with a stand-in Go template renderer; literal
   `{{base_branch}}` references are escaped via `{{`{{...}}`}}`).
4. **TOML syntax.** `mol-refinery-patrol.toml` parses cleanly after
   the R4 edit (Python `tomllib`).

## Live probe procedure (post-merge)

The full live probe — convoy create → integration branch push → child
beads → polecat dispatches → refinery merges back to integration → (no
main movement until graduation) — requires live agents and a clean
bead store. Run after this bead's branch is merged so the new mechanik
and mayor prompts are in effect for the dispatcher.

### Setup

```bash
# Run from the gc-toolkit rig root.
cd "$(gc rig status gc-toolkit -q)"
git fetch --prune origin
PROBE_ID="probe-$(date -u +%Y%m%dT%H%M%S)"
INTEGRATION="integration/$PROBE_ID"
```

### Step 1 — Owned convoy with integration branch

```bash
CONVOY=$(gc convoy create "tk-jkesf-probe-$PROBE_ID" --owned \
    --target "$INTEGRATION" --json | jq -r .convoy_id)
echo "Convoy: $CONVOY  Target: $INTEGRATION"
```

Verify the convoy carries the target metadata:

```bash
gc bd show "$CONVOY" --json | jq '.[0].metadata'
# Expected: { "target": "integration/probe-…", … }
```

### Step 2 — Push integration branch with shared artifact

```bash
git checkout -b "$INTEGRATION" origin/main
mkdir -p "specs/$CONVOY"
echo "# Probe artifact for $CONVOY" > "specs/$CONVOY/probe.md"
git add "specs/$CONVOY/probe.md"
git commit -m "convoy($CONVOY): seed integration branch with probe artifact"
git push -u origin "$INTEGRATION"
git checkout main
```

### Step 3 — File a child work bead

```bash
WORK=$(gc bd create "Probe child for $CONVOY" -t task --json | jq -r .id)
gc bd dep add "$WORK" "$CONVOY" --type=parent-child
```

### Step 4 — Sling the child to a polecat

```bash
gc sling gc-toolkit/gc-toolkit.polecat "$WORK"
```

Verify the polecat picks up the work, branches from
`origin/integration/<convoy-id>`, and not from `origin/main`:

```bash
gc bd show "$WORK" --json | jq '.[0].metadata'
# Expected: target=integration/<convoy-id>, branch=polecat/<work>-<slug>.<polecat-name>
```

### Step 5 — Watch the refinery merge back to the integration branch

When the polecat submits, the refinery rebases and merges to
`integration/<convoy-id>`. The R4 hint should fire in the refinery's
log/output:

```
INFO: Merging <work-id> to integration branch 'integration/<convoy-id>'
(not main). A graduation bead is required to land this work to main;
see 'gc convoy land' and the integration_branch_auto_land patrol step.
```

Verify origin/main has not moved during steps 1–5:

```bash
git fetch origin main
test "$(git rev-parse origin/main)" = "$(git rev-parse origin/main@{1})" \
  && echo "PROBE OK: main did not move." \
  || echo "PROBE FAIL: main moved during integration-branch dispatch."
```

### Step 6 — Cleanup (probe only)

```bash
git push origin --delete "$INTEGRATION"
gc bd close "$WORK" --reason "probe complete"
gc convoy land "$CONVOY" --force
```

## Pass criteria

- Step 4 polecat work bead carries `metadata.target =
  integration/<convoy-id>` (inherited from convoy ancestor walk).
- Step 5 refinery emits the R4 INFO hint.
- Step 5 verification: `origin/main` did not move during steps 1–5.
- Step 6 cleanup leaves the bead store and remote in their pre-probe
  state.

## What this probe is NOT

- Not a regression test in CI (gc-toolkit holds an intentionally low
  CI bar; see `project_gc_toolkit_low_ci_bar`).
- Not a gate. The R4 hint is a visibility nudge, not a block.
- Not a replacement for the `integration_branch_auto_land`
  graduation flow already documented in `mol-refinery-patrol`.
