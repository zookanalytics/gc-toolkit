#!/usr/bin/env bash
# Hermetic test: a formula step that creates a git worktree names the rig by
# path, so the session's cwd never chooses the repository.
#
# A static guard scans formulas/ and packs/*/formulas/ and fails on any bare
# `git worktree add`, so a new site cannot land without -C. The worktree blocks
# of mol-review, mol-upstream-gc-sync and mol-refinery-patrol are extracted and
# run from a WRONG cwd against real git repos, mol-review's filled in with a
# review's values as a pour fills them: each must act on the rig GC_RIG_ROOT
# names, or the roster entry for GC_RIG, and fail closed when neither resolves.
# mol-review's gather also prints the reviewed commit's guidance for the
# review's check alone and what gctk rig recorded there, read in the review's
# worktree, and load-dispatch's refusal of a short record names the
# missing key and leaves the route empty. A control runs a bare add from the same cwd and proves cwd
# steers it, so "landed in the rig, not cwd" is a real discrimination. No live
# city, store, or network.
#
# run-tests-scope: tree
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
REVIEW_TOML="$ROOT/formulas/mol-review.toml"
PATROL_TOML="$ROOT/formulas/mol-refinery-patrol.toml"
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
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$BIN/gc" <<'GC'
# rig list answers the roster file, bd show the bead file, and
# `gc gc-toolkit scripts-dir` the pack $STUB_PACK names; every other call
# is logged and succeeds, and a bd update also writes its --set-metadata and
# --unset-metadata to the bead file.
case "$1 $2" in
  "gc-toolkit scripts-dir") [ -n "${STUB_PACK:-}" ] || exit 1; printf '%s/assets/scripts\n' "$STUB_PACK" ;;
  "rig list") cat "$FAKE_ROSTER" ;;
  "bd show")  cat "$FAKE_META" ;;
  *)
    echo "$*" >> "$FAKE_LOG"
    if [ "$1 $2" = "bd update" ] && [ -n "${FAKE_META:-}" ]; then
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
GC
cat > "$BIN/lifecycle" <<'LC'
#!/usr/bin/env bash
echo "$*" >> "$FAKE_LC_LOG"
echo "${GC_RIG_ROOT:-<unset>}" >> "$FAKE_LC_LOG.root"
LC
# gctk answers the gather's record reads: a fail of the tests, a pass of lint
# and nothing for typecheck, logging each call and the directory it ran in.
cat > "$TMP/gctk" <<'GCTK'
#!/usr/bin/env bash
printf '%s|%s\n' "$*" "$(pwd -P)" >> "$GCTK_LOG"
case "$2" in
  test) echo '{"check":"test","result":"fail","scope":"affected","exit_code":1,"command":"t"}'; exit 1 ;;
  lint) echo '{"check":"lint","result":"pass","exit_code":0,"command":"l"}'; exit 0 ;;
  *) exit 3 ;;
esac
GCTK
chmod +x "$BIN/gc" "$BIN/lifecycle" "$TMP/gctk"
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

# --- 3. mol-review: the review's worktree. -------------------------------------
# load-dispatch's gather makes the worktree in the review's workspace through
# review-workspace.sh add, and the verdict step's remove line removes it. The
# pour fills in the values a review is told, so each case renders the block
# with its own commit, for a pre-open review of polecat/x onto main.
echo "── mol-review: review-gather and review-workspace-remove ──"
review_render() { # <text> <check> <oid>
  printf '%s\n' "$1" | sed -e 's|{{review_bead}}|rb|g' -e "s|{{reviewed_oid}}|$3|g" -e 's|{{review_base}}|main|g' \
    -e 's|{{review_branch}}|polecat/x|g' -e 's|{{anchor_bead}}|tk-anc|g' -e "s|{{check}}|$2|g" -e 's|{{review_pr_url}}||g' \
    -e 's|{{binding_prefix}}|gc-toolkit.|g'
}
GATHER="$(extract "$REVIEW_TOML" review-gather)"
[ -n "$GATHER" ] && ok "review-gather: block extracted between markers" || bad "review-gather: block extracted between markers" "markers missing from formulas/mol-review.toml"
review_render "$GATHER" correctness 0123456789abcdef0123456789abcdef01234567 > "$TMP/review-render.sh"
case "$(cat "$TMP/review-render.sh")" in
  *'{{'*) bad "review-gather: no unrendered formula placeholder left once a review's values fill it" ;;
  *)      ok "review-gather: no unrendered formula placeholder left once a review's values fill it" ;;
