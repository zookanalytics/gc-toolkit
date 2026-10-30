#!/usr/bin/env bash
# Hermetic test for refinery-workspace.sh, and for the property it exists to
# hold: no block of mol-refinery-patrol, nor the refinery's own prompt, removes
# anything itself.
#
# The script runs against real git repositories (a bare origin, the rig cloned
# from it, and a foreign repository the caller's cwd sits in) with a stub gc
# answering the roster. Proves:
#   - stage adds the prep worktree to the RIG, detached at origin/<branch>,
#     whatever the cwd, creating no branch and leaving the rig's HEAD where it
#     was, replaces a leftover from an earlier iteration, a locked one
#     included, and fails over a directory git does not know as a worktree,
#     leaving it as it was;
#   - stage records which bead and branch it staged in a file in the prep
#     worktree's own git dir, which the worktree's status does not list and a
#     worktree added later at the path does not inherit, and fails when that
#     record does not land;
#   - held prints the bead and then the branch the record names, and fails,
#     printing nothing, for a worktree with no record and for no prep worktree;
#   - verify passes only for the bead, and the branch when given, that the
#     record names, and fails for another bead or branch, a worktree with no
#     record, a directory git does not know as a worktree, and no prep
#     worktree at all;
#   - teardown removes it, a locked one included, succeeds when there is none,
#     and says so when git leaves a directory behind;
#   - checks leaves the gate's checks directory empty, creating it when
#     absent, removes every entry the next gate could run, touches nothing else
#     in the gate's record, and fails when it cannot empty it;
#   - the rig root comes from --rig-root, else from the rig-root.sh beside the
#     script: GC_RIG_ROOT, then the roster;
#   - the patrol's formula and the refinery's prompt carry no removal, and the
#     patrol's blocks hand theirs to this script;
#   - each point a cycle ends carries the same teardown block, which finds
#     this script without the cwd, tears the prep worktree down, and when it
#     cannot, says so and carries on without draining;
#   - merge-push opens with one prep-staged-work block, ahead of its first read
#     of the bead, and no other line of the step sets WORK or BRANCH. The
#     block takes WORK and BRANCH from the record, whatever the shell carried,
#     and says so when the shell named another bead. With no record or no prep
#     worktree it tears down what is there and exits 4 without draining, and
#     with no script reachable it drains, both having done nothing else.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SUT="$HERE/refinery-workspace.sh"
PATROL_TOML="$ROOT/formulas/mol-refinery-patrol.toml"
REFINERY_PROMPT="$ROOT/agents/refinery/prompt.template.md"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-refinery-workspace-test.XXXXXX")"
TMP="$(cd "$TMP" && pwd -P)"
cleanup() {
  chmod -R u+w "$TMP" 2>/dev/null
  rm -rf "$TMP"
}
trap cleanup EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1${2:+ ($2)}"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3" "got '$1' want '$2'"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3" "missing '$2' in: $1" ;; esac; }

command -v git >/dev/null 2>&1 || { echo "git is required" >&2; exit 1; }
command -v jq  >/dev/null 2>&1 || { echo "jq is required"  >&2; exit 1; }
for f in "$SUT" "$PATROL_TOML" "$REFINERY_PROMPT"; do
  [ -s "$f" ] || { echo "missing $f" >&2; exit 1; }
done

unset GC_RIG_ROOT GC_RIG GC_CITY_PATH GC_PACK_DIR 2>/dev/null || true
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR 2>/dev/null || true
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

mkdir -p "$TMP/bin"
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GC_LOG"
case "$1 $2" in
  "rig list") cat "$FAKE_ROSTER" ;;
  # gc names the pack it loaded for the binding the city imports it under.
  "gc-toolkit scripts-dir") [ -n "${STUB_PACK:-}" ] || exit 1; printf '%s/assets/scripts\n' "$STUB_PACK" ;;
esac
exit 0
GC
chmod +x "$TMP/bin/gc"
export PATH="$TMP/bin:$PATH"
export GC_LOG="$TMP/gc.log"
: > "$GC_LOG"

commit() { git -C "$1" commit -q --allow-empty -m "$2"; git -C "$1" rev-parse HEAD; }
wt_paths() { git -C "$1" worktree list --porcelain | sed -n 's/^worktree //p'; }
registered() { if grep -qxF -- "$2" < <(wt_paths "$1"); then echo yes; else echo no; fi; }
# locked <repo> <path> -> yes|no: git lists the worktree at <path> as locked.
locked() {
  git -C "$1" worktree list --porcelain | awk -v p="$2" '
    /^worktree / { cur = substr($0, 10) }
    /^locked/ && cur == p { f = 1 }
    END { print (f ? "yes" : "no") }'
}

