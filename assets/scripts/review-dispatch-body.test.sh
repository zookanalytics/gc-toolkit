#!/usr/bin/env bash
# Hermetic test for review-dispatch-body.sh — the dispatch note carried by
# every signoff review bead. No live city, Dolt, network, or PRs.
# The method itself lives in formulas/mol-review.toml, attached at dispatch;
# the note's job is to NAME that method, state the recovery path for a bead
# with no poured workflow, and forbid substituting any other method — the
# fan-out drift a bare title invites (a bead with only a title lets the
# reviewer pick a method out of its own catalog).
# Covered:
#   (NAME)      names mol-review and its formula file path.
#   (RECOVER)   states the no-poured-workflow recovery (gc formula show).
#   (NOOTHER)   forbids substituting another review method.
#   (NOFANOUT)  forbids subagents / persona reviewers / parallel passes.
#   (GATE)      one signoff.sh call; never gh pr review --approve.
#   (RC)        exits 0: a dispatch is never blocked on prose.
#   (NOTE)      --note appends a dispatch-context section; absent without it.
#   (CHECK)     --check-name emits a per-check section (correctness default,
#               triage, demo, arch, pm, and a no-method note for an undeclared check).
#   (BOTH)      the formula and check axes coexist in one note.
#   (EXT)       a rig's docs/review-<check>.md at the reviewed commit is
#               appended; absent (or no --reviewed-oid) degrades silently.
#   (EVIDENCE)  only the correctness check settles test evidence or runs a
#               suite, and its review-test-evidence block counts the anchor's
#               self-review stamp only on an exact match in a rig that
#               declares a test command, in bash and in zsh; neither the
#               frame nor mol-review's shared review step runs a suite.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/review-dispatch-body.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-review-dispatch-body-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
# Host signing of commits and tags must not make this suite need a signing agent.
export GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0=commit.gpgsign GIT_CONFIG_VALUE_0=false \
  GIT_CONFIG_KEY_1=tag.gpgsign GIT_CONFIG_VALUE_1=false

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }
# grep -F: the patterns are literal prose/markdown, never regex.
hasF() { grep -qF -- "$2" "$1" && ok "$3" || bad "$3 (missing: $2)"; }
notF() { grep -qF -- "$2" "$1" && bad "$3 (unexpected: $2)" || ok "$3"; }

RC=0
bash "$SCRIPT" > "$TMP/plain.out" 2> "$TMP/plain.err" || RC=$?
eq "$RC" "0" "(RC) exits 0"
eq "$(wc -c < "$TMP/plain.err" | tr -d ' ')" "0" "(RC) writes nothing to stderr"

OUT="$TMP/plain.out"
hasF "$OUT" 'mol-review' "(NAME) names the mol-review formula"
hasF "$OUT" 'formulas/mol-review.toml' "(NAME) names the formula's file path"
hasF "$OUT" 'gc formula show mol-review' "(RECOVER) states the no-poured-workflow recovery command"
hasF "$OUT" 'REVIEW_BEAD is this bead itself' "(RECOVER) tells the recovery agent the bead IS the review bead (no convoy to derive from)"
hasF "$OUT" 'Do not substitute any other review method' "(NOOTHER) forbids substituting another method"
hasF "$OUT" 'No fan-out' "(NOFANOUT) forbids fan-out"
hasF "$OUT" 'no persona reviewers' "(NOFANOUT) forbids persona reviewers"
hasF "$OUT" 'no parallel review pass' "(NOFANOUT) forbids a parallel review pass"
hasF "$OUT" 'exactly once' "(GATE) states the one-signoff-call rule"
hasF "$OUT" 'signoff.sh --review-bead' "(GATE) names the signoff.sh call shape"
hasF "$OUT" 'gh pr review --approve' "(GATE) addresses --approve (never used)"

echo "# --note"
bash "$SCRIPT" --note 'STALE-NOTE-a1b2: the head moved.' > "$TMP/note.out" 2>/dev/null
hasF "$TMP/note.out" '## Context from the dispatch' "(NOTE) --note adds the dispatch-context section"
hasF "$TMP/note.out" 'STALE-NOTE-a1b2: the head moved.' "(NOTE) --note text reaches the body"
notF "$TMP/plain.out" '## Context from the dispatch' "(NOTE) the section is absent without --note"

echo "# the named formula really ships in this pack"
ROOT="$(cd "$HERE/../.." && pwd)"
[ -r "$ROOT/formulas/mol-review.toml" ] \
  && ok "(NAME) formulas/mol-review.toml exists where the note points" \
  || bad "(NAME) formulas/mol-review.toml missing — the note names a formula the pack does not ship"

