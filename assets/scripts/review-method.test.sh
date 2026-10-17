#!/usr/bin/env bash
# Hermetic test for the split between the review lifecycle and each check's
# method. formulas/mol-review.toml and its two-lane variant,
# formulas/mol-review-quorum-signoff.toml, carry what every check shares: the
# pins, the review workspace and the claim-lease keepalive, the verdict
# envelope and the one signoff.sh call. Each check's method, the file its
# review-checks.toml row names, carries what that check reads, runs and judges.
# No live city, Dolt, network, or PRs.
# Covered:
#   (NEUTRAL)    neither review formula names a test or a suite, a P0/P1/P2
#                grade, the Verification line, a dimension of the correctness
#                method's What to check list, a check's method skill, or a
#                signoff.sh flag that only a check's method passes; mol-review
#                names no severity at all.
#   (METHOD)     the correctness row points at its own method file, which
#                carries the What to check list, the severity ladder, the
#                review-test-evidence block and the Verification line.
#   (STANDARDS)  the method reads the work-quality fragments and the exemplar
#                corpus from its own references/ directory and resolves no
#                pack file by path; each fragment it reads has a relative link
#                there, and every link there is one of them.
#   (QUORUM)     the quorum's lanes load the method skill the dispatch note
#                names, and point at no mol-review review step; a lane
#                runs nothing anywhere, and the synthesis runs what the method
#                runs inside a workspace made by the review-workspace-add block
#                alone, which leaves the synthesis's own keepalive in place.
#   (SPECIALIST) no other check's dispatch note or method file asks for a test
#                run or its result, or runs a suite, and an undeclared check's
#                note borrows no other check's method.
#   (KEEPALIVE)  every long command a method runs goes through hb: the
#                correctness suites, through the gate or plain, and the demo
#                capture.
#   (RUBRIC)     the learning loop's review-rubric anchors sit in the ledger
#                beside the method, each line naming a dimension of its What
#                to check list, an anchor whose dimension was recorded at
#                adoption naming that one, and the inventory reads every one;
#                the method itself carries no HTML comment.
#   (EVIDENCE)   the review-test-evidence block reads gctk rig's record of the
#                tests at the pinned commit, in the review's worktree: a pass
#                of the full suite or the affected subset is evidence and runs
#                no suite, a fail whose record the anchor's pre-existing mark
#                holds at that commit is not run again, any other fail is run
#                again with --force, and no record, a pass that ran nothing,
#                a machine failure or no binary runs the suites the diff
#                touches through the gate; in bash and in zsh.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-review-method-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }
hasF() { grep -qF -- "$2" "$1" && ok "$3" || bad "$3 (missing: $2)"; }
notF() { grep -qF -- "$2" "$1" && bad "$3 (unexpected: $2)" || ok "$3"; }
# notE <file> <ERE> <label> [-i]: no line matches; a hit names the line.
notE() {
  local hit
  hit=$(grep -E ${4:-} -m1 -- "$2" "$1" || true)
  [ -z "$hit" ] && ok "$3" || bad "$3 (unexpected: $hit)"
}

LIFE="$ROOT/formulas/mol-review.toml"
QUORUM="$ROOT/formulas/mol-review-quorum-signoff.toml"
INDEX="$ROOT/review-checks.toml"
CHECKS="$ROOT/assets/scripts/review-checks.sh"
BODY="$ROOT/assets/scripts/review-dispatch-body.sh"

# The text a reviewer reads from a formula: its description and every step's
# title and description. One file for the whole formula, and one per step.
dump() {  # dump <toml> <out-prefix>
  python3 - "$1" "$2" <<'PY'
import sys, tomllib
d = tomllib.load(open(sys.argv[1], 'rb'))
parts = [d.get('description', '')]
for s in d.get('steps', []):
    text = s.get('title', '') + '\n' + s.get('description', '')
    parts.append(text)
    open(sys.argv[2] + '.' + s['id'] + '.txt', 'w').write(text)
open(sys.argv[2] + '.txt', 'w').write('\n'.join(parts))
PY
}
dump "$LIFE" "$TMP/life"
dump "$QUORUM" "$TMP/quorum"
[ -s "$TMP/life.txt" ] && ok "(NEUTRAL) mol-review's text is read" || bad "(NEUTRAL) mol-review's text is empty"
[ -s "$TMP/quorum.review-lane-one.txt" ] && ok "(QUORUM) the quorum's lane text is read" || bad "(QUORUM) the quorum's lane text is empty"

