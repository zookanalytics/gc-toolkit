#!/usr/bin/env bash
# Hermetic test for assets/scripts/branch-supersession.sh — tells a conflicting
# branch a landed change made moot from one that only drifted. Covers classify
# over real git fixtures: the base side deleting or rewriting a block the branch
# edits (or rewrote itself), deleting a file it edits, and both sides newly
# defining one name, each naming the commit that did it rather than a later one
# on the same file; and what is not a tell: same-line drift, small edits
# interleaved across a large block the base side mostly kept, a block too small
# to count, a block the base side moved elsewhere, a renamed file, minified
# output, a generated file, a test file, identical additions that merge into one
# copy, Go `init`, and a definition only test files share. An unresolvable ref
# and unrelated histories are "could not tell". Covers hold over a stubbed store: a
# supersession files one rework-base-supersession visit on the anchor and holds;
# an open visit holds without classifying; drift proceeds; and every way the
# record can fail to stand behind the hold proceeds, so the guard never withholds
# a dispatch no person was asked about.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-branch-supersession-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
# Captured before harness_init shadows PATH with the stub bin.
REAL_GIT="$(command -v git)"
# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"
harness_init

# The classification IS git. The harness git stub answers every command it does
# not know with exit 0, which would classify nothing; real git over a real
# fixture repository instead, and only the bead store is stubbed.
cat > "$BIN/git" <<GITW
#!/usr/bin/env bash
exec "$REAL_GIT" "\$@"
GITW
chmod +x "$BIN/git"

SD="$TMP/scripts"
mk_sut_dir "$SD" "$HERE/branch-supersession.sh"
SUT="$SD/branch-supersession.sh"
# escalate.sh's contract, not just its call log: one visit per subject+key,
# stamped so the caller can find it again. STUB_ESC_RC models a refusal;
# STUB_ESC_NOFILE models the exit 0 that files nothing (a recent moot or benign
# verdict on the situation answers it).
cat > "$SD/escalate.sh" <<'ESC'
#!/usr/bin/env bash
set -u
printf '%s\n' "$*" >> "${STUB_ESC_LOG:?}"
[ -n "${STUB_ESC_RC:-}" ] && exit "$STUB_ESC_RC"
subj=""; key=""; msg=""
while [ $# -gt 0 ]; do
  case "$1" in
    --subject) shift; subj="${1:-}" ;;
    --key)     shift; key="${1:-}" ;;
    --message) shift; msg="${1:-}" ;;
  esac
  shift || true