echo "# a non-mol-review formula (the two-lane quorum) gets a note that defers to its steps"
bash "$SCRIPT" --formula mol-review-quorum-signoff > "$TMP/quorum.out" 2>/dev/null
QOUT="$TMP/quorum.out"
hasF "$QOUT" 'formulas/mol-review-quorum-signoff.toml' "(NAME) names the dispatched formula's file path"
hasF "$QOUT" 'gc formula show mol-review-quorum-signoff' "(RECOVER) recovery command names the dispatched formula"
hasF "$QOUT" 'which of its steps makes the single verdict' "(DEFER) defers the verdict path to the formula's steps"
notF "$QOUT" 'single pass' "(DEFER) does not assert a single-agent pass for a fan-out formula"
notF "$QOUT" 'no parallel review pass' "(DEFER) does not forbid the parallel pass the quorum performs"
notF "$QOUT" 'signoff.sh --review-bead' "(DEFER) does not tell a lane to call signoff itself — the formula's synthesis step owns that"
notF "$QOUT" '__FORMULA__' "(DEFER) the formula placeholder is substituted, not left raw"
RCQ=0; bash "$SCRIPT" --formula mol-review-quorum-signoff >/dev/null 2>&1 || RCQ=$?
eq "$RCQ" "0" "(RC) a non-default formula still exits 0"

echo "# the check-name axis: a check section names the concern, orthogonal to the formula"
hasF "$OUT" '## Check: `correctness`' "(CHECK) the default check is correctness"
notF "$OUT" '## Check: `codex`' "(CHECK) the standing check is named correctness, not codex"
bash "$SCRIPT" --check-name triage > "$TMP/tri.out" 2>/dev/null
hasF "$TMP/tri.out" '## Check: `triage`' "(CHECK) --check-name triage names the triage check"
hasF "$TMP/tri.out" '--add-gates' "(CHECK) triage names the widening verdict call"
hasF "$TMP/tri.out" 'Adding nothing is the expected common case' "(CHECK) triage states the common no-op case"
hasF "$TMP/tri.out" '--reopen <lanes>|none --round-reason <why> [--dismiss-approval]' "(CHECK) triage names the bring-current round ruling it carries on the same call"
hasF "$TMP/tri.out" 'bring-current-audit.sh render --anchor <anchor>' "(CHECK) …and where the round's account is read"
bash "$SCRIPT" --check-name demo > "$TMP/demo.out" 2>/dev/null
hasF "$TMP/demo.out" '## Check: `demo`' "(CHECK) --check-name demo names the demo check"
hasF "$TMP/demo.out" 'skills/review-demo/SKILL.md' "(CHECK) demo names its method skill"
hasF "$TMP/demo.out" 'needs a visual to be understood' "(CHECK) demo decides need first"
hasF "$TMP/demo.out" 'attach nothing' "(CHECK) demo approves a no-need change with a note and no attachment"
hasF "$TMP/demo.out" 'never a block' "(CHECK) demo never blocks on a visual the city cannot produce"
hasF "$TMP/demo.out" '--visual none|repo-artifact|screenshot|video' "(CHECK) demo names the verdict call that records its decision"
notF "$TMP/demo.out" 'that is a finding against the change, not a' "(CHECK) an unrecordable demo is no longer a finding against the change"
[ -r "$(cd "$HERE/../.." && pwd)/skills/review-demo/SKILL.md" ] \
  && ok "(CHECK) the demo method skill ships where the note points" \
  || bad "(CHECK) skills/review-demo/SKILL.md missing — the note names a method the pack does not ship"
bash "$SCRIPT" --check-name pm > "$TMP/pm.out" 2>/dev/null
hasF "$TMP/pm.out" '## Check: `pm`' "(CHECK) --check-name pm names the pm check"
hasF "$TMP/pm.out" 'skills/review-pm/SKILL.md' "(CHECK) pm names its method skill"
hasF "$TMP/pm.out" 'product lens' "(CHECK) pm carries the product lens"
hasF "$TMP/pm.out" 'needs a visual, and delivering it, is `demo`'"'"'s' "(CHECK) pm leaves the visual decision to demo"
bash "$SCRIPT" --check-name arch > "$TMP/arch.out" 2>/dev/null
hasF "$TMP/arch.out" '## Check: `arch`' "(CHECK) --check-name arch names the arch check"
hasF "$TMP/arch.out" 'The Architect' "(CHECK) arch names the Architect persona"
hasF "$TMP/arch.out" 'docs/architecture.md' "(CHECK) arch reads the architecture reference docs before judging"
hasF "$TMP/arch.out" 'never edit' "(CHECK) arch enforces and never edits"
hasF "$TMP/arch.out" 'skills/review-arch/SKILL.md' "(CHECK) arch points at its method skill, the way demo and triage do"
notF "$TMP/arch.out" 'No generic method is declared' "(CHECK) a declared check gets its method, not the no-method note"
bash "$SCRIPT" --check-name nonesuch > "$TMP/undeclared.out" 2>/dev/null
hasF "$TMP/undeclared.out" 'No generic method is declared' "(CHECK) an undeclared check gets the no-method note, never a guess"
RCC=0; bash "$SCRIPT" --check-name nonesuch >/dev/null 2>&1 || RCC=$?
eq "$RCC" "0" "(RC) an undeclared check still exits 0"

