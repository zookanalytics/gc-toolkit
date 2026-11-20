#!/usr/bin/env bash
# Hermetic test: a conversation on an open PR holds the PR's merge until it
# closes, and otherwise blocks nothing.
#
# A conversation whose subject is an open PR's anchor, or a bead whose
# anchor_bead names one, holds the PR's merge through a plain dependency: the
# anchor depends on the conversation through bd's blocks edge (gc-helm.sh open,
# engage, and the converse hold step). bd lifts the block once the conversation
# closes, so no close path writes a release.
#
# Runs the REAL gc-helm.sh (as `sh`, as shipped) for open and dismiss, the REAL
# converse-signoff.sh, the close block of skills/converse-recheck-premise and the
# hold and lift blocks of skills/converse-hold as the skills write them, and the
# REAL gctk, built from this checkout, for `gctk pr status` and
# `gctk bead holds`, over the compiled fake gc of test-harness.sh. No live
# city, Dolt, network or sessions. Covered:
#   (OPEN-ANCHOR)  opening a conversation on an open PR's anchor makes the anchor
#                  depend on the conversation and files no gate, and the PR then
#                  derives needs-attention with held: blocked, naming the
#                  conversation
#   (OPEN-JOIN)    a second concern joins the queued conversation, which still
#                  holds the merge through one edge
#   (OPEN-REVIEW)  opening one on the PR's review makes the anchor depend on it,
#                  and leaves the review itself free to dispatch
#   (SIGNOFF, DISMISS, MOOT, BARE-CLOSE) every close of the conversation, the
#                  sign-off, dismiss, the premise re-check's moot close and a
#                  bare `gc bd close`, frees the merge, with no write to the edge
#   (MOOT)         a moot close whose reading runs past the headline's cap
#                  closes the conversation: the close reason and the subject's
#                  notes keep the reading whole, and the headline it writes is
#                  the reading's short sentence
#   (REVIEW-RULING) a ruling in a conversation on the PR's review reaches the PR
#                  whose merge it holds, and its rework is filed against the
#                  anchor and lands before the conversation's close
#   (ANSWER-REWORK) a ruling on a turn that does not sign off files that rework
#                  at once, while the conversation and its hold stay open, and the
#                  rework is free to dispatch
#   (SIGNOFF-RETIRE) a sign-off carrying --retire retires the PR before the close
#   (CLOSE-FAIL)   a close the store refuses both ways leaves the conversation
#                  open, so the merge stays held
#   (LIFT)         a sitting's lift removes the edge and records why on the
#                  conversation, and the PR reads what it did before
#   (HOLD-STEP)    a PR that opened after its conversation started is held from
#                  the hold step's add on
#   (NOT-PR)       a subject that is no open PR, one whose anchor has merged, a
#                  pre-open anchor and a review of one each take no edge
#   (OPEN-UNREAD)  an anchor that does not read files nothing
#   (HOLD-FAIL)    an edge the store refuses exits 4 naming the repair, the reply
#                  onto a gate open was pointed at is written all the same, and
#                  a re-run of open holds the merge
#   (REPLY-FAIL)   a reply onto the gate that the store refuses, for a
#                  conversation open files through a human gate on an open PR
#                  or joins in the queue, exits 4 with the merge held, and the
#                  PR stays held once the gate is answered elsewhere
#   (SAVE-AGAIN)   the conversation form's save again (--conversation) after a
#                  save whose reply the store refused completes the reply and
#                  files nothing. Once a sitting has taken the conversation, it
#                  leaves the hold as that sitting left it: lifted, the PR is
#                  free to merge once the gate is answered; kept, it stays held.
#                  One still in the queue, whose hold the store refused, takes
#                  the hold
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-conversation-merge-hold-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# The shared harness: the compiled fake gc over one store, and gctk built from
# this checkout, which GCTK_BIN pins for the scripts and the reads below.
# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"
harness_build_gctk
harness_init
GCTK="$GCTK_BIN"
mkdir -p "$TMP/rig" "$TMP/cwd" "$TMP/pack/assets/scripts"
STUB_RIGS="$TMP/rigs.json"
printf '{"rigs":[{"name":"gc-toolkit","prefix":"tk","path":"%s","hq":false}]}\n' "$TMP/rig" > "$STUB_RIGS"
export STUB_RIGS

# gh answers nothing, so no call reaches a network.
printf '#!/bin/sh\nexit 1\n' > "$BIN/gh"

