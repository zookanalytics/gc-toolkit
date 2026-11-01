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
#   (EPIC-PR*, SHARED-PR*, RELEASED-UNREAD) a gate the ruling answers that
#             releases an open PR other than the subject puts that PR's
#             question to the ruling: the rework or the retirement acts on that
#             PR, --pr-anchor names the one it acts on when the ruling reaches
#             more than one, the re-run of an attempt that stopped after
#             resolving the gate acts on the same PR, and a release that does
#             not read stops the sign-off before any write
#   (RECORD*, RETIRED-RERUN*) the PR an answer acts on is recorded on the
#             conversation before it acts, and a re-run of the same ruling acts
#             on that PR even once its retirement has closed it, never falling
#             back to the subject; a re-run that answers differently is not
#             bound by the record
#   (RIG*)    the rework or the retirement runs in the rig of the PR it acts
#             on, its store, pool and checkout, when a gate in another rig's
#             store releases that PR, and a PR whose rig cannot be resolved
#             stops the sign-off before any write
#   (LEAVE)   a gate the ruling leaves owed stays open
#   (UNCLOSED, HEADLINE) a gate that does not close or a headline that does not
#             land stops the sign-off before the conversation closes
#   (HELD, HELD-FAIL) a held subject is released on a ruling, and a release
#             that fails stops the sign-off before the close, so the
#             conversation stays open and its re-run releases the subject
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
#   (TWO-CONV) two conversations on one PR, each holding with a gate of its
#             own: the first ruling resolves only its own gate, so the merge
#             stays held until the second ruling
#   (ACCEPT*) a ruling that takes the subject's recommendation hands its gate
#             to Accept's writer after every other write but the close, never
#             resolving it itself; it is refused before any write when the
#             ruling does not answer that gate, answers a gate under the key
#             that blocks another bead (an epic's member) and not the subject's
#             own, or leaves unanswered a gate Accept would answer, the subject
#             carries no recommendation, or another gate holds the subject; a
#             sign-off
#             releases a held subject before Accept's writer runs, and runs
#             no Accept when that release fails, and an
#             answer leaves a held subject to that writer's own release; a take
#             Accept does not complete stops the sign-off, and an answer that
#             reached the gate first stands; each --var reaches Accept's writer,
#             and one without --accept, or not <key>=<value>, is refused
#   (APPROVE*) a PR a ruling leaves standing with no approval that would land it
#             is named in the headline, the close reason and the reminder, and
#             printed with its link, read before the first write through the
#             rule the merge lands on; a PR the ruling reworks or retires is not
#
# Runs the REAL converse-signoff.sh with a stubbed `gc` on PATH over a
# file-backed store, linked into a stub pack beside the libraries it sources and
# stub pack scripts, from a cwd outside any checkout. The sign-off finds every
# script it runs beside itself, so no real pack script is reached. Whether a gate still holds the
# anchor's merge is read by the REAL finalize-gate.sh over the same store, and
# the rig of a PR the ruling acts on by the REAL bead-store.sh over the stub's
# rig list: rig-a carries the prefix tk and rig-b the prefix rb.
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
# SHOW_DOWN=<id> fails `bd show` of that bead; DEP_UP_DOWN=<gate> fails the
# listing of the beads that wait on that gate; GATE_STUCK=<gate> makes its
# resolve change nothing; CLOSE_STUCK=<id> makes its close change nothing;
# EARLIER_ANSWER=<reason> closes the gate with that reason inside the resolve
# call, before the sign-off's own answer.
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/gc" <<'GC'
B="$STORE/b"
row() { cat "$B/$1.json" 2>/dev/null; }
put() { cat > "$B/$1.json.tmp" && mv "$B/$1.json.tmp" "$B/$1.json"; }
log() { printf '%s\n' "$*" >> "$CALLS"; }
all_ids() { for f in "$B"/*.json; do [ -f "$f" ] && basename "$f" .json; done; }
show_row() { row "$1" | jq -c '. + {dependencies: [ .deps[] | {id: .on, dependency_type: .type} ]} | del(.deps)'; }
list_row() { row "$1" | jq -c '. + {dependencies: [ .deps[] as $d | {issue_id: .id, depends_on_id: $d.on, type: $d.type} ]} | del(.deps)'; }
case "$1 ${2:-}" in
  "rig list")
    jq -n --arg a "$RIG_A" --arg b "$RIG_B" '{rigs: [{name: "rig-a", prefix: "tk", path: $a, hq: false},
                                                    {name: "rig-b", prefix: "rb", path: $b, hq: false}]}' ;;
  "bd show")
    [ -n "${SHOW_DOWN:-}" ] && [ "$3" = "$SHOW_DOWN" ] && { echo "bd show: data plane down" >&2; exit 1; }
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
        [ "$_up" = 1 ] && [ -n "${DEP_UP_DOWN:-}" ] && [ "$_who" = "$DEP_UP_DOWN" ] && { echo "bd dep list: data plane down" >&2; exit 1; }
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
    [ "${CLOSE_STUCK:-}" = "$3" ] && exit 0
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

# --- gh stub ------------------------------------------------------------------
# `api ... user` names the city's login, and a PR's reviews come from
# $STORE/reviews-<n>.json, one value per line as --jq '.[]' prints them. Every
# call is logged to $GH_CALLS with how many writes came before it. GH_DOWN fails
# every call.
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/gh" <<'GH'
printf 'writes=%s %s\n' "$(grep -c -v '^lifecycle state' "$CALLS" 2>/dev/null)" "$*" >> "$GH_CALLS"
[ -n "${GH_DOWN:-}" ] && { echo "gh: network down" >&2; exit 1; }
case "$*" in
  *" user "*) echo city-bot ;;
  *"/pulls/"*"/reviews"*)
    _n=$(printf '%s' "$*" | sed -n 's#.*/pulls/\([0-9][0-9]*\)/reviews.*#\1#p')
    [ -f "$STORE/reviews-$_n.json" ] && jq -c '.[]' "$STORE/reviews-$_n.json" ;;
esac
exit 0
GH
chmod +x "$TMP/bin/gh"

# --- stub pack scripts at the rig root the sign-off searches first ------------
# gc-helm.sh's accept leaves the store as Accept's writer would, per
# ACCEPT_DOES: take (the default) answers each open first-reaction gate on the
# subject with an Accept's answer and records the dispatch; refuse writes
# nothing, as a run refused at the lock does; other finds the gate answered
# first; dispatched finds the recommendation already dispatched.
S="$TMP/rig/assets/scripts"
cat > "$S/gc-helm.sh" <<'H'
#!/usr/bin/env bash
printf 'gc-helm %s\n' "$*" >> "$CALLS"
B="$STORE/b"
case "$1" in
  takeaway)
    [ -n "${TAKEAWAY_FAIL:-}" ] && { echo "takeaway refused" >&2; exit 2; }
    gc bd update "$2" --set-metadata "gc.takeaway=$3" >/dev/null ;;
  accept)
    _s="$2"; _f=$(jq -r '.metadata["gc.recommended_formula"] // ""' "$B/$_s.json")
    _rec=""
    for g in $(jq -r '.deps[] | select(.type == "blocks") | .on' "$B/$_s.json"); do
      jq -e '.await_id == "first-reaction" and .status != "closed"' "$B/$g.json" >/dev/null 2>&1 && _rec="$_rec $g"
    done
    close_rec() { for g in $_rec; do jq --arg r "$1" '.status = "closed" | .close_reason = $r' "$B/$g.json" > "$B/x" && mv "$B/x" "$B/$g.json"; done; }
    case "${ACCEPT_DOES:-take}" in
      refuse) echo "gc-helm.sh: accept: another Accept on $_s holds its acceptance lock (pid 7), so this one refuses and writes nothing." >&2; exit 4 ;;
      other)  close_rec "moot: the reaction withdrew its recommendation"
              echo "gc-helm.sh: accept: another answer reached $_s's recommendation gate first" >&2; exit 4 ;;
      dispatched) echo "gc-helm.sh: accept: $_s carries no gc.recommended_formula: its recommendation was dispatched. Nothing to accept; nothing dispatched." >&2; exit 2 ;;
      *) close_rec "ruled: accepted $_f accept:0123456789abcdef"
         jq --arg f "$_f" '.metadata["gc.recommended_formula_dispatched"] = $f | del(.metadata["gc.recommended_formula"])' "$B/$_s.json" > "$B/x" && mv "$B/x" "$B/$_s.json"
         echo "gc-helm.sh: accept: dispatched $_f at $_s (acceptance 0123456789abcdef)" ;;
    esac ;;
