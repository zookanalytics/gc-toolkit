{{ define "layered-startup-discovery-deacon" }}
## Startup Protocol — Layered Discovery

> **The Universal Propulsion Principle: If you find something on your hook, YOU RUN IT.**

`/clear` empties your context. Before pouring a fresh wisp, walk a
four-tier discovery so an inherited in-progress wisp, a routed work
bead, or an orphaned cross-rotation patrol wisp is picked up first.
Pouring unconditionally would orphan whatever the prior session left
behind.

```bash
# Tier 1 — In-progress patrol wisp (resume in place)
WISP=$(gc bd list --assignee="$GC_ALIAS" --status=in_progress \
  --type=molecule --include-infra --json --limit=1 | jq -r '.[0].id // empty')
if [ -n "$WISP" ]; then
  echo "Resuming in-progress wisp: $WISP"
fi

# Tier 2 — Routed work beads (open + branch metadata)
# Defensive: deacon rarely receives branch-bearing work beads, but
# structural symmetry with refinery startup avoids surprise gaps.
if [ -z "$WISP" ]; then
  WORK=$(gc bd list --assignee="$GC_ALIAS" --status=open \
    --has-metadata-key=branch --exclude-type=epic --json --limit=1 \
    | jq -r '.[0].id // empty')
  if [ -n "$WORK" ]; then
    echo "Found routed work bead: $WORK — pouring wisp; formula handles the work"
    WISP=$(gc bd mol wisp mol-deacon-patrol --root-only --var binding_prefix={{ .BindingPrefix }} --json | jq -r '.new_epic_id')
    gc bd update "$WISP" --assignee="$GC_ALIAS"
  fi
fi

# Tier 3 — Open patrol wisps (cross-rotation orphans / pour-before-burn inheritance)
# Pour-before-burn cycle-recycle leaves an open wisp here.
# A pathological loop could leave multiple — adopt newest, close older
# ones with reason 'orphaned cross-rotation'.
if [ -z "$WISP" ]; then
  # Wisp records carry the formula name in `title` (no metadata.formula field).
  ORPHANS=$(gc bd list --assignee="$GC_ALIAS" --status=open --type=molecule \
    --include-infra --json | jq -r '[.[] | select(.title == "mol-deacon-patrol")] | sort_by(.created_at) | reverse')
  COUNT=$(echo "$ORPHANS" | jq 'length')
  if [ "$COUNT" -gt 0 ]; then
    WISP=$(echo "$ORPHANS" | jq -r '.[0].id')
    echo "Adopting open patrol wisp: $WISP"
    gc bd update "$WISP" --status=in_progress
    if [ "$COUNT" -gt 1 ]; then
      echo "$ORPHANS" | jq -r '.[1:][] | .id' | while read -r OLD; do
        gc bd close "$OLD" --reason "orphaned cross-rotation: superseded by $WISP" || true
      done
    fi
  fi
fi

# Tier 4 — Pour fresh wisp (no in-progress, no routed work, no open wisp)
if [ -z "$WISP" ]; then
  WISP=$(gc bd mol wisp mol-deacon-patrol --root-only --var binding_prefix={{ .BindingPrefix }} --json | jq -r '.new_epic_id')
  gc bd update "$WISP" --assignee="$GC_ALIAS"
  echo "Poured fresh wisp: $WISP"
fi

# Then: Execute — read formula steps and work through them in order
# (mail handling is the formula's check-inbox step, not part of startup)
```

**Hook -> Read formula steps -> Follow in order -> pour next iteration.**
{{ end }}

{{ define "layered-startup-discovery-refinery" }}
## Startup — Layered Discovery

`/clear` empties your context. Before pouring a fresh wisp, walk a
four-tier discovery so an inherited in-progress wisp, a routed work
bead, or an orphaned cross-rotation wisp is picked up first. Pouring
unconditionally would orphan whatever the prior session left behind.

```bash
# Tier 1 — In-progress patrol wisp (resume in place)
WISP=$(gc bd list --assignee="$GC_ALIAS" --status=in_progress \
  --type=molecule --include-infra --json --limit=1 | jq -r '.[0].id // empty')
if [ -n "$WISP" ]; then
  echo "Resuming in-progress wisp: $WISP"
  # Re-enter formula at check-inbox.
fi

# Tier 2 — Routed work beads (open + branch metadata)
# Polecats reassign work to you with status=open + metadata.branch.
# If cycle-recycle interleaved with a polecat handoff, the work bead
# is here even though no in-progress wisp exists yet.
if [ -z "$WISP" ]; then
  WORK=$(gc bd list --assignee="$GC_ALIAS" --status=open \
    --has-metadata-key=branch --exclude-type=epic --json --limit=1 \
    | jq -r '.[0].id // empty')
  if [ -n "$WORK" ]; then
    echo "Found routed work bead: $WORK — pouring wisp and entering formula at find-work"
    WISP=$(gc bd mol wisp mol-refinery-patrol --root-only --var target_branch={{ .DefaultBranch }} --var rig_name={{ .RigName }} --var binding_prefix={{ .BindingPrefix }} --var default_merge_strategy={{ or .DefaultMergeStrategy "direct" }} --json | jq -r '.new_epic_id')
    gc bd update "$WISP" --assignee="$GC_ALIAS"
    # Re-enter formula at find-work; it will pick up $WORK.
  fi
fi

# Tier 3 — Open patrol wisps (cross-rotation orphans / pour-before-burn inheritance)
# Pour-before-burn cycle-recycle leaves an open wisp here.
# A pathological event-watch loop could leave multiple — adopt newest,
# close older ones with reason 'orphaned cross-rotation'.
if [ -z "$WISP" ]; then
  # Wisp records carry the formula name in `title` (no metadata.formula field).
  ORPHANS=$(gc bd list --assignee="$GC_ALIAS" --status=open --type=molecule \
    --include-infra --json | jq -r '[.[] | select(.title == "mol-refinery-patrol")] | sort_by(.created_at) | reverse')
  COUNT=$(echo "$ORPHANS" | jq 'length')
  if [ "$COUNT" -gt 0 ]; then
    WISP=$(echo "$ORPHANS" | jq -r '.[0].id')
    echo "Adopting open patrol wisp: $WISP"
    gc bd update "$WISP" --status=in_progress
    if [ "$COUNT" -gt 1 ]; then
      # Burn older wisps only if they have no recent activity.
      echo "$ORPHANS" | jq -r '.[1:][] | .id' | while read -r OLD; do
        gc bd close "$OLD" --reason "orphaned cross-rotation: superseded by $WISP" || true
      done
    fi
  fi
fi

# Tier 4 — Pour fresh wisp (no in-progress, no routed work, no open wisp)
if [ -z "$WISP" ]; then
  WISP=$(gc bd mol wisp mol-refinery-patrol --root-only --var target_branch={{ .DefaultBranch }} --var rig_name={{ .RigName }} --var binding_prefix={{ .BindingPrefix }} --var default_merge_strategy={{ or .DefaultMergeStrategy "direct" }} --json | jq -r '.new_epic_id')
  gc bd update "$WISP" --assignee="$GC_ALIAS"
  echo "Poured fresh wisp: $WISP"
fi
```

Then follow the formula. The step descriptions below are your instructions —
work through them in order. On crash or restart, re-read the steps and
determine where you left off from context (git state, bead state).
{{ end }}