echo "# the correctness method is its own file, beside the other checks' methods"
METHOD_REL=$("$CHECKS" --file "$INDEX" --check correctness | cut -f2)
eq "$METHOD_REL" "skills/review-correctness/SKILL.md" "(METHOD) the correctness row points at its own method file"
METHOD="$ROOT/$METHOD_REL"
[ -r "$METHOD" ] && ok "(METHOD) the correctness method ships" || bad "(METHOD) $METHOD_REL is missing"
eq "$(sed -n 's/^name: //p' "$METHOD" | head -1)" "review-correctness" "(METHOD) its skill name matches its directory"
hasF "$METHOD" '## What to check' "(METHOD) it carries the What to check list"
hasF "$METHOD" 'P0 — ' "(METHOD) it carries the severity ladder (P0)"
hasF "$METHOD" 'P1 — ' "(METHOD) …(P1)"
hasF "$METHOD" 'P2 — ' "(METHOD) …(P2)"
hasF "$METHOD" '# >>> review-test-evidence' "(METHOD) it carries the review-test-evidence block"
hasF "$METHOD" 'Verification: <' "(METHOD) it carries the Verification line"

# The dimensions are the bold bullets of the What to check list.
awk '/^## What to check$/ {f = 1; next} f && /^## / {exit} f' "$METHOD" \
  | sed -n 's/^- \*\*\([^*]*\)\*\*.*/\1/p' > "$TMP/dimensions"
DIMS=$(grep -c . "$TMP/dimensions" || true)
[ "$DIMS" -ge 5 ] && ok "(METHOD) the What to check list names its dimensions ($DIMS)" \
  || bad "(METHOD) the What to check list names only $DIMS dimensions"

