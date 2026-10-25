#!/usr/bin/env bash
# Hermetic test for merge-push's zero-diff guard (the `zero-diff-guard` block of
# formulas/mol-refinery-patrol.toml) across two patrol attempts at one direct
# landing.
#
# The guard parks a bead whose branch introduces no change against its target
# as refused_false_completion. A direct landing whose push lands and whose
# record fails leaves that shape behind, because origin/<target> then carries
# the branch. direct-merge-push.sh stamps direct_landing_sha on the bead before
# it pushes, and the guard sends a bead whose target carries the stamp down the
# direct path, which records the landing.
#
# Each attempt runs the real blocks, extracted verbatim from the formula, in the
# order a patrol runs them: the rebase step's shared-branch-merge-mode, then
# merge-push's branch-has-real-change, zero-diff-guard and, for a direct bead,
# direct-merge-push. A few lines stand in for merge-push's opening read, which
# gives the guard the bead, the strategy and lifecycle.sh. The gate between the
# two steps judges the prepared head and decides nothing here, so it is left
# out. The blocks run against real git repositories, the real
# direct-merge-push.sh, refinery-workspace.sh, detached-job.sh and bd-lib.sh, a
# stub gc that keeps the bead in a file, and stub lifecycle.sh and escalate.sh
# that log. They run from a directory that is no git checkout, as a refinery's
# scratch directory is, so every git call has to name the rig by path.
# Proves:
#   - an attempt that pushes and then cannot record leaves the landing on
#     origin, the stamp on the bead and the branch on origin, and the next
#     attempt stages the branch again and records the landing at the stamped
#     commit without parking, escalating or draining, whether origin/main
#     stayed at the landing or moved on past it, and whatever strategy the
#     bead reads by then; the branch is deleted once the landing is recorded;
#   - a branch that never introduced work is still refused, parked and
#     escalated, with no stamp and with a stamp its target does not carry, and
#     so is a branch whose commits net to no change;
#   - a check that cannot run leaves the work with the refinery to retry,
#     counting the failures in a row on the bead, and the third parks it
#     blocked: its park and its visit say the check could not run, and name
#     git's error and the directory, never that the branch has no change. A
#     check that runs clears the count.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TOML="$ROOT/formulas/mol-refinery-patrol.toml"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-unrecorded-direct-landing-test.XXXXXX")"
# git names the prep worktree under the repository's resolved path, so every
# path is built on a resolved root.
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1${2:+ ($2)}"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3" "got '$1' want '$2'"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3" "missing '$2' in: $1" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3" "found '$2' in: $1" ;; *) ok "$3" ;; esac; }

command -v git >/dev/null 2>&1 || { echo "git is required" >&2; exit 1; }
command -v jq  >/dev/null 2>&1 || { echo "jq is required"  >&2; exit 1; }
[ -s "$TOML" ] || { echo "missing $TOML" >&2; exit 1; }

unset GC_RIG_ROOT GC_RIG GC_CITY GC_CITY_PATH GC_PACK_DIR GC_BD_LIB GC_RECONCILE_BD_CACHE 2>/dev/null || true
unset DIRECT_MERGE_PUSH_ATTEMPTS DIRECT_MERGE_PUSH_BACKOFF 2>/dev/null || true
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR 2>/dev/null || true
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

fence() { awk -v m="$1" '$0 ~ ("# >>> " m "$") {f=1; next} $0 ~ ("# <<< " m "$") {f=0} f' "$TOML"; }

echo "── the blocks ──"
for m in shared-branch-merge-mode branch-has-real-change zero-diff-guard direct-merge-push; do
  if [ -n "$(fence "$m")" ]; then ok "$m: extracted between its markers"; else bad "$m: extracted between its markers"; fi
