#!/usr/bin/env bash
# Hermetic test for assets/scripts/converse-rework.sh — an operator ruling's entry
# to rework — run end to end through rework-child.sh, the one writer of a rework
# child that signoff.sh files through too, over the compiled fake gc of
# test-harness.sh. No live city, Dolt, or network. The child is the fix unit a
# review verdict files (task_kind=rework, anchor_bead, branch, target,
# merge_strategy=mr, PR fields), sourced by source_ruling_bead rather than
# source_review_bead; it blocks the anchor and is slung with mol-polecat-work.
# The assertions pin: the child's full work order, that it carries
# source_ruling_bead and NOT a minted source_review_bead, the blocks edge, the
# dispatch read-back, idempotency on the ruling, the identity riding in the
# create so a lost create id is adopted rather than twinned, a review's child
# never adopted for a ruling, the open-PR guards (a live anchor at pull_request,
# carrying no disposition, naming its branch, target and PR), the
# no-double-dispatch refusal on a partial pour, and every lane returned to
# unreviewed (review-outcome.sh, run for real) once the child is dispatched,
# resolved at the head of the anchor's branch, whose failed read refuses before
# anything is filed. The head is read, and the lanes are resolved, in the
# anchor's rig checkout, whatever directory the sitting runs from, and an anchor
# whose rig checkout does not resolve refuses too. A git wrapper answers the
# read. Over two stores, one per rig, a run with GC_RIG naming the anchor's rig,
# as converse-signoff.sh runs it, files, edges and dispatches the child there,
# and a run from the conversation's rig cannot prove the edge and dispatches
# nothing. An anchor on the pending record takes the ruling as an ask to its
# review run instead, with the checks the ruling names, read from the check
# index beside this checkout's scripts whatever the binding, and nothing
# superseded.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/converse-rework.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-converse-rework-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
REAL_GIT="$(command -v git)" || { echo "git is required for this test" >&2; exit 1; }

# The shared harness: the compiled fake gc, and gctk built from this checkout,
# which reads the check index for the scripts under test.
# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"
harness_build_gctk
harness_init
export GC_RIG="gc-toolkit"
# No check index: gctk review checks then resolves every check_set token as a
# lane gating every transition, so the lanes do not depend on the checkout.
export GC_REVIEW_CHECKS_INDEX="$TMP/no-such-index.toml"

