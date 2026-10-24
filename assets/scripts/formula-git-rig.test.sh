#!/usr/bin/env bash
# Hermetic test: a formula step whose git calls choose a repository names it by
# path, so the session's cwd never chooses it.
#
# The marked blocks of mol-review (the commit pin and the diff),
# mol-review-quorum-signoff (a lane's repository), mol-refinery-patrol (the
# conflict reason), mol-upstream-gc-rebase and mol-upstream-gc-pr-prep (the
# gascity worktree setup) and mol-feedback-miner (the repository mined) are
# extracted verbatim and run from a WRONG cwd against real git repos. Each must
# act on the rig GC_RIG_ROOT names, or the roster entry for GC_RIG (for the
# keeper formulas, the roster entry named gascity), and refuse when none
# resolves. A keeper formula's refusal drains only once its hand-back to the
# keeper is written. The wrong cwd is a clone of the same origin wherever that
# makes a cwd-steered call succeed, so "read the rig, not cwd" discriminates.
# Controls prove that a bare git call and an empty `git -C ""` both follow cwd.
# The refinery's zero-diff check, its rejection's branch delete and its
# recorded-PR lookup are proven the same way in the suites that run those blocks
# (unrecorded-direct-landing, mr-aware-rejection-failclosed and
# find-work-gating-guard). No live city, store, or network.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
REVIEW_TOML="$ROOT/formulas/mol-review.toml"
QUORUM_TOML="$ROOT/formulas/mol-review-quorum-signoff.toml"
PATROL_TOML="$ROOT/formulas/mol-refinery-patrol.toml"
MINER_TOML="$ROOT/formulas/mol-feedback-miner.toml"
REBASE_TOML="$ROOT/packs/gascity-keeper/formulas/mol-upstream-gc-rebase.toml"
PRPREP_TOML="$ROOT/packs/gascity-keeper/formulas/mol-upstream-gc-pr-prep.toml"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-formula-git-rig-test.XXXXXX")"
# git lists a worktree by its resolved path, so every path is built on a
# resolved root, a TMPDIR behind a symlink (as macOS's is) included.
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1${2:+ ($2)}"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3" "got '$1' want '$2'"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3" "missing '$2' in: $1" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3" "found '$2' in: $1" ;; *) ok "$3" ;; esac; }

command -v jq  >/dev/null 2>&1 || { echo "jq is required"  >&2; exit 1; }
command -v git >/dev/null 2>&1 || { echo "git is required" >&2; exit 1; }
for f in "$REVIEW_TOML" "$QUORUM_TOML" "$PATROL_TOML" "$MINER_TOML" "$REBASE_TOML" "$PRPREP_TOML"; do
  [ -s "$f" ] || { echo "formula not found: $f" >&2; exit 1; }
done

# The blocks fall back to `gc rig list --json` when GC_RIG_ROOT is empty, so no
# ambient city value may reach them: each run sets its own, and a stub gc heads
# PATH so the live one is never asked. Git reads no user or system config, so
# cwd versus -C is the only thing steering it.
unset GC_RIG_ROOT GC_RIG GC_CITY GC_CITY_PATH GC_PACK_DIR 2>/dev/null || true
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR 2>/dev/null || true
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

# gc answers `rig list` from the roster file and `bd show` from the bead file,
# and logs every other call, one line each. A `bd update` then exits
# FAKE_UPDATE_RC, so a case can have the store refuse the write.
BIN="$TMP/bin"; mkdir -p "$BIN"
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$BIN/gc" <<'GC'
case "$1 $2" in
  "rig list") cat "$FAKE_ROSTER" ;;
  "bd show")  cat "$FAKE_META" ;;
  *)          printf '%s\n' "$*" | tr '\n' ' ' >> "$FAKE_LOG"; echo >> "$FAKE_LOG"
              [ "$1 $2" != "bd update" ] || exit "${FAKE_UPDATE_RC:-0}" ;;
esac
exit 0
GC
chmod +x "$BIN/gc"
export PATH="$BIN:$PATH"

# copy <toml> <marker> <n>: the n-th copy of a marked block.
copy() {
  awk -v m="$2" -v want="$3" '
    $0 ~ ("# >>> " m "$") { n++; f = (n == want); next }
    $0 ~ ("# <<< " m "$") { f = 0 }
    f' "$1"
}
copies() { grep -c -- "# >>> $2\$" "$1" || true; }