esac
if bash -n "$TMP/review-render.sh" 2>/dev/null; then ok "review-gather: block is valid bash"; else bad "review-gather: block is valid bash"; fi
# The block asks gc for the pack's scripts, so every git call it makes names
# the repository it acts on.
eq "$(bare_git "$TMP/review-render.sh")" "" "review: every git call in the block names its repo with -C"
extract "$REVIEW_TOML" review-workspace-remove > "$TMP/review-rm.tmpl"
[ -s "$TMP/review-rm.tmpl" ] && ok "review-workspace-remove: block extracted between markers" \
  || bad "review-workspace-remove: block extracted between markers" "markers missing from formulas/mol-review.toml"
PROBE_TAIL='printf "%s\n" "$WT" > "$PROBE/wt"
pwd -P > "$PROBE/pwd"
git -C "$WT" rev-parse HEAD > "$PROBE/head"
git -C "$PROBE_RIG" worktree list --porcelain | sed -n "s/^worktree //p" > "$PROBE/rig"
git -C "$PROBE_CWD" worktree list --porcelain | sed -n "s/^worktree //p" > "$PROBE/cwd"'
printf '[{"id":"tk-anc","title":"the change under review"}]\n' > "$TMP/anchor.json"

# gc names this checkout as the pack, so the block runs the review-workspace.sh and
# review-checks.sh under test. The rig's origin carries the reviewed commit as
# both main and polecat/x, which the block fetches before it makes the worktree.
review_case() { # <mode> [check] [guidance file]; sets RC, OID, D
  local d="$TMP/review-$1${2:+-$2}" rc=0
  mkdir -p "$d/probe" "$d/tmp"
  git init -q -b main "$d/rig"
  if [ -n "${3:-}" ]; then
    mkdir -p "$d/rig/docs"; printf 'GUIDANCE FOR TRIAGE: never add demo here\n' > "$d/rig/docs/$3"
    git -C "$d/rig" add "docs/$3"
  fi
  OID=$(commit "$d/rig" "reviewed head ($1)")
  git init -q --bare "$d/origin.git"
  git -C "$d/rig" push -q "$d/origin.git" "$OID:refs/heads/main" "$OID:refs/heads/polecat/x"
  git -C "$d/rig" remote add origin "$d/origin.git"
  # The cwd repo is a clone, so it holds the reviewed commit too: an add that
  # follows cwd succeeds there instead of failing for want of the commit.
  git clone -q "$d/rig" "$d/cwd"; commit "$d/cwd" "cwd repo moves on ($1)" >/dev/null
  pick "$1" "$d/rig"
  { review_render "$GATHER" "${2:-correctness}" "$OID"; printf '%s\n' "$PROBE_TAIL"; } > "$d/review-probe.sh"
  ( cd "$d/cwd" && TMPDIR="$d/tmp" STUB_PACK="$ROOT" GC_RIG_ROOT="$RR" GC_RIG="$GR" FAKE_META="$TMP/anchor.json" FAKE_LOG="$d/gc.log" \
      GCTK_BIN="$TMP/gctk" GCTK_LOG="$d/gctk.log" \
      PROBE="$d/probe" PROBE_RIG="$d/rig" PROBE_CWD="$d/cwd" bash "$d/review-probe.sh" ) >"$d/out" 2>&1 || rc=$?
  RC=$rc; D=$d
}

# review_remove: the verdict step's remove line, run from the same foreign cwd.
review_remove() {
  review_render "$(cat "$TMP/review-rm.tmpl")" correctness "$OID" > "$D/review-rm.sh"
  ( cd "$D/cwd" && TMPDIR="$D/tmp" STUB_PACK="$ROOT" \
      bash "$D/review-rm.sh" ) >>"$D/out" 2>&1 || true
}

