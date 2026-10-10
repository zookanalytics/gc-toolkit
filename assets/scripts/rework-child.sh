#!/usr/bin/env bash
# rework-child.sh — the one writer of a rework child: the fix unit that blocks an
# anchor while a worker resumes the anchor's own branch. A review verdict
# (signoff.sh, --review-bead) and an operator ruling (converse-rework.sh,
# --ruling-bead) each demand rework through it, and the flag names the source key
# the child carries: source_review_bead or source_ruling_bead. The caller decides
# the work order: the branch the child resumes, where it lands, the PR it keeps,
# its title and its rejection_reason.
#
# The store has no transactions, so filing is a sequence in which each step is
# proved before the next one relies on it, and a retry finishes what an earlier
# run started:
#   - The pool route is proved before any write (pool-route.sh). A refusal there
#     is simply retried, while a child no pool claims is found only by a human.
#   - A source key owns at most one live child. A live child carrying the key is
#     adopted, preferring one already dispatched. Otherwise the child is created
#     with its identity (task_kind, anchor_bead and the source key) inside the
#     create, so no run leaves a child its retry cannot find. A dedup query that
#     does not answer files nothing, because an unreadable answer cannot be told
#     from no child.
#   - The work order and the child's blocks edge onto the anchor are written,
#     then read back before dispatch. The edge is what holds the merge.
#   - The child is slung with mol-polecat-work, and the dispatch is proved by
#     reading gc.execution_routed_to back. A pour that does not read back may
#     still have started the workflow, so the writer never stamps a bare route,
#     which would let the pool and the workflow both take the work.
# A child already dispatched is reported and left alone. prepare_mode is not
# stamped: the resume merges the base into a rejected branch whatever the stamp
# says, and the refinery stamps it on every prepare.
#
# Usage:
#   rework-child.sh --anchor <id> (--review-bead <id> | --ruling-bead <id>) \
#     --branch <branch> --target <branch> --title "<title>" --reason "<text>" \
#     [--pr-url <url>] [--pr-number <n>] [--pool <pool-name>]
#   --reason is the rejection_reason the resumed worker starts from; an adopted
#   child that already records one keeps it. --pr-url keeps the rework on that PR
#   (existing_pr, pr_url) and --pr-number names it; pre-open work passes neither.
#   --pool defaults to gc-toolkit.polecat.
# Output: one line on stdout, "<child> <route> <filed|adopted|in-flight>"; the
#   narrative goes to stderr.
# Exit: 0 the child stands dispatched · 1 usage, nothing written · 2 not
#   dispatched: refused before any write, or a write that did not land or read
#   back, which can leave the child blocking the anchor for a retry to adopt
set -uo pipefail

_lib_dir="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=bd-lib.sh
. "${GC_BD_LIB:-$_lib_dir/bd-lib.sh}" || { echo "rework-child: cannot source bd-lib.sh beside this script" >&2; exit 2; }
SCRIPT_DIR=$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")

warn()  { echo "rework-child: $*" >&2; }
usage() { warn "$1"; exit 1; }
fail()  { warn "$1"; exit 2; }
row_meta() { printf '%s' "$1" | jq -r --arg k "$2" '(.[0].metadata[$k] // "") | tostring' 2>/dev/null; }
LIVE_STATUSES="open,in_progress,blocked,deferred,hooked,pinned"

ANCHOR=""; SRC_KEY=""; SRC_BEAD=""; BRANCH=""; TARGET=""; TITLE=""; REASON=""
PR_URL=""; PR_NUMBER=""; POOL_NAME="gc-toolkit.polecat"
need() { [ "$2" -gt 1 ] || usage "$1 needs a value"; }
provenance() { # <source-key> <bead>
  [ -z "$SRC_KEY" ] || usage "name one provenance: --review-bead or --ruling-bead"
  SRC_KEY="$1"; SRC_BEAD="$2"
}
while [ $# -gt 0 ]; do
  case "$1" in
    --anchor)      need "$1" $#; ANCHOR="$2"; shift ;;
    --review-bead) need "$1" $#; provenance source_review_bead "$2"; shift ;;
    --ruling-bead) need "$1" $#; provenance source_ruling_bead "$2"; shift ;;
    --branch)      need "$1" $#; BRANCH="$2"; shift ;;
    --target)      need "$1" $#; TARGET="$2"; shift ;;
    --title)       need "$1" $#; TITLE="$2"; shift ;;
    --reason)      need "$1" $#; REASON="$2"; shift ;;
    --pr-url)      need "$1" $#; PR_URL="$2"; shift ;;
    --pr-number)   need "$1" $#; PR_NUMBER="$2"; shift ;;
    --pool)        need "$1" $#; POOL_NAME="$2"; shift ;;
    -h|--help)     sed -n '2,/^set -uo pipefail$/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)             usage "unknown argument '$1'" ;;
  esac
  shift
