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
#   1. The bead's store is named once, from gc rig list. It is the store --db
#      names, or with no --db the rig whose prefix the bead id carries
#      (bead-store.sh), which is where gc bd reads the bead. Every read and
#      write below is pinned to that store, and the convoy calls and the sling
#      name its rig. gc convoy create puts a convoy with no member in the store
#      --rig names, else in GC_RIG's, else in that of the rig the working
#      directory is in, else in the city's, and gc convoy add refuses a bead
#      its convoy's store does not hold. Naming the rig is what makes the
#      convoy beside the bead when the caller runs at city scope or in another
#      rig.
#   2. Each call takes an exclusive lock on the bead in its store, kept under
#      the city root, and holds it until it exits, so no other call pours
#      between this call's check for a live run and its own pour. gc sling's
#      launch lock is keyed by the bead it is handed, and each call hands it a
#      convoy of its own. A call that finds the lock held waits for it, up to
#      WORK_SLING_LOCK_WAIT_SECS (120 unless set), and then makes the check in
#      step 3, which finds any run the holder made.
#   3. No live run of the formula already works on the bead through an input
#      convoy made for it. gc sling refuses the same duplicate on a bead it
#      pours onto, but here it is handed a convoy it has never seen.
#   4. gc convoy create makes the convoy in the bead's store, titled and marked
#      gc.synthetic=true the way gc sling marks its own. It has the bead's
#      priority, which the pour copies, and the bead's target, from which gc
#      sling takes the run's base branch. gc convoy add then tracks the bead.
#   5. gc sling pours onto that convoy, once its membership reads back as the
#      bead alone, because a pour cannot be taken back.
#   6. The bead is stamped with the gc.execution_routed_to that the pour leaves
#      on the convoy, the stamp gc sling leaves on any other bead it pours onto.
# A convoy whose making or sling fails is closed again unless a workflow root
# names it, as gc sling closes the input convoy of a pour it discards.
#
# A call stopped at step 2 or refused at step 3 slings nothing, and its caller
# goes on as it does after any failed sling. The reconcile leaves the bead's
# arm in place for its next pass. rejection-repool.sh reads the bead's stamp
# back: a call that waited out another finds the stamp that call's pour left,
# which proves the rebuild when it went to the same route, and otherwise the
# repool arms a deferred dispatch.
# Exit: 0 slung · 1 usage, nothing done · 2 the bead, its store or a convoy
#   could not be read or made, or its lock could not be taken, and nothing was
#   slung · 3 a live run of the formula already works on the bead, and nothing
#   was slung · otherwise gc sling's own exit
set -uo pipefail

SCRIPTS_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"

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
# Each gc call runs through bd-lib.sh's pass_child, with fd 9 closed. fd 9
# holds the lock of step 2, so no process a gc call leaves running holds it.
# shellcheck source=bd-lib.sh
. "${GC_BD_LIB:-$SCRIPTS_DIR/bd-lib.sh}" || { warn "cannot source bd-lib.sh beside this script; $BEAD not slung"; exit 2; }
gcbd() { if [ -n "$DB" ]; then pass_child gc bd --db "$DB" "$@"; else pass_child gc bd "$@"; fi; }
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

# 1. The bead's store. A rig row is its name, its path and whether it is the
# city's own store (hq); a store lives in <path>/.beads. With no --db, the
# store is the rig bead-store.sh names from the bead's prefix.
RIGS=$(pass_child gc rig list --json </dev/null 2>/dev/null | grep -a -vE '^gc bd:' | scrub)
rig_rows() {
  printf '%s' "$RIGS" | jq -r '.rigs[]? | [((.name // "") | tostring), ((.path // "") | tostring), (if .hq == true then "hq" else "rig" end)]
    | select(.[0] != "" and .[1] != "") | @tsv' 2>/dev/null
}
STORE=""; STORE_PATH=""; STORE_KIND=""
if [ -n "$DB" ]; then
  want=$(cd "$DB" 2>/dev/null && pwd -P) || want=""
  while IFS=$'\t' read -r name path kind; do
    [ -n "$want" ] && [ "$(cd "$path/.beads" 2>/dev/null && pwd -P)" = "$want" ] || continue
    STORE="$name"; STORE_PATH="$path"; STORE_KIND="$kind"; break
  done <<< "$(rig_rows)"
  [ -n "$STORE" ] || { warn "no rig in gc rig list keeps its store at $DB, so the input convoy for $BEAD cannot be made beside it; nothing slung"; exit 2; }
else
  owner=$(pass_child "$SCRIPTS_DIR/bead-store.sh" "$BEAD" </dev/null) || owner=""
  while IFS=$'\t' read -r name path kind; do
    [ -n "$owner" ] && [ "$name" = "$owner" ] || continue
    STORE="$name"; STORE_PATH="$path"; STORE_KIND="$kind"; break
  done <<< "$(rig_rows)"
  [ -n "$STORE" ] || { warn "no store in gc rig list is named for $BEAD${owner:+ (bead-store.sh named $owner)}, so the store its input convoy must be made in is unknown; nothing slung"; exit 2; }
  DB="$STORE_PATH/.beads"
fi
# The city's own store is not a rig gc can name, so its convoy is made at city
# scope, and the calls that find a convoy by its id need no scope.
RIG_ARGS=(--rig "$STORE"); CREATE_SCOPE=(--rig "$STORE")
[ "$STORE_KIND" = "hq" ] && { RIG_ARGS=(); CREATE_SCOPE=(--city-scope); }

