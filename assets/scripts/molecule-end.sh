#!/usr/bin/env bash
# molecule-end.sh — bound a graph.v2 molecule's lifetime by the work it was
# poured for.
#
#   molecule-end.sh <bead-id> [--dry-run]
#
# A molecule is poured for one source: the single bead its input convoy tracks.
# Once that source closes, whichever writer closes it, nothing the molecule
# could still do is wanted, so the molecule ends. Its members are de-routed,
# then closed with the root, through dead-molecule-dispose.sh and the guards it
# keeps. A molecule whose source is still open stays as it is.
#
# <bead-id> is a member the caller holds: the step molecule-hold.sh is holding,
# or the end bead the caller claimed. What happens turns on the source:
#
#   CLOSED  The molecule ends now. The disposer runs with --owner, because the
#           caller is the one session behind the molecule and drains next, and
#           with --if-source-closed, so a source reopened since it was read
#           stops the end.
#   OPEN    The end is armed as a graph edge. The molecule gets one end bead:
#           a member (gc.root_bead_id, gc.step_ref=molecule-end) routed to the
#           pool the molecule runs on, and blocked by the source and by every
#           open escalation visit tracking the root or the source. bd ready
#           leaves it out while any of those is open, so no pool is offered it.
#           Once the last of them closes the pool is offered it, and the worker
#           that claims it runs this script on it, which ends the molecule, the
#           end bead included.
#
# A disposer refusal is a wait on what it names. An open visit joins the end
# bead's blockers, and a source reopened since it was read keeps the end bead
# behind the source. A live session still standing behind the molecule owns
# its end: that session's own exits (its terminal step, or a hold, which runs
# this script) end it, so nothing is armed, and an end bead the caller claimed
# is retired. Any other refusal is one the disposer will repeat, so a visit is
# filed through escalate.sh, keyed to the molecule, and the end waits on it.
#
# The end bead is created unrouted, its blocks edges are added, and only then
# is it routed, so it is never offerable without its blockers. Re-arming one
# the caller claimed adds the edges first, then reopens it and clears the claim
# with its route kept. The source and the molecule's steps are only ever
# written through the disposer.
#
# Callers: molecule-hold.sh, before every hold; the worker that claims an end
# bead (polecat doctrine).
# exit: 0 ended, armed, live, or nothing to bound · 1 a read or a write failed,
#       and the molecule is as it was · 2 usage
set -uo pipefail

PROG="molecule-end"
END_REF="molecule-end"
LIVE_STATUSES="open,in_progress,blocked,deferred,hooked,pinned"

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

usage() {
  cat <<'USAGE'
usage: molecule-end.sh <bead-id> [--dry-run]

  <bead-id>  a member of the molecule the caller holds: the step being held,
             or the end bead the caller claimed
  --dry-run  resolve and report what would happen; write nothing

Ends the molecule when the work it was poured for has closed, and otherwise
arms its end bead, blocked by that work and by any open escalation visit.

result=ended    the molecule is closed
result=armed    the end bead waits on the beads named in waits_on
result=live     a live session still holds the molecule and owns its end
result=unbound  the molecule names no single source, so nothing bounds it
exit: 0 ended, armed, live, or unbound · 1 a read or write failed · 2 usage
USAGE
}

BEAD=""
DRY_RUN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "$PROG: unknown flag '$1'" >&2; usage >&2; exit 2 ;;
    *)
      if [ -n "$BEAD" ]; then echo "$PROG: unexpected argument '$1'" >&2; exit 2; fi
      BEAD="$1" ;;
  esac
  shift
done
[ -n "$BEAD" ] || { echo "$PROG: a bead id is required" >&2; usage >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "$PROG: jq is required" >&2; exit 1; }

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=bd-lib.sh
. "${GC_BD_LIB:-$SCRIPT_DIR/bd-lib.sh}" || { echo "$PROG: cannot source bd-lib.sh beside this script" >&2; exit 1; }
DISPOSE="${GC_DEAD_MOLECULE_DISPOSE:-$SCRIPT_DIR/dead-molecule-dispose.sh}"
ESCALATE="${GC_ESCALATE_TOOL:-$SCRIPT_DIR/escalate.sh}"

ROOT=""; SOURCE=""; END=""; WAITS=""
report() { # <result> [detail]
  printf 'result=%s bead=%s' "$1" "$BEAD"
  [ -n "$ROOT" ] && printf ' root=%s' "$ROOT"
  [ -n "$SOURCE" ] && printf ' source=%s' "$SOURCE"
  [ -n "$END" ] && printf ' end=%s' "$END"
  [ -n "$WAITS" ] && printf ' waits_on=%s' "$WAITS"
  [ -n "${2:-}" ] && printf ' detail=%s' "$2"
  printf '\n'
}
fail() { # <message> <detail>
  echo "$PROG: $1" >&2
  report failed "$2"
  exit 1
}

