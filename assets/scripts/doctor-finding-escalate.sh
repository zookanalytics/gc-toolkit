#!/usr/bin/env bash
# doctor-finding-escalate.sh — file ONE `gc doctor` finding as a visit through
# escalate.sh, with the situation key and the message derived from the finding.
#   doctor-finding-escalate.sh --subject <bead-id> --finding <json> [--pool <pool>]
#   <json on stdin> | doctor-finding-escalate.sh --subject <bead-id> [--pool <pool>]
# <json> is ONE object from `gc doctor --json` `.results[]`.
#
# escalate.sh dedups on escalation_key together with gc.continuation_group, so
# the key IS the situation's identity: two spellings of one check name are two
# situations, and one-open-visit-per-situation holds only between calls that
# spell the key the same way. The key here is a function of `.name` alone —
# `doctor-` followed by the name with every byte outside escalate.sh's
# [A-Za-z0-9._-] charset replaced by `-` — so every caller naming one check
# arrives at one key.
#
# The message is `.message` first, then the finding's remaining fields as
# labelled lines. escalate.sh takes the message's first line as the visit
# title's headline, so a whole finding object handed over as the message puts
# JSON on an operator-facing surface.
#
# A finding that names no check is refused rather than escalated under an
# invented key: composing one by hand is what this script exists to remove.
# Exit: escalate.sh's, once the call is forwarded · 1 escalate.sh unavailable
#       · 2 usage, or an input that is not exactly one finding naming a check.
set -uo pipefail

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload. All but
# LF go: raw TAB and CR do not occur in bd/gh output, and the TAB-splitting
# consumers downstream split jq's own @tsv, emitted after this runs.
scrub() { tr -d '\000-\011\013-\037'; }
# <<< control-char-scrub

usage() {
  cat >&2 <<'U'
usage: doctor-finding-escalate.sh --subject <bead-id> [--finding <json>]
                                  [--pool <rig-qualified converse pool>]

  --subject  the bead the escalation is about; escalate.sh tracks it and
             narrows the dedup to it when it is durable (required)
  --finding  ONE object from `gc doctor --json` `.results[]`. Read from stdin
             when the flag is absent
  --pool     converse pool to route to; passed through to escalate.sh, which
             holds the default and the routability check
U
}

warn() { echo "doctor-finding-escalate: $*" >&2; }

SUBJECT=""; FINDING=""; FINDING_GIVEN=0; POOL=""
while [ $# -gt 0 ]; do
  case "$1" in
    --subject) SUBJECT="${2:-}"; shift 2 || { usage; exit 2; } ;;
    --finding) FINDING="${2:-}"; FINDING_GIVEN=1; shift 2 || { usage; exit 2; } ;;
    --pool)    POOL="${2:-}";    shift 2 || { usage; exit 2; } ;;
    -h|--help) usage; exit 2 ;;
    *) warn "unknown argument '$1'"; usage; exit 2 ;;
  esac
done
[ -n "$SUBJECT" ] || { warn "--subject is required"; usage; exit 2; }
command -v jq >/dev/null 2>&1 || { warn "jq is required to read the finding"; exit 2; }

if [ "$FINDING_GIVEN" != 1 ]; then
  if [ -t 0 ]; then
    warn "no --finding, and stdin is a terminal — there is nothing to read"
    usage; exit 2
  fi
  FINDING=$(cat)
fi
FINDING=$(printf '%s' "$FINDING" | scrub)

# Exactly one finding, or nothing is filed. An empty selection and a selection
# matching several checks both reach here as a caller's `jq` output, and both
# would otherwise escalate under a key that names the wrong situation.
case "$FINDING" in
  *[![:space:]]*) ;;
  *) warn "no finding given (--finding was empty, or stdin carried nothing) — nothing filed"; exit 2 ;;
esac
COUNT=$(printf '%s' "$FINDING" | jq -s 'length' 2>/dev/null)
case "$COUNT" in
  1) ;;
  ''|*[!0-9]*) warn "the finding does not parse as JSON — nothing filed"; exit 2 ;;
  *) warn "expected ONE finding, got $COUNT — escalate each under its own key; nothing filed"; exit 2 ;;
esac

NAME=$(printf '%s' "$FINDING" | jq -r 'if type == "object" then ((.name // "") | tostring) else "" end' 2>/dev/null)
[ -n "$NAME" ] || { warn "the finding names no check (.name is absent or empty) — nothing filed"; exit 2; }

# LC_ALL=C keeps the charset a byte set: a multi-byte character outside it
# becomes dashes here rather than passing as alphanumeric and failing
# escalate.sh's own charset check.
SLUG=$(printf '%s' "$NAME" | LC_ALL=C tr -c 'A-Za-z0-9._-' '-' | LC_ALL=C tr -s '-')
SLUG="${SLUG#-}"; SLUG="${SLUG%-}"
[ -n "$SLUG" ] || { warn "check name '$NAME' carries no key-legal byte — nothing filed"; exit 2; }
KEY="doctor-$SLUG"

# `.message` is the prose the visit title is cut from; the rest of the finding
# rides the body, where a human reads it. A finding with no message still gets
# a prose headline, never a blank one.
MESSAGE=$(printf '%s' "$FINDING" | jq -r '
  def labelled($label; $v): if (($v // "") | tostring) == "" then empty else "\($label): \($v | tostring)" end;
  ((.message // "") | tostring) as $m
  | (if ($m | test("[^[:space:]]")) then $m
     else "doctor check \(.name) reports \((.status // "a finding") | tostring)" end) as $head
  | [ $head, "", "check: \(.name)" ]
    + [ labelled("status"; .status) ]
    + [ labelled("severity"; .severity) ]
    + [ labelled("fix hint"; .fix_hint) ]
    + ((.details // []) | if type == "array" and length > 0
       then [ "details:" ] + map("  - " + tostring) else [] end)
  | join("\n")' 2>/dev/null)
[ -n "$MESSAGE" ] || { warn "could not compose a message from the finding — nothing filed"; exit 2; }

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ESCALATE="$HERE/escalate.sh"
[ -x "$ESCALATE" ] || { warn "escalate.sh is not beside this script ($ESCALATE) — nothing filed"; exit 1; }

warn "check '$NAME' escalates under key '$KEY'"
ARGS=(--subject "$SUBJECT" --key "$KEY" --message "$MESSAGE")
[ -z "$POOL" ] || ARGS+=(--pool "$POOL")
exec "$ESCALATE" "${ARGS[@]}"