done
[ -n "$subj" ] && [ -n "$key" ] || exit 2
printf '%s' "$msg" > "${STUB_ESC_MSG:?}"
[ -n "${STUB_ESC_NOFILE:-}" ] && exit 0
have=$(jq -r --arg s "$subj" --arg k "$key" '
  [ .[] | select((.status // "open") != "closed")
    | select(((.metadata["gc.continuation_group"] // "") | tostring) == $s)
    | select(((.metadata.escalation_key // "") | tostring) == $k) | .id ] | .[0] // empty' "${STUB_STORE:?}")
[ -n "$have" ] && exit 0
vid=$(gc bd create "visit: $subj — $key" -t task --json | jq -r '.id // empty')
[ -n "$vid" ] || exit 1
gc bd update "$vid" --set-metadata "escalation_key=$key" \
  --set-metadata "gc.continuation_group=$subj" --set-metadata "task_kind=visit" >/dev/null
ESC
chmod +x "$SD/escalate.sh"
export STUB_ESC_LOG="$TMP/esc.log" STUB_ESC_MSG="$TMP/esc.msg" STUB_ESC_RC="" STUB_ESC_NOFILE=""

# --- fixture repository ---------------------------------------------------------
# One base commit. Each scenario forks two branches from it: m-<s> is the base
# side (the target after a sibling landed) and b-<s> is the branch under rework.
R="$TMP/repo"
git init -q -b main "$R"
cd "$R" || exit 1
git config user.email t@t; git config user.name t; git config commit.gpgsign false

mkdir -p lib pkg/board generated
cat > .gitattributes <<'EOF'
generated/** linguist-generated
EOF
PIN_BLOCK='check_pin() {
  local anchor="$1" marker oid head
  marker=$(gc bd show "$anchor" --json | jq -r ".[0].metadata.check")
  oid="${marker#*@}"
  head=$(git rev-parse HEAD)
  if [ "$oid" != "$head" ]; then
    echo "stale pin on $anchor: the marker $marker names $oid, not the head $head"
    echo "a review bound to an older commit proves nothing about this one"
    return 1
  fi
  echo "pin current for $anchor at $oid, so the verdict still binds"
  return 0
}'
{
  printf '#!/usr/bin/env bash\n# gate helpers\nprelude() { echo start; }\n\n'
  printf '%s\n\n' "$PIN_BLOCK"
  printf 'postlude() { echo done; }\n'
} > lib/gate.sh
cp lib/gate.sh lib/gate.test.sh
cp lib/gate.sh generated/out.sh
printf 'greet() {\n  echo "hello $1"\n}\n' > lib/small.sh
{
  printf '# The old dispatcher: every pending review is poured here, one per lane,\n'
  printf '# and the marker it stamps names the commit the review was poured for,\n'
  printf '# so a push that moves the head leaves every earlier verdict behind.\n'
  printf 'dispatch_all() {\n  for lane in correctness codex arch; do\n'
  printf '    pour_review "$lane" "$(git rev-parse HEAD)" || echo "could not pour $lane"\n'
  printf '  done\n}\n'
} > lib/gone.sh
printf 'package board\n\nfunc severity(a int) int {\n\treturn a * 2\n}\n' > pkg/board/derive.go
# Minified build output nobody declared generated: one line of hundreds of words.
mkdir -p web
bundle() { awk -v p="$1" 'BEGIN { for (i = 0; i < 200; i++) printf "%s%d=f(%d); ", p, i, i; print "" }'; }
bundle v > web/app.js
bundle c > web/app.css
git add -A; git commit -qm base
BASE=$(git rev-parse HEAD)

# scenario <name> <base-side-message>: run the base-side edit (function m_<name>)
# and the branch-side edit (b_<name>) on two branches cut from BASE.
scenario() {
  git checkout -q -b "m-$1" "$BASE"; "m_$1"; git add -A; git commit -qm "$2"
  git checkout -q -b "b-$1" "$BASE"; "b_$1"; git add -A; git commit -qm "branch edits for $1"
  git checkout -q main
}
edit_pin_line() { # <file>: the branch's in-place edit inside check_pin
  sed -i 's/a review bound to an older commit proves nothing about this one/a verdict bound to an older commit proves nothing about this head/' "$1"
}
drop_pin_block() { # <file>: the base side deletes check_pin outright
  awk '/^check_pin\(\) \{/ {skip=1} skip && /^}$/ {skip=0; getline; next} !skip' "$1" > "$1.n" && mv "$1.n" "$1"
}
rewrite_pin_body() { # <file>: the base side replaces check_pin's body with a lane-state read
  awk '/^check_pin\(\) \{/ {print; print "  lane_is_green \"$1\""; skip=1; next}
       skip && /^}$/ {skip=0} !skip' "$1" > "$1.n" && mv "$1.n" "$1"
}

m_del() { drop_pin_block lib/gate.sh; }
b_del() { edit_pin_line lib/gate.sh; }
scenario del "remove the commit pin"
# A later, unrelated commit on the same file: the landed line names the commit
# that deleted the block, not merely the newest one to touch the file.
git checkout -q m-del; sed -i 's/^# gate helpers$/# gate helpers, sourced by the gate scripts/' lib/gate.sh; git commit -qam "describe the gate helpers"; git checkout -q main

m_rew() { rewrite_pin_body lib/gate.sh; }
b_rew() { edit_pin_line lib/gate.sh; }
scenario rew "read the lane state, not a pinned commit"

m_both() { drop_pin_block lib/gate.sh; }
b_both() { rewrite_pin_body lib/gate.sh; }
scenario both "remove the commit pin"

m_ord() { sed -i 's/pin current for/the pin is current for/' lib/gate.sh; }
b_ord() { sed -i 's/pin current for/pin still current for/' lib/gate.sh; }
scenario ord "reword the current-pin message"

# Small edits on alternating lines of one block: no unchanged line between them,
# so git reports one conflict over most of the block, yet the base side kept
# nearly every word of it.
m_drift() {
  awk '{
    if ($0 == "  local anchor=\"$1\" marker oid head") $0 = "  local anchor=\"$1\" marker oid head base"
    else if ($0 == "  oid=\"${marker#*@}\"") $0 = "  oid=\"${marker##*@}\""
    else if ($0 == "  if [ \"$oid\" != \"$head\" ]; then") $0 = "  if [ \"$oid\" != \"$head\" ]; then # stale"
    else if ($0 == "    echo \"a review bound to an older commit proves nothing about this one\"") $0 = "    echo \"a review bound to an older commit proves nothing about this one at all\""
    print }' lib/gate.sh > lib/gate.sh.n && mv lib/gate.sh.n lib/gate.sh
}
b_drift() {
  awk '{
    if (index($0, "  marker=$(gc bd show") == 1) sub(/--json \|/, "--json 2>/dev/null |")
    else if ($0 == "  head=$(git rev-parse HEAD)") $0 = "  head=$(git rev-parse --verify HEAD)"
    else if (index($0, "    echo \"stale pin on") == 1) sub(/the head \$head"/, "the head $head.\"")
    print }' lib/gate.sh > lib/gate.sh.n && mv lib/gate.sh.n lib/gate.sh
}
scenario drift "tighten the pin check"

m_mov() { drop_pin_block lib/gate.sh; printf '%s\n' "$PIN_BLOCK" > lib/pins.sh; }
b_mov() { edit_pin_line lib/gate.sh; }
scenario mov "move check_pin into its own file"

m_small() { printf 'greet() {\n  printf "hi %%s\\n" "$1"\n}\n' > lib/small.sh; }
b_small() { printf 'greet() {\n  echo "hello there $1"\n}\n' > lib/small.sh; }
scenario small "greet with printf"

m_gone() { git rm -q lib/gone.sh; }
b_gone() { sed -i 's/could not pour $lane/could not pour the $lane review/' lib/gone.sh; }
scenario gone "retire the old dispatcher"

m_ren() { git mv lib/gone.sh lib/dispatch.sh; }
b_ren() { sed -i 's/could not pour $lane/could not pour the $lane review/' lib/gone.sh; }
scenario ren "rename the dispatcher"

m_gen() { rewrite_pin_body generated/out.sh; }
b_gen() { edit_pin_line generated/out.sh; }
scenario gen "regenerate the rendered copy"

m_bundle() { bundle w > web/app.js; }
b_bundle() { bundle x > web/app.js; }
scenario bundle "rebuild the bundle"

m_bundled() { git rm -q web/app.css; }
b_bundled() { bundle d > web/app.css; }
scenario bundled "drop the stylesheet bundle"

m_tst() { rewrite_pin_body lib/gate.test.sh; }
b_tst() { edit_pin_line lib/gate.test.sh; }
scenario tst "rewrite the pin test"

m_dup() { printf '\nfunc stallReason(b []string) string {\n\treturn "main"\n}\n' >> pkg/board/derive.go; }
b_dup() { printf 'package board\n\nfunc stallReason(b []string) string {\n\treturn "branch"\n}\n' > pkg/board/stall.go; }
scenario dup "surface stalled anchors on the board"

m_same() { printf '\nfunc helper() int {\n\treturn 1\n}\n' >> pkg/board/derive.go; }
b_same() { printf '\nfunc helper() int {\n\treturn 1\n}\n' >> pkg/board/derive.go; }
scenario same "add the helper"

m_dtest() { printf 'package board\n\nfunc stallReason() string { return "a" }\n' > pkg/board/derive_test.go; }
b_dtest() { printf 'package board\n\nfunc stallReason() string { return "b" }\n' > pkg/board/stall_test.go; }
scenario dtest "add a test helper"

m_init() { printf 'package board\n\nfunc init() { severity(1) }\n' > pkg/board/a.go; }
b_init() { printf 'package board\n\nfunc init() { severity(2) }\n' > pkg/board/b.go; }
scenario init "register at init"

m_shdup() { sed -i 's/^prelude() { echo start; }$/prelude() { echo start; }\nusage() { echo "usage: gate"; }/' lib/gate.sh; }
b_shdup() { sed -i 's/^postlude() { echo done; }$/usage() { echo "usage: gate <anchor>"; }\npostlude() { echo done; }/' lib/gate.sh; }
scenario shdup "add usage to the gate helpers"

# A root commit sharing no history with BASE.
git update-ref refs/heads/orphan "$(git commit-tree "$(git mktree < /dev/null)" -m orphan)"

classify() { "$SUT" classify "$@" 2>&1; }

echo "# the base side deleted a block the branch edits"
OUT=$(classify m-del b-del); rc=$?
eq "$rc" "0" "a block the base side deleted while the branch edits it is a supersession"
has "$OUT" "$(printf 'deleted-block\tlib/gate.sh\t')" "it is reported as a deleted block, with the path"
has "$OUT" "$(printf 'landed\t%s\tremove the commit pin' "$(git rev-parse --short m-del~1)")" "and the landed line names the commit that deleted it"
hasnt "$OUT" "describe the gate helpers" "not a later commit that only touched the same file"

echo "# the base side rewrote a block the branch edits"
OUT=$(classify m-rew b-rew); rc=$?
eq "$rc" "0" "a block the base side rewrote while the branch edits it in place is a supersession"
has "$OUT" "$(printf 'rewritten-block\tlib/gate.sh\t')" "it is reported as a rewritten block"
has "$OUT" "read the lane state, not a pinned commit" "and names the rewriting commit"

OUT=$(classify m-both b-both); rc=$?
eq "$rc" "0" "a block the base side deleted while the branch rewrote it is a supersession too"
has "$OUT" "$(printf 'deleted-block\tlib/gate.sh\t')" "and is reported as the deleted block it is"

echo "# the base side deleted a file the branch edits"
OUT=$(classify m-gone b-gone); rc=$?
eq "$rc" "0" "a modify/delete conflict on a file of real size is a supersession"
has "$OUT" "$(printf 'deleted-file\tlib/gone.sh\t')" "it is reported as a deleted file"
has "$OUT" "retire the old dispatcher" "and names the commit that deleted it"

echo "# both sides newly define one name"
OUT=$(classify m-dup b-dup); rc=$?
eq "$rc" "0" "two new definitions of one Go function in one package are a supersession, conflict or not"
has "$OUT" "$(printf 'duplicate-definition\tpkg/board\tstallReason')" "it names the package and the doubled function"
has "$OUT" "surface stalled anchors on the board" "and the commit that added the base side's copy"
OUT=$(classify m-shdup b-shdup); rc=$?
eq "$rc" "0" "two new definitions of one shell function in one script are a supersession"
has "$OUT" "$(printf 'duplicate-definition\tlib/gate.sh\tusage')" "it names the script and the function"

echo "# drift is not a supersession"
git merge-tree --write-tree --quiet m-ord b-ord >/dev/null 2>&1; eq "$?" "1" "the same-line edit really conflicts (premise of the next check)"
OUT=$(classify m-ord b-ord); rc=$?
eq "$rc" "1" "both sides editing one line of a block is drift"
eq "$OUT" "" "and prints no evidence"
OUT=$(classify m-small b-small); rc=$?
eq "$rc" "1" "a rewrite of a block too small to count is drift"
REGION=$(git merge-file -p --diff3 --object-id "$(git rev-parse m-drift:lib/gate.sh)" "$(git rev-parse "$BASE":lib/gate.sh)" "$(git rev-parse b-drift:lib/gate.sh)" \
  | awk '/^\|\|\|\|\|\|\| /{f=1; next} /^=======$/{f=0} f' | wc -w)
[ "$REGION" -ge 50 ] && ok "interleaved edits really form one conflict of ${REGION} base words (premise of the next check)" \
  || bad "interleaved edits form a conflict of only ${REGION} base words, below the block size the next check needs"
OUT=$(classify m-drift b-drift); rc=$?
eq "$rc" "1" "a large conflict whose base side kept most of the block's words is drift"

echo "# a block the base side moved is not a deletion"
git merge-tree --write-tree --quiet m-mov b-mov >/dev/null 2>&1; eq "$?" "1" "the move really conflicts with the in-place edit"
OUT=$(classify m-mov b-mov); rc=$?
eq "$rc" "1" "a block whose lines reappear among the base side's additions was moved, and the branch's edit can follow it"
OUT=$(classify m-ren b-ren); rc=$?
eq "$rc" "1" "a renamed file is followed by the merge, not read as deleted"

echo "# what is not read"
git merge-tree --write-tree --quiet m-gen b-gen >/dev/null 2>&1; eq "$?" "1" "the generated rewrite really conflicts"
OUT=$(classify m-gen b-gen); rc=$?
eq "$rc" "1" "a rewrite in a file the repository declares generated is regenerated, not superseded"
OUT=$(classify m-tst b-tst); rc=$?
eq "$rc" "1" "a rewrite in a test file is not a tell"
git merge-tree --write-tree --quiet m-bundle b-bundle >/dev/null 2>&1; eq "$?" "1" "a bundle rebuilt on both sides really conflicts"
OUT=$(classify m-bundle b-bundle); rc=$?
eq "$rc" "1" "minified output rebuilt on both sides is not a rewrite of code, declared generated or not"
OUT=$(classify m-bundled b-bundled); rc=$?
eq "$rc" "1" "nor is a bundle one side deleted and the other rebuilt"
OUT=$(classify m-same b-same); rc=$?
eq "$rc" "1" "both sides adding the identical definition merges into one copy, which is no collision"
OUT=$(classify m-dtest b-dtest); rc=$?
eq "$rc" "1" "a name only test files share is not a tell"
OUT=$(classify m-init b-init); rc=$?
eq "$rc" "1" "Go init may be defined any number of times in a package"

echo "# could not tell"
OUT=$(classify nosuchref b-del); rc=$?
eq "$rc" "2" "an unresolvable ref is could-not-tell, never drift or supersession"
OUT=$(classify m-del orphan); rc=$?
eq "$rc" "2" "unrelated histories have no merge base, so could-not-tell"
"$SUT" classify m-del >/dev/null 2>&1; eq "$?" "2" "classify takes exactly two refs"

# --- hold -----------------------------------------------------------------------
SUP_BASE=$(git rev-parse m-del); SUP_HEAD=$(git rev-parse b-del)
ORD_BASE=$(git rev-parse m-ord); ORD_HEAD=$(git rev-parse b-ord)
anchor() { printf '{"id":"%s","status":"open","assignee":"","notes":"","title":"%s","metadata":{"merge_result":"pre_open_gate","branch":"polecat/tk-pin"}}' "$1" "${2:-tighten the stale-pin check}"; }
reset() { # <row-json>...
  local IFS=,; store "[$*]"
  : > "$STUB_ESC_LOG"; : > "$STUB_ESC_MSG"
  export STUB_ESC_RC="" STUB_ESC_NOFILE="" STUB_LIST_FAIL=""
}
hold() { "$SUT" hold --anchor "$1" --branch polecat/tk-pin --target main --base "$2" --head "$3" "${@:4}" 2>&1; }
visits() { jq -r --arg a "$1" '[ .[] | select((.metadata.escalation_key // "") == "rework-base-supersession") | select((.metadata["gc.continuation_group"] // "") == $a) | select((.status // "open") != "closed") ] | length' "$STUB_STORE"; }

echo "# hold: a supersession files the decision and holds behind it"
reset "$(anchor A1)"
OUT=$(hold A1 "$SUP_BASE" "$SUP_HEAD"); rc=$?
eq "$rc" "0" "a superseded branch holds the dispatch"
has "$(cat "$STUB_ESC_LOG")" "--subject A1 --key rework-base-supersession" "the decision is filed on the anchor under the key polecats file by hand"
eq "$(visits A1)" "1" "exactly one open decision visit stands behind the hold"
has "$OUT" "filed decision" "and the arm's log says the decision was filed"
MSG=$(cat "$STUB_ESC_MSG")
FIRST=$(printf '%s\n' "$MSG" | head -n 1)
eq "$FIRST" "Branch polecat/tk-pin may be moot: a change already on main deleted or rewrote code it edits" "the headline states the stake in plain language"
[ "${#FIRST}" -le 100 ] && ok "the headline fits escalate.sh's 100-character title" || bad "headline is ${#FIRST} characters"
has "$MSG" "(tighten the stale-pin check)" "the anchor's title says what the work is"
has "$MSG" "remove the commit pin" "the brief names what landed"
has "$MSG" "lib/gate.sh: main deleted a" "and where it collides"
has "$MSG" "Retire it, if what landed covers this work" "it offers retiring the work"
has "$MSG" "bead-rehome.sh disposes of the anchor" "naming the pre-open disposal verb"
has "$MSG" "Re-scope it" "it offers re-scoping"
has "$MSG" "Close this visit benign, and the next reconcile pass sends the ordinary merge-in child" "and says how an incidental overlap releases the dispatch"
has "$MSG" "(anchor A1, branch polecat/tk-pin at ${SUP_HEAD:0:8}, main at ${SUP_BASE:0:8})" "identifiers ride in one closing parenthetical"

reset "$(anchor A2)"
hold A2 "$SUP_BASE" "$SUP_HEAD" --pr 7 >/dev/null
MSG=$(cat "$STUB_ESC_MSG")
has "$MSG" "PR#7 may be moot" "a PR anchor is named by its PR"
has "$MSG" "pr-dispose.sh closes the PR and disposes of the anchor" "and gets the PR disposal verb"

echo "# hold: an open decision holds without asking again"
reset "$(anchor A3)" '{"id":"V3","status":"open","assignee":"","title":"visit","notes":"","metadata":{"escalation_key":"rework-base-supersession","gc.continuation_group":"A3","task_kind":"visit"}}'
OUT=$(hold A3 "$ORD_BASE" "$ORD_HEAD"); rc=$?
eq "$rc" "0" "an open decision on the anchor holds, even where the branch now reads as drift"
eq "$(cat "$STUB_ESC_LOG")" "" "and nothing is escalated a second time"
has "$OUT" "V3 is still open" "the arm's log names the pending decision"

reset "$(anchor A4)" '{"id":"V4","status":"open","assignee":"","title":"visit","notes":"","metadata":{"escalation_key":"some-other-key","gc.continuation_group":"A4","task_kind":"visit"}}' \
  '{"id":"V5","status":"open","assignee":"","title":"visit","notes":"","metadata":{"escalation_key":"rework-base-supersession","gc.continuation_group":"OTHER","task_kind":"visit"}}' \
  '{"id":"V6","status":"closed","assignee":"","title":"visit","notes":"","metadata":{"escalation_key":"rework-base-supersession","gc.continuation_group":"A4","task_kind":"visit","gc.outcome":"benign"}}'
hold A4 "$ORD_BASE" "$ORD_HEAD" >/dev/null; rc=$?
eq "$rc" "1" "another key, another anchor's decision, or a closed one holds nothing"

echo "# hold: drift proceeds"
reset "$(anchor A5)"
OUT=$(hold A5 "$ORD_BASE" "$ORD_HEAD"); rc=$?
eq "$rc" "1" "an ordinary conflict proceeds to the merge-in child"
eq "$(cat "$STUB_ESC_LOG")" "" "and files no decision"

echo "# hold: no record behind the hold means no hold"
reset "$(anchor A6)"
export STUB_ESC_RC=1
OUT=$(hold A6 "$SUP_BASE" "$SUP_HEAD"); rc=$?
eq "$rc" "1" "a decision that could not be filed proceeds rather than holding with no record"
has "$OUT" "could not be filed" "and says so"
reset "$(anchor A7)"
export STUB_ESC_NOFILE=1
OUT=$(hold A7 "$SUP_BASE" "$SUP_HEAD"); rc=$?
eq "$rc" "1" "escalate.sh answering with no open visit (a recent moot or benign ruling) proceeds"
has "$OUT" "no supersession visit is open" "and says why"
reset "$(anchor A8)"
OUT=$(hold A8 nosuchref "$SUP_HEAD"); rc=$?
eq "$rc" "1" "a trial merge that cannot be read proceeds as drift"
eq "$(cat "$STUB_ESC_LOG")" "" "and files nothing"
reset "$(anchor A9)"
export STUB_LIST_FAIL=1
OUT=$(hold A9 "$ORD_BASE" "$ORD_HEAD"); rc=$?
eq "$rc" "1" "an unreadable store does not hold a branch that reads as drift"
"$SUT" hold --anchor A1 --branch b --target main >/dev/null 2>&1; eq "$?" "2" "hold without both commits is a usage error"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