# One bead object, or nothing and a non-zero status. bd answers a show with an
# array, and a miss with an empty array or an {"error":...} object.
show_one() {
  local raw
  raw=$(bd_json show "$1") || return 1
  printf '%s' "$raw" | jq -ce 'if type == "array" then (.[0] // empty) else empty end' 2>/dev/null
}
meta_of() { printf '%s' "$1" | jq -r --arg k "$2" '((.metadata // {})[$k] // "") | tostring' 2>/dev/null; }
field_of() { printf '%s' "$1" | jq -r --arg k "$2" '(.[$k] // "") | tostring' 2>/dev/null; }
# An array read, or a non-zero status: a failed read and an empty answer must
# not look alike.
read_array() {
  local raw
  raw=$(bd_json "$@") || return 1
  printf '%s' "$raw" | jq -e 'type == "array"' >/dev/null 2>&1 || return 1
  printf '%s' "$raw"
}

IDENTITIES=$(printf '%s\n%s\n%s\n' "${GC_SESSION_NAME:-}" "${GC_SESSION_ID:-}" "${GC_ALIAS:-}" | awk 'NF && !seen[$0]++')
mine() { [ -n "$1" ] && [ -n "$IDENTITIES" ] && printf '%s\n' "$IDENTITIES" | awk -v a="$1" '$0 == a { f = 1 } END { exit !f }'; }

# --- resolve the molecule and its source --------------------------------------
SELF_JSON=$(show_one "$BEAD") || fail "cannot read $BEAD — nothing done" "bead_unreadable"
ROOT=$(meta_of "$SELF_JSON" gc.root_bead_id)
if [ -z "$ROOT" ]; then
  if [ "$(meta_of "$SELF_JSON" gc.kind)" = "workflow" ] || [ "$(meta_of "$SELF_JSON" gc.formula_contract)" = "graph.v2" ]; then
    ROOT="$BEAD"
  else
    fail "$BEAD carries no gc.root_bead_id and is no workflow root, so it names no molecule" "not_a_molecule"
  fi
fi
ROOT_JSON=$(show_one "$ROOT") || fail "cannot read root $ROOT — nothing done" "root_unreadable"
ROOT_STATUS=$(field_of "$ROOT_JSON" status)
SELF_REF=$(meta_of "$SELF_JSON" gc.step_ref)

# A closed root is a finished molecule whatever its source says, and what is
# left under it is residue for the disposer.
SRC_STATUS=""
if [ "$ROOT_STATUS" != "closed" ]; then
  CONVOY=$(meta_of "$ROOT_JSON" gc.input_convoy_id)
  if [ -z "$CONVOY" ]; then
    report unbound "no_input_convoy"
    exit 0
  fi
  TRACKED=$(read_array dep list "$CONVOY" --direction=down -t tracks) \
    || fail "cannot read what input convoy $CONVOY tracks — nothing done" "convoy_unreadable=$CONVOY"
  N=$(printf '%s' "$TRACKED" | jq -r '[ .[]? | .id ] | length')
  if [ "$N" != "1" ]; then
    report unbound "convoy_tracks=$N"
    exit 0
  fi
  SOURCE=$(printf '%s' "$TRACKED" | jq -r '.[0].id // empty')
  SRC_JSON=$(show_one "$SOURCE") || fail "cannot read source $SOURCE — nothing done" "source_unreadable=$SOURCE"
  SRC_STATUS=$(field_of "$SRC_JSON" status)
fi

# Every open escalation visit tracking <subject>, one id per line. A visit is a
# tracker carrying an escalation_key; the input convoy tracks the source too and
# carries none.
open_visits() {
  local raw
  raw=$(read_array dep list "$1" --direction=up -t tracks) || return 1
  printf '%s' "$raw" | jq -r '.[]? | select((((.metadata["escalation_key"] // "") | tostring) != "") and ((.status // "") != "closed")) | .id'
}

# The molecule's live end bead, if it has one. More than one is a race between
# two arms; the first is used and the rest are left to close with the molecule.
find_end() {
  local raw
  raw=$(read_array list --metadata-field "gc.root_bead_id=$ROOT" --metadata-field "gc.step_ref=$END_REF" --status "$LIVE_STATUSES" --limit 0) || return 1
  printf '%s' "$raw" | jq -r '[ .[]? | .id ] | sort | (.[0] // "")'
}

