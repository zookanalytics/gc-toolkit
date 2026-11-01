#!/usr/bin/env bash
# stand-down — carry out a person's ruling that work waiting on a human gate will
# not go on.
#
#   stand-down.sh <work-bead> --key <situation-key> --ruling <why>
#                 [--successor <bead>] [--dry-run]
#
# A human gate blocks the work bead, and await-ruling.sh arms the work's re-sling
# for when the gate clears, so neither order a person would try by hand ends the
# wait. bd refuses to close a bead an open gate blocks, and clearing the gate
# first makes the bead ready, which is what the arm waits for. This runs the one
# order that does end it:
#   1. It removes the arm, and any notice owed, through deferred-dispatch.sh
#      disarm, and reads the arm back. The reconcile pass reads an arm again just
#      before it slings, so a pass that reads the gate closed reads the arm gone.
#   2. It ends the run beneath the bead and clears the bead's route and session
#      pins through gc-helm.sh takeaway --release --no-wait, and reads back that
#      the bead has no dispatch path, because a bare release reads back no route.
#      So nothing is still building the work and no pool is offered it once it is
#      ready.
#   3. It answers each gate under the key with the ruling, and reads each back.
#      An answer releases every bead a gate blocks, so a gate that also holds
#      another open bead takes none: this bead leaves it, and it goes on asking
#      about the rest. Either way the bead is ready from here on, with nothing
#      left to send it, which is why this comes after the arm and the route.
#   4. It hands the close to bead-rehome.sh, the writer of a close that is not a
#      landing, as not-needed. The bead's branch ends with the close, as any
#      disposition's does.
#
# The evidence the pointer names is the gate that carries the ruling, unless
# --successor names other evidence, such as a sitting's conversation. A gate this
# bead leaves carries no ruling, so it cannot be the evidence.
#
# Nothing is written, and the exit is 1, for a bead whose close this cannot
# carry out:
#   * an open PR, which the prs skill retires, because the PR has to close before
#     an answer releases its merge;
#   * a gate under the key that also holds another open bead, with that gate as
#     the only evidence. --successor names other evidence and lets this bead leave
#     it, and an answer once this bead has closed releases the rest;
#   * anything bead-rehome.sh --check refuses: another open human gate, a gate
#     assigned to a person, another live blocker, an open child, a claim, or a
#     pointer to other evidence.
#
# A step that does not land exits 1 and names what has landed. Re-running
# converges: the arm stays gone, an answered gate stays answered and still names
# the evidence, and bd keeps the first answer a gate was given. A closed bead exits
# 0 with nothing to do.
#
# Callers: a person or a sitting, on the ruling. A worker that declines its work
# does not run this; it asks with human-gate.sh and await-ruling.sh.
# exit: 0 the bead is closed · 1 it is not · 2 usage
set -uo pipefail

PROG="stand-down"

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

usage() {
  cat >&2 <<'USAGE'
usage: stand-down.sh <work-bead> --key <situation-key> --ruling <why>
                     [--successor <bead>] [--dry-run]

  <work-bead>   the bead the ruling says will not go on
  --key         the situation key of the human gate the ruling answers (required)
  --ruling      the ruling, one sentence: the answer on the gate and the note on
                the close (required)
  --successor   the evidence the close points at; default the gate under the key,
                which a gate that also holds another open bead cannot be
  --dry-run     resolve and report; write nothing

exit: 0 the bead is closed · 1 it is not · 2 usage
USAGE
}

require_value() {
  if [ "$#" -lt 2 ]; then
    echo "$PROG: $1 requires a value" >&2; usage; exit 2
  fi
  case "$2" in
    --key|--ruling|--successor|--dry-run|-h|--help)
      echo "$PROG: $1 requires a value, but the next argument is the option '$2'" >&2; usage; exit 2 ;;
  esac
}

WORK=""; KEY=""; RULING=""; SUCCESSOR=""; DRY_RUN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --key)       require_value "$@"; KEY="$2";       shift 2 ;;
    --ruling)    require_value "$@"; RULING="$2";    shift 2 ;;
    --successor) require_value "$@"; SUCCESSOR="$2"; shift 2 ;;
    --dry-run)   DRY_RUN=1; shift ;;
    -h|--help)   usage; exit 2 ;;
    -*)          echo "$PROG: unknown argument '$1'" >&2; usage; exit 2 ;;
    *)
      if [ -n "$WORK" ]; then echo "$PROG: unexpected argument '$1'" >&2; usage; exit 2; fi
      WORK="$1"; shift ;;
  esac