# block <toml> <marker> <out> [<n>]: the n-th copy (default 1) of the marked
# block, with formula placeholders rendered as the materializer renders them.
block() {
  local body
  body="$(copy "$1" "$2" "${4:-1}")"
  if [ -z "$body" ]; then
    bad "$2: block extracted between markers" "markers missing from ${1#"$ROOT"/}"
    : > "$3"
    return 0
  fi
  ok "$2: block extracted between markers"
  printf '%s\n' "$body" | sed -e 's|{{issue}}|tk-iss|g' -e 's|{{origin_remote}}|origin|g' \
    -e 's|{{upstream_remote}}|upstream|g' -e 's|{{upstream_branch}}|main|g' \
    -e 's|{{notify_recipient}}|mayor/|g' -e 's|{{requesting_keeper}}|keeper/from-var|g' > "$3"
  case "$(cat "$3")" in
    *'{{'*) bad "$2: no unrendered formula placeholder left" ;;
    *)      ok "$2: no unrendered formula placeholder left" ;;
  esac
  if bash -n "$3" 2>/dev/null; then ok "$2: block is valid bash"; else bad "$2: block is valid bash"; fi
}

# bare_git <file>: the first argument of every git invocation that does not
# start with -C, outside comment lines. Empty means each call names its repo.
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

count() { awk 'NF { n++ } END { print n + 0 }'; }
wt_paths() { git -C "$1" worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p'; }
registered() { if [ -n "$2" ] && grep -qxF -- "$2" <<< "$(wt_paths "$1")"; then echo yes; else echo no; fi; }
# commit <repo> <message>: a commit that adds a file named for the message.
commit() {
  printf '%s\n' "$2" > "$1/${2// /-}.txt"
  git -C "$1" add -A
  git -C "$1" commit -q -m "$2"
  git -C "$1" rev-parse HEAD
}
ref() { git -C "$1" rev-parse -q --verify "$2" 2>/dev/null || echo none; }

# pick <mode> <rig>: write the roster and set RR/GR, the GC_RIG_ROOT/GC_RIG one
# run resolves its rig from.
#   env      GC_RIG_ROOT names the rig.
#   roster   GC_RIG_ROOT is empty; the roster maps GC_RIG to the rig.
#   nomatch  GC_RIG_ROOT is empty and GC_RIG names no rig: the block must refuse.
pick() {
  printf '{"rigs":[{"name":"myrig","path":"%s"}]}\n' "$2" > "$FAKE_ROSTER"
  case "$1" in
    env)     RR="$2"; GR=ignored ;;
    roster)  RR="";   GR=myrig ;;
    nomatch) RR="";   GR=no-such-rig ;;
  esac
}

# --- 1. Controls: a bare git call and an empty -C both follow cwd. -------------
# What each site ran before it named the rig. Without them, "read the rig, not
# cwd" below would pass even if -C did nothing.
echo "── controls ──"
C="$TMP/control"
mkdir -p "$C"
git init -q --bare -b main "$C/origin.git"
git init -q -b main "$C/seed"
commit "$C/seed" "control base" >/dev/null
git -C "$C/seed" push -q "$C/origin.git" main
git clone -q "$C/origin.git" "$C/rig"
git clone -q "$C/origin.git" "$C/cwd"
MOVED=$(commit "$C/seed" "control moved on")
git -C "$C/seed" push -q "$C/origin.git" main
( cd "$C/cwd" && GC_RIG_ROOT="$C/rig" git fetch -q origin main ) >/dev/null 2>&1 || true
eq "$(ref "$C/cwd" origin/main)" "$MOVED" "control: a bare fetch updated the cwd repo's refs"
[ "$(ref "$C/rig" origin/main)" != "$MOVED" ] && ok "control: a bare fetch never reached the rig, whatever GC_RIG_ROOT says" \
  || bad "control: a bare fetch never reached the rig, whatever GC_RIG_ROOT says"
eq "$(cd "$C/cwd" && git -C "" rev-parse --show-toplevel 2>/dev/null || true)" "$C/cwd" \
  "control: git -C \"\" runs in the cwd repo, so an empty root must refuse rather than run"

# --- 2. mol-review: the commit pin. ---------------------------------------------
echo "── mol-review: review-pin-commit ──"
block "$REVIEW_TOML" review-pin-commit "$TMP/pin.sh"
eq "$(bare_git "$TMP/pin.sh")" "" "pin: every git call in the block names its repo with -C"

pin_case() { # <mode> <meta-json> [<label>]; sets RC, D, OLD, NEW
  local d="$TMP/pin-${3:-$1}" rc=0
  mkdir -p "$d"
  git init -q --bare -b main "$d/origin.git"
  git init -q -b main "$d/seed"
  commit "$d/seed" "base ($1)" >/dev/null
  git -C "$d/seed" push -q "$d/origin.git" main
  git -C "$d/seed" checkout -q -b feature
  OLD=$(commit "$d/seed" "feature ($1)")
  git -C "$d/seed" push -q "$d/origin.git" feature
  git clone -q "$d/origin.git" "$d/rig"
  # The cwd repo is a clone of the same origin, so a fetch and a head read that
  # follow cwd succeed there instead of failing for want of the refs.
  git clone -q "$d/origin.git" "$d/cwd"
  # The branch moves on after both last fetched, so only the block's own fetch
  # can bring its new head into a repository.
  NEW=$(commit "$d/seed" "feature follow-up ($1)")
  git -C "$d/seed" push -q "$d/origin.git" feature
  # PIN_UNREACHABLE points the rig's origin at nothing, so its fetch fails.
  [ -z "${PIN_UNREACHABLE:-}" ] || git -C "$d/rig" remote set-url origin "$d/gone.git"
  FAKE_ROSTER="$d/roster.json"; pick "$1" "$d/rig"
  ( cd "$d/cwd" && GC_RIG_ROOT="$RR" GC_RIG="$GR" FAKE_ROSTER="$d/roster.json" FAKE_LOG="$d/gc.log" \
      M="$2" BASE=main BRANCH=feature bash "$TMP/pin.sh" ) >"$d/out" 2>&1 || rc=$?
  RC=$rc; D=$d
}

