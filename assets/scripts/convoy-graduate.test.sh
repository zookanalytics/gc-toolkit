#!/usr/bin/env bash
# Hermetic test for assets/scripts/convoy-graduate.sh — convoy graduation.
# Covers: the happy path (assignee/branch/target/merge_strategy/graduation);
# rig-local reads only, with no gc convoy query; membership counted from
# parent-child children and tracks edges, closed or tombstoned meaning done and
# a dangling tracks edge meaning not done; the non-vacuous-completion guard (no
# recorded merge onto the branch = no graduation); operator holds on the
# convoy bead and on a separate bead naming the branch; a live branch owner;
# idempotency via metadata.branch; a ## Summary seeded from the landed members
# with an existing summary left intact; fail-closed skips on unreadable probes
# and a non-zero abort on an unreadable enumeration; the interval watermark;
# and the GC_AGENT-unset skip.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-convoy-graduate-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"
harness_init
SUT="$HERE/convoy-graduate.sh"
[ -x "$SUT" ] || chmod +x "$SUT"

export GC_AGENT="rig/gc-toolkit.refinery"

cbead() { # id target [extra-metadata] [tracked ids, comma-joined] — an open owned convoy
  local deps="" t
  for t in $(printf '%s' "${4:-}" | tr ',' ' '); do
    deps="${deps:+$deps,}{\"issue_id\":\"$1\",\"depends_on_id\":\"$t\",\"type\":\"tracks\"}"
  done
  printf '{"id":"%s","status":"open","assignee":"","notes":"","issue_type":"convoy","labels":["owned"],"dependencies":[%s],"metadata":{"target":"%s"%s}}' \
    "$1" "$deps" "$2" "${3:+,$3}"
}
landed() { # id branch — a closed bead that recorded a merge onto <branch>
  printf '{"id":"%s","status":"closed","assignee":"","notes":"","metadata":{"merged_target":"%s","merge_result":"merged"}}' "$1" "$2"
}
work() { # id status
  printf '{"id":"%s","status":"%s","assignee":"","notes":"","metadata":{}}' "$1" "$2"
}
edges() { # "A|TYPE|B"... — replaces the edge set (child|parent-child|convoy, convoy|tracks|member)
  : > "$STUB_DEPS"
  [ "$#" -eq 0 ] || printf '%s\n' "$@" > "$STUB_DEPS"
}
convoy_calls() { grep -c '^convoy' "$STUB_GC_LOG" || true; }

echo "# happy path"
store "[$(cbead cv-1 integration/feat), $(landed w-1 integration/feat), $(work w-2 closed)]"
edges "w-1|parent-child|cv-1" "w-2|parent-child|cv-1"
: > "$STUB_GC_LOG"
out=$("$SUT" --target main 2>&1); rc=$?
eq "$rc" 0 "graduation pass exits 0"
has "$out" "graduating cv-1 — integration/feat -> main (mr" "the convoy graduates"
eq "$(bassignee cv-1)" "$GC_AGENT" "assignee = the refinery"
eq "$(meta cv-1 branch)" "integration/feat" "branch = the integration branch"
eq "$(meta cv-1 target)" "main" "target = the graduation target"
eq "$(meta cv-1 merge_strategy)" "mr" "merge_strategy = mr (human-approved PR)"
eq "$(meta cv-1 graduation)" "true" "graduation marker stamped"
eq "$(convoy_calls)" 0 "no gc convoy query runs"

echo "# idempotent: a graduated convoy leaves the candidate set"
out=$("$SUT" --target main 2>&1)
has "$out" "no complete owned integration convoys" "a graduated convoy is no longer a candidate"
eq "$(bassignee cv-1)" "$GC_AGENT" "…and keeps its assignment"
# A branch alone keeps a convoy out, even one whose target still names the
# integration branch.
store "[$(cbead cv-b integration/started '"branch":"integration/started"'), $(landed w-b integration/started)]"
edges "w-b|parent-child|cv-b"
out=$("$SUT" --target main 2>&1)
has "$out" "no complete owned integration convoys" "a convoy already carrying a branch is not a candidate"
eq "$(bassignee cv-b)" "" "…and is not assigned"