# The rig: origin carries main and polecat/wb, the rig is cloned from it, and
# a foreign repository is where every call's cwd sits.
D="$TMP/fixture"
git init -q --bare -b main "$D/origin.git"
git init -q -b main "$D/seed"
commit "$D/seed" "base" >/dev/null
git -C "$D/seed" push -q "$D/origin.git" main
git -C "$D/seed" checkout -q -b polecat/wb
FEATURE=$(commit "$D/seed" "feature")
git -C "$D/seed" push -q "$D/origin.git" polecat/wb
git clone -q "$D/origin.git" "$D/rig"
git init -q -b main "$D/cwd"; commit "$D/cwd" "foreign" >/dev/null
COMMON="$(git -C "$D/rig" rev-parse --path-format=absolute --git-common-dir)"
PREP="$COMMON/gc-refinery-prep"
GATE="$COMMON/gc-refinery-gate"
printf '{"rigs":[{"name":"myrig","path":"%s"}]}\n' "$D/rig" > "$TMP/roster.json"
export FAKE_ROSTER="$TMP/roster.json"

# ws <args>...: the script run from the foreign repository. Sets RC and OUT.
ws() { OUT=$(cd "$D/cwd" && "$SUT" "$@" 2>&1); RC=$?; }

echo "── stage ──"
RIG_HEAD=$(git -C "$D/rig" rev-parse HEAD)
ws stage --rig-root "$D/rig" --branch polecat/wb --work wb
eq "$RC" 0 "stage: exits 0"
eq "$(registered "$D/rig" "$PREP")" yes "stage: the prep worktree is registered in the RIG"
eq "$(wt_paths "$D/cwd" | wc -l | tr -d ' ')" 1 "stage: nothing is registered in the cwd's repository"
eq "$(git -C "$PREP" rev-parse HEAD 2>/dev/null)" "$FEATURE" "stage: the prep worktree is at origin/polecat/wb"
eq "$(git -C "$PREP" rev-parse --abbrev-ref HEAD 2>/dev/null)" HEAD "stage: the prep worktree is detached"
eq "$(git -C "$D/rig" rev-parse HEAD)" "$RIG_HEAD" "stage: the rig's HEAD does not move"
eq "$(git -C "$D/rig" for-each-ref --format='%(refname)' refs/heads/ | tr '\n' ' ')" "refs/heads/main " "stage: no branch is created"

echo "── stage over a leftover replaces it ──"
: > "$PREP/left-by-the-last-gate"
NEXT=$(commit "$D/seed" "feature follow-up")
git -C "$D/seed" push -q "$D/origin.git" polecat/wb
git -C "$D/rig" fetch -q origin
ws stage --rig-root "$D/rig" --branch polecat/wb --work wb
eq "$RC" 0 "leftover: exits 0"
eq "$(git -C "$PREP" rev-parse HEAD 2>/dev/null)" "$NEXT" "leftover: the prep worktree is at the branch's new tip"
[ ! -e "$PREP/left-by-the-last-gate" ] && ok "leftover: the old worktree's files are gone" || bad "leftover: the old worktree's files are gone"
eq "$(wt_paths "$D/rig" | wc -l | tr -d ' ')" 2 "leftover: one prep worktree is registered beside the rig"

echo "── stage of a branch origin does not carry fails ──"
ws stage --rig-root "$D/rig" --branch polecat/no-such --work wb
eq "$RC" 1 "missing branch: exits 1"
has "$OUT" "could not add the prep worktree" "missing branch: it says what failed"

echo "── teardown ──"
ws stage --rig-root "$D/rig" --branch polecat/wb --work wb >/dev/null
ws teardown --rig-root "$D/rig"
eq "$RC" 0 "teardown: exits 0"
[ ! -e "$PREP" ] && ok "teardown: the directory is gone" || bad "teardown: the directory is gone"
eq "$(registered "$D/rig" "$PREP")" no "teardown: the worktree is unregistered"
ws teardown --rig-root "$D/rig"
eq "$RC" 0 "teardown with nothing staged: exits 0"
mkdir -p "$PREP" && : > "$PREP/not-a-worktree"
ws teardown --rig-root "$D/rig"
eq "$RC" 1 "teardown of a directory git does not know: exits 1"
has "$OUT" "is still there" "teardown of a directory git does not know: it says so"
[ -e "$PREP/not-a-worktree" ] && ok "teardown removes only what git knows as the worktree" || bad "teardown removes only what git knows as the worktree"
ws stage --rig-root "$D/rig" --branch polecat/wb --work wb
eq "$RC" 1 "stage over a directory git does not know: exits 1"
has "$OUT" "could not add the prep worktree" "stage over a directory git does not know: it says what failed"
[ -e "$PREP/not-a-worktree" ] && ok "stage over a directory git does not know: the directory is left as it was" \
  || bad "stage over a directory git does not know: the directory is left as it was"
chmod -R u+w "$PREP"; ( cd "$TMP" && rm -rf -- "${PREP:?}" )

