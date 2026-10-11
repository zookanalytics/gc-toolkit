#!/usr/bin/env bash
# witness-recovery.sh — the stages of the witness's orphan recovery, sourced by
# mol-witness-patrol's recover-orphaned-beads step:
#
#   . "$SCRIPTS/witness-recovery.sh"
#
# The witness finds beads assigned to agents that will never process them,
# salvages unpublished worktree work, and returns the beads to the pool. The
# canonical chain is worktree -> (push) -> branch -> (merge) -> target: recovery
# ensures work reaches the branch, then the bead is schedulable again.
#
# Each function is one stage, run in the witness's own shell. Stages hand state
# to later ones through shell variables, so a stage reads what an earlier one
# set: witness_liveness_lookup reads LIVENESS_MAP and OWNER; every per-bead
# stage reads BEAD, and the salvage stages read what witness_salvage_context
# sets. The marked regions are the stage bodies, which each stage's own test
# extracts and executes.
#
# Sourced, never executed: nothing runs at load, and a stage may set traps on
# the caller's shell, as the step's own blocks did.
# shellcheck disable=SC2034  # each stage sets variables the sourcing step reads

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

# witness_candidates — print one `<bead> <owner>` row per owned candidate, or a
# `did not parse` line on stderr when the listing failed (no candidate set this
# cycle, not a rig with nothing to recover).
#
# The listing and its three filters run as ONE pipeline, so bd's JSON flows from
# `gc bd list` through each filter on stdin and never sits in a shell variable:
# zsh's builtin echo expands the backslash escapes inside JSON strings, so a
# listing re-fed through `echo "$X" | jq` reaches jq corrupted.
#
# host-bead-skip drops only beads that name no owner (already the pool's), so
# every other owned bead reaches the liveness loop whatever its kind: a visit
# whose session died should return to the pool. downstream-court-skip drops, by
# state, work that already reached a downstream court: an in-flight PR
# (merge_result pre_open_gate or pull_request), which the refinery enumerates
# and owns landing, or a human gate (gc.routed_to=human). Returning either to
# the pool re-dispatches finished work and stamps a recovery whose crash-loop
# RATE escalates a moot visit every cycle. pr.machine is not read: transition
# --to unanchored clears merge_result and leaves a stale `progressing` stamp,
# and a bead still in the machine carries the merge_result already dropped.
# topology-root-skip drops, by kind, the graph.v2 topology root (gc.kind
# workflow, scope or spec): it names only a gc.session_name slot label, its
# steps carry the work and the gc.session_id, and its close is the
# control-dispatcher's workflow-finalize, so the loop has no recovery to offer
# it (orphan-dispose.sh refuses it as root_not_schedulable).
witness_candidates() {
# >>> candidate-pipeline
# A raw control byte in any one bead string aborts jq on the whole listing and
# blinds the cycle to every candidate, so the strip runs ahead of the first jq,
# the same strip check-refinery applies to its listing.
CANDIDATES=$(mktemp "${TMPDIR:-/tmp}/gctk-witness-candidates.XXXXXX")
gc bd list --status=in_progress,open --json --limit=0 | tr -d '[:cntrl:]' | {
# >>> host-bead-skip
# Keep only beads that name an OWNER, and stamp that owner as `.owner` for the
# liveness loop. Reads the bead-list array on stdin, writes the surviving array
# on stdout.
#
# A bead names its owner in up to three places and only one of them is an
# assignee. A workflow STEP bead has no assignee at all: gc bd list --json omits
# the key when it is empty, and the step names its owner in
# metadata.gc.session_id, which is what gc.session_affinity=require pins it to.
# A workflow ROOT bead names only metadata.gc.session_name.
#
# Precedence runs session id, then assignee, then session name. Only the id
# names a session that will never come back. It is re-stamped on every claim, so
# it always names the session actually holding the bead. The other two are labels
# a successor inherits: pool work is assigned to the slot, and the slot stays
# live under whoever holds it next. A crashed pool session leaves a bead whose
# assignee and session name both name that still-live slot, so resolving it on
# either label reports the successor's life as the dead owner's, and the bead
# stays in_progress under an owner that never returns.
jq -c '[ .[]
  | . as $bead
  | (.metadata // {}) as $m
  | ([ ($m["gc.session_id"] // ""), (.assignee // ""), ($m["gc.session_name"] // "") ]
     | map(select(. != "")) | first) as $owner
  | select($owner != null)
  | $bead + {owner: $owner} ]'
# <<< host-bead-skip
} | {
# >>> downstream-court-skip
# Drop beads whose work already reached a downstream court, so orphan recovery
# never returns finished work to the pool or marks it. The crash-loop signal is a
# RATE off recovered_at/recovered_count, so a re-recovered in-flight bead
# escalates a moot visit each cycle; dropping it here is what stops both the
# re-dispatch and the escalation. Two states name not-the-pool's work: an
# in-flight PR (merge_result pre_open_gate/pull_request) or a human gate
# (gc.routed_to=human). pr.machine is not read: a progressing stamp is written
# only with an anchor merge_result, which unanchoring clears while leaving the
# stamp, so on a repooled bead it is stale — the in-flight-PR test already covers
# a bead still in the machine. A bead carrying neither state is still the pool's
# to recover. Reads the candidate array on stdin (the host-bead-skip result),
# writes the survivors on stdout, and touches no field a survivor arrived with.
jq -c '[ .[]
  | (.metadata // {}) as $m
  | ($m.merge_result // "") as $mr
  | ($m["gc.routed_to"] // "") as $routed
  | select($mr != "pre_open_gate" and $mr != "pull_request"
           and $routed != "human") ]'
# <<< downstream-court-skip
} | {
# >>> topology-root-skip
# Drop graph.v2 topology ROOTS before the liveness loop. A root names its owner
# only in gc.session_name — the pool SLOT, which a successor session keeps alive
# — so resolving its liveness reads the successor's life as the dead run's and
# warrants a live session; and a root has no worktree, so the salvage path only
# churns a witness-salvage-refused notice. A root is not recoverable work: its
# steps carry the work and the gc.session_id, and its close is the
# control-dispatcher's workflow-finalize. The kind set is
# beadmeta.WorkflowTopologyKinds (workflow, scope, spec) — the same set the hook
# (hookCandidateClaimable) and pool demand (demandRowServable) refuse, mirrored
# by liveness-sweep.sh's topology_kind. Reads the candidate array on stdin (the
# downstream-court-skip result), writes the survivors on stdout, and touches no
# field a survivor arrived with.
jq -c '[ .[]
  | (.metadata // {}) as $m
  | ($m["gc.kind"] // "") as $kind
  | select($kind != "workflow" and $kind != "scope" and $kind != "spec") ]'
# <<< topology-root-skip
} > "$CANDIDATES"
# A file that is not a JSON array is a failed listing, not a rig with no
# candidates.
if jq -e 'type == "array"' "$CANDIDATES" >/dev/null 2>&1; then
  jq -r '.[] | .id + " " + .owner' "$CANDIDATES"
else
  echo "witness: the candidate listing did not parse; no orphan recovery this cycle" >&2
fi
rm -f "$CANDIDATES"
# <<< candidate-pipeline
}

# witness_liveness_map — build the identity->state map ONCE per cycle, before
# the first bead is read, keyed on id, name, session_name, alias, agent_name
# and configured_named_identity. Pool instances get NEW ids on restart, so
# liveness is session-ID liveness, never template matching. Both blobs stream
# through temp files, never --argjson (ARG_MAX).
#
# MAP_TRIP is the entire fail-safe test: non-empty means the map failed to load,
# which would false-orphan live agents, so the cycle skips orphan recovery. An
# owner that resolves `absent` against a POPULATED map is never grounds for the
# fail safe: closed sessions are excluded from `gc session list` by design, and
# `--state=closed` never returns a row, so a bead naming a closed session always
# resolves absent, which is the orphan signal. The session beads answer an empty array on a healthy city (gc bd list
# drops issue_type=session), so an empty second source is not an empty map.
witness_liveness_map() {
# >>> liveness-map-guard
# Builds the map and answers the ONE question the fail safe asks: did the map
# itself fail to load. Sets LIVENESS_MAP, MAP_COUNT, and MAP_TRIP. MAP_TRIP is
# empty when the map is usable and carries the escalation reason otherwise. This
# runs once per cycle with no bead in scope, so no bead's owner can reach the
# decision.
SESSIONS_RAW=$(mktemp "${TMPDIR:-/tmp}/gctk-witness-patrol.XXXXXX")
SESSION_BEADS=$(mktemp "${TMPDIR:-/tmp}/gctk-witness-patrol.XXXXXX")
trap 'rm -f "$SESSIONS_RAW" "$SESSION_BEADS" 2>/dev/null' EXIT
trap 'exit 130' INT; trap 'exit 143' TERM; trap 'exit 129' HUP
gc session list --state=all --json > "$SESSIONS_RAW" 2>/dev/null || true
gc bd list --type=session --label=gc:session --include-infra --all --json --limit=0 > "$SESSION_BEADS" 2>/dev/null || true
# The session list is the load-bearing source. A non-object, or an object with
# no .sessions array, is the READ failing, which is a different fact from a
# city that reports no sessions.
SESSIONS_OK=0
if jq -e 'type == "object" and (.sessions | type) == "array"' "$SESSIONS_RAW" >/dev/null 2>&1; then
  SESSIONS_OK=1
fi
# Normalize both sources to a shape the builder cannot fail on, so MAP_COUNT is
# a number on every path and the trip below is decided by SESSIONS_OK rather
# than by how the builder happened to die. The session beads contribute keys
# when they can and are never required: an unusable answer from them
# contributes nothing rather than failing the cycle.
[ "$SESSIONS_OK" = "1" ] || printf '{"sessions":[]}' > "$SESSIONS_RAW"
jq -e 'type == "array"' "$SESSION_BEADS" >/dev/null 2>&1 || printf '[]' > "$SESSION_BEADS"
LIVENESS_MAP=$(jq -n --slurpfile s "$SESSIONS_RAW" --slurpfile b "$SESSION_BEADS" '
  def kv($st): [ .id, .name, .session_name, .alias, .agent_name, .configured_named_identity ]
    | map(select(type == "string" and . != "")) | map({key: ., value: $st});
  # Bead keys first, session-list keys second: from_entries lets the later
  # entry win, which keeps the authoritative source authoritative.
  [ (($b[0] // [])[] | kv(.status // "active")) ]
  + [ (($s[0].sessions // [])[] | kv(.state // "active")) ]
  | add // {} | from_entries' 2>/dev/null) || LIVENESS_MAP=""
MAP_COUNT=$(printf '%s' "$LIVENESS_MAP" | jq 'length' 2>/dev/null) || MAP_COUNT=""
# Ordered by authority, and total: a count that is not a number means the
# builder died behind a source that read fine, which is still a map that
# cannot be trusted. Falling through to an empty MAP_TRIP would skip the
# fail safe on an unusable map, so the two assignments above absorb their own
# failure: under `set -e` an abort would leave MAP_TRIP unset, and unset reads
# as no trip.
MAP_TRIP=""
if [ "$SESSIONS_OK" != "1" ]; then
  MAP_TRIP="session list unreadable"
else
  case "$MAP_COUNT" in
    ''|*[!0-9]*) MAP_TRIP="liveness map unreadable" ;;
    0)           MAP_TRIP="liveness map empty" ;;
  esac
fi
rm -f "$SESSIONS_RAW" "$SESSION_BEADS"
trap - EXIT INT TERM HUP
# <<< liveness-map-guard
}

# witness_liveness_lookup — resolve OWNER against LIVENESS_MAP into STATE,
# exact-first, with ONE narrow fallback: the last `/`-segment, resolved toward
# LIFE. A collision with any non-closed session reads as alive, so the retry can
# un-orphan, never manufacture an orphan. A session id is a map key like any
# other, so the two passes answer for an assignee, a session name and an id.
witness_liveness_lookup() {
# >>> liveness-lookup
# Exact lookup first: authoritative whenever the owner is a literal map key.
STATE=$(printf '%s' "$LIVENESS_MAP" | jq -r --arg a "$OWNER" '.[$a] // "absent"')
# Identity-normalizing fallback. Stripping the prefix can make two sessions in
# different cities collide on one bare identity, so resolve a collision toward
# LIFE: any matching session that is not closed/archived wins. Only when EVERY
# candidate owner is dead does the fallback report a dead state.
if [ "$STATE" = "absent" ]; then
  STATE=$(printf '%s' "$LIVENESS_MAP" | jq -r --arg a "$OWNER" '
    def bare: sub("^.*/"; "");
    [ to_entries[] | select((.key | bare) == ($a | bare)) | .value ] as $matches
    | if ($matches | length) == 0 then "absent"
      else ([ $matches[] | select(. != "closed" and . != "archived") ] | first) // $matches[0]
      end')
fi
# <<< liveness-lookup
}

# witness_salvage_context — read BEAD's recovery pointers and resolve the repo
# that OWNS its branch. The witness runs from its agent home, whose git toplevel
# is the town repo, so an unpinned git or gh call resolves `origin` there and a
# branch living in a rig repo reads as absent: a false "gone" that invites
# discarding pushed work. branch-context.sh resolves the owning rig (store ref,
# then work_dir, then the patrol's own rig), pins every existence, geometry and
# push check to it, and reports `unknown` for anything it cannot assert.
witness_salvage_context() {
BEAD_JSON=$(gc bd show "$BEAD" --json)
WORKTREE=$(printf '%s' "$BEAD_JSON" | jq -r '.[0].metadata.work_dir // empty')
BRANCH=$(printf '%s' "$BEAD_JSON" | jq -r '.[0].metadata.branch // empty')
STORE_REF=$(printf '%s' "$BEAD_JSON" | jq -r '.[0].metadata["gc.root_store_ref"] // empty')
BC=""; for c in "${GC_RIG_ROOT:-}" "$(git rev-parse --show-toplevel 2>/dev/null)" "${GC_CITY_PATH:-}/rigs/gc-toolkit"; do
  [ -x "$c/assets/scripts/branch-context.sh" ] && { BC="$c/assets/scripts/branch-context.sh"; break; }
done
eval "$("$BC" resolve --store-ref "$STORE_REF" --worktree "$WORKTREE" --branch "$BRANCH")"
# sets RIG_ROOT, OWNER_REPO, OWNING_ORIGIN_URL, REPO_CTX, BRANCH_ON_ORIGIN
}

# witness_salvage_scope — set IS_WORK_BEAD. Salvage and the merge verify are
# work-bead operations: a visit, a review, a graph.v2 step or a root has no
# worktree to salvage and no branch of its own, and goes straight to disposal.
witness_salvage_scope() {
# >>> salvage-scope-gate
# Salvage and part 4's merge-verify are WORK-BEAD operations: both read
# metadata.work_dir and metadata.branch, which a polecat stamps on the work
# (source) bead alone. A visit, a review, a graph.v2 step and a graph.v2 root
# carry neither — a review's review_branch names the anchor under review, not
# work of its own — so salvaging one refuses on the husk guard and files a
# no-signal witness-salvage-refused, and verifying one reads `unknown` off an
# empty branch and escalates witness-branch-recovery-unknown. Classify the bead
# as part 5's orphan-dispose.sh does — task_kind=visit, then task_kind=review,
# then a root (gc.kind=workflow or gc.formula_contract=graph.v2), then a step
# (gc.step_ref), else a source — and salvage only a source; anything else skips
# to part 5, which releases or skips it by that same class.
# salvage-scope-gate.test.sh runs this gate and orphan-dispose.sh over one set of
# fixtures and asserts they agree, so the two classifiers cannot drift. An
# unreadable classification defaults to the work-bead path: recovery is
# load-bearing and salvage self-guards on the husk check, so it never skips a
# real orphan.
IS_WORK_BEAD=$(printf '%s' "$BEAD_JSON" | jq -r '
  (.[0].metadata // {}) as $m
  | if   ($m.task_kind // "") == "visit" then "0"
    elif ($m.task_kind // "") == "review" then "0"
    elif (($m["gc.kind"] // "") == "workflow") or (($m["gc.formula_contract"] // "") == "graph.v2") then "0"
    elif ($m["gc.step_ref"] // "") != "" then "0"
    else "1" end' 2>/dev/null)
case "$IS_WORK_BEAD" in 1|0) ;; *) IS_WORK_BEAD=1 ;; esac
# <<< salvage-scope-gate
}

# witness_nothing_to_salvage — set NOTHING_TO_SALVAGE for a source work bead
# carrying neither a worktree nor a branch: its owner died before
# workspace-setup, so there is nothing to salvage and no branch to verify. Without
# this mark, salvage would file a no-signal witness-salvage-refused and the
# verify would escalate a branch recovery for a branch that never existed.
witness_nothing_to_salvage() {
# >>> nothing-to-salvage-gate
NOTHING_TO_SALVAGE=0
if [ "$IS_WORK_BEAD" = "1" ] && [ -z "$WORKTREE" ] && [ -z "$BRANCH" ]; then
  NOTHING_TO_SALVAGE=1
fi
# <<< nothing-to-salvage-gate
}

# witness_husk_guard — set WORKTREE_SAFE only when work_dir is its OWN worktree
# root. A husk directory (worktree removed, directory survives) lets `cd`
# succeed while every git command resolves to the ENCLOSING repo, so a salvage
# `git add -A && git push` would publish that repo's working tree.
witness_husk_guard() {
# >>> husk-guard
WORKTREE_SAFE=0
if [ -n "$WORKTREE" ] && [ -d "$WORKTREE" ]; then
  EXPECTED_ROOT=$(cd "$WORKTREE" && pwd -P)
  ACTUAL_ROOT=$(git -C "$WORKTREE" rev-parse --show-toplevel 2>/dev/null)
  if [ -n "$ACTUAL_ROOT" ] && [ "$ACTUAL_ROOT" = "$EXPECTED_ROOT" ]; then
    WORKTREE_SAFE=1
  else
    echo "witness: REFUSING salvage for $BEAD — work_dir $WORKTREE is a husk (git toplevel='${ACTUAL_ROOT:-<none>}' != worktree root '$EXPECTED_ROOT'); skipping add/commit/push to avoid town-repo contamination." >&2
  fi
fi
# <<< husk-guard
}

# witness_salvage — publish BEAD's unpublished worktree work to its branch. A
# branch already on origin needs no salvage. The push is gated on
# push-target-ok, which refuses when the worktree's origin is not the owning
# origin (a husk points it at the wrong repo). A push of work that may already
# be on origin is idempotent and never loses commits, while `unknown` is never
# read as gone.
witness_salvage() {
if [ "$IS_WORK_BEAD" != "1" ]; then
  echo "not a work bead (a visit, a review, or a graph.v2 step or root) — no worktree by construction; skipping salvage, straight to disposal." >&2
elif [ "$NOTHING_TO_SALVAGE" = "1" ]; then
  echo "source work bead with no work_dir and no branch — never had a worktree; nothing to salvage, straight to disposal." >&2
elif [ "$BRANCH_ON_ORIGIN" = "present" ]; then
  echo "branch already on origin — worktree disposable; skipping salvage." >&2
elif [ "$WORKTREE_SAFE" = "1" ] && "$BC" push-target-ok --worktree "$WORKTREE" --owning-origin "$OWNING_ORIGIN_URL" --bead "$BEAD"; then
  cd "$WORKTREE" || return 1
  git status --porcelain
  # All work is useful work — commit whatever is uncommitted, then publish.
  git add -A
  git commit -m "witness: salvage work from orphaned agent ($BEAD)" || true
  BRANCH=$(git branch --show-current)
  git push origin HEAD
  gc bd update "$BEAD" --set-metadata branch="$BRANCH"
else
  echo "husk, wrong-origin, or missing work_dir — REFUSING salvage writes (see guards); nothing salvageable." >&2
fi
}

# witness_verify — set BRANCH_MERGED: whether the work bead's branch already
# landed on its target. branch-context.sh merged reads it after the salvage
# push and defers to the compare API on a shallow checkout, whose grafted
# boundary makes a landed branch read as unmerged; a branch it cannot freshly
# fetch is `unknown`, never a stale-ref discard.
witness_verify() {
if [ "$IS_WORK_BEAD" = "1" ]; then
  if [ "$NOTHING_TO_SALVAGE" = "1" ]; then
    BRANCH_MERGED=skip   # never had a branch; nothing to verify, go to part 5
  else
    TARGET=$(printf '%s' "$BEAD_JSON" | jq -r '.[0].metadata.target // "main"')
    BRANCH_MERGED=$("$BC" merged --store-ref "$STORE_REF" --worktree "$WORKTREE" --branch "$BRANCH" --target "$TARGET")
  fi
else
  BRANCH_MERGED=skip   # no branch by construction; nothing to verify, go to part 5
fi
}

# witness_owning_store — set OWNED only when BEAD is provably present in the
# store its own id prefix names. The worktree is removed on the authority of the
# bead that owns it, and a bare `gc bd show` miss is answered by the store you
# stand in, not the one the prefix names, so it cannot tell a bead gone from a
# lookup sent to the wrong store. bead-store.sh --present asks the prefix's
# store by --db and refuses an unknown prefix as readily as a missing bead.
witness_owning_store() {
# >>> owning-store-guard
BS=""; for c in "${GC_RIG_ROOT:-}" "$(git rev-parse --show-toplevel 2>/dev/null)" "${GC_CITY_PATH:-}/rigs/gc-toolkit"; do
  [ -x "$c/assets/scripts/bead-store.sh" ] && { BS="$c/assets/scripts/bead-store.sh"; break; }
done
OWNED=0
if [ -z "$BS" ]; then
  echo "witness: bead-store.sh not found — the store owning $BEAD is unproven; REFUSING to remove $WORKTREE" >&2
elif "$BS" --present "$BEAD"; then
  OWNED=1
else
  echo "witness: $BEAD does not resolve in the store its prefix names — REFUSING to remove $WORKTREE; a worktree whose owner cannot be placed is not an unowned one" >&2
fi
# <<< owning-store-guard
}

# witness_worktree_cleanup — remove the worktree only under the owning-store
# guard, only when the bead recorded one, and from the rig root, never letting a
# failed removal abort the stage: `git worktree remove` exits 128 for a path
# naming no registered worktree (a husk, an already-pruned path), and under
# set -e that would abort before disposal runs. The rig root is required
# because a husk resolves the worktree list from the wrong repo.
witness_worktree_cleanup() {
# >>> worktree-cleanup
if [ "$OWNED" = "1" ] && [ -n "$WORKTREE" ]; then
  if ! git -C "${GC_RIG_ROOT:-.}" worktree remove "$WORKTREE" --force; then
    echo "witness: 'git worktree remove $WORKTREE' failed — a husk or already-removed path names no registered worktree; continuing to prune and disposal." >&2
  fi
  git -C "${GC_RIG_ROOT:-.}" worktree prune
fi
# <<< worktree-cleanup
}

# witness_dispose — hand BEAD to orphan-dispose.sh, which disposes of it by what
# it is, and capture its verdict in DISPOSE_RESULT and DISPOSE_RC. A visit gives
# up its assignee and nothing else. A review is the source of its own mol-review
# molecule and reopens to its review pool. A workflow step under a live root
# gives up the dead session's pin and keeps the rest, so the molecule resumes at
# that step; a step whose root CLOSED goes to dead-molecule-dispose.sh, and one
# whose root will not read is left untouched. A workflow root is skipped:
# nothing claims a root. Everything else is a source bead and goes through
# `gc workflow delete-source --apply` then `reopen-source`, which match roots on
# gc.source_bead_id and so must never run on a step or a root. Exit 3 is a
# PARTIAL write: the bead is half-released and needs a finding, not a retry.
witness_dispose() {
OD=""; for c in "${GC_RIG_ROOT:-}" "$(git rev-parse --show-toplevel 2>/dev/null)" "${GC_CITY_PATH:-}/rigs/gc-toolkit"; do
  [ -x "$c/assets/scripts/orphan-dispose.sh" ] && { OD="$c/assets/scripts/orphan-dispose.sh"; break; }
done
DISPOSE_RESULT=""; DISPOSE_RC=0
if [ -z "$OD" ]; then
  echo "orphan-dispose.sh not found — NOT disposing of $BEAD; it stays owned and returns next cycle" >&2
else
  # Capture the disposal's own verdict: it decides whether this bead was RETURNED
  # to the pool (result=disposed) or left untouched (result=skipped — a root, or a
  # source already in a downstream court). `|| DISPOSE_RC=$?` keeps a non-zero exit
  # (3 partial, 1 failed) from killing the step under set -e; the JSON is printed
  # before either exit, so DISPOSE_RESULT still reads.
  DISPOSE_JSON=$("$OD" "$BEAD" --owner "$OWNER" --apply --json) || DISPOSE_RC=$?
  printf '%s\n' "$DISPOSE_JSON"
  DISPOSE_RESULT=$(printf '%s' "$DISPOSE_JSON" | jq -r '.result // ""')
fi
}

# witness_recovery_stamp_gate — set STAMP_RECOVERY from the disposal's own
# verdict. A disposal that SKIPPED changed nothing, so stamping a recovery on it
# would feed the crash-loop RATE a recovery that never re-dispatched anything.
witness_recovery_stamp_gate() {
# >>> recovery-stamp-gate
# STAMP_RECOVERY is 1 only for a bead orphan-dispose RETURNED to the pool
# (result=disposed: a released visit or step, or a delegated source or review). Every other
# verdict — skipped (a root, or a source already in a downstream court), partial,
# failed, or an unread empty — returned nothing to the pool, so no recovery is
# stamped and no crash-loop rate is read.
case "${DISPOSE_RESULT:-}" in
  disposed) STAMP_RECOVERY=1 ;;
  *)        STAMP_RECOVERY=0 ;;
esac
# <<< recovery-stamp-gate
}

# witness_prev_recovery — read the recovery history BEAD already carries, BEFORE
# witness_record overwrites it.
witness_prev_recovery() {
PREV=$(gc bd show "$BEAD" --json | scrub | jq -r '.[0].metadata // {} | [(.recovered_at // ""), (.recovered_count // ""), (.recovered // "")] | @tsv')
PREV_AT=$(printf '%s' "$PREV" | cut -f1)
PREV_COUNT=$(printf '%s' "$PREV" | cut -f2)
PREV_FLAG=$(printf '%s' "$PREV" | cut -f3)
}

# witness_crash_loop_window — decide CRASH_LOOP against a window. A crash loop
# is a RATE, not a mark: a bare recovered=true is a flag nothing clears, so
# reading a repeat recovery off its presence makes every bead ever recovered a
# permanent escalation candidate. Two recoveries three days apart are two
# incidents; a loop is recurrence faster than the work can progress.
witness_crash_loop_window() {
# >>> crash-loop-window
# Inputs: PREV_AT, PREV_COUNT and PREV_FLAG — metadata.recovered_at,
# recovered_count and recovered as they stood BEFORE this recovery, each empty
# when the key is absent. Sets NOW_AT, COUNT, and CRASH_LOOP=1 only when the
# previous recovery falls inside the window.
#
# An absent or unparseable PREV_AT is UNKNOWN, never "long ago, therefore a
# loop". Beads carrying a bare recovered=true predate this record and hold no
# evidence of recurrence at all, so they stamp a first timestamp and escalate
# nothing: the legacy population drains in one pass instead of escalating
# itself. The flag still proves one prior recovery, so the count it seeds is 2.
CRASH_LOOP_WINDOW="${CRASH_LOOP_WINDOW:-21600}"
NOW_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
case "${PREV_COUNT:-}" in
  ''|*[!0-9]*) case "${PREV_FLAG:-}" in true) COUNT=2 ;; *) COUNT=1 ;; esac ;;
  *)           COUNT=$((PREV_COUNT + 1)) ;;
esac
CRASH_LOOP=0
# jq reads the %Y-%m-%dT%H:%M:%SZ form NOW_AT stamps as UTC in any local zone,
# and the epoch it gives does not depend on which date(1) the host ships. A
# value it cannot parse, an empty one included, leaves PREV_EPOCH empty.
PREV_EPOCH=$(jq -rn --arg t "${PREV_AT:-}" '$t | fromdateiso8601' 2>/dev/null || printf '')
NOW_EPOCH=$(date -u +%s)
# `if`, not `[ ... ] && CRASH_LOOP=1`: a false test makes that AND-list the
# block's last command and its exit status 1, so under `set -e` the caller dies
# on the ordinary not-a-loop path, which is the one taken almost every cycle.
case "$PREV_EPOCH" in
  ''|*[!0-9]*) : ;;
  *) if [ "$((NOW_EPOCH - PREV_EPOCH))" -lt "$CRASH_LOOP_WINDOW" ]; then CRASH_LOOP=1; fi ;;
esac
# <<< crash-loop-window
}

# witness_record — stamp the recovery forward on a disposed bead. A skip stamps
# nothing, so the crash-loop RATE is never fed a recovery that did not happen.
witness_record() {
# Only a disposed bead is a recovery (recovery-stamp-gate above); a skip stamps
# nothing, so the crash-loop RATE is never fed a recovery that did not happen.
if [ "$STAMP_RECOVERY" = "1" ]; then
  gc bd update "$BEAD" --set-metadata recovered=true --set-metadata "recovered_at=$NOW_AT" --set-metadata "recovered_count=$COUNT"
fi
}
