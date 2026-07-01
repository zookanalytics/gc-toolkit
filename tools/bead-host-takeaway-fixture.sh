#!/usr/bin/env bash
# bead-host-takeaway-fixture.sh — automatable assertions that the bead-host
# prompt instructs the resident host to keep its board-visible gc.takeaway
# current (epic tk-q4xaj; bead tk-q4xaj.3).
#
# The takeaway is the one-line headline gc-helm.sh renders as a bead's
# NEEDS. A bead-host keeps it fresh so a glance off the board explains where the
# conversation stands without opening it. Whether a LIVE host actually writes
# the metadata on a real turn needs a live LLM session — that is operator-
# deferred (the same class as bead-host-binding-fixture.sh assertions 2 & 5).
# What IS automatable, and what this fixture locks, is the PROMPT CONTRACT: the
# bead-host prompt must
#   • tell the host to refresh gc.takeaway on each meaningful turn — takeaway-
#     only (the per-turn note ritual is gone; host is the default --by); AND
#   • tell it to refresh the takeaway before an intentional drain; AND
#   • justify the per-turn cadence — there is no runtime drain hook for the hard
#     idle-timeout/detach case, so per-turn freshness is what survives a suspend.
#
# HERMETIC: a static read of the prompt template — no Dolt, no city, no
# sessions. Mirrors how proactive-first-reaction-fixture.sh verifies its
# worker-prompt contract ("the worker prompt names the contract").
#
# Run:   tools/bead-host-takeaway-fixture.sh
# Exit:  0 iff every assertion passes.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
PROMPT_MD="$ROOT/agents/bead-host/prompt.template.md"
[ -f "$PROMPT_MD" ] || { echo "fixture: $PROMPT_MD missing" >&2; exit 2; }

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n        expected: [%s]\n        actual:   [%s]\n' "$1" "$2" "$3"; }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "$2" "$3"; fi; }
has() { case "$3" in *"$2"*) ok "$1" ;; *) bad "$1" "contains: $2" "$3" ;; esac; }

PM="$(cat "$PROMPT_MD")"

echo "── the host stamps the board takeaway via the wrapper (takeaway-only) ──"
# The raw gc.takeaway/_at/_by triple lives inside gc-helm.sh; the prompt's
# contract is the WRAPPER INVOCATION (… takeaway "$BEAD" "<headline>") — takeaway-
# only, with no --by (host is the default) and no folded-in --note. So assert the
# call shape, not the encapsulated metadata fields.
# shellcheck disable=SC2016  # intentional: match the LITERAL "$BEAD" in the prompt text, no expansion
has "prompt refreshes the takeaway via the gc-helm wrapper" 'gc-helm.sh" takeaway "$BEAD"' "$PM"
# Both the per-turn block AND the drain block must invoke the wrapper.
# shellcheck disable=SC2016  # intentional: the literal "$BEAD" is prompt text, not expanded here
CALLS="$(grep -cF 'gc-helm.sh" takeaway "$BEAD"' "$PROMPT_MD" || true)"
eq "per-turn AND drain blocks each invoke the takeaway wrapper" "2" "$CALLS"
# Takeaway-only: the per-turn note ritual is gone. Match --note as a FLAG (not
# the longer gc-bd --notes capability, which stays in the Communication list).
NOTE_FLAG_HITS="$(grep -nE -- '--note([^s]|$)' "$PROMPT_MD" || true)"
eq "no per-turn --note flag remains (takeaway is takeaway-only)" "" "$NOTE_FLAG_HITS"

echo "── the cadence: per meaningful turn + before an intentional drain ──"
has "prompt frames the takeaway as a kept-current living field" "Keep Your Takeaway Current" "$PM"
has "prompt ties the takeaway refresh to each meaningful turn"  "each meaningful turn"        "$PM"
has "prompt refreshes the takeaway before a drain"     "Before an intentional drain" "$PM"
# The per-turn cadence is deliberate: no drain hook covers idle-timeout/detach,
# so a current takeaway means even an abrupt suspend leaves a recent headline.
has "prompt justifies the per-turn cadence (no drain hook)" "idle-timeout"           "$PM"

echo "── the takeaway is the board's NEEDS (the why) ──"
has "prompt ties the takeaway to the board NEEDS"  "NEEDS" "$PM"

echo ""
echo "bead-host-takeaway-fixture: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