# 2. The bead's lock, held on fd 9 until this call exits. Every caller names its
# file the same way: the city root is the one its environment carries, else the
# city's own row in the rig list, never a per-session directory. The file stays
# in place, because a removed file lets the next call lock a new one.
CITY="${GC_CITY_PATH:-${GC_CITY:-${GC_CITY_ROOT:-}}}"
[ -n "$CITY" ] || CITY=$(printf '%s' "$RIGS" | jq -r 'first(.rigs[]? | select(.hq == true) | (.path // "") | tostring | select(. != "")) // empty' 2>/dev/null)
[ -n "$CITY" ] || { warn "no city root (GC_CITY_PATH, GC_CITY, GC_CITY_ROOT or the city's row in gc rig list) to keep the lock on $BEAD under; nothing slung"; exit 2; }
LOCK_WAIT="${WORK_SLING_LOCK_WAIT_SECS:-120}"
case "$LOCK_WAIT" in ''|*[!0-9]*) LOCK_WAIT=120 ;; esac
command -v flock >/dev/null 2>&1 || { warn "flock is not on PATH, so no lock keeps another call off $BEAD; nothing slung"; exit 2; }
LOCK="$CITY/.gc/runtime/packs/gc-toolkit/work-sling/${STORE//[^A-Za-z0-9._-]/_}/${BEAD//[^A-Za-z0-9._-]/_}.lock"
{ mkdir -p "${LOCK%/*}" && : >> "$LOCK"; } 2>/dev/null || { warn "cannot create the lock $LOCK; nothing slung"; exit 2; }
exec 9>>"$LOCK" || { warn "cannot open the lock $LOCK; nothing slung"; exit 2; }
if ! flock -n 9; then
  warn "another call holds the lock on $BEAD; waiting up to ${LOCK_WAIT}s for it ($LOCK)"
  flock -w "$LOCK_WAIT" 9 || { warn "the lock on $BEAD was still held after ${LOCK_WAIT}s, so a pour by the call that holds it cannot be ruled out; nothing slung"; exit 2; }
fi

# 3. A live run of the formula through an input convoy made for this bead.
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

# 4. The input convoy, made, marked and given the bead in the order gc sling
# makes its own.
PRIO=$(printf '%s' "$ROW" | jq -r '.[0].priority // 2 | tostring' 2>/dev/null)
BASE=$(printf '%s' "$ROW" | jq -r '(.[0].metadata.target // "") | tostring' 2>/dev/null)
CONVOY=$(pass_child gc convoy create "input convoy for $BEAD" "${CREATE_SCOPE[@]}" ${BASE:+--target "$BASE"} --json 2>/dev/null </dev/null \
  | grep -a -vE '^gc bd:' | scrub | jq -r 'select(type == "object") | (.convoy_id // .id // empty)' 2>/dev/null | head -n 1)
[ -n "$CONVOY" ] || { warn "gc convoy create made no input convoy for $BEAD; nothing slung"; exit 2; }
# close_convoy — close the convoy this run made, unless a workflow root names
# it or its roots cannot be read; non-zero when it is left open.
close_convoy() {
  local roots
  roots=$(live_roots "$CONVOY") && [ -z "$roots" ] || return 1
  pass_child gc convoy close "$CONVOY" ${RIG_ARGS[@]+"${RIG_ARGS[@]}"} >/dev/null 2>&1 </dev/null \
    || warn "could not close $CONVOY, the input convoy made for $BEAD"
}
# drop_convoy <why> — close the convoy this run made and give up with exit 2.
drop_convoy() {
  close_convoy || warn "left $CONVOY open: a workflow root names it, or its roots could not be read"
  warn "$1; nothing slung"
  exit 2
}
gcbd update "$CONVOY" --set-metadata gc.synthetic=true --priority "$PRIO" >/dev/null 2>&1 </dev/null \
  || drop_convoy "could not mark $CONVOY as the input convoy for $BEAD"
pass_child gc convoy add "$CONVOY" "$BEAD" ${RIG_ARGS[@]+"${RIG_ARGS[@]}"} >/dev/null 2>&1 </dev/null \
  || drop_convoy "could not track $BEAD in its input convoy $CONVOY"

# 5. The pour, onto a convoy that reads back tracking the bead alone.
MEMBERS=$(pass_child gc convoy status "$CONVOY" ${RIG_ARGS[@]+"${RIG_ARGS[@]}"} --json 2>/dev/null </dev/null | grep -a -vE '^gc bd:' | scrub \
  | jq -r 'if (.children | type) == "array" then ([.children[].id] | join(" ")) else error("unreadable") end' 2>/dev/null)
[ "$MEMBERS" = "$BEAD" ] || drop_convoy "input convoy $CONVOY reads as tracking '${MEMBERS:-nothing readable}', not $BEAD alone"
pass_child gc sling ${RIG_ARGS[@]+"${RIG_ARGS[@]}"} "$TARGET" "$CONVOY" ${SLING_ARGS[@]+"${SLING_ARGS[@]}"}; RC=$?
if [ "$RC" != 0 ]; then
  close_convoy
  warn "gc sling of $CONVOY, the input convoy for $BEAD, exited $RC"
  exit "$RC"
fi

# 6. The stamp the pour left on its convoy, on the bead it works.
STAMP=$(read_json show "$CONVOY" | jq -r '(.[0].metadata["gc.execution_routed_to"] // "") | tostring' 2>/dev/null)
if [ -z "$STAMP" ]; then
  warn "the pour over $CONVOY left no gc.execution_routed_to, so $BEAD carries none"
elif ! gcbd update "$BEAD" --set-metadata "gc.execution_routed_to=$STAMP" >/dev/null 2>&1 </dev/null; then
  warn "could not stamp gc.execution_routed_to=$STAMP on $BEAD; its pour over $CONVOY is live"
fi
warn "slung $BEAD to $TARGET through input convoy $CONVOY"
exit 0