# A `worktree add` killed partway leaves its worktree locked "initializing", and
# git refuses a locked worktree a single --force. Each case locks the prep
# worktree the way such an add leaves it.
echo "── a locked leftover ──"
ws stage --rig-root "$D/rig" --branch polecat/wb --work wb >/dev/null
git -C "$D/rig" worktree lock --reason initializing "$PREP"
eq "$(locked "$D/rig" "$PREP")" yes "locked: precondition, git lists the prep worktree as locked"
ws teardown --rig-root "$D/rig"
eq "$RC" 0 "locked, teardown: exits 0"
[ ! -e "$PREP" ] && ok "locked, teardown: the directory is gone" || bad "locked, teardown: the directory is gone"
eq "$(registered "$D/rig" "$PREP")" no "locked, teardown: the worktree is unregistered"

ws stage --rig-root "$D/rig" --branch polecat/wb --work wb >/dev/null
: > "$PREP/left-by-a-killed-add"
git -C "$D/rig" worktree lock --reason initializing "$PREP"
ws stage --rig-root "$D/rig" --branch polecat/wb --work wb
eq "$RC" 0 "locked, stage: exits 0"
eq "$(git -C "$PREP" rev-parse HEAD 2>/dev/null)" "$NEXT" "locked, stage: the prep worktree is at the branch tip"
[ ! -e "$PREP/left-by-a-killed-add" ] && ok "locked, stage: the old worktree's files are gone" || bad "locked, stage: the old worktree's files are gone"
eq "$(locked "$D/rig" "$PREP")" no "locked, stage: the new prep worktree is not locked"

# The directory of a locked worktree moved away leaves git a locked registration
# for a path with nothing at it, which `worktree add -f` given once refuses.
git -C "$D/rig" worktree lock "$PREP"
mv "$PREP" "$TMP/moved-away"
ws teardown --rig-root "$D/rig"
eq "$RC" 0 "locked and moved away, teardown: exits 0"
eq "$(registered "$D/rig" "$PREP")" no "locked and moved away, teardown: the registration is cleared"
( cd "$TMP" && rm -rf -- moved-away )
ws stage --rig-root "$D/rig" --branch polecat/wb --work wb >/dev/null
git -C "$D/rig" worktree lock "$PREP"
mv "$PREP" "$TMP/moved-away"
ws stage --rig-root "$D/rig" --branch polecat/wb --work wa
eq "$RC" 0 "locked and moved away, stage: exits 0"
eq "$(git -C "$PREP" rev-parse HEAD 2>/dev/null)" "$NEXT" "locked and moved away, stage: the prep worktree is added again at the branch tip"
eq "$(locked "$D/rig" "$PREP")" no "locked and moved away, stage: the new prep worktree is not locked"
( cd "$TMP" && rm -rf -- moved-away )

# A locked worktree whose directory holds no .git file fails the removal's
# validation, so only the add given -f twice can take the path back.
git -C "$D/rig" worktree lock --reason initializing "$PREP"
( cd "$TMP" && rm -rf -- "${PREP:?}" ) && mkdir "$PREP"
ws teardown --rig-root "$D/rig"
eq "$RC" 1 "locked with no .git file, teardown: exits 1"
has "$OUT" "is still there" "locked with no .git file, teardown: it says the directory is still there"
ws stage --rig-root "$D/rig" --branch polecat/wb --work wb
eq "$RC" 0 "locked with no .git file, stage: exits 0"
eq "$(git -C "$PREP" rev-parse HEAD 2>/dev/null)" "$NEXT" "locked with no .git file, stage: the prep worktree is at the branch tip"
eq "$(locked "$D/rig" "$PREP")" no "locked with no .git file, stage: the new prep worktree is not locked"
# The leftover was staged for wa, so only the new record can name wb.
ws verify --rig-root "$D/rig" --work wb --branch polecat/wb
eq "$RC" 0 "locked with no .git file, stage: the worktree records the new staging"
ws verify --rig-root "$D/rig" --work wa
eq "$RC" 1 "locked with no .git file, stage: nothing of the leftover's record survives"
eq "$(wt_paths "$D/rig" | wc -l | tr -d ' ')" 2 "a locked leftover: one prep worktree is registered beside the rig"
ws teardown --rig-root "$D/rig" >/dev/null

echo "── stage records which bead and branch the prep worktree holds ──"
ws stage --rig-root "$D/rig" --branch polecat/wb --work wb >/dev/null
REC="$(git -C "$PREP" rev-parse --path-format=absolute --git-dir 2>/dev/null)/gc-refinery-staged"
case "$REC" in
  "$COMMON/worktrees/"*) ok "record: it is a file in the prep worktree's own git dir" ;;
  *) bad "record: it is a file in the prep worktree's own git dir" "$REC" ;;
esac
eq "$(git config --file "$REC" --get staged.work 2>/dev/null) $(git config --file "$REC" --get staged.branch 2>/dev/null)" \
  "wb polecat/wb" "record: it names the bead and the branch staged"