# Retire the end bead the caller claimed: its job has passed to whatever the
# reason names.
retire_end() { # <reason>
  [ "$DRY_RUN" = "1" ] && return 0
  END=$(find_end) || fail "cannot list the end bead of $ROOT" "end_unreadable"
  [ -n "$END" ] || return 0
  local ej who
  ej=$(show_one "$END") || fail "cannot read end bead $END" "end_unreadable"
  who=$(field_of "$ej" assignee)
  mine "$who" || return 0
  gc bd update "$END" --status=closed --set-metadata gc.outcome=moot --set-metadata gc.work_outcome=no-op \
    --append-notes "$PROG: retired — $1" >/dev/null 2>&1 \
    || fail "could not retire end bead $END" "retire_failed=$END"
}

# The pool the molecule runs on: the held step's route, else the root's, else
# the caller's own pool template.
pool_route() {
  local r
  r=$(meta_of "$SELF_JSON" gc.routed_to)
  [ -n "$r" ] || r=$(meta_of "$ROOT_JSON" gc.routed_to)
  [ -n "$r" ] || r="${GC_TEMPLATE:-}"
  printf '%s' "$r"
}

# Arm the molecule's end on the blockers given, one id per argument.
arm() {
  local b want have route created ej est who new=0 out
  WAITS=$(printf '%s\n' "$@" | awk 'NF && !seen[$0]++' | paste -sd, -)
  if [ "$DRY_RUN" = "1" ]; then
    report would_arm
    exit 0
  fi
  END=$(find_end) || fail "cannot list the end bead of $ROOT — nothing armed" "end_unreadable"
  route=""
  if [ -z "$END" ]; then
    route=$(pool_route)
    [ -n "$route" ] || fail "no pool to route the end of $ROOT to: $BEAD and $ROOT carry no gc.routed_to and GC_TEMPLATE is unset — nothing armed" "no_route"
    created=$(printf '%s\n' \
      "This bead ends molecule $ROOT, which was poured for $SOURCE, once that work is over." \
      "It is blocked by $SOURCE and by every open escalation visit on the molecule, so no pool is offered it until they close." \
      "" \
      "If you claimed it, run assets/scripts/molecule-end.sh with this bead's id, from the gc-toolkit pack, then gc runtime drain-ack." \
      "The script ends the molecule through dead-molecule-dispose.sh, this bead included, or re-arms this bead on whatever still holds the end back." \
      "Close nothing by hand: not this bead, not the molecule's steps, not $SOURCE." \
      | gc bd create "End molecule $ROOT once its work $SOURCE closes" -t task --body-file - \
          --metadata "$(jq -cn --arg r "$ROOT" --arg s "$END_REF" '{"gc.root_bead_id": $r, "gc.step_ref": $s}')" \
          --json 2>&1) || true
    END=$(printf '%s' "$created" | scrub | jq -r 'if type == "array" then (.[0].id // empty) else (.id // empty) end' 2>/dev/null)
    [ -n "$END" ] || fail "could not create the end bead of $ROOT ($(printf '%s' "$created" | head -c 200)) — nothing armed" "create_failed"
    new=1
  fi
  have=$(read_array dep list "$END" --direction=down -t blocks) || fail "cannot read the blockers of end bead $END" "end_unreadable=$END"
  for b in "$@"; do
    [ -n "$b" ] || continue
    printf '%s' "$have" | jq -e --arg b "$b" 'any(.[]?; .id == $b)' >/dev/null 2>&1 && continue
    out=$(gc bd dep add "$END" "$b" --type blocks 2>&1) \
      || fail "could not block end bead $END on $b ($out)" "edge_failed=$b"
  done
  have=$(read_array dep list "$END" --direction=down -t blocks) || fail "cannot read back the blockers of end bead $END" "end_unreadable=$END"
  for want in "$@"; do
    [ -n "$want" ] || continue
    printf '%s' "$have" | jq -e --arg b "$want" 'any(.[]?; .id == $b)' >/dev/null 2>&1 \
      || fail "end bead $END does not read back blocked by $want" "edge_missing=$want"
  done
  ej=$(show_one "$END") || fail "cannot read end bead $END" "end_unreadable=$END"
  est=$(field_of "$ej" status)
  who=$(field_of "$ej" assignee)
  # A new end bead is routed only now, with its blockers in place. One that
  # lost its route is given one back the same way.
  if [ "$new" = "0" ] && [ -z "$(meta_of "$ej" gc.routed_to)" ]; then
    route=$(pool_route)
  fi
  if [ -n "$route" ]; then
    gc bd update "$END" --set-metadata "gc.routed_to=$route" >/dev/null 2>&1 \
      || fail "end bead $END is blocked but could not be routed to $route; no pool is offered it" "route_failed=$END"
  fi
  if [ "$new" = "0" ] && [ "$est" = "in_progress" ] && mine "$who"; then
    # The claimant's own end bead goes back to the pool behind its new blockers:
    # status first, which the holder may write, then the claim, which the claim
    # guard accepts once the bead is open.
    gc bd update "$END" --status=open --append-notes "$PROG: re-armed — waits on $WAITS" >/dev/null 2>&1 \
      || fail "could not reopen end bead $END" "release_failed=$END"
    gc bd update "$END" --assignee "" >/dev/null 2>&1 \
      || fail "end bead $END is reopened but still assigned to $who" "release_failed=$END"
  fi
  ej=$(show_one "$END") || fail "cannot read back end bead $END" "end_unreadable=$END"
  [ -n "$(meta_of "$ej" gc.routed_to)" ] || fail "end bead $END reads back with no route; no pool is offered it once its blockers close" "route_missing=$END"
  report armed
  exit 0
}

