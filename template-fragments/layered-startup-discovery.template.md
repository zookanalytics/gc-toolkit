{{ define "layered-startup-discovery-deacon" }}
## Startup Protocol — Layered Discovery

> **The Universal Propulsion Principle: If you find something on your hook, YOU RUN IT.**

`/clear` empties your context. Before pouring a fresh wisp, walk a
four-tier discovery so an inherited in-progress wisp, a routed work
bead, or an orphaned cross-rotation patrol wisp is picked up first.
Pouring unconditionally would orphan whatever the prior session left
behind.

```bash
# Identity: discovery filters on $GC_AGENT, the canonical mailbox identity the
# patrol formula also assigns to. $GC_ALIAS can legitimately be empty (the
# harness guarantees $GC_AGENT, falling back to the session name); polling on
# an empty alias is what self-polled for hours with queued beads (upstream
# #1833). Do not switch these back to $GC_ALIAS.

# Tier 1 — In-progress patrol wisp (resume in place)
WISP=$(gc bd list --assignee="$GC_AGENT" --status=in_progress \
  --type=molecule --include-infra --json --limit=1 | jq -r '.[0].id // empty')
if [ -n "$WISP" ]; then
  echo "Resuming in-progress wisp: $WISP"
fi

# Tier 2 — Routed work beads (open + branch metadata)
# Defensive: deacon rarely receives branch-bearing work beads, but
# structural symmetry with refinery startup avoids surprise gaps.
if [ -z "$WISP" ]; then
  WORK=$(gc bd list --assignee="$GC_AGENT" --status=open \
    --has-metadata-key=branch --exclude-type=epic --json --limit=1 \
    | jq -r '.[0].id // empty')
  if [ -n "$WORK" ]; then
    echo "Found routed work bead: $WORK — pouring wisp; formula handles the work"
    WISP=$(gc bd mol wisp mol-deacon-patrol --root-only --var binding_prefix={{ .BindingPrefix }} --json | jq -r '.new_epic_id')
    gc bd update "$WISP" --assignee="$GC_AGENT"
  fi
fi

# Tier 3 — Open patrol wisps (cross-rotation orphans / pour-before-burn inheritance)
# Pour-before-burn cycle-recycle leaves an open wisp here.
# A pathological loop could leave multiple — adopt newest, close older
# ones with reason 'orphaned cross-rotation'.
if [ -z "$WISP" ]; then
  # Wisp records carry the formula name in `title` (no metadata.formula field).
  ORPHANS=$(gc bd list --assignee="$GC_AGENT" --status=open --type=molecule \
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
  gc bd update "$WISP" --assignee="$GC_AGENT"
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
# Identity: discovery filters on $GC_AGENT, the canonical mailbox identity the
# refinery formula validates and assigns to. $GC_ALIAS can legitimately be
# empty (the harness guarantees $GC_AGENT, falling back to the session name);
# polling on an empty alias is what self-polled for 13h42m with seven queued
# beads while looking healthy-idle (upstream #1833). Do not switch these back
# to $GC_ALIAS — startup discovery runs before the formula's validate-identity
# guard, so it must use the safe identity from the first query.

# Tier 1 — In-progress patrol wisp (resume in place)
WISP=$(gc bd list --assignee="$GC_AGENT" --status=in_progress \
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
  WORK=$(gc bd list --assignee="$GC_AGENT" --status=open \
    --has-metadata-key=branch --exclude-type=epic --json --limit=1 \
    | jq -r '.[0].id // empty')
  if [ -n "$WORK" ]; then
    echo "Found routed work bead: $WORK — pouring wisp and entering formula at find-work"
    WISP=$(gc bd mol wisp mol-refinery-patrol --root-only --var target_branch={{ .DefaultBranch }} --var rig_name={{ .RigName }} --var binding_prefix={{ .BindingPrefix }} --var default_merge_strategy={{ or .DefaultMergeStrategy "direct" }} --json | jq -r '.new_epic_id')
    gc bd update "$WISP" --assignee="$GC_AGENT"
    # Re-enter formula at find-work; it will pick up $WORK.
  fi
fi

# Tier 3 — Open patrol wisps (cross-rotation orphans / pour-before-burn inheritance)
# Pour-before-burn cycle-recycle leaves an open wisp here.
# A pathological event-watch loop could leave multiple — adopt newest,
# close older ones with reason 'orphaned cross-rotation'.
if [ -z "$WISP" ]; then
  # Wisp records carry the formula name in `title` (no metadata.formula field).
  ORPHANS=$(gc bd list --assignee="$GC_AGENT" --status=open --type=molecule \
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
  gc bd update "$WISP" --assignee="$GC_AGENT"
  echo "Poured fresh wisp: $WISP"
fi
```

