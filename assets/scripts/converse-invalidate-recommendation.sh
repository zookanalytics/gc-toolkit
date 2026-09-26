#!/usr/bin/env bash
# converse-invalidate-recommendation.sh — a converse sitting's active strip of a
# first-reaction recommendation it has judged no longer valid. It removes
# gc.recommended_formula from the SUBJECT and records why, leaving the subject
# and its visit open. gc.recommended_formula is the key the operator's Accept
# reads — the board offers Accept only where it is present — so removing it
# withdraws Accept while the visit stays for Discuss.
#
# This is the durable half of the invalidation rule. A live sitting already
# suppresses Accept, because the board offers it only on an un-engaged visit, so
# the strip is what keeps Accept withdrawn once the sitting ends and the visit
# un-engages: a recommendation the sitting rejected does not return as a
# one-click action.
#
# Disposing of the subject is a different act: bead-rehome.sh (a no-work subject)
# and a PR retire close the subject and its gate, and a closed gate offers no
# Accept. Use this only where the subject stays open for Discuss.
#
# gc.recommended_formula has a reader, so the unset is read back and repaired: a
# key that survives is Accept returning, the exact defect this exists to prevent.
#
# Inputs:
#   $1       the reason: why the recommendation is no longer valid
#   SUBJECT  the subject bead carrying gc.recommended_formula (environment)
#   VISIT    the sitting's visit; named in the note when set (environment, optional)
# Exit: 0 stripped, or nothing to strip; 2 usage; 3 subject unreadable;
#       4 the key survived the unset.
set -u

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

REASON="${1:-}"
SUBJECT="${SUBJECT:-}"
VISIT="${VISIT:-}"

[ -n "$SUBJECT" ] || { echo "converse-invalidate-recommendation: \$SUBJECT is required" >&2; exit 2; }
[ -n "$REASON" ]  || { echo "converse-invalidate-recommendation: a reason (why the recommendation is no longer valid) is required (arg 1)" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "converse-invalidate-recommendation: jq is required" >&2; exit 2; }
command -v gc >/dev/null 2>&1 || { echo "converse-invalidate-recommendation: gc is required" >&2; exit 2; }

# Present in ANY form means Accept is derivable — an empty value round-trips as a
# present key — so read presence with has(), not a non-empty test. An unreadable
# subject is not proof there is nothing to strip; treat it as blocked.
present() { gc bd show "$SUBJECT" --json | scrub | jq -r '(.[0].metadata // {}) | has("gc.recommended_formula")'; }
HAD=$(present)
case "$HAD" in
  true)  ;;
  false) echo "converse-invalidate-recommendation: $SUBJECT carries no gc.recommended_formula — nothing to invalidate (already Discuss-only)."; exit 0 ;;
  *)     echo "converse-invalidate-recommendation: could not read $SUBJECT (got '${HAD:-<empty>}') — an unreadable subject is not proof there is nothing to strip; refusing" >&2; exit 3 ;;
esac
WAS=$(gc bd show "$SUBJECT" --json | scrub | jq -r '(.[0].metadata // {})["gc.recommended_formula"] // ""')

# The record and the act in one write: either both land or neither, so a
# half-run never strips without its reason or records a reason without the strip.
NOTE="recommendation invalidated${VISIT:+ (visit $VISIT)}: was '${WAS:-<empty>}'. $REASON. Accept withdrawn; Discuss remains."
gc bd update "$SUBJECT" --unset-metadata gc.recommended_formula --append-notes "$NOTE" \
  || echo "converse-invalidate-recommendation: the strip update returned non-zero on $SUBJECT — verifying by read-back before trusting it" >&2

# Read back and repair: the key has a reader, and a silent drop in a multi-field
# update can leave it standing. A surviving key is Accept returning, so retry a
# lone unset and refuse to report success if it is still there.
STILL=$(present)
if [ "$STILL" = "true" ]; then
  echo "converse-invalidate-recommendation: gc.recommended_formula read back present on $SUBJECT — repairing with a lone unset" >&2
  gc bd update "$SUBJECT" --unset-metadata gc.recommended_formula >/dev/null 2>&1 || true
  STILL=$(present)
fi
if [ "$STILL" != "false" ]; then
  echo "converse-invalidate-recommendation: gc.recommended_formula survived the unset on $SUBJECT (read '${STILL:-<empty>}') — Accept would return; refusing to report success" >&2
  exit 4
fi
echo "converse-invalidate-recommendation: stripped gc.recommended_formula (was '${WAS:-<empty>}') from $SUBJECT — Accept withdrawn; Discuss remains."