eq "$(git -C "$PREP" status --porcelain | wc -l | tr -d ' ')" 0 "record: the prep worktree's status lists nothing new"
ws verify --rig-root "$D/rig" --work wb --branch polecat/wb
eq "$RC/$OUT" "0/" "verify, the bead and branch staged: exits 0 and prints nothing"
ws verify --rig-root "$D/rig" --work wb
eq "$RC" 0 "verify, the bead staged with no branch given: exits 0"
OUT=$(cd "$D/cwd" && GC_RIG_ROOT="$D/rig" "$SUT" verify --work wb --branch polecat/wb 2>&1); RC=$?
eq "$RC" 0 "verify: GC_RIG_ROOT names the rig"
ws verify --rig-root "$D/rig" --work wa --branch polecat/wa
eq "$RC" 1 "verify, another bead and branch: exits 1"
has "$OUT" "holds polecat/wb for wb, not polecat/wa for wa" "verify, another bead and branch: it names what the worktree holds and what was asked"
ws verify --rig-root "$D/rig" --work wa --branch polecat/wb
eq "$RC" 1 "verify, another bead on the staged branch: exits 1"
ws verify --rig-root "$D/rig" --work wb --branch polecat/wa
eq "$RC" 1 "verify, the staged bead with another branch: exits 1"
ws verify --rig-root "$D/rig" --work wa
eq "$RC" 1 "verify, another bead with no branch given: exits 1"
# held_ws <args>...: held run from the foreign repository. Sets RC, HOUT (its
# stdout) and HERR (its stderr).
held_ws() { HOUT=$(cd "$D/cwd" && "$SUT" held "$@" 2>"$TMP/held.err"); RC=$?; HERR=$(cat "$TMP/held.err"); }
held_ws --rig-root "$D/rig"
eq "$RC" 0 "held: exits 0"
eq "$HOUT" "wb
polecat/wb" "held: prints the bead staged, then its branch, one per line"
eq "$HERR" "" "held: says nothing else"

ws stage --rig-root "$D/rig" --branch polecat/wb --work wa >/dev/null
ws verify --rig-root "$D/rig" --work wa --branch polecat/wb
eq "$RC" 0 "a stage for the next bead: verify passes for that bead"
ws verify --rig-root "$D/rig" --work wb --branch polecat/wb
eq "$RC" 1 "a stage for the next bead: verify refuses the bead staged before it"
held_ws --rig-root "$D/rig"
eq "$HOUT" "wa
polecat/wb" "a stage for the next bead: held prints that bead"

ws teardown --rig-root "$D/rig" >/dev/null
ws verify --rig-root "$D/rig" --work wa --branch polecat/wb
eq "$RC" 1 "verify with no prep worktree: exits 1"
has "$OUT" "no prep worktree is staged" "verify with no prep worktree: it says so"
held_ws --rig-root "$D/rig"
eq "$RC/$HOUT" "1/" "held with no prep worktree: exits 1 and prints nothing"
has "$HERR" "no prep worktree is staged" "held with no prep worktree: it says so"
# git removed the record with the worktree, so a worktree added at the same
# path by anything but stage holds none.
git -C "$D/rig" worktree add -q -f --detach "$PREP" origin/polecat/wb
ws verify --rig-root "$D/rig" --work wa --branch polecat/wb
eq "$RC" 1 "verify, a worktree added at the prep path after a teardown: exits 1"
has "$OUT" "records no bead and branch" "verify, a worktree added at the prep path after a teardown: it inherited no record"
held_ws --rig-root "$D/rig"
eq "$RC/$HOUT" "1/" "held, a worktree added at the prep path after a teardown: exits 1 and prints nothing"
has "$HERR" "records no bead and branch" "held, a worktree added at the prep path after a teardown: it inherited no record"
ws teardown --rig-root "$D/rig" >/dev/null
mkdir -p "$PREP" && : > "$PREP/not-a-worktree"
ws verify --rig-root "$D/rig" --work wb --branch polecat/wb
eq "$RC" 1 "verify, a directory git does not know as a worktree: exits 1"
has "$OUT" "no prep worktree is staged" "verify, a directory git does not know as a worktree: it reads no record from the rig's own git dir"
chmod -R u+w "$PREP"; ( cd "$TMP" && rm -rf -- "${PREP:?}" )

# A git that refuses every config write, so the add succeeds and the record
# does not land.
REAL_GIT=$(command -v git)
mkdir -p "$TMP/gitshim"
{ printf '#!/usr/bin/env bash\n'; printf 'REAL_GIT=%q\n' "$REAL_GIT"; cat; } > "$TMP/gitshim/git" <<'SHIM'
case " $* " in
  *" config --file "*" --get "*) ;;
  *" config --file "*) echo "error: could not lock config file" >&2; exit 255 ;;
esac
exec "$REAL_GIT" "$@"
SHIM
chmod +x "$TMP/gitshim/git"
OUT=$(cd "$D/cwd" && PATH="$TMP/gitshim:$PATH" "$SUT" stage --rig-root "$D/rig" --branch polecat/wb --work wb 2>&1); RC=$?
eq "$RC" 1 "a stage whose record does not land: exits 1"
has "$OUT" "could not record that it holds polecat/wb for wb" "a stage whose record does not land: it says so"
ws verify --rig-root "$D/rig" --work wb --branch polecat/wb
eq "$RC" 1 "a stage whose record does not land: verify refuses the worktree it added"
ws teardown --rig-root "$D/rig" >/dev/null

