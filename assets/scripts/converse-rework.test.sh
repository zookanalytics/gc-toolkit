#!/usr/bin/env bash
# Hermetic test for assets/scripts/converse-rework.sh — an operator ruling's entry
# to rework — over the compiled fake gc of test-harness.sh, with a stub for
# gctk's ask. No live city, Dolt, or network. An anchor on the pending record
# takes the ruling as an ask to its review run, with the checks the ruling
# names, read from the check index beside this checkout's scripts whatever the
# binding, and each bead the ruling waits on, and nothing filed, slung or
# superseded. The open-PR guards refuse, before the ask: an anchor off the
# pending record, one that is not live, carries a disposition, or names no
# branch, target or PR.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../../tools/test-floor.sh" || exit 2
SUT="$HERE/converse-rework.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-converse-rework-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# The shared harness: the compiled fake gc, and gctk built from this checkout,
# which reads the check index for the scripts under test.
# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"
harness_build_gctk
harness_init
export GC_RIG="gc-toolkit"

# reset <store-json>: seed the store and clear the logs.
reset() {
  store "$1"
  : > "$STUB_DEPS"; : > "$STUB_GC_LOG"
}
# The fake mints new-<N> for its store's Nth row, so created counts the beads a
# run filed beside the fixture.
created() {
  local n=0 id
  while IFS= read -r id; do case "$id" in new-*) n=$((n + 1)) ;; esac; done < <(bids)
  echo "$n"
}

ANCHOR_PR='[{"id":"anc-1","status":"open","assignee":"","notes":"","metadata":{"merge_result":"pull_request_pending","branch":"polecat/anc-1","target":"main","existing_pr":"https://github.com/o/r/pull/42","pr_url":"https://github.com/o/r/pull/42","pr_number":"42","check_set":"correctness,arch"}}]'

echo "# --- an open PR on the pending record takes the ruling as an ask to its review run ---"
# The ask's writer is gctk review ask, whose rules its own suite proves, so a
# stub stands in for it here: it logs its call and answers as the real one does.
cat > "$TMP/gctk-ask" <<'ASK'
#!/usr/bin/env bash
echo "$*" >> "$TMP_ASK_LOG"
echo "${GCTK_SCRIPTS_DIR:-unset}" >> "$TMP_ASK_LOG.env"
[ "${STUB_ASK_RC:-0}" = 0 ] || { echo "${STUB_ASK_ERR:-gctk review ask: anc-1: the check index at the head declares no check \"nope\"}" >&2; exit "$STUB_ASK_RC"; }
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
hasnt "$OUT" "a re-run finds one that landed" "…promising no ask to a re-run the writer refuses the same way"
: > "$STUB_GC_LOG"
OUT=$(STUB_ASK_RC=1 STUB_ASK_ERR="gctk review ask: unknown flag: --waiting-on" GCTK_BIN="$TMP/gctk-ask" "$SUT" --anchor anc-1 --ruling-bead vis-1 --ruling "x" --waiting-on anc-43 2>&1); RC=$?
eq "$RC $(created)" "2 0" "an ask whose arguments the writer does not take, such as a gctk older than the option, exits 2 with nothing filed"
has "$OUT" "unknown flag: --waiting-on" "…naming the argument it did not take"
hasnt "$OUT" "a re-run finds one that landed" "…promising no ask to a re-run"
eq "$(grep -c -E '^(bd update|bd dep|bd create|sling)' "$STUB_GC_LOG")" "0" "…with nothing written"
OUT=$(STUB_ASK_RC=2 STUB_ASK_ERR="gctk review ask: anc-1: ledger: the filing may not have landed" GCTK_BIN="$TMP/gctk-ask" "$SUT" --anchor anc-1 --ruling-bead vis-1 --ruling "x" 2>&1); RC=$?
eq "$RC" "2" "an ask whose create did not answer exits 2"
has "$OUT" "a re-run finds one that landed" "…saying a re-run finds the ask if it landed"
# A ruling that must wait for other work passes each bead it waits on to the
# writer, which files the ask with those waits in the one create, or refuses a
# bead whose edge would hold nothing, such as one of another prefix, with
# nothing filed.
: > "$TMP_ASK_LOG"; : > "$STUB_GC_LOG"
OUT=$(GCTK_BIN="$TMP/gctk-ask" "$SUT" --anchor anc-1 --ruling-bead vis-1 --ruling "rename the flag once #43 lands" --check arch --waiting-on anc-43 --waiting-on anc-44 2>&1); RC=$?
eq "$RC $(created)" "0 0" "a ruling that waits on other work exits 0 once the ask stands, filing no rework child"
eq "$(cat "$TMP_ASK_LOG")" "review ask anc-1 --reason operator ruling (conversation vis-1): rename the flag once #43 lands --source vis-1 --check arch --waiting-on anc-43 --waiting-on anc-44" "…the ask carries each bead the ruling waits on"
hasnt "$(cat "$STUB_GC_LOG")" "sling" "…and nothing is slung"
: > "$STUB_GC_LOG"
OUT=$(STUB_ASK_RC=3 STUB_ASK_ERR="gctk review ask: nothing filed on anc-1: rb-43 does not carry the id prefix of anc-1, and bd keeps an edge between beads of two prefixes as one into another rig's store, which holds nothing even when this store holds the bead" \
  GCTK_BIN="$TMP/gctk-ask" "$SUT" --anchor anc-1 --ruling-bead vis-1 --ruling "rename the flag once rb-43 lands" --waiting-on rb-43 2>&1); RC=$?
