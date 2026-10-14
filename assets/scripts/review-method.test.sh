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
#                method's What to check list, or a signoff.sh flag that only a
#                check's method passes; mol-review names no severity at all.
#   (METHOD)     the correctness row points at its own method file, which
#                carries the What to check list, the severity ladder, the
#                review-test-evidence block and the Verification line.
#   (QUORUM)     the quorum's lanes apply the check's method, naming the
#                correctness method, and not mol-review's review step.
#   (SPECIALIST) no other check's method file asks for test results or runs a
#                suite.
#   (KEEPALIVE)  every long command a method runs goes through hb: the
#                correctness suites and the demo capture.
#   (RUBRIC)     the learning loop's review-rubric anchors sit above the
#                dimension each amends, and the inventory reads every one.
#   (EVIDENCE)   the review-test-evidence block counts the anchor's self-review
#                stamp only on an exact match in a rig that declares a test
#                command, in bash and in zsh.
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

echo "# the flags only a check's method passes to signoff.sh"
# A check-specific flag is one signoff.sh takes, a method file or dispatch arm
# names, and the lifecycle's own verdict call does not carry.
grep -oE '^    --[a-z][a-z-]*\)' "$ROOT/assets/scripts/signoff.sh" | tr -d ' )' | sort -u > "$TMP/signoff-flags"
grep -F '/signoff.sh" --review-bead' "$LIFE" | grep -oE -- '--[a-z][a-z-]*' | sort -u > "$TMP/call-flags"
: > "$TMP/method-text"
"$CHECKS" --file "$INDEX" | while IFS="$(printf '\t')" read -r name method _; do
  bash "$BODY" --check-name "$name" >> "$TMP/method-text"
  printf '%s\n' "$method" | awk '{n = split($0, m, / [+] /); for (i = 1; i <= n; i++) print m[i]}' \
    | while IFS= read -r f; do cat "$ROOT/$f" >> "$TMP/method-text"; done
done
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
  local d f
  while IFS= read -r d; do
    notF "$1" "**$d**" "(NEUTRAL) $2 carries no '$d' dimension"
  done < "$TMP/dimensions"
  while IFS= read -r f; do
    notE "$1" "(^|[^[:alnum:]-])$f([^[:alnum:]-]|$)" "(NEUTRAL) $2 names no check-specific flag $f"
  done < "$TMP/check-flags"
}
neutral "$TMP/life.txt" "mol-review"
notE "$TMP/life.txt" 'severity' "(NEUTRAL) mol-review names no severity" -i
notE "$LIFE" 'adopted:' "(RUBRIC) mol-review carries no adopted rubric anchor"
# The quorum's lanes record a severity key, the lane schema's, so only the
# grades themselves are held out of it.
neutral "$TMP/quorum.txt" "the quorum formula"

echo "# the quorum's lanes apply the check's method"
for lane in review-lane-one review-lane-two; do
  hasF "$TMP/quorum.$lane.txt" "$METHOD_REL" "(QUORUM) $lane names the correctness method"
  notF "$TMP/quorum.$lane.txt" "'s \`review\` step" "(QUORUM) $lane points at no mol-review review step"
done

echo "# no other check is asked for test results"
"$CHECKS" --file "$INDEX" | while IFS="$(printf '\t')" read -r name method _; do
  [ "$name" = correctness ] && continue
  printf '%s\n' "$method" | awk '{n = split($0, m, / [+] /); for (i = 1; i <= n; i++) print m[i]}'
done | sort -u > "$TMP/specialist-methods"
[ -s "$TMP/specialist-methods" ] && ok "(SPECIALIST) the index declares other checks" || bad "(SPECIALIST) no other check is declared"
while IFS= read -r f; do
  notF "$ROOT/$f" 'review-test-evidence' "(SPECIALIST) $f carries no evidence block"
  notF "$ROOT/$f" 'hb bash -c' "(SPECIALIST) $f runs no suite"
  notF "$ROOT/$f" 'Verification:' "(SPECIALIST) $f asks for no Verification line"
done < "$TMP/specialist-methods"

echo "# every long command a method runs goes through hb"
hasF "$METHOD" "hb bash -c '<suite>'" "(KEEPALIVE) the correctness suites run through hb"
DEMO="$ROOT/skills/review-demo/SKILL.md"
awk '/^ *```/ {f = !f; next} f && /rig-demo-capture\.sh/' "$DEMO" > "$TMP/capture-lines"
[ -s "$TMP/capture-lines" ] && ok "(KEEPALIVE) the demo method runs a capture" || bad "(KEEPALIVE) no capture command found in the demo method"
notE "$TMP/capture-lines" '^[[:space:]]*([^h[:space:]]|h[^b]|hb[^[:space:]])' "(KEEPALIVE) every demo capture runs through hb"

echo "# the rubric's anchors sit on the dimensions they amend, and are inventoried"
# Each anchor is followed, past any further anchors, by a dimension bullet.
awk '
  /^<!-- rule:/ && /adopted:/ && !/rule:<pattern-bead>/ { n++; pending = 1; next }
  pending && /^<!-- rule:/ { next }
  pending { if ($0 !~ /^- \*\*/) bad++; pending = 0 }
  END { printf "%d %d\n", n, bad + pending }
