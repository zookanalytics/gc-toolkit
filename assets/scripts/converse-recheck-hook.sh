#!/usr/bin/env bash
# converse-recheck-hook.sh — a visit body is written at FILING time, so before
# prep run the re-check the filer left, if it left one. `visit.recheck` is a
# path to an executable taking the visit id as its only argument — a stamp,
# never a command string to eval. Its output supersedes the body's lists. A
# missing or non-executable stamp is LOUD: the body is UNVERIFIED.
# assets/scripts/liveness-recheck.test.sh keeps the stamp key this reads in
# step with the one liveness-sweep.sh writes.
#
# Input (environment, or positional fallback):
#   VISIT  the visit bead ($1)
set -u

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload. All but
# LF go: raw TAB and CR do not occur in bd/gh output, and the TAB-splitting
# consumers downstream split jq's own @tsv, emitted after this runs.
scrub() { tr -d '\000-\011\013-\037'; }
# <<< control-char-scrub

VISIT="${VISIT:-${1:-}}"

[ -n "$VISIT" ] || { echo "converse-recheck-hook: a visit id is required (\$VISIT or arg 1)" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "converse-recheck-hook: jq is required" >&2; exit 2; }
command -v gc >/dev/null 2>&1 || { echo "converse-recheck-hook: gc is required" >&2; exit 2; }

RECHECK=$(gc bd show "$VISIT" --json | scrub | jq -r '.[0].metadata["visit.recheck"] // ""')
if [ -n "$RECHECK" ] && [ -x "$RECHECK" ]; then "$RECHECK" "$VISIT"
elif [ -n "$RECHECK" ]; then echo "visit.recheck=$RECHECK is not executable here — the body is UNVERIFIED; re-verify by hand before routing anything"; fi
