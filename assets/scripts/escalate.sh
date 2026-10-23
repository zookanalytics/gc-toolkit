#!/usr/bin/env bash
# escalate.sh — the old name of human-gate.sh, kept as a hand-off that runs it.
# A run keeps the text its steps were poured with, so a step poured before the
# rename still calls this path, and mol-polecat-work's load-context looks for it
# on every such run. A call reaches human-gate.sh with its own arguments, except
# where the old contract took what the helper refuses, so that an old call still
# files rather than exits on a usage error:
#   --pool <pool> routed the old visit to a pool. A gate is cleared by a person
#     and routed nowhere, so the flag is dropped, with a notice.
#   A wisp or a session named as the subject of a filing was redirected onto a
#     standing triage bead. The helper refuses one, so the call is filed as a
#     patrol finding under its key instead, the route that refusal names. A
#     --retract on one goes to the helper, which refuses it as the old script
#     did.
# GC_ESCALATE_VERDICT_WINDOW is read by nothing, so an old call declares no
# quiet window. The hand-off goes once no open step bead's description names
# escalate.sh and no session that read the old name in its prompt still runs
# (the debt and its trigger are in specs/tk-0ur8r9p/design.md, section 10).
set -uo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"

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

case "$SUBJECT" in
  *-wisp-*)
    if [ "$RETRACT" = 0 ] && [ -n "$KEY" ] && [ -n "$MESSAGE" ]; then
      TITLE="${MESSAGE%%$'\n'*}"
      [ -n "$TITLE" ] || TITLE="$KEY"
      echo "escalate: '$SUBJECT' names a patrol wisp or a session, which no human gate can block; filing the call as a patrol finding under [$KEY]" >&2
      exec "$HERE/patrol-finding.sh" --key "$KEY" --title "$TITLE" --message "$MESSAGE"
    fi ;;
esac
exec "$HERE/human-gate.sh" ${ARGS[@]+"${ARGS[@]}"}