esac
exit 0
H
# TRANSITION_FAIL=<code> makes a transition exit with that code, as the real
# writer exits 1 when bd refuses the write and 2 when it does not read back.
cat > "$S/lifecycle.sh" <<'L'
#!/usr/bin/env bash
printf 'lifecycle %s\n' "$*" >> "$CALLS"
[ "$1" = state ] && printf '%s\n' "${SUBJECT_LC_STATE:-unanchored}"
[ "$1" = transition ] && [ -n "${TRANSITION_FAIL:-}" ] && { echo "lifecycle: the transition did not land" >&2; exit "$TRANSITION_FAIL"; }
exit 0
L
# The rework and the retirement stand-ins each log the rig they ran in: GC_RIG,
# GC_RIG_ROOT and the working directory.
cat > "$S/converse-rework.sh" <<'R'
#!/usr/bin/env bash
printf 'converse-rework %s\n' "$*" >> "$CALLS"
printf 'converse-rework ran in GC_RIG=%s GC_RIG_ROOT=%s PWD=%s\n' "${GC_RIG:-}" "${GC_RIG_ROOT:-}" "$PWD" >> "$CALLS"
[ -n "${REWORK_FAIL:-}" ] && { echo "rework refused: anchor has no branch"; exit 2; }
echo "tk-child gc-toolkit/gc-toolkit.polecat filed"
R
# RETIRE_FAIL models pr-dispose.sh recording the disposition and then failing
# to close the PR, which leaves it open.
cat > "$S/pr-dispose.sh" <<'D'
#!/usr/bin/env bash
printf 'pr-dispose %s\n' "$*" >> "$CALLS"
printf 'pr-dispose ran in GC_RIG=%s GC_RIG_ROOT=%s PWD=%s\n' "${GC_RIG:-}" "${GC_RIG_ROOT:-}" "$PWD" >> "$CALLS"
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
# Linked after the chmod, which would otherwise follow each link and change the
# mode of the pack's own file.
for _lib in converse-signoff.sh conversation.sh work-outcome.sh bd-lib.sh review-verdict.sh bead-store.sh rig-map.sh; do
    ln -s "$HERE/$_lib" "$S/$_lib"
done
SCRIPT="$S/converse-signoff.sh"

mkdir -p "$TMP/rig-a" "$TMP/rig-b"
RIG_A="$(cd "$TMP/rig-a" && pwd -P)"; RIG_B="$(cd "$TMP/rig-b" && pwd -P)"
export PATH="$TMP/bin:$PATH" STORE="$TMP/store" CALLS="$TMP/calls" GH_CALLS="$TMP/gh-calls" GC_RIG_ROOT="$TMP/rig" RIG_A RIG_B
unset GC_CITY_PATH 2>/dev/null || true

# --- fixtures -----------------------------------------------------------------
fresh() { rm -rf "$STORE"; mkdir -p "$STORE/b"; : > "$CALLS"; : > "$GH_CALLS"; }
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
run_signoff --conversation tk-conv --outcome x "${RULED[@]}" --no-rework --pr-anchor tk-anc
eq "$RC" 2 "(USAGE) --pr-anchor without --rework or --retire exits 2"
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

echo "# an open PR a gate releases: a member's PR answered from the epic's sitting"
# The member is an open PR behind its own gate, which only the epic's
# conversation replies to. Answering the gate releases the member's merge, so
# the ruling must say what it does to the member's PR, and the rework or the
# retirement lands on that PR before the gate is resolved. The record and the
# headline stay on the epic.
epic_pr() {
    fresh; bead tk-epic epic; bead tk-mem; setm tk-mem merge_result pull_request; edge tk-mem parent-child tk-epic
    gate tk-mg design-choice; edge tk-mem blocks tk-mg
    conv tk-conv tk-epic; edge tk-conv replies-to tk-mg
}
epic_pr
eq "$(merge_held tk-mem)" held "(EPIC-PR) the member's gate holds its open PR's merge before the ruling"
run_signoff --conversation tk-conv --outcome "the epic takes option B" "${RULED[@]}"
eq "$RC" 2 "(EPIC-PR) a ruling whose gate releases a member's open PR, saying nothing of that PR, exits 2"
has "$OUT" "reaches tk-mem at merge_result=pull_request" "(EPIC-PR) …naming the member's PR"
eq "$(writes)" 0 "(EPIC-PR) …writing nothing"
eq "$(merge_held tk-mem)" held "(EPIC-PR) …so the gate still holds the member's merge"
run_signoff --conversation tk-conv --outcome "the epic takes option B" "${RULED[@]}" --rework
eq "$RC" 0 "(EPIC-PR-REWORK) --rework exits 0"
has "$(cat "$CALLS")" "converse-rework --anchor tk-mem --ruling-bead tk-conv --ruling fix the retry before the merge" "(EPIC-PR-REWORK) the rework is filed on the member's PR, sourced by the epic's conversation"
hasnt "$(cat "$CALLS")" "converse-rework --anchor tk-epic" "(EPIC-PR-REWORK) …never on the epic"
case "$(cat "$CALLS")" in
  *"converse-rework --anchor tk-mem"*"gate resolve tk-mg"*) ok "(EPIC-PR-REWORK) …before the member's gate is resolved" ;;
  *) bad "(EPIC-PR-REWORK) the gate was resolved before the rework was filed: $(cat "$CALLS")" ;;
esac
eq "$(meta tk-epic gc.takeaway)" "the epic takes option B" "(EPIC-PR-REWORK) the record and headline stay on the epic"
eq "$(meta tk-mem gc.takeaway)" "" "(EPIC-PR-REWORK) …and the member carries none"
has "$(grep '^pr-sitting-comment' "$CALLS")" "close --sitting tk-conv --subject tk-epic" "(EPIC-PR-REWORK) the reminder stays the subject's"
has "$(grep '^pr-sitting-comment' "$CALLS")" "filed ruling-driven rework on tk-mem" "(EPIC-PR-REWORK) …and says the member's PR was sent back"
epic_pr
run_signoff --conversation tk-conv --outcome "the member's PR moves to the new design" "${RETIRED[@]}" --retire not-needed
eq "$RC" 0 "(EPIC-PR-RETIRE) --retire exits 0"
case "$(cat "$CALLS")" in
  *"pr-dispose --anchor tk-mem --successor tk-conv --kind not-needed"*"gate resolve tk-mg"*) ok "(EPIC-PR-RETIRE) the member's PR is retired before its gate is resolved" ;;
  *) bad "(EPIC-PR-RETIRE) the member's PR was not retired before its gate: $(cat "$CALLS")" ;;