done
RULING=$(printf '%s' "$RULING" | tr -s '[:space:]' ' ' | sed -e 's/^ //' -e 's/ $//')
if [ -z "$WORK" ] || [ -z "$KEY" ] || [ -z "$RULING" ]; then
  echo "$PROG: a work bead, --key and --ruling are all required" >&2; usage; exit 2
fi
case "$WORK$KEY$SUCCESSOR" in
  *[!A-Za-z0-9._-]*)
    echo "$PROG: the work bead, --key and --successor must contain only [A-Za-z0-9._-]" >&2; exit 2 ;;
esac

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=bd-lib.sh
. "${GC_BD_LIB:-$SCRIPT_DIR/bd-lib.sh}" || { echo "$PROG: cannot source bd-lib.sh beside this script" >&2; exit 1; }
# shellcheck source=work-outcome.sh
. "$SCRIPT_DIR/work-outcome.sh" || { echo "$PROG: cannot source work-outcome.sh beside this script" >&2; exit 1; }
# shellcheck source=dispatch-path.sh
. "$SCRIPT_DIR/dispatch-path.sh" || { echo "$PROG: cannot source dispatch-path.sh beside this script" >&2; exit 1; }
DEFERRED="$SCRIPT_DIR/deferred-dispatch.sh"
HELM="$SCRIPT_DIR/gc-helm.sh"
REHOME="$SCRIPT_DIR/bead-rehome.sh"

refuse() { echo "$PROG: $1 Nothing was written." >&2; exit 1; }

WORK_JSON=$(bd_json show "$WORK")
printf '%s' "$WORK_JSON" | jq -e 'type == "array" and length > 0' >/dev/null 2>&1 \
  || refuse "could not read $WORK."
case "$(printf '%s' "$WORK_JSON" | jq -r '.[0].status // ""' 2>/dev/null)" in
  closed)
    echo "$PROG: $WORK is already closed, so there is nothing to stand down"
    exit 0 ;;
esac
[ "$(row_meta "$WORK_JSON" merge_result)" != pull_request ] \
  || refuse "$WORK is an open PR, which is retired rather than stood down, so the PR closes before an answer releases its merge: $SCRIPT_DIR/pr-dispose.sh, or --retire on a sitting's sign-off."

GATES=$(bd_human_gates "$WORK") || refuse "could not read the human gates of $WORK."
OPEN_GATES=$(printf '%s' "$GATES" | bd_gates_open_under_key "$KEY") \
  || refuse "could not read the human gates of $WORK."