echo "# the method reads its standards from its own skill directory"
notE "$METHOD" 'GC_PACK_DIR|GC_RIG_ROOT|GC_CITY_PATH|template-fragments/' "(STANDARDS) the method resolves no pack file by path"
hasF "$METHOD" '`references/work-quality-*.template.md`' "(STANDARDS) it reads the work-quality fragments from its references"
hasF "$METHOD" '`references/learning-exemplars.template.md`' "(STANDARDS) …and the exemplar corpus"
# A skill reaches a reviewer as a link to its directory, so a relative link in
# references/ resolves wherever the pack is installed. A new class fragment
# fails here until it has its link.
REFS="$(dirname "$METHOD")/references"
for frag in "$ROOT"/template-fragments/work-quality-*.template.md "$ROOT/template-fragments/learning-exemplars.template.md"; do
  b=$(basename "$frag")
  if [ -L "$REFS/$b" ] && [ "$REFS/$b" -ef "$frag" ]; then
    case "$(readlink "$REFS/$b")" in
      /*) bad "(STANDARDS) references/$b links template-fragments/$b by an absolute path" ;;
      *) ok "(STANDARDS) references/$b is a relative link to template-fragments/$b" ;;
    esac
  else
    bad "(STANDARDS) references/$b is not a link to template-fragments/$b"
  fi
done
for l in "$REFS"/*; do
  b=$(basename "$l")
  case "$b" in work-quality-*.template.md|learning-exemplars.template.md) ;; *) b="" ;; esac
  [ -n "$b" ] && [ "$l" -ef "$ROOT/template-fragments/$b" ] \
    && ok "(STANDARDS) references/$(basename "$l") is a fragment the method reads" \
    || bad "(STANDARDS) references/$(basename "$l") is not a fragment the method reads"
done

echo "# the flags only a check's method passes to signoff.sh"
# A check-specific flag is one signoff.sh takes, a check's method file or
# dispatch note names, and the lifecycle's own verdict call does not carry.
grep -oE '^    --[a-z][a-z-]*\)' "$ROOT/assets/scripts/signoff.sh" | tr -d ' )' | sort -u > "$TMP/signoff-flags"
grep -F '/signoff.sh" --review-bead' "$LIFE" | grep -oE -- '--[a-z][a-z-]*' | sort -u > "$TMP/call-flags"
: > "$TMP/method-text"
: > "$TMP/method-skills"
"$CHECKS" --file "$INDEX" | while IFS="$(printf '\t')" read -r name method _; do
  bash "$BODY" --check-name "$name" >> "$TMP/method-text"
  printf '%s\n' "$method" | awk '{n = split($0, m, / [+] /); for (i = 1; i <= n; i++) print m[i]}' \
    | while IFS= read -r f; do
        cat "$ROOT/$f" >> "$TMP/method-text"
        # The skill a reviewer loads from its catalog: the method file's directory.
        basename "$(dirname "$f")" >> "$TMP/method-skills"
      done
done
[ -s "$TMP/method-skills" ] && ok "(NEUTRAL) each declared check's method skill is read from the index" \
  || bad "(NEUTRAL) no method skill read from the index"
grep -oE -- '--[a-z][a-z-]*' "$TMP/method-text" | sort -u > "$TMP/method-flags"
comm -12 "$TMP/signoff-flags" "$TMP/method-flags" | comm -23 - "$TMP/call-flags" > "$TMP/check-flags"
hasF "$TMP/check-flags" '--add-gates' "(NEUTRAL) triage's --add-gates is found as a check-specific flag"
hasF "$TMP/check-flags" '--visual' "(NEUTRAL) demo's --visual is found as a check-specific flag"
notF "$TMP/check-flags" '--reviewed-oid' "(NEUTRAL) the lifecycle's own call flags are not"

echo "# the lifecycle names no check's judgment"
neutral() {  # neutral <text file> <label>
  notE "$1" '(^|[^[:alnum:]_])(tests?|tested|testing|suites?)([^[:alnum:]_]|$)' "(NEUTRAL) $2 names no test or suite" -i
  notE "$1" '(^|[^[:alnum:]_])P[0-2]([^[:alnum:]_]|$)' "(NEUTRAL) $2 names no P0/P1/P2 grade"
  notF "$1" 'Verification:' "(NEUTRAL) $2 has no Verification line"
  notF "$1" 'What to check' "(NEUTRAL) $2 points at no What to check list"
  local d f s
  while IFS= read -r d; do
    notF "$1" "**$d**" "(NEUTRAL) $2 carries no '$d' dimension"
  done < "$TMP/dimensions"
  while IFS= read -r f; do
    notE "$1" "(^|[^[:alnum:]-])$f([^[:alnum:]-]|$)" "(NEUTRAL) $2 names no check-specific flag $f"
  done < "$TMP/check-flags"
  while IFS= read -r s; do
    notF "$1" "$s" "(NEUTRAL) $2 names no check's method skill ($s)"
  done < "$TMP/method-skills"
}
neutral "$TMP/life.txt" "mol-review"
notE "$TMP/life.txt" 'severity' "(NEUTRAL) mol-review names no severity" -i
notE "$LIFE" 'adopted:' "(RUBRIC) mol-review carries no adopted rubric anchor"
# The quorum's lanes record a severity key, the lane schema's, so only the
# grades themselves are held out of it.
neutral "$TMP/quorum.txt" "the quorum formula"

echo "# the quorum's lanes apply the check's method"
# flat <file> : the file's prose on one line, so a pinned phrase may wrap.
flat() { tr '\n' ' ' < "$1" | tr -s ' '; }
for lane in review-lane-one review-lane-two; do
  flat "$TMP/quorum.$lane.txt" > "$TMP/quorum.$lane.flat"
  hasF "$TMP/quorum.$lane.flat" "The method is the skill the check section of the review bead's dispatch note names, loaded from your skill catalog." \
    "(QUORUM) $lane loads the method skill the dispatch note names, from its catalog"
  notF "$TMP/quorum.$lane.txt" "'s \`review\` step" "(QUORUM) $lane points at no mol-review review step"
  notF "$TMP/quorum.$lane.txt" 'review-method-read' "(QUORUM) …and names no read block"
  hasF "$TMP/quorum.$lane.flat" 'no review workspace and no keepalive' "(QUORUM) $lane names what of the frame a lane lacks"
  hasF "$TMP/quorum.$lane.flat" 'runs nothing the method runs, anywhere: not at the reviewed commit and not against the pre-change code' \
    "(QUORUM) $lane runs nothing anywhere"
done
flat "$TMP/quorum.synthesize-and-signoff.txt" > "$TMP/synth.flat"
hasF "$TMP/synth.flat" 'against the pre-change code alike' "(QUORUM) the synthesis owns every run the method calls for, the pre-change code's included"
hasF "$TMP/synth.flat" 'the `review-workspace-add` block of `formulas/mol-review.toml`, and only that block' \
  "(QUORUM) the synthesis makes its workspace with the review-workspace-add block alone"
# The synthesis runs this block alone, after its own keepalive, so the block
# must leave hb alone: mol-review's keepalive keys hb on a step bead the
# synthesis never sets.
awk '/^# >>> review-workspace-add$/ {f = 1} f {print} /^# <<< review-workspace-add$/ {f = 0}' "$LIFE" > "$TMP/workspace-add.sh"
[ -s "$TMP/workspace-add.sh" ] && ok "(QUORUM) mol-review's review-workspace-add block extracts" || bad "(QUORUM) no review-workspace-add block in mol-review"
notE "$TMP/workspace-add.sh" '(^|[^[:alnum:]_])hb[[:space:]]*\(\)' "(QUORUM) the review-workspace-add block defines no hb"
notF "$TMP/workspace-add.sh" 'CLAIMED_STEP_BEAD_ID' "(QUORUM) …and reads no claimed step bead"

echo "# no other check is asked for test results"
: > "$TMP/specialists"
"$CHECKS" --file "$INDEX" | while IFS="$(printf '\t')" read -r name method _; do
  [ "$name" = correctness ] && continue
  printf '%s\n' "$name" >> "$TMP/specialists"
  printf '%s\n' "$method" | awk '{n = split($0, m, / [+] /); for (i = 1; i <= n; i++) print m[i]}'
done | sort -u > "$TMP/specialist-methods"
[ -s "$TMP/specialist-methods" ] && ok "(SPECIALIST) the index declares other checks" || bad "(SPECIALIST) no other check is declared"
# A specialist's method may name tests as part of what a diff carries, so its
# texts are held to the words that ask for a run or its result: a test run,
# result, evidence, command or output, a suite, or running tests.
ASKS='(^|[^[:alnum:]_])(tests? (runs?|results?|evidence|commands?|output)|suites?|(run|runs|running|ran)( [[:alpha:]]+)? (tests?|suites?))([^[:alnum:]_]|$)'
# A specialist reviewer reads its dispatch note, under either review formula,
# and its method files.
while IFS= read -r name; do
  for formula in mol-review mol-review-quorum-signoff; do
    bash "$BODY" --formula "$formula" --check-name "$name" > "$TMP/note.$formula.$name"
    notE "$TMP/note.$formula.$name" "$ASKS" "(SPECIALIST) the $name dispatch note under $formula asks for no test run or result" -i
  done
done < "$TMP/specialists"
# A check the pack declares no method for borrows none: it is judged on its
# stated purpose, with no test run, grade or Verification line of another check's.
for formula in mol-review mol-review-quorum-signoff; do
  bash "$BODY" --formula "$formula" --check-name nonesuch > "$TMP/note.$formula.nonesuch"
  notE "$TMP/note.$formula.nonesuch" "$ASKS" "(SPECIALIST) an undeclared check's note under $formula asks for no test run or result" -i
  notF "$TMP/note.$formula.nonesuch" 'review-correctness' "(SPECIALIST) …under $formula it points at no other check's method"
  notE "$TMP/note.$formula.nonesuch" '(^|[^[:alnum:]_])P[0-2]([^[:alnum:]_]|$)' "(SPECIALIST) …under $formula it names no P0/P1/P2 grade"
  notF "$TMP/note.$formula.nonesuch" 'Verification' "(SPECIALIST) …under $formula it asks for no Verification line"
done
while IFS= read -r f; do
  notE "$ROOT/$f" "$ASKS" "(SPECIALIST) $f asks for no test run or result" -i
  notF "$ROOT/$f" 'review-test-evidence' "(SPECIALIST) $f carries no evidence block"
  notF "$ROOT/$f" 'hb bash -c' "(SPECIALIST) $f runs no suite"
  notF "$ROOT/$f" 'Verification:' "(SPECIALIST) $f asks for no Verification line"
done < "$TMP/specialist-methods"

echo "# every long command a method runs goes through hb"
hasF "$METHOD" "hb bash -c '<suite>'" "(KEEPALIVE) the correctness suites run through hb"
hasF "$METHOD" "\`hb \"\$GCTK\" rig test --scope affected --command '<the suites>'\`" "(KEEPALIVE) …and a run through the gate does too"
DEMO="$ROOT/skills/review-demo/SKILL.md"
awk '/^ *```/ {f = !f; next} f && /rig-demo-capture\.sh/' "$DEMO" > "$TMP/capture-lines"
[ -s "$TMP/capture-lines" ] && ok "(KEEPALIVE) the demo method runs a capture" || bad "(KEEPALIVE) no capture command found in the demo method"
notE "$TMP/capture-lines" '^[[:space:]]*([^h[:space:]]|h[^b]|hb[^[:space:]])' "(KEEPALIVE) every demo capture runs through hb"

echo "# the rubric's anchors sit in the ledger beside the method, and are inventoried"
LEDGER_REL="$(dirname "$METHOD_REL")/rubric-ledger.md"
LEDGER="$ROOT/$LEDGER_REL"
[ -r "$LEDGER" ] && ok "(RUBRIC) the review-rubric ledger ships beside the correctness method" || bad "(RUBRIC) $LEDGER_REL is missing"
# The reviewer reads the whole method file, comments included, so no anchor,
# nor any other HTML comment, sits in it.
notF "$METHOD" '<!--' "(RUBRIC) the correctness method carries no HTML comment, so no anchor reaches the reviewer"
awk '/^## What to check/ {f = 1; next} /^## / {f = 0} f && /^- \*\*/ {sub(/^- \*\*/, ""); sub(/\*\*.*/, ""); print}' "$METHOD" > "$TMP/dimensions"
[ -s "$TMP/dimensions" ] && ok "(RUBRIC) the What to check list's dimensions are read" || bad "(RUBRIC) no dimension found in the What to check list"
# Each adopted anchor's ledger line ends with a dimension the list names.
grep -E '<!-- [^>]*adopted:[0-9]{4}-[0-9]{2}-[0-9]{2}[^>]*-->' "$LEDGER" > "$TMP/ledger-lines" || true
ANCHORS=$(grep -c . "$TMP/ledger-lines" || true)
UNKNOWN=$(sed 's/.*--> *//' "$TMP/ledger-lines" | grep -vxF -f "$TMP/dimensions" | head -n1 || true)
eq "$UNKNOWN" "" "(RUBRIC) every ledger line names a dimension of the What to check list"
# The dimension each of these anchors amends, as recorded at its adoption: each
# is held to that dimension, not to any.
while read -r rule dim; do
  got=$(grep -F -- "<!-- rule:$rule " "$LEDGER" | sed 's/.*--> *//')
  eq "$got" "$dim" "(RUBRIC) $rule's ledger line names $dim, the dimension it amends"
