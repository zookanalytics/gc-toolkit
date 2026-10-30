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
# that log. They run from inside the rig's checkout, because
# branch_has_real_change's git calls take their repository from the cwd.
# Proves:
#   - an attempt that pushes and then cannot record leaves the landing on
#     origin, the stamp on the bead and the branch on origin, and the next
#     attempt stages the branch again and records the landing at the stamped
#     commit without parking, escalating or draining, whether origin/main
#     stayed at the landing or moved on past it, and whatever strategy the
#     bead reads by then; the branch is deleted once the landing is recorded;
#   - a branch that never introduced work is still refused, parked and
#     escalated, with no stamp and with a stamp its target does not carry.
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

# A block comes out with {{binding_prefix}} rendered as the patrol fills it in:
# the binding it was poured with, gc-toolkit. here.
fence() { awk -v m="$1" '$0 ~ ("# >>> " m "$") {f=1; next} $0 ~ ("# <<< " m "$") {f=0} f' "$TOML" | sed 's|{{binding_prefix}}|gc-toolkit.|g'; }

echo "── the blocks ──"
for m in shared-branch-merge-mode branch-has-real-change zero-diff-guard direct-merge-push; do
  if [ -n "$(fence "$m")" ]; then ok "$m: extracted between its markers"; else bad "$m: extracted between its markers"; fi
done
fence shared-branch-merge-mode > "$TMP/prep.sh"
# delete_merged_branches takes the patrol's default, true.
{
  echo 'BEAD_JSON=$(gc bd show $WORK --json)'
  echo 'MERGE_STRATEGY="$STRATEGY"'
  echo 'LC="$(gc gc-toolkit scripts-dir)/lifecycle.sh"'
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

# The pack the blocks find their scripts in, which gc names.
CITY="$TMP/city"
PACK="$CITY/rigs/gc-toolkit/assets/scripts"
mkdir -p "$PACK" "$TMP/bin"
cp "$HERE/direct-merge-push.sh" "$HERE/bd-lib.sh" "$HERE/refinery-workspace.sh" "$HERE/detached-job.sh" "$PACK/"
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
# gc names the pack for `gc gc-toolkit scripts-dir`, answers the roster for
# `rig list` and the bead file for `bd show`, applies
# each --set-metadata and --unset-metadata of a `bd update` to that file, and
# logs every other call.
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
case "$1 $2" in
  "gc-toolkit scripts-dir") [ -n "${STUB_PACK:-}" ] || exit 1; printf '%s/assets/scripts\n' "$STUB_PACK" ;;
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

# fixture <dir> work|nowork: origin with main at BASE and polecat/wb one commit
# ahead of it (work) or at BASE itself (nowork), the rig cloned from it, and a
# direct-strategy bead. Sets D, BASE, FEATURE and PREP.
fixture() {
  D="$1"
  mkdir -p "$D"
  git init -q --bare -b main "$D/origin.git"
  git init -q -b main "$D/seed"
  BASE=$(commit "$D/seed" "base")
  git -C "$D/seed" push -q "$D/origin.git" main
  git -C "$D/seed" checkout -q -b polecat/wb
  if [ "$2" = work ]; then FEATURE=$(commit "$D/seed" "feature"); else FEATURE="$BASE"; fi
  git -C "$D/seed" push -q "$D/origin.git" polecat/wb
  git -C "$D/seed" checkout -q main
  git clone -q "$D/origin.git" "$D/rig"
  PREP="$(git -C "$D/rig" rev-parse --path-format=absolute --git-common-dir)/gc-refinery-prep"
  printf '{"rigs":[{"name":"myrig","path":"%s"}]}\n' "$D/rig" > "$D/roster.json"
  printf '%s\n' '[{"id":"wb","status":"in_progress","metadata":{"branch":"polecat/wb","target":"main","merge_strategy":"direct"}}]' > "$D/bead.json"
}

# attempt [<env>...]: one patrol's prepare, then its merge-push, both from
# inside the rig, the bead read as a direct one unless STRATEGY says otherwise.
# The logs start over, so each attempt's assertions read only its own calls.
# Sets PREP_RC, RC and OUT.
attempt() {
  : > "$D/gc.log"; : > "$D/lc.log"
  local run=(env GC_RIG_ROOT="$D/rig" GC_RIG=myrig STUB_PACK="$CITY/rigs/gc-toolkit" WORK=wb BRANCH=polecat/wb TARGET=main
    TARGET_BRANCH_DEFAULT=main FAKE_ROSTER="$D/roster.json" FAKE_META="$D/bead.json" FAKE_LOG="$D/gc.log"
    FAKE_LC_LOG="$D/lc.log" DIRECT_MERGE_PUSH_BACKOFF=0 STRATEGY=direct "$@")
  ( cd "$D/rig" && "${run[@]}" bash "$TMP/prep.sh" ) >"$D/prep.out" 2>&1; PREP_RC=$?
  OUT=$(cd "$D/rig" && "${run[@]}" bash "$TMP/merge-push.sh" 2>&1); RC=$?
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

echo "-----"
echo "unrecorded-direct-landing: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
