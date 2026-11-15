#!/usr/bin/env bash
# seed-audit-reaudit.sh — the one writer of the seed audit's re-audit: the bead
# that re-renders generated/seed-audit on the default branch and lands the new
# text in a pull request of its own, once that branch's audit has gone stale.
#
#   seed-audit-reaudit.sh --base <branch> [--page <path>]... [--seen-by <text>]
#                         [--pool <pool-name>]
#
# What a page renders to is a function of this repository and of the `gc`
# binary that renders it (render-seed-audit.sh, WHOSE TEXT IT IS). A newer build
# moves the pages that carry gc's own text on every branch at once, and a
# landing whose render was made before another landing moved an input it
# renders leaves that page stale on the branch it lands on. Two callers hand the
# pages here. The merge gate reports a page its base is already stale in as the
# base's own staleness and holds nothing on it (render-seed-audit.sh
# --check-merge --base-stale-out). The landing order checks the default branch
# after each landing on it and hands every page stale there (gctk pr
# reconcile). The new text lands as a change of its own: one bead, slung to the
# polecat pool on mol-polecat-work, whose pull request is the re-render and
# nothing else. That route stands on the operator's rulings, so it needs no
# placement sitting (docs/steering.md, the intake rule).
#
# --base is the branch the caller found stale. Only the default branch is
# re-audited. A branch cut from it inherits its audit and takes the re-render
# when it is brought current, and an integration branch's own staleness is that
# branch's to fix. --page names a file the caller found stale, by its path under
# generated/seed-audit, and the bead lists it; the re-render covers every file
# whatever the list says. --seen-by names who found it, for the bead's record.
# --pool defaults to gc-toolkit.polecat.
#
# The base owns at most one live re-audit, the live bead carrying
# seed_audit_reaudit=<base>. One already dispatched is reported and left alone.
# One filed and never dispatched, because an earlier run stopped between its
# create and its sling, is adopted and slung. One someone holds, routes or parks
# is reported and left alone, and so is one armed for a deferred dispatch
# (gc.dispatch_when_ready). A run that declined it waits on a human gate that
# way, and the arm re-slings it once the gate closes, so a sling from here would
# step past the person's ruling. A dedup query that does not answer files
# nothing, because an unreadable answer cannot be told from no bead, and it
# reads the store itself, never a pass's memo, since a memo taken before this
# run's own write would show no bead. Otherwise the bead is created with its
# identity in the create, settled at its priority (queue-priority.sh settle),
# and slung with mol-polecat-work, and each write's exit says whether it landed.
# An adopted bead is judged by the row the dedup query found it by. The route is
# proved after the dedup read and before any write, so a base whose re-audit is
# already in flight proves no route (pool-route.sh).
#
# One call at a time reads and writes a store's re-audits. A call holds the
# store's re-audit lock from before its dedup read until it exits: a flock on
# seed-audit-reaudit.lock in the .beads directory of the store gc resolves here
# (gc bd where), which the dedup query reads and the create writes. So two
# callers that overlap, such as two runs of the landing order that each land a
# PR on the default branch, cannot both read no live bead and each file and
# sling one. A call that finds the lock held files nothing: the call holding it
# is reading or writing the base's re-audit, and a retry reads what it left.
# Every gc call and script run under the lock starts with the lock's descriptor
# closed, so no process one leaves running, such as a Dolt server, holds the
# lock once this call has exited.
#
# Output: one line on stdout, "<bead> <route> <filed|adopted|in-flight|held>",
#   or "none <base> not-default" for a base that is not the default branch. The
#   narrative goes to stderr.
# Exit: 0 the base has its re-audit, or is not one to re-audit · 1 usage,
#   nothing written · 2 not dispatched: another call held the store's lock, or
#   the lock, the route, the dedup query, the create, the settle or the sling
#   did not land, and a retry adopts what was filed
set -uo pipefail

_lib_dir="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=bd-lib.sh
. "${GC_BD_LIB:-$_lib_dir/bd-lib.sh}" || { echo "seed-audit-reaudit: cannot source bd-lib.sh beside this script" >&2; exit 2; }
SCRIPT_DIR="$_lib_dir"
# bd_list's reads run under the store's re-audit lock, so they start without its
# descriptor, as every other call below does.
_bd_call() { gc bd "$@" 9>&-; }

PROG="seed-audit-reaudit"

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub
usage() { warn "$1"; exit 1; }
fail()  { warn "$1"; exit 2; }
LIVE_STATUSES="open,in_progress,blocked,deferred,hooked,pinned"
KEY="seed_audit_reaudit"
WORK_FORMULA="mol-polecat-work"