for mode in env roster; do
  pin_case "$mode" '{}'
  eq "$RC" 0 "pin/$mode: the block runs from a foreign cwd"
  eq "$(ref "$D/rig" origin/feature)" "$NEW" "pin/$mode: the fetch brought the branch's new head into the RIG"
  eq "$(ref "$D/cwd" origin/feature)" "$OLD" "pin/$mode: the cwd repo was not fetched"
  has "$(cat "$D/out")" "reviewing feature -> main at $NEW" "pin/$mode: with no reviewed_oid, the head is read from the rig's refreshed refs"
done
STAMP="$OLD"
pin_case env "{\"reviewed_oid\":\"$STAMP\"}" stamped
eq "$RC" 0 "pin/stamped: the block runs from a foreign cwd"
has "$(cat "$D/out")" "reviewing feature -> main at $STAMP" "pin/stamped: the dispatch-stamped reviewed_oid still wins over the fetched head"
PIN_UNREACHABLE=1 pin_case env '{}' unreachable
[ "$RC" -ne 0 ] && ok "pin/unreachable: a fetch that fails stops the review" || bad "pin/unreachable: a fetch that fails stops the review"
has "$(cat "$D/out")" "review: fetching main and feature into $D/rig failed" "pin/unreachable: the block says the fetch failed"
hasnt "$(cat "$D/out")" "reviewing " "pin/unreachable: no commit is pinned from the rig's stale refs"
pin_case nomatch '{}'
[ "$RC" -ne 0 ] && ok "pin/nomatch: an unresolvable rig fails closed" || bad "pin/nomatch: an unresolvable rig fails closed"
eq "$(ref "$D/rig" origin/feature)" "$OLD" "pin/nomatch: refused before fetching into the rig"
eq "$(ref "$D/cwd" origin/feature)" "$OLD" "pin/nomatch: refused before fetching into the cwd repo"
hasnt "$(cat "$D/out")" "reviewing " "pin/nomatch: no commit is pinned"

# --- 3. mol-review: the diff under review. -------------------------------------
echo "── mol-review: review-diff ──"
block "$REVIEW_TOML" review-diff "$TMP/diff.sh"
eq "$(bare_git "$TMP/diff.sh")" "" "diff: every git call in the block names its repo with -C"

diff_case() { # <mode>; sets RC, D, OID
  local d="$TMP/diff-$1" rc=0
  mkdir -p "$d"
  git init -q --bare -b main "$d/origin.git"
  git init -q -b main "$d/seed"
  commit "$d/seed" "base ($1)" >/dev/null
  git -C "$d/seed" push -q "$d/origin.git" main
  # The cwd repo cloned before the base moved, so its origin/main is stale.
  git clone -q "$d/origin.git" "$d/cwd"
  commit "$d/seed" "base moved on" >/dev/null
  git -C "$d/seed" push -q "$d/origin.git" main
  git -C "$d/seed" checkout -q -b feature
  OID=$(commit "$d/seed" "branch work")
  git -C "$d/seed" push -q "$d/origin.git" feature
  git clone -q "$d/origin.git" "$d/rig"
  # It holds the reviewed commit, so a diff that follows cwd succeeds there,
  # against the stale base.
  git -C "$d/cwd" fetch -q origin feature
  FAKE_ROSTER="$d/roster.json"; pick "$1" "$d/rig"
  ( cd "$d/cwd" && GC_RIG_ROOT="$RR" GC_RIG="$GR" FAKE_ROSTER="$d/roster.json" FAKE_LOG="$d/gc.log" \
      BASE=main REVIEWED_OID="$OID" bash "$TMP/diff.sh" ) >"$d/out" 2>&1 || rc=$?
  RC=$rc; D=$d
}

diff_case env
CONTROL=$(cd "$D/cwd" && git diff --stat "origin/main...$OID" 2>&1 || true)
has "$CONTROL" "base-moved-on.txt" "control: a bare diff from the stale clone shows the base's change as the branch's"
for mode in env roster; do
  [ "$mode" = env ] || diff_case "$mode"
  eq "$RC" 0 "diff/$mode: the block runs from a foreign cwd"
  has "$(cat "$D/out")" "branch-work.txt" "diff/$mode: the diff shows the branch's change"
  hasnt "$(cat "$D/out")" "base-moved-on.txt" "diff/$mode: the diff is taken against the rig's current base, not the cwd's stale one"