for mode in env roster; do
  review_case "$mode"
  eq "$RC" 0 "review/$mode: the block runs from a foreign cwd"
  WT="$(cat "$D/probe/wt" 2>/dev/null || true)"
  eq "$(in_paths "$(cat "$D/probe/rig" 2>/dev/null || true)" "$WT")" yes "review/$mode: the worktree is registered in the RIG repo"
  eq "$(in_paths "$(cat "$D/probe/cwd" 2>/dev/null || true)" "$WT")" no  "review/$mode: the worktree is NOT registered in the cwd repo"
  eq "$(cat "$D/probe/head" 2>/dev/null || true)" "$OID" "review/$mode: the worktree is checked out at the reviewed OID"
  eq "$(cat "$D/probe/pwd" 2>/dev/null || true)" "${WT:-/nonexistent}" "review/$mode: the block leaves the shell in the review worktree"
  grep -qF "== The review's worktree: $WT" "$D/out" && ok "review/$mode: the block prints the worktree's path" \
    || bad "review/$mode: the block prints the worktree's path" "$(tr '\n' '|' < "$D/out")"
  grep -qF "the change under review" "$D/out" && ok "review/$mode: the block prints the anchor" \
    || bad "review/$mode: the block prints the anchor" "$(tr '\n' '|' < "$D/out")"
  grep -qxF "== What gctk rig recorded at $OID" "$D/out" && grep -qxF "test: fail, scope affected, exit 1, command: t" "$D/out" \
    && grep -qxF "lint: pass, exit 0, command: l" "$D/out" \
    && ok "review/$mode: the block prints what gctk rig recorded at the reviewed commit" \
    || bad "review/$mode: the block prints what gctk rig recorded at the reviewed commit" "$(tr '\n' '|' < "$D/out")"
  eq "$(cut -d'|' -f2 "$D/gctk.log" 2>/dev/null | sort -u)" "${WT:-/nonexistent}" "review/$mode: the records are read in the review's worktree"
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

# A rig's guidance for a check is the reviewed commit's docs/review-<check>.md,
# which the gather prints for that check's review alone.
review_case env triage review-triage.md
eq "$RC" 0 "review/guidance: a triage review's gather runs"
grep -qF "GUIDANCE FOR TRIAGE: never add demo here" "$D/out" && ok "review/guidance: the reviewed commit's docs/review-triage.md reaches the triage review" \
  || bad "review/guidance: the reviewed commit's docs/review-triage.md reaches the triage review" "$(tr '\n' '|' < "$D/out")"
review_case env correctness review-triage.md
grep -qF "GUIDANCE FOR TRIAGE" "$D/out" && bad "review/guidance: a correctness review at the same commit is not shown triage's guidance" \
  || ok "review/guidance: a correctness review at the same commit is not shown triage's guidance"

# load-dispatch's refusal: a review whose record lacks a value every review
# needs reviews nothing. The block names the missing key in the review's notes
# and exits non-zero, and nothing restores a route, because the next claim
# would meet the same gap. It runs as the pour renders it, from the parsed
# formula, with reviewed_oid given empty.
python3 - "$REVIEW_TOML" > "$TMP/refusal.tmpl" <<'PY'
import sys, tomllib, re
for step in tomllib.load(open(sys.argv[1], 'rb'))['steps']:
    if step['id'] == 'load-dispatch':
        print(re.findall(r'```bash\n(.*?)```', step['description'], re.S)[0], end='')
PY
case "$(cat "$TMP/refusal.tmpl")" in
  *'# >>> review-record-check'*) ok "refusal: load-dispatch's first block is the record check" ;;
  *) bad "refusal: load-dispatch's first block is the record check" "$(head -3 "$TMP/refusal.tmpl")" ;;
