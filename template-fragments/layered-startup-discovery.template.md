{{ define "layered-startup-discovery-boot" }}
## Triage Queries — Ephemeral-Aware Deacon-Wisp Read

This supersedes the deacon-wisp query in `### Step 2: Observe deacon state`
and the `Check deacon work` row of the `## Command Quick-Reference` table
above. Both sites run the same query today and both omit the same flag, so
correcting only Step 2 would leave the quick-reference row teaching the broken
form. Nothing else in Step 2 changes — the pane peek and the mail count are
right as written; only the `gc bd list` call is wrong.

Patrol wisps are EPHEMERAL: they live in `<store>.wisps`, not `.issues`.
`gc bd list` reads `.issues` by default, so a query without `--include-infra`
comes back `[]` even while the deacon holds a live in-progress patrol wisp.
`gc hook`, `gc bd show`, and `gc bd mol burn` route by id and DO see wisps,
which is why the blindness is invisible from every other angle but real — the
same mechanism the deacon, refinery, and witness startup overlays already
correct (tk-1waw2).

The consequence is specific to boot: your entire wisp-freshness signal is
dead. The two triage rows keyed on wisp staleness — "Idle, young wisp ->
Backoff wait" and "Very stale wisp, errors visible -> Clearly stuck" — can
never fire, because the query they read from is empty on every wake regardless
of how the deacon is doing. You fall back to judging on pane output alone,
which is exactly the ambiguous evidence the wisp timestamps exist to
disambiguate (reported and reproduced in lx-ody8m).

Corrected Step 2 observation block:

```bash
# Recent pane output — is the deacon actively working?
{{ cmd }} session peek {{ .BindingPrefix }}deacon --lines 30

# Deacon's current patrol wisp — how fresh is it?
# --include-infra is REQUIRED: the wisp is ephemeral, so without it this comes
# back [] on every wake and the triage rows keyed on staleness never fire.
# --type=molecule plus the title match keep the result to patrol wisps, and
# --limit=0 lifts the row cap so nothing else the deacon holds can crowd the
# wisp out. Read `updated_at` on the row you get back — that timestamp IS the
# freshness signal.
gc bd list --assignee={{ .BindingPrefix }}deacon --status=in_progress \
  --type=molecule --include-infra --limit=0 --json \
  | jq '[.[] | select(.title == "mol-deacon-patrol")]'

# Separately: what else is the deacon holding? Broad and capped on purpose.
# This answers "how loaded is it", never the freshness question above.
gc bd list --assignee={{ .BindingPrefix }}deacon --status=in_progress \
  --include-infra --json --limit=5

# Does the deacon have unread mail? (may explain idle state)
gc mail count {{ .BindingPrefix }}deacon 2>/dev/null
```

Keep those two `gc bd list` calls apart. They answer different questions, and
folding them back into one capped list is what re-opens this bug from the other
side: `--include-infra` widens what is *visible*, but a deacon holding more than
five in-progress rows can still push the wisp out of a `--limit=5` result, and
the staleness rows go dead again — silently, and only under load, which is the
worst version of it. The wisp query is typed, title-matched and uncapped so the
wisp is in the result set or genuinely absent; the broad query stays capped
because a plate-size read does not need every row.

Corrected quick-reference rows — one row becomes two, for the same reason:

| Want to... | Correct command |
|------------|----------------|
| Check deacon work | `gc bd list --assignee={{ .BindingPrefix }}deacon --status=in_progress --include-infra --json` |
| Check the deacon patrol wisp | `gc bd list --assignee={{ .BindingPrefix }}deacon --status=in_progress --type=molecule --include-infra --title=mol-deacon-patrol --limit=0 --json` |

The wisp row uses bd's own `--title` filter (case-insensitive substring) instead
of the exact `jq` match above, because a quick-reference cell has to stay a
single command: a `|` inside a table cell needs escaping, and an escaped pipe is
copied out broken. Substring matching is safe here because you only read the
answer — nothing is adopted or burned on it, unlike the witness's own wisp
reconcile, which matches the title exactly for precisely that reason. The patrol
wisp comes back with `issue_type` `molecule` and title `mol-deacon-patrol`.

### Empty is not a verdict

With the flag in place an empty result is still not evidence that the deacon
is stuck, and it is never evidence that the store is degraded:

- The query is scoped to `--assignee`, and pouring a wisp and assigning it are
  two separate writes. A session that died between them leaves a wisp with NO
  assignee, invisible to this query — the mechanism tk-fj56a fixed for
  `mol-witness-patrol`. Nothing collects that orphan on the deacon side today:
  the deacon's own startup discovery is `--assignee`-scoped at both its
  in-progress tier and its open-wisp tier, so it is blind to exactly the row
  this query is blind to (tk-9m8k7). Widening this query off `--assignee`
  would not help you either — a stale orphan sitting beside a healthy assigned
  wisp is what would then feed the "very stale wisp" row a false positive. So
  treat an empty result as "no signal", not as "no wisp exists".