echo "── checks ──"
ws checks --rig-root "$D/rig"
eq "$RC" 0 "checks with none yet: exits 0"
[ -d "$GATE/checks" ] && ok "checks: the directory is created" || bad "checks: the directory is created"
mkdir -p "$GATE/checks/sub"
: > "$GATE/checks/01-lint"; : > "$GATE/checks/.hidden"; : > "$GATE/checks/not-numbered"
ln -s "$GATE/checks/01-lint" "$GATE/checks/02-link"
: > "$GATE/log"; : > "$GATE/gate.sh"; printf '4242\n' > "$GATE/pid"
ws checks --rig-root "$D/rig"
eq "$RC" 0 "checks over the last gate's checks: exits 0"
eq "$(ls -A "$GATE/checks" | wc -l | tr -d ' ')" 0 "checks: every entry is gone, dotfiles, links and directories included"
eq "$(ls -A "$GATE" | sort | tr '\n' ' ')" "checks gate.sh log pid " "checks: the rest of the gate's record is untouched"
mkdir -p "$GATE/checks/stuck" && : > "$GATE/checks/stuck/01-test" && chmod 555 "$GATE/checks/stuck"
ws checks --rig-root "$D/rig"
eq "$RC" 1 "checks it cannot empty: exits 1"
has "$OUT" "could not empty $GATE/checks" "checks it cannot empty: it says so"
chmod 755 "$GATE/checks/stuck"

echo "── the rig root ──"
ws checks
eq "$RC" 2 "no --rig-root, no GC_RIG_ROOT, no GC_RIG: exits 2"
has "$OUT" "cannot resolve the rig root" "it says why"
: > "$GATE/checks/01-env"
OUT=$(cd "$D/cwd" && GC_RIG_ROOT="$D/rig" "$SUT" checks 2>&1); RC=$?
eq "$RC/$(ls -A "$GATE/checks" | wc -l | tr -d ' ')" 0/0 "GC_RIG_ROOT names the rig"
: > "$GATE/checks/01-roster"
OUT=$(cd "$D/cwd" && GC_RIG=myrig "$SUT" checks 2>&1); RC=$?
eq "$RC/$(ls -A "$GATE/checks" | wc -l | tr -d ' ')" 0/0 "the roster names the rig for GC_RIG"
OUT=$(cd "$D/cwd" && GC_RIG=no-such-rig "$SUT" checks 2>&1); RC=$?
eq "$RC" 2 "a GC_RIG the roster does not carry: exits 2"
: > "$GATE/checks/01-flag"
OUT=$(cd "$D/cwd" && GC_RIG_ROOT="$D/cwd" "$SUT" checks --rig-root "$D/rig" 2>&1); RC=$?
eq "$RC/$(ls -A "$GATE/checks" | wc -l | tr -d ' ')" 0/0 "--rig-root wins over GC_RIG_ROOT"
[ ! -e "$(git -C "$D/cwd" rev-parse --path-format=absolute --git-common-dir)/gc-refinery-gate" ] \
  && ok "the repository GC_RIG_ROOT named is untouched" || bad "the repository GC_RIG_ROOT named is untouched"
mkdir -p "$TMP/not-a-repo"
ws checks --rig-root "$TMP/not-a-repo"
eq "$RC" 2 "a rig root that is no repository: exits 2"

echo "── usage ──"
for args in "" "nope" "stage --rig-root $D/rig" "stage --rig-root $D/rig --branch polecat/wb" "stage --rig-root $D/rig --work wb" \
  "held --rig-root $D/rig --work wb" "held --rig-root $D/rig --branch polecat/wb" "held --rig-root" \
  "verify --rig-root $D/rig" "verify --rig-root $D/rig --branch polecat/wb" "verify --work" \
  "teardown --rig-root $D/rig --branch polecat/wb" "teardown --rig-root $D/rig --work wb" "checks --work wb" "checks --frob" "checks --rig-root"; do
  # shellcheck disable=SC2086 # each case is a word list
  ( cd "$D/cwd" && "$SUT" $args ) >/dev/null 2>&1
  eq "$?" 2 "usage: '$args' exits 2"
done

# --- The patrol's own text removes nothing. -------------------------------------
# Every line counts, prose included: a command quoted in a step's prose is one
# an agent types. removals <file>... prints file:line for each removal shape.
echo "── the patrol's formula and the refinery's prompt carry no removal ──"
removals() {
  grep -nE '(^|[^[:alnum:]_./-])(rm|rmdir|unlink|shred)([[:space:]]|;|$)|worktree[[:space:]]+(remove|prune)|git[[:space:]]+clean([[:space:]]|$)|(^|[[:space:]])-delete([[:space:]]|$)' "$@"
}
cat > "$TMP/removal-shapes" <<'SAMPLE'
rm -rf "${GATE:?}/checks"
  merge_scratch_rm() { rm -f "$PUSH_ERR"; }
