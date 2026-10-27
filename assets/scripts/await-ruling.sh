#!/usr/bin/env bash
# await-ruling — make a work bead wait on the visit that asks for a ruling on it,
# and re-sling it when the ruling is "proceed".
#
#   await-ruling.sh <work-bead> --key <situation-key> --formula <formula>
#                   [--subject <bead>] [--target <pool>] [--dry-run]
#
# A worker that declines work it cannot finish without a person files the
# question with escalate.sh, then cancels its run (run-cancel.sh). Nothing
# resumes a cancelled run, so the wait sits on the WORK bead, where every reader
# of the work looks:
#   * a `blocks` edge from the work bead onto the open visit escalate.sh filed
#     for (subject, situation key), which keeps the work out of `bd ready` until
#     the visit closes. The subject is the work bead unless --subject names the
#     bead the visit was filed on, such as the anchor a rework child's question
#     goes to. bd's cycle check walks blocks, conditional-blocks and
#     parent-child only, so this edge beside the visit's `tracks` edge onto its
#     subject is not a cycle;
#   * a deferred-dispatch arm that re-slings the work through <formula> once bd
#     reports it ready. Closing the visit is the "proceed" ruling: the edge
#     clears and the next reconcile pass pours a fresh molecule. A ruling not to
#     proceed closes the work bead first, and a closed bead's arm retires
#     without a sling.
# The visit has to be open. Once a person has closed a visit moot or benign,
# escalate.sh answers a repeat of that situation inside its verdict window from
# the closed visit and files nothing, and the re-slung run can meet the same
# situation again. So a caller runs the escalate.sh this waits behind with
# GC_ESCALATE_VERDICT_WINDOW=0.
# The pool is --target, else the work bead's gc.execution_routed_to (the pool
# its last pour ran on), else its gc.routed_to, else the target of an arm
# already recorded, else resling_target. The arm refuses a routed bead, so the
# route keys a pour leaves behind are cleared before it, and the update that
# clears them records the pool as resling_target. One update lands whole or not
# at all, so whatever stops a run after the clear, the pool is still on the
# bead for the next run, and nothing has to be rolled back. The same update
# drops the session pins (gc.session_id, gc.session_name) a claim stamps:
# gascity's detached-handoff orphan sweep restores a pool route from a pin on an
# open, unassigned, unrouted bead that carries a branch, and a pool would then
# claim the bare bead instead of the re-sling pouring a fresh molecule.
#
# The re-sling fires only for an open, unassigned bead: the arm refuses an
# in_progress one, and reconcile never slings over an assignee. So a claim the
# work bead still carries is released after the edge lands and before the arm,
# when no live worker holds it. That is a claim in this session's name, or an
# in_progress claim whose owner `gc session list --state all` lists under none
# of its names. mol-polecat-work's load-context builds over such a crashed
# owner's claim, and this script proves the owner gone itself, so a wait asked
# at any step of that run releases the claim without the caller naming it.
# The release is `gc bd unclaim --if-assignee`, which reopens the bead and
# clears its assignee in one write, and only while that claim is still the one
# this run read. Any other claim exits 1 before anything is written: an owner
# the list still names may be live, a list that cannot be read proves no owner
# gone, and an open bead under another assignee is a hand-off, not a claim.
#
# The edge, the release and the arm are read back. Any of them not landing exits
# 1, and the caller does not cancel its run: a cancelled run with no recorded
# wait leaves the work bead open, unrouted and unarmed, which nothing
# re-offers. Re-running converges, with or without --target: an edge already in
# place, a claim already released and an arm already recorded count as landed,
# and after an arm that did not land, the re-run arms to the pool the earlier
# run recorded.
#
# Callers: the decline arms of mol-polecat-work that wait for a person, and
# mol-refinery-patrol's merge-push, which makes a convoy's rebuild child wait
# when no bead can carry its PR. The child is assigned to the refinery, so the
# release is of a claim in that session's name.
# exit: 0 the work bead waits on the visit and is armed, or is closed and needs
#       neither · 1 the wait did not land · 2 usage
set -uo pipefail

PROG="await-ruling"

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