- A deacon between patrol cycles legitimately holds no wisp at all.

For those cases fall back to pane output and mail, exactly as the triage table
already prescribes for the rows that do not mention a wisp. Do not file a
warrant on an empty wisp query alone.
{{ end }}

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
    WISP=$(gc bd mol wisp mol-refinery-patrol --root-only --var target_branch={{ .DefaultBranch }} --var rig_name={{ .RigName }} --var binding_prefix={{ .BindingPrefix }} --var default_merge_strategy=mr --json | jq -r '.new_epic_id')
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
  WISP=$(gc bd mol wisp mol-refinery-patrol --root-only --var target_branch={{ .DefaultBranch }} --var rig_name={{ .RigName }} --var binding_prefix={{ .BindingPrefix }} --var default_merge_strategy=mr --json | jq -r '.new_epic_id')
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
reconcile to exactly one patrol wisp, burn the surplus — with four
corrections, three of which the deacon and refinery blocks already make:
every `--type=molecule` query carries `--include-infra`; every one of them
is scoped to `mol-witness-patrol` roots; the surviving wisp is adopted
(`--status=in_progress`, and claimed with `--assignee`) before the formula
runs; and no reconcile query filters on `--assignee`, so a wisp that lost
its owner is still collectable.

Patrol wisps are EPHEMERAL — they live in `<store>.wisps`, not `.issues`.
`gc bd list` reads `.issues` by default, so a `--type=molecule` query
without `--include-infra` comes back empty even while wisps exist. The
reconcile then concludes "no wisp", pours a fresh one, and leaks the
prior one — on every restart, accumulating `.wisps` rows. `gc hook`,
`gc bd show`, and `gc bd mol burn` route by id and DO see the wisps,
which is why the leak is invisible to the reconcile but real (three
leaked wisps observed live 2026-06-26; tk-1waw2).

Reconcile on TITLE, never on assignee (tk-fj56a). Pouring a wisp and
assigning it are two separate writes, so a session that dies, is recycled,
or fails the update in between leaves a wisp with NO assignee. Every
`--assignee`-scoped query is blind to it — on this restart and on every
future one — so it is unreachable garbage that accumulates one row per
interrupted pour (one found live at ~3.5h old, 2026-07-28, only by an
unscoped title sweep run as a positive control). This is a DISTINCT
mechanism from the ephemeral blindness above and is not fixed by
`--include-infra`: the miss is on the assignee axis, not the
infra-visibility axis, so both queries must widen for the leak to close.
Title is the correct ownership key here — `gc bd` is pinned to this rig's
store and the witness is the sole owner of the `mol-witness-patrol` title
within it — which is why widening off assignee cannot reach another
agent's wisps.

Unlike the deacon and refinery blocks there is no tier-2
routed-work-bead query here: the witness monitors other agents' work
rather than receiving branch-bearing work beads of its own. The
divergences this block fixes are ephemeral blindness, formula scoping,
orphaned-wisp visibility, and wisp adoption — not tier coverage.

