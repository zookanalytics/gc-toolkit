#!/usr/bin/env bash
# escalate.sh — the old name of human-gate.sh, kept as a hand-off that runs it.
# A run keeps the text its steps were poured with, so a step poured before the
# rename still calls this path, and mol-polecat-work's load-context looks for it
# on every such run. A call reaches human-gate.sh with its own arguments, except
# where the old contract took what the helper refuses or cannot read, so that
# an old call still files rather than exits:
#   --pool <pool> routed the old visit to a pool. A gate is cleared by a person
#     and routed nowhere, so the flag is dropped, with a notice.
#   The old script filed a visit about a `*-wisp-*` id, or about a subject
#     bead-store.sh proves names no bead (no `<prefix>-<id>` shape, or a prefix
#     no rig carries), on a standing triage bead. The helper refuses the first
#     and cannot read the second, so a filing about either is filed as a patrol
#     finding under its key instead, the route the helper's refusal names. So is
#     a filing about a subject that reads as a session bead, whatever the shape
#     of its id, because a session names no work that can wait.
#   A --retract goes to the helper whatever its subject.
# Any other filing goes to the helper only once its subject's own row reads as
# a bead with a type, because only the row tells a session from a bead that can
# wait. A filing whose subject does not read files nothing and exits 1, so its
# caller retries. The helper reads only the subject's edges, and those can
# answer where the row did not, so a session let through would get a gate in
# place of its finding.
# GC_ESCALATE_VERDICT_WINDOW is read by nothing, so an old call declares no
# quiet window. The hand-off goes once no open step bead's description names
# escalate.sh and no session that read the old name in its prompt still runs
# (the debt and its trigger are in specs/tk-0ur8r9p/design.md, section 10).
set -uo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=bd-lib.sh
. "${GC_BD_LIB:-$HERE/bd-lib.sh}" || { echo "escalate: cannot source bd-lib.sh beside this script" >&2; exit 1; }

ARGS=(); SUBJECT=""; KEY=""; MESSAGE=""; RETRACT=0
while [ $# -gt 0 ]; do
  case "$1" in
    --pool)
      echo "escalate: --pool ${2:-} dropped; a human gate is cleared by a person and routed to no pool" >&2
      shift; [ $# -eq 0 ] || shift ;;
    --subject|--key|--message)
      if [ $# -lt 2 ]; then ARGS+=("$1"); shift; continue; fi
      case "$1" in
        --subject) SUBJECT="$2" ;;
        --key)     KEY="$2" ;;
        --message) MESSAGE="$2" ;;
      esac
      ARGS+=("$1" "$2"); shift 2 ;;
    --retract) RETRACT=1; ARGS+=("$1"); shift ;;
    *) ARGS+=("$1"); shift ;;
  esac
done

# no_wait_why <subject> -> what the subject names when it is no bead that can
# wait for a person, or nothing when it is a bead that can. The `*-wisp-*` shape
# answers without a read. Otherwise the subject's own row decides, and only a
# row carrying this exact id and a type is an answer, because bd also answers an
# id that is a prefix of another bead's. Only when no such row reads is
# bead-store.sh asked, so a call about a bead costs the one read, and only
# bead-store.sh's exit 1 proves that no bead is named. Anything else returns 1.
no_wait_why() {
  local rc=0 row="" type=""
  case "$1" in *-wisp-*) echo "names a patrol wisp or a session"; return 0 ;; esac
  if row=$(bd_json show "$1") && type=$(printf '%s' "$row" | jq -er --arg id "$1" '
      if type == "array" then [ .[] | objects | select(.id == $id) ][0].issue_type else null end
      | strings | select(length > 0)' 2>/dev/null); then
    if [ "$type" = session ]; then echo "names a session"; fi
    return 0
  fi
  "$HERE/bead-store.sh" "$1" >/dev/null 2>&1 || rc=$?
  if [ "$rc" -eq 1 ]; then echo "names no bead"; return 0; fi
  return 1
}

# A subject outside the helper's id charset goes to the helper, which refuses it
# as a usage error, as the old script did.
case "$SUBJECT" in
  ''|*[!A-Za-z0-9._-]*) ;;
  *)
    if [ "$RETRACT" = 0 ] && [ -n "$KEY" ] && [ -n "$MESSAGE" ]; then
      WHY=$(no_wait_why "$SUBJECT") || {
        echo "escalate: '$SUBJECT' did not read as one bead with a type through gc bd show (no such bead, or its store did not answer), so nothing shows whether a human gate can hold it. Nothing was filed." >&2
        exit 1
      }
      if [ -n "$WHY" ]; then
        TITLE="${MESSAGE%%$'\n'*}"
        [ -n "$TITLE" ] || TITLE="$KEY"
        echo "escalate: '$SUBJECT' $WHY, not a bead a human gate can hold; filing the call as a patrol finding under [$KEY]" >&2
        exec "$HERE/patrol-finding.sh" --key "$KEY" --title "$TITLE" --message "$MESSAGE"
      fi
    fi ;;
esac
exec "$HERE/human-gate.sh" ${ARGS[@]+"${ARGS[@]}"}