done
diff_case nomatch
[ "$RC" -ne 0 ] && ok "diff/nomatch: an unresolvable rig fails closed" || bad "diff/nomatch: an unresolvable rig fails closed"
hasnt "$(cat "$D/out")" ".txt" "diff/nomatch: no diff is shown"

# --- 4. mol-review-quorum-signoff: a lane's repository. ------------------------
echo "── mol-review-quorum-signoff: quorum-lane-repo ──"
eq "$(copies "$QUORUM_TOML" quorum-lane-repo)" 2 "lane: both lanes carry the quorum-lane-repo block"
block "$QUORUM_TOML" quorum-lane-repo "$TMP/lane-1.sh" 1
block "$QUORUM_TOML" quorum-lane-repo "$TMP/lane-2.sh" 2
cmp -s "$TMP/lane-1.sh" "$TMP/lane-2.sh" && ok "lane: the two lanes carry the same block" \
  || bad "lane: the two lanes carry the same block"
# Step 2's diff runs in a later shell than the block, so it names the path the
# block prints, never the REPO the block's shell took with it.
eq "$(grep -c 'git -C <repo> diff origin/<base>\.\.\.<reviewed_oid>` with `<repo>` the rig' "$QUORUM_TOML" || true)" 2 \
  "lane: each lane reads its diff in the repository the block prints"
eq "$(grep -c 'git -C "\$REPO" diff' "$QUORUM_TOML" || true)" 0 \
  "lane: no lane's diff names REPO, which step 2's shell does not have"
eq "$(grep -c '`git diff origin/' "$QUORUM_TOML" || true)" 0 "lane: no lane reads a diff from its cwd"
# The read-only check looks where the lane reads: a baseline taken in the cwd
# misses a change to the rig's checkout, and errors where the cwd is no checkout.
eq "$(grep -c 'mutation baseline with `git -C <repo> status --porcelain=v1 -z`' "$QUORUM_TOML" || true)" 2 \
  "lane: each lane takes its mutation baseline in the repository its diff reads"
eq "$(grep -c '`git status --porcelain' "$QUORUM_TOML" || true)" 0 "lane: no lane takes its mutation baseline in its cwd"
L="$TMP/lane"
mkdir -p "$L"
git init -q -b main "$L/rig"; commit "$L/rig" "lane rig" >/dev/null
git init -q -b main "$L/cwd"; commit "$L/cwd" "lane cwd" >/dev/null
for mode in env roster nomatch; do
  FAKE_ROSTER="$L/roster-$mode.json"; pick "$mode" "$L/rig"
  rc=0
  OUT=$(cd "$L/cwd" && GC_RIG_ROOT="$RR" GC_RIG="$GR" FAKE_ROSTER="$L/roster-$mode.json" FAKE_LOG="$L/gc.log" \
          bash "$TMP/lane-1.sh" 2>&1) || rc=$?
  case "$mode" in
    nomatch)
      [ "$rc" -ne 0 ] && ok "lane/nomatch: an unresolvable rig fails closed" || bad "lane/nomatch: an unresolvable rig fails closed"
      hasnt "$OUT" "rig repository:" "lane/nomatch: no repository is printed" ;;
    *)
      eq "$rc" 0 "lane/$mode: the block runs from a foreign cwd"
      eq "$OUT" "rig repository: $L/rig" "lane/$mode: the block prints the rig as the lane's repository, not the cwd repo" ;;
  esac
done

# --- 5. mol-refinery-patrol: the conflict reason. -------------------------------
echo "── mol-refinery-patrol: rejection-conflict-reason ──"
block "$PATROL_TOML" rejection-conflict-reason "$TMP/reason.sh"
eq "$(bare_git "$TMP/reason.sh")" "" "reason: every git call in the block names its repo with -C"
printf 'printf "REASON=%%s\\n" "$REJECT_REASON"\n' >> "$TMP/reason.sh"

reason_case() { # <mode>; sets RC, D, RIG_HEAD, CWD_HEAD
  local d="$TMP/reason-$1" rc=0
  mkdir -p "$d"
  git init -q --bare -b main "$d/origin.git"
  git init -q -b main "$d/seed"
  commit "$d/seed" "rig base ($1)" >/dev/null
  git -C "$d/seed" push -q "$d/origin.git" main
  git clone -q "$d/origin.git" "$d/rig"
  RIG_HEAD=$(ref "$d/rig" origin/main)
  # The cwd repo has an origin/main of its own, so a head read that follows
  # cwd succeeds there and names another repository's commit.
  git init -q --bare -b main "$d/foreign.git"
  git init -q -b main "$d/cwd"; commit "$d/cwd" "foreign ($1)" >/dev/null
  git -C "$d/cwd" remote add origin "$d/foreign.git"
  git -C "$d/cwd" push -q origin main
  git -C "$d/cwd" fetch -q origin
  CWD_HEAD=$(ref "$d/cwd" origin/main)
  FAKE_ROSTER="$d/roster.json"; pick "$1" "$d/rig"
  ( cd "$d/cwd" && GC_RIG_ROOT="$RR" GC_RIG="$GR" FAKE_ROSTER="$d/roster.json" FAKE_LOG="$d/gc.log" \
      TARGET=main PREPARE_MODE=merge bash "$TMP/reason.sh" ) >"$d/out" 2>&1 || rc=$?
  RC=$rc; D=$d
}

