#!/usr/bin/env bash
# converse-signoff.test.sh — regression test for the converse role's
# thread-ending contract (bugs tk-bzm86 and tk-mndjz; precedent:
# gate-visit.test.sh).
#
# Two operator complaints, opposite in sign, and the contract has to hold
# both at once — which is why they are guarded in one file. tk-bzm86: a
# sitting ended and said nothing, so the operator was left reading a
# thread that had already gone. tk-mndjz: a visit that needed no operator
# at all held a sitting anyway, so the operator was asked to decide about
# a state they already knew and accepted. The first bug's fix — "never end
# without a sign-off" — is the second bug's cause if it is read as "every
# claimed visit ends out loud". The boundary between them is whether a
# framing was ever POSTED, and the assertions below pin both sides of it.
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
# bad <label> [detail] — the detail is OPTIONAL. Under `set -u` a one-argument
# call used to abort the whole run on `$2`, so the first such failure truncated
# the suite and every assertion after it went unreported — a silent pass.
bad() {
    FAIL=$((FAIL + 1))
    if [ -n "${2:-}" ]; then
        printf '  FAIL  %s\n        %s\n' "$1" "$2"
    else
        printf '  FAIL  %s\n' "$1"
    fi
}
# have <label> <literal> <file> — fixed-string presence
have() {
    if grep -qF -- "$2" "$3"; then ok "$1"; else bad "$1" "missing: $2"; fi
}
# lacks <label> <literal> <file> <why>
lacks() {
    if grep -qF -- "$2" "$3"; then bad "$1" "$4"; else ok "$1"; fi
}
# eq <got> <want> <label>
eq() {
    if [ "$1" = "$2" ]; then ok "$3"; else bad "$3" "got '$1' want '$2'"; fi
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
# The stamp targets $ITEM — the bead this sitting is about — which is the
# subject itself whenever the visit names no other target. Stamping the
# shared continuation group instead lets siblings of a standing scope
# overwrite each other's headline, and hides the hold from the readers
# that look at the item (converse-fold-scope.test.sh owns that contract).
have "hold stamps via the helm takeaway writer" 'takeaway "$ITEM"' "$PROMPT"
have "hold stamp is attributed --by converse" '--by converse' "$PROMPT"
have "hold stamp carries the holding- prefix" '"holding — ' "$PROMPT"
# Each takeaway block runs in its own shell, so every one of them must
# resolve HELM itself. A block that inherits the variable from an earlier
# step resolves to the empty string and the stamp never lands — silently,
# at exactly the moment the trace is the only thing that would survive.
n_takeaway=$(grep -c 'takeaway "\$ITEM"' "$PROMPT")
n_helm=$(grep -c '^ *HELM=' "$PROMPT")
if [ "$n_takeaway" -ge 2 ] && [ "$n_helm" -eq "$n_takeaway" ]; then
    ok "every takeaway block resolves HELM itself ($n_helm/$n_takeaway)"
else
    bad "every takeaway block resolves HELM itself" \
        "$n_takeaway takeaway call(s), $n_helm HELM resolution(s) — a block relying on an earlier step's shell var stamps nothing"
fi
# $ITEM is a shell variable like any other: a takeaway block that does not
# resolve it itself stamps the empty string and the write fails outright.
n_item=$(grep -c '^ *ITEM="\${ITEM:-\$SUBJECT}"' "$PROMPT")
if [ "$n_takeaway" -ge 2 ] && [ "$n_item" -ge "$n_takeaway" ]; then
    ok "every takeaway block resolves ITEM itself ($n_item/$n_takeaway, fold-check included)"
else
    bad "every takeaway block resolves ITEM itself" \
        "$n_takeaway takeaway call(s), $n_item ITEM resolution(s) — a block relying on step 1's shell var stamps nothing"
fi
# The stamp must be a plain takeaway: --release clears assignee and route
# and marks a proactive reaction, which would park a subject the operator
# is actively in conversation about.
if grep -n 'takeaway "\$ITEM"' "$PROMPT" | grep -q -- '--release'; then
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

echo "── a visit whose premise died closes SILENTLY (tk-mndjz) ──"
# The instance: a stalled-workflow visit was filed at 02:49, its premise
# ("no triage.hold and no gc.takeaway on the root") was dispositioned two
# hours later by a sibling visit that named the wait, and a session
# claimed the stale visit ~1.5 days after that. It rebuilt state, SAW the
# hold in force, SAW the underlying condition was a benign open PR
# awaiting the operator's own review — and held a sitting regardless,
# because the loop had exactly one output shape. Both halves are
# load-bearing: without the re-check the role never asks whether the
# premise survived, and without a silent exit a correct diagnosis still
# costs the operator a decision.
have "the loop re-checks the visit's own premise" 'Re-check the premise' "$PROMPT"
have "the silent exit names both readings" 'gc.outcome=<moot|benign>' "$PROMPT"
have "the silent exit posts nothing to the thread" 'Post nothing' "$PROMPT"
have "the canonical benign case is named" 'awaiting the operator' "$PROMPT"
have "the bug is cited where the rule lives (tk-mndjz)" 'tk-mndjz' "$PROMPT"
# A silent exit that fires on a hunch swallows real signals, which is a
# worse bug than the one it fixes. The gate is a NAMED state, not a quiet
# one, and it is the first sentence a "streamline this step" edit drops.
have "uncertainty does not qualify as benign" 'Uncertain is not benign' "$PROMPT"

# Order matters twice over: the premise is re-tested before the prep
# (otherwise the role has already spent the context it was avoiding) and
# before the rename (a visit closing silently must not have moved the
# operator's session title either — that is thread output by another
# route).
ln_recheck=$(grep -n 'Re-check the premise' "$PROMPT" | head -1 | cut -d: -f1)
ln_title=$(grep -n '\*\*Title\.\*\*' "$PROMPT" | head -1 | cut -d: -f1)
ln_prime=$(grep -n '\*\*Prime\.\*\*' "$PROMPT" | head -1 | cut -d: -f1)
if [ -n "$ln_recheck" ] && [ -n "$ln_title" ] && [ -n "$ln_prime" ] &&
    [ "$ln_recheck" -lt "$ln_title" ] && [ "$ln_recheck" -lt "$ln_prime" ]; then
    ok "the re-check runs before the rename and before the prep"
else
    bad "the re-check runs before the rename and before the prep" \
        "re-check@${ln_recheck:-none} title@${ln_title:-none} prime@${ln_prime:-none} — a premise tested after the prep saves nothing"
fi

# The silent close is extracted rather than grepped line by line, because
# what matters is what the block does NOT contain.
silent_block=$(awk '
    /^[[:space:]]*```/ {
        if (infence) { if (hit) { printf "%s", buf; exit } infence = 0 }
        else { infence = 1; buf = ""; hit = 0 }
        next
    }
    !infence { next }
    { buf = buf $0 "\n"; if (index($0, "gc.outcome=<moot|benign>") > 0) hit = 1 }
' "$PROMPT")
if [ -z "$silent_block" ]; then
    bad "the silent close is a runnable block" \
        "no fenced block performs the moot/benign close — prose alone leaves the role to improvise the writes"
else
    ok "the silent close is a runnable block"
    if printf '%s' "$silent_block" | grep -qF -- '--append-notes'; then
        ok "the silent close records the finding on the subject"
    else
        bad "the silent close records the finding on the subject" \
            "the append-note is the ENTIRE durable record of a silently closed visit; without it the visit leaves no trace at all"
    fi
    # THE ASYMMETRY, and the assertion most likely to be "fixed": steps 5
    # and 7 both stamp a takeaway, so a tidying edit reaches for symmetry
    # here. It must not. A takeaway is the subject's headline of what it
    # NEEDS — it is what the board renders and what the stall detector
    # reads as a named wait. Stamping one for a visit that needs nobody
    # re-surfaces the very thing this exit suppresses, one surface out.
    if printf '%s' "$silent_block" | grep -q 'takeaway'; then
        bad "the silent close stamps NO takeaway" \
            "a takeaway is the subject's NEEDS headline; a visit that needs no human must not leave one"
    else
        ok "the silent close stamps NO takeaway"
    fi
    if printf '%s' "$silent_block" | grep -qF -- "jq -e '.[0].metadata[\"gc.outcome\"] // empty'"; then
        ok "the silent close verifies its outcome stamp before closing"
    else
        bad "the silent close verifies its outcome stamp before closing" \
            "an unstamped closed visit is invisible to everything that reads outcomes — silence is not an excuse to skip the read-back"
    fi
    if printf '%s' "$silent_block" | grep -qF -- 'gc bd close "$VISIT"'; then
        ok "the silent close closes only the visit"
    else
        bad "the silent close closes only the visit" \
            "the subject never closes this way"
    fi
fi

# Page one outranks a rule further down — the same reasoning the Hold
# definition case below rests on. A role that reads the opening summary as
# the loop's whole shape reasons straight back to "every visit I claim
# becomes a sitting", which is the bug.
INTRO="$(sed -n '1,/^Definitions:/p' "$PROMPT")"
if printf '%s\n' "$INTRO" | grep -q 'Not every claimed visit earns a sitting'; then
    ok "the opening says a sitting is earned, not automatic"
else
    bad "the opening says a sitting is earned, not automatic" \
        "the summary must not read as if every claimed visit ends in a hold"
fi
# That paragraph was necessary and not sufficient. The role's FIRST
# sentence still read "You hold visits: bounded sittings", so the model was
# already set — visit == sitting — by the time the earned-sitting rule
# arrived to qualify it, and the two contradicted each other on page one
# (tk-flctq). A definition has to be right where it is first given, which
# means "sitting" naming only the held path from the opening line.
if printf '%s\n' "$INTRO" | grep -q 'filed request'; then
    ok "the opening defines a visit as a request for a sitting"
else
    bad "the opening defines a visit as a request for a sitting" \
        "the first sentence sets the role's model; a visit is the request, and only a held one becomes the sitting"
fi
if printf '%s\n' "$INTRO" | grep -q 'visits: bounded sittings'; then
    bad "the opening no longer equates a visit with a sitting" \
        "'visits: bounded sittings' states the tk-mndjz bug as the role's own definition, ahead of the rule that corrects it"
else
    ok "the opening no longer equates a visit with a sitting"
fi
VISIT_DEF="$(awk '/^- \*\*Visit\*\*/ {f = 1; print; next} f && /^- \*\*/ {exit} f && /^$/ {exit} f {print}' "$PROMPT")"
if printf '%s\n' "$VISIT_DEF" | grep -q 'premise'; then
    ok "the Visit definition names the premise as re-testable"
else
    bad "the Visit definition names the premise as re-testable" \
        "the definition itself must say a visit carries a premise that can die, not only the step further down"
fi

# The two contracts read as contradictions to an editor who meets them
# apart, so the resolution lives where the sign-off rule lives.
have "the sign-off rule is scoped to a HELD sitting" 'owed to a sitting that was' "$PROMPT"

echo "── the loop's step numbering still resolves ──"
# Inserting a step renumbers every step after it AND every cross-reference
# to them ("stamp the takeaway at hold time (step 5)"). A stale pointer
# sends the role to the wrong step, and nothing at runtime notices.
nsteps=0
seq_ok=1
for n in $(grep -o '^[0-9]\{1,\}\. \*\*' "$PROMPT" | tr -cd '0-9\n'); do
    nsteps=$((nsteps + 1))
    [ "$n" = "$nsteps" ] || seq_ok=0
done
if [ "$nsteps" -gt 0 ] && [ "$seq_ok" -eq 1 ]; then
    ok "the loop is numbered 1..$nsteps with no gaps"
else
    bad "the loop is numbered 1..N with no gaps" \
        "$nsteps numbered step(s), contiguous=$seq_ok"
fi
stale_refs=""
for n in $(grep -o 'step [0-9]\{1,\}' "$PROMPT" | tr -cd '0-9\n'); do
    if [ "$n" -lt 1 ] || [ "$n" -gt "$nsteps" ]; then stale_refs="$stale_refs $n"; fi
done
if [ -z "$stale_refs" ]; then
    ok "every 'step N' cross-reference names a step that exists"
else
    bad "every 'step N' cross-reference names a step that exists" \
        "out-of-range reference(s):$stale_refs (the loop has $nsteps steps)"
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
# The config header is the role's definition in its third copy, and it
# opened with the same equation the prompt did. Fixing one copy of a
# definition and leaving its siblings stale is how the corrected model
# stops being the one a reader meets first.
lacks "config header no longer equates a visit with a sitting" \
    'holds visits: bounded sittings' "$ATOML" \
    "the header states visit == sitting, which is the behaviour tk-mndjz removed"

echo "── the verified mechanism is recorded centrally ──"
have "engagement doc has the ending section" 'How a held sitting ends' "$ENGAGE"
have "doc corrects the wisp_ttl misreading" 'wisp_ttl' "$ENGAGE"
have "doc names the tmux activity source" 'window_activity' "$ENGAGE"
have "doc names the defer cap" 'assigned_work_defer_limit' "$ENGAGE"
have "doc records the scrollback erasure" 'ClearScrollback' "$ENGAGE"
have "doc names the unbuilt core seam" 'IsAttached' "$ENGAGE"

# Page one outranks a rule further down here too: the doc opens with the
# pack's vocabulary, and a definition reading "a visit IS a sitting, held
# live, closed when the sitting ends" teaches the tk-mndjz behaviour to
# every reader who never reaches the section that corrects it. The
# vocabulary paragraph — not the doc as a whole — has to carry both
# endings, so it is extracted and checked on its own.
VOCAB="$(awk '/^\*\*Vocabulary\.\*\*/ {f = 1} f {print} f && /^$/ {exit}' "$ENGAGE")"
if printf '%s\n' "$VOCAB" | grep -q 'request for one bounded'; then
    ok "the vocabulary defines a visit as a request, not a sitting"
else
    bad "the vocabulary defines a visit as a request, not a sitting" \
        "the opening definition must not equate a claimed visit with a held sitting — that is the tk-mndjz bug, stated as the model"
fi
if printf '%s\n' "$VOCAB" | grep -q 'never becomes a sitting'; then
    ok "the vocabulary carries the silent ending"
else
    bad "the vocabulary carries the silent ending" \
        "both endings belong in the definition; a reader who stops at page one must already know a visit can close silently"
fi
if printf '%s\n' "$VOCAB" | grep -q 'out loud' &&
    printf '%s\n' "$VOCAB" | grep -q 'sign-off'; then
    ok "the vocabulary keeps the out-loud ending"
else
    bad "the vocabulary keeps the out-loud ending" \
        "correcting tk-mndjz must not drop tk-bzm86's rule: a held sitting still ends out loud, with a sign-off"
fi

# The doc defines a visit TWICE — the vocabulary above, and again in
# "What upstream does not ship", which announces itself as "a definition
# first, because everything below uses it". Fixing the first and leaving
# the second is what happened (tk-flctq): the block still opened "A visit
# is one bounded sitting", then contradicted itself a few lines later with
# the silent close. Both copies are authoritative, so both are pinned, and
# the stale phrase is barred from the whole file — the next definition
# added below these two must not reintroduce it either.
SEAM_DEF="$(awk '/^> \*\*A visit\*\* is/ {f = 1} f && /^>[[:space:]]*$/ {exit} f {print}' "$ENGAGE")"
if [ -z "$SEAM_DEF" ]; then
    bad "the seam section still carries a visit definition to check" \
        "no '> **A visit** is ...' block in $ENGAGE — the extraction is stale, not the doc"
else
    ok "the seam section still carries a visit definition to check"
    if printf '%s\n' "$SEAM_DEF" | grep -q 'request for one bounded'; then
        ok "the seam definition calls a visit a request, not a sitting"
    else
        bad "the seam definition calls a visit a request, not a sitting" \
            "this block is the one the section says everything below uses; it must not open by equating the two"
    fi
    if printf '%s\n' "$SEAM_DEF" | grep -q 'never becomes a sitting'; then
        ok "the seam definition carries the silent ending"
    else
        bad "the seam definition carries the silent ending" \
            "a definition that ends every visit out loud is the tk-mndjz model restated"
    fi
    if printf '%s\n' "$SEAM_DEF" | grep -q 'out loud' &&
        printf '%s\n' "$SEAM_DEF" | grep -q 'sign-off'; then
        ok "the seam definition keeps the out-loud ending"
    else
        bad "the seam definition keeps the out-loud ending" \
            "a held sitting still ends out loud, with a sign-off (tk-bzm86)"
    fi
fi
lacks "no 'is one bounded sitting' definition anywhere in the doc" \
    'is one bounded sitting' "$ENGAGE" \
    "a visit is a request FOR one bounded sitting; the bare equation is the bug written as the model"

echo "── the post-sitting drain is documented, not just the reap ──"
# tk-tufrw: an operator lost an unsubmitted multi-paragraph reply. The
# reap section above was written about a HELD sitting and reads as the
# complete account of how the pane goes; it is not. Once a sitting ENDS
# the session has no wake reason and is drained as `no-wake-reason`
# within about a minute, and that drain kills the pane and its process
# tree outright — nothing reads the composer, and nothing warns.
# Every claim below is load-bearing for a reader deciding whether a
# visible pane is safe to type into, and each one was absent (not wrong)
# before the incident. Absence is exactly what made the window invisible.
# The HEADING, not the phrase: the forward pointer added to the reap
# section quotes the section name, so a bare phrase match passes even
# with the section itself deleted (caught by mutating this file).
have "doc carries the post-sitting ending" '## How a pane dies when no sitting is live' "$ENGAGE"
have "doc names the drain reason" 'no-wake-reason' "$ENGAGE"
# The mechanism, pinned at both ends: the deferred signal the reconciler
# actually sends (metadata, not a keystroke) and the call that actually
# destroys the pane. A reader who trusts a visible pane needs to know
# there is no interruption, no prompt and no read-out first — the pane
# and everything composed in it goes in one step.
have "doc names the deferred drain signal" 'GC_DRAIN_ACK=1' "$ENGAGE"
have "doc names the destructor" 'KillSessionWithProcesses' "$ENGAGE"
have "doc rules out the keystroke" 'no Ctrl-C keystroke injection into the pane' "$ENGAGE"
# Regression guard, not decoration. The first version of this section
# said the drain's first act was `Provider.Interrupt` -> SendKeysRaw C-c
# clearing the composer, and THIS suite pinned that string — so the false
# mechanism was load-bearing in two places at once and a corrected doc
# would have failed the tests. `verifiedInterrupt` is the drain code's
# only interrupt wrapper and has no caller outside its own unit test;
# nothing on this path types into the pane. Keep it that way.
lacks "doc does not revive the keystroke mechanism" 'SendKeysRaw' "$ENGAGE" \
    "the no-wake-reason drain signals through GC_DRAIN_ACK metadata and kills; it sends no keys"
have "doc records the misleading stop wording" 'drain acknowledged by agent' "$ENGAGE"
have "doc points at the upstream filing" 'gc-ze774' "$ENGAGE"
# The operator's ruling is a PROHIBITION, and it is the part most likely
# to be softened by a later edit into "capture it on the way out" — which
# is the option they explicitly overrode. Pin the ruling itself, not a
# paraphrase of it.
have "doc carries the hard-no ruling" 'should be a hard no' "$ENGAGE"
# A live pane is not evidence the system knows anyone is there: the
# session survives on the pool having ANY open visit, so a reader must
# not infer protection from the pane still being up.
have "doc says the pane is held by unrelated demand" 'demand-driven' "$ENGAGE"
# A reader who finds the reap section first must not stop there: without
# a forward pointer the held-sitting account silently doubles as "all the
# ways the pane goes", which is the reading that left this window
# unguarded in the first place.
HELD_SEC="$(awk '/^## How a held sitting ends/ {f=1; next} f && /^## / {exit} f {print}' "$ENGAGE")"
if printf '%s\n' "$HELD_SEC" | grep -qF 'How a pane dies when no sitting is live'; then
    ok "the held-sitting section points at the other ending"
else
    bad "the held-sitting section points at the other ending" \
        "without the pointer, the held-sitting account reads as the complete one"
fi
# Both role-facing copies carry it too. The config is where someone goes
# to tune idle_timeout, and the prompt is what the session reads at wake;
# a correction that lands only in the central doc reaches neither.
have "config names the second, shorter clock" 'no-wake-reason' "$ATOML"
have "prompt names the second, shorter clock" 'no-wake-reason' "$PROMPT"

echo "── the writer the contract depends on still exists ──"
have "gc-helm exposes the takeaway verb" 'cmd_takeaway()' "$HELM"
have "takeaway usage documents the converse caller" 'host|proactive|converse' "$HELM"
# The stamp keys are the contract with the board; renaming one silently
# empties every NEEDS cell.
have "takeaway stamps gc.takeaway" 'gc.takeaway=$text' "$HELM"

# ══════════════════════════════════════════════════════════════════════════════
# THE CLAIM BOUNDARY — a turn is claimed WITHIN a continuation group (tk-msfmu)
# ══════════════════════════════════════════════════════════════════════════════
#
# THE BUG: `agent.toml` names `specs/tk-h9pq5/design-doc.md` as the design
# authority, and it says the role "re-claims within the group and drains when
# the group is dry". The shipped prompt said the opposite — "a claim is
# authoritative even when it names a different subject than your last one" —
# because `gc hook --claim` has no group filter, so the scoped re-claim was not
# expressible with the tool the prompt calls its only source of work. On
# 2026-08-22 an operator mid-conversation about the helm board UI had an
# unrelated merge-skill visit prepped in the same thread.
#
# THE FIX: `assets/scripts/converse-claim.sh` claims, and puts a foreign turn
# BACK in the pool before telling the session to drain. The release is the
# load-bearing half — draining on a turn still assigned to a dying session is
# worse than the bug, because the reconciler's reassign path refuses a held
# visit by design.
#
# These run the REAL script against a stubbed `gc` on PATH: no city, no Dolt.

echo "── the claim boundary is scoped to the continuation group ──"

CLAIMER="$REPO/assets/scripts/converse-claim.sh"
have "the claimer ships" "claim one turn FOR A CONTINUATION GROUP" "$CLAIMER"
[ -x "$CLAIMER" ] && ok "the claimer is executable" || bad "the claimer is executable" "chmod +x $CLAIMER"

# The prompt must not carry the sentence that broadened the contract, and must
# route its claim through the claimer. Prose is where this silently reverts.
# Key on the IMPERATIVE half. The sentence itself is QUOTED in step 1 as the
# thing that was removed, so a literal matching the quote would fire on the
# fix's own prose; "work it the same way" is the directive and appears nowhere
# in that quotation.
lacks "the prompt no longer authorises an out-of-group claim" \
      "work it the same way" "$PROMPT" \
      "the broadened contract is back — this is the directive tk-msfmu removed"
have "the prompt claims through the claimer" 'converse-claim.sh' "$PROMPT"
have "step 8 re-claims within the group" "Continue or drain — WITHIN THIS GROUP" "$PROMPT"
# The wake nudge is read BEFORE step 1, so a nudge naming the raw command
# re-teaches the unscoped claim whatever the prompt says.
#
# Read the nudge VALUE, not the file. agent.toml's own comment block names
# converse-claim.sh (that is where it records why the guard moved to
# mechanism), so a file-wide grep is satisfied by the prose alone: mutating
# the nudge to "Claim with gc hook --claim --json; work the visit." — the
# regression this pair exists to catch — left all assertions green while these
# two read the whole file (tk-mpl1c).
NUDGE_VAL="$TMPD/converse-nudge.txt"
# `tr -d` the newline: sed prints an empty LINE for an empty capture, so
# without it `nudge = ""` writes one byte and reads as non-empty below.
sed -n 's/^nudge = "\(.*\)"$/\1/p' "$ATOML" | tr -d '\n' > "$NUDGE_VAL"
if [ -s "$NUDGE_VAL" ]; then
    ok "agent.toml still carries a non-empty nudge"
else
    bad "agent.toml still carries a non-empty nudge" \
        "a CLI agent needs something typed to start a turn; an empty nudge wakes a session that then does nothing"
fi
have "the wake nudge names the claimer, not the raw claim" 'converse-claim.sh' "$NUDGE_VAL"
lacks "…and does not still tell the session to run the raw claim" \
      'gc hook --claim' "$NUDGE_VAL" \
      "the nudge teaches the unscoped claim the prompt just removed"
# Converse is the ONE role whose pane is a human conversation surface — core
# types this text into it and submits it as if the operator had. Every other
# pane is a machine work-log, so only here does nudge length cost the operator
# anything. It ratcheted 21 -> 40 -> 55 words in 13 days because each incident
# appended a clause and none removed one, and the operator read the result in
# their own thread (tk-82epi -> tk-mpl1c). The standing rule is "put the fix in
# the prompt or a script, not another clause here"; an instruction-dependent
# rule fails silently, so the cap is the enforcement. It sits just above the
# longest peer (proactive, 23 words) and well under the 40 that drew the first
# complaint.
NUDGE_WORDS=$(wc -w < "$NUDGE_VAL" | tr -d ' ')
if [ "$NUDGE_WORDS" -le 25 ]; then
    ok "the wake nudge stays at peer length ($NUDGE_WORDS words)"
else
    bad "the wake nudge stays at peer length ($NUDGE_WORDS words)" \
        "converse's pane is the operator's conversation surface — put the fix in the prompt or a script, not another clause here (tk-mpl1c)"
fi

CTMP="$TMPD/claim"
mkdir -p "$CTMP/bin"
cat > "$CTMP/bin/gc" <<'GCC'
#!/usr/bin/env bash
case "$1 ${2:-}" in
  "hook --claim") cat "$FAKE_CLAIM" ;;
  "bd update")    printf '%s\n' "$*" >> "$FAKE_UPDATES" ;;
  # A per-bead fixture wins when one exists, so a case can hold ONE turn of a
  # vacuumed set back while the rest release. Otherwise the shared file answers
  # for every bead, which is what the single-turn cases below rely on.
  "bd show")      if [ -n "${FAKE_SHOW_DIR:-}" ] && [ -f "$FAKE_SHOW_DIR/${3:-}.json" ]; then
                      cat "$FAKE_SHOW_DIR/${3:-}.json"
                  else
                      cat "$FAKE_SHOW"
                  fi ;;
esac
exit 0
GCC
chmod +x "$CTMP/bin/gc"

# run_claim <claim-json> <current-group> <show-json> [held-id ...]
#   -> CRC / COUT / CUPD
# Any id listed after the show fixture reads back as STILL HELD, so a case can
# hold one turn of a vacuumed set back and prove the verdict is gated on the
# whole set rather than on the turn the claim happened to name.
run_claim() {
    printf '%s' "$1" > "$CTMP/claim.json"
    printf '%s' "$3" > "$CTMP/show.json"
    rm -rf "$CTMP/show.d"
    mkdir -p "$CTMP/show.d"
    _rc_group="$2"
    shift 3
    for _rc_held in "$@"; do
        printf '[{"id":"%s","status":"in_progress","assignee":"converse-1"}]' \
            "$_rc_held" > "$CTMP/show.d/$_rc_held.json"
    done
    : > "$CTMP/updates"
    CRC=0
    COUT=$(env PATH="$CTMP/bin:$PATH" FAKE_CLAIM="$CTMP/claim.json" \
               FAKE_UPDATES="$CTMP/updates" FAKE_SHOW="$CTMP/show.json" \
               FAKE_SHOW_DIR="$CTMP/show.d" \
               sh "$CLAIMER" "$_rc_group" 2>"$CTMP/err") || CRC=$?
    CUPD=$(cat "$CTMP/updates")
}

RELEASED='[{"id":"tk-foreign","status":"open","assignee":null}]'
HELD='[{"id":"tk-foreign","status":"in_progress","assignee":"converse-1"}]'

# --- (NOWORK) an empty claim drains, and writes nothing ----------------------
run_claim '{"ok":true}' "tk-subj" "$RELEASED"
eq "$COUT" "action=drain reason=no-work" "(NOWORK) an empty claim drains"
eq "$CRC"  "1"                           "(NOWORK) …and exits 1 so a caller can branch on status"
eq "${CUPD:-<none>}" "<none>"            "(NOWORK) …touching no bead"

# --- (FIRST) the session's first claim has no group to scope to --------------
run_claim '{"bead_id":"tk-a","continuation_group":"tk-subj"}' "" "$RELEASED"
eq "$COUT" "action=work bead=tk-a group=tk-subj" "(FIRST) the first claim of a session is always workable"
eq "$CRC"  "0"                                    "(FIRST) …exit 0"
eq "${CUPD:-<none>}" "<none>"                     "(FIRST) …and is never released"

# --- (SAME) the group this thread is already about ---------------------------
run_claim '{"bead_id":"tk-b","continuation_group":"tk-subj"}' "tk-subj" "$RELEASED"
eq "$COUT" "action=work bead=tk-b group=tk-subj" "(SAME) a turn in the current group is worked"
eq "${CUPD:-<none>}" "<none>"                     "(SAME) …with no release writes"

# --- (NOGROUP) a claim that names no group cannot be proven foreign ----------
run_claim '{"bead_id":"tk-c"}' "tk-subj" "$RELEASED"
eq "$COUT" "action=work bead=tk-c group=" "(NOGROUP) an ungrouped turn is worked, not released on a guess"
eq "${CUPD:-<none>}" "<none>"             "(NOGROUP) …and nothing is written"

# --- (FOREIGN) the defect itself --------------------------------------------
run_claim '{"bead_id":"tk-foreign","continuation_group":"tk-other"}' "tk-subj" "$RELEASED"
eq "$COUT" "action=drain reason=out-of-group bead=tk-foreign group=tk-other" \
   "(FOREIGN) a turn on another subject is NOT worked in this thread"
eq "$CRC"  "1" "(FOREIGN) …and the session is told to drain"
grep -q -- '--status=open' <<< "$CUPD" \
  && ok "(FOREIGN) the turn is reopened" || bad "(FOREIGN) never reopened: $CUPD"
grep -q -- '--assignee=' <<< "$CUPD" \
  && ok "(FOREIGN) …and unassigned, so the pool can offer it again" \
  || bad "(FOREIGN) the assignee was never cleared: $CUPD"

# (SPLIT) bd's claim guard refuses --assignee "" on an in_progress bead and
# rolls the WHOLE update back, so batching the clears loses the ones that
# needed no claim (tk-z27pw). One call doing both is the shape that fails.
if grep -qE -- '--status=open.*--assignee=|--assignee=.*--status=open' <<< "$CUPD"; then
    bad "(SPLIT) the release is split into separate writes" \
        "status and assignee ride one update — the claim guard rolls both back"
else
    ok "(SPLIT) the release is split into separate writes"
fi

# (ORDER) the session pointers must be gone BEFORE the bead becomes offerable,
# or the pool offers a turn that still names a dead session.
sess_ln=$(grep -n -- '--unset-metadata gc.session_id' <<< "$CUPD" | head -1 | cut -d: -f1)
asg_ln=$(grep -n -- '--assignee=' <<< "$CUPD" | head -1 | cut -d: -f1)
if [ -n "$sess_ln" ] && [ -n "$asg_ln" ] && [ "$sess_ln" -lt "$asg_ln" ]; then
    ok "(ORDER) the session pointers are cleared before the turn is offerable"
else
    bad "(ORDER) the session pointers are cleared before the turn is offerable" \
        "unset=${sess_ln:-none} assignee=${asg_ln:-none} in: $CUPD"
fi

# (NOROUTE) gc.routed_to is the pool's offer predicate. Clearing it would PARK
# the turn instead of returning it — the same failure by another route.
if grep -q -- 'gc.routed_to' <<< "$CUPD"; then
    bad "(NOROUTE) the release leaves gc.routed_to alone" \
        "the route was cleared — a parked turn is not a returned one: $CUPD"
else
    ok "(NOROUTE) the release leaves gc.routed_to alone"
fi

# --- (FAILSAFE) never drain on a turn still held -----------------------------
# The read is trusted over the writes: every update can exit 0 and the bead
# still be held. Stranding it is the hazard that made a prompt-only fix
# unshippable, so an unreleasable turn is WORKED instead.
run_claim '{"bead_id":"tk-foreign","continuation_group":"tk-other"}' "tk-subj" "$HELD"
eq "$COUT" "action=work bead=tk-foreign group=tk-other reason=unreleasable" \
   "(FAILSAFE) a turn that could not be released is worked, never stranded"
eq "$CRC" "0" "(FAILSAFE) …and the session does not drain onto a held bead"
grep -q 'could not release' "$CTMP/err" \
  && ok "(FAILSAFE) …and the failure is reported, not swallowed" \
  || bad "(FAILSAFE) the failed release was silent: $(cat "$CTMP/err")"

# --- (VACUUM) one claim can assign MORE turns than the one it names ---------
# `gc hook --claim` preassigns the claimed bead's continuation-group siblings
# onto the SAME session in the SAME call — `preassignHookContinuationGroup` in
# cmd/gc/cmd_hook_claim.go — and reports them back as `continuation_assigned`.
# Releasing only `.bead_id` drained with every vacuumed sibling still
# in_progress on a dying session: the exact strand this script exists to
# prevent, reached through the door next to the one it was watching. The
# siblings are in the claimed turn's group by construction (the preassign
# filters on it), so when the named turn is foreign they all are.
run_claim '{"bead_id":"tk-foreign","continuation_group":"tk-other","continuation_assigned":["tk-sib1","tk-sib2"]}' \
          "tk-subj" "$RELEASED"
eq "$COUT" "action=drain reason=out-of-group bead=tk-foreign group=tk-other" \
   "(VACUUM) the named turn still decides the verdict"
eq "$CRC" "1" "(VACUUM) …and the session is told to drain"
for vb in tk-foreign tk-sib1 tk-sib2; do
    if grep -q -- "update $vb --unset-metadata gc.session_id" <<< "$CUPD" \
       && grep -q -- "update $vb --status=open" <<< "$CUPD" \
       && grep -q -- "update $vb --assignee=" <<< "$CUPD"; then
        ok "(VACUUM) $vb is put back before the drain"
    else
        bad "(VACUUM) $vb is put back before the drain" "not fully released in: $CUPD"
    fi
done

# (VACUUM-ORDER) the ordered writes are PER TURN, not just for the first one:
# a sibling made offerable while it still names a dead session is the same
# failure the (ORDER) case pins for the named turn.
v_sess=$(grep -n -- 'update tk-sib2 --unset-metadata gc.session_id' <<< "$CUPD" | head -1 | cut -d: -f1)
v_asg=$(grep -n -- 'update tk-sib2 --assignee=' <<< "$CUPD" | head -1 | cut -d: -f1)
if [ -n "$v_sess" ] && [ -n "$v_asg" ] && [ "$v_sess" -lt "$v_asg" ]; then
    ok "(VACUUM-ORDER) a sibling's session pointers are cleared before it is offerable"
else
    bad "(VACUUM-ORDER) a sibling's session pointers are cleared before it is offerable" \
        "unset=${v_sess:-none} assignee=${v_asg:-none} in: $CUPD"
fi

# (VACUUM-SPLIT) the split that the claim guard forces applies to siblings too.
if grep -qE -- 'update tk-sib1 .*(--status=open.*--assignee=|--assignee=.*--status=open)' <<< "$CUPD"; then
    bad "(VACUUM-SPLIT) a sibling's release is split into separate writes" \
        "status and assignee ride one update — the claim guard rolls both back"
else
    ok "(VACUUM-SPLIT) a sibling's release is split into separate writes"
fi

# (VACUUM-NOROUTE) parking a sibling is as bad as parking the named turn.
if grep -q -- 'gc.routed_to' <<< "$CUPD"; then
    bad "(VACUUM-NOROUTE) the sibling release leaves gc.routed_to alone" \
        "the route was cleared — a parked turn is not a returned one: $CUPD"
else
    ok "(VACUUM-NOROUTE) the sibling release leaves gc.routed_to alone"
fi

# --- (VACUUM-FAILSAFE) a sibling that will not go back blocks the drain -----
# The named turn releases cleanly here; only tk-sib1 stays held. Draining on
# that is the strand, so the whole set gates the verdict.
run_claim '{"bead_id":"tk-foreign","continuation_group":"tk-other","continuation_assigned":["tk-sib1"]}' \
          "tk-subj" "$RELEASED" tk-sib1
eq "$CRC" "0" "(VACUUM-FAILSAFE) …and the session does not drain onto it"
grep -q 'could not release .*tk-sib1' "$CTMP/err" \
  && ok "(VACUUM-FAILSAFE) …and the held sibling is named in the report" \
  || bad "(VACUUM-FAILSAFE) …and the held sibling is named in the report" \
         "tk-sib1 missing from: $(cat "$CTMP/err")"

# (VACUUM-HELD-NAMED) the turn the caller is sent to work must be one this
# session still HOLDS. This is the exact split the fixture above builds and the
# reason it exists: tk-foreign reads back open/unassigned (it released), tk-sib1
# reads back in_progress/assigned (it did not). Naming tk-foreign here hands the
# sitting a bead this script has just returned to the pool — another session can
# claim it concurrently — while tk-sib1 stays assigned to this session and
# unworked. Both halves of that split are asserted first, so a fixture that
# stopped producing it could never leave the verdict assertion vacuously green.
# read_back <id> -> "<status>|<assignee>", through the SAME stub lookup the
# script's own read-back uses, so these assert what the script saw and not just
# what the fixture files contain.
read_back() {
    env PATH="$CTMP/bin:$PATH" FAKE_SHOW="$CTMP/show.json" \
        FAKE_SHOW_DIR="$CTMP/show.d" gc bd show "$1" --json \
        | sed -e 's/.*"status":"\([^"]*\)".*"assignee":\("\([^"]*\)"\|null\).*/\1|\3/'
}
eq "$(read_back tk-foreign)" "open|" \
   "(VACUUM-HELD-NAMED) fixture: the named turn did read back released"
eq "$(read_back tk-sib1)" "in_progress|converse-1" \
   "(VACUUM-HELD-NAMED) fixture: the sibling did read back still held"
eq "$COUT" "action=work bead=tk-sib1 group=tk-other reason=unreleasable" \
   "(VACUUM-HELD-NAMED) the held sibling is worked, not the turn already put back"

# (VACUUM-HELD-FIRST) when the NAMED turn is among the stuck ones it wins, so
# the single-turn (FAILSAFE) contract is unchanged by the rule above. Both are
# held here; the claimed turn is released first, so it is the first failure.
run_claim '{"bead_id":"tk-foreign","continuation_group":"tk-other","continuation_assigned":["tk-sib1"]}' \
          "tk-subj" "$RELEASED" tk-foreign tk-sib1
eq "$COUT" "action=work bead=tk-foreign group=tk-other reason=unreleasable" \
   "(VACUUM-HELD-FIRST) a stuck claimed turn still outranks a stuck sibling"
grep -q 'could not release .*tk-foreign.*tk-sib1' "$CTMP/err" \
  && ok "(VACUUM-HELD-FIRST) …and both stuck turns are reported" \
  || bad "(VACUUM-HELD-FIRST) …and both stuck turns are reported" \
         "expected both ids in: $(cat "$CTMP/err")"

# (VACUUM-HELD-LATER) the named turn and the FIRST sibling both go back; only
# the second sibling sticks. Guards the off-by-one shape of "first failure":
# a fix that reported the last-processed id, or the first id of the set, or the
# first SIBLING regardless of outcome, all pass the case above and fail here.
run_claim '{"bead_id":"tk-foreign","continuation_group":"tk-other","continuation_assigned":["tk-sib1","tk-sib2"]}' \
          "tk-subj" "$RELEASED" tk-sib2
eq "$COUT" "action=work bead=tk-sib2 group=tk-other reason=unreleasable" \
   "(VACUUM-HELD-LATER) the one stuck turn is named even when it is last"
eq "$CRC" "0" "(VACUUM-HELD-LATER) …and the session does not drain onto it"

# --- (VACUUM-ABSENT) an older gc names no siblings — unchanged behaviour ----
# Guards the other direction: the release set must not invent ids when the key
# is missing, or every claim writes to beads that were never assigned.
run_claim '{"bead_id":"tk-foreign","continuation_group":"tk-other"}' "tk-subj" "$RELEASED"
eq "$(grep -c -- '--status=open' <<< "$CUPD")" "1" \
   "(VACUUM-ABSENT) a claim naming no siblings still releases exactly one turn"

echo "── a routed wait is written as an EDGE, not only as prose (tk-2plde) ──"
# The same failure mode as the stamp, one level up. A takeaway is ONE frozen
# string, so a sitting that routes work leaves the subject saying "routed —
# nothing further needed here" long after the work merges, and nothing in the
# city re-reads prose. The board can only re-ask a wait that exists as a
# `blocks` edge. Each assertion below is one way that quietly stops happening:
# the flag can be dropped from the writer, or — far more likely — the
# instruction to PASS it can be tidied out of the prompt, leaving a verb
# nothing calls.
have "gc-helm takeaway accepts --waiting-on" '--waiting-on)' "$HELM"
have "…and writes it as a depends-on edge" 'bd dep add "$bead" "$_w" -t blocks' "$HELM"
have "…and documents it in usage" '--waiting-on <bead-id>' "$HELM"
# The prompt is the half that decides whether the flag is ever passed.
have "the sign-off block can carry the waits" '--by converse $WAITING' "$PROMPT"
have "the routing rule tells converse to wire the wait" '--waiting-on <work-bead>' "$PROMPT"
# The ORDER is the safety property: the stamp is written first, so an edge that
# cannot be wired warns and the conclusion still lands. A writer that exits on a
# failed edge would trade the data loss this fixes for the one it replaces.
if awk '/^cmd_takeaway\(\)/ {f=1} f' "$HELM" | grep -n 'gc.takeaway=$text' | head -1 | cut -d: -f1 | {
       read -r stamp_ln || stamp_ln=0
       edge_ln=$(awk '/^cmd_takeaway\(\)/ {f=1} f' "$HELM" | grep -n 'bd dep add' | head -1 | cut -d: -f1)
       [ -n "$edge_ln" ] && [ "$stamp_ln" -gt 0 ] && [ "$stamp_ln" -lt "$edge_ln" ]
   }; then
    ok "the takeaway is stamped BEFORE any edge is attempted"
else
    bad "the takeaway is stamped BEFORE any edge is attempted" \
        "an edge wired first can fail the verb and cost the sitting its conclusion"
fi
if awk '/^cmd_takeaway\(\)/ {f=1} f' "$HELM" | grep -A3 'could not wire' | grep -qE 'exit [0-9]'; then
    bad "a failed edge does not abort the verb" \
        "the warning arm exits — the takeaway lands but the caller reads a failure"
else
    ok "a failed edge does not abort the verb"
fi

echo
echo "converse-signoff: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
