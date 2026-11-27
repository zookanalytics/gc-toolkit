#!/usr/bin/env bash
# Hermetic test: a formula step that creates a git worktree names the rig by
# path, so the session's cwd never chooses the repository.
#
# A static guard scans formulas/ and packs/*/formulas/ and fails on any bare
# `git worktree add`, so a new site cannot land without -C. The worktree block
# of mol-upstream-gc-sync is extracted and run from a WRONG cwd against real git
# repos: it must act on the rig GC_RIG_ROOT names, or the roster entry for
# GC_RIG, and fail closed when neither resolves. A control runs a bare add from
# the same cwd and proves cwd steers it, so "landed in the rig, not cwd" is a
# real discrimination. No live city, store, or network.
#
# run-tests-scope: tree
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SYNC_TOML="$ROOT/packs/gascity-keeper/formulas/mol-upstream-gc-sync.toml"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-formula-worktree-rig-test.XXXXXX")"
# git lists a worktree by its resolved path, so every path is built on a
# resolved root and compares to git's as a string, a TMPDIR behind a symlink
# (as macOS's is) included.
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1${2:+ ($2)}"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3" "got '$1' want '$2'"; fi; }

command -v jq  >/dev/null 2>&1 || { echo "jq is required"  >&2; exit 1; }
command -v git >/dev/null 2>&1 || { echo "git is required" >&2; exit 1; }
[ -s "$SYNC_TOML" ] || { echo "formula not found: $SYNC_TOML" >&2; exit 1; }

# The blocks fall back to `gc rig list --json` when GC_RIG_ROOT is empty, so no
# ambient city value may reach them: each run sets its own, and a stub gc heads
# PATH so the live one is never asked. Git reads no user or system config, so
# cwd versus -C is the only thing steering it.
unset GC_RIG_ROOT GC_RIG GC_CITY GC_CITY_PATH GC_PACK_DIR 2>/dev/null || true
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR 2>/dev/null || true
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

BIN="$TMP/bin"; mkdir -p "$BIN"
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$BIN/gc" <<'GC'
# rig list answers the roster file, and `gc gc-toolkit scripts-dir` the pack
# $STUB_PACK names; every other call is logged and succeeds.
case "$1 $2" in
  "gc-toolkit scripts-dir") [ -n "${STUB_PACK:-}" ] || exit 1; printf '%s/assets/scripts\n' "$STUB_PACK" ;;
  "rig list") cat "$FAKE_ROSTER" ;;
  *) echo "$*" >> "$FAKE_LOG" ;;
esac
GC
chmod +x "$BIN/gc"
export PATH="$BIN:$PATH"
export FAKE_ROSTER="$TMP/roster.json"

extract() { awk -v m="$2" '$0 ~ ("# >>> " m "$") {f=1; next} $0 ~ ("# <<< " m "$") {f=0} f' "$1"; }

# block <toml> <marker> <out>: the marked block, with formula placeholders
# rendered as the materializer renders them, written to <out>.
# delete_merged_branches takes the patrol's default, true.
block() {
  local body
  body="$(extract "$1" "$2")"
  if [ -z "$body" ]; then
    bad "$2: block extracted between markers" "markers missing from ${1#"$ROOT"/}"
    : > "$3"
    return 0
  fi
  ok "$2: block extracted between markers"
  printf '%s\n' "$body" | sed 's|{{base_branch}}|main|g; s|{{delete_merged_branches}}|true|g; s|{{binding_prefix}}|gc-toolkit.|g' > "$3"
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
# in_paths <newline-separated paths> <path> -> yes|no, an exact line match.
in_paths() {
  if [ -n "$2" ] && grep -qxF -- "$2" <<< "$1"; then echo yes; else echo no; fi
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
for f in "$SYNC_TOML"; do
  case " ${FILES[*]} " in
    *" $f "*) ok "guard: the scan covers ${f#"$ROOT"/}" ;;
    *)        bad "guard: the scan covers ${f#"$ROOT"/}" ;;
  esac
done
eq "$(bare_adds "${FILES[@]}" | sed "s|^$ROOT/||" | tr '\n' ' ')" "" \
  "guard: no formula in formulas/ or packs/*/formulas/ runs a bare git worktree add"

# --- 2. Control: a bare `git worktree add` follows cwd. ------------------------
# What a site shipped before it named the rig. Without it, "landed in the rig,
# not cwd" below would pass even if -C did nothing.
echo "── control ──"
C="$TMP/control"
git init -q -b main "$C/rig"; commit "$C/rig" "control rig" >/dev/null
git init -q -b main "$C/cwd"; commit "$C/cwd" "control cwd" >/dev/null
( cd "$C/cwd" && GC_RIG_ROOT="$C/rig" git worktree add -q "$C/wt-bare" --detach HEAD ) >/dev/null 2>&1 || true
eq "$(registered "$C/cwd" "$C/wt-bare")" yes "control: the bare add registered in the cwd repo"
eq "$(registered "$C/rig" "$C/wt-bare")" no  "control: the bare add never reached the rig, whatever GC_RIG_ROOT says"

# --- 3. mol-upstream-gc-sync: the read-only survey worktree. -------------------
echo "── mol-upstream-gc-sync: upstream-sync-worktree-add ──"
block "$SYNC_TOML" upstream-sync-worktree-add "$TMP/sync.sh"
eq "$(bare_git "$TMP/sync.sh")" "" "sync: every git call in the block names its repo with -C"

# The stub gc names this checkout as the pack, so the block runs the rig-root.sh under test.
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
  ( cd "$d/cwd" && STUB_PACK="$ROOT" GC_RIG_ROOT="$RR" GC_RIG="$GR" WORKTREE_PATH="$d/wt" bash "$TMP/sync.sh" ) >"$d/out" 2>&1 || rc=$?
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

echo "-----"
echo "formula-worktree-rig: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