for mode in env roster; do
  reason_case "$mode"
  eq "$RC" 0 "reason/$mode: the block runs from a foreign cwd"
  has "$(cat "$D/out")" "REASON=Conflicts with main at $RIG_HEAD; resume in prepare_mode=merge" "reason/$mode: the reason names the rig's origin/main"
  hasnt "$(cat "$D/out")" "$CWD_HEAD" "reason/$mode: the reason does not name the cwd repo's origin/main"
done
reason_case nomatch
eq "$RC" 1 "reason/nomatch: an unresolvable rig fails closed"
grep -qxF 'runtime drain-ack ' "$D/gc.log" 2>/dev/null \
  && ok "reason/nomatch: the refinery drains, leaving the work to retry before the workflow is retired" \
  || bad "reason/nomatch: the refinery drains, leaving the work to retry before the workflow is retired"
hasnt "$(cat "$D/out")" "REASON=" "reason/nomatch: no reason is composed"

# --- 6. mol-upstream-gc-rebase: the gascity worktree. ---------------------------
# The keeper formulas name the gascity rig by its roster entry, so the pool the
# run was slung to never picks the repository: GC_RIG_ROOT here names the cwd
# repo, the wrong one, in every case.
echo "── mol-upstream-gc-rebase: upstream-rebase-worktree-setup ──"
block "$REBASE_TOML" upstream-rebase-worktree-setup "$TMP/rebase.sh"
eq "$(bare_git "$TMP/rebase.sh")" "" "rebase: every git call in the block names its repo with -C"

# keeper_repos <dir>: a gascity rig cloned from its origin, and a cwd repo with
# an origin, an upstream and a main of its own, each of whose origin moved on
# after it was cloned, so a fetch shows which repository it ran in. Sets
# CWD_STALE.
keeper_repos() {
  local d="$1"
  git init -q --bare -b main "$d/origin.git"
  git init -q --bare -b main "$d/upstream.git"
  git init -q -b main "$d/seed"
  commit "$d/seed" "gascity base" >/dev/null
  git -C "$d/seed" push -q "$d/origin.git" main
  git -C "$d/seed" checkout -q -b up
  commit "$d/seed" "upstream base" >/dev/null
  git -C "$d/seed" push -q "$d/upstream.git" up:main
  git clone -q "$d/origin.git" "$d/rig"
  git -C "$d/rig" remote add upstream "$d/upstream.git"
  git init -q --bare -b main "$d/foreign.git"
  git init -q -b main "$d/fseed"; commit "$d/fseed" "foreign base" >/dev/null
  git -C "$d/fseed" push -q "$d/foreign.git" main
  git clone -q "$d/foreign.git" "$d/cwd"
  git -C "$d/cwd" remote add upstream "$d/foreign.git"
  git -C "$d/cwd" fetch -q upstream
  CWD_STALE=$(ref "$d/cwd" origin/main)
  commit "$d/fseed" "foreign moved on" >/dev/null
  git -C "$d/fseed" push -q "$d/foreign.git" main
}
# keeper_roster <dir> gascity|other
keeper_roster() { printf '{"rigs":[{"name":"%s","path":"%s"}]}\n' "$2" "$1/rig" > "$1/roster.json"; }

rebase_case() { # <gascity|other> <meta-json> <label> [<bd-update-rc>]; sets RC, D, WT
  local d="$TMP/rebase-$3" rc=0
  mkdir -p "$d/city"
  keeper_repos "$d"
  keeper_roster "$d" "$1"
  printf '%s\n' "$2" > "$d/meta.json"
  WT="$d/city/.gc/worktrees/gascity/rebase-tk-iss"
  ( cd "$d/cwd" && GC_RIG_ROOT="$d/cwd" GC_RIG=gascity GC_CITY_PATH="$d/city" FAKE_ROSTER="$d/roster.json" \
      FAKE_META="$d/meta.json" FAKE_LOG="$d/gc.log" FAKE_UPDATE_RC="${4:-0}" bash "$TMP/rebase.sh" ) >"$d/out" 2>&1 || rc=$?
  RC=$rc; D=$d
}

