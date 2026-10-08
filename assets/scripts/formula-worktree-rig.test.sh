#!/usr/bin/env bash
# Hermetic test: a formula step that creates a git worktree names the rig by
# path, so the session's cwd never chooses the repository.
#
# A static guard scans formulas/ and packs/*/formulas/ and fails on any bare
# `git worktree add`, so a new site cannot land without -C. The worktree blocks
# of mol-review, mol-upstream-gc-sync and mol-refinery-patrol are extracted
# verbatim and run from a WRONG cwd against real git repos: each must act on the
# rig GC_RIG_ROOT names, or the roster entry for GC_RIG, and fail closed when
# neither resolves. A control runs a bare add from the same cwd and proves cwd
# steers it, so "landed in the rig, not cwd" is a real discrimination. No live
# city, store, or network.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
REVIEW_TOML="$ROOT/formulas/mol-review.toml"
PATROL_TOML="$ROOT/formulas/mol-refinery-patrol.toml"
SYNC_TOML="$ROOT/packs/gascity-keeper/formulas/mol-upstream-gc-sync.toml"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-formula-worktree-rig-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1${2:+ ($2)}"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3" "got '$1' want '$2'"; fi; }

command -v jq  >/dev/null 2>&1 || { echo "jq is required"  >&2; exit 1; }
command -v git >/dev/null 2>&1 || { echo "git is required" >&2; exit 1; }
for f in "$REVIEW_TOML" "$PATROL_TOML" "$SYNC_TOML"; do
  [ -s "$f" ] || { echo "formula not found: $f" >&2; exit 1; }
done

# The blocks fall back to `gc rig list --json` when GC_RIG_ROOT is empty, so no
# ambient city value may reach them: each run sets its own, and a stub gc heads
# PATH so the live one is never asked. The review workspace goes under
# REVIEW_WORKSPACE_DIR when that is set, so each review run names its own
# TMPDIR instead. Git reads no user or system config, so cwd versus -C is the
# only thing steering it.
unset GC_RIG_ROOT GC_RIG GC_CITY GC_CITY_PATH GC_PACK_DIR REVIEW_WORKSPACE_DIR 2>/dev/null || true
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR 2>/dev/null || true
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

BIN="$TMP/bin"; mkdir -p "$BIN"
cat > "$BIN/gc" <<'GC'
#!/usr/bin/env bash
# rig list answers the roster file and bd show the bead file; every other call
# is logged and succeeds.
case "$1 $2" in
  "rig list") cat "$FAKE_ROSTER" ;;
  "bd show")  cat "$FAKE_META" ;;
  *)          echo "$*" >> "$FAKE_LOG" ;;
esac
GC
cat > "$BIN/lifecycle" <<'LC'
#!/usr/bin/env bash
echo "$*" >> "$FAKE_LC_LOG"
LC
chmod +x "$BIN/gc" "$BIN/lifecycle"
export PATH="$BIN:$PATH"
export FAKE_ROSTER="$TMP/roster.json"

extract() { awk -v m="$2" '$0 ~ ("# >>> " m "$") {f=1; next} $0 ~ ("# <<< " m "$") {f=0} f' "$1"; }

