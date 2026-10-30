#!/usr/bin/env bash
# Hermetic test: a formula step whose git calls choose a repository names it by
# path, so the session's cwd never chooses it.
#
# The marked blocks of mol-review and mol-review-quorum-signoff (the review's
# gather), mol-refinery-patrol (the conflict reason), mol-upstream-gc-rebase
# and mol-upstream-gc-pr-prep (the gascity worktree setup) and
# mol-feedback-miner (the repository mined) are extracted verbatim and run from
# a WRONG cwd against real git repos. Each must act on the rig GC_RIG_ROOT
# names, or the roster entry for GC_RIG (for the keeper formulas, the roster
# entry named gascity), and refuse when none resolves. A keeper formula's
# refusal drains only once its hand-back to the keeper is written. The wrong
# cwd is a clone of the same origin wherever that makes a cwd-steered call
# succeed, so "read the rig, not cwd" discriminates. Controls prove that a bare
# git call and an empty `git -C ""` both follow cwd. The refinery's zero-diff
# check, its rejection's branch delete and its recorded-PR lookup are proven
# the same way in the suites that run those blocks (unrecorded-direct-landing,
# mr-aware-rejection-failclosed and find-work-gating-guard). No live city,
# store, or network.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
REVIEW_TOML="$ROOT/formulas/mol-review.toml"
QUORUM_TOML="$ROOT/formulas/mol-review-quorum-signoff.toml"
PATROL_TOML="$ROOT/formulas/mol-refinery-patrol.toml"
MINER_TOML="$ROOT/formulas/mol-feedback-miner.toml"
REBASE_TOML="$ROOT/packs/gascity-keeper/formulas/mol-upstream-gc-rebase.toml"
PRPREP_TOML="$ROOT/packs/gascity-keeper/formulas/mol-upstream-gc-pr-prep.toml"
POLECAT_TOML="$ROOT/formulas/mol-polecat-work.toml"
SYNC_TOML="$ROOT/packs/gascity-keeper/formulas/mol-upstream-gc-sync.toml"
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
for f in "$REVIEW_TOML" "$QUORUM_TOML" "$PATROL_TOML" "$MINER_TOML" "$REBASE_TOML" "$PRPREP_TOML" "$POLECAT_TOML" "$SYNC_TOML"; do
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

# gc names the pack for `gc gc-toolkit scripts-dir` ($STUB_PACK), answers
# `rig list` from the roster file and `bd show` from the bead file, and logs
# every other call, one line each. A `bd update` then exits FAKE_UPDATE_RC, so
# a case can have the store refuse the write.
BIN="$TMP/bin"; mkdir -p "$BIN"
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$BIN/gc" <<'GC'
case "$1 $2" in
  "gc-toolkit scripts-dir") [ -n "${STUB_PACK:-}" ] || exit 1; printf '%s/assets/scripts\n' "$STUB_PACK" ;;
  "rig list") cat "$FAKE_ROSTER" ;;
  "bd show")  cat "$FAKE_META" ;;
  *)          printf '%s\n' "$*" | tr '\n' ' ' >> "$FAKE_LOG"; echo >> "$FAKE_LOG"
              [ "$1 $2" != "bd update" ] || exit "${FAKE_UPDATE_RC:-0}" ;;
esac
exit 0
GC
chmod +x "$BIN/gc"
export PATH="$BIN:$PATH"

# Each block resolves its rig through rig-root.sh, since GC_RIG_ROOT here names a
# rig without the pack. The pack's own formulas find the script in the pack gc
# names, the repository under test. The gascity-keeper's formulas look for it
# under GC_CITY_PATH, and pack_into gives a keeper case's city the script.
export STUB_PACK="$ROOT"
pack_into() { mkdir -p "$1/rigs/gc-toolkit/assets/scripts"; cp "$HERE/rig-root.sh" "$1/rigs/gc-toolkit/assets/scripts/"; }

# copy <toml> <marker> <n>: the n-th copy of a marked block.
copy() {
  awk -v m="$2" -v want="$3" '
    $0 ~ ("# >>> " m "$") { n++; f = (n == want); next }
    $0 ~ ("# <<< " m "$") { f = 0 }
    f' "$1"
}
copies() { grep -c -- "# >>> $2\$" "$1" || true; }

# block <toml> <marker> <out> [<n>]: the n-th copy (default 1) of the marked
# block, with formula placeholders rendered as the materializer renders them:
# the binding as the binding plus a dot, gc-toolkit. here.
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
    -e 's|{{notify_recipient}}|mayor/|g' -e 's|{{requesting_keeper}}|keeper/from-var|g' \
    -e 's|{{base_ref}}|origin/main|g' -e 's|{{binding_prefix}}|gc-toolkit.|g' > "$3"
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