esac
D="$TMP/refusal"; mkdir -p "$D"
review_render "$(cat "$TMP/refusal.tmpl")" correctness "" > "$D/refusal.sh"
rc=0
( FAKE_LOG="$D/gc.log" bash "$D/refusal.sh" ) >"$D/out" 2>&1 || rc=$?
[ "$rc" -ne 0 ] && ok "refusal: an empty reviewed_oid reviews nothing (the block exits non-zero)" || bad "refusal: an empty reviewed_oid reviews nothing" "rc=$rc"
grep -qF "lacks reviewed_oid" "$D/out" && ok "refusal: it names the missing key" || bad "refusal: it names the missing key" "$(tr '\n' '|' < "$D/out")"
grep -q '^bd update rb --append-notes .*lacks reviewed_oid' "$D/gc.log" && ok "refusal: …in the review's notes" \
  || bad "refusal: …in the review's notes" "$(tr '\n' '|' < "$D/gc.log" 2>/dev/null)"
if grep -q 'gc.routed_to' "$D/gc.log"; then bad "refusal: it leaves the route empty" "$(grep 'gc.routed_to' "$D/gc.log")"
else ok "refusal: it leaves the route empty"; fi
review_render "$(cat "$TMP/refusal.tmpl")" correctness 0123456789abcdef0123456789abcdef01234567 > "$D/whole.sh"
rc=0
( FAKE_LOG="$D/gc-whole.log" bash "$D/whole.sh" ) >"$D/out-whole" 2>&1 || rc=$?
eq "$rc" 0 "refusal: a whole record passes the check"
if grep -q -- '--append-notes' "$D/gc-whole.log" 2>/dev/null; then bad "refusal: …writing nothing on the review"; else ok "refusal: …writing nothing on the review"; fi

# --- 4. mol-upstream-gc-sync: the read-only survey worktree. -------------------
echo "── mol-upstream-gc-sync: upstream-sync-worktree-add ──"
block "$SYNC_TOML" upstream-sync-worktree-add "$TMP/sync.sh"
eq "$(bare_git "$TMP/sync.sh")" "" "sync: every git call in the block names its repo with -C"

# GC_PACK_DIR names this checkout, so the block runs the rig-root.sh under test.
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
  ( cd "$d/cwd" && GC_PACK_DIR="$ROOT" GC_RIG_ROOT="$RR" GC_RIG="$GR" WORKTREE_PATH="$d/wt" bash "$TMP/sync.sh" ) >"$d/out" 2>&1 || rc=$?
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