# block <toml> <marker> <out>: the marked block, with formula placeholders
# rendered as the materializer renders them, written to <out>.
block() {
  local body
  body="$(extract "$1" "$2")"
  if [ -z "$body" ]; then
    bad "$2: block extracted between markers" "markers missing from ${1#"$ROOT"/}"
    : > "$3"
    return 0
  fi
  ok "$2: block extracted between markers"
  printf '%s\n' "$body" | sed 's|{{base_branch}}|main|g' > "$3"
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

# bare_adds <file>...: file:line of every `git worktree add` without -C,
# outside comment lines.
bare_adds() {
  awk '
    /^[[:space:]]*#/ { next }
    match($0, "(^|[^-.A-Za-z0-9_/])git[[:space:]]+worktree[[:space:]]+add([^-A-Za-z0-9_]|$)") { print FILENAME ":" FNR }
  ' "$@"
}

count() { awk 'NF { n++ } END { print n + 0 }'; }
wt_paths() { git -C "$1" worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p'; }
# in_paths <newline-separated paths> <path> -> yes|no, compared by realpath so a
# symlinked TMPDIR cannot turn a real match into a miss.
in_paths() {
  local want p
  want="$(realpath -m "$2" 2>/dev/null || printf '%s' "$2")"
  while IFS= read -r p; do
    [ -n "$p" ] && [ -n "$want" ] && [ "$(realpath -m "$p")" = "$want" ] && { echo yes; return 0; }
  done <<< "$1"
  echo no
}
registered() { in_paths "$(wt_paths "$1")" "$2"; }
commit() { git -C "$1" commit -q --allow-empty -m "$2"; git -C "$1" rev-parse HEAD; }

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

# --- 1. Guard: no formula runs a bare `git worktree add`. ----------------------
echo "── guard ──"
cat > "$TMP/detector.sh" <<'SAMPLE'
X=$(git rev-parse HEAD)
git worktree add "$W" --detach main
see `git worktree add` in prose
git -C "$R" worktree add "$W" --detach main
P="$(git -C "$R" rev-parse --git-common-dir)/x"
# git fetch inside a comment is not a call
SAMPLE
# Positive controls: each detector flags the bare shapes and passes the -C ones,
# so a green guard below is not a detector that matches nothing.
eq "$(bare_git "$TMP/detector.sh")" "rev-parse worktree worktree " \
  "detector: bare_git reports each bare call and skips -C calls, comments and --git-* flags"
eq "$(bare_adds "$TMP/detector.sh" | sed 's|.*:||' | tr '\n' ' ')" "2 3 " \
  "detector: bare_adds flags a bare add in code and in prose, never the -C form"

FILES=()
for f in "$ROOT"/formulas/*.toml "$ROOT"/packs/*/formulas/*.toml; do
  [ -f "$f" ] && FILES+=("$f")
done
for f in "$REVIEW_TOML" "$PATROL_TOML" "$SYNC_TOML"; do
  case " ${FILES[*]} " in
    *" $f "*) ok "guard: the scan covers ${f#"$ROOT"/}" ;;
    *)        bad "guard: the scan covers ${f#"$ROOT"/}" ;;
  esac
done
eq "$(bare_adds "${FILES[@]}" | sed "s|^$ROOT/||" | tr '\n' ' ')" "" \
  "guard: no formula in formulas/ or packs/*/formulas/ runs a bare git worktree add"

# --- 2. Control: a bare `git worktree add` follows cwd. ------------------------
# What the three sites shipped before they named the rig. Without it, "landed in
# the rig, not cwd" below would pass even if -C did nothing.
echo "── control ──"
C="$TMP/control"
git init -q -b main "$C/rig"; commit "$C/rig" "control rig" >/dev/null
git init -q -b main "$C/cwd"; commit "$C/cwd" "control cwd" >/dev/null
( cd "$C/cwd" && GC_RIG_ROOT="$C/rig" git worktree add -q "$C/wt-bare" --detach HEAD ) >/dev/null 2>&1 || true
eq "$(registered "$C/cwd" "$C/wt-bare")" yes "control: the bare add registered in the cwd repo"
eq "$(registered "$C/rig" "$C/wt-bare")" no  "control: the bare add never reached the rig, whatever GC_RIG_ROOT says"

# --- 3. mol-review: the review's test worktree. --------------------------------
# The worktree lives in the review's workspace, made by review-workspace.sh add
# and removed by the verdict step's remove line.
echo "── mol-review: review-workspace-add and review-workspace-remove ──"
block "$REVIEW_TOML" review-workspace-add "$TMP/review.sh"
# The pack-script locator's show-toplevel candidate is the block's one bare git
# call. It picks where review-workspace.sh is read from, never the repository
# the worktree is made in.
eq "$(bare_git "$TMP/review.sh")" "rev-parse " "review: the only git call without -C is the pack-script locator's"
block "$REVIEW_TOML" review-workspace-remove "$TMP/review-rm.sh"
cat "$TMP/review.sh" - > "$TMP/review-probe.sh" <<'PROBE'
printf '%s\n' "$REVIEW_WT" > "$PROBE/wt"
pwd -P > "$PROBE/pwd"
git -C "$REVIEW_WT" rev-parse HEAD > "$PROBE/head"
git -C "$PROBE_RIG" worktree list --porcelain | sed -n 's/^worktree //p' > "$PROBE/rig"
git -C "$PROBE_CWD" worktree list --porcelain | sed -n 's/^worktree //p' > "$PROBE/cwd"
PROBE

# GC_PACK_DIR names this checkout, so the block runs the review-workspace.sh
# under test.
review_case() { # <mode>; sets RC, OID, D
  local d="$TMP/review-$1" rc=0
  mkdir -p "$d/probe" "$d/tmp"
  git init -q -b main "$d/rig"; OID=$(commit "$d/rig" "reviewed head ($1)")
  # The cwd repo is a clone, so it holds the reviewed commit too: an add that
  # follows cwd succeeds there instead of failing for want of the commit.
  git clone -q "$d/rig" "$d/cwd"; commit "$d/cwd" "cwd repo moves on ($1)" >/dev/null
  pick "$1" "$d/rig"
  ( cd "$d/cwd" && TMPDIR="$d/tmp" GC_PACK_DIR="$ROOT" GC_RIG_ROOT="$RR" GC_RIG="$GR" REVIEW_BEAD=rb REVIEWED_OID="$OID" \
      PROBE="$d/probe" PROBE_RIG="$d/rig" PROBE_CWD="$d/cwd" bash "$TMP/review-probe.sh" ) >"$d/out" 2>&1 || rc=$?
  RC=$rc; D=$d
}

# review_remove: the verdict step's remove line, run from the same foreign cwd.
review_remove() {
  ( cd "$D/cwd" && TMPDIR="$D/tmp" REVIEW_BEAD=rb SC="$ROOT/assets/scripts/step-close.sh" \
      bash "$TMP/review-rm.sh" ) >>"$D/out" 2>&1 || true
}

for mode in env roster; do
  review_case "$mode"
  eq "$RC" 0 "review/$mode: the block runs from a foreign cwd"
  WT="$(cat "$D/probe/wt" 2>/dev/null || true)"
  eq "$(in_paths "$(cat "$D/probe/rig" 2>/dev/null || true)" "$WT")" yes "review/$mode: the worktree is registered in the RIG repo"
  eq "$(in_paths "$(cat "$D/probe/cwd" 2>/dev/null || true)" "$WT")" no  "review/$mode: the worktree is NOT registered in the cwd repo"
  eq "$(cat "$D/probe/head" 2>/dev/null || true)" "$OID" "review/$mode: the worktree is checked out at the reviewed OID"
  eq "$(cat "$D/probe/pwd" 2>/dev/null || true)" "$(realpath -m "${WT:-/nonexistent}")" "review/$mode: the block leaves the shell in the review worktree"
  review_remove
  eq "$(registered "$D/rig" "$WT")" no "review/$mode: the verdict step's remove unregisters the worktree from the rig"
  if [ -n "$WT" ] && [ ! -e "$WT" ]; then ok "review/$mode: the verdict step's remove deletes the worktree directory"
  else bad "review/$mode: the verdict step's remove deletes the worktree directory" "${WT:-<no worktree recorded>}"; fi
done

review_case nomatch
[ "$RC" -ne 0 ] && ok "review/nomatch: an unresolvable rig fails closed" || bad "review/nomatch: an unresolvable rig fails closed"
eq "$(wt_paths "$D/rig" | count)" 1 "review/nomatch: nothing registered in the rig repo"
eq "$(wt_paths "$D/cwd" | count)" 1 "review/nomatch: nothing registered in the cwd repo"
eq "$(ls -A "$D/tmp" | count)" 0 "review/nomatch: refused before creating the review workspace"

# --- 4. mol-upstream-gc-sync: the read-only survey worktree. -------------------
echo "── mol-upstream-gc-sync: upstream-sync-worktree-add ──"
block "$SYNC_TOML" upstream-sync-worktree-add "$TMP/sync.sh"
eq "$(bare_git "$TMP/sync.sh")" "" "sync: every git call in the block names its repo with -C"

sync_case() { # <mode>; sets RC, D, NEW, STALE
  local d="$TMP/sync-$1" rc=0
  mkdir -p "$d"
  git init -q --bare -b main "$d/origin.git"
  git init -q -b main "$d/seed"
  commit "$d/seed" "base ($1)" >/dev/null
  git -C "$d/seed" push -q "$d/origin.git" main
  git clone -q "$d/origin.git" "$d/rig"
  # origin moves on after the rig last fetched, so only the block's own fetch,
  # run against the rig, can bring the new commit in.
  NEW=$(commit "$d/seed" "origin moved on ($1)")
  git -C "$d/seed" push -q "$d/origin.git" main
  STALE=$(git -C "$d/rig" rev-parse origin/main)
  # The cwd repo has an origin/main of its own, so a fetch and add that follow
  # cwd succeed there instead of failing for want of the ref.
  git init -q --bare -b main "$d/foreign.git"
  git init -q -b main "$d/cwd"; commit "$d/cwd" "unrelated cwd repo ($1)" >/dev/null
  git -C "$d/cwd" remote add origin "$d/foreign.git"
  git -C "$d/cwd" push -q origin main
  pick "$1" "$d/rig"
  ( cd "$d/cwd" && GC_RIG_ROOT="$RR" GC_RIG="$GR" WORKTREE_PATH="$d/wt" bash "$TMP/sync.sh" ) >"$d/out" 2>&1 || rc=$?
  RC=$rc; D=$d
}

for mode in env roster; do
  sync_case "$mode"
  eq "$RC" 0 "sync/$mode: the block runs from a foreign cwd"
  eq "$(registered "$D/rig" "$D/wt")" yes "sync/$mode: the worktree is registered in the RIG repo"
  eq "$(registered "$D/cwd" "$D/wt")" no  "sync/$mode: the worktree is NOT registered in the cwd repo"
  [ "$STALE" != "$NEW" ] && ok "sync/$mode: precondition, the rig's origin/main is stale before the block" \
    || bad "sync/$mode: precondition, the rig's origin/main is stale before the block"
  eq "$(git -C "$D/wt" rev-parse HEAD 2>/dev/null || true)" "$NEW" "sync/$mode: the rig was fetched, so the worktree starts at origin's current main"
  eq "$(git -C "$D/wt" rev-parse --abbrev-ref HEAD 2>/dev/null || true)" HEAD "sync/$mode: the worktree is detached"
done

sync_case nomatch
[ "$RC" -ne 0 ] && ok "sync/nomatch: an unresolvable rig fails closed" || bad "sync/nomatch: an unresolvable rig fails closed"
[ ! -e "$D/wt" ] && ok "sync/nomatch: nothing created at WORKTREE_PATH" || bad "sync/nomatch: nothing created at WORKTREE_PATH"
eq "$(git -C "$D/rig" rev-parse origin/main)" "$STALE" "sync/nomatch: refused before fetching into the rig"
eq "$(wt_paths "$D/rig" | count)" 1 "sync/nomatch: nothing registered in the rig repo"
eq "$(wt_paths "$D/cwd" | count)" 1 "sync/nomatch: nothing registered in the cwd repo"

# --- 5. mol-refinery-patrol: the prep and direct-merge worktrees. ---------------
# patrol_rig <dir> <label>: an origin carrying main and polecat/wb one commit
# ahead, the rig cloned from it, and a foreign cwd repo whose own origin also
# carries a main. Sets BASE, FEATURE, FOREIGN and PREP (the rig's prep path).
patrol_rig() {
  local d="$1"
  git init -q --bare -b main "$d/origin.git"
  git init -q -b main "$d/seed"
  BASE=$(commit "$d/seed" "rig base ($2)")
  git -C "$d/seed" push -q "$d/origin.git" main
  git -C "$d/seed" checkout -q -b polecat/wb
  FEATURE=$(commit "$d/seed" "feature ($2)")
  git -C "$d/seed" push -q "$d/origin.git" polecat/wb
  git clone -q "$d/origin.git" "$d/rig"
  git init -q --bare -b main "$d/foreign.git"
  git init -q -b main "$d/cwd"
  FOREIGN=$(commit "$d/cwd" "foreign ($2)")
  git -C "$d/cwd" remote add origin "$d/foreign.git"
  git -C "$d/cwd" push -q origin main
  PREP="$(git -C "$d/rig" rev-parse --path-format=absolute --git-common-dir)/gc-refinery-prep"
}

echo "── mol-refinery-patrol: shared-branch-merge-mode and shared-branch-push-mode ──"
block "$PATROL_TOML" shared-branch-merge-mode "$TMP/prep.sh"
eq "$(bare_git "$TMP/prep.sh")" "" "prep: every git call in the block names its repo with -C"
block "$PATROL_TOML" shared-branch-push-mode "$TMP/push.sh"
eq "$(bare_git "$TMP/push.sh")" "" "push: every git call in the block names its repo with -C"

printf '%s\n' '[{"metadata":{"branch":"polecat/wb","target":"main"}}]' > "$TMP/meta.json"
prep_case() { # <mode>; sets RC, D, NEWHEAD, STALE (and patrol_rig's globals)
  local d="$TMP/prep-$1" rc=0
  mkdir -p "$d"
  patrol_rig "$d" "prep $1"
  # The branch moves on after the rig last fetched, so only the block's own
  # fetch, run against the rig, can stage the new head.
  NEWHEAD=$(commit "$d/seed" "feature follow-up (prep $1)")
  git -C "$d/seed" push -q "$d/origin.git" polecat/wb
  STALE=$(git -C "$d/rig" rev-parse origin/polecat/wb)
  pick "$1" "$d/rig"
  ( cd "$d/cwd" && GC_RIG_ROOT="$RR" GC_RIG="$GR" WORK=wb TARGET_BRANCH_DEFAULT=main \
      FAKE_META="$TMP/meta.json" FAKE_LOG="$d/gc.log" bash "$TMP/prep.sh" ) >"$d/out" 2>&1 || rc=$?
  RC=$rc; D=$d
}

for mode in env roster; do
  prep_case "$mode"
  eq "$RC" 0 "prep/$mode: the block runs from a foreign cwd"
  eq "$(registered "$D/rig" "$PREP")" yes "prep/$mode: the prep worktree is registered in the RIG repo"
  eq "$(wt_paths "$D/cwd" | count)" 1 "prep/$mode: nothing registered in the cwd repo"
  [ "$STALE" != "$NEWHEAD" ] && ok "prep/$mode: precondition, the rig's origin/polecat/wb is stale before the block" \
    || bad "prep/$mode: precondition, the rig's origin/polecat/wb is stale before the block"
  eq "$(git -C "$PREP" rev-parse HEAD 2>/dev/null || true)" "$NEWHEAD" "prep/$mode: the rig was fetched, so the staged head is the branch's current tip"
done

prep_case nomatch
[ "$RC" -ne 0 ] && ok "prep/nomatch: an unresolvable rig fails closed" || bad "prep/nomatch: an unresolvable rig fails closed"
[ ! -e "$PREP" ] && ok "prep/nomatch: no prep worktree staged" || bad "prep/nomatch: no prep worktree staged"
eq "$(git -C "$D/rig" rev-parse origin/polecat/wb)" "$STALE" "prep/nomatch: refused before fetching into the rig"
grep -qxF 'runtime drain-ack' "$D/gc.log" 2>/dev/null \
  && ok "prep/nomatch: the refinery drains, leaving the work to retry" \
  || bad "prep/nomatch: the refinery drains, leaving the work to retry"

echo "── mol-refinery-patrol: direct-merge-push ──"
block "$PATROL_TOML" direct-merge-push "$TMP/merge.sh"
eq "$(bare_git "$TMP/merge.sh")" "" "direct-merge: every git call in the block names its repo with -C"

merge_case() { # <mode>; sets RC, D (and patrol_rig's globals)
  local d="$TMP/merge-$1" rc=0
  mkdir -p "$d/tmp"
  patrol_rig "$d" "merge $1"
  # The rebase step leaves the prepared head staged here, detached.
  git -C "$d/rig" worktree add -q -f --detach "$PREP" origin/polecat/wb
  pick "$1" "$d/rig"
  ( cd "$d/cwd" && TMPDIR="$d/tmp" GC_RIG_ROOT="$RR" GC_RIG="$GR" WORK=wb TARGET=main BRANCH=polecat/wb \
      LC="$BIN/lifecycle" FAKE_LOG="$d/gc.log" FAKE_LC_LOG="$d/lc.log" bash "$TMP/merge.sh" ) >"$d/out" 2>&1 || rc=$?
  RC=$rc; D=$d
}

for mode in env roster; do
  merge_case "$mode"
  eq "$RC" 0 "direct-merge/$mode: the block runs from a foreign cwd"
  eq "$(git -C "$D/origin.git" rev-parse main)" "$FEATURE" "direct-merge/$mode: the merge landed on the RIG's origin"
  eq "$(git -C "$D/foreign.git" rev-parse main)" "$FOREIGN" "direct-merge/$mode: the cwd repo's origin is untouched"
  eq "$(git -C "$D/rig" rev-parse origin/main)" "$FEATURE" "direct-merge/$mode: the push is verified against the rig's refreshed origin/main"
  case "$(cat "$D/lc.log" 2>/dev/null || true)" in
    "transition wb --to merged --close --set merged_sha=$FEATURE --set merged_target=main "*)
      ok "direct-merge/$mode: recorded and closed through one lifecycle transition" ;;
    *) bad "direct-merge/$mode: recorded and closed through one lifecycle transition" "$(cat "$D/lc.log" 2>/dev/null || true)" ;;
  esac
  eq "$(wt_paths "$D/rig" | count)" 2 "direct-merge/$mode: the merge worktree is unregistered on exit; the rig and its prep worktree remain"
  eq "$(wt_paths "$D/cwd" | count)" 1 "direct-merge/$mode: no worktree is left registered in the cwd repo"
  eq "$(ls -A "$D/tmp" | count)" 0 "direct-merge/$mode: the scratch directory is removed on exit"
