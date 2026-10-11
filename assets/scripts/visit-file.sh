#!/usr/bin/env bash
# visit-file — file the one conversation visit a subject gets on the helm board,
# or reuse a conversation visit already open on it.
#
#   visit-file.sh --subject <bead> --title "<title tail>" --description "<visit body>"
#
# The marked region is the gate-visit convention's formula form
# (formulas/mol-visit.toml carries the canonical copy). It reuses a conversation
# visit already open on the subject, matched by visit-identity.sh's coverage (the
# tracks edge, else the group stamp), and never an escalate.sh visit, which its
# escalation_key closes on its own situation's terms. Otherwise it files the
# visit as "visit: <subject> — <title>", parks it on the helm board
# (gc.routed_to=human), wires it to its subject with a tracks edge, and repairs a
# group stamp that landed empty. gate-visit.test.sh holds the region to the
# convention's invariants and runs its reuse.
#
# Prints the visit's id: the one reused, or the one filed.
# Called by mol-feedback-distiller's file-and-dispatch step, for a contested rule.
# exit: 0 a visit reused or filed · 1 bd created no visit · 2 usage
# shellcheck disable=SC1090  # the region sources visit-identity.sh from the pack it locates

PROG="visit-file"
SUBJECT=""; TITLE=""; DESCRIPTION=""
while [ $# -gt 0 ]; do
  case "$1" in
    --subject|--title|--description)
      [ "$#" -ge 2 ] || { echo "$PROG: $1 requires a value" >&2; exit 2; }
      case "$1" in
        --subject)     SUBJECT="$2" ;;
        --title)       TITLE="$2" ;;
        --description) DESCRIPTION="$2" ;;
      esac
      shift 2 ;;
    *) echo "usage: $PROG --subject <bead> --title <text> --description <text>" >&2; exit 2 ;;
  esac
done
if [ -z "$SUBJECT" ] || [ -z "$TITLE" ] || [ -z "$DESCRIPTION" ]; then
  echo "usage: $PROG --subject <bead> --title <text> --description <text>" >&2
  exit 2
fi

# >>> gate-visit
# Retired converse pool: the visit parks on the helm board (gc.routed_to=human).
POOL="human"
# One conversation visit per subject: a re-run of this block, or a pattern that
# already has a conversation open, reuses that visit and files nothing.
# Coverage is visit-identity.sh's rule (the tracks edge, else the group stamp).
# An escalate.sh visit (escalation_key) closes on its own situation's terms, so
# it never stands in for this one. A listing that does not read files anyway.
VISIT=""
VI=""; for c in "${GC_PACK_DIR:-}" "${GC_RIG_ROOT:-}" "$(git rev-parse --show-toplevel 2>/dev/null)" "${GC_CITY_PATH:-}/rigs/gc-toolkit"; do
  [ -f "$c/assets/scripts/visit-identity.sh" ] && { VI="$c/assets/scripts/visit-identity.sh"; break; }
done
if [ -n "$VI" ] && . "$VI"; then
  VISIT=$(gc bd list --status=open,in_progress --metadata-field task_kind=visit --json --limit 0 2>/dev/null | tr -d '[:cntrl:]' | jq -r --arg s "$SUBJECT" "$VISIT_IDENTITY_JQ"'if type == "array" then ([ .[]
        | select((.metadata.task_kind // "") == "visit" and (.metadata.escalation_key // "") == "")
        | select(.status == "open" or .status == "in_progress")
        | select(visit_covers($s)) | .id ] | sort | .[0] // "") else "" end' 2>/dev/null || printf '')
else
  echo "gate-visit: warning: visit-identity.sh not found, so no open visit on $SUBJECT can be matched — filing" >&2
fi
if [ -n "$VISIT" ]; then
  echo "gate-visit: visit $VISIT is already open on $SUBJECT — reusing it, not filing a second" >&2
else
  VISIT_JSON=$(gc bd create -t task --title "visit: $SUBJECT — $TITLE" -d "$DESCRIPTION" --json)
  VISIT=$(printf '%s' "$VISIT_JSON" | jq -r 'if type == "array" then (.[0].id // empty) else (.id // empty) end' 2>/dev/null)
  [ -n "$VISIT" ] && [ "$VISIT" != "null" ] || { CREATE_ERR=$(printf '%s' "$VISIT_JSON" | jq -r 'if type == "object" then (.error // empty) else empty end' 2>/dev/null)
         echo "gate-visit: bd create returned no id${CREATE_ERR:+: $CREATE_ERR} — stop, address what bd reported, and re-run this block; do not improvise another create form" >&2; exit 1; }
  gc bd update "$VISIT" --set-metadata "gc.routed_to=$POOL" --set-metadata "gc.continuation_group=$SUBJECT" --set-metadata "task_kind=visit"
  gc bd dep add "$VISIT" "$SUBJECT" --type=tracks
  # tracks, not parent-child: a parent-child edge would transmit the
  # subject's blocked state to the visit, making it unclaimable.
  # Read the group stamp back and repair it from the subject if it landed
  # empty: it can land present-but-empty while every sibling stamp in the
  # same update lands, and an empty group disables converse's group-scoped
  # re-claim fence. Repair and warn, never exit — this block files the one
  # visit for its scope, and on a persistent miss the tracks edge still
  # carries the subject for guards that read the union.
  GROUP_GOT=$(gc bd show "$VISIT" --json | tr -d '[:cntrl:]' | jq -r '.[0].metadata["gc.continuation_group"] // ""' 2>/dev/null || printf '')
  if [ "$GROUP_GOT" != "$SUBJECT" ]; then
    echo "gate-visit: warning: gc.continuation_group on $VISIT read back as '$GROUP_GOT', expected '$SUBJECT' — repairing" >&2
    gc bd update "$VISIT" --set-metadata "gc.continuation_group=$SUBJECT" || true
    GROUP_GOT=$(gc bd show "$VISIT" --json | tr -d '[:cntrl:]' | jq -r '.[0].metadata["gc.continuation_group"] // ""' 2>/dev/null || printf '')
    if [ "$GROUP_GOT" = "$SUBJECT" ]; then
      echo "gate-visit: the repair landed on $VISIT" >&2
    else
      echo "gate-visit: warning: the repair did not land on $VISIT — the tracks edge still carries the subject, and the live-visit guards read the union" >&2
    fi
  fi
fi
# <<< gate-visit
printf '%s\n' "$VISIT"
