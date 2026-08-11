#!/usr/bin/env bash
# converse-signoff.test.sh — regression test for the converse role's
# thread-ending contract (bug tk-bzm86; precedent: gate-visit.test.sh).
#
# The bug: an operator was reading a converse thread; it ended and simply
# vanished. The work was recorded correctly and the operator was never
# told. Two endings produce that same disappearance —
#   1. deliberate close (step 6 → step 7 drains, the session goes), and
#   2. an idle reap, which clears the scrollback and, under
#      wake_mode=fresh, respawns a clean session — the thread is
#      unrecoverable, not hidden.
# Nothing pack-owned runs at kill time, so the contract has to hold the
# line in two places, and BOTH are load-bearing:
#   • the durable trace is stamped when the hold BEGINS, not only at
#     close — that is the only thing that survives a reap; and
#   • a deliberate close ends with a sign-off block naming the outcome
#     and the subject to look at next, so the last line the operator
#     sees is an ending rather than an unanswered question.
#
# Each assertion below is one way the fix silently reverts. A prompt is
# prose: a well-meaning edit that "tidies" the hold step can drop the
# stamp, and nothing downstream notices — the sitting still works, the
# record still lands, and only a reaped operator ever pays. Hence a test
# rather than a comment.
#
# Hermetic: reads the repo only; no gc, no city, no network.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$HERE/../.."
PROMPT="$REPO/agents/converse/prompt.template.md"
ATOML="$REPO/agents/converse/agent.toml"
HELM="$REPO/assets/scripts/gc-helm.sh"
ENGAGE="$REPO/docs/gascity-human-engagement.md"

PASS=0
FAIL=0
ok() {
    PASS=$((PASS + 1))
    printf '  ok    %s\n' "$1"
}
bad() {
    FAIL=$((FAIL + 1))
    printf '  FAIL  %s\n        %s\n' "$1" "$2"
}
# have <label> <literal> <file> — fixed-string presence
have() {
    if grep -qF -- "$2" "$3"; then ok "$1"; else bad "$1" "missing: $2"; fi
}
# lacks <label> <literal> <file> <why>
lacks() {
    if grep -qF -- "$2" "$3"; then bad "$1" "$4"; else ok "$1"; fi
}

for f in "$PROMPT" "$ATOML" "$HELM" "$ENGAGE"; do
    [ -r "$f" ] || {
        printf 'converse-signoff: cannot read %s\n' "$f" >&2
        exit 1
    }
done

echo "── the hold stamps the takeaway BEFORE waiting (survives a reap) ──"
# The reap defense in full: without a stamp written at hold time, a
# reaped sitting leaves nothing at all — the visit is in_progress, the
# subject is silent, and the thread that knew why is gone.
have "hold stamps via the helm takeaway writer" 'takeaway "$SUBJECT"' "$PROMPT"
have "hold stamp is attributed --by converse" '--by converse' "$PROMPT"
have "hold stamp carries the holding- prefix" '"holding — ' "$PROMPT"
# Each takeaway block runs in its own shell, so every one of them must
# resolve HELM itself. A block that inherits the variable from an earlier
# step resolves to the empty string and the stamp never lands — silently,
# at exactly the moment the trace is the only thing that would survive.
n_takeaway=$(grep -c 'takeaway "\$SUBJECT"' "$PROMPT")
n_helm=$(grep -c '^   HELM=' "$PROMPT")
if [ "$n_takeaway" -ge 2 ] && [ "$n_helm" -eq "$n_takeaway" ]; then
    ok "every takeaway block resolves HELM itself ($n_helm/$n_takeaway)"
else
    bad "every takeaway block resolves HELM itself" \
        "$n_takeaway takeaway call(s), $n_helm HELM resolution(s) — a block relying on an earlier step's shell var stamps nothing"
fi
# The stamp must be a plain takeaway: --release clears assignee and route
# and marks a proactive reaction, which would park a subject the operator
# is actively in conversation about.
if grep -n 'takeaway "\$SUBJECT"' "$PROMPT" | grep -q -- '--release'; then
    bad "no --release on a converse takeaway" \
        "--release parks the subject (clears assignee + route) mid-conversation"
else
    ok "no --release on a converse takeaway"
fi

echo "── the sitting ends out loud (deliberate-close path) ──"
have "sign-off block is named in the close step" 'sign-off block' "$PROMPT"
have "sign-off line 1: Ended (<outcome>)" 'Ended (<one-word-outcome>):' "$PROMPT"
have "sign-off line 2 points at the subject" 'Look at: <subject-id>' "$PROMPT"
have "the outcome stamp is still verified before the close" \
    "jq -e '.[0].metadata[\"gc.outcome\"] // empty'" "$PROMPT"
have "close step still closes only the visit" 'gc bd close "$VISIT"' "$PROMPT"
have "the bug is cited where the rule lives" 'tk-bzm86' "$PROMPT"

echo "── a cut-short sitting signs off too ──"
# The low-context exit is the likeliest ending to skip the sign-off,
# because the whole point of it is that the session is out of room.
if grep -A 4 'Low context mid-hold' "$PROMPT" | grep -q 'sign-off'; then
    ok "low-context exit routes through the sign-off"
else
    bad "low-context exit routes through the sign-off" \
        "cut-short must still end out loud (step 6, not a bare close)"
fi

echo "── the reap is documented where the role can see it ──"
have "prompt carries a reap rule" 'The reap' "$PROMPT"
have "reap rule names the real clock" 'idle_timeout' "$PROMPT"
have "reap rule states the thread is unrecoverable" 'wake_mode' "$PROMPT"

echo "── the agent config no longer claims timeouts do not end a sitting ──"
# The original comment asserted "visit boundaries, not timeouts, end it".
# It was false, and it is exactly what stops the next reader from looking.
lacks "no 'visit boundaries, not timeouts' claim" \
    'visit boundaries, not' "$ATOML" \
    "the claim is false: idle_timeout + the assigned-work defer cap do end a held sitting"
have "config points at the verified mechanism" 'gascity-human-engagement.md' "$ATOML"

echo "── the verified mechanism is recorded centrally ──"
have "engagement doc has the ending section" 'How a held sitting ends' "$ENGAGE"
have "doc corrects the wisp_ttl misreading" 'wisp_ttl' "$ENGAGE"
have "doc names the tmux activity source" 'window_activity' "$ENGAGE"
have "doc names the defer cap" 'assigned_work_defer_limit' "$ENGAGE"
have "doc records the scrollback erasure" 'ClearScrollback' "$ENGAGE"
have "doc names the unbuilt core seam" 'IsAttached' "$ENGAGE"

echo "── the writer the contract depends on still exists ──"
have "gc-helm exposes the takeaway verb" 'cmd_takeaway()' "$HELM"
have "takeaway usage documents the converse caller" 'host|proactive|converse' "$HELM"
# The stamp keys are the contract with the board; renaming one silently
# empties every NEEDS cell.
have "takeaway stamps gc.takeaway" 'gc.takeaway=$text' "$HELM"

echo
echo "converse-signoff: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