KEEPER_META='[{"metadata":{"requesting_keeper":"gascity/gascity-keeper.keeper"}}]'
rebase_case gascity "$KEEPER_META" gascity
eq "$RC" 0 "rebase/gascity: the block runs from a foreign cwd"
eq "$(registered "$D/rig" "$WT")" yes "rebase/gascity: the worktree is registered in the gascity rig"
eq "$(registered "$D/cwd" "$WT")" no "rebase/gascity: the worktree is NOT registered in the cwd repo, which GC_RIG_ROOT names"
eq "$(git -C "$WT" rev-parse --abbrev-ref HEAD 2>/dev/null || true)" "rebase/tk-iss" "rebase/gascity: the worktree is on rebase/tk-iss"
eq "$(git -C "$WT" rev-parse HEAD 2>/dev/null || true)" "$(ref "$D/rig" origin/main)" "rebase/gascity: cut from the gascity rig's origin/main"
eq "$(ref "$D/cwd" refs/heads/rebase/tk-iss)" none "rebase/gascity: no rebase branch is created in the cwd repo"
eq "$(ref "$D/cwd" origin/main)" "$CWD_STALE" "rebase/gascity: the cwd repo was not fetched"
has "$(cat "$D/gc.log")" "bd update tk-iss --set-metadata work_dir=$WT --set-metadata branch=rebase/tk-iss" "rebase/gascity: the worktree is recorded on the bead"
hasnt "$(cat "$D/gc.log")" "runtime drain-ack" "rebase/gascity: the session does not drain"

rebase_case other "$KEEPER_META" unregistered
eq "$RC" 1 "rebase/unregistered: a roster with no gascity rig fails closed"
[ ! -e "$WT" ] && ok "rebase/unregistered: nothing created at the worktree path" || bad "rebase/unregistered: nothing created at the worktree path"
eq "$(wt_paths "$D/cwd" | count)" 1 "rebase/unregistered: nothing registered in the cwd repo"
eq "$(ref "$D/cwd" refs/heads/rebase/tk-iss)" none "rebase/unregistered: no rebase branch is created in the cwd repo"
eq "$(ref "$D/cwd" origin/main)" "$CWD_STALE" "rebase/unregistered: refused before fetching into the cwd repo"
has "$(cat "$D/gc.log")" "bd update tk-iss --set-metadata aborted_at=workspace-setup --status=open --assignee=gascity/gascity-keeper.keeper --append-notes Refused to set up the rebase worktree" \
  "rebase/unregistered: the bead goes back to the requesting keeper with aborted_at and a note, the formula's abort shape"
has "$(cat "$D/gc.log")" "session nudge gascity/gascity-keeper.keeper rebase tk-iss: aborted at workspace-setup" "rebase/unregistered: the keeper is nudged"
has "$(cat "$D/gc.log")" "runtime drain-ack" "rebase/unregistered: the session drains"
rebase_case other '[{"metadata":{}}]' unstamped
has "$(cat "$D/gc.log")" "--assignee=mayor/" "rebase/unregistered: with no requesting_keeper stamped, the bead goes to notify_recipient"
rebase_case other "$KEEPER_META" refused 1
eq "$RC" 1 "rebase/refused: a hand-back the store refuses fails closed"
eq "$(grep -c '^bd update ' "$D/gc.log" || true)" 1 "rebase/refused: the refused hand-back is the only write attempted"
has "$(cat "$D/out")" "the hand-back of tk-iss to gascity/gascity-keeper.keeper did not land; NOT draining" "rebase/refused: the block says the hand-back did not land"
hasnt "$(cat "$D/gc.log")" "session nudge" "rebase/refused: the keeper is not nudged about a hand-back the bead does not carry"
hasnt "$(cat "$D/gc.log")" "runtime drain-ack" "rebase/refused: the session does not drain, so the step is retried"

# --- 7. mol-upstream-gc-pr-prep: the gascity worktree. --------------------------
echo "── mol-upstream-gc-pr-prep: upstream-pr-prep-worktree-setup ──"
block "$PRPREP_TOML" upstream-pr-prep-worktree-setup "$TMP/prprep.sh"
eq "$(bare_git "$TMP/prprep.sh")" "" "pr-prep: every git call in the block names its repo with -C"

prprep_case() { # <gascity|other> <label> [<bd-update-rc>]; sets RC, D, WT, SHA
  local d="$TMP/prprep-$2" rc=0
  mkdir -p "$d/tmp" "$d/city"
  keeper_repos "$d"
  keeper_roster "$d" "$1"
  printf '%s\n' "${PRPREP_META:-$KEEPER_META}" > "$d/meta.json"
  SHA=$(ref "$d/rig" origin/main)
  # The worktree is anchored to the city, whatever the cwd is.
  WT="$d/city/.gc/worktrees/gascity/pr-prep-tk-iss"
  ( cd "$d/cwd" && TMPDIR="$d/tmp" GC_RIG_ROOT="$d/cwd" GC_RIG=gascity GC_CITY_PATH="${PRPREP_CITY-$d/city}" FAKE_ROSTER="$d/roster.json" \
      FAKE_META="$d/meta.json" FAKE_LOG="$d/gc.log" FAKE_UPDATE_RC="${3:-0}" COMMIT_SHA="$SHA" BRANCH_NAME="" bash "$TMP/prprep.sh" ) >"$d/out" 2>&1 || rc=$?
  RC=$rc; D=$d
}