esac
hasnt "$(cat "$CALLS")" "pr-dispose --anchor tk-epic" "(EPIC-PR-RETIRE) …and the epic is never disposed"
epic_pr
run_signoff --conversation tk-conv --outcome "the epic takes option B" "${RULED[@]}" --no-rework
eq "$RC" 0 "(EPIC-PR-NO-REWORK) --no-rework exits 0"
has "$OUT" "the ruling leaves the branch of tk-mem as it stands" "(EPIC-PR-NO-REWORK) the member's branch is said to stand"
has "$(grep '^pr-sitting-comment' "$CALLS")" "ruling leaves the branch of tk-mem as it stands" "(EPIC-PR-NO-REWORK) …in the reminder too"
hasnt "$(cat "$CALLS")" "converse-rework" "(EPIC-PR-NO-REWORK) …and nothing is filed"
epic_pr
run_signoff --conversation tk-conv --answer tk-mg "${ANSWERED[@]}"
eq "$RC" 2 "(EPIC-PR-ANSWER) an answer on a turn that does not sign off, releasing a member's open PR and saying nothing of it, exits 2"
eq "$(writes)" 0 "(EPIC-PR-ANSWER) …writing nothing"
eq "$(merge_held tk-mem)" held "(EPIC-PR-ANSWER) …so the gate still holds the member's merge"
run_signoff --conversation tk-conv --answer tk-mg "${ANSWERED[@]}" --rework
eq "$RC" 0 "(EPIC-PR-ANSWER) the answer with --rework exits 0"
case "$(cat "$CALLS")" in
  *"converse-rework --anchor tk-mem --ruling-bead tk-conv"*"gate resolve tk-mg"*) ok "(EPIC-PR-ANSWER) the member's rework is filed before its gate is resolved" ;;
  *) bad "(EPIC-PR-ANSWER) the gate was resolved before the member's rework: $(cat "$CALLS")" ;;
esac
eq "$(field tk-conv status)" "in_progress" "(EPIC-PR-ANSWER) the conversation stays open"
# An attempt that files the member's rework and resolves its gate, then stops
# because the conversation's close does not land, asks for a re-run. The gate
# then reads closed with this ruling's answer, and the re-run must still reach
# the member's PR, where the real converse-rework.sh adopts the child the first
# attempt filed, rather than fall back to the epic, which it refuses.
epic_pr; CLOSE_STUCK=tk-conv run_signoff --conversation tk-conv --outcome "the epic takes option B" "${RULED[@]}" --rework
eq "$RC" 1 "(EPIC-PR-RERUN) a sign-off whose close does not land stops short"
eq "$(field tk-mg status)" "closed" "(EPIC-PR-RERUN) …after resolving the member's gate"
: > "$CALLS"
run_signoff --conversation tk-conv --outcome "the epic takes option B" "${RULED[@]}" --rework
eq "$RC" 0 "(EPIC-PR-RERUN) the re-run exits 0"
has "$(cat "$CALLS")" "converse-rework --anchor tk-mem --ruling-bead tk-conv" "(EPIC-PR-RERUN) …sending the rework to the member's PR again"
hasnt "$(cat "$CALLS")" "converse-rework --anchor tk-epic" "(EPIC-PR-RERUN) …never to the epic"
eq "$(field tk-conv status)" "closed" "(EPIC-PR-RERUN) …and closes the conversation"

echo "# a gate about the subject and another open PR"
# One gate blocks the subject's PR and another PR, so its answer releases both.
# A conversation files one live rework, so --rework or --retire names the PR it
# acts on, and the other stands under the ruling.
shared_pr() {
    fresh; bead tk-anc; setm tk-anc merge_result pull_request; bead tk-pr2; setm tk-pr2 merge_result pull_request
    gate tk-sg approach; edge tk-anc blocks tk-sg; edge tk-pr2 blocks tk-sg
    conv tk-conv tk-anc; edge tk-conv replies-to tk-sg
}
shared_pr
run_signoff --conversation tk-conv --outcome "settled" "${RULED[@]}" --rework
eq "$RC" 2 "(SHARED-PR) --rework on a ruling that releases two open PRs, naming neither, exits 2"
has "$OUT" "reaches more than one open PR (tk-anc tk-pr2)" "(SHARED-PR) …naming both"
eq "$(writes)" 0 "(SHARED-PR) …writing nothing"
eq "$(merge_held tk-pr2)" held "(SHARED-PR) …so the gate still holds the other PR's merge"
run_signoff --conversation tk-conv --outcome "settled" "${RULED[@]}" --rework --pr-anchor tk-other
eq "$RC" 2 "(SHARED-PR) --pr-anchor naming no open PR the ruling reaches exits 2"
eq "$(writes)" 0 "(SHARED-PR) …writing nothing"
run_signoff --conversation tk-conv --outcome "the approach stands; fix the retry" "${RULED[@]}" --rework --pr-anchor tk-anc
eq "$RC" 0 "(SHARED-PR) --rework --pr-anchor naming the subject's PR exits 0"
has "$(cat "$CALLS")" "converse-rework --anchor tk-anc --ruling-bead tk-conv" "(SHARED-PR) the rework is filed on the PR it names"
hasnt "$(cat "$CALLS")" "converse-rework --anchor tk-pr2" "(SHARED-PR) …and on no other"
case "$(cat "$CALLS")" in
  *"converse-rework --anchor tk-anc"*"gate resolve tk-sg"*) ok "(SHARED-PR) …before the shared gate is resolved" ;;
  *) bad "(SHARED-PR) the shared gate was resolved before the rework: $(cat "$CALLS")" ;;
esac
has "$OUT" "the ruling leaves the branch of tk-pr2 as it stands" "(SHARED-PR) the other PR stands under the ruling"
has "$(grep '^pr-sitting-comment' "$CALLS")" "ruling leaves the branch of tk-pr2 as it stands" "(SHARED-PR) …as the reminder records"
eq "$(meta tk-pr2 gc.takeaway)" "" "(SHARED-PR) the headline stays off the other PR"
shared_pr; CLOSE_STUCK=tk-conv run_signoff --conversation tk-conv --outcome "settled" "${RULED[@]}" --rework --pr-anchor tk-pr2
eq "$RC" 1 "(SHARED-PR-RERUN) a sign-off whose close does not land, after resolving the shared gate, stops short"
: > "$CALLS"
run_signoff --conversation tk-conv --outcome "settled" "${RULED[@]}" --rework --pr-anchor tk-pr2
eq "$RC" 0 "(SHARED-PR-RERUN) the re-run with the same --pr-anchor exits 0, the gate it already answered still reaching that PR"
has "$(cat "$CALLS")" "converse-rework --anchor tk-pr2 --ruling-bead tk-conv" "(SHARED-PR-RERUN) …and sends the rework to the PR it names again"
has "$OUT" "the ruling leaves the branch of tk-anc as it stands" "(SHARED-PR-RERUN) …with the subject's PR standing, as the first attempt said"
fresh; bead tk-anc; bead tk-pr2; setm tk-pr2 merge_result pull_request
gate tk-sg approach; edge tk-anc blocks tk-sg; edge tk-pr2 blocks tk-sg
conv tk-conv tk-anc; edge tk-conv replies-to tk-sg
run_signoff --conversation tk-conv --outcome "settled" "${RULED[@]}"
eq "$RC" 2 "(SHARED-OTHER-PR) a ruling on a subject that is no PR, whose gate releases another bead's open PR, exits 2"
eq "$(writes)" 0 "(SHARED-OTHER-PR) …writing nothing"
eq "$(merge_held tk-pr2)" held "(SHARED-OTHER-PR) …so the gate still holds that PR's merge"
run_signoff --conversation tk-conv --outcome "settled" "${RULED[@]}" --retire duplicate --successor tk-anc
eq "$RC" 0 "(SHARED-OTHER-PR) --retire on that ruling exits 0"
has "$(cat "$CALLS")" "pr-dispose --anchor tk-pr2 --successor tk-anc --kind duplicate" "(SHARED-OTHER-PR) …retiring the one open PR the ruling reaches"

