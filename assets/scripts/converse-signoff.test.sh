#!/usr/bin/env bash
# Hermetic test for converse-signoff.sh, a sitting's sign-off.
#
# A sitting holds one conversation, a task that tracks its subject and replies
# to each human gate it answers. A ruled sign-off routes the ruling's rework,
# writes the subject's headline, resolves each open gate the conversation
# replies to and reads each back, releases a held subject, closes the
# conversation and updates the PR reminder. A cut-short one writes the headline,
# leaves every gate open and hands the conversation back to the operator's
# queue.
#
# Covered (specs/tk-0ur8r9p/design.md sections 7 and 12):
#   (USAGE, NOT-CONV, UNREAD, SUBJECT) refusals before any write
#   (ONLY-REPLIED) the acceptance case: the sign-off resolves only the gate its
#             conversation replies to, and leaves the recommendation's gate open
#   (ALREADY, EARLIER) a gate cleared before the sign-off, or reached first by
#             another answer, keeps that answer, and the sign-off reports it
#   (SHARED)  a gate about two beads: one resolve releases both, and the record
#             and headline go on the subject alone
#   (EPIC)    a member's gate answered from the epic's sitting
#   (LEAVE)   a gate the ruling leaves owed stays open
#   (UNCLOSED, HEADLINE) a gate that does not close or a headline that does not
#             land stops the sign-off before the conversation closes
#   (HELD)    a held subject is released on a ruling
#   (OPEN-PR, REWORK*, RETIRE*) a ruling on an open PR answers --rework,
#             --no-rework or --retire; the rework or the retirement runs first,
#             and one that fails writes nothing else, so the gate keeps holding
#             the merge
#   (ANSWER*) a ruling on a turn that does not sign off answers only the gates
#             it names, after the same rework or retirement, and leaves the
#             conversation open for the sign-off
#   (CUT-SHORT*) the hand-back is one write guarded on the holder and the
#             status, and a conversation that reads closed, before that write or
#             because a dismiss closed it first, stays closed
#   (RERUN)   a re-run after a sign-off changes nothing
#
# Runs the REAL converse-signoff.sh with a stubbed `gc` on PATH over a
# file-backed store, and stub pack scripts at $GC_RIG_ROOT, from a cwd outside
# any checkout so no real pack script is reached. Whether a gate still holds the
# anchor's merge is read by the REAL finalize-gate.sh over the same store.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/converse-signoff.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-converse-signoff-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 (unexpected '$2' in: $1)" ;; *) ok "$3" ;; esac; }

[ -f "$SCRIPT" ] && ok "converse-signoff.sh present" || bad "converse-signoff.sh missing at $SCRIPT"

mkdir -p "$TMP/bin" "$TMP/store/b" "$TMP/rig/assets/scripts" "$TMP/cwd"