# --- 5. mol-refinery-patrol: the prep worktree and the direct landing. ----------
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
# The pack, where the prep block finds detached-job.sh to stop a gate left
# running in the prep worktree and refinery-workspace.sh to stage it, and the
# direct-merge block finds direct-merge-push.sh, beside the bd-lib.sh it
# sources and a lifecycle.sh that logs. gc names it, so the cwd plays no part.
PACK="$TMP/pack"
mkdir -p "$PACK/assets/scripts"
cp "$HERE/detached-job.sh" "$HERE/refinery-workspace.sh" "$HERE/direct-merge-push.sh" "$HERE/bd-lib.sh" "$HERE/rig-root.sh" "$PACK/assets/scripts/"
cp "$BIN/lifecycle" "$PACK/assets/scripts/lifecycle.sh"
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
  ( cd "$d/cwd" && GC_RIG_ROOT="$RR" GC_RIG="$GR" STUB_PACK="$PACK" WORK=wb TARGET_BRANCH_DEFAULT=main \
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
# The block runs direct-merge-push.sh, which makes the landing's git calls.
eq "$(bare_git "$TMP/merge.sh")" "" "direct-merge: every git call in the block names its repo with -C"
eq "$(bare_git "$HERE/direct-merge-push.sh")" "" "direct-merge: every git call in direct-merge-push.sh names its repo with -C"

# bead_file <dir>: the work bead direct-merge-push.sh stamps before its push.
bead_file() { printf '%s\n' '[{"id":"wb","metadata":{"branch":"polecat/wb","target":"main"}}]' > "$1/meta.json"; }

merge_case() { # <mode>; sets RC, D (and patrol_rig's globals)
  local d="$TMP/merge-$1" rc=0
  mkdir -p "$d/tmp"
  patrol_rig "$d" "merge $1"
  bead_file "$d"
  # The rebase step leaves the prepared head staged here for wb, detached.
  "$PACK/assets/scripts/refinery-workspace.sh" stage --rig-root "$d/rig" --branch polecat/wb --work wb >/dev/null 2>&1
  pick "$1" "$d/rig"
  ( cd "$d/cwd" && TMPDIR="$d/tmp" GC_RIG_ROOT="$RR" GC_RIG="$GR" WORK=wb TARGET=main BRANCH=polecat/wb \
      STUB_PACK="$PACK" FAKE_META="$d/meta.json" FAKE_LOG="$d/gc.log" FAKE_LC_LOG="$d/lc.log" bash "$TMP/merge.sh" ) >"$d/out" 2>&1 || rc=$?
  RC=$rc; D=$d
}

for mode in env roster; do
  merge_case "$mode"
  eq "$RC" 0 "direct-merge/$mode: the block runs from a foreign cwd"
  eq "$(git -C "$D/origin.git" rev-parse main)" "$FEATURE" "direct-merge/$mode: the merge landed on the RIG's origin"
  eq "$(git -C "$D/foreign.git" rev-parse main)" "$FOREIGN" "direct-merge/$mode: the cwd repo's origin is untouched"
  eq "$(git -C "$D/rig" rev-parse origin/main)" "$FEATURE" "direct-merge/$mode: the push is verified against the rig's refreshed origin/main"
  eq "$(jq -r '.[0].metadata.direct_landing_sha // "none"' "$D/meta.json")" "$FEATURE" "direct-merge/$mode: the landing is stamped on the bead"
  case "$(cat "$D/lc.log" 2>/dev/null || true)" in
    "transition wb --to merged --close --set merged_sha=$FEATURE --set merged_target=main "*)
      ok "direct-merge/$mode: recorded and closed through one lifecycle transition" ;;
    *) bad "direct-merge/$mode: recorded and closed through one lifecycle transition" "$(cat "$D/lc.log" 2>/dev/null || true)" ;;
  esac
  # The transition checks the landing in the checkout GC_RIG_ROOT names, so it
  # gets the rig this block resolved, from the roster too.
  eq "$(cat "$D/lc.log.root" 2>/dev/null || true)" "$D/rig" "direct-merge/$mode: the transition runs with GC_RIG_ROOT naming the rig the block resolved"
  eq "$(git -C "$D/origin.git" rev-parse -q --verify refs/heads/polecat/wb || echo deleted)" deleted \
    "direct-merge/$mode: the merged branch is deleted from the rig's origin"
  eq "$(wt_paths "$D/rig" | count)" 2 "direct-merge/$mode: no worktree is added for the landing; the rig and its prep worktree remain"
  eq "$(wt_paths "$D/cwd" | count)" 1 "direct-merge/$mode: no worktree is left registered in the cwd repo"
  eq "$(ls -A "$D/tmp" | count)" 0 "direct-merge/$mode: nothing is left under TMPDIR"
done

merge_case nomatch
[ "$RC" -ne 0 ] && ok "direct-merge/nomatch: an unresolvable rig fails closed" || bad "direct-merge/nomatch: an unresolvable rig fails closed"
eq "$(git -C "$D/origin.git" rev-parse main)" "$BASE" "direct-merge/nomatch: nothing pushed to the rig's origin"
eq "$(git -C "$D/foreign.git" rev-parse main)" "$FOREIGN" "direct-merge/nomatch: nothing pushed to the cwd repo's origin"
[ ! -s "$D/lc.log" ] && ok "direct-merge/nomatch: no lifecycle transition" || bad "direct-merge/nomatch: no lifecycle transition"
grep -qxF 'runtime drain-ack' "$D/gc.log" 2>/dev/null \
  && ok "direct-merge/nomatch: the refinery drains, leaving the work to retry" \
  || bad "direct-merge/nomatch: the refinery drains, leaving the work to retry"
eq "$(ls -A "$D/tmp" | count)" 0 "direct-merge/nomatch: nothing is left under TMPDIR"