echo "# a re-run acts on the PR its ruling recorded, even once that PR's retirement has closed it"
# An attempt that retires the member's PR and answers its gate, then stops
# because the conversation's close does not land, asks for a re-run. pr-facts
# can consummate the retirement before it, closing the member's anchor, which is
# then no open PR the ruling reaches. The re-run takes the PR from the record
# the first attempt wrote on the conversation, finds it closed and goes on,
# rather than falling back to the epic, which pr-dispose.sh refuses.
epic_pr; CLOSE_STUCK=tk-conv run_signoff --conversation tk-conv --outcome "the member's PR moves to the new design" "${RETIRED[@]}" --retire not-needed
eq "$RC" 1 "(RETIRED-RERUN) a sign-off that retired the member's PR, and whose close does not land, stops short"
eq "$(meta tk-conv gc.ruling_consequence | jq -c '.["ruled: the work moved to the new design"]')" '{"act":"retire","anchor":"tk-mem"}' "(RECORD) the conversation records the PR its ruling's --retire acts on, under the ruling's answer"
case "$(cat "$CALLS")" in
  *"bd update tk-conv --set-metadata gc.ruling_consequence="*"pr-dispose --anchor tk-mem"*) ok "(RECORD) …before the retirement acts" ;;
  *) bad "(RECORD) the record should precede the retirement: $(cat "$CALLS")" ;;
esac
setf tk-mem status closed; setm tk-mem gc.superseded_by tk-conv
: > "$CALLS"
run_signoff --conversation tk-conv --outcome "the member's PR moves to the new design" "${RETIRED[@]}" --retire not-needed
eq "$RC" 0 "(RETIRED-RERUN) the re-run exits 0 though the retired member has closed since"
has "$OUT" "tk-mem, the PR an earlier attempt of this ruling recorded for its --retire, reads closed" "(RETIRED-RERUN) …finding the PR its ruling retired closed"
hasnt "$(cat "$CALLS")" "pr-dispose" "(RETIRED-RERUN) …disposing nothing again, and never the epic"
eq "$(field tk-conv status)" "closed" "(RETIRED-RERUN) …and closing the conversation"
shared_pr; CLOSE_STUCK=tk-conv run_signoff --conversation tk-conv --outcome "settled" "${RETIRED[@]}" --retire duplicate --successor tk-anc --pr-anchor tk-pr2
eq "$RC" 1 "(RETIRED-RERUN-PICK) a sign-off that retired the PR --pr-anchor names, and whose close does not land, stops short"
setf tk-pr2 status closed; setm tk-pr2 gc.superseded_by tk-anc
: > "$CALLS"
run_signoff --conversation tk-conv --outcome "settled" "${RETIRED[@]}" --retire duplicate --successor tk-anc --pr-anchor tk-pr2
eq "$RC" 0 "(RETIRED-RERUN-PICK) the re-run with the same --pr-anchor exits 0, the PR it names recovered from the record once closed"
hasnt "$(cat "$CALLS")" "pr-dispose" "(RETIRED-RERUN-PICK) …disposing nothing again"
has "$OUT" "the ruling leaves the branch of tk-anc as it stands" "(RETIRED-RERUN-PICK) …and the subject's PR still stands under the ruling"
epic_pr; REWORK_FAIL=1 run_signoff --conversation tk-conv --outcome "the epic takes option B" "${RULED[@]}" --rework
eq "$RC" 1 "(RECORD-OTHER-ANSWER) a rework that does not file stops the sign-off"
eq "$(meta tk-conv gc.ruling_consequence | jq -r '.["ruled: fix the retry before the merge"].anchor')" "tk-mem" "(RECORD-OTHER-ANSWER) …after recording the PR it acted on"
run_signoff --conversation tk-conv --outcome "the epic takes option B" "${RULED[@]}" --no-rework
eq "$RC" 0 "(RECORD-OTHER-ANSWER) a re-run that answers --no-rework instead is not bound by the record, and exits 0"
has "$OUT" "the ruling leaves the branch of tk-mem as it stands" "(RECORD-OTHER-ANSWER) …the member's branch standing"

echo "# the rework or the retirement runs in the rig of the PR it acts on"
# The epic's conversation lives in rig-a (prefix tk). The member's PR and the
# gate that holds its merge live in rig-b (prefix rb), and the conversation
# replies to that gate across the stores.
rig_pr() {
    fresh; bead tk-epic epic; bead rb-mem; setm rb-mem merge_result pull_request
    gate rb-mg design-choice; edge rb-mem blocks rb-mg
    conv tk-conv tk-epic; edge tk-conv replies-to rb-mg
}
rig_pr; run_signoff --conversation tk-conv --outcome "the epic takes option B" "${RULED[@]}" --rework
eq "$RC" 0 "(RIG-REWORK) a ruling whose gate in rig-b releases rig-b's open PR, with --rework, exits 0"
has "$(cat "$CALLS")" "converse-rework --anchor rb-mem --ruling-bead tk-conv" "(RIG-REWORK) the rework is filed on rig-b's PR, the rig-a conversation its provenance"
has "$(cat "$CALLS")" "converse-rework ran in GC_RIG=rig-b GC_RIG_ROOT=$RIG_B PWD=$RIG_B" "(RIG-REWORK) …and runs in rig-b: its store, its rig root and its checkout"
eq "$(meta tk-epic gc.takeaway)" "the epic takes option B" "(RIG-REWORK) the headline stays on the epic in rig-a"
eq "$(field rb-mg status)" "closed" "(RIG-REWORK) …and the gate in rig-b is answered after the rework"
rig_pr; run_signoff --conversation tk-conv --outcome "the member's PR moves to the new design" "${RETIRED[@]}" --retire not-needed
eq "$RC" 0 "(RIG-RETIRE) the same ruling with --retire exits 0"
has "$(cat "$CALLS")" "pr-dispose --anchor rb-mem --successor tk-conv --kind not-needed" "(RIG-RETIRE) rig-b's PR is retired, the rig-a conversation its evidence"
has "$(cat "$CALLS")" "pr-dispose ran in GC_RIG=rig-b GC_RIG_ROOT=$RIG_B PWD=$RIG_B" "(RIG-RETIRE) …in rig-b"
fresh; bead tk-epic epic; bead zz-mem; setm zz-mem merge_result pull_request
gate tk-mg design-choice; edge zz-mem blocks tk-mg
conv tk-conv tk-epic; edge tk-conv replies-to tk-mg
run_signoff --conversation tk-conv --outcome "the epic takes option B" "${RULED[@]}" --rework
eq "$RC" 1 "(RIG-UNRESOLVED) a PR whose rig cannot be resolved from its id stops the sign-off"
has "$OUT" "the rig that holds zz-mem could not be resolved" "(RIG-UNRESOLVED) …naming the PR"
eq "$(writes)" 0 "(RIG-UNRESOLVED) …before any write"
eq "$(field tk-mg status)" "open" "(RIG-UNRESOLVED) …so the gate still holds the PR's merge"