trap 'rm -rf "$TMP"' EXIT
find "$D" -name x -delete
rmdir "$D"
git -C "$R" worktree remove --force "$P"
git -C "$R" worktree prune
git clean -ffd
SAMPLE
cat > "$TMP/removal-free" <<'SAMPLE'
git push origin --delete "$BRANCH"
gc bd mol burn "$extra" --force
gc workflow delete-source $WORK --apply
the same trap: a stale ref reads as the remote one
refinery-workspace.sh teardown removes the prep worktree
SAMPLE
eq "$(removals "$TMP/removal-shapes" | wc -l | tr -d ' ')" 8 "detector: flags every removal shape in the sample"
eq "$(removals "$TMP/removal-free" | wc -l | tr -d ' ')" 0 "detector: passes a remote branch delete, a bead burn and prose"
eq "$(removals "$PATROL_TOML" "$REFINERY_PROMPT" || true)" "" "no line of the patrol's formula or the refinery's prompt removes anything"

# The removals the patrol needs are this script's, called from the blocks.
grep -qF '"$WS" stage --rig-root "$RIG_ROOT" --branch "$BRANCH" --work "$WORK"' "$PATROL_TOML" \
  && ok "the rebase block stages the prep worktree through refinery-workspace.sh, recording the bead it stages" \
  || bad "the rebase block stages the prep worktree through refinery-workspace.sh, recording the bead it stages"
grep -qF '"$WS" checks --rig-root "$RIG_ROOT"' "$PATROL_TOML" \
  && ok "the gate start empties its checks through refinery-workspace.sh" \
  || bad "the gate start empties its checks through refinery-workspace.sh"
eq "$(grep -cF 'refinery-workspace.sh teardown' "$PATROL_TOML")" 4 \
  "the rejection, failure and both merge-push paths tear down through refinery-workspace.sh"

# --- The teardown block. ---------------------------------------------------------
# A cycle ends in the rebase step's conflict arm, handle-failures' branch-caused
# arm, or one of merge-push's two paths, and each tears down through one block.
echo "── the teardown block ──"
eq "$(awk '/^id = "/ { id = $3; gsub(/"/, "", id) } /^# >>> prep-teardown$/ { printf "%s ", id }' "$PATROL_TOML")" \
  "rebase handle-failures merge-push merge-push " \
  "the rejection, failure and both merge-push paths carry the teardown block"
NBLOCKS=$(awk -v out="$TMP/teardown-" '
  /^# >>> prep-teardown$/ { n++; f=1; next }
  /^# <<< prep-teardown$/ { f=0; next }
  f { print > (out n ".sh") }
  END { print n + 0 }' "$PATROL_TOML")
eq "$NBLOCKS" 4 "four teardown blocks are extracted"
SAME=yes
for i in 2 3 4; do cmp -s "$TMP/teardown-1.sh" "$TMP/teardown-$i.sh" || SAME=no; done
eq "$SAME" yes "every teardown block is the same block"
# The pour renders {{binding_prefix}} as the binding plus a dot, gc-toolkit. here.
sed 's|{{binding_prefix}}|gc-toolkit.|g' "$TMP/teardown-1.sh" > "$TMP/teardown.sh"
TEARDOWN="$TMP/teardown.sh"
case "$(cat "$TEARDOWN")" in
  *\\*) bad "the teardown block is backslash-free (TOML would eat it)" ;;
  *)    ok  "the teardown block is backslash-free (TOML would eat it)" ;;
esac
bash -n "$TEARDOWN" && ok "the teardown block is valid bash" || bad "the teardown block is valid bash"

# The block runs from a cwd in another repository, with the script, and the
# rig-root.sh it resolves the rig through, in the pack gc names, and none in
# the rig. no-pack is a pack without them. Sets RC and OUT.
mkdir -p "$TMP/pack/assets/scripts" "$TMP/no-pack"
cp "$SUT" "$HERE/rig-root.sh" "$TMP/pack/assets/scripts/"
teardown_block() { OUT=$(cd "$D/cwd" && GC_RIG_ROOT="$D/rig" STUB_PACK="$1" bash "$TEARDOWN" 2>&1); RC=$?; }
: > "$GC_LOG"
ws stage --rig-root "$D/rig" --branch polecat/wb --work wb >/dev/null
teardown_block "$TMP/pack"
eq "$RC" 0 "teardown block: exits 0"
[ ! -e "$PREP" ] && ok "teardown block: the prep worktree is gone" || bad "teardown block: the prep worktree is gone"
eq "$(registered "$D/rig" "$PREP")" no "teardown block: the worktree is unregistered"
case "$OUT" in
  *"carry on"*) bad "teardown block: a teardown that completes says nothing of carrying on" "$OUT" ;;
  *)            ok  "teardown block: a teardown that completes says nothing of carrying on" ;;