# protected_case <label> [<bash option>...]: the block against an origin that
# refuses the push for branch protection, followed by the strategy the mr path
# reads. Sets RC and D (and patrol_rig's globals).
{ cat "$TMP/merge.sh"; echo 'echo "MERGE_STRATEGY=${MERGE_STRATEGY:-unset}"'; } > "$TMP/merge-then.sh"
protected_case() {
  local d="$TMP/merge-protected-$1" rc=0
  shift
  mkdir -p "$d/tmp"
  patrol_rig "$d" "merge protected"
  bead_file "$d"
  "$PACK/assets/scripts/refinery-workspace.sh" stage --rig-root "$d/rig" --branch polecat/wb --work wb >/dev/null 2>&1
  printf '%s\n' '#!/usr/bin/env bash' 'echo "GH006: Protected branch update failed for refs/heads/main." >&2' 'exit 1' \
    > "$d/origin.git/hooks/pre-receive"
  chmod +x "$d/origin.git/hooks/pre-receive"
  pick env "$d/rig"
  ( cd "$d/cwd" && TMPDIR="$d/tmp" GC_RIG_ROOT="$RR" GC_RIG="$GR" WORK=wb TARGET=main BRANCH=polecat/wb \
      STUB_PACK="$PACK" FAKE_META="$d/meta.json" FAKE_LOG="$d/gc.log" FAKE_LC_LOG="$d/lc.log" bash "$@" "$TMP/merge-then.sh" ) >"$d/out" 2>&1 || rc=$?
  RC=$rc; D=$d
}

# The script's exit 3 sends the block on to the mr path, undrained, with errexit
# off as in an agent's Bash tool and on as in a shell that keeps it.
for errexit in off on; do
  if [ "$errexit" = on ]; then protected_case "$errexit" -eu; else protected_case "$errexit"; fi
  eq "$RC" 0 "direct-merge/protected, errexit $errexit: the block goes on past the promotion"
  eq "$(grep '^MERGE_STRATEGY=' "$D/out" || true)" "MERGE_STRATEGY=mr" "direct-merge/protected, errexit $errexit: the block takes the mr path"
  grep -qxF 'bd update wb --set-metadata merge_strategy=pr --unset-metadata direct_landing_sha' "$D/gc.log" 2>/dev/null \
    && ok "direct-merge/protected, errexit $errexit: the bead is promoted to merge_strategy=pr and its stamp cleared" \
    || bad "direct-merge/protected, errexit $errexit: the bead is promoted to merge_strategy=pr and its stamp cleared"
  grep -qxF 'runtime drain-ack' "$D/gc.log" 2>/dev/null \
    && bad "direct-merge/protected, errexit $errexit: the refinery does not drain" \
    || ok "direct-merge/protected, errexit $errexit: the refinery does not drain"
  eq "$(git -C "$D/origin.git" rev-parse main)" "$BASE" "direct-merge/protected, errexit $errexit: nothing landed on the rig's origin"
  git -C "$D/origin.git" rev-parse -q --verify refs/heads/polecat/wb >/dev/null \
    && ok "direct-merge/protected, errexit $errexit: the branch stays on origin for the PR" \
    || bad "direct-merge/protected, errexit $errexit: the branch stays on origin for the PR"
  [ ! -s "$D/lc.log" ] && ok "direct-merge/protected, errexit $errexit: no lifecycle transition" \
    || bad "direct-merge/protected, errexit $errexit: no lifecycle transition"
done

# moved_case <label> [<bash option>...]: the block against an origin/main that
# moved on after the branch was prepared, followed by the strategy the mr path
# reads. Sets RC, D and MOVED (and patrol_rig's globals).
moved_case() {
  local d="$TMP/merge-moved-$1" rc=0
  shift
  mkdir -p "$d/tmp"
  patrol_rig "$d" "merge moved"
  bead_file "$d"
  "$PACK/assets/scripts/refinery-workspace.sh" stage --rig-root "$d/rig" --branch polecat/wb --work wb >/dev/null 2>&1
  git -C "$d/seed" checkout -q main
  MOVED=$(commit "$d/seed" "landed while the gate ran")
  git -C "$d/seed" push -q "$d/origin.git" main
  pick env "$d/rig"
  ( cd "$d/cwd" && TMPDIR="$d/tmp" GC_RIG_ROOT="$RR" GC_RIG="$GR" WORK=wb TARGET=main BRANCH=polecat/wb \
      STUB_PACK="$PACK" FAKE_META="$d/meta.json" FAKE_LOG="$d/gc.log" FAKE_LC_LOG="$d/lc.log" bash "$@" "$TMP/merge-then.sh" ) >"$d/out" 2>&1 || rc=$?
  RC=$rc; D=$d
}