echo "# what a gate releases is read before any write"
epic_pr; DEP_UP_DOWN=tk-mg run_signoff --conversation tk-conv --outcome "settled" "${RULED[@]}" --rework
eq "$RC" 1 "(RELEASED-UNREAD) a gate whose waiting beads do not read stops the sign-off"
has "$OUT" "NOT SIGNED OFF" "(RELEASED-UNREAD) …saying not to post the sign-off"
eq "$(writes)" 0 "(RELEASED-UNREAD) …and writes nothing"
epic_pr; SHOW_DOWN=tk-mem run_signoff --conversation tk-conv --outcome "settled" "${RULED[@]}"
eq "$RC" 1 "(RELEASED-UNREAD) a bead the gate releases whose row does not read stops the sign-off"
eq "$(writes)" 0 "(RELEASED-UNREAD) …and writes nothing"
eq "$(field tk-mg status)" "open" "(RELEASED-UNREAD) …leaving the gate open"

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
acceptance; SUBJECT_LC_STATE=held TRANSITION_FAIL=1 run_signoff --conversation tk-conv --outcome "settled" --ruled yes --ruling "go" --route gc-toolkit/gc-toolkit.polecat --no-wait
eq "$RC" 1 "(HELD-FAIL) a ruled sign-off whose release of the held subject fails exits 1"
has "$OUT" "RELEASE FROM held FAILED on tk-anc" "(HELD-FAIL) …naming the subject it did not release"
has "$OUT" "NOT SIGNED OFF" "(HELD-FAIL) …saying not to post the sign-off"
hasnt "$OUT" "SIGNED OFF conversation" "(HELD-FAIL) …and reporting no settlement"
eq "$(field tk-conv status)" "in_progress" "(HELD-FAIL) …so the conversation stays open under its sitting"
hasnt "$(cat "$CALLS")" "pr-sitting-comment" "(HELD-FAIL) …with no reminder update"
SUBJECT_LC_STATE=held run_signoff --conversation tk-conv --outcome "settled" --ruled yes --ruling "go" --route gc-toolkit/gc-toolkit.polecat --no-wait
eq "$RC" 0 "(HELD-FAIL) the re-run, once the release lands, exits 0"
eq "$(grep -c '^lifecycle transition tk-anc --to unanchored' "$CALLS")" 2 "(HELD-FAIL) …trying the release again"
eq "$(field tk-conv status)" "closed" "(HELD-FAIL) …and then closing the conversation"

echo "# a ruling on an open PR says whether its branch changes"
acceptance; setm tk-anc merge_result pull_request
run_signoff --conversation tk-conv --outcome "settled" "${RULED[@]}"
eq "$RC" 2 "(OPEN-PR) a ruled sign-off on an open PR with neither --rework nor --no-rework exits 2"
eq "$(writes)" 0 "(OPEN-PR) …writing nothing"
run_signoff --conversation tk-conv --outcome "settled" "${RULED[@]}" --rework
eq "$RC" 0 "(REWORK) --rework exits 0"
has "$(cat "$CALLS")" "converse-rework --anchor tk-anc --ruling-bead tk-conv --ruling fix the retry before the merge" "(REWORK) the rework is filed with the conversation as its source ruling bead"
has "$(grep -v '^lifecycle state' "$CALLS" | head -1)" "bd update tk-conv --set-metadata gc.ruling_consequence=" "(REWORK) the PR it acts on is recorded on the conversation first"
has "$(grep -v '^lifecycle state' "$CALLS" | sed -n 2p)" "converse-rework --anchor tk-anc" "(REWORK) …then the rework runs, before every other write"
has "$(cat "$CALLS")" "converse-rework ran in GC_RIG=rig-a GC_RIG_ROOT=$RIG_A PWD=$RIG_A" "(REWORK) …in the rig of the PR it acts on"
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

echo "# two conversations on one PR: each ruling answers its own question"
# Each sitting's hold filed its own gate on the anchor, under a key that names
# its conversation (skills/converse-hold), and replies to that gate alone.
fresh; bead tk-anc; setm tk-anc merge_result pull_request
gate tk-ga conversation.tk-ca; edge tk-anc blocks tk-ga
gate tk-gb conversation.tk-cb; edge tk-anc blocks tk-gb
conv tk-ca tk-anc; edge tk-ca replies-to tk-ga
conv tk-cb tk-anc; edge tk-cb replies-to tk-gb
run_signoff --conversation tk-ca --outcome "the retry stays" --ruled yes --ruling "keep the retry" --route human --no-wait --no-rework
eq "$RC" 0 "(TWO-CONV) the first conversation's sign-off exits 0"
eq "$(field tk-ga status)/$(field tk-gb status)" "closed/open" "(TWO-CONV) …resolving its own gate and leaving the other conversation's open"
eq "$(merge_held tk-anc)" held "(TWO-CONV) …so the merge stays held for the second decision"
run_signoff --conversation tk-cb --outcome "the docs ship first" --ruled yes --ruling "ship the docs first" --route human --no-wait --no-rework
eq "$RC" 0 "(TWO-CONV) the second conversation's sign-off exits 0"
eq "$(field tk-gb close_reason)" "ruled: ship the docs first" "(TWO-CONV) …answering its own gate with its own ruling"
eq "$(merge_held tk-anc)" released "(TWO-CONV) …and only then is the merge released"

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

# recommend — tk-anc recommends mol-fix through tk-rec, the gate a first
# reaction filed under the key first-reaction, and the conversation took that
# gate up.
recommend() {
    fresh; bead tk-anc; setm tk-anc gc.recommended_formula mol-fix
    gate tk-rec first-reaction; edge tk-anc blocks tk-rec
    conv tk-conv tk-anc; edge tk-conv replies-to tk-rec
}
TAKE=(--ruled yes --ruling "take the reaction's mol-fix" --route human --no-wait --accept)

echo "# a ruling that takes the recommendation hands its gate to Accept's writer"
recommend; run_signoff --conversation tk-conv --outcome "took the reaction's mol-fix" "${TAKE[@]}"
eq "$RC" 0 "(ACCEPT) a sign-off that takes the recommendation exits 0"
has "$(cat "$CALLS")" "gc-helm accept tk-anc --conversation tk-conv --reason take the reaction's mol-fix" "(ACCEPT) …running Accept's writer on the subject, naming its own conversation"
hasnt "$(cat "$CALLS")" "gate resolve tk-rec" "(ACCEPT) …and never resolving the recommendation's gate itself"
eq "$(field tk-rec close_reason)" "ruled: accepted mol-fix accept:0123456789abcdef" "(ACCEPT) the gate carries Accept's answer"
eq "$(meta tk-anc gc.recommended_formula_dispatched)" "mol-fix" "(ACCEPT) …and the dispatch is recorded"
eq "$(field tk-conv status)" "closed" "(ACCEPT) the conversation closes"
eq "$(jq -r '[.deps[] | select(.type == "replies-to") | .on] | join(" ")' "$STORE/b/tk-conv.json")" "tk-rec" "(ACCEPT) …keeping its reply onto the gate it took up"
has "$OUT" "took the recommendation: mol-fix at tk-anc, through Accept" "(ACCEPT) the take is reported"
has "$(grep '^pr-sitting-comment' "$CALLS")" "took the recommendation: mol-fix, through Accept" "(ACCEPT) …and listed among the reminder's actions"
case "$(cat "$CALLS")" in
  *"gc-helm takeaway"*"gc-helm accept"*"bd close tk-conv"*) ok "(ACCEPT-ORDER) headline, then the acceptance, then the close" ;;
  *) bad "(ACCEPT-ORDER) the writes ran out of order: $(cat "$CALLS")" ;;
esac
TAKEN="$(cat "$CALLS")"
ACCEPT_DOES=dispatched run_signoff --conversation tk-conv --outcome "took the reaction's mol-fix" "${TAKE[@]}"
eq "$RC" 0 "(ACCEPT-RERUN) a re-run of a sign-off that took the recommendation exits 0"
has "$OUT" "the recommendation was already taken" "(ACCEPT-RERUN) …finding it already taken"
eq "$(grep -c '^bd close' "$CALLS")" "$(printf '%s\n' "$TAKEN" | grep -c '^bd close')" "(ACCEPT-RERUN) …and closing nothing again"