# --- the source is open: arm the end ------------------------------------------
if [ "$ROOT_STATUS" != "closed" ] && [ "$SRC_STATUS" != "closed" ]; then
  V_ROOT=$(open_visits "$ROOT") || fail "cannot read the visits tracking $ROOT" "tracks_unreadable=$ROOT"
  V_SRC=$(open_visits "$SOURCE") || fail "cannot read the visits tracking $SOURCE" "tracks_unreadable=$SOURCE"
  # shellcheck disable=SC2086  # one id per word, ids carry no whitespace
  arm "$SOURCE" $V_ROOT $V_SRC
fi

# --- the source is closed: end the molecule -----------------------------------
if [ "$DRY_RUN" = "1" ]; then
  report would_end
  exit 0
fi
D_OUT=$("$DISPOSE" "$BEAD" --apply --owner --if-source-closed --json 2>/dev/null); D_RC=$?
D_RESULT=$(printf '%s' "$D_OUT" | scrub | jq -r '.result // empty' 2>/dev/null)
D_DETAIL=$(printf '%s' "$D_OUT" | scrub | jq -r '.detail // empty' 2>/dev/null)
case "$D_RESULT" in
  disposed|clean)
    report ended "$D_RESULT"
    exit 0 ;;
  live_root)
    case "$D_DETAIL" in
      *liveness_undetermined*) fail "session liveness could not be read, so the end of $ROOT could not be proven safe — nothing done" "$D_DETAIL" ;;
    esac
    # A live session owns the molecule's end. The caller's own end bead, if it
    # holds one, has nothing left to wait for.
    if [ "$SELF_REF" = "$END_REF" ]; then
      retire_end "a live session still holds molecule $ROOT ($D_DETAIL), and its own exits end it"
    fi
    report live "$D_DETAIL"
    exit 0 ;;
  refused)
    case "$D_DETAIL" in
      open_escalation=*) arm "${D_DETAIL#open_escalation=}" ;;
      source_open=*) arm "$SOURCE" ;;
      *unreadable*) fail "the disposer could not read what it needed to end $ROOT ($D_DETAIL) — nothing done" "$D_DETAIL" ;;
    esac
    # A refusal the disposer will repeat whatever closes next: a person decides.
    KEY="molecule-end-$ROOT"
    "$ESCALATE" --subject "$ROOT" --key "$KEY" \
      --message "Molecule $ROOT was poured for $SOURCE, which is closed, but dead-molecule-dispose.sh refuses to end it ($D_DETAIL). The molecule's end waits on this visit: close the visit once the refusal is cleared and the end is retried. Decide whether the molecule should end, and what the refusal means." >/dev/null 2>&1 \
      || fail "the disposer refused to end $ROOT ($D_DETAIL) and escalate.sh filed no visit — nothing armed" "escalate_failed"
    VISITS=$(read_array list --metadata-field "escalation_key=$KEY" --status open,in_progress --limit 0) \
      || fail "cannot read back the visit for $ROOT" "visit_unreadable"
    VISIT=$(printf '%s' "$VISITS" | jq -r '[ .[]? | .id ] | sort | (.[0] // "")')
    [ -n "$VISIT" ] || fail "escalate.sh answered for $ROOT but no open visit carries key $KEY — nothing armed" "visit_missing"
    arm "$VISIT" ;;
  unreadable)
    fail "dead-molecule-dispose.sh could not read what it needed to end $ROOT ($D_DETAIL) — nothing done" "${D_DETAIL:-dispose_unreadable}" ;;
  partial)
    fail "dead-molecule-dispose.sh tore $ROOT down part way ($D_DETAIL): every member is de-routed, so none is offered, but some did not close and a person finishes it" "partial:${D_DETAIL}" ;;
  *)
    fail "dead-molecule-dispose.sh answered rc=$D_RC with no result for $ROOT — nothing done" "dispose_failed" ;;
esac
