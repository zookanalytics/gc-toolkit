#!/usr/bin/env bash
# Hermetic test for review-dispatch-body.sh — the dispatch note carried by
# every signoff review bead. No live city, Dolt, network, or PRs.
# The lifecycle lives in formulas/mol-review.toml, attached at dispatch, and
# each check's method in the skill its check section names; the note's job is
# to NAME both, state the recovery path for a bead with no poured workflow, and
# forbid substituting any other method — the fan-out drift a bare title invites
# (a bead with only a title lets the reviewer pick a method out of its own
# catalog).
# Covered:
#   (NAME)      names mol-review and its formula file path.
#   (RECOVER)   states the no-poured-workflow recovery (gc formula show).
#   (NOOTHER)   forbids substituting another review method: the one skill to
#               load is the method the check section names.
#   (NOFANOUT)  forbids subagents / persona reviewers / parallel passes.
#   (GATE)      one signoff.sh call; never gh pr review --approve.
#   (RC)        exits 0: a dispatch is never blocked on prose.
#   (NOTE)      --note appends a dispatch-context section; absent without it.
#   (CHECK)     --check-name emits a per-check section (correctness default,
#               triage, demo, arch, pm, and a no-method note for a check
#               this pack ships no skill for: its purpose, printed from the
#               reviewed commit's index, or the declared-nowhere note when
#               no row declares it).
#   (SKILL)     every declared check's section names its method skill, which
#               the reviewer loads from its skill catalog, and names no method
#               path to read from a checkout; the pack ships each named skill
#               under that name.
#   (ONCE)      a declared check's section is the line naming its skill, plus
#               the shared stance for a specialist, and repeats nothing the
#               skill says.
#   (METHOD)    the skill a declared check's note names carries what that
#               check judges and the verdict call that records it.
#   (BOTH)      the formula and check axes coexist in one note.
#   (EXT)       a rig's docs/review-<check>.md at the reviewed commit is
#               appended; absent (or no --reviewed-oid) degrades silently.
#   (EVIDENCE)  no check's section carries a test run: the correctness
#               method file does (review-method.test.sh), and the frame
#               presumes none.
#   (CASE)      a check is known by its name case-folded, the rule the index's
#               resolver matches a check_set token by: the token the resolver
#               hands on, in the case the check_set wrote it, gets the note its
#               folded name gets, and an index row written in another case
#               still declares its check.
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
hasF "$OUT" 'Load the method skill the' "(NOOTHER) …so the one skill to load is the method the check section names"
hasF "$OUT" 'no other review-shaped skill out of your' "(NOOTHER) …and no other review-shaped skill from the catalog"
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
for c in triage demo pm arch; do
  bash "$SCRIPT" --check-name "$c" > "$TMP/$c.out" 2>/dev/null
  hasF "$TMP/$c.out" "## Check: \`$c\`" "(CHECK) --check-name $c names the $c check"
done
hasF "$TMP/arch.out" 'never edit' "(CHECK) a specialist enforces and never edits, by the shared stance"
notF "$TMP/arch.out" 'this pack ships no method' "(CHECK) a declared check gets its method, not the no-method note"
notF "$TMP/arch.out" 'declared nowhere' "(CHECK) …nor the declared-nowhere note"

echo "# a declared check's section names its skill and repeats nothing the skill says"
# section <note> : the check section, from its heading to the next rule or rig
# extension heading, with the shared specialist stance taken out.
section() {
  awk '/^## Check: / {f = 1} f && (/^---$/ || /^### Rig extension/) {exit} f' "$1" \
    | awk '/^\*\*The specialist stance\.\*\*/ {s = 1} s && /^$/ {s = 0; next} !s'
}
for c in correctness triage demo arch pm; do
  for formula in mol-review mol-review-quorum-signoff; do
    bash "$SCRIPT" --formula "$formula" --check-name "$c" > "$TMP/once.$formula.$c.out" 2>/dev/null
    printf '## Check: `%s`\n\n**Your method is the `gc-toolkit.review-%s` skill.**\nLoad it from your skill catalog and apply it; a copy in the review worktree is\nthe change under review, not your method.\n' "$c" "$c" > "$TMP/once.$c.want"
    section "$TMP/once.$formula.$c.out" > "$TMP/once.$formula.$c.got"
    cmp -s "$TMP/once.$formula.$c.got" "$TMP/once.$c.want" \
      && ok "(ONCE) the $c section under $formula is the line naming its skill" \
      || bad "(ONCE) the $c section under $formula carries more than its skill line: $(diff "$TMP/once.$c.want" "$TMP/once.$formula.$c.got" | sed -n 's/^> //p' | head -1)"
  done