# An answer releases every bead the gate blocks, so a gate that holds another open
# bead is one this bead leaves.
SHARED=""; SHARED_WHY=""
for gate in $(printf '%s' "$OPEN_GATES" | jq -r '.[].id' 2>/dev/null); do
  WAITERS=$(bd_json dep list "$gate" --direction=up --type blocks)
  printf '%s' "$WAITERS" | jq -e 'type == "array"' >/dev/null 2>&1 \
    || refuse "could not read what gate $gate holds, and an answer releases all of it."
  OTHERS=$(printf '%s' "$WAITERS" | jq -r --arg w "$WORK" '
    [ .[] | select((.id // "") != $w)
          | select(((.status // "open") | tostring | ascii_downcase) != "closed")
          | .id ] | join(" ")' 2>/dev/null)
  if [ -n "$OTHERS" ]; then
    SHARED="$SHARED $gate"
    SHARED_WHY="${SHARED_WHY:+$SHARED_WHY; }gate $gate also holds $OTHERS"
  fi
done

# The evidence: what the caller names, then a pointer an earlier run stamped, then
# the gate that carries the ruling, which reads closed once an earlier run or
# another person answered it.
[ -n "$SUCCESSOR" ] || SUCCESSOR=$(row_meta "$WORK_JSON" gc.superseded_by)
[ -n "$SUCCESSOR" ] || SUCCESSOR=$(printf '%s' "$OPEN_GATES" | jq -r '.[0].id // empty' 2>/dev/null)
[ -n "$SUCCESSOR" ] || SUCCESSOR=$(printf '%s' "$GATES" | jq -r --arg k "$KEY" \
  '[ .[] | select(((.await_id // "") | tostring) == $k) ] | last | .id // empty' 2>/dev/null)
[ -n "$SUCCESSOR" ] \
  || refuse "no human gate under $KEY blocks $WORK, so nothing carries the ruling. Name the gate's own key, which its await_id holds, or name the evidence with --successor."
case " $SHARED " in
  *" $SUCCESSOR "*)
    refuse "$SHARED_WHY, and an answer here would release it, so that gate stays open and cannot carry this ruling. Name the evidence with --successor, and $WORK alone stands down and leaves the gate. To release the rest too, answer the gate once $WORK has closed." ;;
esac

"$REHOME" --origin "$WORK" --successor "$SUCCESSOR" --kind not-needed --except-key "$KEY" --check >/dev/null \
  || refuse "$WORK cannot close: bead-rehome.sh refused it, as printed above."

case "$RULING" in
  ruled:*) ANSWER="$RULING" ;;
  *)       ANSWER="ruled: $RULING" ;;
esac

if [ "$DRY_RUN" = 1 ]; then
  echo "$PROG: DRY RUN: $WORK would lose its arm and its run, each open gate under $KEY would resolve with \"$ANSWER\"${SHARED:+ apart from any it would leave open ($SHARED_WHY)}, and $WORK would close as not needed, per $SUCCESSOR"
  exit 0
fi

# Each step below is one a re-run takes again, so a stop names what stands.
stopped() { echo "$PROG: $1 Re-run this command once that is repaired." >&2; exit 1; }

if [ -n "$(row_meta "$WORK_JSON" gc.dispatch_when_ready)$(row_meta "$WORK_JSON" gc.notify_when_ready)" ]; then
  "$DEFERRED" disarm "$WORK" --reason "stand-down: $RULING" >/dev/null \
    || stopped "the arm on $WORK was not removed, so no gate was answered."
fi
bd_json show "$WORK" | jq -e 'type == "array" and length > 0 and ((.[0].metadata["gc.dispatch_when_ready"] // "") == "")' >/dev/null 2>&1 \
  || stopped "$WORK does not read back unarmed, so no gate was answered and nothing closed."

"$HELM" takeaway "$WORK" "Stood down on a person's ruling, so nothing builds it" --release --no-wait \
  || stopped "the arm on $WORK is gone, but its run did not end or its route did not clear, so no gate was answered."
bd_json show "$WORK" | jq -e "$DISPATCH_PATH_JQ"'type == "array" and length > 0 and (.[0] | has_dispatch_path | not)' >/dev/null 2>&1 \
  || stopped "the arm on $WORK is gone and its run has ended, but it does not read back unrouted, so no gate was answered and it left none."

for gate in $(printf '%s' "$OPEN_GATES" | jq -r '.[].id' 2>/dev/null); do
  case " $SHARED " in
    *" $gate "*)
      gc bd dep remove "$WORK" "$gate" >/dev/null 2>&1 || true
      bd_human_gates "$WORK" | jq -e --arg g "$gate" 'all(.[]; (.id // "") != $g)' >/dev/null 2>&1 \
        || stopped "the arm on $WORK is gone and its run has ended, but it did not leave gate $gate, so nothing closed."
      echo "$PROG: $WORK left gate $gate, which stays open: $SHARED_WHY"
      continue ;;
  esac
  gc bd gate resolve "$gate" --reason "$ANSWER" >/dev/null 2>&1 || true
  BACK=$(bd_json show "$gate")
  [ "$(printf '%s' "$BACK" | jq -r '.[0].status // ""' 2>/dev/null)" = closed ] \
    || stopped "the arm on $WORK is gone and its run has ended, but gate $gate did not resolve, so nothing closed."
  ANSWERED=$(printf '%s' "$BACK" | jq -r '.[0].close_reason // ""' 2>/dev/null)
  if [ "$ANSWERED" = "$ANSWER" ]; then
    echo "$PROG: answered gate $gate: $ANSWER"
  else
    echo "$PROG: another answer reached gate $gate first, and it stands: $ANSWERED"
  fi
done

work_outcome_noop "$WORK" gc bd

"$REHOME" --origin "$WORK" --successor "$SUCCESSOR" --kind not-needed --note "$RULING" \
  || stopped "the arm on $WORK is gone, its run has ended and no gate under $KEY holds it, but it did not close: bead-rehome.sh said why, above."

[ "$(bd_json show "$WORK" | jq -r '.[0].status // ""' 2>/dev/null)" = closed ] \
  || stopped "$WORK does not read back closed."
echo "$PROG: $WORK closed as not needed, per $SUCCESSOR; nothing re-slings it"
exit 0
