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
#   2. an unattended kill, which clears the scrollback and, under
#      wake_mode=fresh, respawns a clean session — the thread is
#      unrecoverable, not hidden.
# Nothing pack-owned runs at kill time, so the contract has to hold the
# line in two places, and BOTH are load-bearing:
#   • the durable trace is stamped when the hold BEGINS, not only at
#     close — that is the only thing that survives an interruption; and
#   • a deliberate close ends with a sign-off block naming the outcome
#     and the subject to look at next, so the last line the operator
#     sees is an ending rather than an unanswered question.
#
# Neither ending is a clock. `idle_timeout = "0"` keeps converse off the
# idle ladder, so a held sitting ends when its visit closes. That
# is a config value with no other guard, which is the shape that gets
# tidied back to a plausible-looking "8h", so it is pinned here alongside
# the operator lever that ends a sitting by hand (`gc-helm dismiss`).
#
# Each assertion below is one way the fix silently reverts. A prompt is
# prose: a well-meaning edit that "tidies" the hold step can drop the
# stamp, and nothing downstream notices — the sitting still works, the
# record still lands, and only an interrupted operator ever pays. Hence a
# test rather than a comment.
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
# bad <label> [detail] — the detail is OPTIONAL, which is why `$2` is read
# through `${2:-}`: under `set -u` a bare `$2` aborts the whole run on a
# one-argument call, truncating the suite into a silent pass.
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

# THE ORDER, not the presence (tk-747cl). Closing the visit removes the
# session's last wake reason, and the no-wake-reason drain pinned further down
# takes the pane whole about a minute later without reading anything out of
# it. So a sign-off written AFTER the close is written into a surface that is
# already condemned: on tk-z9nln the substantive answer to the operator's
# question was posted 15 seconds after the visit closed, and they almost
# certainly never saw it. Step 7's heading always said "sign off, then close";
# its procedure did the opposite, and the procedure is the half that runs.
# Line order inside the step IS the contract, so it is asserted, not described.
STEP7="$(awk '/^7\. \*\*/ {f = 1} f && /^8\. \*\*/ {exit} f {print}' "$PROMPT")"
if [ -z "$STEP7" ]; then
    bad "step 7 is still extractable" \
        "no '7. **...' step in $PROMPT — the extraction is stale, not the prompt"
else
    ok "step 7 is still extractable"
    # A close that is missing entirely reports close@none and fails here too:
    # deleting the close is not a way to satisfy an ordering check.
    s7_signoff=$(printf '%s\n' "$STEP7" | grep -nF 'Ended (<one-word-outcome>):' | head -1 | cut -d: -f1)
    s7_close=$(printf '%s\n' "$STEP7" | grep -nF 'gc bd close "$VISIT"' | head -1 | cut -d: -f1)
    if [ -n "$s7_signoff" ] && [ -n "$s7_close" ] && [ "$s7_signoff" -lt "$s7_close" ]; then
        ok "the sign-off is posted BEFORE the visit is closed"
    else
        bad "the sign-off is posted BEFORE the visit is closed" \
            "sign-off@${s7_signoff:-none} close@${s7_close:-none} — a sign-off written after the close lands in a pane the drain is already taking (tk-747cl)"
    fi
fi
# The heading and the procedure disagreed for as long as the bug existed, and
# the heading was the correct half. Pin it: an edit that reverts the procedure
# and leaves this alone reintroduces exactly that contradiction.
have "step 7's heading states the order it performs" \
    'Sign off, then close the visit' "$PROMPT"
lacks "…and the step no longer teaches the inverted order" \
    'then close, then post the sign-off' "$PROMPT" \
    "the lead-in read close-before-sign-off, and the lead-in is the half the role executes (tk-747cl)"
# The reap rule states this same requirement in prose, two hundred lines down,
# and stated it correctly the whole time the procedure contradicted it. It is
# the only place the WHY is written, so a tidying edit must not take it.
have "the rule is stated where the reap is explained" \
    'has to land before you close, not after' "$PROMPT"