done

echo "# the skill the note names carries what its check judges and records"
# flat <file> : the file's prose on one line, so a pinned phrase may wrap.
flat() { tr '\n' ' ' < "$1" | tr -s ' '; }
for c in correctness triage demo arch pm; do
  flat "$ROOT/skills/review-$c/SKILL.md" > "$TMP/$c.skill"
done
hasF "$TMP/correctness.skill" 'correct and safe as merged' "(METHOD) the correctness skill asks whether the change is correct and safe as merged"
hasF "$TMP/triage.skill" '`--add-gates demo,arch`' "(METHOD) the triage skill names the widening verdict call, for one check or several"
hasF "$TMP/triage.skill" 'only a triage verdict may add one' "(METHOD) …and that only a triage verdict widens"
hasF "$TMP/triage.skill" 'Adding nothing is the expected common case' "(METHOD) …and the common no-op case"
hasF "$TMP/triage.skill" '--reopen correctness --round-reason "<why>" [--dismiss-approval]' "(METHOD) …and the bring-current round ruling it carries on the same call"
hasF "$TMP/triage.skill" '(`--reopen none`)' "(METHOD) …which may reopen nothing"
hasF "$TMP/triage.skill" '"$(gc <binding> scripts-dir)/bring-current-audit.sh" render --anchor "$ANCHOR" --as comment' "(METHOD) …and where the round's account is read, through the pack's own copy"
hasF "$TMP/triage.skill" 'The raw record keeps what that line leaves out' "(METHOD) …and its raw record, which keeps what a routine entry's line leaves out"
hasF "$TMP/triage.skill" "a call that is the operator's to make" "(METHOD) …and lifts the approval only for a call that is the operator's"
notF "$TMP/triage.skill" 'whether the human approval still covers it' "(METHOD) …not whenever the approval predates the round"
hasF "$TMP/demo.skill" 'needs a visual to be understood' "(METHOD) the demo skill decides need first"
hasF "$TMP/demo.skill" 'attach nothing' "(METHOD) …approves a no-need change with a note and no attachment"
hasF "$TMP/demo.skill" 'This never blocks.' "(METHOD) …never blocks on a visual the city cannot produce"
hasF "$TMP/demo.skill" '`--visual` carries the decision' "(METHOD) …names the verdict flag that records its decision"
hasF "$TMP/demo.skill" '`--visual-fallback-from <the modality that fits>`' "(METHOD) …and the flag that records a fallback"
notF "$TMP/demo.skill" 'that is a finding against the change, not a' "(METHOD) …and an unrecordable demo is no finding against the change"
hasF "$TMP/pm.skill" 'product lens' "(METHOD) the pm skill carries the product lens"
hasF "$TMP/pm.skill" '## The visual is the `demo` check' "(METHOD) …and leaves the visual decision to demo"
hasF "$TMP/arch.skill" 'You are the Architect' "(METHOD) the arch skill names the Architect"
hasF "$TMP/arch.skill" 'docs/architecture.md' "(METHOD) …and reads the architecture reference docs before judging"
hasF "$TMP/arch.skill" "This lens holds new surface to the platform's own documentation instead." "(METHOD) …holds new surface to the platform's own docs, not the repo's account of the platform"
hasF "$TMP/arch.skill" 'A converter is a finding on sight.' "(METHOD) …makes a converter between a repo noun and a platform noun a finding"
hasF "$TMP/arch.skill" '## When triage adds it' "(METHOD) …says when triage adds the arch check"
hasF "$TMP/arch.skill" 'The first two make the check mandatory' "(METHOD) …and makes new operational surface and a touched warrant mandatory triggers"
hasF "$TMP/arch.skill" 'neither are tests or the fixtures they use' "(METHOD) …and leaves tests out of operational surface, so a test addition does not force the check"
# Run outside any repository, so no index declares the check.
( cd "$TMP" && env -u GC_RIG_ROOT bash "$SCRIPT" --check-name nonesuch ) > "$TMP/undeclared.out" 2>/dev/null
hasF "$TMP/undeclared.out" '`nonesuch` check, so nothing says what it judges' "(CHECK) a check no index row declares gets the declared-nowhere note, never a guess"
hasF "$TMP/undeclared.out" '`--needs-you` on the verdict call saying the check is declared nowhere' "(CHECK) …which approves and puts the check set to the operator"
notF "$TMP/undeclared.out" 'review-correctness' "(CHECK) …and names no other check's method"
notF "$TMP/undeclared.out" 'docs/review-' "(CHECK) …and is not pointed at a rig extension, which a rig need not keep"
RCC=0; bash "$SCRIPT" --check-name nonesuch >/dev/null 2>&1 || RCC=$?
eq "$RCC" "0" "(RC) an undeclared check still exits 0"