# --- 2. mol-review and mol-review-quorum-signoff: the review's gather. ---------
# The gather fetches the review's base and branch into the rig, makes the
# review's worktree there at the reviewed commit, and leaves the shell in it,
# where the check's method reads the diff. review-methods.test.sh holds the
# four steps that carry it to one text, so mol-review's copy runs for all four,
# filled in as a pour fills it for a correctness review of feature onto main.
# gc names this checkout as the pack, so the block runs the rig-root.sh,
# review-workspace.sh and review-checks.sh under test.
# formula-worktree-rig.test.sh proves where the worktree is registered, and
# that every git call in the block names its repository.
echo "── mol-review: review-gather ──"
GATHER="$(copy "$REVIEW_TOML" review-gather 1)"
[ -n "$GATHER" ] && ok "review-gather: block extracted between markers" \
  || bad "review-gather: block extracted between markers" "markers missing from ${REVIEW_TOML#"$ROOT"/}"
gather_render() { # <reviewed oid>
  printf '%s\n' "$GATHER" | sed -e 's|{{review_bead}}|rb|g' -e "s|{{reviewed_oid}}|$1|g" -e 's|{{review_base}}|main|g' \
    -e 's|{{review_branch}}|feature|g' -e 's|{{anchor_bead}}|tk-anc|g' -e 's|{{check}}|correctness|g' -e 's|{{review_pr_url}}||g' \
    -e 's|{{binding_prefix}}|gc-toolkit.|g'
}
gather_render 0123456789abcdef0123456789abcdef01234567 > "$TMP/gather.sh"
case "$(cat "$TMP/gather.sh")" in
  *'{{'*) bad "review-gather: no unrendered formula placeholder left" ;;
  *)      ok "review-gather: no unrendered formula placeholder left" ;;
esac
if bash -n "$TMP/gather.sh" 2>/dev/null; then ok "review-gather: block is valid bash"; else bad "review-gather: block is valid bash"; fi
printf '[{"id":"tk-anc","title":"the change under review"}]\n' > "$TMP/anchor.json"

# gather_case <mode> <label>: an origin whose base moves on after the rig and
# the cwd repo cloned it, then a branch cut from the moved base, so only the
# gather's own fetch brings either new head into the rig. The cwd repo fetches
# the branch, so a fetch or a diff that followed cwd would find the reviewed
# commit there, against its stale base. GATHER_UNREACHABLE points the rig's
# origin at nothing. GATHER_UNPUSHED reviews a commit no remote has. Sets RC,
# D, OID (the branch's head), BASE_OLD, BASE_NEW and WT, the worktree the block
# printed.
gather_case() {
  local d="$TMP/gather-$2" rc=0 review
  mkdir -p "$d/tmp"
  git init -q --bare -b main "$d/origin.git"
  git init -q -b main "$d/seed"
  BASE_OLD=$(commit "$d/seed" "gather base ($2)")
  git -C "$d/seed" push -q "$d/origin.git" main
  git clone -q "$d/origin.git" "$d/rig"
  git clone -q "$d/origin.git" "$d/cwd"
  BASE_NEW=$(commit "$d/seed" "base moved on ($2)")
  git -C "$d/seed" push -q "$d/origin.git" main
  git -C "$d/seed" checkout -q -b feature
  OID=$(commit "$d/seed" "branch work ($2)")
  git -C "$d/seed" push -q "$d/origin.git" feature
  git -C "$d/cwd" fetch -q origin feature
  review="$OID"
  if [ -n "${GATHER_UNPUSHED:-}" ]; then
    git -C "$d/seed" checkout -q -b local-only
    review=$(commit "$d/seed" "never pushed ($2)")
  fi
  [ -z "${GATHER_UNREACHABLE:-}" ] || git -C "$d/rig" remote set-url origin "$d/gone.git"
  FAKE_ROSTER="$d/roster.json"; pick "$1" "$d/rig"
  gather_render "$review" > "$d/gather.sh"
  ( cd "$d/cwd" && TMPDIR="$d/tmp" GC_RIG_ROOT="$RR" GC_RIG="$GR" FAKE_ROSTER="$d/roster.json" \
      FAKE_META="$TMP/anchor.json" FAKE_LOG="$d/gc.log" bash "$d/gather.sh" ) >"$d/out" 2>&1 || rc=$?
  WT=$(sed -n "s/^== The review's worktree: //p" "$d/out")
  RC=$rc; D=$d
}