echo "# idempotent: a branch stamped after the list read is honoured"
store "[$(cbead cv-r integration/race), $(landed w-r integration/race)]"
edges "w-r|parent-child|cv-r"
cat > "$TMP/race-hook" <<'HOOK'
#!/usr/bin/env bash
[ "$1" = cv-r ] || exit 0
jq -c 'map(if .id == "cv-r" then .metadata.branch = "integration/race" else . end)' "$STUB_STORE" > "$STUB_STORE.race" \
  && mv "$STUB_STORE.race" "$STUB_STORE"
HOOK
chmod +x "$TMP/race-hook"
out=$(STUB_SHOW_HOOK="$TMP/race-hook" "$SUT" 2>&1)
has "$out" "1 skipped" "a convoy whose fresh read carries a branch is skipped"
eq "$(bassignee cv-r)" "" "…and not re-assigned"

echo "# vacuous completion refuses"
store "[$(cbead cv-2 integration/empty), $(work w-2a closed)]"
edges "w-2a|parent-child|cv-2"
out=$("$SUT" 2>&1)
has "$out" "no bead records a merge onto 'integration/empty'" "no recorded landing = no graduation"
has "$out" "1 vacuous" "…counted apart"
eq "$(meta cv-2 branch)" "<absent>" "…and nothing was assigned"

echo "# an open member, an empty convoy, or an un-owned convoy never reaches the gates"
store "[$(cbead cv-3 integration/x), $(landed w-3 integration/x), $(work w-3o open),
        $(cbead cv-e integration/none),
        {\"id\":\"cv-4\",\"status\":\"open\",\"assignee\":\"\",\"notes\":\"\",\"issue_type\":\"convoy\",\"labels\":[],\"metadata\":{\"target\":\"integration/y\"}},
        $(landed w-4 integration/y)]"
edges "w-3|parent-child|cv-3" "w-3o|parent-child|cv-3" "w-4|parent-child|cv-4"
out=$("$SUT" 2>&1)
has "$out" "0 graduating, 0 skipped, 0 held, 0 vacuous, 2 incomplete" "an open member and a memberless convoy are both incomplete"
eq "$(meta cv-3 branch)" "<absent>" "…the convoy with an open member is not assigned"
eq "$(meta cv-4 branch)" "<absent>" "an un-owned convoy is not a candidate, even with every member closed"

echo "# tracks members count, resolved in this rig's store"
store "[$(cbead cv-t integration/trk '' m-1,m-2), $(landed m-1 integration/trk), $(work m-2 tombstone)]"
edges "cv-t|tracks|m-1" "cv-t|tracks|m-2"
out=$("$SUT" 2>&1)
has "$out" "graduating cv-t" "a convoy whose tracked members are closed or tombstoned graduates"

echo "# an open tracked member holds the convoy"
store "[$(cbead cv-to integration/trko '' m-3,m-4), $(landed m-3 integration/trko), $(work m-4 in_progress)]"
edges "cv-to|tracks|m-3" "cv-to|tracks|m-4"
out=$("$SUT" 2>&1)
has "$out" "1 incomplete" "an in_progress tracked member makes the convoy incomplete"
eq "$(meta cv-to branch)" "<absent>" "…and nothing was assigned"

echo "# a tracks edge to a bead this store cannot read holds the convoy"
store "[$(cbead cv-d integration/dang '' m-5,ghost-1), $(landed m-5 integration/dang)]"
edges "cv-d|tracks|m-5" "cv-d|tracks|ghost-1"
out=$("$SUT" 2>&1)
has "$out" "tracks edge(s) to ghost-1 name no bead" "the dangling edge is named"
has "$out" "1 incomplete" "…and counts as unfinished work, not done"
eq "$(meta cv-d branch)" "<absent>" "…and nothing was assigned"

