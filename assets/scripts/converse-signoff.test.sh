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
n_helm=$(grep -c '^ *HELM=' "$PROMPT")
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

echo "── the takeaway writer resolves in an IMPORTED (cross-rig) session ──"
# converse is scope="rig", so it is imported into EVERY rig, and
# rigNameForQualifiedAgent resolves the rig from the qualified name: a
# `signal-loom/gc-toolkit.converse` session runs with GC_RIG_ROOT pointing
# at signal-loom, a rig with no assets/ at all. A writer path built from
# GC_RIG_ROOT alone therefore names a file that does not exist — and
# because the variable is NON-EMPTY, a `${GC_RIG_ROOT:-<pack>}` default
# never fires to save it. Both mandatory stamps then fail before writing,
# in precisely the cross-rig shape that produced this bug's second
# instance (tk-bzm86 notes: signal-loom session lx-qk9v). Grepping the
# prompt cannot catch that, so these blocks are EXTRACTED AND RUN.
TMPD="$(mktemp -d)"
trap 'rm -rf "$TMPD"' EXIT
PACKROOT="$TMPD/city/rigs/gc-toolkit"
FOREIGN="$TMPD/city/rigs/signal-loom" # an importing rig: no assets/ tree
mkdir -p "$PACKROOT/assets/scripts" "$FOREIGN"
printf '#!/bin/sh\necho STUB-HELM "$@"\n' >"$PACKROOT/assets/scripts/gc-helm.sh"
chmod +x "$PACKROOT/assets/scripts/gc-helm.sh"

