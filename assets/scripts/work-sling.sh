#!/usr/bin/env bash
# work-sling.sh — sling a work bead so that the run it pours works on that bead.
#   work-sling.sh <bead> --target <agent> [--db <path>] [-- <gc sling args>...]
# The arguments after -- go to `gc sling` as they stand, after the target and
# the bead it slings. Only a pour (--on) onto an open convoy that carries a
# `branch` is changed. Every other sling is gc sling's own and runs untouched.
# Callers: rejection-repool.sh for the rebuild it pours, and the reconcile pass
# of deferred-dispatch.sh for an armed bead, which passes the store it reads
# as --db.
#
# A formula that works one bead, mol-polecat-work among them, takes the one bead
# its input convoy tracks as its work bead. gc sling makes that convoy for a bead
# it pours onto, and takes a convoy target as the input convoy itself, since a
# pour onto a convoy works on the beads the convoy tracks. A convoy that carries
# a `branch` is a work bead in its own right: convoy-graduate.sh makes a complete
# owned convoy the anchor of its graduation PR. Poured as it stands, its run
# would take the members it landed for its work, not the convoy. So a pour onto
# such a convoy goes through an input convoy made the way gc sling makes one for
# any other bead, in these steps:
#   1. No live run of the formula already works on the bead through an input
#      convoy made for it. gc sling refuses the same duplicate on a bead it
#      pours onto, but here it is handed a convoy it has never seen.
#   2. gc convoy create makes the convoy in GC_RIG's store, titled and marked
#      gc.synthetic=true the way gc sling marks its own. It has the bead's
#      priority, which the pour copies, and the bead's target, from which gc
#      sling takes the run's base branch. gc convoy add then tracks the bead.
#   3. gc sling pours onto that convoy, once its membership reads back as the
#      bead alone, because a pour cannot be taken back.
#   4. The bead is stamped with the gc.execution_routed_to that the pour leaves
#      on the convoy, the stamp gc sling leaves on any other bead it pours onto.
# A convoy whose making or sling fails is closed again unless a workflow root
# names it, as gc sling closes the input convoy of a pour it discards.
# Exit: 0 slung · 1 usage, nothing done · 2 the bead or a convoy could not be
#   read or made, and nothing was slung · 3 a live run of the formula already
#   works on the bead, and nothing was slung · otherwise gc sling's own exit
set -uo pipefail

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

warn()  { echo "work-sling: $*" >&2; }
usage() { warn "$1"; exit 1; }

BEAD=""; TARGET=""; DB=""
need() { [ "$2" -gt 1 ] || usage "$1 needs a value"; }
while [ $# -gt 0 ]; do
  case "$1" in
    --target)  need "$1" $#; TARGET="$2"; shift ;;
    --db)      need "$1" $#; DB="$2"; shift ;;
    --)        shift; break ;;
    -h|--help) sed -n '2,/^set -uo pipefail$/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)        usage "unknown argument '$1'" ;;
    *)         [ -z "$BEAD" ] || usage "one bead per call, not '$BEAD' and '$1'"; BEAD="$1" ;;
  esac
  shift
done
[ -n "$BEAD" ]   || usage "the bead id is required"
[ -n "$TARGET" ] || usage "--target is required: the agent or pool the bead is slung to"
SLING_ARGS=("$@")

sling() { gc sling ${GC_RIG:+--rig "$GC_RIG"} "$TARGET" "$1" ${SLING_ARGS[@]+"${SLING_ARGS[@]}"}; }

# The formula the sling pours, from its --on. None means gc sling pours nothing
# onto the bead itself, so its own handling stands.
FORMULA=""; prev=""
for a in ${SLING_ARGS[@]+"${SLING_ARGS[@]}"}; do
  case "$a" in --on=*) FORMULA="${a#--on=}" ;; esac
  [ "$prev" = "--on" ] && FORMULA="$a"
  prev="$a"
done
[ -n "$FORMULA" ] || { sling "$BEAD"; exit $?; }

command -v jq >/dev/null 2>&1 || { warn "jq is required; $BEAD not slung"; exit 2; }
gcbd() { if [ -n "$DB" ]; then gc bd --db "$DB" "$@"; else gc bd "$@"; fi; }
# read_json <gc-bd-args...> — one read as JSON, with the `gc bd:` rig-store notice
# line and the C0 bytes stripped.
read_json() { gcbd "$@" --json </dev/null 2>/dev/null | grep -a -vE '^gc bd:' | scrub; }
# live_roots <convoy> — the ids of the workflow roots not closed that name the
# convoy as their input convoy, one per line, of every formula; a read that does
# not answer exits non-zero. A root can be a wisp, so both tiers are read.
live_roots() {
  read_json list --metadata-field "gc.input_convoy_id=$1" --include-ephemeral --limit=0 \
    | jq -r 'if type == "array" then (.[] | select((.status // "") != "closed" and ((.metadata["gc.kind"] // "") | tostring) == "workflow") | "\(.id) \((.metadata["gc.formula_name"] // "") | tostring)") else error("unreadable") end' 2>/dev/null
}

