#!/usr/bin/env bash
# Hermetic test for script-callers.sh, the open steps that call a pack script
# and the merge gate's question about a change that removes one. Proves:
#   - a census reads every store the city's rig list names, each pinned by
#     --db, for beads carrying gc.step_ref in every status but closed, and
#     lists a step only when its text names the script whole: no letter,
#     digit, dot, dash or underscore on either side;
#   - --check-merge takes the files the change removes from assets/scripts/,
#     a rename's old path included, that the base still carries, and leaves
#     tests out;
#   - a removed script that a formula at the base or at the head still names,
#     a sub-pack's formula included, exits 1 before any store is read, since
#     no wait clears it;
#   - a removed script that only open steps call exits 3, and one nothing
#     calls exits 0;
#   - it exits 2 when it decides nothing: a usage error, a revision or
#     repository it cannot read, no rig list, or a store that does not answer.
# Runs against a fake gc that serves the rig list and each store's steps from
# JSON files, with real git. No live city.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/script-callers.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-script-callers-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"   # assertions only; harness_init would stub git out
PASS=0; FAIL=0

unset "${!GC_@}" "${!BEADS_@}" "${!GIT_@}" 2>/dev/null || true
export GIT_CONFIG_GLOBAL="$TMP/gitconfig" GIT_CONFIG_NOSYSTEM=1
: > "$GIT_CONFIG_GLOBAL"
git config --file "$GIT_CONFIG_GLOBAL" user.name T
git config --file "$GIT_CONFIG_GLOBAL" user.email t@e.com
git config --file "$GIT_CONFIG_GLOBAL" init.defaultBranch main
git config --file "$GIT_CONFIG_GLOBAL" commit.gpgsign false

BIN="$TMP/bin"; mkdir -p "$BIN"
export PATH="$BIN:$PATH"
export STUB_RIGS="$TMP/rigs.json" STUB_GC_LOG="$TMP/gc.log"
STORES="$TMP/stores"
REPO="$TMP/repo"

# --- fake gc: the rig list, and each store's steps --------------------------
# bd list honours the filters a census asks for, so a step the script lists
# had to pass them; --desc-contains is a substring match, as bd's is, so the
# whole-name rule is the script's own.
cat > "$BIN/gc" <<'STUB'
#!/usr/bin/env bash
set -u
printf '%s\n' "$*" >> "${STUB_GC_LOG:?}"
if [ "${1:-}" = rig ] && [ "${2:-}" = list ]; then
  [ "${STUB_RIGS_RC:-0}" = 0 ] || { echo "the store did not answer" >&2; exit "$STUB_RIGS_RC"; }
  cat "${STUB_RIGS:?}"; exit 0