# --- gc stub ------------------------------------------------------------------
# One JSON file per bead under $STORE/b/<id>.json, its edges as deps
# [{type, on}] on the bead the edge starts from. Every write is appended to
# $CALLS. A guarded update whose --if-assignee or --if-status misses exits 13
# and writes nothing, as bd does. Hooks: LIST_DOWN fails `bd list`;
# GATE_STUCK=<gate> makes its resolve change nothing; EARLIER_ANSWER=<reason>
# closes the gate with that reason inside the resolve call, before the
# sign-off's own answer.
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/gc" <<'GC'
B="$STORE/b"
row() { cat "$B/$1.json" 2>/dev/null; }
put() { cat > "$B/$1.json.tmp" && mv "$B/$1.json.tmp" "$B/$1.json"; }
log() { printf '%s\n' "$*" >> "$CALLS"; }
all_ids() { for f in "$B"/*.json; do [ -f "$f" ] && basename "$f" .json; done; }
show_row() { row "$1" | jq -c '. + {dependencies: [ .deps[] | {id: .on, dependency_type: .type} ]} | del(.deps)'; }
list_row() { row "$1" | jq -c '. + {dependencies: [ .deps[] as $d | {issue_id: .id, depends_on_id: $d.on, type: $d.type} ]} | del(.deps)'; }
case "$1 ${2:-}" in
  "bd show")
    if [ -f "$B/$3.json" ]; then jq -c -n --argjson r "$(show_row "$3")" '[$r]'
    else printf '{"error":"no issues found matching the provided IDs"}\n'; exit 1; fi ;;
  "bd list")
    [ -n "${LIST_DOWN:-}" ] && { echo "bd list: data plane down" >&2; exit 1; }
    _id=""; _p=""; for a in "$@"; do [ "$_p" = "--id" ] && _id="$a"; _p="$a"; done
    if [ -n "$_id" ] && [ -f "$B/$_id.json" ]; then jq -c -n --argjson r "$(list_row "$_id")" '[$r]'; else printf '[]\n'; fi ;;
  "bd dep")
    case "$3" in
      list)
        _who="$4"; _ty=""; _up=0; _p=""
        for a in "$@"; do case "$a" in --direction=up) _up=1 ;; esac; [ "$_p" = "--type" ] && _ty="$a"; _p="$a"; done
        if [ "$_up" = 1 ]; then
          for i in $(all_ids); do
            row "$i" | jq -c --arg w "$_who" --arg t "$_ty" 'select(any(.deps[]; .type == $t and .on == $w)) | . + {dependency_type: $t} | del(.deps)'
          done | jq -sc '.'
        else
          for o in $(row "$_who" | jq -r --arg t "$_ty" '.deps[] | select(.type == $t) | .on'); do
            row "$o" | jq -c --arg t "$_ty" '. + {dependency_type: $t} | del(.deps)'
          done | jq -sc '.'
        fi ;;
      *) log "$*" ;;
    esac ;;
  "bd gate")
    _g="$4"; _r=""; _p=""; for a in "$@"; do [ "$_p" = "--reason" ] && _r="$a"; _p="$a"; done
    log "$*"
    [ "${GATE_STUCK:-}" = "$_g" ] && exit 0
    if [ -n "${EARLIER_ANSWER:-}" ] && [ "$(row "$_g" | jq -r .status)" != closed ]; then
      row "$_g" | jq --arg r "$EARLIER_ANSWER" '.status = "closed" | .close_reason = $r' | put "$_g"
    fi
    if [ "$(row "$_g" | jq -r .status)" != closed ]; then
      row "$_g" | jq --arg r "$_r" '.status = "closed" | .close_reason = $r' | put "$_g"
    fi ;;
  "bd close")
    log "$*"
    _id="$3"; _r=""; _force=""; _p=""
    for a in "$@"; do [ "$_p" = "--reason" ] && _r="$a"; [ "$a" = "--force" ] && _force=1; _p="$a"; done
    row "$_id" | jq --arg r "$_r" '.status = "closed" | .close_reason = $r' | put "$_id" ;;
  "bd update")
    log "$*"
    _id="$3"; shift 3
    _r=$(row "$_id")
    _ifa_set=0; _ifa=""; _ifs_set=0; _ifs=""
    _args=("$@")
    _i=0
    while [ "$_i" -lt "${#_args[@]}" ]; do
      [ "${_args[$_i]}" = "--if-assignee" ] && { _ifa_set=1; _ifa="${_args[$((_i + 1))]}"; }
      [ "${_args[$_i]}" = "--if-status" ] && { _ifs_set=1; _ifs="${_args[$((_i + 1))]}"; }
      _i=$((_i + 1))
    done
    if [ "$_ifa_set" = 1 ] && [ "$(printf '%s' "$_r" | jq -r '.assignee // ""')" != "$_ifa" ]; then exit 13; fi
    if [ "$_ifs_set" = 1 ] && [ "$(printf '%s' "$_r" | jq -r '.status // ""')" != "$_ifs" ]; then exit 13; fi
    while [ $# -gt 0 ]; do
      case "$1" in
        --set-metadata) _k="${2%%=*}"; _v="${2#*=}"; _r=$(printf '%s' "$_r" | jq --arg k "$_k" --arg v "$_v" '.metadata[$k] = $v'); shift 2 ;;
        --assignee)     _r=$(printf '%s' "$_r" | jq --arg v "$2" '.assignee = $v'); shift 2 ;;
        --status)       _r=$(printf '%s' "$_r" | jq --arg v "$2" '.status = $v'); shift 2 ;;
        --append-notes) _r=$(printf '%s' "$_r" | jq --arg v "$2" '.notes = ((.notes // "") + $v)'); shift 2 ;;
        *) shift ;;
      esac
    done
    printf '%s' "$_r" | put "$_id" ;;
esac
exit 0
GC
chmod +x "$TMP/bin/gc"

# --- stub pack scripts at the rig root the sign-off searches first ------------
S="$TMP/rig/assets/scripts"
cat > "$S/gc-helm.sh" <<'H'
#!/usr/bin/env bash
printf 'gc-helm %s\n' "$*" >> "$CALLS"
[ "$1" = takeaway ] || exit 0
[ -n "${TAKEAWAY_FAIL:-}" ] && { echo "takeaway refused" >&2; exit 2; }
gc bd update "$2" --set-metadata "gc.takeaway=$3" >/dev/null
H
cat > "$S/lifecycle.sh" <<'L'
#!/usr/bin/env bash
printf 'lifecycle %s\n' "$*" >> "$CALLS"
[ "$1" = state ] && printf '%s\n' "${SUBJECT_LC_STATE:-unanchored}"
exit 0
L
cat > "$S/converse-rework.sh" <<'R'
#!/usr/bin/env bash
printf 'converse-rework %s\n' "$*" >> "$CALLS"
[ -n "${REWORK_FAIL:-}" ] && { echo "rework refused: anchor has no branch"; exit 2; }
echo "tk-child gc-toolkit/gc-toolkit.polecat filed"
R
# RETIRE_FAIL models pr-dispose.sh recording the disposition and then failing
# to close the PR, which leaves it open.
cat > "$S/pr-dispose.sh" <<'D'
#!/usr/bin/env bash
printf 'pr-dispose %s\n' "$*" >> "$CALLS"
_a=""; _k=""; _p=""; for a in "$@"; do [ "$_p" = "--anchor" ] && _a="$a"; [ "$_p" = "--kind" ] && _k="$a"; _p="$a"; done
gc bd update "$_a" --set-metadata "gc.pr_close_disposition_kind=$_k" >/dev/null
[ -n "${RETIRE_FAIL:-}" ] && { echo "pr-dispose: the marker is recorded but 'gh pr close 7' failed and the PR is still OPEN"; exit 1; }
echo "pr-dispose: closed PR#7 as $_k"
D
cat > "$S/pr-sitting-comment.sh" <<'P'
#!/usr/bin/env bash
printf 'pr-sitting-comment %s\n' "$*" >> "$CALLS"
P
chmod +x "$S"/*.sh

export PATH="$TMP/bin:$PATH" STORE="$TMP/store" CALLS="$TMP/calls" GC_RIG_ROOT="$TMP/rig"
unset GC_CITY_PATH 2>/dev/null || true

# --- fixtures -----------------------------------------------------------------
fresh() { rm -rf "$STORE"; mkdir -p "$STORE/b"; : > "$CALLS"; }
# bead <id> [type] [status] [assignee]
bead() {
    jq -n --arg id "$1" --arg t "${2:-task}" --arg s "${3:-open}" --arg a "${4:-}" '{id:$id, title:("the bead " + $id), issue_type:$t,
        status:$s, assignee:$a, metadata:{}, deps:[]}' > "$STORE/b/$1.json"
}
# gate <id> <key> — an open human gate.
gate() { bead "$1" gate open ""; jq --arg k "$2" '.await_type = "human" | .await_id = $k' "$STORE/b/$1.json" > "$STORE/b/x" && mv "$STORE/b/x" "$STORE/b/$1.json"; }
edge() { jq --arg t "$2" --arg o "$3" '.deps += [{type:$t, on:$o}]' "$STORE/b/$1.json" > "$STORE/b/x" && mv "$STORE/b/x" "$STORE/b/$1.json"; }
setf() { jq --arg k "$2" --arg v "$3" '.[$k] = $v' "$STORE/b/$1.json" > "$STORE/b/x" && mv "$STORE/b/x" "$STORE/b/$1.json"; }
setm() { jq --arg k "$2" --arg v "$3" '.metadata[$k] = $v' "$STORE/b/$1.json" > "$STORE/b/x" && mv "$STORE/b/x" "$STORE/b/$1.json"; }
field() { jq -r --arg k "$2" '.[$k] // "" | tostring' "$STORE/b/$1.json" 2>/dev/null; }
meta()  { jq -r --arg k "$2" '.metadata[$k] // ""' "$STORE/b/$1.json" 2>/dev/null; }
# conv <id> <subject> [assignee] — a conversation a sitting holds.
conv() { bead "$1" task in_progress "${3:-gc-toolkit/gc-toolkit.$1}"; edge "$1" tracks "$2"; }
# The acceptance case's anchor: a recommendation's gate and a review gate, and
# the conversation that took up the review gate alone.
acceptance() {
    fresh; bead tk-anc
    gate tk-rec first-reaction; edge tk-anc blocks tk-rec
    gate tk-rev review-needs-you.tk-find; edge tk-anc blocks tk-rev
    conv tk-conv tk-anc; edge tk-conv replies-to tk-rev
}
# An open PR whose merge only the conversation's own gate holds, so resolving
# that gate releases the merge.
open_pr() {
    fresh; bead tk-anc; setm tk-anc merge_result pull_request
    gate tk-rev conversation; edge tk-anc blocks tk-rev
    conv tk-conv tk-anc; edge tk-conv replies-to tk-rev
}

# run_signoff <args...> -> RC, OUT (stdout and stderr), from a cwd outside any
# checkout.
run_signoff() {
    set +e
    OUT="$(cd "$TMP/cwd" && bash "$SCRIPT" "$@" 2>&1)"; RC=$?
    set -e
}
writes() { grep -c -v '^lifecycle state' "$CALLS" 2>/dev/null || true; }
# merge_held <bead> — "held" while the real finalize gate refuses the bead, the
# check merge.sh makes for an open human gate before it lands a PR.
merge_held() {
    if (cd "$TMP/cwd" && bash "$HERE/finalize-gate.sh" check "$1" >/dev/null 2>&1); then echo released; else echo held; fi
}
RULED=(--ruled yes --ruling "fix the retry before the merge" --route human --no-wait)
RETIRED=(--ruled yes --ruling "the work moved to the new design" --route human --no-wait)
ANSWERED=(--ruling "fix the retry before the merge" --outcome "ruled on the review; the rollout is still open")

echo "# refusals before any write"
acceptance; run_signoff --outcome x
eq "$RC" 2 "(USAGE) a missing --conversation exits 2"
run_signoff --conversation tk-conv
eq "$RC" 2 "(USAGE) a missing --outcome exits 2"
run_signoff --conversation tk-conv --outcome x --ruled yes --route human
eq "$RC" 2 "(USAGE) --ruled yes without --ruling exits 2"
run_signoff --conversation tk-conv --outcome x --ruled yes --ruling r
eq "$RC" 2 "(USAGE) --ruled yes without --route exits 2"
run_signoff --conversation tk-conv --outcome x --rework
eq "$RC" 2 "(USAGE) --rework without a ruling exits 2"
run_signoff --conversation tk-conv --outcome x --leave tk-rev
eq "$RC" 2 "(USAGE) --leave without a ruling exits 2"
run_signoff --conversation tk-conv --outcome x "${RULED[@]}" --leave tk-rec
eq "$RC" 2 "(USAGE) --leave on a gate the conversation does not reply to exits 2"
eq "$(writes)" 0 "(USAGE) …and nothing is written"
acceptance; run_signoff --conversation tk-anc --outcome x "${RULED[@]}"
eq "$RC" 2 "(NOT-CONV) a bead that is no conversation exits 2"
eq "$(writes)" 0 "(NOT-CONV) …writing nothing"
acceptance; LIST_DOWN=1 run_signoff --conversation tk-conv --outcome x "${RULED[@]}"
eq "$RC" 1 "(UNREAD) a conversation that does not read stops the sign-off"
has "$OUT" "NOT SIGNED OFF" "(UNREAD) …saying not to post the sign-off"
eq "$(writes)" 0 "(UNREAD) …and writes nothing"
acceptance; run_signoff --conversation tk-conv --subject tk-rec --outcome x "${RULED[@]}"
eq "$RC" 2 "(SUBJECT) a --subject other than the bead the conversation tracks exits 2"

echo "# the acceptance case: the sign-off resolves only the gate its conversation replies to"
acceptance
run_signoff --conversation tk-conv --outcome "review settled: fix the retry first" "${RULED[@]}"
eq "$RC" 0 "(ONLY-REPLIED) the sign-off exits 0"
eq "$(field tk-rev status)/$(field tk-rev close_reason)" "closed/ruled: fix the retry before the merge" "(ONLY-REPLIED) the review gate it replies to is resolved with ruled: <ruling>"
eq "$(field tk-rec status)" "open" "(ONLY-REPLIED) the recommendation's gate, which it does not reply to, stays open"
hasnt "$(cat "$CALLS")" "gate resolve tk-rec" "(ONLY-REPLIED) …and is never resolved"
eq "$(meta tk-anc gc.takeaway)" "review settled: fix the retry first" "(ONLY-REPLIED) the subject carries the headline"
eq "$(field tk-conv status)" "closed" "(ONLY-REPLIED) the conversation is closed"
eq "$(field tk-conv close_reason)" "review settled: fix the retry first" "(ONLY-REPLIED) …with the headline as its close reason"
eq "$(meta tk-conv gc.work_outcome)" "no-op" "(ONLY-REPLIED) …and gc.work_outcome=no-op stamped before the close"
has "$OUT" "resolved gate tk-rev" "(ONLY-REPLIED) the resolve is reported"
has "$OUT" "it held tk-anc" "(ONLY-REPLIED) …with the bead it released"
has "$(grep '^pr-sitting-comment' "$CALLS")" "close --sitting tk-conv --subject tk-anc --outcome settled --summary review settled: fix the retry first" "(ONLY-REPLIED) the PR reminder says the sitting settled"
has "$(grep '^pr-sitting-comment' "$CALLS")" "ruling: fix the retry before the merge (released to human)" "(ONLY-REPLIED) …with the ruling among its actions"
case "$(cat "$CALLS")" in
  *"gc-helm takeaway"*"gate resolve tk-rev"*"bd close tk-conv"*"pr-sitting-comment close"*) ok "(ORDER) headline, then the gate, then the close, then the reminder" ;;
  *) bad "(ORDER) the writes ran out of order: $(cat "$CALLS")" ;;
esac
SIGNED="$(cat "$CALLS")"
run_signoff --conversation tk-conv --outcome "review settled: fix the retry first" "${RULED[@]}"
eq "$RC" 0 "(RERUN) a re-run of a finished sign-off exits 0"
has "$OUT" "gate tk-rev was already cleared before this sign-off" "(RERUN) …finding its gate already answered"
eq "$(grep -c '^bd close' "$CALLS")" "$(printf '%s\n' "$SIGNED" | grep -c '^bd close')" "(RERUN) …and closing nothing again"

echo "# an answer that reached the gate first stands"
acceptance; edge tk-conv replies-to tk-rec; jq '.status = "closed" | .close_reason = "ruled: accepted mol-fix accept:0123456789abcdef"' "$STORE/b/tk-rec.json" > "$STORE/b/x" && mv "$STORE/b/x" "$STORE/b/tk-rec.json"
run_signoff --conversation tk-conv --outcome "settled" "${RULED[@]}"
eq "$RC" 0 "(ALREADY) a gate Accept cleared before the sign-off does not stop it"
has "$OUT" 'gate tk-rec was already cleared before this sign-off: "ruled: accepted mol-fix accept:0123456789abcdef"' "(ALREADY) …which reports the gate was already cleared"
eq "$(field tk-rec close_reason)" "ruled: accepted mol-fix accept:0123456789abcdef" "(ALREADY) …and the gate keeps Accept's answer"
acceptance; EARLIER_ANSWER="moot: the finding was withdrawn" run_signoff --conversation tk-conv --outcome "settled" "${RULED[@]}"
eq "$RC" 0 "(EARLIER) an answer that reaches the gate inside the sign-off's resolve exits 0"
has "$OUT" 'another answer reached gate tk-rev first: "moot: the finding was withdrawn"' "(EARLIER) …reporting that answer"
eq "$(field tk-rev close_reason)" "moot: the finding was withdrawn" "(EARLIER) …which stands"

echo "# a gate about two beads: one resolve, one record"
fresh; bead tk-anc; bead tk-kid; gate tk-bc bring-current; edge tk-anc blocks tk-bc; edge tk-kid blocks tk-bc
conv tk-conv tk-anc; edge tk-conv replies-to tk-bc
run_signoff --conversation tk-conv --outcome "merge main in, keep the branch" "${RULED[@]}"
eq "$RC" 0 "(SHARED) the sign-off on the anchor's sitting exits 0"
eq "$(field tk-bc status)" "closed" "(SHARED) the gate is resolved once"
has "$OUT" "it held tk-anc tk-kid" "(SHARED) …releasing both beads, read from its blocks dependents"
eq "$(meta tk-anc gc.takeaway)" "merge main in, keep the branch" "(SHARED) the headline is on the anchor"
eq "$(meta tk-kid gc.takeaway)" "" "(SHARED) …and the child's headline is unchanged"
eq "$(field tk-kid notes)" "" "(SHARED) …as are its notes: it reads the answer in the gate's resolve reason"
hasnt "$(cat "$CALLS")" "update tk-kid" "(SHARED) …the child is never written"

echo "# a member's gate answered from the epic's sitting"
fresh; bead tk-epic epic; bead tk-mem; edge tk-mem parent-child tk-epic; gate tk-mg design-choice; edge tk-mem blocks tk-mg
conv tk-conv tk-epic; edge tk-conv replies-to tk-mg
run_signoff --conversation tk-conv --outcome "the epic takes option B" "${RULED[@]}"
eq "$RC" 0 "(EPIC) the epic's sign-off exits 0"
eq "$(field tk-mg status)" "closed" "(EPIC) the member's gate is resolved"
eq "$(meta tk-epic gc.takeaway)" "the epic takes option B" "(EPIC) the record and headline go on the epic"
hasnt "$(cat "$CALLS")" "update tk-mem" "(EPIC) …and the member is never written"

echo "# a gate the ruling leaves owed stays open"
acceptance; gate tk-two later-question; edge tk-anc blocks tk-two; edge tk-conv replies-to tk-two
run_signoff --conversation tk-conv --outcome "settled the review, not the rollout" "${RULED[@]}" --leave tk-two
eq "$RC" 0 "(LEAVE) a sign-off that leaves one gate exits 0"
eq "$(field tk-rev status)" "closed" "(LEAVE) the gate the ruling answers is resolved"
eq "$(field tk-two status)" "open" "(LEAVE) the gate it leaves stays open"
eq "$(jq -r '[.deps[] | select(.type == "replies-to") | .on] | join(" ")' "$STORE/b/tk-conv.json")" "tk-rev tk-two" "(LEAVE) …and its reply stays"

echo "# a gate that does not close, or a headline that does not land, stops the sign-off"
acceptance; GATE_STUCK=tk-rev run_signoff --conversation tk-conv --outcome "settled" "${RULED[@]}"
eq "$RC" 1 "(UNCLOSED) a gate that does not close exits 1"
eq "$(field tk-conv status)" "in_progress" "(UNCLOSED) …and the conversation stays open for the re-run"
hasnt "$(cat "$CALLS")" "pr-sitting-comment" "(UNCLOSED) …with no reminder update"
acceptance; TAKEAWAY_FAIL=1 run_signoff --conversation tk-conv --outcome "settled" "${RULED[@]}"
eq "$RC" 1 "(HEADLINE) a headline that does not land exits 1"
eq "$(field tk-rev status)" "open" "(HEADLINE) …before any gate is resolved"
eq "$(field tk-conv status)" "in_progress" "(HEADLINE) …or the conversation closed"

echo "# a held subject is released on a ruling"
acceptance; SUBJECT_LC_STATE=held run_signoff --conversation tk-conv --outcome "settled" --ruled yes --ruling "go" --route gc-toolkit/gc-toolkit.polecat --no-wait
eq "$RC" 0 "(HELD) a ruled sign-off on a held subject exits 0"
has "$(cat "$CALLS")" "lifecycle transition tk-anc --to unanchored --route gc-toolkit/gc-toolkit.polecat" "(HELD) …releasing it to its route"

echo "# a ruling on an open PR says whether its branch changes"
acceptance; setm tk-anc merge_result pull_request
run_signoff --conversation tk-conv --outcome "settled" "${RULED[@]}"
eq "$RC" 2 "(OPEN-PR) a ruled sign-off on an open PR with neither --rework nor --no-rework exits 2"
eq "$(writes)" 0 "(OPEN-PR) …writing nothing"
run_signoff --conversation tk-conv --outcome "settled" "${RULED[@]}" --rework
eq "$RC" 0 "(REWORK) --rework exits 0"
has "$(cat "$CALLS")" "converse-rework --anchor tk-anc --ruling-bead tk-conv --ruling fix the retry before the merge" "(REWORK) the rework is filed with the conversation as its source ruling bead"
has "$(grep -v '^lifecycle state' "$CALLS" | head -1)" "converse-rework" "(REWORK) …before every other write"
has "$(grep '^pr-sitting-comment' "$CALLS")" "filed ruling-driven rework on tk-anc" "(REWORK) …and the reminder says so"
acceptance; setm tk-anc merge_result pull_request
REWORK_FAIL=1 run_signoff --conversation tk-conv --outcome "settled" "${RULED[@]}" --rework
eq "$RC" 1 "(REWORK-FAIL) a rework that does not file exits 1"
has "$OUT" "REWORK NOT COMPLETE on tk-anc" "(REWORK-FAIL) …saying so"
hasnt "$(cat "$CALLS")" "gc-helm takeaway" "(REWORK-FAIL) …with no headline written"
eq "$(field tk-rev status)" "open" "(REWORK-FAIL) …no gate resolved"
eq "$(field tk-conv status)" "in_progress" "(REWORK-FAIL) …and the conversation open"
acceptance; setm tk-anc merge_result pull_request
run_signoff --conversation tk-conv --outcome "settled" "${RULED[@]}" --no-rework
eq "$RC" 0 "(NO-REWORK) --no-rework exits 0"
has "$(grep '^pr-sitting-comment' "$CALLS")" "ruling leaves the branch of tk-anc as it stands" "(NO-REWORK) …recording that the branch stands"

echo "# a ruling that the PR will not land retires it before any gate releases the merge"
open_pr
run_signoff --conversation tk-conv --outcome x "${RETIRED[@]}" --retire duplicate
eq "$RC" 2 "(RETIRE-USAGE) --retire duplicate without --successor exits 2"
run_signoff --conversation tk-conv --outcome x "${RETIRED[@]}" --retire abandoned
eq "$RC" 2 "(RETIRE-USAGE) --retire with a kind bead-rehome does not take exits 2"
run_signoff --conversation tk-conv --outcome x "${RETIRED[@]}" --rework --retire not-needed
eq "$RC" 2 "(RETIRE-USAGE) --rework beside --retire exits 2"
run_signoff --conversation tk-conv --outcome x "${RETIRED[@]}" --no-rework --successor tk-new
eq "$RC" 2 "(RETIRE-USAGE) --successor without --retire exits 2"
run_signoff --conversation tk-conv --outcome x --retire not-needed
eq "$RC" 2 "(RETIRE-USAGE) --retire without a ruling exits 2"
eq "$(writes)" 0 "(RETIRE-USAGE) …and nothing is written"
eq "$(merge_held tk-anc)" held "(RETIRE) the conversation's gate holds the open PR's merge before the ruling"
RETIRE_FAIL=1 run_signoff --conversation tk-conv --outcome "retired" "${RETIRED[@]}" --retire not-needed
eq "$RC" 1 "(RETIRE-FAIL) a retirement that leaves the PR open exits 1"
has "$OUT" "RETIREMENT NOT COMPLETE on tk-anc" "(RETIRE-FAIL) …saying so"
has "$OUT" "NOT SIGNED OFF" "(RETIRE-FAIL) …and that the sign-off is not to be posted"
hasnt "$(cat "$CALLS")" "gc-helm takeaway" "(RETIRE-FAIL) …with no headline written"
eq "$(field tk-rev status)" "open" "(RETIRE-FAIL) …no gate resolved"
eq "$(merge_held tk-anc)" held "(RETIRE-FAIL) …so the real finalize gate still holds the open PR's merge"
eq "$(field tk-conv status)" "in_progress" "(RETIRE-FAIL) …and the conversation stays open for the re-run"
: > "$CALLS"
run_signoff --conversation tk-conv --outcome "retired: the work moved" "${RETIRED[@]}" --retire not-needed
eq "$RC" 0 "(RETIRE) the re-run's --retire exits 0"
has "$(cat "$CALLS")" "pr-dispose --anchor tk-anc --successor tk-conv --kind not-needed --note the work moved to the new design" "(RETIRE) the PR is retired as not-needed, with the conversation as the evidence and the ruling as the note"
has "$(grep -v '^lifecycle state' "$CALLS" | head -1)" "pr-dispose" "(RETIRE) …before every other write"
case "$(cat "$CALLS")" in
  *"pr-dispose"*"gate resolve tk-rev"*) ok "(RETIRE) …so the PR is closed before the gate that held its merge is resolved" ;;
  *) bad "(RETIRE) the gate was resolved before the PR was retired: $(cat "$CALLS")" ;;
esac
eq "$(merge_held tk-anc)" released "(RETIRE) the gate releases the merge only after the PR is closed"
eq "$(field tk-conv status)" "closed" "(RETIRE) the conversation is closed"
has "$(grep '^pr-sitting-comment' "$CALLS")" "retired the PR of tk-anc (not-needed, successor tk-conv)" "(RETIRE) …and the reminder says the PR was retired"
open_pr
run_signoff --conversation tk-conv --outcome "retired: a duplicate" "${RETIRED[@]}" --retire duplicate --successor tk-new
eq "$RC" 0 "(RETIRE-SUCCESSOR) --retire duplicate --successor exits 0"
has "$(cat "$CALLS")" "pr-dispose --anchor tk-anc --successor tk-new --kind duplicate" "(RETIRE-SUCCESSOR) …naming the bead that carries the work as the successor"

echo "# a ruling on a turn that does not sign off: the gates it names, after what it does to the PR"
acceptance; gate tk-two later-question; edge tk-anc blocks tk-two; edge tk-conv replies-to tk-two
run_signoff --conversation tk-conv --answer tk-rec "${ANSWERED[@]}"
eq "$RC" 2 "(ANSWER-USAGE) --answer on a gate the conversation does not reply to exits 2"
run_signoff --conversation tk-conv --answer tk-rev --outcome x
eq "$RC" 2 "(ANSWER-USAGE) --answer without --ruling exits 2"
run_signoff --conversation tk-conv --answer tk-rev "${ANSWERED[@]}" --ruled no
eq "$RC" 2 "(ANSWER-USAGE) --answer beside --ruled no exits 2"
run_signoff --conversation tk-conv --answer tk-rev "${ANSWERED[@]}" --route human
eq "$RC" 2 "(ANSWER-USAGE) --answer beside --route exits 2"
run_signoff --conversation tk-conv --answer tk-rev "${ANSWERED[@]}" --leave tk-two
eq "$RC" 2 "(ANSWER-USAGE) --answer beside --leave exits 2"
eq "$(writes)" 0 "(ANSWER-USAGE) …and nothing is written"
run_signoff --conversation tk-conv --answer tk-rev "${ANSWERED[@]}"
eq "$RC" 0 "(ANSWER) an answer on a turn that does not sign off exits 0"
eq "$(field tk-rev status)/$(field tk-rev close_reason)" "closed/ruled: fix the retry before the merge" "(ANSWER) the gate it names is resolved with ruled: <ruling>"
eq "$(field tk-two status)" "open" "(ANSWER) the other gate the conversation replies to stays open"
eq "$(field tk-conv status)/$(field tk-conv assignee)" "in_progress/gc-toolkit/gc-toolkit.tk-conv" "(ANSWER) the conversation stays open under its sitting"
eq "$(meta tk-anc gc.takeaway)" "ruled on the review; the rollout is still open" "(ANSWER) the headline is written"
case "$(cat "$CALLS")" in
  *"gc-helm takeaway"*"gate resolve tk-rev"*) ok "(ANSWER) …before the gate" ;;
  *) bad "(ANSWER) the gate was resolved before the headline: $(cat "$CALLS")" ;;
esac
hasnt "$(cat "$CALLS")" "bd close" "(ANSWER) nothing is closed"
hasnt "$(cat "$CALLS")" "lifecycle" "(ANSWER) …no held subject is read or released"
hasnt "$(cat "$CALLS")" "pr-sitting-comment" "(ANSWER) …and the reminder is left for the sign-off"
has "$OUT" "ANSWERED tk-rev for conversation tk-conv on tk-anc" "(ANSWER) the answer is reported"
run_signoff --conversation tk-conv --outcome "settled" "${RULED[@]}"
eq "$RC" 0 "(ANSWER) the sign-off that follows exits 0"
has "$OUT" "gate tk-rev was already cleared before this sign-off" "(ANSWER) …reading the answered gate as already cleared"
eq "$(field tk-two status)/$(field tk-conv status)" "closed/closed" "(ANSWER) …and answering the gate left open before it closes the conversation"
open_pr
run_signoff --conversation tk-conv --answer tk-rev "${ANSWERED[@]}"
eq "$RC" 2 "(ANSWER-OPEN-PR) an answer on an open PR that says nothing of the PR exits 2"
eq "$(writes)" 0 "(ANSWER-OPEN-PR) …writing nothing"
eq "$(merge_held tk-anc)" held "(ANSWER-OPEN-PR) …so the gate still holds the merge"
REWORK_FAIL=1 run_signoff --conversation tk-conv --answer tk-rev "${ANSWERED[@]}" --rework
eq "$RC" 1 "(ANSWER-REWORK-FAIL) an answer whose rework does not file exits 1"
has "$OUT" "REWORK NOT COMPLETE on tk-anc" "(ANSWER-REWORK-FAIL) …saying so"
has "$OUT" "NOT ANSWERED" "(ANSWER-REWORK-FAIL) …and that the ruling is not carried out"
eq "$(field tk-rev status)" "open" "(ANSWER-REWORK-FAIL) …leaving the gate open"
eq "$(merge_held tk-anc)" held "(ANSWER-REWORK-FAIL) …so the real finalize gate still holds the merge"
: > "$CALLS"
run_signoff --conversation tk-conv --answer tk-rev "${ANSWERED[@]}" --rework
eq "$RC" 0 "(ANSWER-REWORK) the re-run, whose rework files, exits 0"
case "$(cat "$CALLS")" in
  *"converse-rework --anchor tk-anc --ruling-bead tk-conv --ruling fix the retry before the merge"*"gate resolve tk-rev"*) ok "(ANSWER-REWORK) the rework is filed before the gate is resolved" ;;
  *) bad "(ANSWER-REWORK) the gate was resolved before the rework was filed: $(cat "$CALLS")" ;;
esac
eq "$(merge_held tk-anc)" released "(ANSWER-REWORK) …and only then does the gate release the merge"
eq "$(field tk-conv status)" "in_progress" "(ANSWER-REWORK) the conversation stays open"
open_pr
RETIRE_FAIL=1 run_signoff --conversation tk-conv --answer tk-rev --ruling "the work moved" --outcome "retired" --retire not-needed
eq "$RC" 1 "(ANSWER-RETIRE-FAIL) an answer whose retirement leaves the PR open exits 1"
eq "$(field tk-rev status)" "open" "(ANSWER-RETIRE-FAIL) …leaving the gate open"
eq "$(merge_held tk-anc)" held "(ANSWER-RETIRE-FAIL) …so the real finalize gate still holds the merge"
: > "$CALLS"
run_signoff --conversation tk-conv --answer tk-rev --ruling "the work moved" --outcome "retired" --retire not-needed
eq "$RC" 0 "(ANSWER-RETIRE) the re-run, whose retirement completes, exits 0"
case "$(cat "$CALLS")" in
  *"pr-dispose --anchor tk-anc --successor tk-conv --kind not-needed"*"gate resolve tk-rev"*) ok "(ANSWER-RETIRE) the PR is retired before the gate is resolved" ;;
  *) bad "(ANSWER-RETIRE) the gate was resolved before the PR was retired: $(cat "$CALLS")" ;;
esac
eq "$(merge_held tk-anc)" released "(ANSWER-RETIRE) …and only then does the gate release the merge"

echo "# cut short: the conversation goes back to the operator's queue"
acceptance; run_signoff --conversation tk-conv --outcome "cut short: the rollout question is still owed" --ruled no
eq "$RC" 0 "(CUT-SHORT) a cut-short sign-off exits 0"
eq "$(meta tk-anc gc.takeaway)" "cut short: the rollout question is still owed" "(CUT-SHORT) the headline is written"
eq "$(field tk-rev status)" "open" "(CUT-SHORT) the gate stays open and owed"
eq "$(jq -r '[.deps[] | select(.type == "replies-to") | .on] | join(" ")' "$STORE/b/tk-conv.json")" "tk-rev" "(CUT-SHORT) …with its reply in place for the next sitting"
eq "$(field tk-conv assignee)/$(field tk-conv status)" "human/open" "(CUT-SHORT) the conversation is back in the operator's queue"
has "$(cat "$CALLS")" "bd update tk-conv --if-assignee gc-toolkit/gc-toolkit.tk-conv --if-status in_progress --assignee human --status open" "(CUT-SHORT) …by one write guarded on the sitting that held it and the status it read"
hasnt "$(cat "$CALLS")" "bd close" "(CUT-SHORT) …and nothing is closed"
has "$(grep '^pr-sitting-comment' "$CALLS")" "--outcome handed back" "(CUT-SHORT) the reminder says the conversation was handed back"
# The guard misses when another writer reached the conversation first: model it
# by changing the conversation between the sign-off's read and its write. Another
# sitting taking it changes the holder. A dismiss closes it and keeps the
# holder, so only the status guard sees it.
cp "$TMP/bin/gc" "$TMP/bin/gc.real"
cat > "$TMP/bin/gc" <<'G2'
#!/usr/bin/env bash
if [ "$1 $2 $3" = "bd update tk-conv" ]; then
  if [ -n "${STEAL_BEFORE_UPDATE:-}" ]; then
    jq '.assignee = "gc-toolkit/gc-toolkit.c-tk-conv"' "$STORE/b/$3.json" > "$STORE/b/x" && mv "$STORE/b/x" "$STORE/b/$3.json"
  fi
  if [ -n "${DISMISS_BEFORE_UPDATE:-}" ]; then
    jq '.status = "closed" | .close_reason = "dismissed by the operator"' "$STORE/b/$3.json" > "$STORE/b/x" && mv "$STORE/b/x" "$STORE/b/$3.json"
  fi
fi
exec "$(dirname "$0")/gc.real" "$@"
G2
chmod +x "$TMP/bin/gc"
acceptance
STEAL_BEFORE_UPDATE=1 run_signoff --conversation tk-conv --outcome "cut short" --ruled no
eq "$RC" 1 "(CUT-SHORT-RACE) a hand-back whose guard misses exits 1"
eq "$(field tk-conv assignee)" "gc-toolkit/gc-toolkit.c-tk-conv" "(CUT-SHORT-RACE) …overwriting nothing"
acceptance
DISMISS_BEFORE_UPDATE=1 run_signoff --conversation tk-conv --outcome "cut short" --ruled no
eq "$RC" 0 "(CUT-SHORT-DISMISS) a dismiss that lands between the sign-off's read and its hand-back exits 0"
eq "$(field tk-conv status)/$(field tk-conv assignee)" "closed/gc-toolkit/gc-toolkit.tk-conv" "(CUT-SHORT-DISMISS) …and the dismissed conversation stays closed, not reopened into the operator's queue"
has "$OUT" "was closed while this sign-off ran" "(CUT-SHORT-DISMISS) …saying so"
hasnt "$(cat "$CALLS")" "pr-sitting-comment" "(CUT-SHORT-DISMISS) …leaving the reminder the dismiss wrote"
eq "$(field tk-rev status)" "open" "(CUT-SHORT-DISMISS) the gate stays open and owed"
mv "$TMP/bin/gc.real" "$TMP/bin/gc"
# A conversation that already reads closed has ended: a dismiss or an earlier
# sign-off closed it, and bd's close kept its assignee, so the guarded hand-back
# would reopen it into the operator's queue.
acceptance; setf tk-conv status closed
run_signoff --conversation tk-conv --outcome "cut short" --ruled no
eq "$RC" 0 "(CUT-SHORT-CLOSED) a cut-short sign-off on a closed conversation exits 0"
eq "$(field tk-conv status)" "closed" "(CUT-SHORT-CLOSED) …and the conversation stays closed"
hasnt "$(cat "$CALLS")" "bd update tk-conv" "(CUT-SHORT-CLOSED) …with no hand-back written"
hasnt "$(cat "$CALLS")" "pr-sitting-comment" "(CUT-SHORT-CLOSED) …leaving the reminder its closer wrote"
eq "$(field tk-rev status)" "open" "(CUT-SHORT-CLOSED) the gate stays open and owed"

echo
echo "converse-signoff: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