esac
mkdir -p "$PREP" && : > "$PREP/not-a-worktree"
teardown_block "$TMP/pack"
eq "$RC" 0 "teardown block, the teardown fails: exits 0"
has "$OUT" "is still there" "teardown block, the teardown fails: the script's reason is shown"
has "$OUT" "carry on" "teardown block, the teardown fails: it says to carry on"
[ -e "$PREP/not-a-worktree" ] && ok "teardown block, the teardown fails: the leftover is left for the next stage" \
  || bad "teardown block, the teardown fails: the leftover is left for the next stage"
chmod -R u+w "$PREP"; ( cd "$TMP" && rm -rf -- "${PREP:?}" )
ws stage --rig-root "$D/rig" --branch polecat/wb --work wb >/dev/null
teardown_block "$TMP/no-pack"
eq "$RC" 0 "teardown block, no script reachable: exits 0"
has "$OUT" "carry on" "teardown block, no script reachable: it says to carry on"
eq "$(registered "$D/rig" "$PREP")" yes "teardown block, no script reachable: the prep worktree is left for the next stage"
ws teardown --rig-root "$D/rig" >/dev/null
eq "$(grep -c 'drain-ack' "$GC_LOG")" 0 "teardown block: no run drains the session"

# --- The prep-staged-work block. ---------------------------------------------------
# merge-push takes the bead and branch it acts for from the record, once, at its
# start, so every later block of the step pushes, lands and records for the
# bead whose head the prep worktree holds, whatever the agent's shell carried.
echo "── the prep-staged-work block ──"
eq "$(awk '/^id = "/ { id = $3; gsub(/"/, "", id) } /^# >>> prep-staged-work$/ { printf "%s ", id }' "$PATROL_TOML")" \
  "merge-push " \
  "only merge-push carries the prep-staged-work block, once"
awk '/^id = "merge-push"$/ {f=1} f && /^\[\[steps\]\]$/ {f=0} f' "$PATROL_TOML" > "$TMP/merge-push-step.txt"
STAGED_AT=$(grep -n '^# >>> prep-staged-work$' "$TMP/merge-push-step.txt" | head -1 | cut -d: -f1)
SHOW_AT=$(grep -n 'gc bd show \$WORK' "$TMP/merge-push-step.txt" | head -1 | cut -d: -f1)
if [ -n "$STAGED_AT" ] && [ -n "$SHOW_AT" ] && [ "$STAGED_AT" -lt "$SHOW_AT" ]; then
  ok "merge-push takes WORK from the record before it first reads the bead"
else
  bad "merge-push takes WORK from the record before it first reads the bead" "block at ${STAGED_AT:-none}, first read at ${SHOW_AT:-none}"
fi
eq "$(awk '/^# >>> prep-staged-work$/ {f=1} /^# <<< prep-staged-work$/ {f=0; next} !f' "$TMP/merge-push-step.txt" \
      | grep -cE '(^|[^[:alnum:]_])(WORK|BRANCH)=|read -r (WORK|BRANCH)' || true)" 0 \
  "no other line of merge-push sets WORK or BRANCH"
awk '/^# >>> prep-staged-work$/ {f=1; next} /^# <<< prep-staged-work$/ {f=0; next} f' "$PATROL_TOML" \
  | sed 's|{{binding_prefix}}|gc-toolkit.|g' > "$TMP/staged.sh"
grep -qF '"$WS" held --rig-root "$RIG_ROOT"' "$TMP/staged.sh" \
  && ok "the block hands the script the rig root it resolved" \
  || bad "the block hands the script the rig root it resolved"
case "$(cat "$TMP/staged.sh")" in
  *\\*) bad "the prep-staged-work block is backslash-free (TOML would eat it)" ;;
  *)    ok  "the prep-staged-work block is backslash-free (TOML would eat it)" ;;
esac
bash -n "$TMP/staged.sh" && ok "the prep-staged-work block is valid bash" || bad "the prep-staged-work block is valid bash"

# The block runs from a cwd in another repository. What follows it in the step
# is stood for by one line that shows the bead and branch it hands on.
{ cat "$TMP/staged.sh"; echo 'echo "ACTS FOR $WORK ON $BRANCH"'; } > "$TMP/staged-run.sh"
# staged_block <pack> [<work> <branch>]: the block with the script in the pack
# gc names, GC_RIG_ROOT naming the rig, and the shell's WORK and BRANCH when
# given. Sets RC and OUT.
staged_block() {
  local pack="$1"; shift
  : > "$GC_LOG"
  if [ "$#" -eq 2 ]; then
    OUT=$(cd "$D/cwd" && GC_RIG_ROOT="$D/rig" STUB_PACK="$pack" WORK="$1" BRANCH="$2" bash "$TMP/staged-run.sh" 2>&1); RC=$?
  else
    OUT=$(cd "$D/cwd" && env -u WORK -u BRANCH GC_RIG_ROOT="$D/rig" STUB_PACK="$pack" bash "$TMP/staged-run.sh" 2>&1); RC=$?
  fi
}
drains() { grep -c 'drain-ack' "$GC_LOG"; }
went_on() { case "$OUT" in *"ACTS FOR"*) echo yes ;; *) echo no ;; esac; }
# The block resolves the rig through rig-root.sh before it looks for the
# script, so a pack that holds rig-root.sh alone is one where the script is not
# reachable.
RR_PACK="$TMP/rig-root-pack"
mkdir -p "$RR_PACK/assets/scripts"
cp "$HERE/rig-root.sh" "$RR_PACK/assets/scripts/"