fi
if [ "${1:-}" = bd ] && [ "${2:-}" = list ]; then
  shift 2
  db=""; contains=""; statuses=""; key=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --db) db="$2"; shift 2 ;;
      --desc-contains) contains="$2"; shift 2 ;;
      --status) statuses="$2"; shift 2 ;;
      --has-metadata-key) key="$2"; shift 2 ;;
      *) shift ;;
    esac
  done
  [ "$db" != "${STUB_BD_FAIL_DB:-}" ] || { echo "Error: database unavailable" >&2; exit 1; }
  [ -f "$db/steps.json" ] || { echo "Error: no database at $db" >&2; exit 1; }
  echo "gc bd: answering from the rig \"workshop\" store"
  jq -c --arg c "$contains" --arg s "$statuses" --arg k "$key" '[.[]
    | select((.description // "") | contains($c))
    | select(.status as $st | ($s | split(",")) | index($st))
    | select($k == "" or (.metadata | has($k)))]' "$db/steps.json"
  exit 0
fi
echo "fake gc: unexpected call: $*" >&2
exit 1
STUB
chmod +x "$BIN/gc"

# The city: an HQ and two rigs, each with a store of its own.
cat > "$STUB_RIGS" <<JSON
{"rigs":[
  {"name":"harbor","path":"$STORES/harbor","prefix":"hb","hq":true},
  {"name":"workshop","path":"$STORES/workshop","prefix":"ws"},
  {"name":"lantern","path":"$STORES/lantern","prefix":"ln"}
]}
JSON
mkdir -p "$STORES/harbor/.beads" "$STORES/workshop/.beads" "$STORES/lantern/.beads"
step() { # id step_ref status assignee root description
  jq -nc --arg id "$1" --arg ref "$2" --arg st "$3" --arg as "$4" --arg root "$5" --arg d "$6" \
    '{id: $id, status: $st, assignee: $as, description: $d, metadata: {"gc.step_ref": $ref, "gc.root_bead_id": $root}}'
}
callers_on() {
  printf '[]' > "$STORES/harbor/.beads/steps.json"
  printf '[%s,%s,%s,%s,%s]' \
    "$(step ws-s1 mol-a.load open "" ws-r1 "$(printf 'Run:\n"$SCRIPTS/old-tool.sh" --flag')")" \
    "$(step ws-s2 mol-a.submit in_progress worker-1 ws-r1 'x=$(gc kit scripts-dir)/old-tool.sh')" \
    "$(step ws-s3 mol-a.done closed "" ws-r0 '"$SCRIPTS/old-tool.sh"')" \
    '{"id":"ws-n1","status":"open","assignee":"","description":"old-tool.sh is named here","metadata":{}}' \
    "$(step ws-s4 mol-a.load open "" ws-r2 'bold-tool.sh, old-tool.sh.bak and old-tool.shx')" \
    > "$STORES/workshop/.beads/steps.json"
  printf '[%s]' "$(step ln-s1 mol-b.check blocked "" ln-r1 "$(printf 'first\nold-tool.sh runs here')")" \
    > "$STORES/lantern/.beads/steps.json"
}
callers_off() {
  local s
  for s in harbor workshop lantern; do printf '[]' > "$STORES/$s/.beads/steps.json"; done
}
run() { out=$("$SUT" "$@" 2>&1); rc=$?; }

echo "# census"
callers_on; : > "$STUB_GC_LOG"
run old-tool.sh
eq "$rc" "3" "open steps that call the script exit 3"
has "$out" "old-tool.sh: step ws-s1 (mol-a.load, open, unassigned) in run ws-r1, store of rig workshop" \
  "a step that calls it through \$SCRIPTS is listed with its step ref, status, run and store"
has "$out" "old-tool.sh: step ws-s2 (mol-a.submit, in_progress, worker-1) in run ws-r1, store of rig workshop" \
  "...one that calls it through scripts-dir, with its assignee"
has "$out" "old-tool.sh: step ln-s1 (mol-b.check, blocked, unassigned) in run ln-r1, store of rig lantern" \
  "...and a blocked step in another rig's store, its name at the start of a line"
hasnt "$out" "ws-s3" "a closed step is not a caller"
hasnt "$out" "ws-n1" "a bead with no gc.step_ref is not a caller"
hasnt "$out" "ws-s4" "a longer name that holds the script's name is not the script"
eq "$(printf '%s\n' "$out" | head -1)" "3 open step(s) call old-tool.sh" "...the count first, so a log that keeps only the head keeps it"
log=$(cat "$STUB_GC_LOG")
has "$log" "bd list --db $STORES/harbor/.beads --has-metadata-key gc.step_ref --status open,in_progress,blocked,deferred,hooked,pinned --desc-contains old-tool.sh --limit=0 --json" \
  "each store is read pinned by --db, for steps in every status but closed"
has "$log" "bd list --db $STORES/lantern/.beads" "...the last rig's store included"

callers_off
run old-tool.sh keep.sh
eq "$rc" "0" "no caller exits 0"
has "$out" "no open step calls old-tool.sh keep.sh" "...and says which scripts it asked about"

callers_on
export STUB_BD_FAIL_DB="$STORES/lantern/.beads"
run old-tool.sh
eq "$rc" "2" "a store that does not answer decides nothing"
has "$out" "cannot read the open steps in the store of rig 'lantern' ($STORES/lantern/.beads); nothing was decided" \
  "...and names the store"
unset STUB_BD_FAIL_DB

export STUB_RIGS_RC=1
run old-tool.sh
eq "$rc" "2" "an unreadable rig list decides nothing"
has "$out" "cannot read the city's rigs" "...and says so"
unset STUB_RIGS_RC
cp "$STUB_RIGS" "$TMP/rigs.keep"; printf '{"rigs":[]}' > "$STUB_RIGS"
run old-tool.sh
eq "$rc" "2" "a city that lists no rig decides nothing, since no store was read"
cp "$TMP/rigs.keep" "$STUB_RIGS"

echo "# usage"
run; eq "$rc" "2" "no script and no --check-merge is a usage error"
run assets/scripts/old-tool.sh; eq "$rc" "2" "a path is not a script's file name"
run --frobnicate; eq "$rc" "2" "an unknown option is a usage error"
run --check-merge main; eq "$rc" "2" "--check-merge needs two revisions"
run --check-merge main main old-tool.sh; eq "$rc" "2" "--check-merge takes no script names"

echo "# --check-merge"
G() { git -C "$REPO" "$@" >/dev/null 2>&1 || { echo "setup failed: git $*" >&2; exit 1; }; }
put() { mkdir -p "$(dirname "$REPO/$1")"; printf '%s\n' "$2" > "$REPO/$1"; }
git init -q "$REPO"
put assets/scripts/old-tool.sh '#!/bin/sh'
put assets/scripts/keep.sh '#!/bin/sh'
put assets/scripts/old-tool.test.sh '#!/bin/sh'
put formulas/mol-a.toml 'run = "$SCRIPTS/keep.sh"'
put formulas/mol-b.toml 'run = "$SCRIPTS/old-tool.sh"'
put docs/notes.md 'old-tool.sh is documented here'
G add -A; G commit -q -m c0
# One change stops naming the script and removes it.
G checkout -q -b same-change
G rm -q assets/scripts/old-tool.sh
put formulas/mol-b.toml 'run = "$SCRIPTS/keep.sh"'
G commit -qam same-change
# main stops naming it first; its text still holds a longer name.
G checkout -q main
put formulas/mol-b.toml 'run = "$SCRIPTS/keep.sh"  # not bold-tool.sh'
G commit -qam stop-naming
G checkout -q -b delete; G rm -q assets/scripts/old-tool.sh; G commit -qm delete
G checkout -q main; G checkout -q -b head-names
G rm -q assets/scripts/old-tool.sh
put formulas/mol-c.toml 'run = "$SCRIPTS/old-tool.sh"'
G add -A; G commit -qm head-names
G checkout -q main; G checkout -q -b tests-only; G rm -q assets/scripts/old-tool.test.sh; G commit -qm tests-only
G checkout -q main; G checkout -q -b rename; G mv assets/scripts/old-tool.sh assets/scripts/new-tool.sh; G commit -qm rename
G checkout -q main; G checkout -q -b edit-only; put assets/scripts/keep.sh '#!/bin/sh
true'; G commit -qam edit-only
G checkout -q main; G checkout -q -b drop-keep; G rm -q assets/scripts/keep.sh; G commit -qm drop-keep
G checkout -q main; G checkout -q -b subpack
put packs/sub/formulas/mol-s.toml 'run = "$SCRIPTS/old-tool.sh"'
G add -A; G commit -qm subpack
G checkout -q -b subpack-delete; G rm -q assets/scripts/old-tool.sh; G commit -qm subpack-delete
G checkout -q main; G checkout -q -b main-dropped; G rm -q assets/scripts/keep.sh; G commit -qm main-dropped
G checkout -q main

callers_on; : > "$STUB_GC_LOG"
run --root "$REPO" --check-merge main edit-only
eq "$rc" "0" "a change that removes no script passes"
has "$out" "the merge removes no pack script" "...and says so"
eq "$(wc -c < "$STUB_GC_LOG" | tr -d ' ')" "0" "...without reading a store"

run --root "$REPO" --check-merge main tests-only
eq "$rc" "0" "removing a test is not removing a script"
has "$out" "the merge removes no pack script" "...so nothing is asked about it"

run --root "$REPO" --check-merge main-dropped drop-keep
eq "$rc" "0" "a script the base no longer carries is not the change's to remove"

: > "$STUB_GC_LOG"
run --root "$REPO" --check-merge main~1 same-change
eq "$rc" "1" "removing a script a formula at the base still names exits 1"
has "$out" "assets/scripts/old-tool.sh: the merge removes it, and formulas/mol-b.toml at the base (main~1) still names it" \
  "...naming the formula and the side"
has "$(printf '%s\n' "$out" | head -1)" "1 formula file(s) name a script the merge removes." "...under a headline with the count"
has "$(printf '%s\n' "$out" | head -1)" "Keep a file at each such path, a hand-off to what replaces it" "...and the remedy"
hasnt "$out" "docs/notes.md" "a document that names it is not a formula"
eq "$(wc -c < "$STUB_GC_LOG" | tr -d ' ')" "0" "...decided before any store is read, since no wait clears it"

run --root "$REPO" --check-merge main head-names
eq "$rc" "1" "removing a script a formula at the head names exits 1"
has "$out" "assets/scripts/old-tool.sh: the merge removes it, and formulas/mol-c.toml at the head (head-names) still names it" \
  "...naming the head's formula"

run --root "$REPO" --check-merge subpack subpack-delete
eq "$rc" "1" "a sub-pack's formula counts"
has "$out" "packs/sub/formulas/mol-s.toml at the base (subpack) still names it" "...and is named"

: > "$STUB_GC_LOG"
run --root "$REPO" --check-merge main delete
eq "$rc" "3" "removing a script only open steps call exits 3"
has "$out" "old-tool.sh: step ws-s1 (mol-a.load, open, unassigned) in run ws-r1, store of rig workshop" "...listing each caller"
has "$(printf '%s\n' "$out" | head -1)" "3 open step(s) call a script the merge removes (assets/scripts/old-tool.sh)" "...under a headline with the count"
has "$(cat "$STUB_GC_LOG")" "--desc-contains old-tool.sh" "...asking the stores by the script's file name"

run --root "$REPO" --check-merge main rename
eq "$rc" "3" "a rename removes the old path"
has "$out" "(assets/scripts/old-tool.sh)" "...which is the path the callers lose"

callers_off
run --root "$REPO" --check-merge main delete
eq "$rc" "0" "a removed script nothing calls or names passes"
has "$out" "the merge removes assets/scripts/old-tool.sh; no formula names them and no open step calls them" "...and says what it removes"

callers_on; export STUB_BD_FAIL_DB="$STORES/harbor/.beads"
run --root "$REPO" --check-merge main delete
eq "$rc" "2" "a store that does not answer holds the decision"
unset STUB_BD_FAIL_DB

run --root "$REPO" --check-merge main no-such-branch
eq "$rc" "2" "a revision the repository lacks decides nothing"
has "$out" "'no-such-branch' names no commit" "...and says which"
run --root "$TMP/not-a-repo" --check-merge main delete
eq "$rc" "2" "a directory that is not a repository decides nothing"

echo "---"
echo "script-callers.test: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
