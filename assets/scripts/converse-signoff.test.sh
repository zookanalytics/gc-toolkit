#!/usr/bin/env bash
# converse-signoff.test.sh — regression test for the converse role's
# thread-ending contract (precedent:
# gate-visit.test.sh).
#
# Two operator complaints, opposite in sign, and the contract has to hold
# both at once — which is why they are guarded in one file. One: a
# sitting ended and said nothing, so the operator was left reading a
# thread that had already gone. The other: a visit that needed no operator
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
#   2. an unattended kill. The sittings run wake_mode=resume, so the respawn
#      replays the thread; only a failed resume comes back without it.
# Nothing pack-owned runs at kill time, so the contract has to hold the
# line in two places, and BOTH are load-bearing:
#   • the durable trace is stamped when the hold BEGINS, not only at
#     close — it is the demand gate the board reads and work blocks on,
#     and it is also what a failed resume finds; and
#   • a deliberate close ends with a sign-off — a plain-language wrap-up
#     of what the sitting settled — so the last line the operator sees is
#     an ending rather than an unanswered question.
#
# Neither ending is a clock. `idle_timeout = "0"` on every converse-<model>
# template keeps a sitting off the idle ladder, so a held sitting ends when
# its visit closes. That is a config value with no other guard, which is the
# shape that gets tidied back to a plausible-looking "8h", so it is pinned
# here alongside the operator lever that ends a sitting by hand
# (`gc-helm dismiss`).
#
# Each assertion below is one way the fix silently reverts. A prompt is
# prose: a well-meaning edit that "tidies" the hold step can drop the
# stamp, and nothing downstream notices — the sitting still works, the
# record still lands, and only an interrupted operator ever pays. Hence a
# test rather than a comment.
#
# Hermetic: reads the repo only; no gc, no city, no network.
#
# run-tests-scope: tree

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$HERE/../.."
PROMPT="$REPO/agents/_converse/prompt.template.md"
# A sitting runs from one of the converse-<model> templates. They differ only in
# provider and model, and converse-opus carries the per-field documentation the
# others cite, so the config's prose is read there and its values on every one.
ATOML="$REPO/agents/converse-opus/agent.toml"
SITTINGS=("$REPO"/agents/converse-*/agent.toml)
HELM="$REPO/assets/scripts/gc-helm.sh"
# The pack's conversation model and the Gas City facts it rides are two
# pages: each pin below reads the one that carries the text it guards.
ENGAGE="$REPO/docs/human-engagement.md"
ENGAGE_GC="$REPO/docs/gascity/human-engagement.md"
# Steps 2–7 are carried by on-demand skills; step 1 and the routing table stay
# in the prompt. Each pin below reads the file that carries the text it guards:
# the prompt for step 1, the routing table and the shared Definitions/Rules, and
# the per-step skill for a moved step body.
SK_RECHECK="$REPO/skills/converse-recheck-premise/SKILL.md"  # step 2
SK_PREP="$REPO/skills/converse-prep/SKILL.md"                # steps 3–4
SK_HOLD="$REPO/skills/converse-hold/SKILL.md"                # step 5
SK_SETTLE="$REPO/skills/converse-settle/SKILL.md"            # steps 6–7
SK_CONTINUE="$REPO/skills/converse-continue/SKILL.md"        # must not ship

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

for f in "$PROMPT" "$ATOML" "${SITTINGS[@]}" "$HELM" "$ENGAGE" "$ENGAGE_GC" \
    "$SK_RECHECK" "$SK_PREP" "$SK_HOLD" "$SK_SETTLE"; do
    [ -r "$f" ] || {
        printf 'converse-signoff: cannot read %s\n' "$f" >&2
        exit 1
    }
done

echo "── the hold stamps the takeaway BEFORE waiting (the stamp files the demand) ──"
# The stamp written at hold time IS the demand: it files the gate the board
# reads and dependent work blocks on, so a hold that writes none parks a bead
# nothing re-asks. The same write leaves the gc.hold_demand trace that step 1's
# action=hold arm reads back to tell a real hold from a claim that died before
# step 2. Under wake_mode=resume the thread replays across a restart, so the
# stamp does not rest on surviving a kill; a fresh respawn or a failed resume is
# the one case that comes back without the thread, and there the durable trace
# is what a reader finds instead. The takeaway on the subject, the demand gate and
# the gc.hold_demand read-back ship as converse-hold.sh (run against stubs in
# converse-hold.test.sh, which also pins the stamp to the subject and the writer
# search); here the prompt is pinned to CALL it before it waits.
have "the hold runs converse-hold.sh before it waits" 'converse-hold.sh' "$SK_HOLD"
have "the hold skill keeps the stamp-before-wait invariant" 'Stamp BEFORE you wait' "$SK_HOLD"

echo "── a stand-down ruling states its disposition ──"
# gc-helm.sh takeaway refuses a --release park that names no disposition
# unless an open blocker already holds the anchor, and writes nothing. A
# stand-down ruling ends the wait, so the command the sitting copies carries
# --no-wait.
have "the stand-down example passes --no-wait" \
     'takeaway <anchor> "<ruling>" --release --no-wait' "$SK_HOLD"

# The cross-rig takeaway-writer resolution moved out of the prompt into
# converse-hold.sh and converse-signoff.sh; it runs against stubs in
# converse-hold.test.sh and in this file's discharge section below. A shared
# TMPD is still needed by the sections that follow.
TMPD="$(mktemp -d "${TMPDIR:-/tmp}/gctk-converse-signoff-test.XXXXXX")"
trap 'rm -rf "$TMPD"' EXIT

echo "── the sitting ends out loud (deliberate-close path) ──"
have "the sign-off is a hand-back headed by the subject" '<subject-id> — <short human label>' "$PROMPT"
have "the sign-off's open decision leads with the recommendation" 'lead with the recommendation' "$PROMPT"
lacks "the rote Ended (<outcome>) sign-off tag is gone" 'Ended (<one-word-outcome>):' "$SK_SETTLE" \
    "the sign-off is a plain-language wrap-up, not a fixed two-line tag"
lacks "the rote Look at: <subject-id> pointer is gone" 'Look at: <subject-id>' "$SK_SETTLE" \
    "a converse names another bead only where the substance leads there, as prose"
have "the close goes through the shared guarded close (visit-close.sh), which stamps the outcome and its reason, verifies both, then closes" \
    'visit-close.sh' "$SK_SETTLE"
have "the guarded close names only the visit" '--visit "$VISIT"' "$SK_SETTLE"

# THE ORDER, not the presence. Closing the visit removes the
# session's last wake reason, and the no-wake-reason drain pinned further down
# takes the pane whole about a minute later without reading anything out of
# it. So a sign-off written AFTER the close is written into a surface that is
# already condemned: the substantive answer to the operator's
# question was posted 15 seconds after the visit closed, and they almost
# certainly never saw it. Step 7's heading always said "sign off, then close";
# its procedure did the opposite, and the procedure is the half that runs.
# Line order inside the step IS the contract, so it is asserted, not described.
STEP7="$(awk '/^## 7\./ {f = 1} f {print}' "$SK_SETTLE")"
if [ -z "$STEP7" ]; then
    bad "step 7 is still extractable" \
        "no '## 7.' step in $SK_SETTLE — the extraction is stale, not the skill"
else
    ok "step 7 is still extractable"
    # A close that is missing entirely reports close@none and fails here too:
    # deleting the close is not a way to satisfy an ordering check. The stamp,
    # its readback, and the close are now one act inside visit-close.sh, so the
    # line to order against the sign-off is that call: visit-close.sh stamps
    # gc.outcome (the marker converse-claim.sh reads to finish a stranded visit)
    # immediately before it closes, so the stamp lands after the sign-off
    # whenever the CALL does. A call ahead of the sign-off reopens the original
    # bug — a death between the stamp and the sign-off strands a visit that then
    # finishes silently, dropping the sign-off it still owed — and a
    # sign-off written after the close lands in a pane the drain is already
    # taking.
    s7_signoff=$(printf '%s\n' "$STEP7" | grep -nF '<subject-id> — <short human label>' | head -1 | cut -d: -f1)
    s7_close=$(printf '%s\n' "$STEP7" | grep -nF 'visit-close.sh' | head -1 | cut -d: -f1)
    if [ -n "$s7_signoff" ] && [ -n "$s7_close" ] && [ "$s7_signoff" -lt "$s7_close" ]; then
        ok "the sign-off is posted BEFORE the guarded close stamps and closes"
    else
        bad "the sign-off is posted BEFORE the guarded close stamps and closes" \
            "sign-off@${s7_signoff:-none} close@${s7_close:-none} — a stamp/close ahead of the sign-off drops the sign-off it owed (tk-ayd4c0/tk-747cl)"
    fi
    # The visit's PR reminder is marked closed only AFTER the visit's own close
    # lands, so a death or a failed close between the two never leaves the PR
    # saying "closed" over an open visit still holding the merge. It reads the
    # summary/actions converse-signoff.sh stashed, needing no re-derive.
    s7_prcomment=$(printf '%s\n' "$STEP7" | grep -nF 'pr-visit-comment.sh" close' | head -1 | cut -d: -f1)
    if [ -n "$s7_close" ] && [ -n "$s7_prcomment" ] && [ "$s7_close" -lt "$s7_prcomment" ]; then
        ok "the PR reminder is marked closed after the visit's own close"
    else
        bad "the PR reminder is marked closed after the visit's own close" \
            "close@${s7_close:-none} pr-comment@${s7_prcomment:-none} — a reminder closed before the visit closes lies on the PR"
    fi
fi
# The heading and the procedure disagreed for as long as the bug existed, and
# the heading was the correct half. Pin it: an edit that reverts the procedure
# and leaves this alone reintroduces exactly that contradiction.
have "step 7's heading states the order it performs" \
    'Sign off, then close the visit' "$SK_SETTLE"
lacks "…and the step no longer teaches the inverted order" \
    'then close, then post the sign-off' "$SK_SETTLE" \
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

# The cut-short bullet is where the still-waiting exit is taught, so the
# continued hold has to be stated there too; the gate above is invisible from
# the rule that sends a sitting through it.
if grep -A 8 'Low context mid-hold' "$PROMPT" | grep -q -- '--ruled no'; then
    ok "the low-context exit says the hold stays"
else
    bad "the low-context exit says the hold stays" \
        "the cut-short rule must name the gate it leaves shut (--ruled no), or the release reads as unconditional from there"
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
have "the loop re-checks the visit's own premise" 'Re-check the premise' "$SK_RECHECK"
have "the silent exit names both readings" 'gc.outcome=<moot|benign>' "$SK_RECHECK"
have "the silent exit posts nothing to the thread" 'Post nothing' "$SK_RECHECK"
have "the canonical benign case is named" 'awaiting the operator' "$SK_RECHECK"
# A silent exit that fires on a hunch swallows real signals, which is a
# worse bug than the one it fixes. The gate is a NAMED state, not a quiet
# one, and it is the first sentence a "streamline this step" edit drops.
have "uncertainty does not qualify as benign" 'Uncertain is not benign' "$SK_RECHECK"

# Order matters twice over: the premise is re-tested before the prep (otherwise
# the role has already spent the context it was avoiding) and before the rename
# (a visit closing silently must not have moved the operator's session title —
# that is thread output by another route). Step 2 and steps 3–4 are separate
# skills now, so the order is set by the authoritative routing table (step 2's
# re-check ahead of steps 3–4's prep) and carried by each skill's own imperative.
ln_recheck=$(grep -n 'converse-recheck-premise' "$PROMPT" | head -1 | cut -d: -f1)
ln_prep=$(grep -n 'converse-prep' "$PROMPT" | head -1 | cut -d: -f1)
if [ -n "$ln_recheck" ] && [ -n "$ln_prep" ] && [ "$ln_recheck" -lt "$ln_prep" ]; then
    ok "the re-check runs before the rename and before the prep"
else
    bad "the re-check runs before the rename and before the prep" \
        "routing table: recheck@${ln_recheck:-none} prep@${ln_prep:-none} — step 2 must route ahead of steps 3–4"
fi
have "the re-check skill runs before the prep and the rename" 'before the rename' "$SK_RECHECK"
have "the prep skill waits on the step-2 re-check" 'after step 2' "$SK_PREP"


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
# arrived to qualify it, and the two contradicted each other on page one.
# A definition has to be right where it is first given, which
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
have "the sign-off rule is scoped to a HELD sitting" 'owed to a sitting that was' "$SK_SETTLE"

echo "── the loop's step numbering still resolves ──"
# Inserting a step renumbers every step after it AND every cross-reference to
# them ("stamp the takeaway at hold time (step 5)"). A stale pointer sends the
# role to the wrong step, and nothing at runtime notices. Step 1 is inline
# (`1. **Claim.**`); steps 2–7 are named by the routing table (`**Step N**` /
# `**Steps N–M**`). The steps that EXIST are the union of the two, ranges
# expanded, and a `step N` reference is stale when it points outside that set.
steps_defined="$(
    {
        grep -oE '^[0-9]+\. \*\*' "$PROMPT" | grep -oE '^[0-9]+'
        grep -oE '\*\*Steps? [0-9]+([^0-9*]+[0-9]+)?\*\*' "$PROMPT" \
            | grep -oE '[0-9]+([^0-9*]+[0-9]+)?' \
            | while IFS= read -r r; do
                seq "$(printf '%s' "$r" | grep -oE '^[0-9]+')" \
                    "$(printf '%s' "$r" | grep -oE '[0-9]+$')"
            done
    } | sort -n -u
)"
nsteps="$(printf '%s\n' "$steps_defined" | tail -1)"
seq_ok=1
i=0
for n in $steps_defined; do
    i=$((i + 1))
    [ "$n" = "$i" ] || seq_ok=0
done
if [ -n "$nsteps" ] && [ "$nsteps" -gt 0 ] && [ "$seq_ok" -eq 1 ]; then
    ok "the loop is numbered 1..$nsteps with no gaps"
else
    bad "the loop is numbered 1..N with no gaps" \
        "defined steps: $(printf '%s' "$steps_defined" | tr '\n' ' ')(contiguous=$seq_ok)"
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
have "ending rule names the template's wake_mode" 'wake_mode' "$PROMPT"
# The rule's whole content is WHICH act ends a sitting. A rule that names
# neither the visit closing nor the operator's own lever leaves the role
# believing a clock owns the ending.
have "ending rule names the visit close as the ending" 'ends when its visit closes' "$PROMPT"
have "ending rule names the operator lever" 'gc-helm dismiss' "$PROMPT"

# The Hold definition is page one, and a definition outranks a rule
# further down: it is where the session reads what a hold is first, so
# correcting the ending rule alone is not enough — the reason the stamp is
# mandatory has to be right here too. That reason is the demand: the hold
# files a gate the board reads and dependent work blocks on, and a hold
# that files none parks a bead nothing re-asks. The stamp does not rest on
# whether the session survives a restart; it rests on the demand.
lacks "no 'a hold has no timeout' claim in the definition" \
    'A hold has no timeout' "$PROMPT" \
    "no idle clock is not no ending: a held sitting still ends when its visit closes (sign-off or dismiss)"