# git is the real one, but for the one remote read the run makes, the anchor
# branch's head: ls-remote answers STUB_LS_REMOTE_HEAD, else the sha1, for each
# refs/heads/<branch> it is asked for, unless STUB_LS_REMOTE_MISS names that
# branch, and logs the call to STUB_GIT_LOG.
export STUB_GIT_LOG="$TMP/git.log"
{ printf '#!/usr/bin/env bash\nREAL_GIT=%q\n' "$REAL_GIT"; cat; } > "$BIN/git" <<'GIT'
case " $* " in
  *" ls-remote "*)
    printf '%s\n' "$*" >> "${STUB_GIT_LOG:?}"
    for a in "$@"; do
      case "$a" in refs/heads/*) ;; *) continue ;; esac
      b="${a#refs/heads/}"
      [ "${STUB_LS_REMOTE_MISS:-}" = "$b" ] && continue
      printf '%s\t%s\n' "${STUB_LS_REMOTE_HEAD:-$(printf '%s' "$b" | sha1sum | cut -d' ' -f1)}" "$a"
    done
    exit 0 ;;
esac
exec "$REAL_GIT" "$@"
GIT
chmod +x "$BIN/git"

# The anchor's rig checkout, which the rig list names for the anc prefix. It
# keeps no store of its own, so the anchor lives in the harness's store. Over
# two stores, rig-a (ra) and rig-b (rb) each keep one, and rig-b's path is the
# checkout of its anchor rb-anc.
export STUB_RIG_PATH="$TMP/anc-rig" RIG_A="$TMP/rig-a" RIG_B="$TMP/rig-b"
for d in "$STUB_RIG_PATH" "$RIG_B"; do
  git init -q "$d"
  git -C "$d" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -q --allow-empty -m "the anchor's head"
done
mkdir -p "$RIG_A"
export STUB_RIGS="$TMP/rigs.json"
rigs() { # [two]: the rig list the run finds the anchor's rig checkout in
  if [ "${1:-}" = two ]; then
    printf '{"rigs":[{"name":"anc-rig","prefix":"anc","path":"%s"},{"name":"rig-a","prefix":"ra","path":"%s"},{"name":"rig-b","prefix":"rb","path":"%s"}]}\n' \
      "$STUB_RIG_PATH" "$RIG_A" "$RIG_B" > "$STUB_RIGS"
  else
    printf '{"rigs":[{"name":"anc-rig","prefix":"anc","path":"%s"}]}\n' "$STUB_RIG_PATH" > "$STUB_RIGS"
  fi
}

# reset <store-json>: seed the store and clear the logs and the faults.
reset() {
  store "$1"
  : > "$STUB_DEPS"; : > "$STUB_GC_LOG"; : > "$STUB_GIT_LOG"
  STUB_DROP_KEYS=""; STUB_LIST_FAIL=""; STUB_CREATE_GARBAGE=""
  unset STUB_LS_REMOTE_MISS STUB_LS_REMOTE_HEAD 2>/dev/null || true
  rigs
}
# The fake mints new-<N> for its store's Nth row, so the child a run files
# beside the anchor alone is new-2. created counts the children a run filed.
created() {
  local n=0 id
  while IFS= read -r id; do case "$id" in new-*) n=$((n + 1)) ;; esac; done < <(bids)
  echo "$n"
}
# Does the child block the anchor? The anchor depends on it through a blocks
# edge.
blocks_anchor() { case " $(bedges "$2" blocks) " in *" $1 "*) return 0 ;; esac; return 1; }

ANCHOR_PR='[{"id":"anc-1","status":"open","assignee":"","notes":"","metadata":{"merge_result":"pull_request","branch":"polecat/anc-1","target":"main","existing_pr":"https://github.com/o/r/pull/42","pr_url":"https://github.com/o/r/pull/42","pr_number":"42","check_set":"correctness,arch"}}]'
# approve <id> <lane>: a closed approve review backing <lane> on anc-1, the bead
# lane-state.sh derives green from.
approve() {
  brow "$1" status=closed assignee= notes= metadata.task_kind=review metadata.anchor_bead=anc-1 "metadata.check_name=$2" \
    metadata.reviewed_oid=deadbeef metadata.signoff_verdict=approve metadata.gc.outcome=recorded
}
# with_lanes: the anchor, and an approve backing each of its lanes.
with_lanes() { reset "$ANCHOR_PR"; approve rv-c correctness; approve rv-a arch; }
green() { "$HERE/lane-state.sh" green --anchor anc-1 --lane "$1" --no-remote; }

echo "# --- happy path: a ruling on an open PR mints the fix unit and dispatches it ---"
reset "$ANCHOR_PR"
OUT=$("$SUT" --anchor anc-1 --ruling-bead vis-1 --ruling "apply the amendment directly to docs/material-layers.md" 2>&1); RC=$?
eq "$RC" "0" "exit 0 on a clean mint+dispatch"
eq "$(created)" "1" "exactly one rework child created"
eq "$(meta new-2 task_kind)" "rework" "child is task_kind=rework"
eq "$(meta new-2 anchor_bead)" "anc-1" "child names the anchor"
eq "$(meta new-2 branch)" "polecat/anc-1" "child resumes the anchor's branch"
eq "$(meta new-2 target)" "main" "child lands where the anchor lands"
eq "$(meta new-2 merge_strategy)" "mr" "child is merge_strategy=mr"
eq "$(meta new-2 source_ruling_bead)" "vis-1" "child names the ruling's conversation as source_ruling_bead"
eq "$(meta new-2 source_review_bead)" "<absent>" "child carries NO source_review_bead (a ruling has no verdict)"
eq "$(meta new-2 existing_pr)" "https://github.com/o/r/pull/42" "child keeps the rework on this PR (existing_pr)"
eq "$(meta new-2 pr_number)" "42" "child carries pr_number"
has "$(meta new-2 rejection_reason)" "apply the amendment" "rejection_reason carries the ruling"
has "$(meta new-2 rejection_reason)" "vis-1" "rejection_reason names the conversation"
if blocks_anchor new-2 anc-1; then ok "child blocks the anchor (merge held by the edge)"; else bad "child does NOT block the anchor"; fi
eq "$(meta new-2 gc.execution_routed_to)" "gc-toolkit/gc-toolkit.polecat" "child was slung (execution_routed_to read back)"
has "$OUT" "filed rework new-2 on anchor anc-1" "reports the filed child"
eq "$(meta new-2 prepare_mode)" "<absent>" "prepare_mode left unset (resume defaults merge; refinery re-stamps)"

echo "# --- PR-finishing work: the shift, no parent, and the priority it is slung at ---"
# The anchor sits under a P2 epic, its posture in the shape pr-facts.sh stores
# it. A ruling's rework of a PR that is not approved is slung one level sooner
# than its anchor, at P1, and of an approved PR at P0. A rank that compared the
# whole stored posture with approved would sling the second at P1.
OID=0f38036a1b2c3d4e5f60718293a4b5c6d7e8f901
under_epic() { # <posture>: the anchor moved under a P2 epic, with that posture read at the PR's head
  reset "$ANCHOR_PR"
  bset anc-1 "metadata.pr_posture=$1" "metadata.pr_head_oid=$OID" 'priority:=4' \
    'dependencies:=[{"issue_id":"anc-1","depends_on_id":"ep-2","type":"parent-child"}]'
  brow ep-2 status=open assignee= notes= issue_type=epic 'priority:=2' 'metadata:={}'
}
under_epic "commented@$OID@2026-10-11T00:00:00Z"
"$SUT" --anchor anc-1 --ruling-bead vis-1 --ruling "apply the amendment" >/dev/null 2>&1
eq "$(meta new-3 priority_shift)" "-1" "the ruling's rework is born carrying the PR-finishing shift"
eq "$(bparents new-3)" "" "…with no parent, so no hold on an epic reaches it"
eq "$(bpoured new-3)" "1" "…and slung at P1, one level sooner than its anchor under a P2 epic"
under_epic "approved@$OID@2026-10-11T00:00:00Z"
"$SUT" --anchor anc-1 --ruling-bead vis-1 --ruling "apply the amendment" >/dev/null 2>&1
eq "$(bpoured new-3)" "0" "a ruling's rework of an approved PR is slung at P0"
reset "$ANCHOR_PR"
"$SUT" --anchor anc-1 --ruling-bead vis-1 --ruling "apply the amendment directly to docs/material-layers.md" >/dev/null 2>&1

echo "# --- idempotency: a second run on the same ruling files no second child ---"
OUT=$("$SUT" --anchor anc-1 --ruling-bead vis-1 --ruling "apply the amendment directly to docs/material-layers.md" 2>&1); RC=$?
eq "$RC" "0" "exit 0 on the re-run"
eq "$(created)" "1" "still exactly one child (dedup on source_ruling_bead)"
has "$OUT" "already dispatched" "re-run reports the child is already in flight"

echo "# --- a later ruling of the same conversation is refused while its first rework is open ---"
# A conversation can rule on a turn that does not sign off and again at its
# sign-off, and both rulings key their rework on the conversation. The writer
# adopts the live child with the work order it was filed with, so a later
# ruling it adopted would never reach the branch.
reset "$ANCHOR_PR"
"$SUT" --anchor anc-1 --ruling-bead vis-1 --ruling "apply the amendment" >/dev/null 2>&1
: > "$STUB_GC_LOG"
OUT=$("$SUT" --anchor anc-1 --ruling-bead vis-1 --ruling "also rename the section" 2>&1); RC=$?
eq "$RC" "2" "exit 2 when the conversation's open rework records another ruling"
eq "$(created)" "1" "…filing no second child"
has "$OUT" 'new-2, which records "operator ruling (conversation vis-1): apply the amendment"' "…naming the open rework and what it carries"
eq "$(grep -c -E '^(bd update|bd dep|bd create|sling)' "$STUB_GC_LOG")" "0" "…with nothing written"
hasnt "$(meta new-2 rejection_reason)" "rename the section" "…so the open rework's work order is as it was filed"
OUT=$("$SUT" --anchor anc-1 --ruling-bead vis-1 --ruling "apply the amendment" 2>&1); RC=$?
eq "$RC" "0" "a re-run of the first ruling still adopts its rework"
eq "$(created)" "1" "…filing no second child"
bset new-2 status=closed
OUT=$("$SUT" --anchor anc-1 --ruling-bead vis-1 --ruling "also rename the section" 2>&1); RC=$?
eq "$RC" "0" "once the first rework has landed and closed, the later ruling is filed"
eq "$(created)" "2" "…as a child of its own"
has "$(meta new-3 rejection_reason)" "also rename the section" "…carrying the later ruling"

echo "# --- an open PR on the pending record takes the ruling as an ask to its review run ---"
# The ask's writer is gctk review ask, whose rules its own suite proves, so a
# stub stands in for it here: it logs its call and answers as the real one does.
cat > "$TMP/gctk-ask" <<'ASK'
#!/usr/bin/env bash
echo "$*" >> "$TMP_ASK_LOG"
echo "${GCTK_SCRIPTS_DIR:-unset}" >> "$TMP_ASK_LOG.env"
[ "${STUB_ASK_RC:-0}" = 0 ] || { echo "gctk review ask: anc-1: the check index at the head declares no check \"nope\"" >&2; exit 3; }
echo "ask-1 ${STUB_ASK_HOW:-filed}"
ASK
chmod +x "$TMP/gctk-ask"
export TMP_ASK_LOG="$TMP/ask.log"
for rec in "pull_request_pending blocked" "pull_request_head_changed open"; do
  set -- $rec
  reset "$ANCHOR_PR"
  bset anc-1 "metadata.merge_result=$1" "status=$2"
  : > "$TMP_ASK_LOG"; : > "$TMP_ASK_LOG.env"
  OUT=$(env -u GCTK_SCRIPTS_DIR GCTK_BIN="$TMP/gctk-ask" "$SUT" --anchor anc-1 --ruling-bead vis-1 --ruling "apply the amendment directly to docs/material-layers.md" --check arch 2>&1); RC=$?
  eq "$RC" "0" "$1: exit 0 once the ask stands"
  eq "$(cat "$TMP_ASK_LOG.env")" "$HERE" "$1: the checked ask names the pack's scripts beside converse-rework.sh, with none in the caller's environment"
  eq "$(created)" "0" "$1: no rework child is filed"
  eq "$(cat "$TMP_ASK_LOG")" "review ask anc-1 --reason operator ruling (conversation vis-1): apply the amendment directly to docs/material-layers.md --source vis-1 --check arch" "$1: the ask carries the ruling, the conversation as its source, and the checks it names"
  eq "$(printf '%s\n' "$OUT" | tail -n 1)" "ask-1 ask filed" "$1: the last line names the ask, as a child's line names the child"
  hasnt "$(cat "$STUB_GC_LOG")" "sling" "$1: nothing is slung"
  hasnt "$OUT" "returned anc-1's lanes to unreviewed" "$1: nothing is superseded"
done
OUT=$(STUB_ASK_HOW=found GCTK_BIN="$TMP/gctk-ask" "$SUT" --anchor anc-1 --ruling-bead vis-1 --ruling "apply the amendment directly to docs/material-layers.md" 2>&1); RC=$?
eq "$RC $(printf '%s\n' "$OUT" | tail -n 1)" "0 ask-1 ask found" "a re-run names the ask the first filed"
OUT=$(STUB_ASK_RC=3 GCTK_BIN="$TMP/gctk-ask" "$SUT" --anchor anc-1 --ruling-bead vis-1 --ruling "x" --check nope 2>&1); RC=$?
eq "$RC" "2" "an ask the writer refuses exits 2"
has "$OUT" "declares no check" "…naming why"
reset "$ANCHOR_PR"
OUT=$("$SUT" --anchor anc-1 --ruling-bead vis-1 --ruling "x" --check arch 2>&1); RC=$?
eq "$RC $(created)" "2 0" "--check on the old path is refused, with nothing filed"

echo "# --- guard: a non-PR anchor is refused, nothing filed ---"
reset '[{"id":"anc-1","status":"open","metadata":{"merge_result":"","branch":"polecat/anc-1","target":"main"}}]'
OUT=$("$SUT" --anchor anc-1 --ruling-bead vis-1 --ruling "x" 2>&1); RC=$?
eq "$RC" "2" "exit 2 when the anchor is not an open PR"
eq "$(created)" "0" "no child filed for a non-PR anchor"
has "$OUT" "not an open PR's (pull_request, pull_request_pending or pull_request_head_changed)" "says why it refused"

echo "# --- guard: an open PR with no branch is refused ---"
reset '[{"id":"anc-1","status":"open","metadata":{"merge_result":"pull_request","target":"main"}}]'
OUT=$("$SUT" --anchor anc-1 --ruling-bead vis-1 --ruling "x" 2>&1); RC=$?
eq "$RC" "2" "exit 2 when the anchor names no branch"
eq "$(created)" "0" "no child filed when the branch is unknown"

echo "# --- guard: an open PR with no landing target is refused ---"
reset '[{"id":"anc-1","status":"open","metadata":{"merge_result":"pull_request","branch":"polecat/anc-1"}}]'
OUT=$("$SUT" --anchor anc-1 --ruling-bead vis-1 --ruling "x" 2>&1); RC=$?
eq "$RC" "2" "exit 2 when the anchor names no target"
eq "$(created)" "0" "no child filed when the target is unknown"

echo "# --- guard: an anchor still at pull_request but not an open PR is refused ---"
# merge_result alone does not prove the PR open: a hand-closed anchor keeps the
# field, and a disposed one sits at pull_request until pr-facts.sh consummates
# the close. Each is refused before the writer runs.
guard() { # <label> <expected message fragment> <fixture writer and its arguments...>
  local label="$1" says="$2"
  shift 2
  reset "$ANCHOR_PR"
  "$@"
  OUT=$("$SUT" --anchor anc-1 --ruling-bead vis-1 --ruling "x" 2>&1); RC=$?
  eq "$RC" "2" "exit 2 when $label"
  has "$OUT" "$says" "…saying why"
  eq "$(created)" "0" "…and no child filed"
  eq "$(grep -c '^bd list' "$STUB_GC_LOG")" "0" "…before the writer's dedup read"
}
guard "the anchor is closed" "status='closed', not live" bset anc-1 status=closed
guard "pr-dispose.sh has disposed the anchor" "gc.pr_close_disposition_kind=not-needed" bset anc-1 metadata.gc.pr_close_disposition_kind=not-needed
guard "the anchor is superseded" "superseded by anc-2" bset anc-1 'dependencies:=[{"id":"anc-2","dependency_type":"supersedes"}]'
guard "the anchor is a duplicate" "superseded by anc-2" bset anc-1 'dependencies:=[{"id":"anc-2","dependency_type":"duplicates"}]'
guard "the anchor names no PR" "names no PR" bunset anc-1 metadata.existing_pr metadata.pr_url

echo "# --- no double-dispatch: a partial pour (no route stamped) refuses the bare-route fallback ---"
# The pour exits 0 and never stamps the route on the child it is about to file.
reset "$ANCHOR_PR"
OUT=$(STUB_DROP_KEYS="new-2:gc.execution_routed_to" "$SUT" --anchor anc-1 --ruling-bead vis-1 --ruling "x" 2>&1); RC=$?
eq "$RC" "2" "exit 2 when the pour did not stamp the route"
eq "$(created)" "1" "the child is filed"
if blocks_anchor new-2 anc-1; then ok "the child still blocks the anchor (merge stays held for the retry)"; else bad "the child does not block the anchor"; fi
eq "$(meta new-2 gc.execution_routed_to)" "<absent>" "no bare route stamped (no double-dispatch)"
has "$OUT" "double-dispatch hazard" "says why it refused to bare-stamp"

echo "# --- fail-closed: an unreadable dedup query files nothing ---"
reset "$ANCHOR_PR"
OUT=$(STUB_LIST_FAIL=1 "$SUT" --anchor anc-1 --ruling-bead vis-1 --ruling "x" 2>&1); RC=$?
eq "$RC" "2" "exit 2 when the dedup query is unreadable"
eq "$(created)" "0" "no child filed on an unreadable dedup query"

echo "# --- identity at create: a create whose id never came back is adopted on the retry, not twinned ---"
# The child is in the store, but the run never learned its id, so nothing past the
# create ran: no work order, no edge, no pour. The dedup finds a prior child only
# by source_ruling_bead, so that key must ride in the create itself; a child born
# bare and keyed by a later write is invisible to the retry, which files a twin.
reset "$ANCHOR_PR"
OUT=$(STUB_CREATE_GARBAGE=1 "$SUT" --anchor anc-1 --ruling-bead vis-1 --ruling "apply the amendment" 2>&1); RC=$?
eq "$RC" "2" "exit 2 when the create returned no id"
has "$OUT" "returned no id" "says the create's id was lost"
eq "$(created)" "1" "the create landed exactly one child"
eq "$(meta new-2 source_ruling_bead)" "vis-1" "the child carries the ruling's key from its create"
eq "$(meta new-2 task_kind)" "rework" "…and its role marker"
eq "$(meta new-2 anchor_bead)" "anc-1" "…and the anchor it belongs to"
eq "$(meta new-2 branch)" "<absent>" "no work order was stamped on a child whose id never came back"
eq "$(meta new-2 gc.execution_routed_to)" "<absent>" "…and it was never dispatched"
OUT=$("$SUT" --anchor anc-1 --ruling-bead vis-1 --ruling "apply the amendment" 2>&1); RC=$?
eq "$RC" "0" "the retry exits 0"
eq "$(created)" "1" "the retry files NO second child"
has "$OUT" "adopting existing open rework child new-2" "…it adopts the child the lost-id create filed"
eq "$(meta new-2 branch)" "polecat/anc-1" "the adopted child is stamped with the full work order"
has "$(meta new-2 rejection_reason)" "apply the amendment" "…including the ruling as its rejection_reason"
eq "$(meta new-2 gc.execution_routed_to)" "gc-toolkit/gc-toolkit.polecat" "the adopted child is dispatched on the retry"
eq "$(grep -cxF 'new-2|blocks|anc-1' "$STUB_DEPS")" "1" "exactly one edge holds the anchor"

echo "# --- provenance: a review's rework child is never adopted for a ruling ---"
# The source key is the dedup key, so a live child a review verdict filed on the
# same anchor answers that review, not this ruling: the ruling files its own.
reset "$ANCHOR_PR"
brow rv-kid status=open assignee= notes= metadata.task_kind=rework metadata.anchor_bead=anc-1 metadata.source_review_bead=rv-1 \
  metadata.branch=polecat/anc-1 metadata.target=main
OUT=$("$SUT" --anchor anc-1 --ruling-bead vis-1 --ruling "x" 2>&1); RC=$?
eq "$RC" "0" "exit 0"
eq "$(created)" "1" "the ruling files its own child beside the review's"
eq "$(meta new-3 source_ruling_bead)" "vis-1" "…keyed on the ruling"
eq "$(meta rv-kid source_ruling_bead)" "<absent>" "the review's child is not re-keyed"
eq "$(meta rv-kid gc.execution_routed_to)" "<absent>" "…nor dispatched by the ruling"

echo "# --- every lane returns to unreviewed once the ruling's child is dispatched ---"
# A ruling has no lane of its own, so the approves every lane holds were of a
# branch the ruling has outdated. Left standing they keep each lane green, and
# the merge passes on the rework no review read.
with_lanes
if green correctness && green arch; then ok "both lanes are green before the ruling"; else bad "setup: the lanes are not green"; fi
OUT=$("$SUT" --anchor anc-1 --ruling-bead vis-1 --ruling "apply the amendment" 2>&1); RC=$?
eq "$RC" "0" "exit 0 once the child is dispatched and the lanes are returned"
eq "$(meta rv-c gc.outcome)" "superseded" "the correctness approve is superseded"
eq "$(meta rv-a gc.outcome)" "superseded" "…and the arch approve"
if green correctness; then bad "correctness still derives green after the ruling"; else ok "correctness no longer derives green"; fi
if green arch; then bad "arch still derives green after the ruling"; else ok "…nor arch"; fi
has "$(notes rv-c)" "operator ruling (conversation vis-1): superseded (anchor-wide) — rework new-4" \
  "the superseded review names the ruling and the child"
has "$OUT" "2 standing review(s) superseded" "the run reports the lanes it returned"
so_sl=$(grep -n '^sling ' "$STUB_GC_LOG" | head -1 | cut -d: -f1)
so_sp=$(grep -n '^bd update rv-c ' "$STUB_GC_LOG" | head -1 | cut -d: -f1)
if [ -n "$so_sl" ] && [ -n "$so_sp" ] && [ "$so_sl" -lt "$so_sp" ]; then
  ok "…after the child is dispatched, so quiescence already holds every review dispatch"
else
  bad "the supersede did not follow the dispatch (sling@${so_sl:-none} supersede@${so_sp:-none})"
fi
OUT=$("$SUT" --anchor anc-1 --ruling-bead vis-1 --ruling "apply the amendment" 2>&1); RC=$?
eq "$RC" "0" "the re-run exits 0"
has "$OUT" "0 standing review(s) superseded" "…with nothing left to supersede"
eq "$(created)" "1" "…and no second child"

echo "# --- the lanes are resolved at the head of the anchor's branch ---"
with_lanes
OUT=$("$SUT" --anchor anc-1 --ruling-bead vis-1 --ruling "apply the amendment" 2>&1); RC=$?
eq "$RC" "0" "exit 0"
has "$(cat "$STUB_GIT_LOG")" "-C $STUB_RIG_PATH ls-remote origin refs/heads/polecat/anc-1" "the head of the anchor's branch is read from origin in the anchor's rig checkout"
eq "$(meta rv-c gc.outcome)" "superseded" "…and the supersede it names resolves the lanes"

echo "# --- from another checkout, the head is read and the lanes resolved in the anchor's rig ---"
# A sitting runs from the city or another rig's checkout. With no index named
# outright, the lanes resolve at the head's commit, which the anchor's rig
# checkout holds and the sitting's checkout does not, so a supersede resolved
# in the sitting's directory finds no repository holding it.
OTHER="$TMP/other-checkout"; git init -q "$OTHER"
RIG_HEAD=$(git -C "$STUB_RIG_PATH" rev-parse HEAD)
with_lanes
OUT=$(cd "$OTHER" && env -u GC_REVIEW_CHECKS_INDEX -u GC_RIG_ROOT STUB_LS_REMOTE_HEAD="$RIG_HEAD" \
  "$SUT" --anchor anc-1 --ruling-bead vis-1 --ruling "apply the amendment" 2>&1); RC=$?
eq "$RC" "0" "exit 0 from another checkout"
has "$(cat "$STUB_GIT_LOG")" "-C $STUB_RIG_PATH ls-remote origin refs/heads/polecat/anc-1" "…the head read in the anchor's rig checkout"
eq "$(meta rv-c gc.outcome)" "superseded" "…and the lanes resolved at that head there and returned"
eq "$(meta rv-a gc.outcome)" "superseded" "…every lane"

echo "# --- an anchor whose rig checkout does not resolve refuses with nothing written ---"
with_lanes
echo '{"rigs":[]}' > "$STUB_RIGS"
OUT=$("$SUT" --anchor anc-1 --ruling-bead vis-1 --ruling "apply the amendment" 2>&1); RC=$?
eq "$RC" "2" "exit 2 when no rig carries the anchor's prefix"
has "$OUT" "rig checkout did not resolve" "…saying why"
eq "$(created)" "0" "…no child filed"
eq "$(grep -c 'ls-remote' "$STUB_GIT_LOG")" "0" "…and no head read in any other repository"
eq "$(meta rv-c gc.outcome)" "recorded" "…and the approves stand"

echo "# --- a head that does not read refuses with nothing written ---"
with_lanes
OUT=$(STUB_LS_REMOTE_MISS="polecat/anc-1" "$SUT" --anchor anc-1 --ruling-bead vis-1 --ruling "apply the amendment" 2>&1); RC=$?
eq "$RC" "2" "exit 2 when the branch's head does not read"
has "$OUT" "did not read from origin" "…saying why"
eq "$(created)" "0" "…no child filed"
eq "$(meta rv-c gc.outcome)" "recorded" "…and the approves stand"
eq "$(grep -c '^bd list' "$STUB_GC_LOG")" "0" "…before the writer's dedup read"

echo "# --- a supersede that fails fails the run, and the re-run finishes it ---"
with_lanes
bunset anc-1 metadata.check_set
OUT=$("$SUT" --anchor anc-1 --ruling-bead vis-1 --ruling "x" 2>&1); RC=$?
eq "$RC" "2" "exit 2 when the lanes cannot be returned (no check_set to resolve them from)"
has "$OUT" "rework new-4 is dispatched, but the review lanes on anc-1 did not return to unreviewed" "…saying the child stands and the lanes do not"
eq "$(meta new-4 gc.execution_routed_to)" "gc-toolkit/gc-toolkit.polecat" "the child stands dispatched"
eq "$(meta rv-c gc.outcome)" "recorded" "…and the approves stand"
bset anc-1 metadata.check_set=correctness,arch
OUT=$("$SUT" --anchor anc-1 --ruling-bead vis-1 --ruling "x" 2>&1); RC=$?
eq "$RC" "0" "the re-run exits 0"
eq "$(created)" "1" "…adopting the dispatched child rather than filing a second"
eq "$(meta rv-c gc.outcome)" "superseded" "…and returns the lanes"

echo "# --- a filing the writer does not dispatch returns no lane ---"
with_lanes
OUT=$(STUB_DROP_KEYS="new-4:gc.execution_routed_to" "$SUT" --anchor anc-1 --ruling-bead vis-1 --ruling "x" 2>&1); RC=$?
eq "$RC" "2" "the writer's exit code is the run's"
eq "$(meta rv-c gc.outcome)" "recorded" "the approves stand while the child's edge holds the merge for the retry"

echo "# --- two stores: the child is filed, edged and slung in the anchor's own rig ---"
# The anchor rb-anc lives in rig-b's store, and the ruling's conversation in
# rig-a's. converse-signoff.sh runs this script with GC_RIG naming the anchor's
# rig, so the dedup, the create, the blocks edge, the pool and the sling all act
# in rig-b. Run from the conversation's rig instead, the child lands in rig-a,
# where no edge onto rb-anc can be added or proved, and nothing is dispatched.
two_stores() {
  rm -rf "$RIG_A/.beads" "$RIG_B/.beads"
  harness_store "$RIG_A/.beads"; harness_store "$RIG_B/.beads"
  printf '%s\n' "${ANCHOR_PR//anc-1/rb-anc}" > "$RIG_B/.beads/beads.json"
  rigs two
  : > "$STUB_GC_LOG"
}
# in_rig <rig> <id>: does that rig's store hold the bead?
in_rig() { if [ "$(GC_RIG="$1" bstatus "$2")" = "<absent>" ]; then echo false; else echo true; fi; }
two_stores
OUT=$(GC_RIG=rig-b "$SUT" --anchor rb-anc --ruling-bead ra-conv --ruling "apply the amendment" 2>&1); RC=$?
eq "$RC" "0" "(TWO-STORES) a run pinned to the anchor's rig exits 0"
eq "$(in_rig rig-b new-2)/$(in_rig rig-a new-2)" "true/false" "(TWO-STORES) …filing the child in the anchor's store, not the conversation's"
if blocks_anchor new-2 rb-anc; then ok "(TWO-STORES) …its blocks edge onto the anchor in that store, where the anchor's merge reads it"; else bad "(TWO-STORES) no blocks edge onto rb-anc in rig-b's store"; fi
eq "$(GC_RIG=rig-b meta new-2 source_ruling_bead)" "ra-conv" "(TWO-STORES) …the conversation in the other rig its provenance"
eq "$(GC_RIG=rig-b meta new-2 gc.execution_routed_to)" "rig-b/gc-toolkit.polecat" "(TWO-STORES) …and slung to the anchor's rig's pool"
has "$(grep '^sling ' "$STUB_GC_LOG")" "sling --rig rig-b rig-b/gc-toolkit.polecat new-2 --on mol-polecat-work" "(TWO-STORES) …through a sling in that rig"
two_stores
OUT=$(GC_RIG=rig-a "$SUT" --anchor rb-anc --ruling-bead ra-conv --ruling "apply the amendment" 2>&1); RC=$?
eq "$RC" "2" "(TWO-STORES-AMBIENT) the same run from the conversation's rig exits 2"
has "$OUT" "work order incomplete (blocks_edge)" "(TWO-STORES-AMBIENT) …the child's blocks edge onto the anchor in another store not provable"
eq "$(in_rig rig-a new-1)" "true" "(TWO-STORES-AMBIENT) …because the child landed in the conversation's store"
eq "$(grep -c '^sling ' "$STUB_GC_LOG")" "0" "(TWO-STORES-AMBIENT) …and nothing is dispatched"

echo
echo "===================="
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