done
fence shared-branch-merge-mode > "$TMP/prep.sh"
# delete_merged_branches takes the patrol's default, true.
{
  echo 'BEAD_JSON=$(gc bd show $WORK --json)'
  echo 'MERGE_STRATEGY="$STRATEGY"'
  echo 'LC="${TEST_LC:-$GC_CITY_PATH/rigs/gc-toolkit/assets/scripts/lifecycle.sh}"'
  fence branch-has-real-change
  fence zero-diff-guard
  echo 'if [ "$MERGE_STRATEGY" = direct ]; then'
  fence direct-merge-push | sed 's|{{delete_merged_branches}}|true|g'
  echo 'fi'
  echo 'echo "MERGE_STRATEGY=$MERGE_STRATEGY"'
} > "$TMP/merge-push.sh"
for f in prep merge-push; do
  case "$(cat "$TMP/$f.sh")" in
    *'{{'*) bad "$f: no unrendered formula placeholder left" ;;
    *)      ok  "$f: no unrendered formula placeholder left" ;;
  esac
  if bash -n "$TMP/$f.sh" 2>/dev/null; then ok "$f: valid bash"; else bad "$f: valid bash"; fi
done

# bare_git <file>: the first argument of every git invocation that does not
# start with -C, outside comment lines.
bare_git() {
  awk '
    /^[[:space:]]*#/ { next }
    {
      line = $0
      while (match(line, "(^|[^-.A-Za-z0-9_/])git[[:space:]]+[^[:space:]]+")) {
        n = split(substr(line, RSTART, RLENGTH), w, "[[:space:]]+")
        if (w[n] != "-C") print w[n]
        line = substr(line, RSTART + RLENGTH)
      }
    }' "$1" | tr '\n' ' '
}
fence branch-has-real-change > "$TMP/bhrc.sh"
fence zero-diff-guard > "$TMP/zdg.sh"
eq "$(bare_git "$TMP/bhrc.sh")" "" "branch-has-real-change: every git call names its repo with -C"
eq "$(bare_git "$TMP/zdg.sh")" "rev-parse " "zero-diff-guard: the only git call without -C is the pack-script locator's"