# extract_resolver <n> — everything the Nth takeaway block runs BEFORE it
# invokes the writer, de-indented. Deliberately shape-agnostic: it lifts
# whatever the prompt says rather than a resolver of an expected form, so
# a prompt that reverts to assuming one path is executed and FAILS on
# behaviour below, instead of skipping these cases for want of a match.
extract_resolver() {
    awk -v want="$1" '
        /^[[:space:]]*```/ { infence = !infence; nl = 0; next }
        !infence { next }
        {
            line = $0; sub(/^[[:space:]]*/, "", line)
            if (line ~ /^"\$HELM" takeaway/) {
                if (++n == want) { for (i = 1; i <= nl; i++) print buf[i]; exit }
                nl = 0; next
            }
            buf[++nl] = line
        }
    ' "$PROMPT"
}
# resolve <n> <GC_RIG_ROOT> <GC_CITY_PATH> — prints the writer it picked.
# Runs from $TMPD with git discovery fenced, so the middle candidate
# (`git rev-parse --show-toplevel`) cannot silently rescue a broken
# search from an ambient checkout; the case below exercises it on purpose.
# The value is tagged rather than simply echoed: a block may legitimately
# print of its own accord (the not-found guard does), and that output must
# not be mistaken for the resolved path.
resolve() {
    {
        extract_resolver "$1"
        printf 'printf "RESOLVED=%%s\\n" "$HELM"\n'
    } >"$TMPD/probe.sh"
    (cd "$TMPD" && GIT_CEILING_DIRECTORIES="$TMPD" GC_RIG_ROOT="$2" GC_CITY_PATH="$3" bash "$TMPD/probe.sh" 2>/dev/null) |
        sed -n 's/^RESOLVED=//p' | tail -1
}

# Fixture control: if the probe's cwd were itself inside a checkout that
# happens to ship assets/scripts/gc-helm.sh, every case below would pass
# for the wrong reason.
if (cd "$TMPD" && GIT_CEILING_DIRECTORIES="$TMPD" git rev-parse --show-toplevel >/dev/null 2>&1); then
    bad "probe runs outside any git checkout" \
        "$TMPD resolves to a repo; the toplevel candidate could mask a broken search"
else
    ok "probe runs outside any git checkout (toplevel candidate inert unless a case arms it)"
fi

n_blocks=$(grep -c '^[[:space:]]*"\$HELM" takeaway' "$PROMPT")
n_search=$(grep -c '\[ -x "\$cand/assets/scripts/gc-helm.sh" \]' "$PROMPT")
if [ "$n_blocks" -ge 2 ] && [ "$n_search" -eq "$n_blocks" ]; then
    ok "both takeaway blocks search for the writer rather than assume it ($n_search/$n_blocks)"
else
    bad "both takeaway blocks search for the writer rather than assume it" \
        "$n_search executable-test(s) for $n_blocks takeaway block(s); a path built from GC_RIG_ROOT alone is wrong in every imported session"
fi

blk=1
while [ "$blk" -le "$n_blocks" ]; do
    # THE REGRESSION: non-empty GC_RIG_ROOT naming a rig without the asset.
    got=$(resolve "$blk" "$FOREIGN" "$TMPD/city")
    if [ "$got" = "$PACKROOT/assets/scripts/gc-helm.sh" ]; then
        ok "block $blk: imported session (GC_RIG_ROOT=a rig without assets/) still finds the pack writer"
    else
        bad "block $blk: imported session (GC_RIG_ROOT=a rig without assets/) still finds the pack writer" \
            "resolved '$got' — a non-empty GC_RIG_ROOT must not defeat the pack fallback"
    fi
    # The owning rig keeps precedence: its checkout is the CURRENT source.
    got=$(resolve "$blk" "$PACKROOT" "$TMPD/city")
    if [ "$got" = "$PACKROOT/assets/scripts/gc-helm.sh" ]; then
        ok "block $blk: the owning rig's own copy still wins when it has one"
    else
        bad "block $blk: the owning rig's own copy still wins when it has one" \
            "resolved '$got'"
    fi
    # Unset GC_RIG_ROOT (city-scoped invocation) must not break the search.
    got=$(resolve "$blk" "" "$TMPD/city")
    if [ "$got" = "$PACKROOT/assets/scripts/gc-helm.sh" ]; then
        ok "block $blk: an empty GC_RIG_ROOT falls through to the city pack path"
    else
        bad "block $blk: an empty GC_RIG_ROOT falls through to the city pack path" \
            "resolved '$got'"
    fi
    # Nothing anywhere: must land EMPTY, which is what makes the loud
    # guard reachable. Resolving to a plausible-but-absent path instead
    # would restore the silent failure this section exists to prevent.
    got=$(resolve "$blk" "$FOREIGN" "$TMPD/no-such-city")
    if [ -z "$got" ]; then
        ok "block $blk: no writer anywhere resolves EMPTY (the guard can fire)"
    else
        bad "block $blk: no writer anywhere resolves EMPTY (the guard can fire)" \
            "resolved '$got' — an unexecutable path passes the guard and fails at the stamp instead"
    fi
    blk=$((blk + 1))
done

# The middle candidate is a real arm, not decoration: prove it fires when
# the session IS inside a pack checkout and neither env var helps.
GITPACK="$TMPD/gitpack"
mkdir -p "$GITPACK/assets/scripts"
printf '#!/bin/sh\necho STUB-HELM "$@"\n' >"$GITPACK/assets/scripts/gc-helm.sh"
chmod +x "$GITPACK/assets/scripts/gc-helm.sh"
if git -C "$GITPACK" init -q >/dev/null 2>&1; then
    extract_resolver 1 >"$TMPD/probe-git.sh"
    printf 'printf "RESOLVED=%%s\\n" "$HELM"\n' >>"$TMPD/probe-git.sh"
    got=$(cd "$GITPACK" && GC_RIG_ROOT="$FOREIGN" GC_CITY_PATH="$TMPD/no-such-city" \
        bash "$TMPD/probe-git.sh" 2>/dev/null | sed -n 's/^RESOLVED=//p' | tail -1)
    if [ "$got" = "$GITPACK/assets/scripts/gc-helm.sh" ]; then
        ok "the git-toplevel candidate resolves a pack checkout when the env vars do not"
    else
        bad "the git-toplevel candidate resolves a pack checkout when the env vars do not" \
            "resolved '$got'"
    fi
else
    ok "git-toplevel candidate case skipped (git init unavailable)"
fi

# A search that finds nothing must SAY so. Silence here reproduces the
# original bug one level down: the stamp is skipped and the sitting
# reports nothing wrong.
n_guard=$(grep -c 'NO TAKEAWAY WRITER' "$PROMPT")
if [ "$n_guard" -eq "$n_blocks" ] && [ "$n_guard" -gt 0 ]; then
    ok "every resolver block fails LOUD when no writer is found ($n_guard/$n_blocks)"
else
    bad "every resolver block fails LOUD when no writer is found" \
        "$n_guard guard(s) for $n_blocks block(s) — an unguarded block stamps nothing and says nothing"
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

# The Hold definition is page one, and a definition outranks a rule
# further down: from "a hold has no timeout" the role reasons straight
# to "my held sitting cannot be reaped" — the belief that produced the
# bug. Correcting the reap rule alone leaves the root cause live in the
# active role definition, which is where the session reads it first.
lacks "no 'a hold has no timeout' claim in the definition" \
    'A hold has no timeout' "$PROMPT" \
    "false on the runtime: idle_timeout + the assigned-work defer cap do end a held sitting"
HOLD_DEF="$(awk '/^- \*\*Hold\*\*/ {f=1} f && /^$/ {exit} f {print}' "$PROMPT")"
if printf '%s\n' "$HOLD_DEF" | grep -q 'reap'; then
    ok "the Hold definition carries the reap contract"
else
    bad "the Hold definition carries the reap contract" \
        "the definition itself must say a hold is reapable, not only the rule further down"
fi
if printf '%s\n' "$HOLD_DEF" | grep -q 'mandatory'; then
    ok "the Hold definition makes the hold-time stamp mandatory"
else
    bad "the Hold definition makes the hold-time stamp mandatory" \
        "a reapable hold makes the step-4 takeaway required, not advisory"
fi

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