eq "$RC $(created)" "2 0" "a wait on a bead in another store, which the writer refuses, exits 2 with nothing filed"
has "$OUT" "rb-43 does not carry the id prefix of anc-1" "…naming the bead the ask could not wait on"
eq "$(grep -c -E '^(bd update|bd dep|bd create|sling)' "$STUB_GC_LOG")" "0" "…with nothing written"
OUT=$("$SUT" --anchor anc-1 --ruling-bead vis-1 --ruling "x" --waiting-on 2>&1); RC=$?
eq "$RC" "2" "--waiting-on with no bead is refused"

echo "# --- guard: a non-PR anchor is refused, nothing filed ---"
reset '[{"id":"anc-1","status":"open","metadata":{"merge_result":"","branch":"polecat/anc-1","target":"main"}}]'
OUT=$("$SUT" --anchor anc-1 --ruling-bead vis-1 --ruling "x" 2>&1); RC=$?
eq "$RC" "2" "exit 2 when the anchor is not an open PR"
eq "$(created)" "0" "no child filed for a non-PR anchor"
has "$OUT" "not an open PR's (pull_request_pending or pull_request_head_changed)" "says why it refused"

echo "# --- guard: an open PR with no branch is refused ---"
reset '[{"id":"anc-1","status":"open","metadata":{"merge_result":"pull_request_pending","target":"main"}}]'
OUT=$("$SUT" --anchor anc-1 --ruling-bead vis-1 --ruling "x" 2>&1); RC=$?
eq "$RC" "2" "exit 2 when the anchor names no branch"
eq "$(created)" "0" "no child filed when the branch is unknown"

echo "# --- guard: an open PR with no landing target is refused ---"
reset '[{"id":"anc-1","status":"open","metadata":{"merge_result":"pull_request_pending","branch":"polecat/anc-1"}}]'
OUT=$("$SUT" --anchor anc-1 --ruling-bead vis-1 --ruling "x" 2>&1); RC=$?
eq "$RC" "2" "exit 2 when the anchor names no target"
eq "$(created)" "0" "no child filed when the target is unknown"

echo "# --- guard: an anchor still on the record but not an open PR is refused ---"
# merge_result alone does not prove the PR open: a hand-closed anchor keeps the
# field, and a disposed one keeps its record until the landing order
# consummates the close. Each is refused before the writer runs.
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

echo
echo "===================="
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