done <<'MAP'
tk-wamr3 Comments
tk-v32d2u Comments
tk-0rhvews Testing
tk-prvea Contract
MAP
INV=$(bash "$ROOT/assets/scripts/learning-recurrence.sh" --inventory --repo "$ROOT" | grep -c "^$LEDGER_REL	" || true)
eq "$INV" "$ANCHORS" "(RUBRIC) the inventory reads every anchor in the ledger"

echo "# the test evidence block, run as written"
awk '/^# >>> review-test-evidence$/ {f = 1} f {print} /^# <<< review-test-evidence$/ {f = 0}' "$METHOD" > "$TMP/evidence.sh"
[ -s "$TMP/evidence.sh" ] && ok "(EVIDENCE) the block extracts from the method" || bad "(EVIDENCE) the block did not extract"
# A stub gctk answers `rig test --check` with STUB_REC on stdout and STUB_RC as
# its exit, and logs its call and the directory it ran in. A stub gc answers the
# anchor's bd show.
mkdir -p "$TMP/bin" "$TMP/wt"
cat > "$TMP/gctk" <<'GCTK'
#!/usr/bin/env bash
printf '%s|%s\n' "$*" "$(pwd -P)" >> "$STUB_LOG"
[ -n "${STUB_REC:-}" ] && printf '%s\n' "$STUB_REC"
exit "${STUB_RC:-3}"
GCTK
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
printf 'gc %s\n' "$*" >> "$STUB_LOG"
case "$1 $2" in
  "bd show") [ "${STUB_BD_FAIL:-0}" = 1 ] && exit 1; printf '%s\n' "$STUB_ANCHOR_JSON" ;;
  *) exit 1 ;;