# The pack the blocks find their scripts in, through GC_CITY_PATH.
CITY="$TMP/city"
PACK="$CITY/rigs/gc-toolkit/assets/scripts"
mkdir -p "$PACK" "$TMP/bin"
cp "$HERE/direct-merge-push.sh" "$HERE/bd-lib.sh" "$HERE/refinery-workspace.sh" "$HERE/detached-job.sh" "$HERE/rig-root.sh" "$PACK/"
cat > "$PACK/lifecycle.sh" <<'LC'
#!/usr/bin/env bash
echo "$*" >> "$FAKE_LC_LOG"
[ -z "${LC_FAIL:-}" ] || { echo "lifecycle: refused" >&2; exit 1; }
exit 0
LC
cat > "$PACK/escalate.sh" <<'ESC'
#!/usr/bin/env bash
echo "escalate $*" >> "$FAKE_LOG"
ESC
chmod +x "$PACK"/*.sh
# gc answers the roster for `rig list` and the bead file for `bd show`, applies
# each --set-metadata and --unset-metadata of a `bd update` to that file, and
# logs every other call.
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
case "$1 $2" in
  "rig list") cat "$FAKE_ROSTER" ;;
  "bd show")  cat "$FAKE_META" ;;
  *)
    echo "$*" >> "$FAKE_LOG"
    if [ "$1 $2" = "bd update" ]; then
      shift 3
      while [ $# -gt 0 ]; do
        case "$1" in
          --set-metadata)
            jq --arg kv "$2" '.[0].metadata[($kv | sub("=.*$"; ""))] = ($kv | sub("^[^=]*="; ""))' "$FAKE_META" > "$FAKE_META.new" \
              && mv "$FAKE_META.new" "$FAKE_META"
            shift 2 ;;
          --unset-metadata)
            jq --arg k "$2" 'del(.[0].metadata[$k])' "$FAKE_META" > "$FAKE_META.new" && mv "$FAKE_META.new" "$FAKE_META"
            shift 2 ;;
          *) shift ;;
        esac
      done
    fi ;;
esac
exit 0
GC
chmod +x "$TMP/bin/gc"
export PATH="$TMP/bin:$PATH"

# The cwd every block runs from: a directory git finds no repository in, as in
# a scratch directory under the system temp dir.
ELSEWHERE="$TMP/elsewhere"
mkdir -p "$ELSEWHERE"
if git -C "$ELSEWHERE" rev-parse --git-dir >/dev/null 2>&1; then
  bad "precondition: the blocks' cwd is no git checkout" "$ELSEWHERE is inside one"
else
  ok "precondition: the blocks' cwd is no git checkout"
fi

# commit <repo> <message>: a commit that adds a file, since the guard judges a
# branch by the change in its tree.
commit() {
  printf '%s\n' "$2" > "$1/${2// /-}"
  git -C "$1" add -A
  git -C "$1" commit -q -m "$2"
  git -C "$1" rev-parse HEAD
}
stamp() { jq -r '.[0].metadata.direct_landing_sha // "none"' "$D/bead.json"; }
on_origin() { if git -C "$D/origin.git" rev-parse -q --verify "refs/heads/$1" >/dev/null; then echo yes; else echo no; fi; }
merged_tries() { grep -c '^transition wb --to merged ' "$D/lc.log"; }

# fixture <dir> work|nowork|netzero: origin with main at BASE and polecat/wb
# one commit ahead of it (work), at BASE itself (nowork), or two commits ahead
# whose second removes what the first added (netzero), the rig cloned from it,
# and a direct-strategy bead. Sets D, BASE, FEATURE and PREP.
fixture() {
  D="$1"
  mkdir -p "$D"
  git init -q --bare -b main "$D/origin.git"
  git init -q -b main "$D/seed"
  BASE=$(commit "$D/seed" "base")
  git -C "$D/seed" push -q "$D/origin.git" main
  git -C "$D/seed" checkout -q -b polecat/wb
  case "$2" in
    work) FEATURE=$(commit "$D/seed" "feature") ;;
    netzero)
      commit "$D/seed" "added then removed" >/dev/null
      git -C "$D/seed" rm -q added-then-removed
      git -C "$D/seed" commit -q -m "remove it again"
      FEATURE=$(git -C "$D/seed" rev-parse HEAD) ;;
    *) FEATURE="$BASE" ;;
  esac
  git -C "$D/seed" push -q "$D/origin.git" polecat/wb
  git -C "$D/seed" checkout -q main
  git clone -q "$D/origin.git" "$D/rig"
  PREP="$(git -C "$D/rig" rev-parse --path-format=absolute --git-common-dir)/gc-refinery-prep"
  printf '{"rigs":[{"name":"myrig","path":"%s"}]}\n' "$D/rig" > "$D/roster.json"
  printf '%s\n' '[{"id":"wb","status":"in_progress","metadata":{"branch":"polecat/wb","target":"main","merge_strategy":"direct"}}]' > "$D/bead.json"
}

# attempt [<env>...]: one patrol's prepare, then its merge-push, both from a
# directory that is no checkout, the bead read as a direct one unless STRATEGY
# says otherwise.
# The logs start over, so each attempt's assertions read only its own calls.
# Sets PREP_RC, RC and OUT.
attempt() {
  : > "$D/gc.log"; : > "$D/lc.log"
  local run=(env GC_RIG_ROOT="$D/rig" GC_RIG=myrig GC_CITY_PATH="$CITY" WORK=wb BRANCH=polecat/wb TARGET=main
    TARGET_BRANCH_DEFAULT=main FAKE_ROSTER="$D/roster.json" FAKE_META="$D/bead.json" FAKE_LOG="$D/gc.log"
    FAKE_LC_LOG="$D/lc.log" DIRECT_MERGE_PUSH_BACKOFF=0 STRATEGY=direct "$@")
  ( cd "$ELSEWHERE" && "${run[@]}" bash "$TMP/prep.sh" ) >"$D/prep.out" 2>&1; PREP_RC=$?
  OUT=$(cd "$ELSEWHERE" && "${run[@]}" bash "$TMP/merge-push.sh" 2>&1); RC=$?
}
recorded_at() { # <label> <sha>: one transition, recording and closing at <sha>
  case "$(cat "$D/lc.log")" in
    "transition wb --to merged --close --set merged_sha=$2 --set merged_target=main --unset rejection_reason --unset direct_landing_sha --append-notes Merged to main at "*)
      ok "$1: recorded and closed at ${2:0:9} through one lifecycle transition" ;;
    *) bad "$1: recorded and closed at ${2:0:9} through one lifecycle transition" "$(cat "$D/lc.log")" ;;
  esac
}
not_parked() { # <label>: no refusal, no escalation, no drain
  hasnt "$(cat "$D/lc.log")" "refused_false_completion" "$1: the bead is not parked as a false completion"
  hasnt "$(cat "$D/gc.log")" "escalate " "$1: nothing is escalated"
  hasnt "$(cat "$D/gc.log")" "runtime drain-ack" "$1: the session does not drain"
}
# unrecorded_landing <label>: the first attempt, whose record never lands.
unrecorded_landing() {
  attempt LC_FAIL=1
  eq "$PREP_RC" 0 "$1, first attempt: the prepare stages the branch"
  eq "$RC" 1 "$1, first attempt: merge-push stops"
  eq "$(git -C "$D/origin.git" rev-parse main)" "$FEATURE" "$1, first attempt: the push landed on origin/main"
  eq "$(merged_tries)" 3 "$1, first attempt: the record was tried three times"
  eq "$(stamp)" "$FEATURE" "$1, first attempt: the bead keeps the stamp"
  eq "$(on_origin polecat/wb)" yes "$1, first attempt: the branch stays on origin for the next attempt to stage"
  hasnt "$(cat "$D/lc.log")" "refused_false_completion" "$1, first attempt: the bead is not parked as a false completion"
}

echo "── a landing whose record failed: the next patrol records it ──"
fixture "$TMP/same" work
unrecorded_landing same
attempt
eq "$PREP_RC" 0 "same, next attempt: the prepare stages the branch"
eq "$(git -C "$PREP" rev-parse HEAD)" "$FEATURE" "same, next attempt: precondition, the prepared head is origin/main's tip, the landing"
eq "$RC" 0 "same, next attempt: merge-push exits 0"
has "$OUT" "pushed without recording; taking the direct path to record it" "same, next attempt: the guard names the unrecorded landing"
recorded_at "same, next attempt" "$FEATURE"
not_parked "same, next attempt"
eq "$(git -C "$D/origin.git" rev-parse main)" "$FEATURE" "same, next attempt: origin/main is unchanged"
eq "$(on_origin polecat/wb)" no "same, next attempt: the branch is deleted once the landing is recorded"

echo "── the same, after origin/main moved on past the landing ──"
fixture "$TMP/later" work
unrecorded_landing later
git -C "$D/seed" fetch -q "$D/origin.git" main
git -C "$D/seed" checkout -q -B main FETCH_HEAD
LATER=$(commit "$D/seed" "landed after the unrecorded landing")
git -C "$D/seed" push -q "$D/origin.git" main
attempt
eq "$(git -C "$PREP" rev-parse HEAD)" "$LATER" "later, next attempt: precondition, the prepared head is the later tip"
eq "$RC" 0 "later, next attempt: merge-push exits 0"
recorded_at "later, next attempt (the landing, not the later tip)" "$FEATURE"
not_parked "later, next attempt"

echo "── the same, when the next attempt reads the bead as mr ──"
fixture "$TMP/mr" work
unrecorded_landing mr
attempt STRATEGY=mr
eq "$RC" 0 "mr, next attempt: merge-push exits 0"
has "$OUT" "MERGE_STRATEGY=direct" "mr, next attempt: the guard sends the bead down the direct path"
recorded_at "mr, next attempt" "$FEATURE"
not_parked "mr, next attempt"

echo "── a branch that never introduced work is refused ──"
fixture "$TMP/nowork" nowork
attempt
eq "$PREP_RC" 0 "nowork: the prepare stages the branch"
eq "$RC" 1 "nowork: merge-push stops"
has "$(cat "$D/lc.log")" "transition wb --to refused_false_completion" "nowork: the bead is parked as a false completion"
has "$(cat "$D/gc.log")" "escalate --subject wb --key refinery-false-completion" "nowork: the refusal is escalated"
has "$(cat "$D/gc.log")" "runtime drain-ack" "nowork: the session drains"
eq "$(merged_tries)" 0 "nowork: nothing is recorded as merged"
eq "$(git -C "$D/origin.git" rev-parse main)" "$BASE" "nowork: nothing is pushed"

echo "── the same, with a stamp the target does not carry ──"
fixture "$TMP/stale" nowork
git -C "$D/seed" checkout -q -b side "$BASE"
SIDE=$(commit "$D/seed" "a push that never landed")
git -C "$D/seed" push -q "$D/origin.git" side
jq --arg s "$SIDE" '.[0].metadata.direct_landing_sha = $s' "$D/bead.json" > "$D/bead.json.new" && mv "$D/bead.json.new" "$D/bead.json"
attempt
eq "$RC" 1 "stale: merge-push stops"
has "$(cat "$D/lc.log")" "transition wb --to refused_false_completion" "stale: the bead is parked as a false completion"
has "$(cat "$D/gc.log")" "escalate --subject wb --key refinery-false-completion" "stale: the refusal is escalated"
eq "$(merged_tries)" 0 "stale: nothing is recorded as merged"
eq "$(git -C "$D/origin.git" rev-parse main)" "$BASE" "stale: nothing is pushed"

echo "── a refusal files its visit through the pack lifecycle.sh came from ──"
# The refinery sits in a scratch directory, GC_RIG_ROOT is unset so the rig
# comes from the roster, and GC_CITY_PATH names no pack. GC_PACK_DIR holds
# rig-root.sh alone, so the block resolves the rig, and the only place that
# names the rest of the pack is the lifecycle.sh the step found.
RR_ONLY="$TMP/rig-root-only"
mkdir -p "$RR_ONLY/assets/scripts"
cp "$HERE/rig-root.sh" "$RR_ONLY/assets/scripts/"
fixture "$TMP/nopack" nowork
: > "$D/gc.log"; : > "$D/lc.log"
( cd "$ELSEWHERE" && env GC_RIG_ROOT="$D/rig" GC_RIG=myrig GC_CITY_PATH="$CITY" WORK=wb BRANCH=polecat/wb TARGET=main \
    TARGET_BRANCH_DEFAULT=main FAKE_ROSTER="$D/roster.json" FAKE_META="$D/bead.json" FAKE_LOG="$D/gc.log" \
    FAKE_LC_LOG="$D/lc.log" bash "$TMP/prep.sh" ) >"$D/prep.out" 2>&1; PREP_RC=$?
eq "$PREP_RC" 0 "nopack: the prepare stages the branch"
nopack_merge_push() { # <lifecycle.sh> [<GC_PACK_DIR>]
  : > "$D/gc.log"; : > "$D/lc.log"
  OUT=$(cd "$ELSEWHERE" && env GC_PACK_DIR="${2-$RR_ONLY}" GC_RIG_ROOT="" GC_RIG=myrig GC_CITY_PATH="" TEST_LC="$1" WORK=wb BRANCH=polecat/wb \
    TARGET=main FAKE_ROSTER="$D/roster.json" FAKE_META="$D/bead.json" FAKE_LOG="$D/gc.log" FAKE_LC_LOG="$D/lc.log" \
    STRATEGY=direct bash "$TMP/merge-push.sh" 2>&1); RC=$?
}
nopack_merge_push "$PACK/lifecycle.sh"
eq "$RC" 1 "nopack: merge-push stops"
has "$(cat "$D/lc.log")" "transition wb --to refused_false_completion" "nopack: the bead is parked as a false completion"
has "$(cat "$D/gc.log")" "escalate --subject wb --key refinery-false-completion" "nopack: the refusal files its visit"
# A lifecycle.sh with no escalate.sh beside it, and no other pack location:
# the park stands, and the block says no visit was filed.
mkdir -p "$TMP/lc-only/assets/scripts"
cp "$PACK/lifecycle.sh" "$TMP/lc-only/assets/scripts/lifecycle.sh"
nopack_merge_push "$TMP/lc-only/assets/scripts/lifecycle.sh"
eq "$RC" 1 "nopack/no escalate.sh: merge-push stops"
has "$(cat "$D/lc.log")" "transition wb --to refused_false_completion" "nopack/no escalate.sh: the bead is parked as a false completion"
hasnt "$(cat "$D/gc.log")" "escalate " "nopack/no escalate.sh: no visit is filed"
has "$OUT" "is parked for a human with no refinery-false-completion visit" "nopack/no escalate.sh: the block says the park has no visit"
# With no pack location at all, rig-root.sh is not found, so the rig does not
# resolve: the block stops before the check, parks nothing and leaves the work
# with the refinery to retry.
nopack_merge_push "$PACK/lifecycle.sh" ""
eq "$RC" 1 "nopack/no rig-root.sh: merge-push stops"
has "$OUT" "cannot resolve the rig root; leaving the work with the refinery to retry" "nopack/no rig-root.sh: the block says the rig did not resolve"
hasnt "$(cat "$D/lc.log")" "transition" "nopack/no rig-root.sh: nothing is parked"
hasnt "$(cat "$D/gc.log")" "escalate " "nopack/no rig-root.sh: nothing is escalated"
has "$(cat "$D/gc.log")" "runtime drain-ack" "nopack/no rig-root.sh: the session drains"

echo "── a branch whose commits net to no change is refused ──"
fixture "$TMP/netzero" netzero
attempt
eq "$PREP_RC" 0 "netzero: the prepare stages the branch"
eq "$(git -C "$PREP" rev-list --count "$BASE..HEAD" 2>/dev/null || echo 0)" 2 "netzero: precondition, the prepared head is two commits ahead of the target"
eq "$RC" 1 "netzero: merge-push stops"
has "$(cat "$D/lc.log")" "transition wb --to refused_false_completion" "netzero: the bead is parked as a false completion"
has "$(cat "$D/gc.log")" "escalate --subject wb --key refinery-false-completion" "netzero: the refusal is escalated"
eq "$(merged_tries)" 0 "netzero: nothing is recorded as merged"
eq "$(git -C "$D/origin.git" rev-parse main)" "$BASE" "netzero: nothing is pushed"

echo "── a check that cannot run is retried, then parked as a failed check, not as a branch without work ──"
fixture "$TMP/nocheck" work
# The prepare alone stages the branch; then the rig loses origin/main, so the
# check cannot find the merge-base it needs, on every patrol until it returns.
: > "$D/gc.log"; : > "$D/lc.log"
NOCHECK_ENV=(env GC_RIG_ROOT="$D/rig" GC_RIG=myrig GC_CITY_PATH="$CITY" WORK=wb BRANCH=polecat/wb TARGET=main
  TARGET_BRANCH_DEFAULT=main FAKE_ROSTER="$D/roster.json" FAKE_META="$D/bead.json" FAKE_LOG="$D/gc.log"
  FAKE_LC_LOG="$D/lc.log" STRATEGY=direct)
( cd "$ELSEWHERE" && "${NOCHECK_ENV[@]}" bash "$TMP/prep.sh" ) >"$D/prep.out" 2>&1; PREP_RC=$?
eq "$PREP_RC" 0 "nocheck: the prepare stages the branch"
git -C "$D/rig" update-ref -d refs/remotes/origin/main
fails() { jq -r '.[0].metadata.zero_diff_check_failures // "none"' "$D/bead.json"; }
nocheck_merge_push() {
  : > "$D/gc.log"; : > "$D/lc.log"
  OUT=$(cd "$ELSEWHERE" && "${NOCHECK_ENV[@]}" bash "$TMP/merge-push.sh" 2>&1); RC=$?
}
for n in 1 2; do
  nocheck_merge_push
  eq "$RC" 1 "nocheck, patrol $n: merge-push stops"
  has "$OUT" "the zero-diff check could not run in $D/rig: merge-base origin/main " \
    "nocheck, patrol $n: it says the check could not run, in the rig, and names the failed git call"
  has "$OUT" "Not a valid object name origin/main (failure $n of 3 in a row); leaving the work with the refinery to retry" \
    "nocheck, patrol $n: it carries git's own error and leaves the work with the refinery"
  eq "$(cat "$D/lc.log")" "" "nocheck, patrol $n: the bead is not parked"
  hasnt "$(cat "$D/gc.log")" "escalate " "nocheck, patrol $n: nothing is escalated"
  has "$(cat "$D/gc.log")" "runtime drain-ack" "nocheck, patrol $n: the session drains"
  eq "$(fails)" "$n" "nocheck, patrol $n: the bead counts $n failed check(s) in a row"
done
nocheck_merge_push
eq "$RC" 1 "nocheck, patrol 3: merge-push stops"
has "$(cat "$D/lc.log")" "transition wb --to blocked --assignee  --route human --set blocked_reason=the zero-diff check could not run in $D/rig, 3 patrols in a row: merge-base origin/main " \
  "nocheck, patrol 3: the bead is parked blocked, its reason naming the rig, the count and the failed git call"
has "$(cat "$D/lc.log")" "Not a valid object name origin/main; no change verified, refused merge-close --unset zero_diff_check_failures" \
  "nocheck, patrol 3: the park carries git's own error and clears the count"
has "$(cat "$D/lc.log")" "--takeaway the zero-diff check could not run 3 patrols in a row, so no change was verified" "nocheck, patrol 3: the board's takeaway says the check could not run"
hasnt "$(cat "$D/lc.log")" "refused_false_completion" "nocheck, patrol 3: the bead is not parked as a false completion"
hasnt "$(cat "$D/lc.log")" "false_completion_suspected" "nocheck, patrol 3: no false completion is recorded as suspected"
has "$(cat "$D/gc.log")" "escalate --subject wb --key refinery-zero-diff-check-failed --message The zero-diff check of branch polecat/wb against origin/main could not run in $D/rig, 3 patrols in a row. The last error: merge-base origin/main " \
  "nocheck, patrol 3: the visit is a failed-check situation, naming the directory, the count and the failed git call"
has "$(cat "$D/gc.log")" "Not a valid object name origin/main. It verified nothing either way" \
  "nocheck, patrol 3: the visit carries git's own error, its trailing newline not left as a space before the rest"
hasnt "$(cat "$D/gc.log")" "refinery-false-completion" "nocheck, patrol 3: the visit is not a no-change situation"
has "$(cat "$D/gc.log")" "runtime drain-ack" "nocheck, patrol 3: the session drains"
eq "$(merged_tries)" 0 "nocheck: nothing is recorded as merged"
eq "$(git -C "$D/origin.git" rev-parse main)" "$BASE" "nocheck: nothing is pushed"

echo "── a check that runs again clears the count, and the landing goes on ──"
fixture "$TMP/recheck" work
: > "$D/gc.log"; : > "$D/lc.log"
NOCHECK_ENV=(env GC_RIG_ROOT="$D/rig" GC_RIG=myrig GC_CITY_PATH="$CITY" WORK=wb BRANCH=polecat/wb TARGET=main
  TARGET_BRANCH_DEFAULT=main FAKE_ROSTER="$D/roster.json" FAKE_META="$D/bead.json" FAKE_LOG="$D/gc.log"
  FAKE_LC_LOG="$D/lc.log" DIRECT_MERGE_PUSH_BACKOFF=0 STRATEGY=direct)
( cd "$ELSEWHERE" && "${NOCHECK_ENV[@]}" bash "$TMP/prep.sh" ) >"$D/prep.out" 2>&1; PREP_RC=$?
eq "$PREP_RC" 0 "recheck: the prepare stages the branch"
git -C "$D/rig" update-ref -d refs/remotes/origin/main
nocheck_merge_push
eq "$(fails)" 1 "recheck: a failed check is counted"
git -C "$D/rig" update-ref refs/remotes/origin/main "$BASE"
nocheck_merge_push
eq "$RC" 0 "recheck: once the check runs, merge-push goes on"
eq "$(fails)" none "recheck: the check that ran cleared the count"
recorded_at "recheck" "$FEATURE"
not_parked "recheck"

echo "── a failed git call runs once, and its own error is the one reported ──"
# A git that fails the first call of FLAKY_SUB as a held index.lock does, and
# runs every later call for real, so a rerun of the failed call succeeds. The
# error reported must be the failed call's, and that call must run once.
fixture "$TMP/flaky" work
REAL_GIT=$(command -v git)
mkdir -p "$TMP/flaky-bin"
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; printf 'REAL_GIT=%q\n' "$REAL_GIT"; cat; } > "$TMP/flaky-bin/git" <<'GITW'
if [ "$1" = -C ]; then sub="$3"; else sub="$1"; fi
printf '%s\n' "$sub" >> "$FLAKY_LOG"
if [ "$sub" = "$FLAKY_SUB" ] && [ ! -e "$FLAKY_LOG.tripped" ]; then
  : > "$FLAKY_LOG.tripped"
  echo "fatal: Unable to create '/held/index.lock': File exists." >&2
  exit 128
fi
exec "$REAL_GIT" "$@"
GITW
chmod +x "$TMP/flaky-bin/git"
for sub in merge-base diff rev-list; do
  rm -f "$TMP/flaky.log" "$TMP/flaky.log.tripped"
  OUT=$(cd "$ELSEWHERE" && PATH="$TMP/flaky-bin:$PATH" FLAKY_SUB="$sub" FLAKY_LOG="$TMP/flaky.log" \
    bash -c "$(cat "$TMP/bhrc.sh")"'
branch_has_real_change "$1" origin/main "$2"
echo "rc=$? error=$BHRC_ERROR"' _ "$D/rig" "$FEATURE" 2>&1)
  has "$OUT" "rc=2 error=$sub " "flaky/$sub: a failed $sub is a check that could not run"
  has "$OUT" "failed: fatal: Unable to create '/held/index.lock': File exists." "flaky/$sub: the error reported is the one the failed call wrote"
  eq "$(grep -cx -- "$sub" "$TMP/flaky.log" || true)" 1 "flaky/$sub: the failed call ran once"
done

echo "── a warning git writes ahead of its answer does not cost the check ──"
# Each call's stderr is captured with its stdout, so the answer is read from the
# last line. A git that warns before every answer, as it does for an ambiguous
# refname, still yields a branch with a change.
mkdir -p "$TMP/warn-bin"
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; printf 'REAL_GIT=%q\n' "$REAL_GIT"; cat; } > "$TMP/warn-bin/git" <<'GITW'
echo "warning: refname 'origin/main' is ambiguous." >&2
exec "$REAL_GIT" "$@"
GITW
chmod +x "$TMP/warn-bin/git"
OUT=$(cd "$ELSEWHERE" && PATH="$TMP/warn-bin:$PATH" bash -c "$(cat "$TMP/bhrc.sh")"'
branch_has_real_change "$1" origin/main "$2"
echo "rc=$? error=$BHRC_ERROR"' _ "$D/rig" "$FEATURE" 2>&1)
eq "$OUT" "rc=0 error=" "warning: a branch with a change still reads as one"

echo "-----"
echo "unrecorded-direct-landing: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