HOLD_DEF="$(awk '/^- \*\*Hold\*\*/ {f=1} f && /^$/ {exit} f {print}' "$PROMPT")"
if printf '%s\n' "$HOLD_DEF" | grep -q 'idle_timeout'; then
    ok "the Hold definition states what does and does not end a hold"
else
    bad "the Hold definition states what does and does not end a hold" \
        "the definition itself must say the clock is off and the visit close is the ending, not only the rule further down"
fi
if printf '%s\n' "$HOLD_DEF" | grep -q 'demand'; then
    ok "the Hold definition ties the mandatory stamp to the demand it files"
else
    bad "the Hold definition ties the mandatory stamp to the demand it files" \
        "the stamp is mandatory because the hold IS a demand — the gate the conversation blocks on; that reason, not restart-fear, is what a tidy edit must not drop"
fi
if printf '%s\n' "$HOLD_DEF" | grep -q 'mandatory'; then
    ok "the Hold definition makes the hold-time stamp mandatory"
else
    bad "the Hold definition makes the hold-time stamp mandatory" \
        "the hold's demand gate makes the step-5 takeaway required, not advisory"
fi

echo "── the agent config no longer claims timeouts do not end a sitting ──"
# The original comment asserted "visit boundaries, not timeouts, end it".
# It was false, and it is exactly what stops the next reader from looking.
lacks "no 'visit boundaries, not timeouts' claim" \
    'visit boundaries, not' "$ATOML" \
    "the claim is false: idle_timeout + the assigned-work defer cap do end a held sitting"
have "config points at the verified mechanism" 'docs/human-engagement.md' "$ATOML"
# The config header is the role's definition in its third copy, and it
# opened with the same equation the prompt did. Fixing one copy of a
# definition and leaving its siblings stale is how the corrected model
# stops being the one a reader meets first.
lacks "config header no longer equates a visit with a sitting" \
    'holds visits: bounded sittings' "$ATOML" \
    "the header states visit == sitting, which is the behaviour tk-mndjz removed"

echo "── the idle reap is OFF for every sitting template, and the operator's lever exists ──"
# The layout rule on this surface: an operator reading a held thread must not
# lose it to a clock. Idle is measured from terminal OUTPUT, so a reader
# produces none, and 8h of attention reads as 8h of abandonment. A template
# whose idle_timeout is <= 0 is never registered with the idle tracker, so the
# ladder is never reached. This is a single config VALUE with nothing else
# guarding it: an edit that puts a plausible-looking duration back removes the
# rule and passes every other assertion in this file. The idle tracker reads it
# per template, so every template a sitting can run from is checked.
for SITTING in "${SITTINGS[@]}"; do
    NAME="$(basename "$(dirname "$SITTING")")"
    IDLE_VAL="$(sed -n 's/^idle_timeout = "\(.*\)"$/\1/p' "$SITTING" | tr -d '\n')"
    case "$IDLE_VAL" in
        0|0s|0m|0h)
            ok "$NAME keeps the idle reap disabled (idle_timeout=$IDLE_VAL)" ;;
        "")
            bad "$NAME keeps the idle reap disabled" \
                "no idle_timeout line at all; an absent value disables the reap too, but it leaves nothing for a reader or this test to see — keep it explicit" ;;
        *)
            bad "$NAME keeps the idle reap disabled" \
                "idle_timeout is '$IDLE_VAL'; any positive value re-arms the clock that collects a thread the operator is reading" ;;
    esac
done
have "config explains what ends a sitting instead" 'gc-helm dismiss' "$ATOML"
# With no idle clock and no release valve, a held visit nobody answers keeps its
# session running with nothing able to end it. The verb IS that valve, so its
# absence is not a missing convenience.
have "gc-helm carries the operator's dismiss verb" 'cmd_dismiss()' "$HELM"
have "dismiss ends the sitting by closing the visit" 'the sitting on $bead ends' "$HELM"
have "the engagement doc records the switch-off" 'off the idle ladder' "$ENGAGE"

echo "── no sitting template sets a max session age ──"
# The runtime's max-age ladder defers while a session holds open assigned work,
# and a sitting's visit is assigned to it, so a max age fires on the first tick
# after the visit closes. The ladder has no attachment rung, so that stop takes
# the pane and its scrollback from an attached operator, and converse-reap then
# collects the restarted session. An absent max age is off. It is one config
# line nothing else guards, and a credential refresh reads as a reason to add
# one, so every template a sitting can run from is checked for the line itself.
for SITTING in "${SITTINGS[@]}"; do
    NAME="$(basename "$(dirname "$SITTING")")"
    AGE_LINE="$(grep -E '^[[:space:]]*max_session_age[[:space:]]*=' "$SITTING" | tr '\n' ' ')"
    if [ -z "$AGE_LINE" ]; then
        ok "$NAME sets no max session age"
    else
        bad "$NAME sets no max session age" \
            "found: ${AGE_LINE% }; the restart fires as the visit closes and destroys the pane under an attached operator"
    fi
done

echo "── the verified mechanism is recorded centrally ──"
have "engagement doc has the ending section" 'How a held sitting ends' "$ENGAGE"
have "doc corrects the wisp_ttl misreading" 'wisp_ttl' "$ENGAGE_GC"
have "doc names the tmux activity source" 'window_activity' "$ENGAGE_GC"
have "doc names the defer cap" 'assigned_work_defer_limit' "$ENGAGE_GC"
have "doc records the scrollback erasure" 'ClearScrollback' "$ENGAGE_GC"
have "doc names the unbuilt core seam" 'IsAttached' "$ENGAGE_GC"

# Page one outranks a rule further down here too: the doc opens with the
# pack's vocabulary, and a definition reading "a visit IS a sitting, held
# live, closed when the sitting ends" teaches that equation to
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
# the second is what happened: the block still opened "A visit
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

echo "── the post-sitting ending is documented, not just the held one ──"
# Once a sitting ENDS, its session goes, and the pane with it: the sitting's
# own drain-ack ends it, dismiss stops it, and converse-reap closes one that
# outlives its closed visit, attached or not. The stop kills the pane and its
# process tree outright, so a reply typed and not sent goes with it. Every claim
# below is load-bearing for a reader deciding whether a visible pane is safe to
# type into, so each is pinned inside that section rather than anywhere in the
# doc. The HEADING, not the phrase: the forward pointer in the held-sitting
# section quotes the section name, so a bare phrase match passes even with the
# section itself deleted.
have "doc carries the post-sitting ending" '## How a pane dies when no sitting is live' "$ENGAGE"
POST_SEC="$TMPD/post-sitting-section.txt"
awk '/^## How a pane dies when no sitting is live/ {f=1; next} f && /^## / {exit} f {print}' \
    "$ENGAGE" | tr '\n' ' ' | tr -s ' ' >"$POST_SEC"
# What ends a settled sitting is its own drain-ack, not a runtime clock: the
# awake set keeps a manual session, so the pool's no-wake-reason drain never
# reaches one. The reap is the backstop, and it no longer spares an attached
# session.
have "the section says the sitting ends its own session" 'gc runtime drain-ack' "$POST_SEC"
have "the section says the pool drain does not reach a sitting" 'no-wake-reason' "$POST_SEC"
have "the section names the reap as the backstop" 'converse-reap' "$POST_SEC"
have "the section names the reap's close" 'gc session close' "$POST_SEC"
have "…which closes a session whether or not anyone is attached" 'attached or not' "$POST_SEC"
# The mechanism, pinned at the call that destroys the pane. A reader who
# trusts a visible pane needs to know there is no interruption, no prompt and
# no read-out first — the pane and everything composed in it goes in one step.
have "the section names the destructor" 'KillSessionWithProcesses' "$POST_SEC"
have "the section rules out the keystroke" 'no Ctrl-C keystroke injection into the pane' "$POST_SEC"
have "…and says an unsent reply goes with the pane" 'goes with the pane' "$POST_SEC"
# Regression guard: nothing on this path types into the pane. The stop kills
# the pane's process tree through Provider.Stop and sends no keys.
lacks "doc does not revive the keystroke mechanism" 'SendKeysRaw' "$ENGAGE" \
    "the stop kills the pane's process tree through Provider.Stop; it sends no keys"
# The city's tmux server carries a client per sitting tab beside the main
# connection, so attachment was never a single pane on screen.
lacks "the doc does not claim the city runs one tmux client" 'one tmux client' "$ENGAGE" \
    "the operator keeps a tab per sitting beside the main connection"
# Viewing does not hold a sitting open, a tab exits and prints the last
# hand-back, and the main connection moves on. Nothing copies the pane, so the
# visit's record is what the tab prints. Pin the constraint and the mechanism
# that carries it.
have "doc says viewing holds no sitting open" 'nothing holds a session open because someone is viewing it' "$POST_SEC"
have "…and that nothing copies the pane" 'Nothing copies the pane' "$POST_SEC"
have "…the per-session tmux option that carries it" 'detach-on-destroy' "$POST_SEC"
have "…the client flag the main connection keeps moving on with" '-f no-detach-on-destroy' "$POST_SEC"
have "…and the tab printing the sitting's last hand-back" 'last hand-back the sitting recorded on it' "$POST_SEC"
# A reader who finds the held-sitting section first must not stop there:
# without a forward pointer the held-sitting account silently doubles as "all
# the ways the pane goes", which is the reading that left this window
# unguarded in the first place.
HELD_SEC="$(awk '/^## How a held sitting ends/ {f=1; next} f && /^## / {exit} f {print}' "$ENGAGE")"
if printf '%s\n' "$HELD_SEC" | grep -qF 'How a pane dies when no sitting is live'; then
    ok "the held-sitting section points at the other ending"
else
    bad "the held-sitting section points at the other ending" \
        "without the pointer, the held-sitting account reads as the complete one"
fi
# Both role-facing copies carry it too. converse-opus is where someone goes to
# tune idle_timeout, and the prompt is what the session reads at wake; a
# correction that lands only in the central doc reaches neither.
have "config names the reap that closes a sitting outliving its visit" 'converse-reap' "$ATOML"
have "prompt names the reap that closes a sitting outliving its visit" 'converse-reap' "$PROMPT"

echo "── the writer the contract depends on still exists ──"
have "gc-helm exposes the takeaway verb" 'cmd_takeaway()' "$HELM"
have "takeaway usage documents the converse caller" 'host|proactive|converse' "$HELM"
# The stamp keys are the contract with the board; renaming one silently
# empties every NEEDS cell.
have "takeaway stamps gc.takeaway" 'gc.takeaway=$text' "$HELM"

# ══════════════════════════════════════════════════════════════════════════════
# THE CLAIM — a sitting works the one visit its claim hands it
# ══════════════════════════════════════════════════════════════════════════════
#
# A sitting works one visit and ends its session as soon as that visit closes:
# the sign-off, a fold, a moot or benign close and a finish each end in
# `gc runtime drain-ack`, and nothing claims again. So the claim is never
# scoped to a group, and a turn on another subject is never reached in a thread
# an operator is reading: it belongs to a sitting of its own.
#
# `assets/scripts/converse-claim.sh` claims, and names a turn this session
# already holds (hold) or whose record is complete with only its close missing
# (finish), because `gc hook --claim` reports both as existing_assignment.
#
# These run the REAL script against a stubbed `gc` on PATH: no city, no Dolt.

echo "── the claim is the session's one visit ──"

CLAIMER="$REPO/assets/scripts/converse-claim.sh"
have "the claimer ships" "claim the turn a converse session works" "$CLAIMER"
[ -x "$CLAIMER" ] && ok "the claimer is executable" || bad "the claimer is executable" "chmod +x $CLAIMER"

# The prompt must not carry the sentence that broadened the contract, and must
# route its claim through the claimer. Prose is where this silently reverts.
# Key on the IMPERATIVE half: "work it the same way" is the directive.
lacks "the prompt does not authorise working a claim on another subject" \
      "work it the same way" "$PROMPT" \
      "the broadened contract is back — a sitting works only its own visit"
have "the prompt claims through the claimer" 'converse-claim.sh' "$PROMPT"
# No step re-claims after the close: the step that did is gone, its skill with
# it, and every path that closes the visit drains instead.
[ ! -e "$SK_CONTINUE" ] && ok "no skill re-claims after the visit closes" \
    || bad "no skill re-claims after the visit closes" "$SK_CONTINUE still ships"
lacks "the prompt routes no step to a re-claim" 'converse-continue' "$PROMPT" \
      "the step table still sends a closed sitting to claim again"
lacks "…and sends no path back to step 8" 'step 8' "$PROMPT" \
      "a path that closes the visit must drain, not claim again"
# The wake nudge is read BEFORE step 1, so a nudge naming the raw command
# re-teaches the unscoped claim whatever the prompt says.
#
# Read the nudge VALUE, not the file. agent.toml's own comment block names
# converse-claim.sh (that is where it records why the guard moved to
# mechanism), so a file-wide grep is satisfied by the prose alone: mutating
# the nudge to "Claim with gc hook --claim --json; work the visit." — the
# regression this pair exists to catch — left all assertions green while these
# two read the whole file.
NUDGE_VAL="$TMPD/converse-nudge.txt"
# `tr -d` the newline: sed prints an empty LINE for an empty capture, so
# without it `nudge = ""` writes one byte and reads as non-empty below.
sed -n 's/^nudge = "\(.*\)"$/\1/p' "$ATOML" | tr -d '\n' > "$NUDGE_VAL"
# An absent key and a deliberately empty one are the same value to the engine
# and different to a reader, so the field has to stay written out.
if grep -qE '^nudge = ' "$ATOML"; then
    ok "converse-opus states its nudge explicitly"
else
    bad "converse-opus states its nudge explicitly" \
        "the key is gone; deleting it loses the record of why the field is empty"
fi
# The nudge is read per template, and the sitting templates differ only in
# provider and model, so every one states the same nudge. Everything below reads
# converse-opus's value, so a sibling that drifted from it would go unchecked.
for SITTING in "${SITTINGS[@]}"; do
    [ "$SITTING" -ef "$ATOML" ] && continue
    NAME="$(basename "$(dirname "$SITTING")")"
    if grep -qE '^nudge = ' "$SITTING" &&
        [ "$(sed -n 's/^nudge = "\(.*\)"$/\1/p' "$SITTING" | tr -d '\n')" = "$(cat "$NUDGE_VAL")" ]; then
        ok "$NAME states the same nudge as converse-opus"
    else
        bad "$NAME states the same nudge as converse-opus" \
            "its nudge is missing or differs from converse-opus's, which is the only value the checks below read"
    fi