# --- the pack the sign-off and the premise re-check run from --------------------
# The real scripts these writers are, linked beside the stand-ins for the PR's
# rework, its retirement and the visit's PR comment, which log what they do to
# the fake's call log. The converse-rework.sh stand-in files a task that blocks
# the anchor, as the ask `gctk review ask` files does, and pr-dispose.sh
# records the disposition.
P="$TMP/pack/assets/scripts"
cat > "$P/converse-rework.sh" <<'R'
#!/usr/bin/env bash
printf 'converse-rework %s\n' "$*" >> "$CALLS"
_a=""; _p=""; for a in "$@"; do [ "$_p" = "--anchor" ] && _a="$a"; _p="$a"; done
_c=$(gc bd create -t task --title "rework $_a" --metadata "{\"task_kind\":\"rework\",\"anchor_bead\":\"$_a\"}" --json)
_c=${_c#*\"id\":\"}; _c=${_c%%\"*}
gc bd dep add "$_a" "$_c" --type blocks >/dev/null
echo "$_c ask filed"
R
cat > "$P/pr-dispose.sh" <<'D'
#!/usr/bin/env bash
printf 'pr-dispose %s\n' "$*" >> "$CALLS"
_a=""; _k=""; _p=""; for a in "$@"; do [ "$_p" = "--anchor" ] && _a="$a"; [ "$_p" = "--kind" ] && _k="$a"; _p="$a"; done
gc bd update "$_a" --set-metadata "gc.pr_close_disposition_kind=$_k" >/dev/null
echo "pr-dispose: closed the PR of $_a as $_k"
D
cat > "$P/pr-sitting-comment.sh" <<'C'
#!/usr/bin/env bash
printf 'pr-sitting-comment %s\n' "$*" >> "$CALLS"
C
chmod +x "$P"/*.sh
for _s in converse-signoff.sh gc-helm.sh human-gate.sh conversation.sh work-outcome.sh bd-lib.sh \
          review-verdict.sh review-dismissal.sh bead-store.sh rig-map.sh dispatch-path.sh; do
    ln -s "$HERE/$_s" "$P/$_s"
done

CALLS="$STUB_GC_LOG"
export CALLS GC_SITTING_COMMENT_TOOL="$P/pr-sitting-comment.sh" TMPDIR="$TMP"

# --- fixtures -----------------------------------------------------------------
# A bead's edge is a dep row: `edge <id> <type> <on>` is <id>'s edge onto <on>.
fresh() { store '[]'; : > "$STUB_DEPS"; echo '[]' > "$STUB_COMMENTS"; : > "$CALLS"; }
# bead <id> [type] [status] [metadata-json]
bead() {
    brow "$1" "title=the bead $1" description= notes= "issue_type=${2:-task}" "status=${3:-open}" assignee= \
        created_at=2026-11-08T00:00:00Z "metadata:=${4:-"{}"}"
}
setf() { bset "$1" "$2=$3"; }
setm() { bset "$1" "metadata.$2=$3"; }
edge() {
    if [ "$2" = blocks ]; then printf '%s|blocks|%s\n' "$3" "$1" >> "$STUB_DEPS"
    else printf '%s|%s|%s\n' "$1" "$2" "$3" >> "$STUB_DEPS"; fi
}
field() { local v; v=$(bfield "$1" "$2"); [ "$v" = "<absent>" ] || printf '%s' "$v"; }
deps_of() { bedges "$1" "$2"; }
acts() { local a; a=$(bcomments "$1"); printf '%s' "${a//$'\n'/|}"; }
# An open PR's anchor, and the PR's review in flight.
pr() { fresh; bead tk-anc task blocked '{"merge_result":"pull_request_pending","pr_number":"41"}'; }
pr_review() { pr; bead tk-rev task open '{"task_kind":"review","anchor_bead":"tk-anc"}'; }
# gate_on <bead> <gate> — an open human gate the bead waits on.
gate_on() {
    brow "$2" "title=should this land as built?" description= notes= issue_type=gate status=open assignee= \
        created_at=2026-11-08T00:00:00Z 'metadata:={}' await_type=human "await_id=review-needs-you.$2"
    edge "$1" blocks "$2"
}
# filed_on <bead> — the conversation that tracks the bead, read from the store.
filed_on() { local c; c=$(bonto "$1" tracks); printf '%s' "${c%% *}"; }
# conversations_on <bead> — every conversation that tracks the bead, read from
# the store, sorted and space-separated.
conversations_on() { bonto "$1" tracks; }
derive() { (cd "$TMP/cwd" && "$GCTK" pr status "$1" --json 2>/dev/null) || echo "derive-failed"; }
# held_of <bead> — the held: values the PR derives, bracketed.
held_of() { local s; s=$(status_of "$1"); printf '%s' "${s#* }"; }
status_of() { local d; d=$(derive "$1"); printf '%s [%s]' "$(json_get "$d" status)" "$(json_get_strs "$d" held)"; }
# holds_of <bead> — what holds the bead by gctk bead holds, the rule the work
# gate at load-context and every reader of a bead's waits share: its status,
# then the waits of its own that have not landed.
holds_of() {
    local h
    h=$(cd "$TMP/cwd" && "$GCTK" bead holds "$1" 2>/dev/null) || { echo "holds-failed"; return 0; }
    printf '%s %s' "$(json_get "$h" status)" "$(json_get_ids "$h" pending)"
}
# writes — the calls since the last reset that write: the fake logs every call,
# and the stand-ins log what they do.
writes() { grep -E '^(bd (create|update|close|comment|dep (add|remove)|gate resolve)|converse-rework|pr-dispose|pr-sitting-comment|runtime drain-ack)' "$CALLS" || true; }
# no_release — the calls since the last reset wrote nothing to the edge or to a
# gate: no dep remove, no gate write.
no_release() { ! grep -qE '^bd dep remove |^bd gate resolve ' "$CALLS"; }
# run_open <args...> -> RC, OUT (stdout), ERR (stderr)
run_open() {
    set +e
    OUT="$(cd "$TMP/cwd" && sh "$HERE/gc-helm.sh" open "$@" 2>"$TMP/err")"; RC=$?
    ERR="$(cat "$TMP/err")"
    set -e
}
opened_conv() { json_get "$OUT" conversation; }
run_signoff() {
    set +e
    OUT="$(cd "$TMP/cwd" && bash "$P/converse-signoff.sh" "$@" 2>&1)"; RC=$?
    set -e
}
run_dismiss() {
    set +e
    OUT="$(cd "$TMP/cwd" && sh "$HERE/gc-helm.sh" dismiss "$@" 2>&1)"; RC=$?
    set -e
}
# skill_block <skill> <marker> — the fenced bash block of the skill that holds
# <marker>, as the skill writes it.
skill_block() {
    awk -v m="$2" '/^```bash[ \t]*$/ { inb = 1; buf = ""; hit = 0; next }
         inb && /^```[ \t]*$/ { if (hit) { printf "%s", buf; exit } inb = 0; next }
         inb { buf = buf $0 "\n"; if (index($0, m)) hit = 1 }' "$ROOT/skills/$1/SKILL.md"
}
# The premise re-check's close, a moot reading filled in for its placeholders.
# A reading that states the premise and what is true instead runs past the
# headline's cap, TAKEAWAY_MAX in gc-helm.sh, so only its short sentence fits
# the headline.
MOOT_WHY="the conversation asked whether the PR should land as built, and the operator has since answered that on GitHub, so the merge it holds waits on no person and nothing is left to ask"
MOOT_HEADLINE="the PR it asked about was answered on GitHub"
skill_block converse-recheck-premise 'closed $CONVERSATION as $KIND' \
    | sed -e 's#KIND="<moot|benign>"#KIND="moot"#' \
          -e "s#WHY=\"<[^>]*>\"#WHY=\"$MOOT_WHY\"#" \
          -e "s#HEADLINE=\"<[^>]*>\"#HEADLINE=\"$MOOT_HEADLINE\"#" \
          -e 's#ACTION="<[^>]*>"#ACTION="The visit ended: its question was already answered."#' > "$TMP/moot-close.sh"
[ -s "$TMP/moot-close.sh" ] && ok "the premise re-check's close is found in the skill" \
    || bad "the premise re-check's close is found in the skill"
# The hold step's add and its lift, the anchor filled in.
skill_block converse-hold 'gc bd dep add "$ANCHOR" "$CONVERSATION" --type blocks' \
    | sed -e 's#ANCHOR="<[^>]*>"#ANCHOR="tk-anc"#' > "$TMP/hold-add.sh"
skill_block converse-hold 'gc bd dep remove "$ANCHOR" "$CONVERSATION"' \
    | sed -e 's#ANCHOR="<[^>]*>"#ANCHOR="tk-anc"#' \
          -e 's#WHY="<[^>]*>"#WHY="the operator opened this to get the PR merged"#' > "$TMP/hold-lift.sh"
[ -s "$TMP/hold-add.sh" ] && [ -s "$TMP/hold-lift.sh" ] && ok "the hold step's add and lift are found in the skill" \
    || bad "the hold step's add and lift are found in the skill"
run_block() { # <file> <conversation> <subject>
    set +e
    OUT="$(cd "$TMP/cwd" && CONV="$P" CONVERSATION="$2" SUBJECT="$3" bash "$1" 2>&1)"; RC=$?
    set -e
}
# lands_before <a> <b> — the first call in $CALLS that carries <a> was made
# before the first that carries <b>, and both were made.
lands_before() {
    _la=$(grep -n -F -- "$1" "$CALLS" | head -1 | cut -d: -f1)
    _lb=$(grep -n -F -- "$2" "$CALLS" | head -1 | cut -d: -f1)
    [ -n "$_la" ] && [ -n "$_lb" ] && [ "$_la" -lt "$_lb" ]
}
# rework_of <anchor> — the rework the stand-in filed against the anchor.
rework_of() { local r; r=$(bids metadata.task_kind=rework "metadata.anchor_bead=$1"); printf '%s' "${r%%$'\n'*}"; }

echo "# opening a conversation on an open PR's anchor holds the PR's merge"
pr
# The status a fresh PR derives before any conversation, which each case below
# returns to once its conversation lets the merge go.
BASE=$(status_of tk-anc)
eq "${BASE#* }" "[]" "(OPEN-ANCHOR) before any conversation, nothing holds the PR"
run_open tk-anc --reason "should this land as built?" --json
C=$(opened_conv)
eq "$RC" 0 "(OPEN-ANCHOR) open exits 0"
eq "$(deps_of tk-anc blocks)" "$C" "(OPEN-ANCHOR) the anchor depends on the conversation through a blocks edge"
eq "$(deps_of "$C" tracks)" "tk-anc" "(OPEN-ANCHOR) …and the conversation tracks the anchor, its subject"
hasnt "$(cat "$CALLS")" "bd gate" "(OPEN-ANCHOR) …and no gate is filed"
has "$ERR" "conversation $C holds the merge of the PR of tk-anc until it closes" "(OPEN-ANCHOR) open says the conversation holds the merge"
D=$(derive tk-anc)
eq "$(json_get "$D" status) [$(json_get_strs "$D" held)] $(json_get_ids "$D" reasons)" "needs-attention [blocked] $C" \
    "(OPEN-ANCHOR) gctk pr status then reads needs-attention with held: blocked, naming the conversation"
eq "$(holds_of tk-anc)" "blocked $C" "(OPEN-ANCHOR) …and gctk bead holds reads the anchor blocked by the conversation"

echo "# a second concern joins the queued conversation, which still holds the merge"
: > "$CALLS"
run_open tk-anc --reason "and the docs?"
eq "$RC" 0 "(OPEN-JOIN) the second open exits 0"
has "$OUT" "conversation $C is already open for tk-anc" "(OPEN-JOIN) …joining the queued conversation"
eq "$(deps_of tk-anc blocks)" "$C" "(OPEN-JOIN) …and one edge still holds the anchor"

echo "# the sign-off closes the conversation, and the close frees the merge"
: > "$CALLS"
run_signoff --conversation "$C" --outcome "lands as built" --ruled yes --ruling "it lands as built" --no-wait --no-rework
eq "$RC" 0 "(SIGNOFF) the sign-off exits 0"
eq "$(field "$C" status)" "closed" "(SIGNOFF) the conversation is closed"
no_release && ok "(SIGNOFF) …and nothing is written to release the merge" \
    || bad "(SIGNOFF) …and nothing is written to release the merge ($(tr '\n' ';' < "$CALLS"))"
eq "$(status_of tk-anc)" "$BASE" "(SIGNOFF) the PR derives what it did before the conversation opened"
eq "$(holds_of tk-anc)" "clear " "(SIGNOFF) …and nothing holds the anchor, though the edge onto the closed conversation stays"

echo "# an open PR on the pending record is held the same way, blocked or open"
for rec in "pull_request_pending blocked" "pull_request_head_changed open"; do
    set -- $rec
    fresh; bead tk-anc task "$2" "{\"merge_result\":\"$1\",\"pr_number\":\"41\"}"
    run_open tk-anc --reason "should this land as built?" --json
    C=$(opened_conv)
    eq "$RC" 0 "(OPEN-RECORD) $1: open exits 0"
    eq "$(deps_of tk-anc blocks)" "$C" "(OPEN-RECORD) $1: the anchor depends on the conversation through a blocks edge"
    has "$ERR" "conversation $C holds the merge of the PR of tk-anc until it closes" "(OPEN-RECORD) $1: open says the conversation holds the merge"
done

echo "# dismiss closes the conversation, and the close frees the merge"
pr; run_open tk-anc --json; C=$(opened_conv)
: > "$CALLS"
run_dismiss "$C" --reason "done here"
eq "$RC" 0 "(DISMISS) dismiss exits 0"
eq "$(field "$C" status)" "closed" "(DISMISS) the conversation is closed"
no_release && ok "(DISMISS) …with nothing written to release the merge" \
    || bad "(DISMISS) …with nothing written to release the merge ($(tr '\n' ';' < "$CALLS"))"
eq "$(status_of tk-anc)" "$BASE" "(DISMISS) the PR derives what it did before the conversation opened"

echo "# the premise re-check's moot close frees the merge, and the conversation keeps no headline"
pr; run_open tk-anc --json; C=$(opened_conv)
setm tk-anc gc.takeaway "holding — should this land as built?"
: > "$CALLS"
run_block "$TMP/moot-close.sh" "$C" tk-anc
eq "$RC" 0 "(MOOT) the moot close exits 0"
has "$OUT" "closed $C as moot" "(MOOT) …closing the conversation"
has "$OUT" "replaced the headline of tk-anc, which waited on nothing" "(MOOT) …and the conversation, about to close, kept no headline"
eq "$(meta tk-anc gc.takeaway)" "moot: $MOOT_HEADLINE" "(MOOT) …the headline it wrote is the reading's short sentence"
eq "$(field "$C" close_reason)" "moot: $MOOT_WHY" "(MOOT) …while the conversation's close reason keeps the whole reading"
has "$(field tk-anc notes)" "moot (conversation $C): $MOOT_WHY" "(MOOT) …and so do the subject's notes"
no_release && ok "(MOOT) …with nothing written to release the merge" \
    || bad "(MOOT) …with nothing written to release the merge ($(tr '\n' ';' < "$CALLS"))"
eq "$(status_of tk-anc)" "$BASE" "(MOOT) the PR derives what it did before the conversation opened"

echo "# a bare close of the conversation frees the merge too"
pr; run_open tk-anc --json; C=$(opened_conv)
gc bd close "$C" --reason "closed by hand" >/dev/null
eq "$(status_of tk-anc)" "$BASE" "(BARE-CLOSE) a gc bd close by hand frees the merge"
eq "$(holds_of tk-anc)" "clear " "(BARE-CLOSE) …and nothing holds the anchor"

echo "# a conversation on the PR's review holds the anchor's merge, and the review goes on"
pr_review
eq "$(held_of tk-anc)" "[]" "(OPEN-REVIEW) with its review in flight, nothing holds the PR"
run_open tk-rev --reason "is this review stuck?" --json
C=$(opened_conv)
eq "$RC" 0 "(OPEN-REVIEW) open exits 0"
eq "$(deps_of tk-anc blocks)" "$C" "(OPEN-REVIEW) the anchor the review names depends on the conversation"
eq "$(deps_of "$C" tracks)" "tk-rev" "(OPEN-REVIEW) …which tracks the review"
eq "$(deps_of tk-rev blocks)" "" "(OPEN-REVIEW) the review itself waits on nothing"
eq "$(holds_of tk-rev)" "clear " "(OPEN-REVIEW) …so gctk bead holds reads it clear, and it keeps dispatching"
eq "$(status_of tk-anc)" "needs-attention [blocked]" "(OPEN-REVIEW) the PR reads needs-attention, held: blocked"

echo "# a ruling in a conversation on the PR's review says what it does to the PR"
: > "$CALLS"
run_signoff --conversation "$C" --outcome "sent back" --ruled yes --ruling "fix the retry first" --no-wait
eq "$RC" 2 "(REVIEW-RULING) a ruling that gives no answer for the PR whose merge the conversation holds exits 2"
has "$OUT" "as the PR whose merge this conversation holds" "(REVIEW-RULING) …naming the PR it reaches that way"
eq "$(writes)" "" "(REVIEW-RULING) …writing nothing"
run_signoff --conversation "$C" --outcome "sent back for the retry" --ruled yes --ruling "fix the retry first" --no-wait --rework
eq "$RC" 0 "(REVIEW-RULING) with --rework it exits 0"
has "$(cat "$CALLS")" "converse-rework --anchor tk-anc --ruling-bead $C" "(REVIEW-RULING) the rework is filed against the PR's anchor"
lands_before "converse-rework " "bd close $C " \
    && ok "(REVIEW-RULING) …and lands before the conversation's close, so the merge is never free in between" \
    || bad "(REVIEW-RULING) …and lands before the conversation's close ($(tr '\n' ';' < "$CALLS"))"
RW=$(rework_of tk-anc)
eq "$(field "$C" status)" "closed" "(REVIEW-RULING) the conversation is closed"
eq "$(holds_of tk-anc)" "blocked $RW" "(REVIEW-RULING) the anchor now waits on the rework alone"
eq "$(held_of tk-anc)" "[]" "(REVIEW-RULING) …so nothing holds the PR for a person"

echo "# a ruling on a turn that does not sign off files the rework at once, and the rework goes on"
pr_review
bead tk-q gate open; bset tk-q await_type=human await_id=review-needs-you.tk-q "title=is the retry in scope?"
edge tk-rev blocks tk-q
run_open tk-rev --reason "is the retry in scope?" --json
C=$(opened_conv); edge "$C" replies-to tk-q
: > "$CALLS"
run_signoff --conversation "$C" --answer tk-q --ruling "fix the retry first" \
    --outcome "ruled on the retry; the conversation stays open" --no-wait --rework
eq "$RC" 0 "(ANSWER-REWORK) the answer exits 0"
eq "$(field tk-q status)" "closed" "(ANSWER-REWORK) the gate it names is answered"
has "$(cat "$CALLS")" "converse-rework --anchor tk-anc --ruling-bead $C" "(ANSWER-REWORK) the rework is filed against the PR's anchor at once"
RW=$(rework_of tk-anc)
eq "$(field "$C" status)" "open" "(ANSWER-REWORK) the conversation stays open"
eq "$(holds_of tk-anc)" "blocked $C,$RW" "(ANSWER-REWORK) …so its hold stands beside the rework's"
eq "$(holds_of "$RW")" "clear " "(ANSWER-REWORK) the rework waits on nothing, so it dispatches while the merge waits"
eq "$(holds_of tk-rev)" "clear " "(ANSWER-REWORK) …and so does the review, its question answered"

echo "# a sign-off carrying --retire retires the PR before the conversation closes"
pr; run_open tk-anc --json; C=$(opened_conv)
: > "$CALLS"
run_signoff --conversation "$C" --outcome "will not land" --ruled yes --ruling "the work moved to the new design" --no-wait \
    --retire re-homed --successor tk-new
eq "$RC" 0 "(SIGNOFF-RETIRE) the sign-off exits 0"
lands_before "pr-dispose " "bd close $C " \
    && ok "(SIGNOFF-RETIRE) the PR is retired before the conversation's close" \
    || bad "(SIGNOFF-RETIRE) the PR is retired before the conversation's close ($(tr '\n' ';' < "$CALLS"))"

echo "# a close the store refuses leaves the merge held"
pr; run_open tk-anc --json; C=$(opened_conv)
STUB_CLOSE_FAIL="$C" run_signoff --conversation "$C" --outcome "lands as built" --ruled yes --ruling "it lands as built" --no-wait --no-rework
[ "$RC" -ne 0 ] && ok "(CLOSE-FAIL) a sign-off whose close is refused both ways fails" || bad "(CLOSE-FAIL) a sign-off whose close is refused both ways fails (exit $RC)"
eq "$(field "$C" status)" "open" "(CLOSE-FAIL) the conversation stays open"
eq "$(status_of tk-anc)" "needs-attention [blocked]" "(CLOSE-FAIL) …so the merge stays held"
STUB_CLOSE_FAIL="$C" run_block "$TMP/moot-close.sh" "$C" tk-anc
hasnt "$OUT" "closed $C as moot" "(CLOSE-FAIL) a moot close the store refuses stops short of its closed line"
eq "$(status_of tk-anc)" "needs-attention [blocked]" "(CLOSE-FAIL) …and the merge stays held"

echo "# a sitting that is helping the PR land lifts the hold"
pr; run_open tk-anc --json; C=$(opened_conv)
: > "$CALLS"
run_block "$TMP/hold-lift.sh" "$C" tk-anc
eq "$RC" 0 "(LIFT) the lift exits 0"
has "$OUT" "the merge of tk-anc no longer waits for this conversation" "(LIFT) …saying the merge no longer waits"
eq "$(deps_of tk-anc blocks)" "" "(LIFT) the anchor's edge onto the conversation is gone"
eq "$(acts "$C")" "Lifted the hold on the PR's merge: the operator opened this to get the PR merged" "(LIFT) …and the conversation records why, among the visit's actions"
eq "$(field "$C" status)" "open" "(LIFT) the conversation stays open"
eq "$(status_of tk-anc)" "$BASE" "(LIFT) the PR reads what it did before the conversation opened"
run_block "$TMP/hold-lift.sh" "$C" tk-anc
eq "$RC" 0 "(LIFT) a second lift, with no edge left to remove, still exits 0"

echo "# a PR that opened after its conversation started is held from the hold step on"
fresh; bead tk-anc task open '{}'
run_open tk-anc --json; C=$(opened_conv)
eq "$(deps_of tk-anc blocks)" "" "(HOLD-STEP) a conversation on a pre-open anchor takes no edge, which would stop the work"
bset tk-anc status=blocked metadata.merge_result=pull_request_pending metadata.pr_number=41
run_block "$TMP/hold-add.sh" "$C" tk-anc
eq "$RC" 0 "(HOLD-STEP) the hold step's add exits 0 once the PR has opened"
has "$OUT" "the merge of tk-anc waits for this conversation" "(HOLD-STEP) …saying the merge waits"
eq "$(deps_of tk-anc blocks)" "$C" "(HOLD-STEP) the anchor now depends on the conversation"
run_block "$TMP/hold-add.sh" "$C" tk-anc
eq "$RC/$(deps_of tk-anc blocks)" "0/$C" "(HOLD-STEP) a second hold adds no second edge"
eq "$(status_of tk-anc)" "needs-attention [blocked]" "(HOLD-STEP) the PR reads needs-attention, held: blocked"

echo "# a subject that is no open PR takes no edge"
fresh; bead tk-plain
run_open tk-plain --json
eq "$RC" 0 "(NOT-PR) a plain subject's conversation is filed"
hasnt "$(writes)" "--type blocks" "(NOT-PR) …and nothing is added for a merge"
fresh; bead tk-anc task closed '{"merge_result":"merged"}'; bead tk-rev task open '{"task_kind":"review","anchor_bead":"tk-anc"}'
run_open tk-rev --json
eq "$RC" 0 "(NOT-PR) a conversation on the review of a merged PR is filed"
hasnt "$(writes)" "--type blocks" "(NOT-PR) …and takes no edge"
fresh; bead tk-anc task open '{}'; bead tk-rev task open '{"task_kind":"review","anchor_bead":"tk-anc"}'
run_open tk-rev --json
hasnt "$(writes)" "--type blocks" "(NOT-PR) a review of a pre-open anchor takes no edge either"

echo "# an anchor that does not read files nothing"
pr_review
STUB_SHOW_FAIL_ON=tk-anc run_open tk-rev --json
eq "$RC" 4 "(OPEN-UNREAD) an anchor that does not read exits 4"
has "$ERR" "could not read tk-anc, the anchor tk-rev names" "(OPEN-UNREAD) …saying so"
hasnt "$(cat "$CALLS")" "bd create" "(OPEN-UNREAD) …and files no conversation"

echo "# an edge the store refuses is reported, and a re-run of open holds the merge"
pr
STUB_DEP_ADD_FAIL_ON="--type blocks" run_open tk-anc --json
eq "$RC" 4 "(HOLD-FAIL) an edge the store refuses exits 4"
C=$(filed_on tk-anc)
[ -n "$C" ] && ok "(HOLD-FAIL) …with the conversation filed" || bad "(HOLD-FAIL) …with the conversation filed"
has "$ERR" "gc bd dep add tk-anc $C --type blocks" "(HOLD-FAIL) …naming the edge to add by hand"
eq "$(deps_of tk-anc blocks)" "" "(HOLD-FAIL) …and no edge holds the anchor yet"
run_open tk-anc --json
eq "$RC/$(deps_of tk-anc blocks)" "0/$C" "(HOLD-FAIL) a re-run of open joins that conversation and holds the merge"
pr; gate_on tk-anc tk-q
STUB_DEP_ADD_FAIL_ON="--type blocks" run_open tk-q --json
eq "$RC" 4 "(HOLD-FAIL) an edge the store refuses on a conversation open files through a gate exits 4"
C=$(filed_on tk-anc)
has "$ERR" "gc bd dep add tk-anc $C --type blocks" "(HOLD-FAIL) …naming the edge to add by hand"
eq "$(deps_of "$C" replies-to)" "tk-q" "(HOLD-FAIL) …and the conversation replies to the gate all the same"

echo "# a reply onto the gate that the store refuses leaves the merge held"
pr; gate_on tk-anc tk-q
STUB_DEP_ADD_FAIL_ON="--type replies-to" run_open tk-q --json
eq "$RC" 4 "(REPLY-FAIL) open through a gate whose reply the store refuses exits 4"
C=$(filed_on tk-anc)
[ -n "$C" ] && ok "(REPLY-FAIL) …with the conversation filed on the bead the gate holds" \
    || bad "(REPLY-FAIL) …with the conversation filed on the bead the gate holds"
has "$ERR" "gc bd dep add $C tk-q --type replies-to" "(REPLY-FAIL) …naming the reply to add by hand"
eq "$(deps_of tk-anc blocks)" "$C tk-q" "(REPLY-FAIL) the anchor depends on the conversation all the same"
lands_before "bd dep add tk-anc $C --type blocks" "bd dep add $C tk-q --type replies-to" \
    && ok "(REPLY-FAIL) …through a hold written before the reply" \
    || bad "(REPLY-FAIL) …through a hold written before the reply ($(tr '\n' ';' < "$CALLS"))"
gc bd gate resolve tk-q --reason "answered in another sitting" >/dev/null
eq "$(status_of tk-anc)" "needs-attention [blocked]" "(REPLY-FAIL) once another sitting answers the gate, the PR stays held"
eq "$(holds_of tk-anc)" "blocked $C" "(REPLY-FAIL) …by the conversation, which is still open"
# A conversation filed before its PR opened holds no merge until open joins it.
fresh; bead tk-anc task open '{}'
run_open tk-anc --json; C=$(opened_conv)
bset tk-anc status=blocked metadata.merge_result=pull_request_pending metadata.pr_number=41; gate_on tk-anc tk-q
: > "$CALLS"
STUB_DEP_ADD_FAIL_ON="--type replies-to" run_open tk-q --reason "and should it wait for the gate?" --json
eq "$RC" 4 "(REPLY-FAIL) joining a queued conversation through a gate whose reply the store refuses exits 4"
has "$ERR" "conversation $C waits in the queue for tk-anc, but the store refused its reply onto gate tk-q" \
    "(REPLY-FAIL) …saying the joined conversation's reply was refused"
hasnt "$(cat "$CALLS")" "bd create" "(REPLY-FAIL) …filing no second conversation"
eq "$(deps_of tk-anc blocks)" "$C tk-q" "(REPLY-FAIL) the conversation it joined holds the merge all the same"
gc bd gate resolve tk-q --reason "answered in another sitting" >/dev/null
eq "$(status_of tk-anc)" "needs-attention [blocked]" "(REPLY-FAIL) …so the PR stays held once the gate is answered"

echo "# a save again leaves the hold as the sitting that took the conversation left it"
# The conversation form's save files the question through the gate on the PR as
# a concern of its own, and the store refuses its reply onto the gate.
Q="should the rollout wait for the load test?"
pr; gate_on tk-anc tk-q
STUB_DEP_ADD_FAIL_ON="--type replies-to" run_open tk-q --allow-duplicate --if-subject tk-anc --reason "$Q" --json
eq "$RC" 4 "(SAVE-AGAIN) a save whose reply onto the gate the store refuses exits 4"
C=$(opened_conv)
eq "$(deps_of tk-anc blocks)" "$C tk-q" "(SAVE-AGAIN) …with the conversation filed and holding the merge"
# Another terminal's sitting takes the conversation out of the queue, as
# engage's bind does, and lifts the hold because it is helping the PR land.
gc bd update "$C" --if-assignee human --if-status open --assignee "c-$C" >/dev/null
run_block "$TMP/hold-lift.sh" "$C" tk-anc
eq "$RC/$(deps_of tk-anc blocks)" "0/tk-q" "(SAVE-AGAIN) the sitting that took the conversation lifts the hold"
: > "$CALLS"
run_open tk-q --allow-duplicate --if-subject tk-anc --conversation "$C" --reason "$Q" --json
eq "$RC" 0 "(SAVE-AGAIN) the save again naming the conversation exits 0"
eq "$(opened_conv)" "$C" "(SAVE-AGAIN) …answering that conversation"
eq "$(deps_of "$C" replies-to)" "tk-q" "(SAVE-AGAIN) …which now replies to the gate"
hasnt "$(cat "$CALLS")" "bd create" "(SAVE-AGAIN) …and files no second conversation"
eq "$(conversations_on tk-anc)" "$C" "(SAVE-AGAIN) one conversation tracks the anchor"
eq "$(deps_of tk-anc blocks)" "tk-q" "(SAVE-AGAIN) the anchor does not depend on the conversation again"
hasnt "$(cat "$CALLS")" "bd dep add tk-anc" "(SAVE-AGAIN) …since the save again adds no hold"
has "$ERR" "the sitting c-$C has taken conversation $C out of the queue, so the hold on the merge of the PR of tk-anc stays as that sitting left it" \
    "(SAVE-AGAIN) …which open says"
eq "$(holds_of tk-anc)" "blocked tk-q" "(SAVE-AGAIN) only the gate the conversation answers holds the anchor"
gc bd gate resolve tk-q --reason "answered in the sitting" >/dev/null
eq "$(status_of tk-anc)" "$BASE" "(SAVE-AGAIN) …so once the sitting answers it, the PR is free to merge"
# A sitting that keeps the hold keeps it through the save again.
pr; gate_on tk-anc tk-q
STUB_DEP_ADD_FAIL_ON="--type replies-to" run_open tk-q --allow-duplicate --if-subject tk-anc --reason "$Q" --json
C=$(opened_conv)
gc bd update "$C" --if-assignee human --if-status open --assignee "c-$C" >/dev/null
: > "$CALLS"
run_open tk-q --allow-duplicate --if-subject tk-anc --conversation "$C" --reason "$Q" --json
eq "$RC/$(deps_of "$C" replies-to)" "0/tk-q" "(SAVE-AGAIN) a save again on a conversation whose sitting kept the hold completes the reply"
eq "$(deps_of tk-anc blocks)" "$C tk-q" "(SAVE-AGAIN) …and the conversation still holds the merge"
no_release && ok "(SAVE-AGAIN) …with nothing removed" || bad "(SAVE-AGAIN) …with nothing removed ($(tr '\n' ';' < "$CALLS"))"
# One still in the queue, whose hold the store refused, takes the hold.
pr; gate_on tk-anc tk-q
STUB_DEP_ADD_FAIL_ON="--type blocks" run_open tk-q --allow-duplicate --if-subject tk-anc --reason "$Q" --json
eq "$RC" 4 "(SAVE-AGAIN) a save whose hold the store refuses exits 4"
C=$(opened_conv)
eq "$(deps_of tk-anc blocks)/$(deps_of "$C" replies-to)" "tk-q/tk-q" "(SAVE-AGAIN) …with the reply written and no hold on the merge"
run_open tk-q --allow-duplicate --if-subject tk-anc --conversation "$C" --reason "$Q" --json
eq "$RC" 0 "(SAVE-AGAIN) a save again on the conversation still in the queue exits 0"
eq "$(deps_of tk-anc blocks)" "$C tk-q" "(SAVE-AGAIN) …and holds the merge"
eq "$(conversations_on tk-anc)" "$C" "(SAVE-AGAIN) …on the one conversation"

echo
echo "conversation-merge-hold: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