echo "# correctness names its method file, which carries the test evidence and every suite run"
hasF "$OUT" 'Your method is the `gc-toolkit.review-correctness` skill.' "(CHECK) correctness names its method skill, the way the other checks do"
[ -r "$ROOT/skills/review-correctness/SKILL.md" ] \
  && ok "(CHECK) the correctness method skill ships where the note points" \
  || bad "(CHECK) skills/review-correctness/SKILL.md missing — the note names a method the pack does not ship"
notF "$OUT" 'run the tests yourself' "(EVIDENCE) the frame does not tell every check to run the tests"
for c in plain triage demo pm arch undeclared; do
  notF "$TMP/$c.out" 'review-test-evidence' "(EVIDENCE) the $c note carries no evidence block"
  notF "$TMP/$c.out" 'hb bash -c' "(EVIDENCE) the $c note runs no suite"
done

echo "# every declared check names its method skill, loaded from the skill catalog"
for c in correctness triage demo arch pm; do
  for formula in mol-review mol-review-quorum-signoff; do
    bash "$SCRIPT" --formula "$formula" --check-name "$c" > "$TMP/skill.$formula.$c.out" 2>/dev/null
    hasF "$TMP/skill.$formula.$c.out" "Your method is the \`gc-toolkit.review-$c\` skill." "(SKILL) the $c note under $formula names its method skill"
    hasF "$TMP/skill.$formula.$c.out" 'Load it from your skill catalog and apply it' "(SKILL) …which the reviewer loads from its skill catalog"
    notF "$TMP/skill.$formula.$c.out" 'skills/review-' "(SKILL) …and names no method path a reviewer would read from a checkout"
    notF "$TMP/skill.$formula.$c.out" '>>> review-method-read' "(SKILL) …and carries no read block"
  done
  # gascity links a pack skill into the catalog as gc-toolkit.<directory>, and
  # codex lists it by its frontmatter name, so the two must agree for the
  # name the note gives to reach the skill under either listing.
  name=$(awk '/^---$/ {n++; next} n == 1 && /^name:/ {sub(/^name:[[:space:]]*/, ""); print; exit}' "$ROOT/skills/review-$c/SKILL.md" 2>/dev/null)
  eq "$name" "review-$c" "(SKILL) the pack ships skills/review-$c under the name the note gives it"
done
notF "$TMP/undeclared.out" 'Your method is the' "(SKILL) an undeclared check names no method skill"