done
if [ -s "$NUDGE_VAL" ]; then
    have "the wake nudge names the claimer, not the raw claim" 'converse-claim.sh' "$NUDGE_VAL"
    lacks "…and does not still tell the session to run the raw claim" \
          'gc hook --claim' "$NUDGE_VAL" \
          "the nudge teaches the unscoped claim the prompt just removed"
    # Converse is the ONE role whose pane is a human conversation surface — core
    # types this text into it and submits it as if the operator had. Every other
    # pane is a machine work-log, so only here does nudge length cost the operator
    # anything. It ratcheted 21 -> 40 -> 55 words in 13 days because each incident
    # appended a clause and none removed one, and the operator read the result in
    # their own thread. The standing rule is "put the fix in
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
else
    # The field is empty, but empty is not a backstop lever. converse runs as a
    # manual session, never pool_managed, and all three claim backstops gate
    # governs() on pool_managed (gascity idle_nudge.go / execution_backstop.go),
    # so none of them reaches a held sitting whatever this field holds — the
    # manual origin is the exemption, not the empty text. An empty nudge is not a
    # uniform "skip", and it does not uniformly drain either. Only the execution
    # backstop drains on it: the shared empty-content path in gascity
    # nudge_backstop.go runs its exhausted action. The pool-claim backstop
    # substitutes a default claim nudge and re-delivers, and the continuation
    # backstop's exhausted action is a no-op. The config records that split,
    # because a superseded mechanism only ever lived in prose, and prose is where
    # it silently rots.
    have "config names the real backstop gate" 'pool_managed' "$ATOML"
    have "config still names the backstops it is exempt from" 'claim backstops' "$ATOML"
    have "config names the execution backstop as the one that drains on empty" \
         'execution backstop' "$ATOML"
    have "config records that pool-claim substitutes a default nudge, not a drain" \
         'default claim nudge' "$ATOML"
    have "config keeps the claimer constraint for anyone re-arming it" \
         'converse-claim.sh' "$ATOML"
    lacks "config no longer claims a blanket empty-nudge terminal drain" \
          'terminal drain' "$ATOML" \
          "only the execution backstop drains on an empty nudge; the pool-claim backstop substitutes a default claim nudge and the continuation backstop's exhausted is a no-op (verified in gascity nudge_backstop.go / idle_nudge.go)"
    lacks "config no longer records a silenced idle-claim rescue" \
          'idle-claim rescue' "$ATOML" \
          "the rescue is a pool backstop; a manual session never had it, so emptying the field silences nothing (the exemption is pool_managed, verified in gascity)"
    lacks "config no longer asserts the superseded never-empty rule" \
          'must never be empty' "$ATOML" \
          "the field is empty, so the claim that it cannot be is now false in the file that carries it"
fi

CTMP="$TMPD/claim"
mkdir -p "$CTMP/bin"
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$CTMP/bin/gc" <<'GCC'
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
  # A close is recorded and then MOVES the per-bead read-back, because the
  # script trusts the read over the exit status: a stub that closed nothing
  # would leave that gate green on a script that never closed anything either.
  # FAKE_CLOSE_REFUSE arms bd's close-authority guard — `plain` refuses all but
  # --force, `all` refuses both — and refusals are recorded before they fire.
  "bd close")     printf '%s\n' "$*" >> "$FAKE_CLOSES"
                  forced=0
                  for a in "$@"; do [ "$a" = "--force" ] && forced=1; done
                  case "${FAKE_CLOSE_REFUSE:-}" in
                    plain) [ "$forced" = 1 ] || exit 1 ;;
                    all)   exit 1 ;;
                  esac
                  [ -n "${FAKE_SHOW_DIR:-}" ] && \
                    printf '[{"id":"%s","status":"closed","assignee":null}]' "${3:-}" \
                      > "$FAKE_SHOW_DIR/${3:-}.json" ;;
esac
exit 0
GCC
chmod +x "$CTMP/bin/gc"

# run_claim <claim-json> <show-json> -> CRC / COUT / CUPD / CCLOSE
# A trailing group argument is passed to the claimer the way a sitting started
# on an earlier prompt still passes one, and the claimer reads none.
# CLOSE_REFUSE arms the close-authority refusal for ONE run and is cleared
# afterwards, so a refusal case cannot leak into the cases that follow it.
CLOSE_REFUSE=""
run_claim() {
    printf '%s' "$1" > "$CTMP/claim.json"
    printf '%s' "$2" > "$CTMP/show.json"
    rm -rf "$CTMP/show.d"
    mkdir -p "$CTMP/show.d"
    : > "$CTMP/updates"
    : > "$CTMP/closes"
    CRC=0
    # The sitting is converse-1, recorded under its alias as gc hook records a
    # converse claim. No other identity from the shell running this suite
    # reaches it.
    COUT=$(env -u GC_SESSION_ID -u GC_SESSION_NAME -u GC_AGENT GC_ALIAS=converse-1 \
               PATH="$CTMP/bin:$PATH" FAKE_CLAIM="$CTMP/claim.json" \
               FAKE_UPDATES="$CTMP/updates" FAKE_SHOW="$CTMP/show.json" \
               FAKE_SHOW_DIR="$CTMP/show.d" FAKE_CLOSES="$CTMP/closes" \
               FAKE_CLOSE_REFUSE="$CLOSE_REFUSE" \
               sh "$CLAIMER" tk-subj 2>"$CTMP/err") || CRC=$?
    CUPD=$(cat "$CTMP/updates")
    CCLOSE=$(cat "$CTMP/closes")
    CLOSE_REFUSE=""
}

OPENROW='[{"id":"tk-a","status":"open","assignee":null}]'

# --- (NOWORK) an empty claim drains, and writes nothing ----------------------
run_claim '{"ok":true}' "$OPENROW"
eq "$COUT" "action=drain reason=no-work" "(NOWORK) an empty claim drains"
eq "$CRC"  "1"                           "(NOWORK) …and exits 1 so a caller can branch on status"
eq "${CUPD:-<none>}" "<none>"            "(NOWORK) …touching no bead"

# --- (WORK) the claim is this session's visit, whatever its group -----------
run_claim '{"bead_id":"tk-a","continuation_group":"tk-subj"}' "$OPENROW"
eq "$COUT" "action=work bead=tk-a group=tk-subj" "(WORK) a fresh claim is worked"
eq "$CRC"  "0"                                    "(WORK) …exit 0"
eq "${CUPD:-<none>}" "<none>"                     "(WORK) …and nothing is written"
run_claim '{"bead_id":"tk-a","continuation_group":"tk-other"}' "$OPENROW"
eq "$COUT" "action=work bead=tk-a group=tk-other" \
   "(WORK) a claim in another group than the one a caller passes is worked too"
eq "${CUPD:-<none>}" "<none>" "(WORK) …and is never put back"

# --- (NOGROUP) a claim that names no group -----------------------------------
run_claim '{"bead_id":"tk-c"}' "$OPENROW"
eq "$COUT" "action=work bead=tk-c group=" "(NOGROUP) an ungrouped turn is worked"
eq "${CUPD:-<none>}" "<none>"             "(NOGROUP) …and nothing is written"

# --- (EMPTYSTAMP) the stamp is empty; the tracks edge still carries it -------
# `gc hook --claim` reports the gc.continuation_group STAMP, and the stamp
# lands empty on a minority of visits. The group is the SUBJECT the caller
# works the sitting on, and the `tracks` edge has held where the stamp did not
# (rb-ab9je), so the subject is recovered from it.
VISIT_TRACKS='[{"id":"tk-foreign","status":"open","assignee":null,"metadata":{"task_kind":"visit"},"dependencies":[{"id":"tk-other","dependency_type":"tracks"}]}]'
run_claim '{"bead_id":"tk-foreign","continuation_group":""}' "$VISIT_TRACKS"
eq "$COUT" "action=work bead=tk-foreign group=tk-other" \
   "(EMPTYSTAMP) an empty stamp is recovered from the visit's tracks edge"
eq "${CUPD:-<none>}" "<none>" "(EMPTYSTAMP) …and nothing is written"
run_claim '{"bead_id":"tk-foreign","continuation_group":""}' \
    '[{"id":"tk-foreign","status":"open","assignee":null,"metadata":{"task_kind":"visit"}}]'
eq "$COUT" "action=work bead=tk-foreign group=" \
   "(EMPTYSTAMP) a visit carrying neither recording reports an empty group"
# SCOPE. `tracks` is not a visit-only edge — a convoy tracks its members — so
# resolving it for any bead would hand the caller a subject the bead never had.
run_claim '{"bead_id":"tk-foreign","continuation_group":""}' \
    '[{"id":"tk-foreign","status":"open","assignee":null,"metadata":{},"dependencies":[{"id":"tk-kid","dependency_type":"tracks"}]}]'
eq "$COUT" "action=work bead=tk-foreign group=" \
   "(EMPTYSTAMP) a NON-visit tracks edge invents no group"

echo "── a turn already underway is held, not worked and not drained ──"

UNDERWAY='{"bead_id":"tk-held","continuation_group":"tk-subj","reason":"existing_assignment"}'

# --- (HOLD) the sitting this thread is in ------------------------------------
run_claim "$UNDERWAY" "$OPENROW"
eq "$COUT" "action=hold bead=tk-held group=tk-subj reason=already-underway" \
   "(HOLD) a turn already in_progress under this session is a sitting underway"
eq "$CRC" "3" "(HOLD) …with an exit status distinct from work and from drain"
eq "${CUPD:-<none>}" "<none>" "(HOLD) …and the claimer issues no write of its own"

# --- (HOLD-VACUUM) a hold keeps the siblings adoption took, and says so ------
# The claim is not side-effect free on this path: the same result that reports
# existing_assignment can pre-assign open same-group siblings and name them in
# continuation_assigned. They are later turns of the sitting's OWN group, so
# a hold that dropped the field would leave the caller believing it holds one
# turn when it holds several.
run_claim '{"bead_id":"tk-held","continuation_group":"tk-other","reason":"existing_assignment","continuation_assigned":["tk-sib1","tk-sib2"]}' \
          "$OPENROW"
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
# An empty adopted= would read as a set that arrived and name none of it, and
# visits are filed without gc.root_bead_id, so preassignment returns nothing
# and this is the shape every hold has today.
run_claim '{"bead_id":"tk-held","continuation_group":"tk-subj","reason":"existing_assignment","continuation_assigned":[]}' \
          "$OPENROW"
eq "$COUT" "action=hold bead=tk-held group=tk-subj reason=already-underway" \
   "(HOLD-VACUUM-ABSENT) an empty sibling set adds no field to the line"

# --- (HOLD-FRESH) the mirror: a turn this claim STARTED is ordinary work -----
# `gc hook --claim` reports a turn it moved to in_progress as `claimed` or
# `ready_assignment`; only a turn that was ALREADY in_progress under this
# identity reports `existing_assignment` (hookClaimExistingAssignment,
# cmd/gc/cmd_hook_claim.go).
for fresh in claimed ready_assignment; do
    run_claim "{\"bead_id\":\"tk-new\",\"continuation_group\":\"tk-subj\",\"reason\":\"$fresh\"}" "$OPENROW"
    eq "$COUT" "action=work bead=tk-new group=tk-subj" \
       "(HOLD-FRESH) reason=$fresh is fresh work, not a sitting underway"
    eq "$CRC" "0" "(HOLD-FRESH) …and exits 0"
done

echo "── a sitting stranded between its outcome stamp and its close is finished ──"

# A sitting does not end in one write. Step 7 posts the sign-off, then stamps
# gc.outcome on the visit, reads it back, and closes. A session that dies
# between the stamp and the close leaves a visit that is in_progress, assigned,
# and carrying a final outcome, and the respawn's claim reports it as
# `existing_assignment`. A hold there would send the session back to waiting on
# a sitting that is over, and the close would never run. The stamp lands after
# the sign-off, so a visit carrying the outcome has already had its last word:
# finishing it closes a sitting that is over, not one whose sign-off is owed.
STRANDED='[{"id":"tk-held","status":"in_progress","assignee":"converse-1","metadata":{"task_kind":"visit","gc.outcome":"settled"}}]'
LIVE_VISIT='[{"id":"tk-held","status":"in_progress","assignee":"converse-1","metadata":{"task_kind":"visit"}}]'

# --- (FINISH) the stamped turn is finished, not held -------------------------
run_claim "$UNDERWAY" "$STRANDED"
eq "$COUT" "action=finish bead=tk-held group=tk-subj reason=outcome-stamped" \
   "(FINISH) a turn carrying a final outcome is a sitting over, not one underway"
eq "$CRC" "4" "(FINISH) …with an exit status distinct from work, hold and drain"
if grep -q '^bd close tk-held' <<< "$CCLOSE"; then
    ok "(FINISH) …and the close the dead session never reached runs here"
else
    bad "(FINISH) …and the close the dead session never reached runs here" \
        "no close issued: ${CCLOSE:-<none>}"
fi

# The mirror, and the reason the arm is keyed on the stamp rather than on the
# claim reason: a live sitting carries no outcome and must still be held.
run_claim "$UNDERWAY" "$LIVE_VISIT"
eq "$COUT" "action=hold bead=tk-held group=tk-subj reason=already-underway" \
   "(FINISH) a sitting with no outcome stamp is still held"
eq "${CCLOSE:-<none>}" "<none>" "(FINISH) …and nothing is closed under a live operator"

# --- (FINISH-SCOPE) gc.outcome is not a visit-only key -----------------------
# A dog warrant and a graph.v2 step both carry it. Closing whatever the pool
# hands this role because it has the field would be destruction, so the arm is
# keyed on task_kind=visit exactly as the group recovery above is.
run_claim "$UNDERWAY" \
    '[{"id":"tk-held","status":"in_progress","assignee":"converse-1","metadata":{"gc.outcome":"pass"}}]'
eq "$COUT" "action=hold bead=tk-held group=tk-subj reason=already-underway" \
   "(FINISH-SCOPE) a NON-visit carrying gc.outcome is held, not disposed of"
eq "${CCLOSE:-<none>}" "<none>" "(FINISH-SCOPE) …and is never closed"

# --- (FINISH-FRESH) the arm fires on the claim shape the strand produces -----
# The strand leaves the visit in_progress under the identity that stamped it,
# which is what `existing_assignment` reports. A stamped visit arriving as a
# FRESH claim means something else reopened it, which is a different question;
# disposing of it here would answer it by accident.
run_claim '{"bead_id":"tk-held","continuation_group":"tk-subj","reason":"claimed"}' "$STRANDED"
eq "$COUT" "action=work bead=tk-held group=tk-subj" \
   "(FINISH-FRESH) the finish arm does not fire on a claim it did not start from"
eq "${CCLOSE:-<none>}" "<none>" "(FINISH-FRESH) …and closes nothing out from under it"