' "$METHOD" > "$TMP/anchors"
read -r ANCHORS MISPLACED < "$TMP/anchors"
eq "$MISPLACED" "0" "(RUBRIC) every adopted anchor sits immediately above a dimension"
INV=$(bash "$ROOT/assets/scripts/learning-recurrence.sh" --inventory --repo "$ROOT" | grep -c "^$METHOD_REL	" || true)
eq "$INV" "$ANCHORS" "(RUBRIC) the inventory reads every anchor in the correctness method"

echo "# the test evidence block, run as written"
awk '/^# >>> review-test-evidence$/ {f = 1} f {print} /^# <<< review-test-evidence$/ {f = 0}' "$METHOD" > "$TMP/evidence.sh"
[ -s "$TMP/evidence.sh" ] && ok "(EVIDENCE) the block extracts from the method" || bad "(EVIDENCE) the block did not extract"
# A stub gc: bd show answers the anchor, and formula show answers the rig's
# mol-polecat-work vars.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_LOG"
case "$1 $2" in
  "bd show") [ "${STUB_BD_FAIL:-0}" = 1 ] && exit 1; printf '%s\n' "$STUB_ANCHOR_JSON" ;;
  "formula show") [ "${STUB_FORMULA_FAIL:-0}" = 1 ] && exit 1; printf '%s\n' "$STUB_FORMULA_JSON" ;;
  *) exit 1 ;;
esac
GC
chmod +x "$TMP/bin/gc"
OID=0123456789abcdef0123456789abcdef01234567
DECLARES='{"ok":true,"vars":[{"name":"affected_tests_command","default":"","rig_default":"tools/run-tests.sh x"},{"name":"test_command","default":"","rig_default":null}]}'
# A rig's own empty value wins over a formula default, the way the self-review renders it.
DECLARES_NONE='{"ok":true,"vars":[{"name":"affected_tests_command","default":"","rig_default":null},{"name":"test_command","default":"make test","rig_default":""}]}'
stamped() { printf '[{"id":"tk-a","metadata":{"self_review_passed_sha":"%s"}}]' "$1"; }
# evidence <shell> <review-bead metadata> <anchor json> <formula json> [GC_RIG] : the block's verdict word
evidence() {
  : > "$TMP/stub.log"
  ( PATH="$TMP/bin:$PATH" M="$2" REVIEWED_OID="$OID" GC_RIG="${5-gc-toolkit}" STUB_LOG="$TMP/stub.log" \
      STUB_ANCHOR_JSON="$3" STUB_FORMULA_JSON="$4" "$1" "$TMP/evidence.sh" 2>/dev/null ) | sed -nE 's/^(test evidence|no test evidence).*/\1/p'
}
SHELLS="bash"; command -v zsh >/dev/null 2>&1 && SHELLS="bash zsh"
for sh in $SHELLS; do
  eq "$(evidence "$sh" '{"anchor_bead":"tk-a"}' "$(stamped "$OID")" "$DECLARES")" "test evidence" \
     "(EVIDENCE) $sh: a stamp on the reviewed commit in a rig that declares a test command is evidence"
  grep -qx -- 'formula show mol-polecat-work --rig=gc-toolkit --json' "$TMP/stub.log" \
    && ok "(EVIDENCE) $sh: the rig's declared commands are read with --rig=<rig> as one word" \
    || bad "(EVIDENCE) $sh: the formula read did not pass --rig=gc-toolkit (log: $(tr '\n' ';' < "$TMP/stub.log"))"
  eq "$(evidence "$sh" '{"anchor_bead":"tk-a"}' "$(stamped "$OID")" "$DECLARES_NONE")" "no test evidence" \
     "(EVIDENCE) $sh: a rig whose own values declare no test command gives no evidence"
  eq "$(evidence "$sh" '{"anchor_bead":"tk-a"}' "$(stamped fedcba9876543210fedcba9876543210fedcba98)" "$DECLARES")" "no test evidence" \
     "(EVIDENCE) $sh: a stamp naming another commit is no evidence"
  eq "$(evidence "$sh" '{"anchor_bead":"tk-a"}' "$(stamped "${OID:0:12}")" "$DECLARES")" "no test evidence" \
     "(EVIDENCE) $sh: a short sha is no exact match, so no evidence"
  eq "$(evidence "$sh" '{}' "$(stamped "$OID")" "$DECLARES")" "no test evidence" \
     "(EVIDENCE) $sh: a review bead with no anchor gives no evidence"
  eq "$(STUB_BD_FAIL=1 evidence "$sh" '{"anchor_bead":"tk-a"}' "$(stamped "$OID")" "$DECLARES")" "no test evidence" \
     "(EVIDENCE) $sh: an unreadable anchor gives no evidence"
  eq "$(STUB_FORMULA_FAIL=1 evidence "$sh" '{"anchor_bead":"tk-a"}' "$(stamped "$OID")" "$DECLARES")" "no test evidence" \
     "(EVIDENCE) $sh: unreadable rig commands give no evidence"
  evidence "$sh" '{"anchor_bead":"tk-a"}' "$(stamped "$OID")" "$DECLARES" "" >/dev/null
  grep -qx -- 'formula show mol-polecat-work --json' "$TMP/stub.log" \
    && ok "(EVIDENCE) $sh: with GC_RIG unset the formula is read with no --rig" \
    || bad "(EVIDENCE) $sh: with GC_RIG unset the formula read was not bare (log: $(tr '\n' ';' < "$TMP/stub.log"))"
done

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