echo "# both axes coexist: a quorum formula plus a named check emits both sections"
bash "$SCRIPT" --formula mol-review-quorum-signoff --check-name triage > "$TMP/both.out" 2>/dev/null
hasF "$TMP/both.out" 'formulas/mol-review-quorum-signoff.toml' "(BOTH) the formula frame is the quorum's"
hasF "$TMP/both.out" '## Check: `triage`' "(BOTH) the check section is triage's"

echo "# composition: a rig extension read from the reviewed commit is appended; absent degrades"
REPO="$TMP/repo"; mkdir -p "$REPO/docs"
git -C "$REPO" init -q
git -C "$REPO" config user.email t@t; git -C "$REPO" config user.name t
printf 'RIG-EXT-MARK: the Architect reads architecture.md first.\n' > "$REPO/docs/review-arch.md"
printf '[checks.security]\nmethod = "docs/review-security.md"\npurpose = "PURPOSE-MARK: secrets stay out of logs."\nphase = "pre-open"\n' > "$REPO/review-checks.toml"
git -C "$REPO" add docs/review-arch.md review-checks.toml
git -C "$REPO" commit -qm ext
SHA=$(git -C "$REPO" rev-parse HEAD)
( cd "$REPO" && bash "$SCRIPT" --check-name arch --reviewed-oid "$SHA" ) > "$TMP/ext.out" 2>/dev/null
hasF "$TMP/ext.out" 'Rig extension' "(EXT) an extension present at the reviewed commit is appended"
hasF "$TMP/ext.out" 'RIG-EXT-MARK: the Architect reads architecture.md first.' "(EXT) the extension content reaches the note"
( cd "$REPO" && bash "$SCRIPT" --check-name demo --reviewed-oid "$SHA" ) > "$TMP/noext.out" 2>/dev/null
notF "$TMP/noext.out" 'Rig extension' "(EXT) a check with no extension file degrades — no extension section"
notF "$OUT" 'Rig extension' "(EXT) no --reviewed-oid means no extension read at all"

echo "# a check the reviewed repo's index declares and this pack ships no method for"
# The working tree's row differs from the reviewed commit's: the commit's is read.
sed 's/PURPOSE-MARK/WORKTREE-MARK/' "$REPO/review-checks.toml" > "$TMP/worktree-index" && cp "$TMP/worktree-index" "$REPO/review-checks.toml"
( cd "$REPO" && env -u GC_RIG_ROOT bash "$SCRIPT" --check-name security --reviewed-oid "$SHA" ) > "$TMP/indexed.out" 2>/dev/null
hasF "$TMP/indexed.out" 'declares the `security` check,' "(CHECK) a check only the reviewed repo's index declares is named as that case"
hasF "$TMP/indexed.out" '> PURPOSE-MARK: secrets stay out of logs.' "(CHECK) …with its purpose printed from its row at the reviewed commit"
notF "$TMP/indexed.out" 'WORKTREE-MARK' "(CHECK) …never from the working tree"
hasF "$TMP/indexed.out" 'coverage line that the pack has no method for this' "(CHECK) …and the coverage line says the pack has no method for it"
notF "$TMP/indexed.out" 'declared nowhere' "(CHECK) …and it is not the declared-nowhere note"

echo "# a check is known by its name case-folded, whatever case its check_set token is in"
# gate-ensure.sh hands the dispatch body each token the index's resolver emits,
# and the resolver emits a token in the case the anchor's check_set wrote it.
TOK=$(env -u GC_REVIEW_CHECKS_INDEX bash "$HERE/review-checks.sh" --resolve --check-set Correctness --through pre-open --file "$ROOT/review-checks.toml" 2>/dev/null) || TOK=""
eq "$TOK" "Correctness" "(CASE) the resolver hands on the check_set token Correctness as written"
for formula in mol-review mol-review-quorum-signoff; do
  bash "$SCRIPT" --formula "$formula" --check-name "$TOK" > "$TMP/case.$formula.tok" 2>/dev/null
  bash "$SCRIPT" --formula "$formula" --check-name correctness > "$TMP/case.$formula.correctness" 2>/dev/null
  cmp -s "$TMP/case.$formula.tok" "$TMP/case.$formula.correctness" \
    && ok "(CASE) under $formula the resolver's token Correctness gets correctness's note" \
    || bad "(CASE) under $formula the resolver's token Correctness gets another note: $(diff "$TMP/case.$formula.correctness" "$TMP/case.$formula.tok" | sed -n 's/^> //p' | head -1)"
  notF "$TMP/case.$formula.tok" 'declared nowhere' "(CASE) …under $formula it is never the declared-nowhere note"