# --- (FINISH-FORCE) bd refuses this session's own id on the rendering alone --
# The assignee is the canonical mailbox identity and the actor is derived from
# the session name, so a self-close trips the close-authority guard. gc-helm's
# dismiss escalates the same way. Plain close FIRST, so a close needing no
# override never pays for one.
CLOSE_REFUSE=plain
run_claim "$UNDERWAY" "$STRANDED"
eq "$COUT" "action=finish bead=tk-held group=tk-subj reason=outcome-stamped" \
   "(FINISH-FORCE) a refused close escalates rather than standing"
if grep -q -- '--force' <<< "$CCLOSE"; then
    ok "(FINISH-FORCE) …to --force"
else
    bad "(FINISH-FORCE) …to --force" "no forced close in: ${CCLOSE:-<none>}"
fi
# Matched on the whole first line rather than on the absence of --force: with
# no close attempted at all there is no --force to find either, and the
# ordering assertion would read green on a script that closed nothing.
case "$(head -1 <<< "$CCLOSE")" in
    "bd close tk-held "*--force*)
        bad "(FINISH-FORCE) the plain close is tried first" \
            "the first attempt was already forced: $(head -1 <<< "$CCLOSE")" ;;
    "bd close tk-held "*)
        ok "(FINISH-FORCE) the plain close is tried first" ;;
    *)
        bad "(FINISH-FORCE) the plain close is tried first" \
            "no close was attempted at all: ${CCLOSE:-<none>}" ;;
esac

# --- (FINISH-STUCK) a close that will not take is still a finish -------------
# The READ decides: a close can exit 0 and leave the visit open. Answering
# `hold` on that would send the session back to waiting on a sitting that is
# over, which is the defect itself, so the verdict stands and the operator gets
# the line naming the command that ends it.
CLOSE_REFUSE=all
run_claim "$UNDERWAY" "$STRANDED"
eq "$COUT" "action=finish bead=tk-held group=tk-subj reason=outcome-stamped" \
   "(FINISH-STUCK) a close that would not take does not fall back to a hold"
eq "$CRC" "4" "(FINISH-STUCK) …and keeps the finish status"
if grep -q 'would not close' "$CTMP/err"; then
    ok "(FINISH-STUCK) …and the failure is reported, not swallowed"
else
    bad "(FINISH-STUCK) …and the failure is reported, not swallowed" \
        "$(cat "$CTMP/err")"
fi

# --- (FINISH-VACUUM) a finish names its adopted siblings and closes none -----
# Siblings are later turns of the sitting's own group. The stamp is on the one
# visit that ended, so it is the only bead the arm may dispose of.
run_claim '{"bead_id":"tk-held","continuation_group":"tk-subj","reason":"existing_assignment","continuation_assigned":["tk-sib1"]}' \
          "$STRANDED"
eq "$COUT" "action=finish bead=tk-held group=tk-subj reason=outcome-stamped adopted=tk-sib1" \
   "(FINISH-VACUUM) a finished turn still names what the claim assigned with it"
# Both halves, so a run that closed NOTHING cannot read as "no sibling closed".
if ! grep -q '^bd close tk-held' <<< "$CCLOSE"; then
    bad "(FINISH-VACUUM) only the stranded turn is closed" \
        "the stranded turn itself was never closed: ${CCLOSE:-<none>}"
elif grep -q 'tk-sib1' <<< "$CCLOSE"; then
    bad "(FINISH-VACUUM) only the stranded turn is closed" "a sibling was closed too: $CCLOSE"
else
    ok "(FINISH-VACUUM) only the stranded turn is closed"
fi

# --- the prompt and the doc carry the verdict the script returns -------------
# An unknown action falls through the prompt's case with VISIT set, so a prompt
# that never learned this verdict walks a closed visit into step 2 and holds a
# second sitting on a subject that already settled one.
have "the prompt has a branch for a sitting already over" 'action=finish' "$PROMPT"
have "…and posts nothing into a thread the session took with it" \
     'Post nothing, and run none of' "$PROMPT"
have "the central doc states the fourth verdict" 'action=finish' "$ENGAGE"

# --- every path that closes the visit ends the session ------------------------
# The drain is the last act wherever the visit closes, and nothing claims
# after it. Collapsed to one line per surface, because the prose is
# hard-wrapped and a multi-word literal breaks when a sentence ahead of it
# grows.
ENDS_PROSE="$TMPD/ends-prose.txt"
awk '/^- \*\*How this thread ends/ {f=1} f && /^- \*\*Disposing of a subject/ {exit} f {print}' "$PROMPT" \
    | tr '\n' ' ' | tr -s ' ' >"$ENDS_PROSE"
have "the prompt says a closed visit ends the session, whichever path closed it" \
     'A closed visit ends this session, whichever path closed it' "$ENDS_PROSE"
have "…drains after the writes that follow the close" 'gc runtime drain-ack' "$ENDS_PROSE"
have "…and never claims again" 'Never claim again' "$ENDS_PROSE"
FINISH_PROSE="$TMPD/finish-prose.txt"
awk '/action=finish. — this visit/ {f=1} f && /action=hold. — this bead/ {exit} f {print}' "$PROMPT" \
    | tr '\n' ' ' | tr -s ' ' >"$FINISH_PROSE"
have "the finish arm drains once the close is done" 'Then drain' "$FINISH_PROSE"
have "…and escalates a close it could not complete before it drains" 'Escalate that before you drain' "$FINISH_PROSE"
FOLD_LINE="$TMPD/fold-line.txt"
grep -F -A3 -e '--into "$HOLDER" --outcome folded' "$PROMPT" | tr '\n' ' ' >"$FOLD_LINE"
have "the fold arm drains once it has closed the visit" 'Then drain' "$FOLD_LINE"
have "a moot or benign close drains once the close-out exits 0" \
     'Once it exits 0, drain' "$SK_RECHECK"
SETTLE_TAIL="$TMPD/settle-tail.txt"
tr '\n' ' ' < "$SK_SETTLE" | tr -s ' ' >"$SETTLE_TAIL"
have "the sign-off drains once the close has landed" 'Run `gc runtime drain-ack` once the close has landed' "$SETTLE_TAIL"
have "…and not when the close did not land" 'and do not drain' "$SETTLE_TAIL"

# --- the prompt is the half that decides what a hold MEANS -------------------
# The script can state that a sitting is underway; whether this session's
# scrollback still carries the framing is answerable only in the thread, so
# both arms of that choice live in the prompt — as prose, which reverts
# silently unless pinned here.
have "the prompt has a branch for a sitting already underway" 'action=hold' "$PROMPT"
have "…and the claimer-less fallback renders the same verdict" \
     'existing_assignment' "$PROMPT"
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
# of it grows. Both arms are pinned: a scrollback-less respawn tells a real
# hold from a dead claim by the gc.hold_demand trace, so the verdict resolves
# to two different acts, and a hold that keeps one and loses the other either
# leaves a reaped sitting with nothing posted or re-opens one the operator is
# already reading.
HOLD_PROSE="$TMPD/hold-prose.txt"
awk '/already assigned to this session/ {f=1}
     f && /^   On a fresh claim/ {exit}
     f {print}' "$PROMPT" | tr '\n' ' ' | tr -s ' ' >"$HOLD_PROSE"
have "…and forbids the drain-ack that would take the operator's pane" \
     'Do not `drain-ack`' "$HOLD_PROSE"
have "…and leaves a thread that already carries the sitting alone" \
     'nothing to do' "$HOLD_PROSE"
have "…and re-opens a scrollback-less respawn once its trace proves the hold" \
     'Re-open it at step 4' "$HOLD_PROSE"

# The nudge is read before step 1, so naming the script alone lands the session
# outside the block where the hold verdict is read. The field is empty while the
# backstops are silenced, and these bind whatever text re-arms them.
if [ -s "$NUDGE_VAL" ]; then
    have "the wake nudge sends the session through the prompt's claim block" \
         "step 1's claim block" "$NUDGE_VAL"
    lacks "…and no longer reads as an instruction to run the visit to its close" \
          'work the visit it returns' "$NUDGE_VAL" \
          "this sentence directs a mid-hold session to run the visit to its close"
else
    have "config binds a re-armed nudge to the prompt's step-1 block" \
         "step-1 block" "$ATOML"
fi

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
# converse-signoff.sh is the half that decides whether the flag is ever passed;
# the prompt's step 7 states the disposition and the script carries it through.
have "the sign-off script can carry the waits" '--by converse "${WAIT[@]}"' "$REPO/assets/scripts/converse-signoff.sh"
have "…and accumulates them in an array" 'WAIT=()' "$REPO/assets/scripts/converse-signoff.sh"
# The same array carries the other answer to the same question. A sitting that
# settled its subject says so with --no-wait, and one that says neither leaves a
# headline the board and the doctor read as a wait nothing re-asks. Both flags
# have to be reachable from the block, or the sitting has only one thing it can
# claim and will claim it.
have "the sign-off block can also say nothing is waiting" '--no-wait' "$SK_SETTLE"
have "gc-helm takeaway accepts --no-wait" '--no-wait)' "$HELM"
have "…and stamps the disposition beside the headline" 'gc.takeaway_settled=$no_wait' "$HELM"
# THE SHELL, not style. The block was written `WAITING=""` … `--by converse
# $WAITING`, unquoted, with a comment saying that was deliberate — an idiom that
# needs word-splitting to become several arguments. This city runs zsh, which
# does not word-split an unquoted parameter: a populated array arrived as ONE
# argument and gc-helm died with `unknown flag '--waiting-on tk-… --waiting-on
# tk-…'`. The empty case splits to nothing in every shell, so the bug was
# invisible on sittings that routed nothing and fired reliably on the ones the
# flag exists for — twice in one day before it was diagnosed. It
# reverts by one pair of quotes coming off, so it is pinned from both sides.
lacks "…and never as an unquoted string, which zsh does not split" \
      '--by converse $WAIT' "$REPO/assets/scripts/converse-signoff.sh" \
      "an unquoted parameter is ONE argument under zsh — the flags never reach gc-helm and the wait is lost on exactly the sittings that routed work (tk-2cy79)"
lacks "…nor teaches the broken idiom as deliberate" \
      'Unquoted on purpose' "$REPO/assets/scripts/converse-signoff.sh" \
      "the comment blessed the word-splitting idiom, so the next editor restores it"
have "the routing rule tells converse to wire the wait" '--waiting-on <work-bead>' "$SK_SETTLE"
# The takeaway is read back on the SUBJECT. The verification the block already
# shipped checks `gc.outcome` on the VISIT, which is a different bead: a sitting
# whose takeaway died still passed it and closed clean — the "unstamped closed
# visit" this same step warns against, one bead over.
have "the takeaway is read back, not just the visit's outcome stamp" \
     'metadata["gc.takeaway"]' "$REPO/assets/scripts/converse-signoff.sh"
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

echo "── a wait is a bead and an edge, never a parked subject ──"
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
        "filed under the gated bead, the demand can never carry a blocks edge to it"
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
if demand_body | grep -qF -- 'blocks_edge_reads_back "$_w" "$demand"'; then
    ok "…having read the edge back off each bead it was asked to gate"
else
    bad "…having read the edge back off each bead it was asked to gate" \
        "a read-back that checks only the gated bead passes an --also-blocks target that never got its edge"
fi

# converse-hold.sh files the demand and converse-signoff.sh discharges it; the
# prompt states which and calls them. Matched on the CAPTURE, not the call: the
# sign-off re-states a demand with the same tokens, so a looser pattern passes
# on a hold that files nothing.
have "the hold files a demand, not only a stamp" 'DEMAND_OUT=$("$HELM" demand "$GATED"' "$REPO/assets/scripts/converse-hold.sh"
have "…and reads the demand id back off stdout" "awk '/^demand /{print \$2; exit}'" "$REPO/assets/scripts/converse-hold.sh"
lacks "…and never authorizes a prose-only wait in its place" \
      'the takeaway is then the only record' "$REPO/assets/scripts/converse-hold.sh" \
      "that arm sends the sitting on to post framing for a hold with no demand bead behind it"

have "the sitting resolves the demand gate when it settles the question" \
     'gc bd gate resolve "$DEMAND"' "$REPO/assets/scripts/converse-signoff.sh"
have "…and re-states the wait on the SUBJECT when it does not (cut-short consolidation)" \
     '"$HELM" demand "$SUBJECT" "$STILL_OWED"' "$REPO/assets/scripts/converse-signoff.sh"
have "the prompt says what a sitting files sits beside the subject" \
     'a sitting files sits beside the subject' "$PROMPT"
have "…except work that decomposes an epic subject, which is its member" \
     'genuinely decomposes an epic subject' "$PROMPT"

# THE POINT OF ALL OF IT. A prose hold is a dispatch only a person can resume:
# it requires someone to come back, read a sentence, and hand-clear a field.
# No agent in this pack may write one. The readers stay, because live holds
# predate this rule and keep working. Converting them is separate work, so
# this pins the WRITE.
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

echo "── a sitting is a conversation, not a unit of work ──"
# The role knew what it must not do and not what it IS, so every prohibition
# read as a fence around one repo rather than as a consequence of the shape of
# the work. From "protect the pack checkout" a session reasons that a repo
# which is not pack source is fair game. The statement has to come first, on
# page one, and the prohibition has to rest on it.
if printf '%s\n' "$INTRO" | grep -q 'not a unit of work'; then
    ok "the opening says what a sitting is, not only what it may not do"
else
    bad "the opening says what a sitting is, not only what it may not do" \
        "without it every rule below is a fence with no principle behind it, and the role argues about where the fence ends"
fi
if printf '%s\n' "$INTRO" | grep -q 'no commits'; then
    ok "…and that it produces no commits"
else
    bad "…and that it produces no commits" \
        "the commit prohibition belongs to the definition; stated only as a rule it reads as scoped to whatever repo the rule names"
fi
OUTPUT_RULE="$(awk '/^- \*\*A visit acts on its universe/ {f = 1; print; next} f && /^- \*\*/ {exit} f {print}' "$PROMPT")"
if [ -z "$OUTPUT_RULE" ]; then
    bad "the visit-latitude output rule is still extractable" \
        "no '- **A visit acts on its universe' rule in $PROMPT — the extraction is stale, not the prompt"
else
    ok "the visit-latitude output rule is still extractable"
    if printf '%s\n' "$OUTPUT_RULE" | grep -q 'not a unit of work'; then
        ok "…and rests on what a sitting is, not on what a checkout holds"
    else
        bad "…and rests on what a sitting is, not on what a checkout holds" \
            "the rule is right either way; only the right REASON survives contact with a repo that is not pack source"
    fi
    if printf '%s\n' "$OUTPUT_RULE" | grep -q 'live pack source'; then
        bad "…and no longer justifies itself by the checkout" \
            "'the checkout is live pack source' invites the scope argument: it says nothing about any other repo"
    else
        ok "…and no longer justifies itself by the checkout"
    fi
fi