echo "# operator hold on the convoy bead"
store "[$(cbead cv-5 integration/h '"merge_hold":"true"'), $(landed w-5 integration/h)]"
edges "w-5|parent-child|cv-5"
out=$("$SUT" 2>&1)
has "$out" "operator gate); not graduated" "merge_hold on the convoy vetoes"
eq "$(meta cv-5 branch)" "<absent>" "…and nothing was assigned"

echo "# hold on a SEPARATE bead naming the branch"
store "[$(cbead cv-6 integration/f), $(landed w-6 integration/f),
        {\"id\":\"rb-1\",\"status\":\"blocked\",\"assignee\":\"\",\"notes\":\"\",\"metadata\":{\"branch\":\"integration/f\",\"rebase_hold\":\"true\"}}]"
edges "w-6|parent-child|cv-6"
out=$("$SUT" 2>&1)
has "$out" "rb-1 holds branch 'integration/f'" "a held sibling bead vetoes (even blocked — not-open is not gone)"

echo "# live unheld branch owner"
store "[$(cbead cv-7 integration/g), $(landed w-7 integration/g),
        {\"id\":\"own-1\",\"status\":\"open\",\"assignee\":\"\",\"notes\":\"\",\"metadata\":{\"branch\":\"integration/g\"}}]"
edges "w-7|parent-child|cv-7"
out=$("$SUT" 2>&1)
has "$out" "own-1 already owns branch 'integration/g'" "a live owner blocks a duplicate graduation"

echo "# unreadable probes fail closed"
store "[$(cbead cv-8 integration/z), $(landed w-8 integration/z)]"
edges "w-8|parent-child|cv-8"
for probe in "branch=integration/z" "merged_target=integration/z"; do
  out=$(STUB_LIST_FAIL_ON="$probe" "$SUT" 2>&1); rc=$?
  eq "$rc" 0 "a failed $probe probe does not abort the pass"
  hasnt "$out" "graduating cv-8" "…but nothing graduates on a read that could not answer"
done
out=$(STUB_DEP_PARTIAL=1 "$SUT" 2>&1); rc=$?
eq "$rc" 0 "a failed member read does not abort the pass"
has "$out" "cv-8 — member read failed" "…it names the convoy it could not read"
out=$(STUB_DEP_GARBAGE=1 "$SUT" 2>&1)
has "$out" "cv-8 — member read failed" "a member read that is not JSON is unreadable, not empty"
out=$(STUB_SHOW_FAIL=1 "$SUT" 2>&1)
has "$out" "cv-8 — convoy bead read failed" "an unreadable convoy bead skips the candidate"
eq "$(meta cv-8 branch)" "<absent>" "…and cv-8 was never assigned"

echo "# every read is this rig's store's"
export GC_RIG=myrig
store "[$(cbead cv-9 integration/scoped), $(landed w-9 integration/scoped)]"
edges "w-9|parent-child|cv-9"
: > "$STUB_GC_LOG"
out=$("$SUT" 2>&1)
has "$out" "graduating cv-9" "the convoy graduates"
bd_calls=$(grep -c '^bd ' "$STUB_GC_LOG" || true)
rig_calls=$(grep -c '^bd .*--rig=myrig' "$STUB_GC_LOG" || true)
eq "$rig_calls" "$bd_calls" "every bead read and the write name --rig=myrig"
eq "$(convoy_calls)" 0 "…and no gc convoy query runs"
unset GC_RIG

echo "# a rig with no owned integration convoy costs one read"
store "[]"; edges
: > "$STUB_GC_LOG"
out=$("$SUT" 2>&1); rc=$?
eq "$rc" 0 "an empty rig exits 0"
has "$out" "no complete owned integration convoys" "…and says there is nothing to graduate"
eq "$(wc -l < "$STUB_GC_LOG" | tr -d ' ')" 1 "…after the one rig-store list"
eq "$(convoy_calls)" 0 "…and no gc convoy query"

echo "# GC_AGENT unset skips"
out=$(env -u GC_AGENT "$SUT" 2>&1); rc=$?
eq "$rc" 0 "no identity exits 0"
has "$out" "GC_AGENT unset; skip" "…and says why"

echo "# graduation seeds the ## Summary from the landed members"
store "[$(cbead cv-s integration/syn),
  {\"id\":\"m-1\",\"status\":\"closed\",\"assignee\":\"\",\"title\":\"Add the widget\",\"notes\":\"\",\"metadata\":{\"merged_target\":\"integration/syn\",\"merge_result\":\"merged\",\"pr_summary\":\"Adds a widget to the toolbar.\"}},
  {\"id\":\"m-2\",\"status\":\"closed\",\"assignee\":\"\",\"title\":\"Wire the widget\",\"notes\":\"\",\"metadata\":{\"merged_target\":\"integration/syn\",\"merge_result\":\"merged\",\"pr_summary\":\"Wires the widget to the store.\"}}]"
edges "m-1|parent-child|cv-s" "m-2|parent-child|cv-s"
out=$("$SUT" --target main 2>&1); rc=$?
eq "$rc" 0 "seeded graduation exits 0"
has "$out" "graduating cv-s" "the convoy graduates"
ps="$(meta cv-s pr_summary)"
has "$ps" "landing the work of these beads" "a seed summary is composed from the members"
has "$ps" "m-1" "…names the first landed member"
has "$ps" "m-2" "…and every other landed member"
has "$ps" "Adds a widget to the toolbar." "…and carries each member's own reviewed pr_summary"

echo "# an already-authored summary is preserved (read-modify-write)"
store "[$(cbead cv-k integration/keep '"pr_summary":"Operator-written summary."'),
  {\"id\":\"m-3\",\"status\":\"closed\",\"assignee\":\"\",\"title\":\"Some work\",\"notes\":\"\",\"metadata\":{\"merged_target\":\"integration/keep\",\"merge_result\":\"merged\",\"pr_summary\":\"member summary\"}}]"
edges "m-3|parent-child|cv-k"
out=$("$SUT" --target main 2>&1)
has "$out" "graduating cv-k" "the convoy graduates"
eq "$(meta cv-k pr_summary)" "Operator-written summary." "an existing summary is not overwritten by the seed"

echo "# disk pressure: a failed mktemp aborts non-zero, never a false all-clear"
# The CANDS guard proves the candidate list non-empty, so a loop that then runs
# zero times can only be a silently-failed <<< temp file. The remedy routes the
# loop through an explicit mktemp; force THAT to fail and the pass must abort
# loudly rather than print "0 graduating, …" + exit 0. A failing mktemp binary on
# PATH is the hermetic stand-in for a full disk (bash's own <<< temp file is
# internal and cannot be stubbed, which is exactly why the remedy replaces it).
store "[$(cbead cv-df integration/df), $(landed w-df integration/df)]"
edges "w-df|parent-child|cv-df"
mkdir -p "$TMP/failbin"
cat > "$TMP/failbin/mktemp" <<'MK'
#!/usr/bin/env bash
echo "mktemp: failed to create file via template: Disk quota exceeded" >&2
exit 1
MK
chmod +x "$TMP/failbin/mktemp"
df_rc=0
PATH="$TMP/failbin:$PATH" "$SUT" --target main >"$TMP/df.out" 2>"$TMP/df.err" || df_rc=$?
eq "$([ "$df_rc" -ne 0 ] && echo nonzero || echo zero)" "nonzero" "a mktemp failure aborts the pass non-zero"
# The forged summary would land on STDOUT; the abort announcement on STDERR. Check
# each on its own stream, so the summary text quoted inside the abort message is
# not mistaken for the summary line itself.
hasnt "$(cat "$TMP/df.out")" "graduating" "no summary line reaches stdout under disk pressure"
has "$(cat "$TMP/df.err")" "ABORTING non-zero" "…the blackout is announced on stderr"

echo "# a failed rig list is could-not-enumerate, not an empty rig"
out=$(STUB_LIST_FAIL=1 "$SUT" 2>&1); rc=$?
eq "$([ "$rc" -ne 0 ] && echo nonzero || echo zero)" "nonzero" "an unreadable rig list aborts non-zero"
has "$out" "could not list this rig's open owned convoys" "…and says it could not enumerate"
hasnt "$out" "graduating" "…never a forged summary"

echo "# a rig list the candidate render cannot read is could-not-enumerate"
store '[{"id":"cv-m","status":"open","issue_type":"convoy","labels":["owned"],"metadata":"not an object"}]'
edges
out=$("$SUT" 2>&1); rc=$?
eq "$([ "$rc" -ne 0 ] && echo nonzero || echo zero)" "nonzero" "a jq render failure aborts non-zero"
has "$out" "could not render candidates" "…and says it could not enumerate"

echo "# the interval watermark"
STAMPF="$TMP/convoy-graduate.stamp"
stamp_now() { # <stamp> <floor> — the stamp is a start time no earlier than <floor>, no later than now
  local s; s=$(cat "$1" 2>/dev/null)
  case "$s" in ''|*[!0-9]*) return 1 ;; esac
  [ "$s" -ge "$2" ] && [ "$s" -le "$(date -u +%s)" ]
}
store "[$(cbead cv-w integration/wm), $(landed w-w integration/wm), $(work w-wo open)]"
edges "w-w|parent-child|cv-w" "w-wo|parent-child|cv-w"
rm -f "$STAMPF"
t0=$(date -u +%s)
out=$("$SUT" --stamp "$STAMPF" 2>&1); rc=$?
eq "$rc" 0 "a pass with no stamp yet runs and exits 0"
has "$out" "1 incomplete" "…having answered its one candidate"
stamp_now "$STAMPF" "$t0" && ok "…and stamps its start time" || bad "…and stamps its start time (stamp '$(cat "$STAMPF" 2>/dev/null)')"

: > "$STUB_GC_LOG"
out=$("$SUT" --stamp "$STAMPF" 2>&1); rc=$?
eq "$rc" 0 "a pass inside the interval exits 0"
has "$out" "last complete pass" "…says it is waiting out the interval"
eq "$(wc -l < "$STUB_GC_LOG" | tr -d ' ')" 0 "…and reads nothing"

printf '%s\n' "$(( $(date -u +%s) - 901 ))" > "$STAMPF"
t0=$(date -u +%s)
out=$("$SUT" --stamp "$STAMPF" 2>&1)
has "$out" "1 incomplete" "a stamp older than 15 minutes lets the pass run"
stamp_now "$STAMPF" "$t0" && ok "…and the pass re-stamps" || bad "…and the pass re-stamps (stamp '$(cat "$STAMPF" 2>/dev/null)')"

printf '%s\n' "$(( $(date -u +%s) + 3600 ))" > "$STAMPF"
out=$("$SUT" --stamp "$STAMPF" 2>&1)
has "$out" "1 incomplete" "a stamp ahead of the clock does not park the arm"

printf 'not-a-time\n' > "$STAMPF"
out=$("$SUT" --stamp "$STAMPF" 2>&1)
has "$out" "1 incomplete" "an unreadable stamp lets the pass run"

printf '1000\n' > "$STAMPF"
out=$(STUB_DEP_PARTIAL=1 "$SUT" --stamp "$STAMPF" 2>&1); rc=$?
eq "$rc" 0 "a pass that could not read a candidate exits 0"
eq "$(cat "$STAMPF")" "1000" "…and leaves the stamp, so the next pass retries it"

out=$(STUB_LIST_FAIL=1 "$SUT" --stamp "$STAMPF" 2>&1); rc=$?
eq "$([ "$rc" -ne 0 ] && echo nonzero || echo zero)" "nonzero" "an aborted pass exits non-zero"
eq "$(cat "$STAMPF")" "1000" "…and leaves the stamp"

store "[]"; edges
rm -f "$STAMPF"
t0=$(date -u +%s)
out=$("$SUT" --stamp "$STAMPF" 2>&1)
has "$out" "no complete owned integration convoys" "a rig with no candidate finishes its pass"
stamp_now "$STAMPF" "$t0" && ok "…and stamps it" || bad "…and stamps it (stamp '$(cat "$STAMPF" 2>/dev/null)')"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