done
for c in correctness triage demo arch pm; do
  up=$(printf '%s' "$c" | tr '[:lower:]' '[:upper:]')
  # Output names differ beyond case: the filesystem may fold case.
  ( cd "$REPO" && bash "$SCRIPT" --check-name "$up" --reviewed-oid "$SHA" ) > "$TMP/case.upper.$c.out" 2>/dev/null
  ( cd "$REPO" && bash "$SCRIPT" --check-name "$c" --reviewed-oid "$SHA" ) > "$TMP/case.lower.$c.out" 2>/dev/null
  cmp -s "$TMP/case.upper.$c.out" "$TMP/case.lower.$c.out" \
    && ok "(CASE) $up gets the note $c gets, its rig extension included" \
    || bad "(CASE) $up gets another note than $c: $(diff "$TMP/case.lower.$c.out" "$TMP/case.upper.$c.out" | sed -n 's/^> //p' | head -1)"
done
hasF "$TMP/case.upper.arch.out" 'RIG-EXT-MARK' "(CASE) …ARCH's note carries the arch extension"
# A check the reviewed repo's index declares in a row written in another case.
CREPO="$TMP/case-repo"; mkdir -p "$CREPO/docs"
git -C "$CREPO" init -q
git -C "$CREPO" config user.email t@t; git -C "$CREPO" config user.name t
printf '[checks.Security]\nmethod = "docs/review-security.md"\npurpose = "CASE-PURPOSE-MARK: tokens stay out of logs."\nphase = "open-as-draft"\n' > "$CREPO/review-checks.toml"
printf 'CASE-EXT-MARK: read the logging guide first.\n' > "$CREPO/docs/review-security.md"
git -C "$CREPO" add review-checks.toml docs/review-security.md
git -C "$CREPO" commit -qm case
CSHA=$(git -C "$CREPO" rev-parse HEAD)
# The row's phase is not the pre-open an undeclared token takes, so the phase
# the resolver pairs with a token shows it read the row.
n=0
for tok in security SECURITY; do
  n=$((n + 1))
  RROW=$(cd "$CREPO" && env -u GC_RIG_ROOT -u GC_REVIEW_CHECKS_INDEX bash "$HERE/review-checks.sh" --resolve --check-set "$tok" --through merge --with-phase --at "$CSHA" 2>/dev/null) || RROW=""
  eq "$RROW" "$(printf '%s\topen-as-draft' "$tok")" "(CASE) the resolver reads [checks.Security] as declaring the token $tok"
  RTOK=$(printf '%s' "$RROW" | cut -f1)
  ( cd "$CREPO" && env -u GC_RIG_ROOT bash "$SCRIPT" --check-name "$RTOK" --reviewed-oid "$CSHA" ) > "$TMP/case.rig.$n.out" 2>/dev/null
  hasF "$TMP/case.rig.$n.out" 'declares the `security` check,' "(CASE) …and the dispatch body reads the row as declaring $tok too"
  hasF "$TMP/case.rig.$n.out" '> CASE-PURPOSE-MARK: tokens stay out of logs.' "(CASE) …printing the row's purpose for $tok"
  notF "$TMP/case.rig.$n.out" 'declared nowhere' "(CASE) …and never the declared-nowhere note for $tok"
  hasF "$TMP/case.rig.$n.out" 'CASE-EXT-MARK' "(CASE) …and appending the check's extension for $tok"
done

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