echo "── what reaches the operator is a judgment only they can make ──"
# "Does a pool cover it, and everything uncovered goes to the operator" is the
# wrong test in both directions: it hands over work nobody automated yet, and
# it reads driving a judgment — the evidence, the analysis, the framing — as
# the operator's job rather than the sitting's.
have "the prompt names the operator boundary as a judgment they are needed for" \
     'the point where the OPERATOR is needed' "$PROMPT"
have "…and says work that merely needs doing goes to a molecule" \
     'goes to a molecule' "$PROMPT"
have "…and makes an unreachable gap a bead, not a chore handed over" \
     'a bead to file in its own right' "$PROMPT"

echo "── an informed sitting may close, and doubt keeps it open ──"
# The mandatory trailing decision made one ending illegal: the operator asked,
# was answered, and wants to close out. Manufacturing a decision for them is
# how that ending got spent as attention. The correction over-corrects just as
# easily, so both halves are pinned: the omission is legal, and doubt still
# holds the sitting open.
lacks "no rule makes a decision mandatory on every framing" \
      'decide is not a hold' "$PROMPT" \
      "that clause forbids the informed close-out: the operator wanted to know something, now knows it, and the sitting can end"
have "the omission is stated as legal" \
     'nothing for the operator to decide is legal' "$PROMPT"
have "…and doubt still leaves the sitting open" \
     'the sitting stays open' "$PROMPT"
# converse defines its hand-back shape inline (steps 5 and 7) and does not
# inject the shared operator-next-step-trailing fragment. Injecting it would
# render a `Next (yours):` shape below the inline hand-back and contradict
# it; the fragment stays for witness and mechanik, whose output does not
# change.
if grep -q '{{ template "operator-next-step-trailing" \. }}' "$PROMPT"; then
    bad "converse does not inject the shared trailing-decision fragment" \
        "the injection is back; it renders the Next (yours): shape below the inline hand-back and the two contradict each other"
else
    ok "converse does not inject the shared trailing-decision fragment"
fi

echo "── every framing hands over the switch that ends the sitting ──"
# A sitting stays up until its visit closes, and nothing reaps one. The
# operator's lever existed but lived in a rule the operator never reads, so
# ending a conversation meant remembering a command. It goes at the foot of the
# framing, and it has to be a command that RUNS: a held visit is assigned to
# the session holding it, and a session restarted mid-hold closes under a
# different identity string, which bd refuses outright. It needs no bead-id —
# the subject is inferred from the session the command runs in — so the bare
# line stands and the same act can sit behind a keystroke.
have "the framing ends with a copyable close-out" 'dismiss --reason' "$SK_HOLD"
have "…written with the resolved path, not a variable the operator never set" \
     'Write the resolved path' "$SK_HOLD"
have "…and the close-out needs no bead-id: it infers the sitting's subject" \
     'needs no bead-id' "$SK_HOLD"
have "…and it is framed as a control, not a chore" 'a control, not a chore' "$SK_HOLD"
# The verb has to do what the prompt promises of it, or the offered line is the
# hand-written close under another name.
dismiss_body() { sed -n '/^cmd_dismiss()/,/^}/p' "$HELM"; }
if dismiss_body | grep -q 'gc.outcome=dismissed'; then
    ok "dismiss stamps the outcome a finished sitting is read for"
else
    bad "dismiss stamps the outcome a finished sitting is read for" \
        "the operator's close-out would leave a closed visit no board can report — the unstamped close step 7 refuses to perform"
fi
d_stamp=$(dismiss_body | grep -n 'gc.outcome=dismissed' | head -1 | cut -d: -f1)
d_close=$(dismiss_body | grep -n 'gc bd close "\$_v"' | head -1 | cut -d: -f1)
if [ -n "$d_stamp" ] && [ -n "$d_close" ] && [ "$d_stamp" -lt "$d_close" ]; then
    ok "…before the close, so it lands whichever arm the close takes"
else
    bad "…before the close, so it lands whichever arm the close takes" \
        "stamp@${d_stamp:-none} close@${d_close:-none} — a stamp written after a close that needed --force is a write onto the refusal path"
fi
if dismiss_body | grep -q -- '--force'; then
    ok "dismiss escalates past the holder's claim rather than asking the operator to"
else
    bad "dismiss escalates past the holder's claim rather than asking the operator to" \
        "without the fallback the offered command fails on exactly the sittings a restart touched, which is the normal case for a long hold"
fi

# converse does not inject the shared fragment, but it must stay intact for
# witness and mechanik, whose output does not change. If the fragment lost its
# own placement rule, those two roles' endings would shift.
FRAG="$REPO/template-fragments/operator-next-step-trailing.template.md"
if grep -qF -- 'sits below it' "$FRAG"; then
    ok "the shared fragment is intact for witness and mechanik"
else
    bad "the shared fragment is intact for witness and mechanik" \
        "the fragment lost 'sits below it'; witness and mechanik output would change"
fi

# ── STEP 7 DISCHARGE, EXECUTED (converse-signoff.sh) ─────────────────────────
# The step-7 sign-off/discharge bash ships as assets/scripts/converse-signoff.sh
# (§C1 above still exercises the takeaway-writer RESOLUTION inside the prompt's
# fenced block; here the whole discharge is RUN). These assertions drive the
# script against stubs: the takeaway lands on the subject with the WAIT disposition,
# the demand discharges one of two ways keyed to --ruled, and a held subject is
# released only when the sitting ruled. The writers are the script's siblings in
# the copy of the pack that runs, never a rig root's or the city's.
echo "── step 7 discharge ships and runs as converse-signoff.sh ──"
SIGNOFF_SUT="$REPO/assets/scripts/converse-signoff.sh"
[ -x "$SIGNOFF_SUT" ] && ok "converse-signoff.sh is present and executable" \
    || bad "converse-signoff.sh is present and executable" "missing or not +x: $SIGNOFF_SUT"
bash -n "$SIGNOFF_SUT" && ok "converse-signoff.sh: valid bash" \
    || bad "converse-signoff.sh: valid bash" "bash -n failed"

SO="$TMPD/so"; SOBIN="$SO/bin"; SOPACK="$SO/pack"; SOFOR="$SO/foreign"; SOCITY="$SO/city"; SOBARE="$SO/bare"
SOST="$SO/state"   # one <id>.closed per demand a gate resolve or close landed on
mkdir -p "$SOBIN" "$SOPACK/assets/scripts" "$SOFOR" "$SOCITY/rigs/gc-toolkit/assets/scripts" "$SOBARE" "$SOST"
SOLOG="$SO/log"    # gc-helm.sh + lifecycle.sh calls, in order
SOGC="$SO/gclog"   # gc bd gate/close/update calls

{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$SOBIN/gc" <<'STUB'
[ "${1:-}" = "bd" ] || exit 2
# The demand rows this store holds: a subject/anchor demand (SO_DEMAND, default
# on — the explicit merge-hold case) and/or a demand on the visit
# (SO_VISIT_DEMAND, default off — the conversation-wait case). SO_DEMAND_LIST
# replaces both with a literal list, for the cases where sibling sittings hold
# topic-keyed demands on one shared subject. SO_UNLISTED holds rows `bd show`
# answers but the open listing leaves out, such as a demand an operator deferred.
rows() {
    if [ -n "${SO_DEMAND_LIST:-}" ]; then printf '%s\n' "$SO_DEMAND_LIST"; return; fi
    items=""
    [ "${SO_DEMAND:-1}" = "1" ] && items='{"id":"d-x","assignee":"","status":"open","metadata":{"gc.demand_for":"item-x"}}'
    if [ "${SO_VISIT_DEMAND:-0}" = "1" ]; then
        [ -n "$items" ] && items="$items,"
        items="$items"'{"id":"d-v","assignee":"","status":"open","metadata":{"gc.demand_for":"v-x"}}'
    fi
    printf '[%s]\n' "$items"
}
in_set() { case " ${2:-} " in *" $1 "*) return 0 ;; esac; return 1; }
# A gate resolve or close lands unless the demand is in SO_STUCK, the store that
# took the call and never wrote the close. A landed close reads back closed and
# drops out of the open listing.
land_close() { in_set "$1" "${SO_STUCK:-}" || : >"$SOST/$1.closed"; }
case "${2:-}" in
    show)
        id="${3:-}"
        # SO_SHOW_FAIL: the read errors with no JSON. SO_MISSING: gc's not-found
        # answer, a non-zero exit that still prints the not-found object.
        if in_set "$id" "${SO_SHOW_FAIL:-}"; then echo "Error: invalid connection" >&2; exit 1; fi
        if in_set "$id" "${SO_MISSING:-}"; then
            echo '{"error":"no issues found matching the provided IDs","schema_version":1}'; exit 1
        fi
        case "$id" in
            # SO_VISIT_META is a metadata object the visit carries as well.
            v-x) vm="${SO_VISIT_META:-}"; [ -n "$vm" ] || vm='{}'
                 jq -nc --arg hd "${SO_HOLD_DEMAND:-}" --arg tp "${SO_TOPIC:-}" --arg vt "${SO_VISIT_TOPIC:-}" \
                    --arg tr "${SO_TRACKS:-}" --arg cg "${SO_GROUP:-}" --argjson vm "$vm" \
                    --arg rl "$(cat "$SOST/v-x.ruling" 2>/dev/null)" \
                    '[{id:"v-x",metadata:(({"task_kind":"visit"} + $vm
                        +(if $hd=="" then {} else {"gc.hold_demand":$hd} end)
                        +(if $tp=="" then {} else {"escalation_key":$tp} end)
                        +(if $vt=="" then {} else {"visit_topic":$vt} end)
                        +(if $cg=="" then {} else {"gc.continuation_group":$cg} end)
                        +(if $rl=="" then {} else {"gc.ruling":$rl} end)))}
                      +(if $tr=="" then {} else {dependencies:[{id:$tr,dependency_type:"tracks"}]} end)]' ;;
            # SO_MERGE_RESULT puts the subject in a lifecycle state (pull_request
            # is an open PR); SO_SUBJECT_UNREADABLE makes it a read that fails.
            *)   row=$(rows | jq -c --arg id "$id" --argjson un "${SO_UNLISTED:-[]}" \
                     '[(.[]?, $un[]) | select(.id == $id)] | .[0] // empty')
                 if [ -n "$row" ]; then
                     st=""; [ -e "$SOST/$id.closed" ] && st=closed
                     printf '%s' "$row" | jq -c --arg st "$st" '[if $st == "" then . else .status = $st end]'
                 elif [ -n "${SO_SUBJECT_UNREADABLE:-}" ]; then echo '{"error":"no issues found"}'
                 elif [ "${SO_TAKEAWAY:-1}" = "1" ]; then jq -nc --arg id "$id" --arg mr "${SO_MERGE_RESULT:-}" \
                    '[{id:$id,metadata:({"gc.takeaway":"prior"}+(if $mr=="" then {} else {merge_result:$mr} end))}]'
                 else jq -nc --arg id "$id" --arg mr "${SO_MERGE_RESULT:-}" \
                    '[{id:$id,metadata:(if $mr=="" then {} else {merge_result:$mr} end)}]'; fi ;;
        esac ;;
    list)
        # SO_LIST_RC fails the listing outright. SO_LIST_RAW is printed instead at
        # exit 0, for a listing that answers but does not parse.
        if [ -n "${SO_LIST_RC:-}" ]; then echo "Error: search count issues: invalid connection" >&2; exit "$SO_LIST_RC"; fi
        if [ -n "${SO_LIST_RAW+set}" ]; then printf '%s' "$SO_LIST_RAW"; exit 0; fi
        closed=$(cd "$SOST" && ls 2>/dev/null | sed -n 's/\.closed$//p' | jq -R . | jq -sc .)
        rows | jq -c --argjson c "$closed" '[.[]? | select((.id as $i | $c | index($i)) == null)]' ;;
    gate)  printf 'GC: %s\n' "$*" >>"$SOGC"
           [ "${SO_GATE_RC:-0}" = 0 ] && land_close "${4:-}"
           exit "${SO_GATE_RC:-0}" ;;
    close) printf 'GC: %s\n' "$*" >>"$SOGC"
           [ "${SO_CLOSE_RC:-0}" = 0 ] && land_close "${3:-}"
           exit "${SO_CLOSE_RC:-0}" ;;
    # The visit keeps its gc.ruling in $SOST/v-x.ruling, so the sign-off's
    # read-back sees what landed. SO_RULING_DROP loses the write while the
    # update still exits 0.
    update) printf 'GC: %s\n' "$*" >>"$SOGC"
            if [ "${3:-}" = v-x ] && [ -z "${SO_RULING_DROP:-}" ]; then
                prev=""
                for a in "$@"; do
                    case "$prev:$a" in
                        --set-metadata:gc.ruling=*) printf '%s' "${a#gc.ruling=}" >"$SOST/v-x.ruling" ;;
                        --unset-metadata:gc.ruling) rm -f "$SOST/v-x.ruling" ;;
                    esac
                    prev="$a"
                done
            fi
            exit 0 ;;
    *) exit 2 ;;
esac
STUB
chmod +x "$SOBIN/gc"
so_helm() {   # <root> <marker> — a gc-helm.sh that logs each call with its root
    # Its demand verb prints the `demand <id>` line callers read the id from, or
    # exits SO_HELM_DEMAND_RC and prints nothing, as a demand that did not land.
    cat >"$1/assets/scripts/gc-helm.sh" <<HELM
#!/usr/bin/env bash
printf 'helm[$2] %s\n' "\$*" >>"\$SOLOG"
case "\${1:-}" in
    takeaway) exit 0 ;;
    demand)   [ "\${SO_HELM_DEMAND_RC:-0}" = 0 ] || exit "\$SO_HELM_DEMAND_RC"
              echo "demand \${SO_RESTATED:-d-s} blocks \$2 (by converse): \$3" ;;
    *) exit 2 ;;
esac
HELM
    chmod +x "$1/assets/scripts/gc-helm.sh"
}
so_helm "$SOPACK" RIG
so_helm "$SOCITY/rigs/gc-toolkit" CITY
cat >"$SOPACK/assets/scripts/lifecycle.sh" <<'LC'
#!/usr/bin/env bash
case "${1:-}" in
    state)      if [ -n "${STUB_STATE_RC:-}" ]; then echo "lifecycle: ${2:-} unreadable" >&2; exit "$STUB_STATE_RC"; fi
                printf '%s\n' "${STUB_STATE:-held}" ;;
    transition) printf 'lc %s\n' "$*" >>"$SOLOG"; exit 0 ;;
    *) exit 2 ;;
esac
LC
chmod +x "$SOPACK/assets/scripts/lifecycle.sh"
# so_pack <dir> — a copy of the sign-off under <dir>, beside the libraries it
# sources, so it runs the writers <dir> carries.
so_pack() {
    mkdir -p "$1/assets/scripts"
    cp "$SIGNOFF_SUT" "$REPO/assets/scripts/visit-identity.sh" "$REPO/assets/scripts/visit-topic.sh" "$1/assets/scripts/"
}
so_pack "$SOPACK"; so_pack "$SOFOR"; so_pack "$SOCITY/rigs/gc-toolkit"