prprep_case gascity gascity
SHORT=$(git -C "$D/rig" rev-parse --short "$SHA")
eq "$RC" 0 "pr-prep/gascity: the block runs from a foreign cwd"
eq "$(registered "$D/rig" "$WT")" yes "pr-prep/gascity: the worktree is registered in the gascity rig"
eq "$(registered "$D/cwd" "$WT")" no "pr-prep/gascity: the worktree is NOT registered in the cwd repo, which GC_RIG_ROOT names"
[ ! -e "$D/cwd/worktrees" ] && ok "pr-prep/gascity: nothing is created inside the cwd checkout" \
  || bad "pr-prep/gascity: nothing is created inside the cwd checkout"
eq "$(git -C "$D/cwd" status --porcelain 2>/dev/null)" "" "pr-prep/gascity: the cwd checkout is left clean"
eq "$(git -C "$WT" rev-parse --abbrev-ref HEAD 2>/dev/null || true)" "upstream-pr/$SHORT" "pr-prep/gascity: the branch is named for the commit's short sha in the gascity rig"
eq "$(git -C "$WT" rev-parse HEAD 2>/dev/null || true)" "$(ref "$D/rig" upstream/main)" "pr-prep/gascity: cut from the gascity rig's freshly fetched upstream/main"
eq "$(ref "$D/cwd" "refs/heads/upstream-pr/$SHORT")" none "pr-prep/gascity: no branch is created in the cwd repo"
has "$(cat "$D/gc.log")" "bd update tk-iss --set-metadata work_dir=$WT --set-metadata branch=upstream-pr/$SHORT" "pr-prep/gascity: the worktree is recorded on the bead"
hasnt "$(cat "$D/gc.log")" "runtime drain-ack" "pr-prep/gascity: the session does not drain"

PRPREP_CITY="" prprep_case gascity nocity
[ "$RC" -ne 0 ] && ok "pr-prep/nocity: with no GC_CITY_PATH the block refuses" || bad "pr-prep/nocity: with no GC_CITY_PATH the block refuses"
eq "$(wt_paths "$D/rig" | count)" 1 "pr-prep/nocity: no worktree is added to the gascity rig"
[ ! -e "$D/cwd/worktrees" ] && ok "pr-prep/nocity: nothing is created inside the cwd checkout" \
  || bad "pr-prep/nocity: nothing is created inside the cwd checkout"
hasnt "$(cat "$D/gc.log" 2>/dev/null)" "work_dir=" "pr-prep/nocity: no work_dir is recorded"

prprep_case other unregistered
eq "$RC" 0 "pr-prep/unregistered: the hand-back exits 0, as the formula's other aborts do"
[ ! -e "$WT" ] && ok "pr-prep/unregistered: nothing created at the worktree path" || bad "pr-prep/unregistered: nothing created at the worktree path"
eq "$(wt_paths "$D/cwd" | count)" 1 "pr-prep/unregistered: nothing registered in the cwd repo"
eq "$(git -C "$D/cwd" for-each-ref --format='%(refname)' 'refs/heads/upstream-pr/' | count)" 0 "pr-prep/unregistered: no branch is created in the cwd repo"
has "$(cat "$D/gc.log")" "mail send gascity/gascity-keeper.keeper -s pr-prep: no gascity rig for tk-iss" "pr-prep/unregistered: the keeper is mailed"
has "$(cat "$D/gc.log")" "mail send human -s pr-prep: no gascity rig for tk-iss" "pr-prep/unregistered: the operator is mailed"
has "$(cat "$D/gc.log")" "bd update tk-iss --set-metadata aborted_at=workspace-setup --status=open --assignee=gascity/gascity-keeper.keeper --set-metadata gc.routed_to=gascity/gascity-keeper.keeper" \
  "pr-prep/unregistered: the bead goes back open, assigned and routed to the keeper"
eq "$(head -n 1 "$D/gc.log" | cut -d' ' -f1-3)" "bd update tk-iss" "pr-prep/unregistered: the hand-back is written before any mail"
has "$(cat "$D/gc.log")" "runtime drain-ack" "pr-prep/unregistered: the session drains"
PRPREP_META='[{"metadata":{}}]' prprep_case other unstamped
has "$(cat "$D/gc.log")" "bd update tk-iss --set-metadata aborted_at=workspace-setup --status=open --assignee=keeper/from-var --set-metadata gc.routed_to=keeper/from-var" \
  "pr-prep/unstamped: with no requesting_keeper on the bead, it goes back to the keeper the run was slung with"