# A closed bead goes to gc sling as it stands, which refuses to pour onto it.
ROW=$(read_json show "$BEAD")
SHAPE=$(printf '%s' "$ROW" | jq -r 'if type == "array" and length > 0 and (.[0] | type) == "object"
    then .[0] | [((.issue_type // "") | tostring), ((.metadata.branch // "") | tostring | gsub("^[[:space:]]+|[[:space:]]+$"; "")), ((.status // "") | tostring)]
      | if .[0] == "convoy" and .[1] != "" and .[2] != "closed" and .[2] != "tombstone" then "convoy-work" else "bead" end
    else empty end' 2>/dev/null)
[ -n "$SHAPE" ] || { warn "could not read $BEAD, so nothing shows whether it is a convoy that is its own work; nothing slung"; exit 2; }
[ "$SHAPE" = "convoy-work" ] || { sling "$BEAD"; exit $?; }

# 1. A live run of the formula through an input convoy made for this bead.
TRACKERS=$(read_json dep list "$BEAD" --direction=up -t tracks \
  | jq -r 'if type == "array" then (.[] | select(((.issue_type // .type // "") | tostring) == "convoy" and ((.metadata["gc.synthetic"] // "") | tostring) == "true") | .id) else error("unreadable") end' 2>/dev/null) \
  || { warn "could not read the convoys that track $BEAD, so a live run of $FORMULA on it cannot be ruled out; nothing slung"; exit 2; }
for c in $TRACKERS; do
  roots=$(live_roots "$c") || { warn "could not read the workflow roots over $c, which tracks $BEAD, so a live run of $FORMULA on it cannot be ruled out; nothing slung"; exit 2; }
  live=$(printf '%s\n' "$roots" | awk -v f="$FORMULA" '$2 == f { print $1; exit }')
  if [ -n "$live" ]; then
    warn "$FORMULA already runs on $BEAD (root $live, over input convoy $c); nothing slung"
    exit 3
  fi
done

# 2. The input convoy, made, marked and given the bead in the order gc sling
# makes its own.
PRIO=$(printf '%s' "$ROW" | jq -r '.[0].priority // 2 | tostring' 2>/dev/null)
BASE=$(printf '%s' "$ROW" | jq -r '(.[0].metadata.target // "") | tostring' 2>/dev/null)
CONVOY=$(gc convoy create "input convoy for $BEAD" ${GC_RIG:+--rig "$GC_RIG"} ${BASE:+--target "$BASE"} --json 2>/dev/null </dev/null \
  | grep -a -vE '^gc bd:' | scrub | jq -r 'select(type == "object") | (.convoy_id // .id // empty)' 2>/dev/null | head -n 1)
[ -n "$CONVOY" ] || { warn "gc convoy create made no input convoy for $BEAD; nothing slung"; exit 2; }
# drop_convoy <why> — close the convoy this run made, unless a workflow root
# names it, and give up with exit 2.
drop_convoy() {
  local roots
  if roots=$(live_roots "$CONVOY") && [ -z "$roots" ]; then
    gc convoy close "$CONVOY" >/dev/null 2>&1 </dev/null || warn "could not close $CONVOY, the input convoy made for $BEAD"
  else
    warn "left $CONVOY open: a workflow root names it, or its roots could not be read"
  fi
  warn "$1; nothing slung"
  exit 2
}
gcbd update "$CONVOY" --set-metadata gc.synthetic=true --priority "$PRIO" >/dev/null 2>&1 </dev/null \
  || drop_convoy "could not mark $CONVOY as the input convoy for $BEAD"
gc convoy add "$CONVOY" "$BEAD" ${GC_RIG:+--rig "$GC_RIG"} >/dev/null 2>&1 </dev/null \
  || drop_convoy "could not track $BEAD in its input convoy $CONVOY"

# 3. The pour, onto a convoy that reads back tracking the bead alone.
MEMBERS=$(gc convoy status "$CONVOY" --json 2>/dev/null </dev/null | grep -a -vE '^gc bd:' | scrub \
  | jq -r 'if (.children | type) == "array" then ([.children[].id] | join(" ")) else error("unreadable") end' 2>/dev/null)
[ "$MEMBERS" = "$BEAD" ] || drop_convoy "input convoy $CONVOY reads as tracking '${MEMBERS:-nothing readable}', not $BEAD alone"
sling "$CONVOY"; RC=$?
if [ "$RC" != 0 ]; then
  roots=$(live_roots "$CONVOY") && [ -z "$roots" ] && { gc convoy close "$CONVOY" >/dev/null 2>&1 </dev/null || warn "could not close $CONVOY after the failed sling"; }
  warn "gc sling of $CONVOY, the input convoy for $BEAD, exited $RC"
  exit "$RC"
fi

# 4. The stamp the pour left on its convoy, on the bead it works.
STAMP=$(read_json show "$CONVOY" | jq -r '(.[0].metadata["gc.execution_routed_to"] // "") | tostring' 2>/dev/null)
if [ -z "$STAMP" ]; then
  warn "the pour over $CONVOY left no gc.execution_routed_to, so $BEAD carries none"
elif ! gcbd update "$BEAD" --set-metadata "gc.execution_routed_to=$STAMP" >/dev/null 2>&1 </dev/null; then
  warn "could not stamp gc.execution_routed_to=$STAMP on $BEAD; its pour over $CONVOY is live"
fi
warn "slung $BEAD to $TARGET through input convoy $CONVOY"
exit 0