```bash
# Step 1: Reconcile your patrol wisps to exactly one (town ledger, via gc bd).
# Collect every open/in_progress patrol wisp in this rig's store, keep one, and
# burn the surplus so restarts never accumulate duplicates. Wisp roots are
# molecules — filter --type=molecule, never --type=wisp. --include-infra is
# REQUIRED: wisps are ephemeral, so without it both queries return empty and
# every restart leaks a wisp. TITLE is the ownership key, and the ONLY one:
# molecule roots are formula-specific (the deacon/refinery blocks filter the
# same way), so an unrelated root must never be adopted as the patrol wisp or
# burned as "surplus" — while filtering on --assignee would hide exactly the
# wisps this reconcile exists to collect, since an interrupted pour leaves one
# with no assignee at all (tk-fj56a).
# >>> patrol-wisp-reconcile
WISP_IDS=$(
  gc bd list --status=in_progress --type=molecule --include-infra --limit=0 --json | jq -r '.[] | select(.title == "mol-witness-patrol") | .id'
  gc bd list --status=open --type=molecule --include-infra --limit=0 --json | jq -r '.[] | select(.title == "mol-witness-patrol") | .id'
)
WISP=$(printf '%s\n' $WISP_IDS | sed -n '1p')           # keep one (prefers in_progress)
for extra in $(printf '%s\n' $WISP_IDS | sed '1d'); do  # burn any surplus
  gc bd mol burn "$extra" --force
done
# <<< patrol-wisp-reconcile

# Step 2: Already have a wisp? Resume it. Otherwise check mail, then pour ONE.
if [ -n "$WISP" ]; then
  echo "Resuming patrol wisp $WISP"
else
  gc mail inbox
  WISP=$(gc bd mol wisp mol-witness-patrol --root-only --var binding_prefix='{{ .BindingPrefix }}' --json | jq -r '.new_epic_id')
fi

# Adopt the wisp you are about to execute: CLAIM it (--assignee) and mark it
# in_progress. The claim is what re-owns a wisp the reconcile just collected
# with no assignee — Step 1 finds it by title, but only this write puts it back
# on your hook; it is a harmless no-op for a wisp you already own, and it is
# also the write that a failed pour-time assign left undone. Without the
# in_progress flip the ACTIVE patrol wisp stays open — visible as queued work
# while it runs, and indistinguishable from the *next* wisp that next-iteration
# pours before burning this one. A restart at that moment sees two open wisps
# and can keep or burn the wrong one. Marking it in_progress is also what makes
# Step 1's in_progress-first ordering select the running wisp.
gc bd update "$WISP" --assignee="$GC_AGENT" --status=in_progress

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
# >>> patrol-wisp-fallback
CURRENT_WISP=${GC_BEAD_ID:-}
if [ -z "$CURRENT_WISP" ]; then
  # Title-filtered and assignee-blind like Step 1 — this id is burned below, so
  # an unrelated molecule root must never land in it, and a wisp orphaned by an
  # interrupted pour must never be skipped. Filtering happens in jq, so the
  # query must not cap itself at --limit=1: that could return one non-patrol
  # root and filter to empty while the real patrol wisp exists.
  CURRENT_WISP=$(gc bd list --status=in_progress --type=molecule --include-infra --limit=0 --json | jq -r '[.[] | select(.title == "mol-witness-patrol")] | .[0].id // empty')
fi
# Reconcile queued (open) patrol wisps to exactly one. A prior cycle may have
# poured a next wisp without burning, or a restart may have raced — keep the
# first and burn the surplus so wisps never accumulate. Same title filter and
# same absence of an --assignee filter as Step 1: only mol-witness-patrol roots
# are ours to burn, and an unassigned one is still ours.
OPEN_WISPS=$(gc bd list --status=open --type=molecule --include-infra --limit=0 --json | jq -r '.[] | select(.title == "mol-witness-patrol") | .id')
QUEUED_WISP=$(printf '%s\n' $OPEN_WISPS | sed -n '1p')
for extra in $(printf '%s\n' $OPEN_WISPS | sed '1d'); do
  gc bd mol burn "$extra" --force
done
# CLAIM the queued wisp before trusting it to carry the loop. That query is
# assignee-blind by design, so this id may be an ORPHAN from an interrupted
# pour — and inheriting one without claiming it would burn the current wisp in
# favour of a wisp that never reaches a hook, stopping the patrol entirely.
# (Named QUEUED, not ASSIGNED: it is only assigned once this write succeeds.)
# A failed claim means there is no usable next wisp, so blank it and fall
# through to pouring a fresh one; Step 1's reconcile collects the stray later.
if [ -n "$QUEUED_WISP" ] && ! gc bd update "$QUEUED_WISP" --assignee="$GC_AGENT"; then
  echo "Could not claim queued wisp $QUEUED_WISP; pouring a fresh one instead."
  QUEUED_WISP=""
fi
if [ -n "$CURRENT_WISP" ] && [ -z "$QUEUED_WISP" ]; then
  NEXT=$(gc bd mol wisp mol-witness-patrol --root-only --var binding_prefix='{{ .BindingPrefix }}' --json | jq -r '.new_epic_id // empty')
  if [ -z "$NEXT" ]; then
    echo "Could not pour next witness wisp; not burning."
    exit 1
  fi
  if ! gc bd update "$NEXT" --assignee="$GC_AGENT"; then
    # Roll the pour back: an assigned-to-nobody wisp is the leak this whole
    # block guards against. If the rollback itself fails, Step 1's title-scoped
    # reconcile collects it on the next restart — that is its backstop role.
    echo "Could not assign next witness wisp; rolling back $NEXT and not burning."
    gc bd mol burn "$NEXT" --force || echo "Rollback burn of $NEXT failed; startup reconcile will collect it."
    exit 1
  fi
  gc bd mol burn "$CURRENT_WISP" --force
elif [ -n "$CURRENT_WISP" ]; then
  gc bd mol burn "$CURRENT_WISP" --force
elif [ -z "$QUEUED_WISP" ]; then
  NEXT=$(gc bd mol wisp mol-witness-patrol --root-only --var binding_prefix='{{ .BindingPrefix }}' --json | jq -r '.new_epic_id // empty')
  if [ -z "$NEXT" ]; then
    echo "Could not bootstrap next witness wisp."
    exit 1
  fi
  if ! gc bd update "$NEXT" --assignee="$GC_AGENT"; then
    # Same rollback as above — never leave a poured wisp unowned.
    echo "Could not assign bootstrap witness wisp; rolling back $NEXT."
    gc bd mol burn "$NEXT" --force || echo "Rollback burn of $NEXT failed; startup reconcile will collect it."
    exit 1
  fi
fi
# <<< patrol-wisp-fallback
gc hook
```
{{ end }}