for mode in env roster; do
  gather_case "$mode" "$mode"
  eq "$RC" 0 "gather/$mode: the block runs from a foreign cwd"
  eq "$(ref "$D/rig" origin/main)" "$BASE_NEW" "gather/$mode: the fetch brought the base's new head into the rig"
  eq "$(ref "$D/rig" origin/feature)" "$OID" "gather/$mode: the fetch brought the branch's head into the rig"
  eq "$(ref "$D/cwd" origin/main)" "$BASE_OLD" "gather/$mode: the cwd repo was not fetched"
  eq "$(git -C "${WT:-$D/no-worktree}" rev-parse HEAD 2>/dev/null || echo none)" "$OID" \
    "gather/$mode: the review's worktree is at the reviewed commit"
  DIFF=$(git -C "${WT:-$D/no-worktree}" diff --name-only origin/main...HEAD 2>&1 || true)
  has "$DIFF" "branch-work" "gather/$mode: the diff read in the worktree shows the branch's change"
  hasnt "$DIFF" "base-moved-on" "gather/$mode: the diff is taken against the base the rig fetched, not a stale one"
done
CONTROL=$(git -C "$D/cwd" diff --name-only "origin/main...$OID" 2>&1 || true)
has "$CONTROL" "base-moved-on" "control: the same diff in the cwd repo, whose base is stale, shows the base's change as the branch's"
gather_case nomatch nomatch
[ "$RC" -ne 0 ] && ok "gather/nomatch: an unresolvable rig fails closed" || bad "gather/nomatch: an unresolvable rig fails closed"
has "$(cat "$D/out")" "review: cannot resolve the rig root" "gather/nomatch: the block says the rig did not resolve"
eq "$(ref "$D/rig" origin/main)" "$BASE_OLD" "gather/nomatch: refused before fetching into the rig"
eq "$(ref "$D/cwd" origin/main)" "$BASE_OLD" "gather/nomatch: refused before fetching into the cwd repo"
eq "$WT" "" "gather/nomatch: no worktree is made"
GATHER_UNREACHABLE=1 gather_case env unreachable
[ "$RC" -ne 0 ] && ok "gather/unreachable: a fetch that fails stops the review" || bad "gather/unreachable: a fetch that fails stops the review"
eq "$WT" "" "gather/unreachable: no worktree is made from the rig's stale refs"
GATHER_UNPUSHED=1 gather_case env missing
[ "$RC" -ne 0 ] && ok "gather/missing: a reviewed commit the rig cannot fetch stops the review" \
  || bad "gather/missing: a reviewed commit the rig cannot fetch stops the review"
eq "$WT" "" "gather/missing: no worktree is made"

# --- 3. mol-refinery-patrol: the conflict reason. -------------------------------
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

# --- 4. mol-upstream-gc-rebase: the gascity worktree. ---------------------------
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
  pack_into "$d/city"
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

# --- 5. mol-upstream-gc-pr-prep: the gascity worktree. --------------------------
echo "── mol-upstream-gc-pr-prep: upstream-pr-prep-worktree-setup ──"
block "$PRPREP_TOML" upstream-pr-prep-worktree-setup "$TMP/prprep.sh"
eq "$(bare_git "$TMP/prprep.sh")" "" "pr-prep: every git call in the block names its repo with -C"

