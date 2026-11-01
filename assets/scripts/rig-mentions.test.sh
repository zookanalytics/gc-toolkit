#!/usr/bin/env bash
# Hermetic test for rig-mentions.sh, the list of places a change names another
# rig of the city. Proves:
#   - the other rigs are the city's (`gc rig list`), less the rig the change is
#     for and the rigs the pack runs on or with (the platform, the pack, the
#     demo engine), and that rig is the one whose checkout holds the
#     repository, a worktree's included, else --rig, else $GC_RIG;
#   - a rig's name matches whole, case aside, with its separators written any
#     way; a bead id is the rig's prefix, a dash and two more letters or digits,
#     reported whole; a path is the rig's path as the city lists it;
#   - --branch reads the lines the branch adds, not the ones it removes or
#     keeps, and the messages of the commits no remote has yet;
#   - --bead reads the title, summary and dispatch text the pull request
#     publishes, which for a rework child are its anchor's;
#   - --file reads a whole file, a process substitution included, and --tree
#     every tracked text file, generated ones included, each symlink and binary
#     file left out;
#   - --rig-map takes the rig map from the caller and reads no listing;
#   - it exits 0 with nothing named, 1 with each mention and the advice, and 2
#     when it could check nothing: no rig list, an unknown rig, no rig to judge
#     for, a bead, file or base it cannot read, or a usage error.
# Runs against a fake gc that serves the rig list and bead reads from JSON
# files, with real git. No live city.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/rig-mentions.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-rig-mentions-test.XXXXXX")"
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
export STUB_RIGS="$TMP/rigs.json" STUB_LEDGER="$TMP/ledger.json"
REPO="$TMP/workshop"
ELSE="$TMP/elsewhere"

# --- fake gc: the rig roster and bead reads ---------------------------------
cat > "$BIN/gc" <<'STUB'
#!/usr/bin/env bash
set -u
if [ "${1:-}" = rig ] && [ "${2:-}" = list ]; then
  [ "${STUB_RIGS_RC:-0}" = 0 ] || { echo "the store did not answer" >&2; exit "$STUB_RIGS_RC"; }
  cat "${STUB_RIGS:?}"; exit 0
fi
if [ "${1:-}" = bd ] && [ "${2:-}" = show ]; then
  out=$(jq -c --arg id "${3:-}" '[.[] | select(.id == $id)]' "${STUB_LEDGER:?}")
  if [ "$out" = "[]" ]; then
    printf '{"error":"no issues found matching the provided IDs","schema_version":1}\n'; exit 1
  fi
  echo "gc bd: answering from the rig \"workshop\" store"
  printf '%s\n' "$out"; exit 0
fi
echo "fake gc: unexpected call: $*" >&2
exit 1
STUB
chmod +x "$BIN/gc"

# The city: an HQ, the rig the change is for, two other rigs, and the three
# rigs the pack runs on or with, each under a name the check must not report.
cat > "$STUB_RIGS" <<JSON
{"rigs":[
  {"name":"harbor","path":"$TMP/harbor","prefix":"hb","hq":true},
  {"name":"workshop","path":"$REPO","prefix":"ws"},
  {"name":"lantern","path":"$TMP/lantern","prefix":"ln"},
  {"name":"orchard-lane","path":"$TMP/orchard-lane","prefix":"ol"},
  {"name":"gascity","path":"$TMP/gascity","prefix":"gc"},
  {"name":"gc-toolkit","path":"$TMP/gc-toolkit","prefix":"tk"},
  {"name":"sprintshow","path":"$TMP/sprintshow","prefix":"ss"}
]}
JSON
echo '[]' > "$STUB_LEDGER"

run() { ( cd "${AT:-$REPO}" && "$SUT" "$@" ) 2>&1; }

git init -q --bare "$TMP/origin.git"
git init -q "$REPO"
git -C "$REPO" remote add origin "$TMP/origin.git"
cat > "$REPO/kept.md" <<'TXT'
A line that stays names lantern, and the diff leaves it alone.
A line the branch removes names orchard-lane.
TXT
git -C "$REPO" add kept.md
git -C "$REPO" commit -q -m "base"
git -C "$REPO" push -q origin main