has "$(cat "$D/gc.log")" "mail send keeper/from-var -s pr-prep: no gascity rig for tk-iss" "pr-prep/unstamped: that keeper is mailed"
hasnt "$(cat "$D/gc.log")" "null" "pr-prep/unstamped: no write or mail names an agent called null"
prprep_case other refused 1
eq "$RC" 1 "pr-prep/refused: a hand-back the store refuses fails the block"
eq "$(grep -c '^bd update ' "$D/gc.log" || true)" 1 "pr-prep/refused: the refused hand-back is the only write attempted"
has "$(cat "$D/out")" "the hand-back of tk-iss to gascity/gascity-keeper.keeper did not land; NOT draining" "pr-prep/refused: the block says the hand-back did not land"
hasnt "$(cat "$D/gc.log")" "mail send" "pr-prep/refused: nobody is mailed about a hand-back the bead does not carry"
hasnt "$(cat "$D/gc.log")" "runtime drain-ack" "pr-prep/refused: the session does not drain, so the step is retried"

# --- 8. mol-feedback-miner: the repository mined. ------------------------------
echo "── mol-feedback-miner: feedback-miner-repo ──"
eq "$(copies "$MINER_TOML" feedback-miner-repo)" 2 "miner: both steps carry the feedback-miner-repo block"
block "$MINER_TOML" feedback-miner-repo "$TMP/miner-1.sh" 1
block "$MINER_TOML" feedback-miner-repo "$TMP/miner-2.sh" 2
cmp -s "$TMP/miner-1.sh" "$TMP/miner-2.sh" && ok "miner: the two steps resolve the repository the same way" \
  || bad "miner: the two steps resolve the repository the same way"
eq "$(grep -c 'show-toplevel)"$' "$MINER_TOML" || true)" 0 "miner: no step takes the repository from the cwd's toplevel"
eq "$(awk '/# <<< feedback-miner-repo$/ { getline; print; exit }' "$MINER_TOML")" \
  "[ -n \"\$REPO\" ] || no_op \"cannot resolve the rig root (GC_RIG_ROOT unset, GC_RIG='\$GC_RIG' matched no rig in the roster)\"" \
  "miner: load-context ends the run as a clean no-op when no rig resolves"
MN="$TMP/miner"
mkdir -p "$MN"
git init -q -b main "$MN/rig"; commit "$MN/rig" "miner rig" >/dev/null
git init -q -b main "$MN/cwd"; commit "$MN/cwd" "miner cwd" >/dev/null
for mode in env roster nomatch; do
  FAKE_ROSTER="$MN/roster-$mode.json"; pick "$mode" "$MN/rig"
  OUT=$(cd "$MN/cwd" && GC_RIG_ROOT="$RR" GC_RIG="$GR" FAKE_ROSTER="$MN/roster-$mode.json" FAKE_LOG="$MN/gc.log" \
          bash -c "$(cat "$TMP/miner-1.sh"; printf 'printf "REPO=%%s\\n" "$REPO"\n')" 2>&1 || true)
  case "$mode" in
    nomatch) eq "$OUT" "REPO=" "miner/nomatch: no repository is resolved, so the cwd repo is never mined" ;;
    *)       eq "$OUT" "REPO=$MN/rig" "miner/$mode: the repository mined is the rig, not the cwd repo" ;;
  esac
done
# mine-and-file: the line after its lookup, run with a stub step-close.sh. A rig
# that no longer resolves ends the run as a no-op that names the cause, and the
# sweep never starts.
awk '/# <<< feedback-miner-repo$/ { if (++n == 2) { getline; print; exit } }' "$MINER_TOML" > "$TMP/miner-2-noop.sh"
printf '#!/usr/bin/env bash\necho "step-close $*" >> "$FAKE_LOG"\n' > "$MN/step-close.sh"
chmod +x "$MN/step-close.sh"
FAKE_ROSTER="$MN/roster-nomatch.json"; pick nomatch "$MN/rig"
: > "$MN/gc.log"
RC=0
OUT=$(cd "$MN/cwd" && GC_RIG_ROOT="$RR" GC_RIG="$GR" FAKE_ROSTER="$MN/roster-nomatch.json" FAKE_LOG="$MN/gc.log" \
        SC="$MN/step-close.sh" bash -c "$(cat "$TMP/miner-2.sh" "$TMP/miner-2-noop.sh"; echo 'echo "SWEEP STARTED"')" 2>&1) || RC=$?
eq "$RC" 0 "miner/mine-and-file: an unresolvable rig ends the run cleanly"
has "$OUT" "feedback-miner: cannot resolve the rig root (GC_RIG_ROOT unset, GC_RIG='no-such-rig' matched no rig in the roster) — nothing to mine this run." \
  "miner/mine-and-file: the run says the rig did not resolve"
hasnt "$OUT" "SWEEP STARTED" "miner/mine-and-file: the sweep never starts"
has "$(cat "$MN/gc.log")" "step-close --step mol-feedback-miner.mine-and-file --outcome pass" "miner/mine-and-file: the step closes with outcome pass"
has "$(cat "$MN/gc.log")" "runtime drain-ack" "miner/mine-and-file: the session drains"

echo "-----"
echo "formula-git-rig: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