prprep_case() { # <gascity|other> <label> [<bd-update-rc>]; sets RC, D, WT, SHA
  local d="$TMP/prprep-$2" rc=0
  mkdir -p "$d/tmp" "$d/city"
  pack_into "$d/city"
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

# --- 6. mol-feedback-miner: the repository mined. ------------------------------
echo "── mol-feedback-miner: feedback-miner-repo ──"
eq "$(copies "$MINER_TOML" feedback-miner-repo)" 2 "miner: both steps carry the feedback-miner-repo block"
block "$MINER_TOML" feedback-miner-repo "$TMP/miner-1.sh" 1
block "$MINER_TOML" feedback-miner-repo "$TMP/miner-2.sh" 2
cmp -s "$TMP/miner-1.sh" "$TMP/miner-2.sh" && ok "miner: the two steps resolve the repository the same way" \
  || bad "miner: the two steps resolve the repository the same way"
eq "$(grep -c 'show-toplevel)"$' "$MINER_TOML" || true)" 0 "miner: no step takes the repository from the cwd's toplevel"
eq "$(awk '/# <<< feedback-miner-repo$/ { getline; print; exit }' "$MINER_TOML")" \
  "[ -n \"\$REPO\" ] || no_op \"cannot resolve the rig root\"" \
  "miner: load-context ends the run as a clean no-op when no rig resolves"
MN="$TMP/miner"
mkdir -p "$MN"
git init -q -b main "$MN/rig"; commit "$MN/rig" "miner rig" >/dev/null
git init -q -b main "$MN/cwd"; commit "$MN/cwd" "miner cwd" >/dev/null
for mode in env roster nomatch; do
  FAKE_ROSTER="$MN/roster-$mode.json"; pick "$mode" "$MN/rig"
  OUT=$(cd "$MN/cwd" && GC_RIG_ROOT="$RR" GC_RIG="$GR" FAKE_ROSTER="$MN/roster-$mode.json" FAKE_LOG="$MN/gc.log" \
          bash -c "$(cat "$TMP/miner-1.sh"; printf 'printf "REPO=%%s\\n" "$REPO"\n')" 2>/dev/null || true)
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
has "$OUT" "feedback-miner: cannot resolve the rig root — nothing to mine this run." \
  "miner/mine-and-file: the run says the rig did not resolve"
hasnt "$OUT" "SWEEP STARTED" "miner/mine-and-file: the sweep never starts"
has "$(cat "$MN/gc.log")" "step-close --step mol-feedback-miner.mine-and-file --outcome pass" "miner/mine-and-file: the step closes with outcome pass"
has "$(cat "$MN/gc.log")" "runtime drain-ack" "miner/mine-and-file: the session drains"

# --- 7. One rig-root lookup. -----------------------------------------------------
# rig-root.sh holds the lookup, so a fix to it lands once. In the formulas whose
# git calls name a rig by path no block reads the roster for a rig's path
# itself, every block finds rig-root.sh by one locator line, and the line after
# each locator calls it. The pack's own formulas ask gc for the pack, as every
# step that runs a pack script does. The gascity-keeper's formulas carry no
# binding for this pack, so theirs is the loop their other lookups of the
# pack's scripts use. The refinery scripts that resolve the rig themselves run
# the rig-root.sh beside them. rig-root.test.sh proves the lookup.
echo "── one rig-root lookup ──"
LOCATOR='RR="$(b='"'"'{{binding_prefix}}'"'"'; gc "${b%.}" scripts-dir)/rig-root.sh" && [ -x "$RR" ] || RR=""'
KEEPER_LOCATOR='RR=""; for c in "${GC_PACK_DIR:-}" "${GC_RIG_ROOT:-}" "${GC_CITY_PATH:-}/rigs/gc-toolkit"; do [ -x "$c/assets/scripts/rig-root.sh" ] && { RR="$c/assets/scripts/rig-root.sh"; break; }; done'
SITES=0
for f in "$REVIEW_TOML" "$QUORUM_TOML" "$PATROL_TOML" "$MINER_TOML" "$REBASE_TOML" "$PRPREP_TOML" "$POLECAT_TOML" "$SYNC_TOML"; do
  name="${f##*/}"
  want="$LOCATOR"
  case "$f" in "$ROOT"/packs/gascity-keeper/*) want="$KEEPER_LOCATOR" ;; esac
  eq "$(grep -c 'rig list --json[[:space:]]*|' "$f" || true)" 0 "$name: no block reads the roster for a rig's path itself"
  LINES=$(grep -E '^[[:space:]]*RR=' "$f" | sed 's/^[[:space:]]*//' || true)
  n=$(printf '%s\n' "$LINES" | awk 'NF { n++ } END { print n + 0 }')
  [ "$n" -ge 1 ] && ok "$name: $n block(s) find rig-root.sh" || bad "$name: blocks find rig-root.sh" "none"
  eq "$(printf '%s\n' "$LINES" | sort -u)" "$want" "$name: every block finds rig-root.sh by the one locator line"
  CALLS=$(awk 'f { sub(/^[[:space:]]*/, ""); print; f = 0 } /^[[:space:]]*RR=/ { f = 1 }' "$f")
  eq "$(printf '%s\n' "$CALLS" | grep -cF '$("${RR:?rig-root.sh not found in the pack}"' || true)" "$n" "$name: the line after each locator calls rig-root.sh"
  SITES=$((SITES + n))
done
for b in gather reason rebase prprep miner-1 miner-2; do
  grep -qF '"${RR:?rig-root.sh not found in the pack}"' "$TMP/$b.sh" && ok "$b: the block resolves its rig through rig-root.sh" \
    || bad "$b: the block resolves its rig through rig-root.sh"
done
echo "($SITES blocks in all)"
for s in direct-merge-push.sh refinery-workspace.sh; do
  eq "$(grep -c 'rig list --json' "$HERE/$s" || true)" 0 "$s: reads no roster itself"
  eq "$(grep -c '"$SCRIPTS_DIR/rig-root.sh"' "$HERE/$s" || true)" 1 "$s: resolves the rig through the rig-root.sh beside it"
done

echo "-----"
echo "formula-git-rig: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