# --- 0. nothing named ---------------------------------------------------------
git -C "$REPO" checkout -q -b work
echo "the change names only itself: workshop, ws-abc12, and gascity, gc-toolkit, sprintshow" > "$REPO/self.md"
git -C "$REPO" add self.md
git -C "$REPO" commit -q -m "a commit that names workshop and tk-abc12"
rc=0; out=$(run --branch main) || rc=$?
eq "$rc" 0 "the rig itself and the rigs the pack runs on or with are not other rigs"
has "$out" "no other rig named" "a clean run says so"

# --- 1. --branch: added lines, every way a name can be written -----------------
cat > "$REPO/added.md" <<TXT
first line names Lantern in a sentence
second line names ORCHARD LANE with a space
third line names orchardlane run together
fourth line names orchard_lane with an underscore
fifth line names lanterns, which is another word
sixth line names the bead ln-kg9z6.1.2 and the session polecat-hb-wisp-7k6m1
seventh line names xln-abc and ln-a, neither of them an id
eighth line names $TMP/harbor/rigs/x, a path under the HQ
TXT
echo "a file whose name holds a space names lantern" > "$REPO/spaced name.md"
sed -i.bak '/removes/d' "$REPO/kept.md" && rm -f "$REPO/kept.md.bak"
git -C "$REPO" add -A
git -C "$REPO" commit -q -m "add the lines"
rc=0; out=$(run --branch main) || rc=$?
eq "$rc" 1 "a mention exits 1"
has "$out" "added.md:1: names rig lantern" "a name matches case aside"
has "$out" "added.md:2: names rig orchard-lane" "a name matches with a space for its dash"
has "$out" "added.md:3: names rig orchard-lane" "a name matches with its separator left out"
has "$out" "added.md:4: names rig orchard-lane" "a name matches with an underscore for its dash"
hasnt "$out" "added.md:5:" "a name inside a longer word is not a mention"
has "$out" "added.md:6: names bead ln-kg9z6.1.2 of rig lantern" "a bead id is reported whole, its child suffix included"
has "$out" "added.md:6: names bead hb-wisp-7k6m1 of rig harbor" "an id after a dash is still an id"
hasnt "$out" "added.md:7:" "a prefix inside a word, or one letter after the dash, is not an id"
has "$out" "added.md:8: names $TMP/harbor, the checkout of rig harbor" "a path into a rig's checkout is a mention"
has "$out" "added.md:8: names rig harbor" "...and so is the name inside it"
has "$out" "spaced name.md:1: names rig lantern" "a file whose name holds a space is located by line too"
hasnt "$out" "kept.md" "a line the branch keeps or removes is not read"
hasnt "$out" "self.md" "a line naming only the rig itself is not a mention"
has "$out" "rig-mentions: " "the list ends with its count"
has "$out" "Rigs shouldn't use other rigs for data in a commit or a PR" "...and the advice"
has "$out" "a ws- id for an example bead" "the advice names the rig's own prefix"

# --- 2. --branch: commit messages, and only the ones no remote has -------------
git -C "$REPO" push -q origin work
git -C "$REPO" commit -q --allow-empty -m "local subject" -m "the body cites ol-abc12 from orchard-lane"
SHORT=$(git -C "$REPO" rev-parse --short HEAD)
rc=0; out=$(run --branch main) || rc=$?
eq "$rc" 1 "an unpushed commit message is read"
has "$out" "commit $SHORT:3: names bead ol-abc12 of rig orchard-lane" "a message line is located by commit and line"
has "$out" "commit $SHORT:3: names rig orchard-lane" "...and its name is found too"
hasnt "$out" "a commit that names workshop" "a pushed commit's message is not read"
git -C "$REPO" push -q origin work
rc=0; out=$(run --branch main) || rc=$?
hasnt "$out" "commit $SHORT" "once pushed, a commit's message is left alone"