done
[ -n "$ANCHOR" ]    || usage "--anchor is required"
[ -n "$SRC_BEAD" ]  || usage "--review-bead or --ruling-bead is required: the verdict or the ruling the rework answers"
[ -n "$BRANCH" ]    || usage "--branch is required: the branch the child resumes"
[ -n "$TARGET" ]    || usage "--target is required: the branch the rework lands on"
[ -n "$TITLE" ]     || usage "--title is required"
[ -n "$REASON" ]    || usage "--reason is required: the rejection_reason the resumed worker starts from"
[ -n "$POOL_NAME" ] || usage "--pool needs a pool name"
command -v jq >/dev/null 2>&1 || fail "jq is required; nothing filed"
command -v gc >/dev/null 2>&1 || fail "gc is required; nothing filed"

bd_json show "$ANCHOR" | jq -e 'type == "array" and length > 0' >/dev/null 2>&1 \
  || fail "anchor $ANCHOR does not resolve; nothing filed"
POOL=$("$SCRIPT_DIR/pool-route.sh" "$POOL_NAME") \
  || fail "the rework child would route to '$POOL_NAME', which no live pool claims; nothing filed"

# The source key is the dedup key: a review bead or a visit id names one review of
# one anchor, or one sitting's ruling, and only a rework child carries it. When
# more than one live child carries it, the one already dispatched wins: a prior
# run filed one and died before dispatch while a retry filed and dispatched
# another, and re-slinging the inert one would double-dispatch the molecule the
# routed one owns.
if ! PRIOR=$(bd_list --metadata-field "$SRC_KEY=$SRC_BEAD" --status="$LIVE_STATUSES"); then
  fail "could not read prior rework children for $SRC_KEY=$SRC_BEAD (dedup query failed); nothing filed rather than risk a second child"
