#!/usr/bin/env bash
# step-close-env-id.sh — hardened learned rule: no step closes a bead on an id
# read from the environment (ported from the retired
# doctor/check-step-close-owns-bead). $GC_BEAD_ID is not populated in the
# step-execution environment (the guarded close no-ops and the step re-offers
# forever), and $GC_TRIGGER_BEAD_ID is NOT refreshed by `gc hook --claim` (the
# close lands on another session's bead — fails open at exit 0). Flagged:
# COMMAND lines where `bd close <env-id>` or `bd update <env-id> …
# --status=closed` takes a GC_*BEAD_ID variable. Not flagged: non-closing
# writes, prose, specs/ (dated records), generated/ (render duplicates).
# Fix: close through assets/scripts/step-close.sh --step <formula>.<step-id>.
# Exit: 0 clean, 1 findings as `<file>:<line>: <message>`.

set -uo pipefail

# An environment-supplied bead id as a command argument, in quoted, braced,
# and bare spellings.
ENV_ID='"?\$\{?GC_[A-Z_]*BEAD_ID'
CLOSE_CMD='bd[[:space:]]+close[[:space:]]+'"$ENV_ID"
# Anchored so the id must be the UPDATE TARGET, not a later flag value.
UPDATE_CLOSE='bd[[:space:]]+update[[:space:]]+'"$ENV_ID"'[^|;&]*--status[= ]closed'
# A COMMAND line, not prose (the hazard is quoted all over the pack).
CMD_SHAPE='^[[:space:]]*(gc[[:space:]]+bd|bd|\[)[[:space:]]'

found=0
for f in "$@"; do
    [ -f "$f" ] || continue
    case "$f" in
        */lint-learned.d/* | */base-snapshots/* | */specs/* | specs/* | */generated/* | generated/*) continue ;;
    esac
    case "$f" in *.toml | *.sh | *.md) ;; *) continue ;; esac
    while IFS= read -r hit; do
        no="${hit%%:*}"; body="${hit#*:}"
        case "$(printf '%s' "$body" | tr -d '[:space:]')" in '#'*) continue ;; esac
        grep -qE "$CMD_SHAPE" <<< "$body" || continue
        echo "$f:$no: closes a bead on an id from the environment — \$GC_TRIGGER_BEAD_ID goes stale across \`gc hook --claim\` (closes another session's bead) and \$GC_BEAD_ID is unset in steps (closes nothing); use assets/scripts/step-close.sh --step <formula>.<step-id> (learned rule: step-close-env-id)"
        found=1
    done < <(grep -nE "$CLOSE_CMD"'|'"$UPDATE_CLOSE" "$f" 2>/dev/null)
done

[ "$found" -eq 0 ]