echo "# the acceptance case in one sitting: the review gate first, then the recommendation"
recommend; gate tk-rev review-needs-you.tk-find; edge tk-anc blocks tk-rev; edge tk-conv replies-to tk-rev
run_signoff --conversation tk-conv --outcome "fix the retry; mol-fix is taken" "${TAKE[@]}"
eq "$RC" 0 "(ACCEPT-BESIDE) a ruling on both gates that takes the recommendation exits 0"
eq "$(field tk-rev close_reason)" "ruled: take the reaction's mol-fix" "(ACCEPT-BESIDE) the review gate is answered with the ruling"
case "$(cat "$CALLS")" in
  *"gate resolve tk-rev"*"gc-helm accept tk-anc"*) ok "(ACCEPT-BESIDE) …before Accept's writer runs, so no other gate holds the bead when it dispatches" ;;
  *) bad "(ACCEPT-BESIDE) Accept ran before the review gate was answered: $(cat "$CALLS")" ;;
esac
eq "$(field tk-rec close_reason)" "ruled: accepted mol-fix accept:0123456789abcdef" "(ACCEPT-BESIDE) the recommendation's gate carries Accept's answer"

echo "# --accept refusals before any write"
recommend; run_signoff --conversation tk-conv --outcome x --ruled no --accept
eq "$RC" 2 "(ACCEPT-USAGE) --accept without a ruling exits 2"
recommend; run_signoff --conversation tk-conv --outcome x "${TAKE[@]}" --leave tk-rec
eq "$RC" 2 "(ACCEPT-LEFT) --accept on a ruling that leaves the recommendation's gate owed exits 2"
eq "$(writes)" 0 "(ACCEPT-LEFT) …writing nothing"
acceptance; setm tk-anc gc.recommended_formula mol-fix
run_signoff --conversation tk-conv --outcome x "${TAKE[@]}"
eq "$RC" 2 "(ACCEPT-NO-REPLY) --accept from a conversation that does not reply to the recommendation's gate exits 2"
has "$OUT" "first-reaction" "(ACCEPT-NO-REPLY) …naming the gate it must reply to"
eq "$(writes)" 0 "(ACCEPT-NO-REPLY) …writing nothing"
recommend; jq 'del(.metadata["gc.recommended_formula"])' "$STORE/b/tk-anc.json" > "$STORE/b/x" && mv "$STORE/b/x" "$STORE/b/tk-anc.json"
run_signoff --conversation tk-conv --outcome x "${TAKE[@]}"
eq "$RC" 2 "(ACCEPT-NONE) --accept on a subject that carries no recommendation exits 2"
eq "$(writes)" 0 "(ACCEPT-NONE) …writing nothing"
recommend; gate tk-rev review-needs-you.tk-find; edge tk-anc blocks tk-rev
run_signoff --conversation tk-conv --outcome x "${TAKE[@]}"
eq "$RC" 2 "(ACCEPT-WITHHELD) --accept while another human gate the ruling does not answer holds the subject exits 2"
has "$OUT" "tk-rev" "(ACCEPT-WITHHELD) …naming that gate"
eq "$(writes)" 0 "(ACCEPT-WITHHELD) …writing nothing"
eq "$(field tk-rec status)" "open" "(ACCEPT-WITHHELD) …so the recommendation's gate stays open"
# epic_rec — an epic and its member each recommend a formula through a gate of
# their own under the key first-reaction, and the epic's conversation took up
# the member's gate alone. Accept on the epic answers the epic's gate, never
# the member's.
epic_rec() {
    fresh; bead tk-epic epic; setm tk-epic gc.recommended_formula mol-fix
    gate tk-eg first-reaction; edge tk-epic blocks tk-eg
    bead tk-mem; edge tk-mem parent-child tk-epic; setm tk-mem gc.recommended_formula mol-polish
    gate tk-mg first-reaction; edge tk-mem blocks tk-mg
    conv tk-conv tk-epic; edge tk-conv replies-to tk-mg
}
epic_rec; run_signoff --conversation tk-conv --answer tk-mg --ruling "take the member's mol-polish" --outcome x --no-wait --accept
eq "$RC" 2 "(ACCEPT-MEMBER) --accept on an answer to a member's first-reaction gate alone exits 2"
has "$OUT" "blocks another bead" "(ACCEPT-MEMBER) …saying that gate asks another bead's recommendation"
eq "$(writes)" 0 "(ACCEPT-MEMBER) …writing nothing"
eq "$(field tk-eg status)/$(field tk-mg status)" "open/open" "(ACCEPT-MEMBER) …so the epic's gate and the member's both stay open"
eq "$(meta tk-epic gc.recommended_formula_dispatched)" "" "(ACCEPT-MEMBER) …and the epic's recommendation is not dispatched"
hasnt "$OUT" "ANSWERED" "(ACCEPT-MEMBER) …nor is the member's gate reported answered"
epic_rec; run_signoff --conversation tk-conv --outcome x "${TAKE[@]}"
eq "$RC" 2 "(ACCEPT-MEMBER) a sign-off that takes the recommendation from a member's gate alone exits 2"
eq "$(writes)" 0 "(ACCEPT-MEMBER) …writing nothing"
eq "$(field tk-eg status)" "open" "(ACCEPT-MEMBER) …and the epic's gate stays open"
# Accept answers each open gate under the key on the subject, so the ruling
# answers each of them, a twin a race filed beside the first included.
recommend; gate tk-rec2 first-reaction; edge tk-anc blocks tk-rec2
run_signoff --conversation tk-conv --outcome x "${TAKE[@]}"
eq "$RC" 2 "(ACCEPT-UNANSWERED) --accept while Accept would also answer a gate the ruling does not exits 2"
has "$OUT" "by answering tk-rec2" "(ACCEPT-UNANSWERED) …naming that gate"
eq "$(writes)" 0 "(ACCEPT-UNANSWERED) …writing nothing"
edge tk-conv replies-to tk-rec2
run_signoff --conversation tk-conv --outcome "took the reaction's mol-fix" "${TAKE[@]}"
eq "$RC" 0 "(ACCEPT-TWINS) a ruling that answers both gates under the key takes the recommendation"
eq "$(field tk-rec status)/$(field tk-rec2 status)" "closed/closed" "(ACCEPT-TWINS) …through Accept, which answers both"
hasnt "$(cat "$CALLS")" "gate resolve tk-rec" "(ACCEPT-TWINS) …and the sign-off resolves neither itself"

echo "# --accept on a turn that does not sign off"
recommend; run_signoff --conversation tk-conv --answer tk-rec --ruling "take the reaction's mol-fix" --outcome "mol-fix is taken; the rollout is still open" --no-wait --accept
eq "$RC" 0 "(ACCEPT-ANSWER) an --answer that takes the recommendation exits 0"
eq "$(meta tk-anc gc.recommended_formula_dispatched)" "mol-fix" "(ACCEPT-ANSWER) …dispatching it through Accept"
eq "$(field tk-conv status)" "in_progress" "(ACCEPT-ANSWER) …and the conversation stays open under its sitting"
has "$OUT" "ANSWERED tk-rec" "(ACCEPT-ANSWER) …saying which gate it answered"
recommend; SUBJECT_LC_STATE=held run_signoff --conversation tk-conv --answer tk-rec --ruling "take it" --outcome x --no-wait --accept
eq "$RC" 0 "(ACCEPT-ANSWER-HELD) an --answer that takes a held subject's recommendation exits 0"
hasnt "$(cat "$CALLS")" "lifecycle" "(ACCEPT-ANSWER-HELD) …reading and releasing nothing itself"
has "$(cat "$CALLS")" "gc-helm accept tk-anc --conversation tk-conv" "(ACCEPT-ANSWER-HELD) …leaving the held subject to Accept's writer, which releases it before its sling"
recommend; SUBJECT_LC_STATE=held run_signoff --conversation tk-conv --outcome "mol-fix is taken" "${TAKE[@]}"
eq "$RC" 0 "(ACCEPT-HELD) a sign-off that takes a held subject's recommendation exits 0"
case "$(cat "$CALLS")" in
  *"lifecycle transition tk-anc --to unanchored"*"gc-helm accept tk-anc"*) ok "(ACCEPT-HELD) …releasing the subject before Accept dispatches at it" ;;
  *) bad "(ACCEPT-HELD) Accept ran before the release: $(cat "$CALLS")" ;;