Then follow the formula. The step descriptions below are your instructions —
work through them in order. On crash or restart, re-read the steps and
determine where you left off from context (git state, bead state).
{{ end }}

{{ define "layered-startup-discovery-witness" }}
## Startup Protocol — Ephemeral-Aware Wisp Reconcile

> **The Universal Propulsion Principle: If you find something on your hook, YOU RUN IT.**

This supersedes the reconcile snippets in the `## Startup Protocol` and
`## CRITICAL: No Idle State Between Cycles` sections above. Same logic —
reconcile to exactly one patrol wisp, burn the surplus — with three
corrections, each of which the deacon and refinery blocks already make:
every `--type=molecule` query carries `--include-infra`; every one of them
is scoped to `mol-witness-patrol` roots; and the surviving wisp is adopted
(`--status=in_progress`) before the formula runs.

Patrol wisps are EPHEMERAL — they live in `<store>.wisps`, not `.issues`.
`gc bd list` reads `.issues` by default, so a `--type=molecule` query
without `--include-infra` comes back empty even while wisps exist. The
reconcile then concludes "no wisp", pours a fresh one, and leaks the
prior one — on every restart, accumulating `.wisps` rows. `gc hook`,
`gc bd show`, and `gc bd mol burn` route by id and DO see the wisps,
which is why the leak is invisible to the reconcile but real (three
leaked wisps observed live 2026-06-26; tk-1waw2).

Unlike the deacon and refinery blocks there is no tier-2
routed-work-bead query here: the witness monitors other agents' work
rather than receiving branch-bearing work beads of its own. The
divergences this block fixes are ephemeral blindness, formula scoping,
and wisp adoption — not tier coverage.

```bash
# Step 1: Reconcile your patrol wisps to exactly one (town ledger, via gc bd).
# Collect every open/in_progress patrol wisp assigned to you, keep one, and
# burn the surplus so restarts never accumulate duplicates. Wisp roots are
# molecules — filter --type=molecule, never --type=wisp. --include-infra is
# REQUIRED: wisps are ephemeral, so without it both queries return empty and
# every restart leaks a wisp. Filter on title as well: molecule roots are
# formula-specific (the deacon/refinery blocks filter the same way), so an
# unrelated root assigned to the witness must never be adopted as the patrol
# wisp or burned as "surplus".
WISP_IDS=$(
  gc bd list --assignee="$GC_AGENT" --status=in_progress --type=molecule --include-infra --limit=0 --json | jq -r '.[] | select(.title == "mol-witness-patrol") | .id'
  gc bd list --assignee="$GC_AGENT" --status=open --type=molecule --include-infra --limit=0 --json | jq -r '.[] | select(.title == "mol-witness-patrol") | .id'
)
WISP=$(printf '%s\n' $WISP_IDS | sed -n '1p')           # keep one (prefers in_progress)
for extra in $(printf '%s\n' $WISP_IDS | sed '1d'); do  # burn any surplus
  gc bd mol burn "$extra" --force
done

# Step 2: Already have a wisp? Resume it. Otherwise check mail, then pour ONE.
if [ -n "$WISP" ]; then
  echo "Resuming patrol wisp $WISP"
else
  gc mail inbox
  WISP=$(gc bd mol wisp mol-witness-patrol --root-only --var binding_prefix='{{ .BindingPrefix }}' --json | jq -r '.new_epic_id')
  gc bd update "$WISP" --assignee="$GC_AGENT"
fi

# Adopt the wisp you are about to execute: mark it in_progress (this leaves the
# assignee untouched). Without it the ACTIVE patrol wisp stays open — visible as
# queued work while it runs, and indistinguishable from the *next* wisp that
# next-iteration pours before burning this one. A restart at that moment sees two
# open wisps and can keep or burn the wrong one. Marking it in_progress is also
# what makes Step 1's in_progress-first ordering select the running wisp.
gc bd update "$WISP" --status=in_progress

# Step 3: Execute — read formula steps and work through them in order
```