echo "── a cut-short sitting signs off too ──"
# The low-context exit is the likeliest ending to skip the sign-off,
# because the whole point of it is that the session is out of room.
if grep -A 4 'Low context mid-hold' "$PROMPT" | grep -q 'sign-off'; then
    ok "low-context exit routes through the sign-off"
else
    bad "low-context exit routes through the sign-off" \
        "cut-short must still end out loud (step 6, not a bare close)"
fi

# ...and a cut-short exit must not cancel the wait it is leaving unresolved
# (tk-7k4862). Step 7 both releases a settled hold and carries the cut-short
# exit, so a release keyed to the item's current state finds "held" on an item
# nobody has ruled on, and drops the declared wait the hold was written to
# record.
signoff_block=$(awk '
    /^[[:space:]]*```/ {
        if (infence) { if (hit) { printf "%s", buf; exit } infence = 0 }
        else { infence = 1; buf = ""; hit = 0 }
        next
    }
    !infence { next }
    { buf = buf $0 "\n"; if (index($0, "gc.outcome=<one-word-outcome>") > 0) hit = 1 }
' "$PROMPT")
if [ -z "$signoff_block" ]; then
    bad "step 7's writes are a runnable block" \
        "no fenced block performs the sign-off writes — prose alone leaves the role to improvise them"
else
    ok "step 7's writes are a runnable block"
    if printf '%s' "$signoff_block" | grep -qF -- '--to unanchored'; then
        ok "step 7 still releases a hold whose ruling landed"
    else
        bad "step 7 still releases a hold whose ruling landed" \
            "without the release an item stays in held after the decision lands, and the state stops meaning waiting"
    fi
    rel_guard=$(printf '%s' "$signoff_block" | grep -F 'state "$ITEM"' | grep -F '"held"' | head -1)
    if [ -z "$rel_guard" ]; then
        bad "the release from held is guarded at all" \
            "no conditional in step 7 reads the item's state before transitioning it"
    elif printf '%s' "$rel_guard" | grep -qF 'RULED'; then
        ok "the release from held is gated on a ruling, not on the state alone"
    else
        bad "the release from held is gated on a ruling, not on the state alone" \
            "guard is [$rel_guard] — a cut-short sitting reaches step 7 on an item still waiting, and a state-only guard releases it (tk-7k4862)"
    fi
    # The gate has to fail CLOSED. An absent or affirmative default releases
    # every hold that passes through step 7, which is the defect itself.
    rel_default=$(printf '%s' "$signoff_block" | grep -E '^[[:space:]]*RULED=' | head -1)
    if printf '%s' "$rel_default" | grep -qE '^[[:space:]]*RULED=no([[:space:]]|$)'; then
        ok "the ruling gate defaults to leaving the hold in place"
    else
        bad "the ruling gate defaults to leaving the hold in place" \
            "default is [${rel_default:-absent}] — a gate that starts open is not a gate"
    fi
fi
# The cut-short bullet is where the still-waiting exit is taught, so the
# continued hold has to be stated there too; the gate above is invisible from
# the rule that sends a sitting through it.
if grep -A 8 'Low context mid-hold' "$PROMPT" | grep -q 'RULED=no'; then
    ok "the low-context exit says the hold stays"
else
    bad "the low-context exit says the hold stays" \
        "the cut-short rule must name the gate it leaves shut, or the release reads as unconditional from there"
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

echo "── how a thread ends is documented where the role can see it ──"
have "prompt carries an ending rule" 'How this thread ends' "$PROMPT"
have "ending rule names the clock it is off" 'idle_timeout' "$PROMPT"
have "ending rule states the thread is unrecoverable" 'wake_mode' "$PROMPT"
# The rule's whole content is WHICH act ends a sitting. A rule that names
# neither the visit closing nor the operator's own lever leaves the role
# believing a clock owns the ending.
have "ending rule names the visit close as the ending" 'ends when its visit closes' "$PROMPT"
have "ending rule names the operator lever" 'gc-helm dismiss' "$PROMPT"

# The Hold definition is page one, and a definition outranks a rule
# further down: from "a hold has no timeout" the role reasons straight
# to "nothing can take this session", and the definition is where the
# session reads it first, so correcting the ending rule alone is not
# enough. The bare claim stays banned with the idle clock off: a health
# restart, a city restart and a crash still end a hold, and the definition
# has to say so or the mandatory stamp below reads as ritual.
lacks "no 'a hold has no timeout' claim in the definition" \
    'A hold has no timeout' "$PROMPT" \
    "no idle clock is not no ending: a restart or a crash still takes a held sitting, with no farewell"
HOLD_DEF="$(awk '/^- \*\*Hold\*\*/ {f=1} f && /^$/ {exit} f {print}' "$PROMPT")"
if printf '%s\n' "$HOLD_DEF" | grep -q 'idle_timeout'; then
    ok "the Hold definition states what does and does not end a hold"
else
    bad "the Hold definition states what does and does not end a hold" \
        "the definition itself must say the clock is off and the visit close is the ending, not only the rule further down"
fi
if printf '%s\n' "$HOLD_DEF" | grep -q 'restart'; then
    ok "the Hold definition still names an ending the role cannot control"
else
    bad "the Hold definition still names an ending the role cannot control" \
        "no clock is not no interruption; drop this and the mandatory stamp below loses its reason"
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

echo "── the idle reap is OFF for this role, and the operator's lever exists ──"
# The layout rule on this surface: an operator reading a held thread must not
# lose it to a clock. Idle is measured from terminal OUTPUT, so a reader
# produces none, and 8h of attention reads as 8h of abandonment. A template
# whose idle_timeout is <= 0 is never registered with the idle tracker, so the
# ladder is never reached. This is a single config VALUE with nothing else
# guarding it: an edit that puts a plausible-looking duration back removes the
# rule and passes every other assertion in this file.
IDLE_VAL="$(sed -n 's/^idle_timeout = "\(.*\)"$/\1/p' "$ATOML" | tr -d '\n')"
case "$IDLE_VAL" in
    0|0s|0m|0h)
        ok "agent.toml keeps the idle reap disabled (idle_timeout=$IDLE_VAL)" ;;
    "")
        bad "agent.toml keeps the idle reap disabled" \
            "no idle_timeout line at all; an absent value disables the reap too, but it takes the explanation with it — keep it explicit" ;;
    *)
        bad "agent.toml keeps the idle reap disabled" \
            "idle_timeout is '$IDLE_VAL'; any positive value re-arms the clock that collects a thread the operator is reading" ;;
esac
have "config explains what ends a sitting instead" 'gc-helm dismiss' "$ATOML"
# With no idle clock and no release valve, a held visit nobody answers holds a
# pool slot with nothing able to reclaim it. The verb IS that valve, so its
# absence is not a missing convenience.
have "gc-helm carries the operator's dismiss verb" 'cmd_dismiss()' "$HELM"
have "dismiss ends the sitting by closing the visit" 'the sitting on $bead ends' "$HELM"
have "dismiss also clears the board row" 'gc.dismissed_at=' "$HELM"
have "the engagement doc records the switch-off" 'off the idle ladder' "$ENGAGE"

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

# --- (EMPTYSTAMP) the stamp is empty; the tracks edge still carries it -------
# tk-tu5g3. `gc hook --claim` reports the gc.continuation_group STAMP, and the
# stamp lands empty on a minority of visits. An empty group turns the
# deliberate (NOGROUP) fallback above from a rare benign case into THE failure
# case, silently disabling this guard for exactly the turn it was written to
# catch: an unrelated visit vacuumed onto a live sitting. A visit records its
# subject twice, and the `tracks` edge has held where the stamp did not
# (su-ab9je).
VISIT_TRACKS='[{"id":"tk-foreign","status":"open","assignee":null,"metadata":{"task_kind":"visit"},"dependencies":[{"id":"tk-other","dependency_type":"tracks"}]}]'

run_claim '{"bead_id":"tk-foreign","continuation_group":""}' "tk-subj" "$VISIT_TRACKS"
eq "$COUT" "action=drain reason=out-of-group bead=tk-foreign group=tk-other" \
   "(EMPTYSTAMP) an empty stamp is recovered from the tracks edge, and the guard fires"
eq "$CRC" "1" "(EMPTYSTAMP) …the session is told to drain"
grep -q -- '--status=open' <<< "$CUPD" \
  && ok "(EMPTYSTAMP) …and the turn goes back to the pool" \
  || bad "(EMPTYSTAMP) the recovered-foreign turn was never released: $CUPD"

# The mirror. Recovery must not release a turn that IS this thread's — without
# it the fix would drain every sitting whose stamp went missing.
run_claim '{"bead_id":"tk-foreign","continuation_group":""}' "tk-other" "$VISIT_TRACKS"
eq "$COUT" "action=work bead=tk-foreign group=tk-other" \
   "(EMPTYSTAMP) a recovered group that MATCHES this thread is worked"
eq "${CUPD:-<none>}" "<none>" "(EMPTYSTAMP) …and nothing is released"

# A visit carrying neither recording is still unprovable, so the pre-existing
# fallback stands: work it rather than release on a guess.
run_claim '{"bead_id":"tk-foreign","continuation_group":""}' "tk-subj" \
    '[{"id":"tk-foreign","status":"open","assignee":null,"metadata":{"task_kind":"visit"}}]'
eq "$COUT" "action=work bead=tk-foreign group=" \
   "(EMPTYSTAMP) a visit with no tracks edge keeps the cannot-prove-foreign fallback"
eq "${CUPD:-<none>}" "<none>" "(EMPTYSTAMP) …and is not released"

# SCOPE. `tracks` is not a visit-only edge — a convoy tracks its members — so
# resolving it for any bead would invent a group for something that never had
# one and release a turn this session was entitled to work.
run_claim '{"bead_id":"tk-foreign","continuation_group":""}' "tk-subj" \
    '[{"id":"tk-foreign","status":"open","assignee":null,"metadata":{},"dependencies":[{"id":"tk-kid","dependency_type":"tracks"}]}]'
eq "$COUT" "action=work bead=tk-foreign group=" \
   "(EMPTYSTAMP) a NON-visit tracks edge invents no group"
eq "${CUPD:-<none>}" "<none>" "(EMPTYSTAMP) …and releases nothing"

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

echo "── a turn already underway is held, not worked and not drained ──"

UNDERWAY='{"bead_id":"tk-held","continuation_group":"tk-subj","reason":"existing_assignment"}'

# --- (HOLD) the sitting this thread is in ------------------------------------
run_claim "$UNDERWAY" "tk-subj" "$RELEASED"
eq "$COUT" "action=hold bead=tk-held group=tk-subj reason=already-underway" \
   "(HOLD) a turn already in_progress under this session is a sitting underway"
eq "$CRC" "3" "(HOLD) …with an exit status distinct from work and from drain"
eq "${CUPD:-<none>}" "<none>" "(HOLD) …and the claimer issues no write of its own"

# --- (HOLD-BARE) the claimer invoked with no group ---------------------------
# An invocation naming no group leaves CURRENT_GROUP empty, so the out-of-group
# guard cannot fire; the hold must not depend on the caller passing its subject.
run_claim "$UNDERWAY" "" "$RELEASED"
eq "$COUT" "action=hold bead=tk-held group=tk-subj reason=already-underway" \
   "(HOLD-BARE) an unscoped nudge invocation still holds"
eq "${CUPD:-<none>}" "<none>" "(HOLD-BARE) …and still writes nothing of its own"

# --- (HOLD-FOREIGN) the hold outranks the out-of-group guard -----------------
run_claim '{"bead_id":"tk-held","continuation_group":"tk-other","reason":"existing_assignment"}' \
          "tk-subj" "$RELEASED"
eq "$COUT" "action=hold bead=tk-held group=tk-other reason=already-underway" \
   "(HOLD-FOREIGN) a sitting underway is not released for being out of group"
eq "${CUPD:-<none>}" "<none>" "(HOLD-FOREIGN) …and the release never runs"

# --- (HOLD-VACUUM) a hold keeps the siblings adoption took, and says so ------
# The claim is not side-effect free on this path: the same result that reports
# existing_assignment can pre-assign open same-group siblings and name them in
# continuation_assigned. They are later turns of the sitting's OWN group, so
# releasing them is the destruction this verdict exists to prevent by a third
# door — but a hold that drops the field silently leaves the caller believing
# it holds one turn when it holds several.
run_claim '{"bead_id":"tk-held","continuation_group":"tk-other","reason":"existing_assignment","continuation_assigned":["tk-sib1","tk-sib2"]}' \
          "tk-subj" "$RELEASED"
eq "$COUT" "action=hold bead=tk-held group=tk-other reason=already-underway adopted=tk-sib1,tk-sib2" \
   "(HOLD-VACUUM) a held sitting names the siblings the claim assigned to it"
eq "${CUPD:-<none>}" "<none>" "(HOLD-VACUUM) …and puts no sibling back"
eq "$CRC" "3" "(HOLD-VACUUM) …and still holds rather than working or draining"

# The caller parses `bead=` and `group=` off this same line, so the added field
# must not move what those resolve to.
eq "$(printf '%s' "$COUT" | sed -n 's/.*bead=\([^ ]*\).*/\1/p')" "tk-held" \
   "(HOLD-VACUUM) …and the caller still parses the held turn off the line"
eq "$(printf '%s' "$COUT" | sed -n 's/.*group=\([^ ]*\).*/\1/p')" "tk-other" \
   "(HOLD-VACUUM) …and its group with it"

# --- (HOLD-VACUUM-ABSENT) no siblings, no field ------------------------------
# The mirror. An empty adopted= would read as a set that arrived and name none
# of it, and visits are filed without gc.root_bead_id, so preassignment returns
# nothing and this is the shape every hold has today.
run_claim '{"bead_id":"tk-held","continuation_group":"tk-subj","reason":"existing_assignment","continuation_assigned":[]}' \
          "tk-subj" "$RELEASED"
eq "$COUT" "action=hold bead=tk-held group=tk-subj reason=already-underway" \
   "(HOLD-VACUUM-ABSENT) an empty sibling set adds no field to the line"

# --- (HOLD-FRESH) the mirror: a turn this claim STARTED is ordinary work -----
# `gc hook --claim` reports a turn it moved to in_progress as `claimed` or
# `ready_assignment`; only a turn that was ALREADY in_progress under this
# identity reports `existing_assignment` (hookClaimExistingAssignment,
# cmd/gc/cmd_hook_claim.go).
for fresh in claimed ready_assignment; do
    run_claim "{\"bead_id\":\"tk-new\",\"continuation_group\":\"tk-subj\",\"reason\":\"$fresh\"}" \
              "tk-subj" "$RELEASED"
    eq "$COUT" "action=work bead=tk-new group=tk-subj" \
       "(HOLD-FRESH) reason=$fresh is fresh work, not a sitting underway"
    eq "$CRC" "0" "(HOLD-FRESH) …and exits 0"
done

run_claim '{"bead_id":"tk-new","continuation_group":"tk-other","reason":"claimed"}' "tk-subj" "$RELEASED"
eq "$COUT" "action=drain reason=out-of-group bead=tk-new group=tk-other" \
   "(HOLD-FRESH) a freshly claimed foreign turn is still released and drained"

# --- the prompt is the half that decides what a hold MEANS -------------------
# The script can state that a sitting is underway; whether this session's
# scrollback still carries the framing is answerable only in the thread, so
# both arms of that choice live in the prompt — as prose, which reverts
# silently unless pinned here.
have "the prompt has a branch for a sitting already underway" 'action=hold' "$PROMPT"
have "…and the claimer-less fallback renders the same verdict" \
     'existing_assignment' "$PROMPT"
have "…and step 8 sends a hold back to step 1 instead of draining on it" \
     "is step 1's case, not this one" "$PROMPT"
# cut-short is a real outcome with one legitimate door; left unqualified it
# reads as the generic way out of any stuck sitting.
have "…and cut-short is confined to the low-context exit" \
     'This is the ONLY path to `cut-short`' "$PROMPT"
# The hold's boundary is the other half of what it means, and it is stated in
# three places that can drift apart. `existing_assignment` skips the claim CAS
# and nothing else: the same result path re-stamps the session identity on the
# visit and can pre-assign open same-group siblings. A "nothing is written"
# reading is the one a later fix would reason from, so each surface is pinned
# to the boundary it actually has.
lacks "the claimer does not promise the hook writes nothing" \
      'changes no state' "$CLAIMER" \
      "existing_assignment skips only the CAS — the result path still stamps identity and can pre-assign siblings"
# Scoped to the hold arm's own comment: `continuation_assigned` is named twice
# more in this script, in the header contract and in the foreign-group release,
# so an unscoped pin passes over a hold comment that has gone quiet about it.
HOLD_NOTE="$(awk '/^# A turn already in_progress under this session/ {f=1}
                  f && /^if \[ "\$REASON" = "existing_assignment" \]/ {exit}
                  f {print}' "$CLAIMER")"
if printf '%s\n' "$HOLD_NOTE" | grep -qF 'continuation_assigned'; then
    ok "…and names the preassignment the hold inherits"
else
    bad "…and names the preassignment the hold inherits" \
        "the hold arm must say the adoption can assign siblings, not only that it claims nothing"
fi
# Scoped to the hold section and matched on the bare key. The doc is
# hard-wrapped, so a multi-word literal breaks the moment a sentence in front
# of it grows; and `gc.root_bead_id` appears again in the routing section
# further down, which would carry an unscoped pin over a deleted boundary.
HOLD_DOC="$(awk '/has that third verdict/ {f=1}
                 f && /^Two constraints follow/ {exit}
                 f {print}' "$ENGAGE")"
if printf '%s\n' "$HOLD_DOC" | grep -qF 'gc.root_bead_id'; then
    ok "the central doc states the same boundary"
else
    bad "the central doc states the same boundary" \
        "the doc must name the key preassignment is gated on, not just that it can happen"
fi
# Same wrapping hazard, opposite polarity, and here it fails OPEN: a banned
# phrase split across two lines would read as absent. Collapse the whitespace
# before looking.
if tr '\n' ' ' < "$ENGAGE" | tr -s ' ' | grep -qF 'nothing written'; then
    bad "…and does not restate the retired side-effect-free claim" \
        "the doc is what a later fix reads as the hook contract"
else
    ok "…and does not restate the retired side-effect-free claim"
fi
# Scoped to the hold prose and collapsed to one line, because the prompt is
# hard-wrapped and a multi-word literal breaks the moment a sentence in front
# of it grows. Both arms are pinned: whether this session's scrollback still
# carries the framing is answerable only in the thread, so the verdict resolves
# to two different acts, and a hold that keeps one and loses the other either
# leaves a reaped sitting with nothing posted or re-opens one the operator is
# already reading.
HOLD_PROSE="$TMPD/hold-prose.txt"
awk '/is a sitting already underway/ {f=1}
     f && /^   Before prepping/ {exit}
     f {print}' "$PROMPT" | tr '\n' ' ' | tr -s ' ' >"$HOLD_PROSE"
have "…and forbids the drain-ack that would take the operator's pane" \
     'Do not `drain-ack`' "$HOLD_PROSE"
have "…and leaves a thread that already carries the sitting alone" \
     'nothing to do' "$HOLD_PROSE"
have "…and sends a scrollback-less respawn back through prep and the re-stamp" \
     're-open it at step 4' "$HOLD_PROSE"

# The nudge is read before step 1, so naming the script alone lands the session
# outside the block where the hold verdict is read, and passes no group, which
# disables the out-of-group guard on every wake.
have "the wake nudge sends the session through the prompt's claim block" \
     "step 1's claim block" "$NUDGE_VAL"
lacks "…and no longer reads as an instruction to run the visit to its close" \
      'work the visit it returns' "$NUDGE_VAL" \
      "this sentence directs a mid-hold session to run the visit to its close"

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
have "the sign-off block can carry the waits" '--by converse "${WAITING[@]}"' "$PROMPT"
have "…and accumulates them in an array" 'WAITING=()' "$PROMPT"
# THE SHELL, not style. The block was written `WAITING=""` … `--by converse
# $WAITING`, unquoted, with a comment saying that was deliberate — an idiom that
# needs word-splitting to become several arguments. This city runs zsh, which
# does not word-split an unquoted parameter: a populated WAITING arrived as ONE
# argument and gc-helm died with `unknown flag '--waiting-on tk-… --waiting-on
# tk-…'`. The empty case splits to nothing in every shell, so the bug was
# invisible on sittings that routed nothing and fired reliably on the ones the
# flag exists for — twice in one day before it was diagnosed (tk-2cy79). It
# reverts by one pair of quotes coming off, so it is pinned from both sides.
lacks "…and never as an unquoted string, which zsh does not split" \
      '--by converse $WAITING' "$PROMPT" \
      "an unquoted parameter is ONE argument under zsh — the flags never reach gc-helm and the wait is lost on exactly the sittings that routed work (tk-2cy79)"
lacks "…nor teaches the broken idiom as deliberate" \
      'Unquoted on purpose' "$PROMPT" \
      "the comment blessed the word-splitting idiom, so the next editor restores it"
have "the routing rule tells converse to wire the wait" '--waiting-on <work-bead>' "$PROMPT"
# The takeaway is read back on the ITEM. The verification the block already
# shipped checks `gc.outcome` on the VISIT, which is a different bead: a sitting
# whose takeaway died still passed it and closed clean — the "unstamped closed
# visit" this same step warns against, one bead over (tk-2cy79, recurrence 2).
have "the takeaway is read back, not just the visit's outcome stamp" \
     'metadata["gc.takeaway"]' "$PROMPT"
# The ORDER is the safety property: the stamp is written first, so an edge that
# cannot be wired warns and the conclusion still lands. A writer that exits on a
# failed edge would trade the data loss this fixes for the one it replaces.
# takeaway_body — cmd_takeaway ALONE. An `awk … f` that never clears its flag
# runs to end-of-file, so every verb defined after cmd_takeaway was read as part
# of it, and these two probes would answer about a sibling's code.
takeaway_body() { sed -n '/^cmd_takeaway()/,/^}/p' "$HELM"; }
if takeaway_body | grep -n 'gc.takeaway=$text' | head -1 | cut -d: -f1 | {
       read -r stamp_ln || stamp_ln=0
       edge_ln=$(takeaway_body | grep -n 'bd dep add' | head -1 | cut -d: -f1)
       [ -n "$edge_ln" ] && [ "$stamp_ln" -gt 0 ] && [ "$stamp_ln" -lt "$edge_ln" ]
   }; then
    ok "the takeaway is stamped BEFORE any edge is attempted"
else
    bad "the takeaway is stamped BEFORE any edge is attempted" \
        "an edge wired first can fail the verb and cost the sitting its conclusion"
fi
if takeaway_body | grep -A3 'could not wire' | grep -qE 'exit [0-9]'; then
    bad "a failed edge does not abort the verb" \
        "the warning arm exits — the takeaway lands but the caller reads a failure"
else
    ok "a failed edge does not abort the verb"
fi

echo "── a wait is a bead and an edge, never a parked subject (tk-0slbb6) ──"
# The takeaway above records a wait for a HUMAN to read. This section is the
# other half: the machine-readable one. A sitting that reaches an open question
# files what the person owes as a bead and blocks the work on it, so the work
# leaves `bd ready` until the demand closes and re-enters it the moment it does.
# Every assertion is one way that reverts to a stamp nobody can act on.
have "gc-helm exposes the demand verb" 'cmd_demand()' "$HELM"
have "…and documents it in usage" 'gc-helm demand <gated-bead>' "$HELM"
demand_body() { sed -n '/^cmd_demand()/,/^}/p' "$HELM"; }

# THE SHAPE. beads refuses a `blocks` edge from a parent to its own descendant,
# so a demand filed UNDER the bead it gates could never gate it — which is why
# prose markers were reached for instead of edges. The demand takes the gated
# bead's own parent; anything else silently rebuilds the dead end.
if demand_body | grep -q -- '--parent "$parent"'; then
    ok "the demand inherits the gated bead's parent (a sibling, not a child)"
else
    bad "the demand inherits the gated bead's parent (a sibling, not a child)" \
        "filed under the gated bead, the demand can never carry a blocks edge to it (tk-2cyxo)"
fi
if demand_body | grep -q -- '--parent "$gated"'; then
    bad "…and never the gated bead itself as parent" \
        "that is the descendant shape beads refuses to let block its ancestor"
else
    ok "…and never the gated bead itself as parent"
fi
have "…reading that parent off the CHILD, where the edge is stored" \
     '"parent-child"' "$HELM"

# FAIL CLOSED, and deliberately unlike takeaway. There the prose is what the
# sitting owes and a rejected edge only warns; here the edge IS the record, and
# a demand without one leaves the work reading ready while a person still owes
# an answer — the exact state this verb removes.
if demand_body | grep -A3 'is NOT blocked by' | grep -qE 'exit [0-9]'; then
    ok "a demand whose edge did not land fails the verb"
else
    bad "a demand whose edge did not land fails the verb" \
        "reporting success on a missing edge leaves the gated work reading ready"
fi
# The verdict comes from the row, never from `dep add`'s exit status, and it is
# read off EVERY bead the call was asked to gate. An --also-blocks target left
# unwired reads ready against a demand named to gate it: the same state, one
# bead over.
if demand_body | grep -qF -- 'w_after=$(gc bd show "$_w"'; then
    ok "…having read the edge back off each bead it was asked to gate"
else
    bad "…having read the edge back off each bead it was asked to gate" \
        "a read-back that checks only the gated bead passes an --also-blocks target that never got its edge"
fi

# The prompt is the half that decides whether the verb is ever called.
# Matched on the CAPTURE, not on the call: step 7 re-states a demand with the
# same three tokens, so a looser pattern passes on a hold that files nothing.
have "the hold files a demand, not only a stamp" 'DEMAND=$("$HELM" demand "$ITEM"' "$PROMPT"
have "…and reads the demand id back off stdout" "awk '/^demand /{print \$2; exit}'" "$PROMPT"
have "the sitting discharges the demand when it settles the question" \
     'gc bd close "$DEMAND"' "$PROMPT"
have "…and re-states it when it does not" '"$HELM" demand "$ITEM" "<what is still owed' "$PROMPT"
have "the prompt states the sibling rule for everything a sitting files" \
     'SIBLING of the subject, never a' "$PROMPT"

# THE POINT OF ALL OF IT. A prose hold is a dispatch only a person can resume:
# it requires someone to come back, read a sentence, and hand-clear a field.
# No agent in this pack may write one. The readers stay — live holds predate
# this and keep working (tk-lb3u4m converts them) — so this pins the WRITE.
holdwriters=""
for f in "$PROMPT" "$REPO"/agents/*/prompt.template.md "$REPO"/formulas/*.toml \
         "$REPO"/assets/scripts/*.sh "$REPO"/template-fragments/*.md; do
    case "$f" in *.test.sh) continue ;; esac
    [ -r "$f" ] || continue
    # A WRITE is an assignment to the key. A read is a lookup, and those stay.
    if grep -qE 'set-metadata "?triage\.hold=|triage\.hold=<' "$f"; then
        holdwriters="$holdwriters ${f#"$REPO"/}"
    fi
done
if [ -z "$holdwriters" ]; then
    ok "no agent, formula, or script in this pack writes a triage.hold"
else
    bad "no agent, formula, or script in this pack writes a triage.hold" \
        "prose hold written by:$holdwriters — a demand bead plus a blocks edge is the disposition now"
fi
have "the sweep's disposition menu offers demand in its place" \
     'demand (gc-helm.sh demand' "$REPO/assets/scripts/liveness-sweep.sh"

echo
echo "converse-signoff: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