# --- 3. the rig, from a worktree, --rig and GC_RIG -----------------------------
git -C "$REPO" worktree add -q --detach "$TMP/wt" work
rc=0; out=$(AT="$TMP/wt" run --branch main) || rc=$?
has "$out" "added.md:1: names rig lantern" "a worktree of the rig's checkout judges for that rig"
hasnt "$out" "names rig workshop" "...so the rig's own name is never a mention there"
git init -q "$ELSE"
git -C "$ELSE" commit -q --allow-empty -m "not a rig's checkout"
echo "names workshop and lantern" > "$ELSE/note.md"
rc=0; out=$(AT="$ELSE" run --file note.md) || rc=$?
eq "$rc" 2 "a repository no rig holds, with no --rig and no GC_RIG, checks nothing"
has "$out" "cannot tell which rig this change is for" "...and says why"
rc=0; out=$( cd "$ELSE" && GC_RIG=workshop "$SUT" --file note.md 2>&1 ) || rc=$?
eq "$rc" 1 "GC_RIG names the rig when the repository does not"
has "$out" "note.md:1: names rig lantern" "...and judges for it"
hasnt "$out" "names rig workshop" "...leaving that rig's own name alone"
rc=0; out=$(AT="$ELSE" run --rig lantern --file note.md) || rc=$?
has "$out" "note.md:1: names rig workshop" "--rig names the rig the change is for"
hasnt "$out" "names rig lantern" "...and that rig's name is no longer a mention"
rc=0; out=$(AT="$ELSE" run --rig nowhere --file note.md) || rc=$?
eq "$rc" 2 "a --rig the city does not have is refused"
has "$out" "'nowhere' is not a rig of this city" "...by name"

# --- 4. --bead: what the pull request publishes --------------------------------
cat > "$STUB_LEDGER" <<'JSON'
[
 {"id":"ws-fresh","title":"Fix the harbor sweep","description":"Asked for:\nport the fix from lantern\nnothing else","status":"open",
  "metadata":{"pr_summary":"Summary line one\nthe ol-abc12 change, ported"}},
 {"id":"ws-child","title":"Rework names lantern","description":"rework text names orchard-lane","status":"open",
  "metadata":{"anchor_bead":"ws-anchor"}},
 {"id":"ws-anchor","title":"A clean anchor title","description":"the anchor's dispatch names harbor","status":"open","metadata":{}},
 {"id":"ws-lost","title":"x","status":"open","metadata":{"anchor_bead":"ws-missing"}}
]
JSON
rc=0; out=$(run --bead ws-fresh) || rc=$?
eq "$rc" 1 "a bead whose text names another rig exits 1"
has "$out" "ws-fresh title:1: names rig harbor" "the title is read"
has "$out" "ws-fresh description:2: names rig lantern" "the dispatch text is read by line"
has "$out" "ws-fresh pr_summary:2: names bead ol-abc12 of rig orchard-lane" "the summary is read by line"
rc=0; out=$(run --bead ws-child) || rc=$?
has "$out" "ws-anchor description:1: names rig harbor" "a rework child is judged by its anchor's text"
hasnt "$out" "ws-child" "...and its own text, which no pull request publishes, is not read"
rc=0; out=$(run --bead ws-nope) || rc=$?
eq "$rc" 2 "a bead that does not read checks nothing"
has "$out" "cannot read bead ws-nope" "...and says which"
rc=0; out=$(run --bead ws-lost) || rc=$?
eq "$rc" 2 "an anchor that does not read checks nothing"
has "$out" "cannot read bead ws-missing, the anchor whose pull request this is" "...and names the anchor"

# --- 5. --file -------------------------------------------------------------------
printf 'a summary\nthat cites hb-q01 from the city store\n' > "$TMP/summary.md"
rc=0; out=$(run --file "$TMP/summary.md") || rc=$?
eq "$rc" 1 "a file naming another rig exits 1"
has "$out" "$TMP/summary.md:2: names bead hb-q01 of rig harbor" "a file is read by line"
rc=0; out=$(run --file "$TMP/absent.md") || rc=$?
eq "$rc" 2 "a file that does not read checks nothing"
rc=0; out=$(run --file "$TMP/summary.md" --bead ws-anchor) || rc=$?
has "$out" "summary.md:2:" "sources combine in one run: the file"
has "$out" "ws-anchor description:1:" "...and the bead"
rc=0; out=$(run --file <(printf 'a line that names lantern\n')) || rc=$?
eq "$rc" 1 "a process substitution is read as a file"
has "$out" ":1: names rig lantern" "...by line"
rc=0; out=$(run --file <(printf 'a line that names nothing\n')) || rc=$?
eq "$rc" 0 "a process substitution naming nothing exits 0"
rc=0; out=$(run --file "$TMP") || rc=$?
eq "$rc" 2 "a directory is not a file to read"