**Hook -> Read formula steps -> Follow in order -> pour next iteration -> run `gc hook`.**

### No-idle-state fallback

Use this only if you exited the cycle without running `next-iteration`
(crash recovery or formula misread). If `next-iteration` already ran, do
not pour again; run `gc hook`. The open-wisp reconcile carries
`--include-infra` for the same reason as Step 1 — without it the
surplus is invisible and gets leaked instead of burned.

```bash
CURRENT_WISP=${GC_BEAD_ID:-}
if [ -z "$CURRENT_WISP" ]; then
  # Title-filtered like Step 1 — this id is burned below, so an unrelated
  # molecule root must never land in it. Filtering happens in jq, so the query
  # must not cap itself at --limit=1: that could return one non-patrol root and
  # filter to empty while the real patrol wisp exists.
  CURRENT_WISP=$(gc bd list --assignee="$GC_AGENT" --status=in_progress --type=molecule --include-infra --limit=0 --json | jq -r '[.[] | select(.title == "mol-witness-patrol")] | .[0].id // empty')
fi
# Reconcile queued (open) patrol wisps to exactly one. A prior cycle may have
# poured a next wisp without burning, or a restart may have raced — keep the
# first and burn the surplus so wisps never accumulate. Same title filter as
# Step 1: only mol-witness-patrol roots are ours to burn.
OPEN_WISPS=$(gc bd list --assignee="$GC_AGENT" --status=open --type=molecule --include-infra --limit=0 --json | jq -r '.[] | select(.title == "mol-witness-patrol") | .id')
ASSIGNED_WISP=$(printf '%s\n' $OPEN_WISPS | sed -n '1p')
for extra in $(printf '%s\n' $OPEN_WISPS | sed '1d'); do
  gc bd mol burn "$extra" --force
done
if [ -n "$CURRENT_WISP" ] && [ -z "$ASSIGNED_WISP" ]; then
  NEXT=$(gc bd mol wisp mol-witness-patrol --root-only --var binding_prefix='{{ .BindingPrefix }}' --json | jq -r '.new_epic_id // empty')
  if [ -z "$NEXT" ]; then
    echo "Could not pour next witness wisp; not burning."
    exit 1
  fi
  if ! gc bd update "$NEXT" --assignee="$GC_AGENT"; then
    echo "Could not assign next witness wisp; not burning."
    exit 1
  fi
  gc bd mol burn "$CURRENT_WISP" --force
elif [ -n "$CURRENT_WISP" ]; then
  gc bd mol burn "$CURRENT_WISP" --force
elif [ -z "$ASSIGNED_WISP" ]; then
  NEXT=$(gc bd mol wisp mol-witness-patrol --root-only --var binding_prefix='{{ .BindingPrefix }}' --json | jq -r '.new_epic_id // empty')
  if [ -z "$NEXT" ]; then
    echo "Could not bootstrap next witness wisp."
    exit 1
  fi
  if ! gc bd update "$NEXT" --assignee="$GC_AGENT"; then
    echo "Could not assign bootstrap witness wisp."
    exit 1
  fi
fi
gc hook
```
{{ end }}