ws stage --rig-root "$D/rig" --branch polecat/wb --work wb >/dev/null
staged_block "$TMP/pack" wa polecat/wa
eq "$RC" 0 "prep-staged-work, another bead's WORK and BRANCH in the shell: exits 0"
has "$OUT" "ACTS FOR wb ON polecat/wb" "prep-staged-work, another bead's WORK and BRANCH in the shell: the step acts for the bead staged, on its branch"
has "$OUT" "WORK was wa, but the prep worktree holds polecat/wb for wb, so this step acts for wb" \
  "prep-staged-work, another bead's WORK and BRANCH in the shell: it says which bead it acts for"
eq "$(drains)" 0 "prep-staged-work, another bead's WORK and BRANCH in the shell: the session does not drain"
staged_block "$TMP/pack" wb polecat/wa
has "$OUT" "ACTS FOR wb ON polecat/wb" "prep-staged-work, the staged bead with another bead's BRANCH: the step acts on the staged branch"
case "$OUT" in *"WORK was"*) bad "prep-staged-work, the staged bead's own WORK: no notice" ;; *) ok "prep-staged-work, the staged bead's own WORK: no notice" ;; esac
staged_block "$TMP/pack"
eq "$RC" 0 "prep-staged-work, nothing in the shell: exits 0"
has "$OUT" "ACTS FOR wb ON polecat/wb" "prep-staged-work, nothing in the shell: the step acts for the bead staged"
case "$OUT" in *"WORK was"*) bad "prep-staged-work, nothing in the shell: no notice" ;; *) ok "prep-staged-work, nothing in the shell: no notice" ;; esac

# GC_RIG_ROOT unset, so the rig comes from the roster, and the script is the
# pack's, which gc names.
: > "$GC_LOG"
OUT=$(cd "$D/cwd" && env -u GC_RIG_ROOT GC_RIG=myrig STUB_PACK="$TMP/pack" WORK=wa BRANCH=polecat/wa bash "$TMP/staged-run.sh" 2>&1); RC=$?
eq "$RC" 0 "prep-staged-work, the rig from the roster: exits 0"
has "$OUT" "ACTS FOR wb ON polecat/wb" "prep-staged-work, the rig from the roster: the block acts for the bead staged in the rig it resolved"
eq "$(grep -c '^rig list' "$GC_LOG")" 1 "prep-staged-work, the rig from the roster: the roster is read once, by the rig-root.sh the block runs, not again by the script"

# A worktree at the prep path with no record, such as one any other path added.
ws teardown --rig-root "$D/rig" >/dev/null
git -C "$D/rig" worktree add -q -f --detach "$PREP" origin/polecat/wb
staged_block "$TMP/pack" wb polecat/wb
eq "$RC" 4 "prep-staged-work, a prep worktree with no record: exits 4"
eq "$(went_on)" no "prep-staged-work, a prep worktree with no record: nothing after the block runs"
has "$OUT" "nothing shows which bead the prep worktree holds" "prep-staged-work, a prep worktree with no record: it says why"
has "$OUT" "jump to next-iteration" "prep-staged-work, a prep worktree with no record: it sends the cycle to next-iteration"
eq "$(registered "$D/rig" "$PREP")" no "prep-staged-work, a prep worktree with no record: the block tears it down"
eq "$(drains)" 0 "prep-staged-work, a prep worktree with no record: the session does not drain"
staged_block "$TMP/pack" wb polecat/wb
eq "$RC" 4 "prep-staged-work, no prep worktree: exits 4"
eq "$(went_on)" no "prep-staged-work, no prep worktree: nothing after the block runs"
eq "$(drains)" 0 "prep-staged-work, no prep worktree: the session does not drain"
ws stage --rig-root "$D/rig" --branch polecat/wb --work wb >/dev/null
staged_block "$RR_PACK" wb polecat/wb
eq "$RC" 1 "prep-staged-work, no script reachable: exits 1"
eq "$(went_on)" no "prep-staged-work, no script reachable: nothing after the block runs"
has "$OUT" "refinery-workspace.sh not found" "prep-staged-work, no script reachable: it says why"
eq "$(drains)" 1 "prep-staged-work, no script reachable: the session drains, leaving the work to retry"
eq "$(registered "$D/rig" "$PREP")" yes "prep-staged-work, no script reachable: the prep worktree is left for the next stage"
ws teardown --rig-root "$D/rig" >/dev/null

echo "-----"
echo "refinery-workspace: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