BASE=""; SEEN_BY=""; POOL_NAME="gc-toolkit.polecat"
PAGES=()
need() { [ "$2" -gt 1 ] || usage "$1 needs a value"; }
while [ $# -gt 0 ]; do
  case "$1" in
    --base)    need "$1" $#; BASE="$2"; shift ;;
    --page)    need "$1" $#; PAGES+=("$2"); shift ;;
    --seen-by) need "$1" $#; SEEN_BY="$2"; shift ;;
    --pool)    need "$1" $#; POOL_NAME="$2"; shift ;;
    -h|--help) sed -n '2,/^set -uo pipefail$/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)         usage "unknown argument '$1'" ;;
  esac
  shift
done
[ -n "$BASE" ] || usage "--base is required: the branch whose audit was found stale"
case "$BASE" in
  *[[:space:]]*|-*) usage "--base '$BASE' is not a branch name" ;;
esac
for p in ${PAGES[@]+"${PAGES[@]}"}; do
  case "$p" in
    ""|*$'\n'*) usage "--page needs a path under generated/seed-audit" ;;
  esac
done
[ -n "$POOL_NAME" ] || usage "--pool needs a pool name"
command -v jq >/dev/null 2>&1 || fail "jq is required; nothing filed"
command -v gc >/dev/null 2>&1 || fail "gc is required; nothing filed"

DEFAULT=$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null) || DEFAULT=""
DEFAULT="${DEFAULT#origin/}"
[ -n "$DEFAULT" ] || DEFAULT=main
if [ "$BASE" != "$DEFAULT" ]; then
  warn "'$BASE' is not the default branch ('$DEFAULT'), so it takes the default branch's re-audit when it is brought current; nothing filed"
  printf 'none %s not-default\n' "$BASE"
  exit 0
fi

unset GC_RECONCILE_BD_CACHE

# The store's re-audit lock (the header's rule), on fd 9 until the exit.
command -v flock >/dev/null 2>&1 \
  || fail "flock is not on PATH, so the store's re-audit lock cannot be taken; nothing filed"
STORE_DIR=$(gc bd where --json </dev/null 2>/dev/null | grep -a -v '^gc bd:' | scrub | jq -r '.path // empty' 2>/dev/null)
[ -n "$STORE_DIR" ] && [ -d "$STORE_DIR" ] \
  || fail "gc bd where named no store here, so no lock holds its re-audits to one call at a time; nothing filed"
LOCK="$STORE_DIR/seed-audit-reaudit.lock"
exec 9>>"$LOCK" || fail "the store's re-audit lock ($LOCK) does not open; nothing filed"
flock -n 9 \
  || fail "another call holds the store's re-audit lock ($LOCK) while it reads or writes $BASE's re-audit; this call filed nothing, and a retry reads what that call left"

if ! PRIOR=$(bd_list --metadata-field "$KEY=$BASE" --status="$LIVE_STATUSES"); then
  fail "could not read live re-audits for $KEY=$BASE (dedup query failed); nothing filed rather than risk a second one"
