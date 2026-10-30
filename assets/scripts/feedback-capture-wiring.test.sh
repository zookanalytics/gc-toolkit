#!/usr/bin/env bash
# A pool session has no one at its terminal, so every turn typed there is text
# the city sends, and its wake nudge reads like a correction. The session
# decides whether a turn is feedback to file where the capture recipe,
# template-fragments/file-feedback-observations.template.md, tells it to, so
# the recipe says which turns can carry the operator's words. This pins that
# text in the prompts the agents receive, the renders under
# generated/seed-audit/agents, which render-seed-audit.sh --check and the merge
# gate hold to their sources:
#
#   1. The polecat and polecat-codex renders say that a turn in the session's
#      own terminal is the city's text and never an operator correction, and
#      name the durable sources a pool session captures from.
#   2. Every render that carries the recipe, the mechanik's and the converse
#      sittings' among them, tells a session the operator attends that it
#      captures the operator's own turns too.
#
# The fragment is checked first, so a render that lacks a sentence its source
# carries reads as a stale render. Text is compared with its line breaks
# joined, so re-wrapping a paragraph passes and rewording one fails.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
FRAGMENT="$ROOT/template-fragments/file-feedback-observations.template.md"
RENDERS="$ROOT/generated/seed-audit/agents"
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }

joined() { tr '\n' ' ' <"$1" | tr -s ' '; }
carries() { case "$(joined "$1")" in *"$2"*) return 0 ;; esac; return 1; }

POOL_TERMINAL="A pool session, such as a polecat, has no one at its terminal by design, so every turn in its own terminal is the city's text: a configured nudge such as the wake nudge, a reminder, hook output, or another agent's \`gc session nudge\`."
POOL_NOT_OPERATOR="Such a turn is never an operator correction, even when it arrives as a user message and reads like one, so it files no observation."
POOL_SOURCES="A pool session captures only from durable sources: a PR review or comment, a rework's rejection reason, and a bead's notes."
ATTENDED="A session the operator attends, such as a converse sitting on a visit or mechanik, captures from those sources and from the operator's own turns."
POOL_SENTENCES=("$POOL_TERMINAL" "$POOL_NOT_OPERATOR" "$POOL_SOURCES")

[ -s "$FRAGMENT" ] || { echo "missing $FRAGMENT" >&2; exit 1; }
for s in "${POOL_SENTENCES[@]}" "$ATTENDED"; do
  carries "$FRAGMENT" "$s" && ok "the capture recipe says: ${s:0:72}…" \
    || bad "the capture recipe lost: $s"
done

for agent in polecat polecat-codex; do
  render="$RENDERS/$agent.md"
  if [ ! -s "$render" ]; then
    bad "$agent has no render at $render"
    continue
  fi
  for s in "${POOL_SENTENCES[@]}"; do
    carries "$render" "$s" && ok "$agent's prompt says: ${s:0:60}…" \
      || bad "$agent's prompt lacks: $s (re-render with assets/scripts/render-seed-audit.sh if the fragment carries it)"
  done
done

WITH_RECIPE=""
for render in "$RENDERS"/*.md; do
  grep -q '^## Feedback observations$' "$render" || continue
  agent=$(basename "$render" .md)
  WITH_RECIPE="$WITH_RECIPE $agent"
  carries "$render" "$ATTENDED" && ok "$agent's prompt tells an attended session to capture the operator's own turns" \
    || bad "$agent's prompt carries the capture recipe without: $ATTENDED"
done
for agent in polecat polecat-codex mechanik converse-opus; do
  case " $WITH_RECIPE " in
    *" $agent "*) ok "$agent's prompt carries the capture recipe" ;;
    *) bad "$agent's prompt no longer carries the capture recipe (found in:${WITH_RECIPE:- none})" ;;
  esac
done

echo
echo "feedback-capture-wiring: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