echo "# test evidence: only the correctness check settles it or runs a suite"
notF "$OUT" 'run the tests yourself' "(EVIDENCE) the frame does not tell every check to run the tests"
hasF "$OUT" 'self_review_passed_sha' "(EVIDENCE) correctness reads the self-review stamp"
hasF "$OUT" '# >>> review-test-evidence' "(EVIDENCE) correctness carries the evidence block"
for c in tri demo pm arch undeclared; do
  notF "$TMP/$c.out" 'review-test-evidence' "(EVIDENCE) $c carries no evidence block"
  notF "$TMP/$c.out" 'hb bash -c' "(EVIDENCE) $c runs no suite"
done
# mol-review's review step is shared by every check, so it runs no suite itself
# and leaves that to the check section.
REVIEW_STEP="$TMP/review-step.txt"
awk '/^id = "review"$/ {f = 1} f && /^\[\[steps\]\]$/ {exit} f' "$ROOT/formulas/mol-review.toml" > "$REVIEW_STEP"
hasF "$REVIEW_STEP" 'title = "' "(EVIDENCE) the review step is found in formulas/mol-review.toml"
notF "$REVIEW_STEP" 'run the tests' "(EVIDENCE) the shared review step neither promises nor runs the tests"
notF "$REVIEW_STEP" 'Run the tests' "(EVIDENCE) the shared review step has no step that runs the tests"
notF "$REVIEW_STEP" 'run the suites' "(EVIDENCE) the shared review step runs no suite"
hasF "$REVIEW_STEP" 'The check section of the' "(EVIDENCE) the shared review step leaves test runs to the check section"

# The block runs as written against a stub gc: bd show answers the anchor, and
# formula show answers the rig's mol-polecat-work vars.
awk '/^# >>> review-test-evidence$/ {f = 1} f {print} /^# <<< review-test-evidence$/ {f = 0}' "$OUT" > "$TMP/evidence.sh"
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

echo "# both axes coexist: a quorum formula plus a named check emits both sections"
bash "$SCRIPT" --formula mol-review-quorum-signoff --check-name triage > "$TMP/both.out" 2>/dev/null
hasF "$TMP/both.out" 'formulas/mol-review-quorum-signoff.toml' "(BOTH) the formula frame is the quorum's"
hasF "$TMP/both.out" '## Check: `triage`' "(BOTH) the check section is triage's"

echo "# composition: a rig extension read from the reviewed commit is appended; absent degrades"
REPO="$TMP/repo"; mkdir -p "$REPO/docs"
git -C "$REPO" init -q
git -C "$REPO" config user.email t@t; git -C "$REPO" config user.name t
printf 'RIG-EXT-MARK: the Architect reads architecture.md first.\n' > "$REPO/docs/review-arch.md"
git -C "$REPO" add docs/review-arch.md
git -C "$REPO" commit -qm ext
SHA=$(git -C "$REPO" rev-parse HEAD)
( cd "$REPO" && bash "$SCRIPT" --check-name arch --reviewed-oid "$SHA" ) > "$TMP/ext.out" 2>/dev/null
hasF "$TMP/ext.out" 'Rig extension' "(EXT) an extension present at the reviewed commit is appended"
hasF "$TMP/ext.out" 'RIG-EXT-MARK: the Architect reads architecture.md first.' "(EXT) the extension content reaches the note"
( cd "$REPO" && bash "$SCRIPT" --check-name demo --reviewed-oid "$SHA" ) > "$TMP/noext.out" 2>/dev/null
notF "$TMP/noext.out" 'Rig extension' "(EXT) a check with no extension file degrades — no extension section"
notF "$OUT" 'Rig extension' "(EXT) no --reviewed-oid means no extension read at all"

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