esac
recommend; SUBJECT_LC_STATE=held TRANSITION_FAIL=2 run_signoff --conversation tk-conv --outcome "mol-fix is taken" "${TAKE[@]}"
eq "$RC" 1 "(ACCEPT-HELD-FAIL) a take whose release of the held subject fails exits 1"
hasnt "$(cat "$CALLS")" "gc-helm accept" "(ACCEPT-HELD-FAIL) …before Accept's writer runs"
eq "$(field tk-rec status)" "open" "(ACCEPT-HELD-FAIL) …so the recommendation's gate stays open"
eq "$(field tk-conv status)" "in_progress" "(ACCEPT-HELD-FAIL) …and the conversation is not closed"

echo "# a take Accept does not complete stops the sign-off, and an answer that reached the gate first stands"
recommend; ACCEPT_DOES=refuse run_signoff --conversation tk-conv --outcome "mol-fix is taken" "${TAKE[@]}"
eq "$RC" 1 "(ACCEPT-REFUSED) a take Accept refuses stops the sign-off"
has "$OUT" "holds its acceptance lock" "(ACCEPT-REFUSED) …showing why Accept refused"
has "$OUT" "the recommendation was not taken" "(ACCEPT-REFUSED) …and that nothing was taken"
has "$OUT" "NOT SIGNED OFF" "(ACCEPT-REFUSED) …saying not to post the sign-off"
eq "$(field tk-conv status)" "in_progress" "(ACCEPT-REFUSED) …and the conversation is not closed"
recommend; ACCEPT_DOES=other run_signoff --conversation tk-conv --outcome "the reaction withdrew mol-fix" "${TAKE[@]}"
eq "$RC" 0 "(ACCEPT-FIRST) a take another answer beat to the gate exits 0"
has "$OUT" "another answer reached the recommendation's gate first — tk-rec: \"moot: the reaction withdrew its recommendation\"" "(ACCEPT-FIRST) …reporting the answer that stands"
eq "$(field tk-conv status)" "closed" "(ACCEPT-FIRST) …and the conversation closes"

echo "# --var hands Accept's writer a var the ruling settled for the dispatch"
recommend; run_signoff --conversation tk-conv --outcome "mol-fix is taken all-in-one" "${TAKE[@]}" --var design_gated=false
eq "$RC" 0 "(ACCEPT-VAR) a take that settles a var for the dispatch exits 0"
has "$(cat "$CALLS")" "gc-helm accept tk-anc --conversation tk-conv --reason take the reaction's mol-fix --var design_gated=false" "(ACCEPT-VAR) …passing it to Accept's writer"
ACCEPT_DOES=dispatched run_signoff --conversation tk-conv --outcome "mol-fix is taken all-in-one" "${TAKE[@]}" --var design_gated=false
eq "$RC" 0 "(ACCEPT-VAR) a re-run once the dispatch is made exits 0"
has "$OUT" "keeps the vars it was made with, so the --var given here does not reach it" "(ACCEPT-VAR) …saying the dispatch already made keeps its own vars"
recommend; run_signoff --conversation tk-conv --outcome x --ruled yes --ruling "fix it" --route human --no-wait --var design_gated=false
eq "$RC" 2 "(ACCEPT-VAR-ALONE) --var without --accept exits 2"
eq "$(writes)" 0 "(ACCEPT-VAR-ALONE) …writing nothing"
recommend; run_signoff --conversation tk-conv --outcome x "${TAKE[@]}" --var design_gated
eq "$RC" 2 "(ACCEPT-VAR-FORM) a --var that is not <key>=<value> exits 2"
eq "$(writes)" 0 "(ACCEPT-VAR-FORM) …writing nothing"

echo "# a ruling is not an approval: a PR it leaves standing with none says so"
# pr_at <anchor> <n> — the PR the anchor records. review <n> <login> <state>
# <submitted_at> — a review on it.
pr_at() { setm "$1" pr_number "$2"; setm "$1" pr_url "https://github.com/acme/widgets/pull/$2"; }
review() {
    _f="$STORE/reviews-$1.json"; [ -f "$_f" ] || echo '[]' > "$_f"
    jq --arg l "$2" --arg s "$3" --arg t "$4" '. + [{id: (length + 1), user: {login: $l}, state: $s, submitted_at: $t}]' "$_f" > "$_f.x" && mv "$_f.x" "$_f"
}
# said <label> <owed|landed> — what a sign-off outcome "design approved" on PR #77
# wrote and printed: the Approve still owed, or nothing of it.
said() {
    if [ "$2" = owed ]; then
        eq "$(meta tk-anc gc.takeaway)" "design approved; PR #77 still needs your Approve on GitHub" "$1 the headline says the Approve is owed"
        has "$OUT" "PR #77 still needs the operator's Approve review on GitHub" "$1 …and the sitting is told"
    else
        eq "$(meta tk-anc gc.takeaway)" "design approved" "$1 the headline stays as given"
        hasnt "$OUT" "Approve" "$1 …and the sitting is told nothing about an Approve"
    fi
}
STAND=(--conversation tk-conv --outcome "design approved" "${RULED[@]}" --no-rework)

open_pr; pr_at tk-anc 77
run_signoff "${STAND[@]}"
eq "$RC" 0 "(APPROVE-OWED) a ruling that leaves an unapproved PR standing signs off"
said "(APPROVE-OWED)" owed
eq "$(field tk-conv close_reason)" "design approved; PR #77 still needs your Approve on GitHub" "(APPROVE-OWED) the close reason says so"
has "$(grep '^pr-sitting-comment' "$CALLS")" "--summary design approved; PR #77 still needs your Approve on GitHub" "(APPROVE-OWED) …and so does the PR reminder"
has "$OUT" "this ruling does not count as one" "(APPROVE-OWED) the sitting is told the ruling is not the approval"
has "$OUT" "link it: https://github.com/acme/widgets/pull/77" "(APPROVE-OWED) …with the PR's link"
case "$OUT" in
  *"SIGNED OFF"*"PR #77 still needs the operator's Approve"*) ok "(APPROVE-OWED) …as the last thing it reads" ;;
  *) bad "(APPROVE-OWED) the tell does not follow SIGNED OFF: $OUT" ;;
esac
eq "$(field tk-rev status)" "closed" "(APPROVE-OWED) the ruling still answers the gate"
has "$(cat "$GH_CALLS")" "repos/acme/widgets/pulls/77/reviews" "(APPROVE-OWED) the reviews are read from the repo the PR's url names"
eq "$(grep -cv '^writes=0 ' "$GH_CALLS" || true)" 0 "(APPROVE-OWED) …before the first write"
run_signoff "${STAND[@]}"
eq "$RC" 0 "(APPROVE-RERUN) a re-run exits 0"
said "(APPROVE-RERUN)" owed

open_pr; pr_at tk-anc 77
run_signoff --conversation tk-conv --outcome "design approved." "${RULED[@]}" --no-rework
said "(APPROVE-PERIOD)" owed

open_pr; pr_at tk-anc 77; review 77 operator APPROVED 2026-10-20T00:00:00Z
run_signoff "${STAND[@]}"
said "(APPROVE-STANDS)" landed
eq "$(field tk-conv close_reason)" "design approved" "(APPROVE-STANDS) the close reason stays as given"

open_pr; pr_at tk-anc 77; review 77 city-bot APPROVED 2026-10-20T00:00:00Z
run_signoff "${STAND[@]}"
said "(APPROVE-CITY) the city's own approval counts for nothing:" owed