esac
GC
chmod +x "$TMP/gctk" "$TMP/bin/gc"
WT_REAL=$(cd "$TMP/wt" && pwd -P)
OID=0123456789abcdef0123456789abcdef01234567
OTHER=fedcba9876543210fedcba9876543210fedcba98
record() { jq -nc --arg r "$1" --arg s "$2" --arg c "$OID" '{check: "test", result: $r, scope: $s, commit: $c, exit_code: (if $r == "pass" then 0 else 1 end), command: "tools/run-tests.sh --affected origin/main"}'; }
# marked <commit> <tracker> <record> : an anchor whose pre-existing mark holds <record>.
marked() { jq -nc --arg c "$1" --arg t "$2" --argjson r "$3" '[{id: "tk-a", metadata: {"rig_check_pre_existing.test": ({commit: $c, record: $r, trackers: [$t]} | tojson)}}]'; }
# evidence <shell> <rc> <record> [anchor json] [review-bead metadata] : the line the block prints
DEFAULT_M='{"anchor_bead":"tk-a"}'
DEFAULT_ANCHOR='[{"id":"tk-a","metadata":{}}]'
evidence() {
  : > "$TMP/stub.log"
  ( cd "$TMP" && PATH="$TMP/bin:$PATH" M="${5-$DEFAULT_M}" REVIEWED_OID="$OID" REVIEW_WT="$TMP/wt" \
      GCTK="${STUB_GCTK-$TMP/gctk}" STUB_LOG="$TMP/stub.log" STUB_RC="$2" STUB_REC="$3" \
      STUB_ANCHOR_JSON="${4-$DEFAULT_ANCHOR}" "$1" "$TMP/evidence.sh" 2>/dev/null )
}
# word <line> : the verdict the line opens with
word() { printf '%s\n' "$1" | sed -nE 's/^(test evidence|no test evidence|recorded fail).*/\1/p'; }
SHELLS="bash"; command -v zsh >/dev/null 2>&1 && SHELLS="bash zsh"
for sh in $SHELLS; do
  OUT=$(evidence "$sh" 0 "$(record pass full)")
  eq "$(word "$OUT")" "test evidence" "(EVIDENCE) $sh: a full-suite pass recorded at the pin is evidence"
  case "$OUT" in *"run no suite"*) ok "(EVIDENCE) $sh: …and reads run no suite" ;; *) bad "(EVIDENCE) $sh: a recorded pass does not read run no suite (got: $OUT)" ;; esac
  grep -qx -- "rig test --check|$WT_REAL" "$TMP/stub.log" \
    && ok "(EVIDENCE) $sh: the record is read with --check, in the review's worktree" \
    || bad "(EVIDENCE) $sh: the record was not read with --check in the review's worktree (log: $(tr '\n' ';' < "$TMP/stub.log"))"
  eq "$(word "$(evidence "$sh" 0 "$(record pass affected)")")" "test evidence" \
     "(EVIDENCE) $sh: a pass of the affected subset is evidence"
  OUT=$(evidence "$sh" 0 "$(record pass none)")
  eq "$(word "$OUT")" "no test evidence" "(EVIDENCE) $sh: a pass that ran nothing is no evidence"
  case "$OUT" in *"run the suites the diff touches through the gate"*) ok "(EVIDENCE) $sh: …and sends the reviewer through the gate" ;; *) bad "(EVIDENCE) $sh: a run of nothing does not send the reviewer through the gate (got: $OUT)" ;; esac
  OUT=$(evidence "$sh" 1 "$(record fail affected)" "$(marked "$OID" tk-t1 "$(record fail affected)")")
  eq "$(word "$OUT")" "test evidence" "(EVIDENCE) $sh: a fail the anchor marks pre-existing at the pin is evidence"
  case "$OUT" in *"tracked by tk-t1; do not run them again"*) ok "(EVIDENCE) $sh: …which names its tracker and is not run again" ;; *) bad "(EVIDENCE) $sh: a pre-existing fail is not told apart (got: $OUT)" ;; esac
  OUT=$(evidence "$sh" 1 "$(record fail full)" "$(marked "$OID" tk-t1 "$(record fail affected)")")
  eq "$(word "$OUT")" "recorded fail" "(EVIDENCE) $sh: a mark holding the record another run replaced does not answer for the fail at the pin"
  OUT=$(evidence "$sh" 1 "$(record fail affected)" "$(marked "$OTHER" tk-t1 "$(record fail affected)")")
  eq "$(word "$OUT")" "recorded fail" "(EVIDENCE) $sh: a pre-existing mark naming another commit does not answer for the pin"
  case "$OUT" in *"command: tools/run-tests.sh --affected origin/main"*"--force"*) ok "(EVIDENCE) $sh: …and the fail is run again with --force, its command named" ;; *) bad "(EVIDENCE) $sh: a recorded fail does not name its command and --force (got: $OUT)" ;; esac
  eq "$(word "$(evidence "$sh" 1 "$(record fail full)" "" '{}')")" "recorded fail" \
     "(EVIDENCE) $sh: a recorded fail on a review bead with no anchor is the commit's"
  eq "$(word "$(STUB_BD_FAIL=1 evidence "$sh" 1 "$(record fail full)" "$(marked "$OID" tk-t1 "$(record fail full)")")")" "recorded fail" \
     "(EVIDENCE) $sh: a recorded fail with an unreadable anchor is the commit's"
  OUT=$(evidence "$sh" 3 "")
  eq "$(word "$OUT")" "no test evidence" "(EVIDENCE) $sh: nothing recorded at the pin is no evidence"
  case "$OUT" in *"run the suites the diff touches through the gate"*) ok "(EVIDENCE) $sh: …and sends the reviewer through the gate" ;; *) bad "(EVIDENCE) $sh: no record does not send the reviewer through the gate (got: $OUT)" ;; esac
  eq "$(word "$(evidence "$sh" 4 "")")" "no test evidence" "(EVIDENCE) $sh: a machine failure is no evidence"
  eq "$(word "$(STUB_GCTK="$TMP/no-gctk" evidence "$sh" 0 "$(record pass full)")")" "no test evidence" \
     "(EVIDENCE) $sh: no gctk binary is no evidence"
done

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