usage() {
  cat >&2 <<'USAGE'
usage: await-ruling.sh <work-bead> --key <situation-key> --formula <formula>
                       [--subject <bead>] [--target <pool>] [--dry-run]

  <work-bead>     the bead the declined run was poured for
  --key           the situation key escalate.sh filed the visit under (required)
  --formula       the formula the re-sling pours, e.g. mol-polecat-work
                  (required)
  --subject       the bead the visit was filed on; default the work bead
  --target        the pool to re-sling to; default the bead's
                  gc.execution_routed_to, else its gc.routed_to, else the pool
                  an earlier run armed or recorded as resling_target
  --dry-run       resolve and report; write nothing

A claim on the work bead is released before the arm when it is this session's,
or when the bead is in_progress under an owner `gc session list --state all`
does not list. Any other claim is kept, and no wait is recorded.

env: GC_SESSION_NAME, GC_SESSION_ID, GC_AGENT, GC_ALIAS name this session.

exit: 0 waiting and armed, or the bead is closed · 1 the wait did not land · 2 usage
USAGE
}

require_value() {
  if [ "$#" -lt 2 ]; then
    echo "$PROG: $1 requires a value" >&2; usage; exit 2
  fi
  case "$2" in
    --key|--formula|--subject|--target|--dry-run|-h|--help)
      echo "$PROG: $1 requires a value, but the next argument is the option '$2'" >&2; usage; exit 2 ;;
  esac
}

WORK=""; KEY=""; FORMULA=""; SUBJECT=""; TARGET=""; DRY_RUN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --key)     require_value "$@"; KEY="$2";     shift 2 ;;
    --formula) require_value "$@"; FORMULA="$2"; shift 2 ;;
    --subject) require_value "$@"; SUBJECT="$2"; shift 2 ;;
    --target)  require_value "$@"; TARGET="$2";  shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 2 ;;
    -*)        echo "$PROG: unknown argument '$1'" >&2; usage; exit 2 ;;
    *)
      if [ -n "$WORK" ]; then echo "$PROG: unexpected argument '$1'" >&2; usage; exit 2; fi
      WORK="$1"; shift ;;
  esac
done
if [ -z "$WORK" ] || [ -z "$KEY" ] || [ -z "$FORMULA" ]; then
  echo "$PROG: a work bead, --key and --formula are all required" >&2; usage; exit 2
fi
[ -n "$SUBJECT" ] || SUBJECT="$WORK"
case "$WORK$KEY$FORMULA$SUBJECT" in
  *'{{'*|*'}}'*)
    echo "$PROG: an argument was passed unsubstituted ('$WORK' '$KEY' '$FORMULA' '$SUBJECT'); the pour did not render it" >&2; exit 2 ;;
esac
case "$WORK$KEY$FORMULA$SUBJECT" in
  *[!A-Za-z0-9._-]*)
    echo "$PROG: the work bead, --key, --formula and --subject must contain only [A-Za-z0-9._-]" >&2; exit 2 ;;
esac

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=bd-lib.sh
. "${GC_BD_LIB:-$SCRIPT_DIR/bd-lib.sh}" || { echo "$PROG: cannot source bd-lib.sh beside this script" >&2; exit 1; }
DEFERRED="${GC_DEFERRED_DISPATCH_TOOL:-$SCRIPT_DIR/deferred-dispatch.sh}"

bd_json_array() { # <bd args...> -> the array on stdout; non-zero on a failed read or a non-array payload
  local out
  out=$(bd_json "$@") || return 1
  printf '%s' "$out" | jq -e 'type == "array"' >/dev/null 2>&1 || return 1
  printf '%s' "$out"
}

if ! WORK_JSON=$(bd_json_array show "$WORK") || [ "$(printf '%s' "$WORK_JSON" | jq 'length' 2>/dev/null)" = "0" ]; then
  echo "$PROG: could not read $WORK; no wait was recorded" >&2
  exit 1
fi
STATUS=$(printf '%s' "$WORK_JSON" | jq -r '.[0].status // ""' 2>/dev/null)
ASSIGNEE=$(printf '%s' "$WORK_JSON" | jq -r '.[0].assignee // ""' 2>/dev/null)
case "$STATUS" in
  closed)
    echo "$PROG: $WORK is closed, so nothing waits on a ruling and nothing re-slings"
    exit 0 ;;
  open|in_progress) ;;
  *)
    echo "$PROG: $WORK is status=${STATUS:-unreadable}; a re-sling can be armed on an open or claimed bead only, so no wait was recorded" >&2
    exit 1 ;;