# run_so [VAR=val ...] — run the copy of converse-signoff.sh in SO_PACK (SOPACK by
# default) with the flags in SOARGS from a non-git cwd; trailing VAR=val pairs
# override the base env (env: last wins), so a case dials SO_DEMAND /
# SO_TAKEAWAY / SO_GATE_RC / STUB_STATE inline. Captures SO_OUT and SO_RC; resets the two logs, and the
# store's closes and the visit's gc.ruling too unless SO_KEEP=1 (a re-run against
# the store a first run left behind). SO_SEED_RULING, set on the call, seeds the
# visit with a ruling an earlier run left.
SOARGS=()
SO_OUT=""; SO_RC=0; SO_KEEP=0
run_so() {
    : >"$SOLOG"; : >"$SOGC"
    [ "$SO_KEEP" = 1 ] || rm -f "$SOST"/*.closed "$SOST/v-x.ruling"
    [ -z "${SO_SEED_RULING:-}" ] || printf '%s' "$SO_SEED_RULING" >"$SOST/v-x.ruling"
    SO_OUT="$(cd "$SOBARE" && env PATH="$SOBIN:$PATH" \
        GC_RIG_ROOT="$SOPACK" GC_CITY_PATH="$SOCITY" GIT_CEILING_DIRECTORIES="$TMPD" \
        SOLOG="$SOLOG" SOGC="$SOGC" SOST="$SOST" "$@" bash "${SO_PACK:-$SOPACK}/assets/scripts/converse-signoff.sh" "${SOARGS[@]}" 2>&1)"
    SO_RC=$?
}
# no_writes <label> — the run reached no writer: no gc-helm.sh or lifecycle.sh
# call, and no gc bd gate, close or update.
no_writes() {
    if [ -s "$SOLOG" ] || [ -s "$SOGC" ]; then
        bad "$1" "a write reached the store: $(cat "$SOLOG" "$SOGC" | tr '\n' '|')"
    else ok "$1"; fi
}

echo "── --ruled yes: record on the subject, resolve the gate, release a held subject ──"
SOARGS=(--visit v-x --subject item-x --outcome "settled — done" --ruled yes --no-wait --ruling approved --route "gc-toolkit/gc-toolkit.polecat")
run_so
eq "$SO_RC" "0" "the discharge exits 0 on a clean ruling"
have "the takeaway lands on the subject with the outcome and --no-wait" \
     'helm[RIG] takeaway item-x settled — done --by converse --no-wait' "$SOLOG"
have "a ruled sitting resolves the demand gate" 'bd gate resolve d-x --reason approved' "$SOGC"
have "…and stamps the ruling onto the demand's board sentence through the takeaway verb, whose --no-wait marks it settled" \
     'helm[RIG] takeaway d-x approved --by converse --no-wait' "$SOLOG"
if grep -q 'gc.takeaway_settled' "$SOGC"; then bad "…and never hand-stamps the settled mark" "gc.takeaway_settled reached a direct bd update; the verb's --no-wait is its only writer"; else ok "…and never hand-stamps the settled mark, so the verb stays its only writer"; fi
have "…and releases the held subject back to the pool it named" \
     'lc transition item-x --to unanchored --route gc-toolkit/gc-toolkit.polecat' "$SOLOG"

echo "── --ruled no: re-state the demand, leave the subject held ──"
SOARGS=(--visit v-x --subject item-x --outcome "cut-short — need input" --ruled no --still-owed "still need X")
run_so
eq "$SO_RC" "0" "the cut-short discharge exits 0"
have "an unruled sitting re-states the demand on the subject" 'helm[RIG] demand item-x still need X --by converse' "$SOLOG"
if grep -q 'gate resolve' "$SOGC"; then bad "…and resolves no gate on an unruled sitting" "found a gate resolve on --ruled no"; else ok "…and resolves no gate on an unruled sitting"; fi
if grep -q 'lc transition' "$SOLOG"; then bad "…and releases nothing on an unruled sitting" "found a release on --ruled no"; else ok "…and releases nothing on an unruled sitting"; fi

# A review finding deferred to the visit (finding.sh needs-you) is released only
# by a visit that closed carrying gc.ruling, so the ruling is recorded on the
# visit and read back, and a cut-short sign-off leaves none behind.
echo "── the ruling is recorded on the visit; a cut-short sign-off leaves none ──"
SOARGS=(--visit v-x --subject item-x --outcome "settled — done" --ruled yes --no-wait --ruling "keep the sweep" --route "gc-toolkit/gc-toolkit.polecat")
run_so
eq "$SO_RC" "0" "a ruled sign-off exits 0 once its ruling reads back"
have "the ruling is stamped on the visit as gc.ruling" 'bd update v-x --set-metadata gc.ruling=keep the sweep' "$SOGC"
eq "$(cat "$SOST/v-x.ruling" 2>/dev/null)" "keep the sweep" "…and the visit reads it back"
run_so SO_RULING_DROP=1
eq "$SO_RC" "1" "a ruling that does not read back stops the sign-off (exit 1)"
case "$SO_OUT" in *"gc.ruling"*"NOT SIGNED OFF"*) ok "…naming gc.ruling, so the visit is not closed without it" ;;
                  *) bad "…naming gc.ruling, so the visit is not closed without it" "got: $SO_OUT" ;; esac
SOARGS=(--visit v-x --subject item-x --outcome "cut-short — need input" --ruled no --still-owed "still need X")
SO_SEED_RULING="an earlier attempt" run_so
eq "$SO_RC" "0" "a cut-short sign-off on a visit an earlier run ruled exits 0"
have "…and clears that ruling" 'bd update v-x --unset-metadata gc.ruling' "$SOGC"
eq "$(cat "$SOST/v-x.ruling" 2>/dev/null)" "" "…so the visit closes carrying no ruling"
SO_SEED_RULING="an earlier attempt" run_so SO_RULING_DROP=1
eq "$SO_RC" "1" "a stale ruling that does not clear stops the cut-short sign-off"
run_so
lacks "a cut-short sign-off on a visit with no ruling writes none" 'gc.ruling' "$SOGC" \
      "a gc.ruling write reached a visit that carries none"

# Under a standing scope two sittings share one bucket subject and each
# holds its own topic-keyed demand on it. The discharge must resolve the exact
# demand THIS sitting filed — the one converse-hold stamped as gc.hold_demand on
# the visit — so a ruling on finding-b cannot resolve or re-state finding-a's
# operator question. Two demands sit on item-x, A before B; the unscoped
# first-match would resolve dA.
echo "── --ruled yes discharges THIS sitting's demand, not a sibling topic's ──"
TWO_DEMANDS='[{"id":"dA","assignee":"","issue_type":"gate","await_type":"human","await_id":"gc-demand:item-x:finding-a","metadata":{"gc.demand_for":"item-x","gc.demand_topic":"finding-a"}},{"id":"dB","assignee":"","issue_type":"gate","await_type":"human","await_id":"gc-demand:item-x:finding-b","metadata":{"gc.demand_for":"item-x","gc.demand_topic":"finding-b"}}]'
SOARGS=(--visit v-x --subject item-x --outcome "settled — done" --ruled yes --no-wait --ruling approved --route "gc-toolkit/gc-toolkit.polecat")
run_so SO_HOLD_DEMAND=dB SO_TOPIC=finding-b SO_DEMAND_LIST="$TWO_DEMANDS"
eq "$SO_RC" "0" "the topic-scoped discharge exits 0"
have "the ruling resolves the demand gc.hold_demand names" 'bd gate resolve dB --reason approved' "$SOGC"
if grep -q 'gate resolve dA' "$SOGC"; then bad "…and never the sibling topic's gate" "gate resolve reached dA — a sibling topic's operator question"; else ok "…and never the sibling topic's gate (dA left shut)"; fi
have "…and stamps the ruling onto its own demand's board sentence" 'helm[RIG] takeaway dB approved --by converse --no-wait' "$SOLOG"
if grep -q 'takeaway dA' "$SOLOG"; then bad "…and never onto the sibling's" "the ruling reached dA's board sentence"; else ok "…and never onto the sibling's board sentence"; fi

# With no gc.hold_demand stamped (a hold predating it), the fallback scan scopes
# by the visit's escalation_key, so it still isolates finding-b from finding-a.
echo "── the discharge isolates by topic even with no gc.hold_demand stamp ──"
run_so SO_TOPIC=finding-b SO_DEMAND_LIST="$TWO_DEMANDS"
have "the topic-scoped fallback resolves finding-b's demand" 'bd gate resolve dB --reason approved' "$SOGC"
if grep -q 'gate resolve dA' "$SOGC"; then bad "…and not finding-a's" "the fallback scan resolved a sibling topic's demand"; else ok "…and not finding-a's demand"; fi

# A visit filed for a distinct concern (visit_topic=own) sits beside the live
# sitting on its subject, and its topic is `visit:` and its own id. The live
# sitting's keyless demand on item-x comes first in the listing, so the unscoped
# first-match would resolve dA; the topic keeps the ruling on this sitting's dB.
echo "── a distinct-concern sitting discharges its own demand, not the live sitting's ──"
BESIDE_LIVE='[{"id":"dA","assignee":"","issue_type":"gate","await_type":"human","await_id":"gc-demand:item-x","metadata":{"gc.demand_for":"item-x"}},{"id":"dB","assignee":"","issue_type":"gate","await_type":"human","await_id":"gc-demand:item-x:visit:v-x","metadata":{"gc.demand_for":"item-x","gc.demand_topic":"visit:v-x"}}]'
SOARGS=(--visit v-x --subject item-x --outcome "settled — done" --ruled yes --no-wait --ruling approved --route "gc-toolkit/gc-toolkit.polecat")
run_so SO_VISIT_TOPIC=own SO_DEMAND_LIST="$BESIDE_LIVE"
eq "$SO_RC" "0" "the own-topic discharge exits 0"
have "the ruling resolves the demand filed under the visit's own topic" 'bd gate resolve dB --reason approved' "$SOGC"
lacks "…and never the live sitting's demand beside it" 'gate resolve dA' "$SOGC" \
      "gate resolve reached dA — the operator question of the live sitting on the same subject"
SOARGS=(--visit v-x --subject item-x --outcome "cut-short — need input" --ruled no --still-owed "still need X")
run_so SO_VISIT_TOPIC=own SO_DEMAND_LIST="$BESIDE_LIVE"
have "a cut-short re-states the wait on the subject under the visit's own topic" \
     'helm[RIG] demand item-x still need X --by converse --topic visit:v-x' "$SOLOG"
lacks "…and leaves the live sitting's demand alone" 'gate resolve dA' "$SOGC" \
      "the cut-short resolved dA, the live sitting's demand"

echo "── every case of the shared topic fixture discharges under its demand topic ──"
# visit-topic.sh is the one definition of a visit's topic, and
# visit-topic.fixture.json holds the cases the fold, the hold and the sign-off
# each run. The stub serves the fixture's visit carrying each case's metadata.
# A ruling resolves the merge hold filed on the subject under the case's demand
# topic, the topic converse-hold.sh files it under. A cut-short re-states the
# visit's wait on the subject under that topic, or under none.
FX="$REPO/assets/scripts/visit-topic.fixture.json"
eq "$(jq -r '.visit' "$FX")" "v-x" "the fixture's visit is the one the stub serves"
eq "$(jq -r '.subject' "$FX")" "item-x" "the fixture's subject is the one the sign-off is handed"
while IFS= read -r c; do
    [ -n "$c" ] || continue
    name="$(printf '%s' "$c" | jq -r '.name')"
    meta="$(printf '%s' "$c" | jq -c '.metadata')"
    want="$(printf '%s' "$c" | jq -r '.demand_topic')"
    UNDER_TOPIC="$(jq -nc --arg t "$want" '[{id:"dT", assignee:"", issue_type:"gate", await_type:"human",
        await_id:("gc-demand:item-x" + (if $t == "" then "" else ":" + $t end)),
        metadata:({"gc.demand_for":"item-x"} + (if $t == "" then {} else {"gc.demand_topic":$t} end))}]')"
    SOARGS=(--visit v-x --subject item-x --outcome "settled — done" --ruled yes --no-wait --ruling approved --route human)
    run_so SO_VISIT_META="$meta" SO_DEMAND_LIST="$UNDER_TOPIC" STUB_STATE=pull_request
    eq "$SO_RC" "0" "(FIXTURE) $name: the ruled sign-off exits 0"
    have "(FIXTURE) $name: the ruling resolves the merge hold filed under its demand topic" \
         'bd gate resolve dT --reason approved' "$SOGC"
    SOARGS=(--visit v-x --subject item-x --outcome "cut-short — need input" --ruled no --still-owed "still need X")
    run_so SO_VISIT_META="$meta" SO_HOLD_DEMAND=d-v SO_DEMAND=0 SO_VISIT_DEMAND=1
    if [ -n "$want" ]; then
        have "(FIXTURE) $name: a cut-short re-states the wait under its demand topic" \
             "helm[RIG] demand item-x still need X --by converse --topic $want" "$SOLOG"
    else
        have "(FIXTURE) $name: a cut-short re-states the wait" \
             'helm[RIG] demand item-x still need X --by converse' "$SOLOG"
        lacks "(FIXTURE) $name: …under no topic" '--topic' "$SOLOG" "the re-state carried a topic"
    fi
done <<< "$(jq -c '.cases[]' "$FX")"

echo "── the conversation wait gates the VISIT: a ruling resolves the visit demand ──"
# Default Phase A shape: converse-hold files the conversation demand on the visit,
# not the anchor, so the PR is never frozen by the conversation. The discharge
# finds and resolves it off the visit exactly as it does an anchor demand.
SOARGS=(--visit v-x --subject item-x --outcome "settled — done" --ruled yes --no-wait --ruling approved --route "gc-toolkit/gc-toolkit.polecat")
run_so SO_DEMAND=0 SO_VISIT_DEMAND=1
eq "$SO_RC" "0" "the discharge exits 0 on a conversation-wait ruling"
have "a ruled sitting resolves the demand gating the VISIT" 'bd gate resolve d-v --reason approved' "$SOGC"
have "…and stamps the ruling onto the visit demand's board sentence" 'helm[RIG] takeaway d-v approved --by converse --no-wait' "$SOLOG"

echo "── a cut-short conversation wait is MOVED off the closing visit onto the subject ──"
# The visit is about to close, so a demand left on it orphans — gate-visit-sweep
# names it on stderr forever and no return trip re-offers it. The cut-short
# discharge closes the visit demand and re-states the wait on the SUBJECT, where the
# liveness sweep re-offers the next sitting and the merge holds until it is answered.
SOARGS=(--visit v-x --subject item-x --outcome "cut-short — need input" --ruled no --still-owed "still need X")
run_so SO_DEMAND=0 SO_VISIT_DEMAND=1
have "the visit demand is closed so it does not orphan on the closing visit" 'gate resolve d-v' "$SOGC"
have "…its board question is settled as moved" \
     'helm[RIG] takeaway d-v cut short; wait moved to item-x --by converse --no-wait' "$SOLOG"
have "…and the wait is re-stated on the SUBJECT, not the visit" 'helm[RIG] demand item-x still need X --by converse' "$SOLOG"
if grep -q 'demand v-x' "$SOLOG"; then bad "…and no longer re-states on the closing visit" "found 'demand v-x' on a cut-short"; else ok "…and no longer re-states on the closing visit"; fi

echo "── cut-short with BOTH a visit wait and a merge hold: both consolidate on the subject ──"
SOARGS=(--visit v-x --subject item-x --outcome "cut-short — need input" --ruled no --still-owed "still need X")
run_so SO_DEMAND=1 SO_VISIT_DEMAND=1
have "the visit demand is closed" 'gate resolve d-v' "$SOGC"
have "…and the wait is re-stated on the subject (refreshing the merge hold)" 'helm[RIG] demand item-x still need X --by converse' "$SOLOG"

echo "── a conversation wait AND an explicit merge hold: both demands discharge ──"
# A sitting that both waits on the operator (visit demand) and pauses the merge
# (anchor demand) discharges each on the ruling.
SOARGS=(--visit v-x --subject item-x --outcome "settled — done" --ruled yes --no-wait --ruling approved --route human)
run_so SO_DEMAND=1 SO_VISIT_DEMAND=1 STUB_STATE=pull_request
have "the conversation (visit) demand resolves" 'bd gate resolve d-v --reason approved' "$SOGC"
have "the merge-hold (anchor) demand resolves too" 'bd gate resolve d-x --reason approved' "$SOGC"

# The two shapes compose under a standing scope. Each sitting's conversation wait
# gates its own visit, and each sitting that took --hold-merge holds its own
# topic-keyed demand on the shared anchor. A ruling resolves this sitting's visit
# demand and its own merge hold, never a sibling's merge hold, so the anchor's
# merge stays paused until that sibling is answered too.
echo "── a ruling discharges THIS sitting's merge hold on a shared anchor, not a sibling's ──"
SIBLING_HOLDS='[{"id":"d-v","assignee":"","issue_type":"gate","await_type":"human","await_id":"gc-demand:v-x:finding-b","metadata":{"gc.demand_for":"v-x","gc.demand_topic":"finding-b"}},{"id":"dA","assignee":"","issue_type":"gate","await_type":"human","await_id":"gc-demand:item-x:finding-a","metadata":{"gc.demand_for":"item-x","gc.demand_topic":"finding-a"}},{"id":"dB","assignee":"","issue_type":"gate","await_type":"human","await_id":"gc-demand:item-x:finding-b","metadata":{"gc.demand_for":"item-x","gc.demand_topic":"finding-b"}}]'
SOARGS=(--visit v-x --subject item-x --outcome "settled — done" --ruled yes --no-wait --ruling approved --route human)
run_so SO_HOLD_DEMAND=d-v SO_TOPIC=finding-b SO_DEMAND_LIST="$SIBLING_HOLDS" STUB_STATE=pull_request
have "the conversation (visit) demand resolves" 'bd gate resolve d-v --reason approved' "$SOGC"
have "…this sitting's merge hold on the anchor resolves" 'bd gate resolve dB --reason approved' "$SOGC"
lacks "…and a sibling sitting's merge hold stays shut" 'gate resolve dA' "$SOGC" \
      "gate resolve reached dA — the ruling released a merge another sitting still holds"

# Re-stated with no topic, the moved wait would match any demand on the shared
# subject and refresh a sibling sitting's gate in place, overwriting its question.
echo "── a cut-short moves the wait onto the subject under THIS sitting's topic ──"
SOARGS=(--visit v-x --subject item-x --outcome "cut-short — need input" --ruled no --still-owed "still need X")
run_so SO_HOLD_DEMAND=d-v SO_TOPIC=finding-b SO_DEMAND_LIST="$SIBLING_HOLDS"
have "the visit demand is closed" 'gate resolve d-v' "$SOGC"
have "…and the wait is re-stated on the subject under the sitting's topic" \
     'helm[RIG] demand item-x still need X --by converse --topic finding-b' "$SOLOG"
lacks "…and a sibling's demand is left alone" 'gate resolve dA' "$SOGC" \
      "the cut-short resolved dA, a sibling sitting's demand"

echo "── the takeaway lands on the subject it is handed ──"
SOARGS=(--visit v-x --subject item-q --outcome "x — y" --ruled no --still-owed z)
run_so
have "the takeaway targets the subject it is handed" 'takeaway item-q' "$SOLOG"
lacks "…and no other bead" 'takeaway item-x' "$SOLOG" \
      "the takeaway reached item-x, a bead this sitting was not handed"

# The sign-off writes to the subject. Step 1 passes it, and the visit records it
# twice, as its tracks edge and as its gc.continuation_group stamp, so an absent
# --subject is recovered from the visit the way converse-fold.sh recovers it.
# With neither, the cut-short discharge would close the visit's demand and then
# re-state the wait on an empty bead id, dropping the operator's question; it
# refuses before any write instead.
echo "── an absent --subject is recovered from the visit, and refused when the visit names none ──"
SOARGS=(--visit v-x --outcome "cut-short — need input" --ruled no --still-owed "still need X")
run_so SUBJECT= SO_DEMAND=0 SO_VISIT_DEMAND=1 SO_TRACKS=item-t
eq "$SO_RC" "0" "a sign-off with no --subject runs when the visit tracks its subject"
have "…the takeaway lands on the tracked subject" 'helm[RIG] takeaway item-t cut-short — need input --by converse' "$SOLOG"
have "…and the moved wait is re-stated on it" 'helm[RIG] demand item-t still need X --by converse' "$SOLOG"
run_so SUBJECT= SO_DEMAND=0 SO_VISIT_DEMAND=1 SO_GROUP=item-g
have "with no tracks edge, the gc.continuation_group stamp names the subject" \
     'helm[RIG] demand item-g still need X --by converse' "$SOLOG"
run_so SUBJECT= SO_DEMAND=0 SO_VISIT_DEMAND=1
eq "$SO_RC" "2" "a visit that names no subject is refused (exit 2)"
case "$SO_OUT" in *"no subject"*) ok "…and the refusal says why" ;;
                  *) bad "…and the refusal says why" "got: $SO_OUT" ;; esac
lacks "…before the visit's demand is closed, so the operator's question survives" 'gate resolve d-v' "$SOGC" \
      "the sign-off closed the visit demand with no subject to re-state it on"
lacks "…and before any takeaway or demand is written" 'helm[' "$SOLOG" \
      "a write reached gc-helm.sh with no subject"

echo "── the WAIT disposition passes through as repeated flags ──"
SOARGS=(--visit v-x --subject item-x --outcome "o — p" --ruled no --still-owed z --waiting-on tk-a --waiting-on tk-b)
run_so
have "each routed wait rides as its own --waiting-on" \
     'takeaway item-x o — p --by converse --waiting-on tk-a --waiting-on tk-b' "$SOLOG"

echo "── the takeaway read-back is loud when the subject carries none ──"
SOARGS=(--visit v-x --subject item-x --outcome "o — p" --ruled no --still-owed z)
run_so SO_TAKEAWAY=0
case "$SO_OUT" in *"NO TAKEAWAY ON"*) ok "a takeaway that did not land is called out" ;;
                  *) bad "a takeaway that did not land is called out" "got: $SO_OUT" ;; esac

echo "── a ruling releases only a HELD subject ──"
SOARGS=(--visit v-x --subject item-x --outcome "o — p" --ruled yes --ruling r --route human)
run_so STUB_STATE=unanchored
if grep -q 'lc transition' "$SOLOG"; then bad "a subject not held is not transitioned" "found a transition on an unanchored subject"; else ok "a subject not held is not transitioned"; fi

echo "── a ruling on an armed unanchored subject releases nothing and writes no route ──"
# A sitting's hold leaves an armed subject unanchored, so nothing is released,
# whatever --route says, and resolving the gate is what lets the arm send it.
ARMED_ROW='[{"id":"item-x","metadata":{"gc.takeaway":"prior","gc.dispatch_when_ready":"rig/pool"}}]'
for armed_route in human gc-toolkit/gc-toolkit.polecat; do
    SOARGS=(--visit v-x --subject item-x --outcome "o — p" --ruled yes --no-wait --ruling r --route "$armed_route")
    run_so STUB_STATE=unanchored SO_UNLISTED="$ARMED_ROW"
    eq "$SO_RC" "0" "--route $armed_route: the armed subject's sign-off exits 0"
    have "…and resolves the gate as on any ruling" 'bd gate resolve d-x --reason r' "$SOGC"
    lacks "…and runs no transition" 'lc transition' "$SOLOG" "found a transition on an armed unanchored subject"
    lacks "…and writes no route" 'gc.routed_to' "$SOGC" "the sign-off wrote a route beside the arm"
    lacks "…and leaves the arm's keys alone" 'dispatch_when_ready' "$SOGC" "the sign-off wrote the arm"
done

echo "── gate resolve falls back to close for a pre-gate demand ──"
SOARGS=(--visit v-x --subject item-x --outcome "o — p" --ruled yes --ruling "the ruling" --route human)
run_so SO_GATE_RC=1
have "a demand that refuses gate resolve is closed on the same terms" 'bd close d-x --reason the ruling' "$SOGC"

echo "── no demand on the subject: nothing to discharge ──"
SOARGS=(--visit v-x --subject item-x --outcome "o — p" --ruled no --still-owed z)
run_so SO_DEMAND=0
if grep -qE 'demand|gate resolve' "$SOLOG" "$SOGC" 2>/dev/null; then
    bad "no demand present means no discharge" "found a discharge with no demand present"
else ok "no demand present means no discharge"; fi

echo "── no writer beside the sign-off is LOUD, though the rig root and the city hold one ──"
SOARGS=(--visit v-x --subject item-x --outcome "o — p" --ruled no --still-owed z)
SO_PACK="$SOFOR" run_so GC_RIG_ROOT="$SOPACK"
case "$SO_OUT" in *"NO TAKEAWAY WRITER"*) ok "no writer beside the script is LOUD" ;;
                  *) bad "no writer beside the script is LOUD" "got: $SO_OUT" ;; esac
case "$(cat "$SOLOG")" in *"helm["*) bad "…and neither the rig root's nor the city's writer is used" "found: $(cat "$SOLOG")" ;;
                          *) ok "…and neither the rig root's nor the city's writer is used" ;; esac

echo "── the flag contract fails closed on a missing judgment ──"
SOARGS=(--visit v-x --outcome "o — p" --ruled yes --route human); run_so; eq "$SO_RC" "2" "--ruled yes without --ruling is refused"
SOARGS=(--visit v-x --outcome "o — p" --ruled yes --ruling r);    run_so; eq "$SO_RC" "2" "--ruled yes without --route is refused"
SOARGS=(--visit v-x --outcome "o — p" --ruled no);                run_so; eq "$SO_RC" "2" "--ruled no without --still-owed is refused"
SOARGS=(--visit v-x --ruled no --still-owed z);                   run_so; eq "$SO_RC" "2" "a missing --outcome is refused"
SOARGS=(--visit v-x --outcome "o — p" --ruled no --still-owed z --rework); run_so; eq "$SO_RC" "2" "--rework without --ruled yes is refused"

# --rework files the ruling's rework child before anything else is written. Its
# blocks edge then holds the merge before the discharge resolves a merge hold this
# sitting took, and a filing that does not land stops the sign-off with every
# demand still standing. The stub logs into SOGC beside the gate calls, so the
# order of the two is read off one log.
cat >"$SOPACK/assets/scripts/converse-rework.sh" <<'CR'
#!/usr/bin/env bash
printf 'REWORK: %s\n' "$*" >>"$SOGC"
if [ "${SO_REWORK_RC:-0}" = 0 ]; then
    echo "converse-rework: filed rework rw-1 on anchor item-x"
else
    echo "converse-rework: anchor item-x is merge_result='pre_open_gate', not pull_request" >&2
fi
exit "${SO_REWORK_RC:-0}"
CR
chmod +x "$SOPACK/assets/scripts/converse-rework.sh"

echo "── --rework files the ruling's rework first, then the sign-off proceeds ──"
SOARGS=(--visit v-x --subject item-x --outcome "settled — done" --ruled yes --no-wait --ruling approved --route human --rework)
run_so
eq "$SO_RC" "0" "a sign-off whose rework filed exits 0"
have "the rework is filed against the subject, sourced by this visit" \
     'REWORK: --anchor item-x --ruling-bead v-x --ruling approved' "$SOGC"
have "…the discharge still resolves the merge hold" 'bd gate resolve d-x --reason approved' "$SOGC"
so_rw=$(grep -n '^REWORK: ' "$SOGC" | head -1 | cut -d: -f1)
so_gr=$(grep -n 'bd gate resolve d-x' "$SOGC" | head -1 | cut -d: -f1)
if [ -n "$so_rw" ] && [ -n "$so_gr" ] && [ "$so_rw" -lt "$so_gr" ]; then
    ok "…only after the rework's blocks edge holds the merge"
else
    bad "…only after the rework's blocks edge holds the merge" \
        "rework@${so_rw:-none} resolve@${so_gr:-none} — a merge hold released before the rework files leaves the stale PR free to land"
fi
have "…and the PR-reminder close text names the filed rework" 'filed ruling-driven rework on item-x' "$SOGC"

echo "── a rework that does not file stops the sign-off before any write ──"
run_so SO_REWORK_RC=2
eq "$SO_RC" "1" "a refused rework exits 1, so the sitting does not sign off"
case "$SO_OUT" in *"REWORK NOT COMPLETE on item-x"*"not pull_request"*) ok "…naming the subject and why the rework refused" ;;
                  *) bad "…naming the subject and why the rework refused" "got: $SO_OUT" ;; esac
case "$SO_OUT" in *"Do NOT post the sign-off or close the visit"*) ok "…and telling the sitting not to sign off or close" ;;
                  *) bad "…and telling the sitting not to sign off or close" "got: $SO_OUT" ;; esac
so_rest=$(grep -v '^REWORK: ' "$SOGC")
if [ -z "$so_rest" ]; then ok "…no demand resolved and no close text stashed, so a merge hold still holds"
else bad "…no demand resolved and no close text stashed, so a merge hold still holds" "found: $so_rest"; fi
if [ -s "$SOLOG" ]; then bad "…and no takeaway or release written" "found: $(cat "$SOLOG")"
else ok "…and no takeaway or release written"; fi

echo "── a rework script the pack lacks stops the sign-off too ──"
# The city's copy carries a takeaway writer but no converse-rework.sh, so a
# sign-off that ran on past the missing script would reach that writer.
SO_PACK="$SOCITY/rigs/gc-toolkit" run_so GC_RIG_ROOT="$SOPACK"
eq "$SO_RC" "1" "a missing converse-rework.sh exits 1"
case "$SO_OUT" in *"REWORK NOT COMPLETE on item-x: no converse-rework.sh"*) ok "…and says the script resolved nowhere" ;;
                  *) bad "…and says the script resolved nowhere" "got: $SO_OUT" ;; esac
if [ -s "$SOLOG" ] || [ -s "$SOGC" ]; then bad "…and writes nothing" "found: $(cat "$SOLOG" "$SOGC")"
else ok "…and writes nothing"; fi

have "the settle skill gates the sign-off on the script's exit" \
     'if VISIT="$VISIT" SUBJECT="$SUBJECT" "$CONV/converse-signoff.sh"' "$SK_SETTLE"

# A ruled sign-off on an open PR must answer the rework question. A ruling whose
# rework is never filed lands only in notes nothing reads while the PR keeps
# reading ready, so a forgotten flag is refused rather than read as no rework.
echo "── a ruled sign-off on an open PR must answer --rework or --no-rework ──"
SOARGS=(--visit v-x --subject item-x --outcome "settled — done" --ruled yes --no-wait --ruling approved --route human)
run_so SO_MERGE_RESULT=pull_request
eq "$SO_RC" "2" "a ruled sign-off on an open PR that answers neither is refused"
case "$SO_OUT" in *"--rework"*"--no-rework"*) ok "…naming both answers" ;;
                  *) bad "…naming both answers" "got: $SO_OUT" ;; esac
if [ -s "$SOLOG" ] || [ -s "$SOGC" ]; then bad "…and writes nothing" "found: $(cat "$SOLOG" "$SOGC")"
else ok "…and writes nothing, so a merge hold this sitting took still holds"; fi
run_so SO_MERGE_RESULT=pull_request SO_TAKEAWAY=0
eq "$SO_RC" "2" "…whether or not the subject carries an earlier takeaway"

SOARGS=(--visit v-x --subject item-x --outcome "settled — done" --ruled yes --no-wait --ruling approved --route human --no-rework)
run_so SO_MERGE_RESULT=pull_request
eq "$SO_RC" "0" "--no-rework answers it, and the sign-off proceeds"
lacks "…filing no rework" 'REWORK: ' "$SOGC" "--no-rework ran converse-rework.sh"
have "…while the discharge still resolves the merge hold" 'bd gate resolve d-x --reason approved' "$SOGC"
have "…and the PR close text records that the ruling leaves the branch" \
     'gc.pr_visit_actions=ruling: approved (released to human); ruling leaves the branch of item-x as it stands' "$SOGC"

SOARGS=(--visit v-x --subject item-x --outcome "settled — done" --ruled yes --no-wait --ruling approved --route human --rework)
run_so SO_MERGE_RESULT=pull_request
eq "$SO_RC" "0" "--rework answers it, and the sign-off proceeds"
have "…filing the rework against the open PR, sourced by this visit" \
     'REWORK: --anchor item-x --ruling-bead v-x --ruling approved' "$SOGC"
lacks "…and its close text does not say the branch stands" 'leaves the branch' "$SOGC" "a --rework sign-off said the branch stands"

SOARGS=(--visit v-x --subject item-x --outcome "settled — done" --ruled yes --no-wait --ruling approved --route human)
run_so SO_MERGE_RESULT=pre_open_gate
eq "$SO_RC" "0" "a subject that is not an open PR needs no answer"
lacks "…and files no rework" 'REWORK: ' "$SOGC" "a sign-off without --rework ran converse-rework.sh"
lacks "…nor records a branch judgment it was never asked for" 'leaves the branch' "$SOGC" "a sign-off with neither flag said the branch stands"
run_so SO_SUBJECT_UNREADABLE=1
eq "$SO_RC" "2" "a subject that will not read is refused as an open PR would be"
if [ -s "$SOLOG" ] || [ -s "$SOGC" ]; then bad "…writing nothing" "found: $(cat "$SOLOG" "$SOGC")"
else ok "…writing nothing"; fi

SOARGS=(--visit v-x --outcome "o — p" --ruled no --still-owed z --no-rework); run_so; eq "$SO_RC" "2" "--no-rework without --ruled yes is refused"
SOARGS=(--visit v-x --subject item-x --outcome "o — p" --ruled yes --ruling r --route human --rework --no-rework)
run_so; eq "$SO_RC" "2" "--rework with --no-rework is refused"
have "the settle skill teaches the forced answer" '--no-rework' "$SK_SETTLE"

# Every script the sign-off runs is its sibling in the copy of the pack that
# runs. A copy carrying all three uses them, each logging its copy, whatever the
# rig root and the city hold.
echo "── every script the sign-off runs is the one beside it ──"
SOCITY2="$SO/city2"; mkdir -p "$SOCITY2/rigs/gc-toolkit/assets/scripts"
so_pack "$SOCITY2/rigs/gc-toolkit"
so_helm "$SOCITY2/rigs/gc-toolkit" CITY2
cat >"$SOCITY2/rigs/gc-toolkit/assets/scripts/lifecycle.sh" <<'LC'
#!/usr/bin/env bash
case "${1:-}" in
    state)      printf '%s\n' "${STUB_STATE:-held}" ;;
    transition) printf 'lc[CITY2] %s\n' "$*" >>"$SOLOG"; exit 0 ;;
    *) exit 2 ;;
esac
LC
cat >"$SOCITY2/rigs/gc-toolkit/assets/scripts/converse-rework.sh" <<'CR'
#!/usr/bin/env bash
printf 'REWORK[CITY2]: %s\n' "$*" >>"$SOGC"
echo "converse-rework: filed rework rw-1 on anchor item-x"
CR
chmod +x "$SOCITY2/rigs/gc-toolkit/assets/scripts/lifecycle.sh" "$SOCITY2/rigs/gc-toolkit/assets/scripts/converse-rework.sh"
SOARGS=(--visit v-x --subject item-x --outcome "settled — done" --ruled yes --no-wait --ruling approved --route human --rework)
SO_PACK="$SOCITY2/rigs/gc-toolkit" run_so GC_RIG_ROOT="$SOPACK" GC_CITY_PATH="$SOCITY" SO_MERGE_RESULT=pull_request
eq "$SO_RC" "0" "a sign-off runs from the copy of the pack that carries its scripts"
have "…finding the rework script there" 'REWORK[CITY2]: --anchor item-x' "$SOGC"
have "…the takeaway writer" 'helm[CITY2] takeaway item-x settled — done --by converse --no-wait' "$SOLOG"
have "…and the lifecycle writer" 'lc[CITY2] transition item-x --to unanchored --route human' "$SOLOG"

# A degraded store answers a read with an error. Taken as an empty answer, the
# demand listing found no demand, the discharge skipped a gate that still
# blocked the subject, and the sign-off exited 0 with the hold open. Every read
# the discharge depends on now runs before the first write and stops the
# sign-off (exit 1) when it does not answer, so nothing is written and the
# sitting re-runs instead of signing off.
echo "── a demand listing that fails stops the sign-off before any write ──"
SOARGS=(--visit v-x --subject item-x --outcome "settled — done" --ruled yes --no-wait --ruling approved --route human)
run_so SO_LIST_RC=1
eq "$SO_RC" "1" "a failed demand listing exits 1"
case "$SO_OUT" in *"NOT SIGNED OFF"*) ok "…and says the sitting is not signed off" ;;
                  *) bad "…and says the sitting is not signed off" "got: $SO_OUT" ;; esac
no_writes "…and writes nothing, not even the subject's takeaway"

echo "── a listing that exits 0 but does not parse stops it too ──"
for raw in 'Error: search count issues: invalid connection' ''; do
    run_so SO_LIST_RAW="$raw"
    eq "$SO_RC" "1" "a listing that answered '${raw:-<nothing>}' exits 1"
    no_writes "…and writes nothing"
done

echo "── a visit that does not read stops the sign-off ──"
SOARGS=(--visit v-x --subject item-x --outcome "cut-short — need input" --ruled no --still-owed "still need X")
run_so SO_SHOW_FAIL=v-x SO_VISIT_DEMAND=1
eq "$SO_RC" "1" "an unreadable visit exits 1"
no_writes "…before any write, because its topic and gc.hold_demand scope the discharge"

echo "── the demand gc.hold_demand names is read directly ──"
# The listing holds open and in_progress rows only, so a stamped demand an
# operator deferred was never discharged. Read by its id, it is.
DEFERRED='[{"id":"d-v","assignee":"","status":"deferred","issue_type":"gate","await_type":"human","await_id":"gc-demand:v-x","metadata":{"gc.demand_for":"v-x"}}]'
SOARGS=(--visit v-x --subject item-x --outcome "settled — done" --ruled yes --no-wait --ruling approved --route human)
run_so SO_DEMAND=0 SO_HOLD_DEMAND=d-v SO_UNLISTED="$DEFERRED"
eq "$SO_RC" "0" "a ruling on a deferred stamped demand exits 0"
have "…and resolves the demand the listing leaves out" 'bd gate resolve d-v --reason approved' "$SOGC"
have "…and stamps the ruling on it once it reads back closed" 'helm[RIG] takeaway d-v approved --by converse --no-wait' "$SOLOG"
run_so SO_DEMAND=0 SO_VISIT_DEMAND=1 SO_HOLD_DEMAND=d-v SO_SHOW_FAIL=d-v
eq "$SO_RC" "1" "a stamped demand that does not read exits 1"
no_writes "…and writes nothing"
run_so SO_HOLD_DEMAND=d-gone SO_MISSING=d-gone
eq "$SO_RC" "0" "a stamped demand that no longer exists blocks nothing, so the sign-off proceeds"
have "…and still discharges what the listing holds" 'bd gate resolve d-x --reason approved' "$SOGC"

echo "── a ruling stamps a demand only once its close reads back ──"
# The incident shape: gate resolve fails, the close fallback fails, and the
# ruling was stamped on a demand that still blocked, the open-but-settled shape
# doctor/check-wait-is-an-edge reads as a discharged wait.
SOARGS=(--visit v-x --subject item-x --outcome "settled — done" --ruled yes --no-wait --ruling approved --route human)
run_so SO_GATE_RC=1 SO_CLOSE_RC=1 SO_STUCK=d-x
eq "$SO_RC" "1" "a demand neither resolve nor close could close exits 1"
case "$SO_OUT" in *"DEMAND d-x DID NOT CLOSE"*) ok "…and names the demand" ;;
                  *) bad "…and names the demand" "got: $SO_OUT" ;; esac
lacks "…and stamps no ruling on it" 'takeaway d-x approved' "$SOLOG" \
      "the ruling reached a demand that still blocks — open-but-settled"
lacks "…and releases nothing" 'lc transition' "$SOLOG" "a held subject was released while its demand still blocks"
lacks "…and stashes no close text on the visit" 'gc.pr_visit_summary' "$SOGC" \
      "the sign-off ran past a demand it did not close"
# A call can report success without the close landing, so the read-back decides.
run_so SO_STUCK=d-x
eq "$SO_RC" "1" "a resolve that exits 0 but leaves the demand open exits 1"
lacks "…and stamps no ruling on it" 'takeaway d-x approved' "$SOLOG" \
      "the exit status, not the read-back, decided the close"
# Each demand is tried: one that closes gets its ruling, one that does not stops it.
run_so SO_VISIT_DEMAND=1 SO_STUCK=d-x STUB_STATE=held
eq "$SO_RC" "1" "a ruling that closes one demand of two exits 1"
have "…the one that closed carries the ruling" 'helm[RIG] takeaway d-v approved --by converse --no-wait' "$SOLOG"
lacks "…the one that did not carries none" 'takeaway d-x approved' "$SOLOG" \
      "the ruling reached the demand whose close did not land"
lacks "…and the held subject is not released" 'lc transition' "$SOLOG" "released while a demand still blocks"

echo "── a cut-short re-states the wait before it closes the visit's demand ──"
# Closed first, a visit demand whose re-state then failed left a re-run finding
# neither demand, and the operator's open question was gone. The re-state now
# lands first, so a re-run after a failed one finds the visit's demand again.
SOARGS=(--visit v-x --subject item-x --outcome "cut-short — need input" --ruled no --still-owed "still need X")
run_so SO_DEMAND=0 SO_VISIT_DEMAND=1 SO_HELM_DEMAND_RC=4
eq "$SO_RC" "1" "a re-state that does not land exits 1"
lacks "…before the visit's demand is closed" 'gate resolve d-v' "$SOGC" \
      "the visit demand was closed although the wait never re-stated on the subject"
SO_KEEP=1
run_so SO_DEMAND=0 SO_VISIT_DEMAND=1
SO_KEEP=0
eq "$SO_RC" "0" "the re-run against the same store signs off"
have "…re-stating the wait on the subject" 'helm[RIG] demand item-x still need X --by converse' "$SOLOG"
have "…and only then closing the visit's demand" 'gate resolve d-v' "$SOGC"
run_so SO_DEMAND=0 SO_VISIT_DEMAND=1 SO_GATE_RC=1 SO_CLOSE_RC=1 SO_STUCK=d-v
eq "$SO_RC" "1" "a visit demand that does not close exits 1"
have "…with the wait already re-stated on the subject" 'helm[RIG] demand item-x still need X --by converse' "$SOLOG"
lacks "…and no moved-wait note on the demand that did not close" 'takeaway d-v cut short' "$SOLOG" \
      "the moved-wait note settled a demand that still gates the visit"

echo "── a ruling reads the subject's lifecycle state before it writes ──"
SOARGS=(--visit v-x --subject item-x --outcome "settled — done" --ruled yes --no-wait --ruling approved --route human)
run_so STUB_STATE_RC=2
eq "$SO_RC" "1" "an unreadable lifecycle state exits 1"
no_writes "…and writes nothing, since it cannot say whether to release"
run_so STUB_STATE_RC=1
eq "$SO_RC" "0" "a state lifecycle.sh refuses for another reason answers as not held"
lacks "…so nothing is released" 'lc transition' "$SOLOG" "a subject whose state was refused was released"

echo "── the exit contract is stated, and the settle step obeys it ──"
have "the sign-off states what each exit means" 'Exit: 0 the trace is written and the hold discharged' "$SIGNOFF_SUT"
have "…and that exit 1 forbids the sign-off" 'do NOT post the sign-off or close the visit' "$SIGNOFF_SUT"
have "the settle step runs the sign-off as an if condition" 'if VISIT="$VISIT" SUBJECT="$SUBJECT" "$CONV/converse-signoff.sh"' "$SK_SETTLE"
have "…and stops without signing off when it fails" 'NOT signed off: a read failed, a demand did not close' "$SK_SETTLE"

echo
echo "converse-signoff: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