# --- 5a. --rig-map ----------------------------------------------------------------
# STUB_RIGS_RC makes the listing fail, so a pass here cannot have read it.
cp "$STUB_RIGS" "$TMP/rig-map.json"
rc=0; out=$(STUB_RIGS_RC=1 run --rig-map "$TMP/rig-map.json" --file "$TMP/summary.md") || rc=$?
eq "$rc" 1 "--rig-map answers with no listing behind it"
has "$out" "summary.md:2: names bead hb-q01 of rig harbor" "...from the rigs in the map it was given"
hasnt "$out" "the store did not answer" "...and the listing is never read"
rc=0; out=$(STUB_RIGS_RC=1 run --rig-map <(cat "$TMP/rig-map.json") --file <(printf 'names nothing\n')) || rc=$?
eq "$rc" 0 "--rig-map takes a process substitution too"
rc=0; out=$(run --rig-map "$TMP/no-such-map.json" --file "$TMP/summary.md") || rc=$?
eq "$rc" 2 "a map that does not read checks nothing, and does not fall back to a listing"
has "$out" "cannot read the city's rigs ($TMP/no-such-map.json)" "...and names the map"
printf 'not json\n' > "$TMP/bad-map.json"
rc=0; out=$(run --rig-map "$TMP/bad-map.json" --file "$TMP/summary.md") || rc=$?
eq "$rc" 2 "a map that is not JSON checks nothing"
printf '{"rigs":[]}\n' > "$TMP/empty-map.json"
rc=0; out=$(run --rig-map "$TMP/empty-map.json" --file "$TMP/summary.md") || rc=$?
eq "$rc" 2 "a map with no rigs checks nothing"

# --- 6. --tree -------------------------------------------------------------------
git -C "$REPO" checkout -q main
mkdir -p "$REPO/generated" "$REPO/link"
echo "a render naming lantern" > "$REPO/generated/render.md"
printf 'generated/** -diff\n' > "$REPO/.gitattributes"
ln -s ../generated/render.md "$REPO/link/render.md"
printf 'lantern\000binary\n' > "$REPO/blob.bin"
echo "untracked names lantern" > "$REPO/untracked.md"
git -C "$REPO" add generated .gitattributes link blob.bin
git -C "$REPO" commit -q -m "tree fixtures"
rc=0; out=$(run --tree) || rc=$?
eq "$rc" 1 "a tracked file naming another rig exits 1"
has "$out" "kept.md:1: names rig lantern" "every tracked file is read"
has "$out" "generated/render.md:1: names rig lantern" "a file .gitattributes marks -diff is still read"
hasnt "$out" "link/render.md" "a symlink is not read twice through its target"
hasnt "$out" "blob.bin" "a binary file is not read"
hasnt "$out" "untracked.md" "an untracked file is not read"

# --- 7. checks nothing ------------------------------------------------------------
rc=0; out=$(STUB_RIGS_RC=1 run --tree) || rc=$?
eq "$rc" 2 "an unreadable rig list checks nothing"
has "$out" "cannot read the city's rigs" "...and says so"
has "$out" "the store did not answer" "...with the reason the listing gave, which rig-map.sh passes on"
rc=0; out=$(run --branch no-such-base) || rc=$?
eq "$rc" 2 "a base that does not resolve checks nothing"
rc=0; out=$(run) || rc=$?
eq "$rc" 2 "nothing to read is a usage error"
rc=0; out=$(run --tree --nope) || rc=$?
eq "$rc" 2 "an unknown argument is a usage error"
rc=0; out=$(run --file) || rc=$?
eq "$rc" 2 "a flag without its value is a usage error"
printf '{"rigs":[{"name":"workshop","path":"%s","prefix":"ws"},{"name":"gascity","path":"/x","prefix":"gc"}]}\n' "$REPO" > "$STUB_RIGS"
rc=0; out=$(run --tree) || rc=$?
eq "$rc" 0 "a city with no other rig has nothing to look for"
has "$out" "no other rig in this city to look for" "...and says so"

echo "---"
echo "rig-mentions.test: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