fi
# The oldest live bead is the base's re-audit, one already dispatched first.
# bd's metadata filter is trusted for nothing: each row is matched here too.
ROW=$(printf '%s' "$PRIOR" | jq -c --arg k "$KEY" --arg v "$BASE" '
    [ .[]? | select(((.metadata[$k] // "") | tostring) == $v) ]
    | sort_by(.created_at // .id) as $all
    | ( ( [ $all[] | select((.metadata["gc.execution_routed_to"] // "") != "") ][0] )
        // $all[0] )
    // empty' 2>/dev/null)

IDENTITY=$(jq -nc --arg k "$KEY" --arg b "$BASE" '{($k): $b, target: $b}' 2>/dev/null)
[ -n "$IDENTITY" ] || fail "could not build the re-audit's identity metadata; nothing filed"

if [ -n "$ROW" ]; then
  BEAD=$(printf '%s' "$ROW" | jq -r '.id // empty')
  ROUTE=$(printf '%s' "$ROW" | jq -r '(.metadata["gc.execution_routed_to"] // "") | tostring')
  if [ -n "$ROUTE" ]; then
    warn "$BASE's re-audit $BEAD is already dispatched to $ROUTE; filing no second one"
    printf '%s %s in-flight\n' "$BEAD" "$ROUTE"
    exit 0
  fi
  HOLDER=$(printf '%s' "$ROW" | jq -r '
      [ (if (.status // "") != "open" then "status " + (.status // "") else empty end),
        (if (.assignee // "") != "" then "assignee " + .assignee else empty end),
        (if ((.metadata["gc.routed_to"] // "") | tostring) != "" then "route " + (.metadata["gc.routed_to"] | tostring) else empty end),
        (if ((.metadata["gc.dispatch_when_ready"] // "") | tostring) != "" then "armed for " + (.metadata["gc.dispatch_when_ready"] | tostring) else empty end) ]
      | join(", ")' 2>/dev/null)
  if [ -n "$HOLDER" ]; then
    warn "$BASE's re-audit $BEAD is held ($HOLDER); leaving it to whoever holds it, and filing no second one"
    printf '%s - held\n' "$BEAD"
    exit 0
  fi
fi

POOL=$("$SCRIPT_DIR/pool-route.sh" "$POOL_NAME" 9>&-) \
  || fail "the re-audit would route to '$POOL_NAME', which no live pool claims; nothing filed"

if [ -n "$ROW" ]; then
  # The dedup query found the bead by its key alone, so the row it answered with
  # shows whether the bead carries the rest of its identity.
  SHORT=$(printf '%s' "$ROW" | jq -r --argjson id "$IDENTITY" \
    '(.metadata // {}) as $m | [ $id | to_entries[] | select((($m[.key] // "") | tostring) != (.value | tostring)) | .key ] | join(",")' 2>/dev/null) \
    || SHORT="unreadable"
  [ -z "$SHORT" ] || fail "re-audit $BEAD does not carry its whole identity (short: $SHORT); not dispatched"
  warn "adopting $BASE's re-audit $BEAD (a prior run filed it but never dispatched it); filing no second one"
  STATE=adopted
else
  PAGE_LIST=""
  for p in ${PAGES[@]+"${PAGES[@]}"}; do
    PAGE_LIST="${PAGE_LIST}- generated/seed-audit/$p
"
  done
  [ -n "$PAGE_LIST" ] || PAGE_LIST="- (none named: the render shows them)
"
  # shellcheck disable=SC2016  # the backticks are markdown in the bead body
  BODY=$(printf '## What happened\n\n%s found %s stale in the files of generated/seed-audit below: %s commits each of them other than as its own tree renders it. A committed page goes stale with no edit to it in two ways. The `gc` binary moves the text its builtin packs carry, the prompts and recipes those files mirror, on every branch at once (assets/scripts/render-seed-audit.sh, WHOSE TEXT IT IS). And a landing whose render was made before another landing moved an input it renders leaves that page stale.\n\n%s\n## The work\n\nOn a branch from %s, run `assets/scripts/render-seed-audit.sh` and commit generated/seed-audit as it renders, every file the render changes, including any not listed above. That re-render is the whole change. Edit no rendered file by hand and change no seed input: a page that reads wrong is corrected at its source, gc or this pack'"'"'s inputs, in a change of its own, and arrives here on the next render.\n\nIn the PR summary, name the gc that rendered it (`gc version`, the binary'"'"'s path and its build time) and say what text moved.\n\nIf the render changes nothing, %s already carries this text and there is nothing to land: decline the work through a human gate, as for a falsified premise, so a person closes this bead.' \
    "${SEEN_BY:-A caller}" "$BASE" "$BASE" "$PAGE_LIST" "$BASE" "$BASE")
  TITLE="Re-render the seed audit on $BASE: its pages no longer render as committed"
  # A create bd could not confirm after a lost connection exits non-zero and may
  # still have written, so a retry adopts by the key before it files again.
  CREATE_RC=0
  REPLY=$(gc bd create --title "$TITLE" -t task --priority=2 -d "$BODY" --metadata "$IDENTITY" --json </dev/null 2>/dev/null 9>&-) || CREATE_RC=$?
  REPLY=$(printf '%s' "$REPLY" | scrub)
  BEAD=$(printf '%s' "$REPLY" | jq -r 'if type == "array" then (.[0].id // empty) else (.id // empty) end' 2>/dev/null)
  [ "$CREATE_RC" = 0 ] \
    || fail "the re-audit create failed${REPLY:+: $(printf '%s' "$REPLY" | jq -r 'if type == "object" then (.error // empty) else empty end' 2>/dev/null)}; a retry adopts the bead by $KEY=$BASE if it was written anyway, and files it otherwise"
  [ -n "$BEAD" ] || fail "the re-audit create returned no id; a retry adopts the bead by $KEY=$BASE if the create landed"
  STATE=filed
fi

# A pour copies the bead's priority into its workflow once, so the bead is
# settled first. Its narrative goes to stderr, beside this script's own.
"${GC_QUEUE_PRIORITY_TOOL:-$SCRIPT_DIR/queue-priority.sh}" settle "$BEAD" >&2 9>&- \
  || fail "re-audit $BEAD did not settle at its priority (queue-priority.sh says why above); not dispatched, and a retry adopts it"

# mol-polecat-work gives the re-audit the control-dispatcher driver a bare
# gc.routed_to has no driver for, so a sling that fails is reported and never
# replaced by a bare route (double-dispatch hazard). The bead stays filed, and a
# retry adopts and slings it.
SLING_OUT=$(gc sling ${GC_RIG:+--rig "$GC_RIG"} "$POOL" "$BEAD" --on "$WORK_FORMULA" </dev/null 2>&1 9>&-) \
  || fail "re-audit $BEAD: the $WORK_FORMULA sling to $POOL failed (${SLING_OUT:-no reason given}); not falling back to a bare route (double-dispatch hazard), and a retry adopts and slings it"
warn "$STATE $BASE's re-audit $BEAD, slung $WORK_FORMULA to $POOL"
printf '%s %s %s\n' "$BEAD" "$POOL" "$STATE"
exit 0