fi
FIX_BEAD=$(printf '%s' "$PRIOR" | jq -r --arg k "$SRC_KEY" --arg v "$SRC_BEAD" '
    [ .[]? | select(((.metadata[$k] // "") | tostring) == $v) ]
    | sort_by(.created_at // .id) as $all
    | ( ( [ $all[] | select((.metadata["gc.execution_routed_to"] // "") != "") ][0] )
        // $all[0] )
    | (.id // empty)' 2>/dev/null)

if [ -n "$FIX_BEAD" ]; then
  ADOPT_ROW=$(bd_json show "$FIX_BEAD")
  ADOPT_ROUTE=$(row_meta "$ADOPT_ROW" "gc.execution_routed_to")
  if [ -n "$ADOPT_ROUTE" ]; then
    # Re-stamping or re-slinging an in-flight child would stomp a live worktree or
    # double-dispatch its molecule.
    warn "rework child $FIX_BEAD ($SRC_KEY=$SRC_BEAD) already dispatched to $ADOPT_ROUTE; filing no second child"
    printf '%s %s in-flight\n' "$FIX_BEAD" "$ADOPT_ROUTE"
    exit 0
  fi
  warn "adopting existing open rework child $FIX_BEAD for $SRC_KEY=$SRC_BEAD (a prior attempt filed it but never dispatched); filing no second child"
  # The reason a prior attempt recorded answers this same source, so it stands.
  [ -n "$(row_meta "$ADOPT_ROW" rejection_reason)" ] && REASON=""
  STATE=adopted
else
  IDENTITY=$(jq -nc --arg a "$ANCHOR" --arg k "$SRC_KEY" --arg v "$SRC_BEAD" \
    '{task_kind: "rework", anchor_bead: $a} + {($k): $v}' 2>/dev/null)
  [ -n "$IDENTITY" ] || fail "could not build the rework child's identity metadata; nothing filed"
  FIX_BEAD=$(gc bd create "$TITLE" -t task --metadata "$IDENTITY" --json 2>/dev/null \
    | jq -r 'if type == "array" then (.[0].id // empty) else (.id // empty) end' 2>/dev/null)
  [ -n "$FIX_BEAD" ] \
    || fail "the rework child create returned no id; a retry adopts the child by $SRC_KEY=$SRC_BEAD if the create landed"
  STATE=filed
fi

# The stamped fields are the work order: branch and target say what to resume and
# where it lands, existing_pr keeps the rework on that PR, and the source key
# names what it answers. task_kind and anchor_bead are the role marker: the child
# resumes the anchor's own branch, so without them a metadata read cannot tell
# the child from the anchor.
META=(
  --set-metadata "task_kind=rework"
  --set-metadata "anchor_bead=$ANCHOR"
  --set-metadata "branch=$BRANCH"
  --set-metadata "target=$TARGET"
  --set-metadata "$SRC_KEY=$SRC_BEAD"
  --set-metadata "merge_strategy=mr"
)
[ -n "$REASON" ]    && META+=(--set-metadata "rejection_reason=$REASON")
[ -n "$PR_URL" ]    && META+=(--set-metadata "existing_pr=$PR_URL" --set-metadata "pr_url=$PR_URL")
[ -n "$PR_NUMBER" ] && META+=(--set-metadata "pr_number=$PR_NUMBER")
gc bd update "$FIX_BEAD" "${META[@]}" >/dev/null 2>&1 || true

# The child must BLOCK the anchor. Recorded the other way round it waits on an
# anchor that closes only once the rework lands, so nothing ever claims it. An
# adopted child already carries the edge, and a second identical edge is one
# every walk of the anchor's blockers sees twice.
if ! bd_json dep list "$ANCHOR" --direction=down -t blocks \
     | jq -e --arg f "$FIX_BEAD" 'any(.[]?; .id == $f)' >/dev/null 2>&1; then
  gc bd dep "$FIX_BEAD" --blocks "$ANCHOR" >/dev/null 2>&1 || true
fi

# A claimed rework must never run against absent fields, so every field the
# resumed workflow reads, and the edge, is read back before the pour.
MISSING=$(bd_json show "$FIX_BEAD" | jq -r \
  --arg a "$ANCHOR" --arg b "$BRANCH" --arg t "$TARGET" --arg k "$SRC_KEY" --arg v "$SRC_BEAD" \
  --arg pr "$PR_URL" --arg pn "$PR_NUMBER" '
  ((.[0] // {}).metadata // {}) as $m | [
    (if ($m.task_kind // "") == "rework" then empty else "task_kind" end),
    (if ($m.anchor_bead // "") == $a then empty else "anchor_bead" end),
    (if ($m.branch // "") == $b then empty else "branch" end),
    (if ($m.target // "") == $t then empty else "target" end),
    (if (($m[$k] // "") | tostring) == $v then empty else $k end),
    (if ($m.merge_strategy // "") == "mr" then empty else "merge_strategy" end),
    (if ($m.rejection_reason // "") != "" then empty else "rejection_reason" end),
    (if $pr == "" or ($m.existing_pr // "") == $pr then empty else "existing_pr" end),
    (if $pn == "" or (($m.pr_number // "") | tostring) == $pn then empty else "pr_number" end)
  ] | join(",") | if . == "" then "ok" else . end' 2>/dev/null)
if [ "$MISSING" = "ok" ] && ! bd_json dep list "$ANCHOR" --direction=down -t blocks \
     | jq -e --arg f "$FIX_BEAD" 'type == "array" and any(.[]; .id == $f)' >/dev/null 2>&1; then
  MISSING="blocks_edge"
fi
[ "$MISSING" = "ok" ] \
  || fail "rework child $FIX_BEAD work order incomplete (${MISSING:-unreadable}); not dispatched, and a retry adopts it. Inspect it with: gc bd show $FIX_BEAD --json | jq '.[0].metadata'"

# mol-polecat-work gives the rework the control-dispatcher driver and continuation
# affinity a bare gc.routed_to has no driver for. The pour retires gc.routed_to and
# stamps gc.execution_routed_to=<pool>, and that read-back is the proof. Without it
# the child stays filed and blocking, and the merge stays held while a retry runs.
WORK_FORMULA="mol-polecat-work"
gc sling ${GC_RIG:+--rig "$GC_RIG"} "$POOL" "$FIX_BEAD" --on "$WORK_FORMULA" >/dev/null 2>&1
if [ "$(row_meta "$(bd_json show "$FIX_BEAD")" "gc.execution_routed_to")" != "$POOL" ]; then
  fail "rework child $FIX_BEAD: the $WORK_FORMULA pour did not stamp gc.execution_routed_to=$POOL; not falling back to a bare route (double-dispatch hazard). The child blocks the anchor, and a retry adopts and dispatches it"
fi
gc session wake "$POOL" >/dev/null 2>&1 || true
gc session nudge "$POOL" "Rework $FIX_BEAD for anchor $ANCHOR" >/dev/null 2>&1 || true
warn "$STATE rework $FIX_BEAD on anchor $ANCHOR ($SRC_KEY=$SRC_BEAD, branch $BRANCH -> $TARGET), slung $WORK_FORMULA to $POOL"
printf '%s %s %s\n' "$FIX_BEAD" "$POOL" "$STATE"
exit 0