open_pr; pr_at tk-anc 77; review 77 operator APPROVED 2026-10-20T00:00:00Z; review 77 other CHANGES_REQUESTED 2026-10-21T00:00:00Z
run_signoff "${STAND[@]}"
said "(APPROVE-VETO) a standing request for changes holds the merge:" owed

open_pr; pr_at tk-anc 77; setm tk-anc bring_current_lifted_at 2026-10-21T00:00:00Z; review 77 operator APPROVED 2026-10-20T00:00:00Z
run_signoff "${STAND[@]}"
said "(APPROVE-LIFTED) an approval a bring-current round lifted counts for nothing:" owed
open_pr; pr_at tk-anc 77; setm tk-anc bring_current_lifted_at 2026-10-21T00:00:00Z; review 77 operator APPROVED 2026-10-22T00:00:00Z
run_signoff "${STAND[@]}"
said "(APPROVE-LIFTED) an approval given after that line counts:" landed

open_pr; pr_at tk-anc 77
GH_DOWN=1 run_signoff "${STAND[@]}"
eq "$RC" 0 "(APPROVE-UNREAD) reviews that do not read do not stop the sign-off"
eq "$(meta tk-anc gc.takeaway)" "design approved; PR #77 still needs your Approve on GitHub" "(APPROVE-UNREAD) …and the PR counts as needing one"
has "$OUT" "The reviews of PR #77 could not be read" "(APPROVE-UNREAD) …and the sitting is told they did not read"
has "$OUT" "link it: https://github.com/acme/widgets/pull/77" "(APPROVE-UNREAD) …with the PR's link"
eq "$(field tk-conv status)" "closed" "(APPROVE-UNREAD) …and the conversation closes"

open_pr; setm tk-anc pr_url "https://github.com/acme/widgets/pull/78"; review 78 operator APPROVED 2026-10-20T00:00:00Z
run_signoff "${STAND[@]}"
said "(APPROVE-URL-ONLY) a PR's number comes from its url when none is recorded:" landed
open_pr; setm tk-anc existing_pr "https://github.com/acme/widgets/pull/79"
run_signoff "${STAND[@]}"
eq "$(meta tk-anc gc.takeaway)" "design approved; PR #79 still needs your Approve on GitHub" "(APPROVE-URL-ONLY) …and its url from existing_pr when no pr_url is"
open_pr
run_signoff "${STAND[@]}"
eq "$RC" 0 "(APPROVE-NO-URL) an anchor that records no PR identity signs off"
eq "$(meta tk-anc gc.takeaway)" "design approved; tk-anc's PR still needs your Approve on GitHub" "(APPROVE-NO-URL) …naming the PR by its anchor"
hasnt "$OUT" "link it" "(APPROVE-NO-URL) …with no link to give"
eq "$(cat "$GH_CALLS")" "" "(APPROVE-NO-URL) …and no GitHub read"

open_pr; pr_at tk-anc 77
run_signoff --conversation tk-conv --outcome "fix the retry" "${RULED[@]}" --rework
eq "$RC" 0 "(APPROVE-REWORK) --rework signs off"
eq "$(meta tk-anc gc.takeaway)" "fix the retry" "(APPROVE-REWORK) …with the headline as given: the branch is changing, so no Approve is owed yet"
eq "$(cat "$GH_CALLS")" "" "(APPROVE-REWORK) …and no GitHub read"
open_pr; pr_at tk-anc 77
run_signoff --conversation tk-conv --outcome "it will not land" "${RETIRED[@]}" --retire not-needed
eq "$RC" 0 "(APPROVE-RETIRE) --retire signs off"
eq "$(meta tk-anc gc.takeaway)" "it will not land" "(APPROVE-RETIRE) …with the headline as given"
eq "$(cat "$GH_CALLS")" "" "(APPROVE-RETIRE) …and no GitHub read"
acceptance; run_signoff --conversation tk-conv --outcome "settled" "${RULED[@]}" --no-rework
eq "$(meta tk-anc gc.takeaway)" "settled" "(APPROVE-NO-PR) --no-rework where the ruling reaches no open PR says nothing of an Approve"
eq "$(cat "$GH_CALLS")" "" "(APPROVE-NO-PR) …and reads nothing from GitHub"
open_pr; pr_at tk-anc 77
run_signoff --conversation tk-conv --outcome "not yet" --ruled no
eq "$RC" 0 "(APPROVE-CUT-SHORT) a sign-off cut short exits 0"
eq "$(meta tk-anc gc.takeaway)" "not yet" "(APPROVE-CUT-SHORT) …and, with no ruling, says nothing of an Approve"
eq "$(cat "$GH_CALLS")" "" "(APPROVE-CUT-SHORT) …and reads nothing from GitHub"

epic_pr; pr_at tk-mem 78
run_signoff --conversation tk-conv --outcome "the epic takes option B" "${RULED[@]}" --no-rework
eq "$(meta tk-epic gc.takeaway)" "the epic takes option B; PR #78 still needs your Approve on GitHub" "(APPROVE-EPIC) the epic's headline names the member's PR"
has "$OUT" "PR #78 still needs the operator's Approve review on GitHub" "(APPROVE-EPIC) …and the sitting is told"
eq "$(meta tk-mem gc.takeaway)" "" "(APPROVE-EPIC) …and the member carries no headline"

shared_pr; pr_at tk-anc 77; pr_at tk-pr2 78
run_signoff --conversation tk-conv --outcome "the approach stands" "${RULED[@]}" --no-rework
eq "$(meta tk-anc gc.takeaway)" "the approach stands; PR #77, PR #78 still need your Approve on GitHub" "(APPROVE-TWO) two PRs left standing are both named"
has "$OUT" "PR #77 still needs the operator's Approve review" "(APPROVE-TWO) …and the sitting is told of the first"
has "$OUT" "PR #78 still needs the operator's Approve review" "(APPROVE-TWO) …and of the second"
shared_pr; pr_at tk-anc 77; pr_at tk-pr2 78; review 77 operator APPROVED 2026-10-20T00:00:00Z
run_signoff --conversation tk-conv --outcome "the approach stands" "${RULED[@]}" --no-rework
eq "$(meta tk-anc gc.takeaway)" "the approach stands; PR #78 still needs your Approve on GitHub" "(APPROVE-TWO) only the one with no approval is named"
shared_pr; pr_at tk-anc 77; pr_at tk-pr2 78
run_signoff --conversation tk-conv --outcome "fix the retry" "${RULED[@]}" --rework --pr-anchor tk-anc
eq "$(meta tk-anc gc.takeaway)" "fix the retry; PR #78 still needs your Approve on GitHub" "(APPROVE-TWO) a PR reworked beside one left standing is not named"

open_pr; pr_at tk-anc 77
TAKEAWAY_FAIL=1 run_signoff "${STAND[@]}"
eq "$RC" 1 "(APPROVE-CAP) a headline refused with the clause on it stops the sign-off"
has "$OUT" "after --outcome, which counts toward the cap" "(APPROVE-CAP) …saying a shorter --outcome makes room"
eq "$(field tk-rev status)" "open" "(APPROVE-CAP) …before any gate is resolved"
open_pr; pr_at tk-anc 77; review 77 operator APPROVED 2026-10-20T00:00:00Z
TAKEAWAY_FAIL=1 run_signoff "${STAND[@]}"
hasnt "$OUT" "counts toward the cap" "(APPROVE-CAP) a headline with no clause on it says nothing of one"

open_pr; pr_at tk-anc 77
run_signoff --conversation tk-conv --answer tk-rev --ruling "design approved" --outcome "design approved" --no-rework
eq "$RC" 0 "(APPROVE-ANSWER) an answer that leaves the PR standing exits 0"
said "(APPROVE-ANSWER)" owed
eq "$(field tk-conv status)" "in_progress" "(APPROVE-ANSWER) …and the conversation stays open"

echo
echo "converse-signoff: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