esac

# owner_listed <assignee> — how many sessions `gc session list --state all`
# lists under that assignee, in any of the three forms a claim writes: the
# session name, the session id, or the agent address, which is a session's
# alias or the end of one. The same match decides load-context's owner check.
# Prints nothing when the list cannot be read.
owner_listed() {
  gc session list --state all --json 2>/dev/null </dev/null | scrub | jq -r --arg o "$1" '
    if type == "object" and (.sessions | type) == "array" and all(.sessions[]; type == "object") then
      [ .sessions[] | select(((.alias // "") == $o) or ((.alias // "") | endswith($o))
                             or ((.session_name // "") == $o) or ((.id // "") == $o)) ] | length
    else empty end' 2>/dev/null
}

# RELEASE says how the bead becomes open and unassigned before the arm:
# `unclaim` a claim no live worker holds, `reopen` an in_progress bead that
# names no assignee, or nothing for a bead already open and unassigned.
RELEASE=""
if [ -n "$ASSIGNEE" ]; then
  for me in "${GC_SESSION_NAME:-}" "${GC_SESSION_ID:-}" "${GC_AGENT:-}" "${GC_ALIAS:-}"; do
    if [ -n "$me" ] && [ "$me" = "$ASSIGNEE" ]; then RELEASE=unclaim; break; fi
  done
  if [ -z "$RELEASE" ]; then
    KEPT="an open bead under another assignee is a hand-off, not a claim this run can release"
    if [ "$STATUS" = in_progress ]; then
      LISTED=$(owner_listed "$ASSIGNEE")
      case "$LISTED" in
        0)  RELEASE=unclaim ;;
        "") KEPT="gc session list could not be read, so nothing proves that owner gone" ;;
        *)  KEPT="gc session list still lists that owner, so its worker may be live" ;;
      esac
    fi
    if [ -z "$RELEASE" ]; then
      echo "$PROG: $WORK is $STATUS under $ASSIGNEE, a claim not in this session's name: $KEPT. Reconcile never slings an assigned bead, so the claim is kept and no wait was recorded" >&2
      exit 1
    fi
  fi
elif [ "$STATUS" = in_progress ]; then
  RELEASE=reopen
fi

# The visit escalate.sh files for a durable subject, matched the way its own
# dedup matches: the situation key and the subject's continuation group.
if ! VISITS=$(bd_json_array list --status=open,in_progress --metadata-field "escalation_key=$KEY" \
    --metadata-field "gc.continuation_group=$SUBJECT" --limit=20); then
  echo "$PROG: could not list the visits on $SUBJECT; no wait was recorded" >&2
  exit 1
fi
VISIT=$(printf '%s' "$VISITS" | jq -r --arg k "$KEY" --arg s "$SUBJECT" '
  [ .[] | select((.metadata.escalation_key // "") == $k and (.metadata["gc.continuation_group"] // "") == $s) | .id ]
  | sort | .[0] // empty' 2>/dev/null)
if [ -z "$VISIT" ]; then
  echo "$PROG: no open visit on $SUBJECT under $KEY; file it with escalate.sh first. No wait was recorded." >&2
  exit 1
fi

if [ -z "$TARGET" ]; then
  TARGET=$(printf '%s' "$WORK_JSON" | jq -r '
    .[0].metadata as $m
    | [ $m["gc.execution_routed_to"], $m["gc.routed_to"], $m["gc.dispatch_when_ready"], $m["resling_target"] ]
    | map(select(. != null and . != "")) | .[0] // empty' 2>/dev/null)
fi
case "$TARGET" in
  */*) ;;
  *)
    echo "$PROG: no rig-qualified pool to re-sling $WORK to (gc.execution_routed_to, gc.routed_to, gc.dispatch_when_ready and resling_target gave '${TARGET}'); pass --target. No wait was recorded." >&2
    exit 1 ;;
esac

if [ "$DRY_RUN" = 1 ]; then
  echo "$PROG: DRY RUN: $WORK would wait on visit $VISIT, armed to re-sling to $TARGET --on $FORMULA${RELEASE:+, after releasing its claim (status $STATUS${ASSIGNEE:+, assignee $ASSIGNEE})}"
  exit 0
fi

# `dep add <bead> <blocker>` reads "<bead> is blocked by <blocker>".
blocks_on_visit() {
  bd_json dep list "$WORK" | jq -e --arg v "$VISIT" '
    type == "array" and any(.[]; (.id // .depends_on_id // "") == $v
                               and ((.dependency_type // .type // "") == "blocks"))' >/dev/null 2>&1
}
if ! blocks_on_visit; then
  gc bd dep add "$WORK" "$VISIT" --type=blocks </dev/null >/dev/null 2>&1 || true
  if ! blocks_on_visit; then
    echo "$PROG: the blocks edge from $WORK onto visit $VISIT did not land; no wait was recorded" >&2
    exit 1
  fi
fi

# The edge already keeps the bead out of `bd ready`, so releasing its claim
# offers it to no pool. The unclaim is a compare-and-swap on the assignee read
# above, so a claim that changed hands since is left alone.
case "$RELEASE" in
  unclaim)
    if ! gc bd unclaim "$WORK" --if-assignee "$ASSIGNEE" </dev/null >/dev/null 2>&1; then
      echo "$PROG: the claim of $ASSIGNEE on $WORK was not released (bd refused it, or the claim changed hands); it waits on visit $VISIT unarmed" >&2
      exit 1
    fi ;;
  reopen)
    if ! gc bd update "$WORK" --status=open </dev/null >/dev/null 2>&1; then
      echo "$PROG: $WORK is in_progress with no assignee and was not reopened; it waits on visit $VISIT unarmed" >&2
      exit 1
    fi ;;
esac

# A pour retires gc.routed_to onto gc.execution_routed_to, and the arm refuses a
# routed bead, so the route keys are cleared before it. From the clear until the
# arm lands, nothing else on the bead names the pool, so the same update records
# it as resling_target: a run whose arm is refused, or that stops before the
# arm, leaves the next run a pool to arm to.
if ! gc bd update "$WORK" --set-metadata gc.routed_to="" --set-metadata gc.deferred_routed_to="" \
    --set-metadata gc.execution_routed_to="" --set-metadata gc.deferred_execution_routed_to="" \
    --set-metadata gc.deferred_assignee="" --set-metadata resling_target="$TARGET" \
    --unset-metadata gc.session_id --unset-metadata gc.session_name </dev/null >/dev/null 2>&1; then
  echo "$PROG: could not clear the route keys on $WORK, so the re-sling cannot be armed; it waits on visit $VISIT unarmed" >&2
  exit 1
fi
if ! ARM_OUT=$("$DEFERRED" arm "$WORK" --target "$TARGET" --sling-arg --on --sling-arg "$FORMULA" \
    --reason "waits on the ruling in visit $VISIT ($KEY)" 2>&1); then
  echo "$PROG: the re-sling was not armed on $WORK: $ARM_OUT; it waits on visit $VISIT unarmed, and a re-run arms it to $TARGET, recorded as resling_target" >&2
  exit 1
fi
BACK=$(bd_json show "$WORK")
ARMED=$(printf '%s' "$BACK" | jq -r '.[0].metadata["gc.dispatch_when_ready"] // empty' 2>/dev/null)
BACK_STATUS=$(printf '%s' "$BACK" | jq -r '.[0].status // empty' 2>/dev/null)
BACK_ASSIGNEE=$(printf '%s' "$BACK" | jq -r '.[0].assignee // empty' 2>/dev/null)
if [ "$ARMED" != "$TARGET" ] || [ "$BACK_STATUS" != open ] || [ -n "$BACK_ASSIGNEE" ]; then
  echo "$PROG: $WORK reads back armed to '${ARMED}', status '${BACK_STATUS}', assignee '${BACK_ASSIGNEE}'; the re-sling fires only for an open, unassigned bead armed to $TARGET" >&2
  exit 1
fi
echo "$PROG: $WORK waits on visit $VISIT ($KEY); closing the visit re-slings it to $TARGET --on $FORMULA"
exit 0