# The script's exit 4 ends the block undrained, and sends the cycle to
# next-iteration instead of either landing path.
for errexit in off on; do
  if [ "$errexit" = on ]; then moved_case "$errexit" -eu; else moved_case "$errexit"; fi
  eq "$RC" 4 "direct-merge/moved, errexit $errexit: the block exits 4"
  grep -qF 'jump to next-iteration' "$D/out" \
    && ok "direct-merge/moved, errexit $errexit: it says to jump to next-iteration" \
    || bad "direct-merge/moved, errexit $errexit: it says to jump to next-iteration" "$(cat "$D/out")"
  grep -q '^MERGE_STRATEGY=' "$D/out" \
    && bad "direct-merge/moved, errexit $errexit: the block goes on to neither landing path" \
    || ok "direct-merge/moved, errexit $errexit: the block goes on to neither landing path"
  grep -qxF 'runtime drain-ack' "$D/gc.log" 2>/dev/null \
    && bad "direct-merge/moved, errexit $errexit: the refinery does not drain" \
    || ok "direct-merge/moved, errexit $errexit: the refinery does not drain"
  eq "$(git -C "$D/origin.git" rev-parse main)" "$MOVED" "direct-merge/moved, errexit $errexit: origin/main is untouched"
  git -C "$D/origin.git" rev-parse -q --verify refs/heads/polecat/wb >/dev/null \
    && ok "direct-merge/moved, errexit $errexit: the branch stays on origin for the next patrol" \
    || bad "direct-merge/moved, errexit $errexit: the branch stays on origin for the next patrol"
  [ ! -s "$D/lc.log" ] && ok "direct-merge/moved, errexit $errexit: no lifecycle transition" \
    || bad "direct-merge/moved, errexit $errexit: no lifecycle transition"
done

# --- 6. mol-refinery-patrol resolves RIG_ROOT one way. -------------------------
# Every refinery block derives the prep worktree's path from RIG_ROOT, so two
# blocks that resolved it differently could stage and read different repos.
# Each resolves it through rig-root.sh: the locator line, the call, and the
# fail-closed guard, copied verbatim. The recorded-PR lookup sits indented in a
# case arm and its guard names the PR, so it is not one of these;
# find-work-gating-guard.test.sh runs it.
echo "── mol-refinery-patrol: one rig-root lookup ──"
LOOKUPS=$(awk '/^RR=/ { l = $0; getline a; getline b; print l " " a " " b }' "$PATROL_TOML")
N=$(printf '%s\n' "$LOOKUPS" | count)
[ "$N" -ge 2 ] && ok "patrol: $N RIG_ROOT resolutions found" || bad "patrol: RIG_ROOT resolutions found" "$N"
eq "$(printf '%s\n' "$LOOKUPS" | sort -u | count)" 1 "patrol: every RIG_ROOT resolution is the same lookup, copied verbatim"
case "$LOOKUPS" in
  *show-toplevel*) bad "patrol: no RIG_ROOT resolution falls back to cwd" ;;
  *)               ok  "patrol: no RIG_ROOT resolution falls back to cwd" ;;
esac
eq "$(printf '%s\n' "$LOOKUPS" | grep -cF 'RIG_ROOT=$("${RR:?rig-root.sh not found in the pack}") [ -n "$RIG_ROOT" ] || { echo "cannot resolve the rig root; leaving the work with the refinery to retry"; gc runtime drain-ack; exit 1; }' || true)" "$N" \
  "patrol: every RIG_ROOT resolution calls rig-root.sh and ends in the fail-closed guard"
eq "$(grep -c 'rig list --json[[:space:]]*|' "$PATROL_TOML" || true)" 0 "patrol: no block reads the roster for the rig's path itself"

echo "-----"
echo "formula-worktree-rig: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