done

merge_case nomatch
[ "$RC" -ne 0 ] && ok "direct-merge/nomatch: an unresolvable rig fails closed" || bad "direct-merge/nomatch: an unresolvable rig fails closed"
eq "$(git -C "$D/origin.git" rev-parse main)" "$BASE" "direct-merge/nomatch: nothing pushed to the rig's origin"
eq "$(git -C "$D/foreign.git" rev-parse main)" "$FOREIGN" "direct-merge/nomatch: nothing pushed to the cwd repo's origin"
[ ! -s "$D/lc.log" ] && ok "direct-merge/nomatch: no lifecycle transition" || bad "direct-merge/nomatch: no lifecycle transition"
grep -qxF 'runtime drain-ack' "$D/gc.log" 2>/dev/null \
  && ok "direct-merge/nomatch: the refinery drains, leaving the work to retry" \
  || bad "direct-merge/nomatch: the refinery drains, leaving the work to retry"
eq "$(ls -A "$D/tmp" | count)" 0 "direct-merge/nomatch: refused before creating any scratch directory"

# --- 6. mol-refinery-patrol resolves RIG_ROOT one way. -------------------------
# Every refinery block derives the prep worktree's path from RIG_ROOT, so two
# blocks that resolved it differently could stage and read different repos.
echo "── mol-refinery-patrol: one rig-root lookup ──"
LOOKUPS=$(awk '/^RIG_ROOT=/ { l = $0; getline a; getline b; print l " " a " " b }' "$PATROL_TOML")
N=$(printf '%s\n' "$LOOKUPS" | count)
[ "$N" -ge 2 ] && ok "patrol: $N RIG_ROOT resolutions found" || bad "patrol: RIG_ROOT resolutions found" "$N"
eq "$(printf '%s\n' "$LOOKUPS" | sort -u | count)" 1 "patrol: every RIG_ROOT resolution is the same lookup, copied verbatim"
case "$LOOKUPS" in
  *show-toplevel*) bad "patrol: no RIG_ROOT resolution falls back to cwd" ;;
  *)               ok  "patrol: no RIG_ROOT resolution falls back to cwd" ;;
esac
eq "$(printf '%s\n' "$LOOKUPS" | grep -cF '[ -n "$RIG_ROOT" ] || { echo "cannot resolve the rig root' || true)" "$N" \
  "patrol: every RIG_ROOT resolution ends in the fail-closed guard"

echo "-----"
echo "formula-worktree-rig: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
