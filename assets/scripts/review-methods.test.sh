#!/usr/bin/env bash
# review-methods.test.sh — a check's method is the skill named from the check,
# held by iterating the pack's index rather than by any list of checks.
#
#   - Every row of the pack's review-checks.toml has skills/review-<check>/,
#     whose SKILL.md is named review-<check> and has a `## The verdict` section,
#     and every skills/review-* directory has a row.
#   - Every signoff.sh flag a check's verdict section names is one signoff.sh
#     accepts, and every skill a check's skill says to load is one the pack ships.
#     Every field signoff.sh checks a finding set for is one the correctness
#     method's verdict section names.
#   - The correctness method reads the work-quality fragments and the exemplar
#     corpus from its own references/ directory, through relative links that
#     resolve to template-fragments/, and resolves no pack file by path.
#   - A rig index that adds a check with no skill resolves it to its purpose
#     through --check, and a token no index declares resolves to nothing, which
#     are the two no-skill cases the review formulas send a reviewer to.
#   - Each region the review formulas repeat across steps, the method load, the
#     record check, the gather and the subagent rules, is the same text in every
#     step carrying it.
#   - Every step that applies a check's method lets the method hand reading to
#     subagents, each read-only in the review's workspace and never calling
#     signoff.sh, while the agent holding the step writes every finding. No
#     review formula or review skill forbids subagents, and the correctness
#     method says when it hands an angle to a finder or a candidate to a
#     verifier, that each gets the diff and the files it needs and none of the
#     reviewer's conversation, and that its brief states the rules it runs
#     under.
#   - The correctness method sweeps once more when the hunt's candidates are
#     deduped, looking only for defects no candidate names yet: moved code that
#     dropped a guard, setup and teardown asymmetry in tests, config defaults
#     that flipped, and second-tier footguns. A finder of its own sweeps where
#     the provider offers subagents and the reviewer sweeps in a separate pass
#     where it offers none, either way given the candidates so far. A defect
#     the sweep adds names it as its category and is verified with the rest,
#     and the trail records the sweep on a Swept: line above the Refuted: lines.
#   - The correctness method checks each blocking candidate before the
#     verdict, in a context that did not raise it: a verifier subagent where
#     the provider offers one, a separate pass where it offers none. The check
#     returns CONFIRMED, PLAUSIBLE or REFUTED, a refutation quotes the line
#     that proves it, and a refuted candidate does not block, stays out of the
#     finding set and keeps its refutation in the trail.
#   - The correctness method grades prose under the same contract. A finding on
#     prose names the text, the reader who acts on it and the wrong action or
#     false belief that follows on the tree as merged, and its check reads the
#     tree. It blocks when it is a claim the tree contradicts, an instruction
#     that does the wrong thing as written, or a committed behavior that fails
#     on a reachable case, and a failure that depends on how work the text
#     leaves open is built is a P2 at most. A diff no suite touches has nothing
#     to run, and the Verification line says so.
#   - Neither review formula names a check's judgment: no test or suite, no
#     P0, P1 or P2 grade, no Verification line, and neither the correctness
#     method's What to check list nor any dimension of it. The correctness
#     method is method alone: it carries no shell block and reads no record
#     itself, because the review formula gathers what it reads.
#   - The pm method says when triage adds it, in words that name no rig: a
#     diff that changes what the rig's product does for the people it serves,
#     or what it promises them, and always a diff that changes the product
#     goals page. An edit that changes neither what the product does nor what
#     it promises, and tests, do not warrant it. When a rig keeps no product
#     goals, a pm review judges the change against its anchor alone and asks
#     the change for no page. It files one request for the page under one
#     token, and its duplicate probe counts a request that has closed. The
#     method defines that page without the foundation doc only this repo keeps.
#   - This repo's own docs/review-triage.md, read the way a review reads it at
#     its commit, carries the changes that make pm mandatory and the edits that
#     do not.
#   - The arch skill approves no commit without a docs/architecture.md, files a
#     gap in architecture the change does not touch without holding the change,
#     and passes no change on a gap in architecture it does touch. This repo's
#     own docs/review-arch.md and docs/review-triage.md, read the way a review
#     reads them at its commit, carry the divergence lens and the changes that
#     make arch mandatory, and the pack's arch skill carries none of that lens.
#   - The demo method says a demo shows a reviewer what the change does,
#     briefly, the way a sprint demo does, and that the check posts only the
#     visuals such a demo needs. The check itself looks at every place the
#     change reaches, and its verdict says what it looked at.
#   - The demo method lists a message the rig's app sends people among the
#     surfaces triage adds it for, even when no screen changes, and such a
#     message settles need. It shows each message a change adds or alters as
#     its recipient would see it, from a run of the reviewed commit, beside any
#     clip of the screens, and its verdict names each message it shows. When a
#     change alters many messages in the same way, the check still captures and
#     checks each one, but it delivers only an example or two and names the
#     rest in its verdict.
#   - When a rig's guidance for the demo check names a design or writing
#     standard, the demo method reviews the change against it:
#     - Any change to what a screen shows needs a visual, however small.
#     - The check reads each standard at the reviewed commit.
#     - It captures every changed screen and every message the change adds or
#       alters, in each state the guidance requires. A changed screen is also
#       captured in the state that shows the change. When the change alters a
#       part that many screens share, the check captures the screens the
#       guidance names for it, or every screen that shows the part if the
#       guidance names none. Each capture is a PNG named for what it shows,
#       and it stays in the review workspace.
#     - It reads the words on each screen and in each message the way the
#       person they are for would read them. Words that state every fact the
#       change claims can still break the writing standard.
#     - A violation blocks approval when the change introduces it, and also
#       when it was already on a screen or message the change alters. One
#       cause is one finding, however many screens it shows on. The finding
#       gives the rule, every screen and state where it shows, what would fix
#       it, where the demo shows it, and the source that draws the wrong part.
#       A violation on a screen or message the change does not alter is filed
#       as a separate bug.
#     - The PR gets one narrated video that walks through the change and
#       through each finding on a screen. It also gets the messages, and no
#       other capture of a screen. A single screenshot takes the video's place
#       when one capture shows the whole demo, and screenshots are its fallback
#       when no video can be made.
#     - The verdict names the standard and lists everything the check captured
#       and checked.
#     - When a capture cannot be made for a reason the change did not cause,
#       such as a state the capture tools cannot reach, the verdict says what
#       stopped it, and approval is not blocked. When the change itself makes a
#       capture fail, that failure is a finding.
#     - With no standard named, the method skips all of this, and the pm
#       method leaves the standards to the demo check.
#   - The demo method states the size at which a page is captured. It is 1280
#     by 900 by default, the script's Device line can name another, and a
#     resize step changes it from that step on.
#
# Hermetic: reads this checkout and a scratch git repository; no gc, store or
# network.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-review-methods-test.XXXXXX")" || exit 1
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1${2:+ ($2)}"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3" "got '$1' want '$2'"; fi; }

CHECKS="$ROOT/assets/scripts/review-checks.sh"
INDEX="$ROOT/review-checks.toml"
NAMES=$("$CHECKS" --file "$INDEX" 2>/dev/null | cut -f1)
[ -n "$NAMES" ] && ok "the pack's index declares checks ($(printf '%s' "$NAMES" | paste -sd' ' -))" \
  || bad "the pack's index declares checks" "none read"

echo "# every declared check has its skill, and every review skill a row"
grep -oE -- '^    --[a-z][a-z-]*\)' "$ROOT/assets/scripts/signoff.sh" | tr -d ' )' | sort -u > "$TMP/signoff-flags"
[ -s "$TMP/signoff-flags" ] && ok "signoff.sh's flags are read" || bad "signoff.sh's flags are read" "none"
while IFS= read -r c; do
  [ -n "$c" ] || continue
  f="$ROOT/skills/review-$c/SKILL.md"
  if [ ! -r "$f" ]; then bad "$c: skills/review-$c/SKILL.md ships"; continue; fi
  ok "$c: skills/review-$c/SKILL.md ships"
  eq "$(sed -n 's/^name: //p' "$f" | head -1)" "review-$c" "$c: its skill is named review-$c"
  awk '/^## The verdict$/ {f = 1; next} f && /^## / {exit} f' "$f" > "$TMP/verdict.$c"
  [ -s "$TMP/verdict.$c" ] && ok "$c: its skill has a verdict section" || bad "$c: its skill has a verdict section"
  grep -oE -- '--[a-z][a-z-]*' "$TMP/verdict.$c" | sort -u > "$TMP/flags.$c"
  eq "$(comm -23 "$TMP/flags.$c" "$TMP/signoff-flags" | paste -sd' ' -)" "" \
    "$c: every flag its verdict section names is one signoff.sh accepts"
  for s in $(grep -oE 'gc-toolkit\.[a-z][a-z0-9-]*' "$f" | sed 's/^gc-toolkit\.//' | sort -u); do
    [ -r "$ROOT/skills/$s/SKILL.md" ] && ok "$c: the skill it says to load, gc-toolkit.$s, ships" \
      || bad "$c: the skill it says to load, gc-toolkit.$s, ships"
  done
done <<< "$NAMES"
for d in "$ROOT"/skills/review-*/; do
  c=$(basename "$d"); c=${c#review-}
  grep -qxF -- "$c" <<< "$NAMES" && ok "skills/review-$c has a row in the pack's index" \
    || bad "skills/review-$c has a row in the pack's index"
done
# The finding set signoff.sh holds to the finding contract carries the fields
# the correctness method's verdict section tells its reviewer to write.
FIELDS=$(grep -m1 -F '("locus", "message"' "$ROOT/assets/scripts/signoff.sh" | grep -oE '"[a-z_]+"' | tr -d '"')
[ "$(printf '%s\n' "$FIELDS" | grep -c .)" -ge 6 ] && ok "signoff.sh's finding fields are read ($(printf '%s' "$FIELDS" | paste -sd' ' -))" \
  || bad "signoff.sh's finding fields are read" "got '$FIELDS'"
for f in $FIELDS; do
  grep -qF -- "\`$f\`" "$TMP/verdict.correctness" && ok "correctness: its verdict section names \`$f\`, a field signoff.sh checks" \
    || bad "correctness: its verdict section names \`$f\`, a field signoff.sh checks"
done
grep -l 'specialist-stance' "$ROOT"/skills/review-*/SKILL.md | xargs -n1 dirname | xargs -n1 basename | sort > "$TMP/stance-holders"
[ -s "$TMP/stance-holders" ] && ok "the specialist checks load the stance ($(paste -sd' ' - < "$TMP/stance-holders"))" \
  || bad "no check's skill loads the specialist stance"
eq "$(sed -n 's/^name: //p' "$ROOT/skills/specialist-stance/SKILL.md" | head -1)" "specialist-stance" \
  "the stance ships as its own skill, outside the review- prefix"

echo "# the correctness method reads its standards from its own skill directory"
METHOD="$ROOT/skills/review-correctness/SKILL.md"
if grep -qE 'GC_PACK_DIR|GC_RIG_ROOT|template-fragments/' "$METHOD"; then bad "the method resolves no pack file by path"
else ok "the method resolves no pack file by path"; fi
grep -qF '`references/work-quality-*.template.md`' "$METHOD" && ok "it reads the work-quality fragments from its references" \
  || bad "it reads the work-quality fragments from its references"
grep -qF '`references/learning-exemplars.template.md`' "$METHOD" && ok "…and the exemplar corpus" || bad "…and the exemplar corpus"
# A skill reaches a reviewer as a link to its directory, so a relative link in
# references/ resolves wherever the pack is installed. A new class fragment
# fails here until it has its link.
REFS="$(dirname "$METHOD")/references"
for frag in "$ROOT"/template-fragments/work-quality-*.template.md "$ROOT/template-fragments/learning-exemplars.template.md"; do
  b=$(basename "$frag")
  if [ -L "$REFS/$b" ] && [ "$REFS/$b" -ef "$frag" ]; then
    case "$(readlink "$REFS/$b")" in
      /*) bad "references/$b links template-fragments/$b by an absolute path" ;;
      *) ok "references/$b is a relative link to template-fragments/$b" ;;
    esac
  else
    bad "references/$b is not a link to template-fragments/$b"
  fi
done
for l in "$REFS"/*; do
  b=$(basename "$l")
  case "$b" in work-quality-*.template.md|learning-exemplars.template.md) ;; *) b="" ;; esac
  [ -n "$b" ] && [ "$l" -ef "$ROOT/template-fragments/$b" ] \
    && ok "references/$(basename "$l") is a fragment the method reads" \
    || bad "references/$(basename "$l") is not a fragment the method reads"
done

echo "# the two no-skill cases: a rig's own check resolves to its purpose, an undeclared one to nothing"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
unset GC_REVIEW_CHECKS_INDEX GC_RIG_ROOT 2>/dev/null || true
RIG="$TMP/rig"; git init -q "$RIG"
printf '[checks.ux]\npurpose = "Does the change keep the flows a person uses intact?"\nphase = "pre-open"\n' > "$RIG/review-checks.toml"
git -C "$RIG" add review-checks.toml; git -C "$RIG" commit -q -m "a check of the rig's own"
AT=$(git -C "$RIG" rev-parse HEAD)
[ -d "$ROOT/skills/review-ux" ] && bad "the fixture's check has no pack skill" || ok "the fixture's check has no pack skill"
ROW=$(cd "$RIG" && "$CHECKS" --check ux --at "$AT" 2>/dev/null); rc=$?
eq "$rc" "0" "--check of the rig's own check succeeds at its commit"
eq "$(printf '%s' "$ROW" | cut -f2)" "Does the change keep the flows a person uses intact?" "…and prints the purpose the reviewer judges against"
ERR=$(cd "$RIG" && "$CHECKS" --check nonesuch --at "$AT" 2>&1 >/dev/null); rc=$?
eq "$rc" "1" "--check of a token no index declares exits 1"
case "$ERR" in *"does not declare check 'nonesuch'"*) ok "…saying no index declares it, the case the formula approves with --needs-you" ;;
  *) bad "…saying no index declares it" "got '$ERR'" ;; esac
ERR=$(cd "$RIG" && "$CHECKS" --check ux --at 0000000000000000000000000000000000000000 2>&1 >/dev/null); rc=$?
eq "$rc" "1" "--check at a commit nothing can read exits 1 too"
case "$ERR" in *"does not declare"*) bad "…but never as a check declared nowhere" "got '$ERR'" ;;
  *) ok "…but never as a check declared nowhere, which nothing approves on" ;; esac

echo "# the arch skill's rules on docs/architecture.md, and this repo's own arch and triage guidance"
# Text a reviewer reads, which no test of the mechanism that delivers it pins.
# flat <file>: the file's prose on one line, so a pinned phrase may wrap.
flat() { tr '\n' ' ' < "$1" | tr -s ' '; }
hasF() { if flat "$1" | grep -qF -- "$2"; then ok "$3"; else bad "$3" "missing: $2"; fi; }
notF() { if flat "$1" | grep -qF -- "$2"; then bad "$3" "unexpected: $2"; else ok "$3"; fi; }
hasF "$METHOD" 'a title whose type or words misname what the diff does' "the correctness method judges a PR title's type and words against its diff"
hasF "$METHOD" 'a false one blocks as a false summary does' "…blocks a false title"
hasF "$METHOD" 'one that is true but merely weak is a P2' "…and grades a title that is only weak a P2"
ARCH_SKILL="$ROOT/skills/review-arch/SKILL.md"
hasF "$ARCH_SKILL" 'A `docs/architecture.md` at the reviewed commit is a precondition of approval' "the arch skill approves no commit without docs/architecture.md"
hasF "$ARCH_SKILL" 'a passable account of the architecture the change covers' "…whose change adds one covering the architecture it covers"
hasF "$ARCH_SKILL" '`docs/architecture.md: incomplete`' "…and files the rest of the architecture as one follow-up under one token"
hasF "$ARCH_SKILL" 'File it the same way, and do not hold the change for it.' "…files a gap the change does not touch without holding the change for it"
hasF "$ARCH_SKILL" 'A gap in the architecture the change does touch is no reason to pass the change' "…and passes no change on a gap in the architecture it touches"
notF "$ARCH_SKILL" 'not a reason to pass or fail the change' "…so no missing reference lets a change through unjudged"
notF "$ARCH_SKILL" 'divergence lens' "the pack's arch skill, which every rig's arch review loads, carries none of gc-toolkit's lens"
# This checkout's guidance, committed in a scratch repository and read back
# through --extension at that commit, the read load-dispatch makes for a review.
OWN="$TMP/own"; git init -q "$OWN"; mkdir -p "$OWN/docs"
cp "$ROOT/docs/review-arch.md" "$ROOT/docs/review-triage.md" "$OWN/docs/"
git -C "$OWN" add docs; git -C "$OWN" commit -q -m "this repo's arch and triage guidance"
OWN_AT=$(git -C "$OWN" rev-parse HEAD)
for c in arch triage; do
  (cd "$OWN" && "$CHECKS" --extension "$c" --at "$OWN_AT" 2>/dev/null) > "$TMP/own.$c"
done
hasF "$TMP/own.arch" "The lens holds new surface to Gas City's own documentation instead." "this repo's arch guidance holds new surface to Gas City's own docs, not the pack's account of Gas City"
hasF "$TMP/own.arch" 'A converter is a finding on sight.' "…makes a converter between a pack noun and a Gas City noun a finding"
hasF "$TMP/own.arch" 'neither are tests or the fixtures they use' "…and leaves tests out of operational surface"
hasF "$TMP/own.triage" '## When `arch` is mandatory' "this repo's triage guidance says when the arch check is mandatory"
hasF "$TMP/own.triage" 'does not make `arch` mandatory' "…and that a diff of tests alone does not make it so"
hasF "$TMP/own.triage" '## When `pm` is mandatory' "…says when the pm check is mandatory"
hasF "$TMP/own.triage" 'does not make `pm` mandatory, and neither do tests and the fixtures they use' \
  "…and that an edit changing no behavior, or a test, does not make it so"

echo "# a region the review formulas repeat is one text in every step carrying it"
python3 - "$ROOT/formulas/mol-review.toml" "$ROOT/formulas/mol-review-quorum-signoff.toml" > "$TMP/regions" <<'PY'
import sys, tomllib, re, json
out = {}
for path in sys.argv[1:]:
    d = tomllib.load(open(path, 'rb'))
    for s in d['steps']:
        text = s['description']
        for m in re.finditer(r'(?:<!-- |# )>>> (review-method-load|review-record-check|review-gather|review-subagents)(?: -->)?\n(.*?)\n(?:<!-- |# )<<< \1', text, re.S):
            out.setdefault(m.group(1), []).append([d['formula'] + '.' + s['id'], m.group(2)])
print(json.dumps(out))
PY
for r in review-method-load:4 review-record-check:4 review-gather:4 review-subagents:4; do
  name=${r%%:*}; want=${r#*:}
  eq "$(jq -r --arg r "$name" '.[$r] | length' "$TMP/regions")" "$want" "$name: the steps that carry it carry it ($want)"
  eq "$(jq -r --arg r "$name" '[.[$r][][1]] | unique | length' "$TMP/regions")" "1" "$name: every copy is the same text"
done
case "$(jq -r '."review-method-load"[0][1]' "$TMP/regions")" in
  *'`{{binding_prefix}}review-{{check}}`'*'`{{binding_prefix}}specialist-stance`'*) ok "the method load names the skill from the check, and the stance for the purpose case" ;;
  *) bad "the method load names the skill from the check, and the stance for the purpose case" ;;
esac
eq "$(jq -r '[."review-subagents"[][0]] | sort | join(" ")' "$TMP/regions")" \
  "$(jq -r '[."review-method-load"[][0]] | sort | join(" ")' "$TMP/regions")" \
  "the subagent rules ride every step that loads a check's method, and no other"
case "$(jq -r '."review-subagents"[0][1]' "$TMP/regions" | tr '\n' ' ')" in
  *'read-only in the review'*'runs nothing the method runs'*'never calls signoff.sh'*'write every finding yourself'*)
    ok "the subagent rules keep every subagent read-only and off signoff.sh, and the step's own agent the one writer" ;;
  *) bad "the subagent rules keep every subagent read-only and off signoff.sh, and the step's own agent the one writer" ;;
esac

echo "# the review formulas name no check's judgment, and the correctness method is method"
# The formulas carry what every check shares, so a test, a grade or a
# dimension in one is a check's judgment in the lifecycle. The text checked is
# what a reviewer reads: the description, and each step's title and
# description, shell blocks included.
for f in mol-review mol-review-quorum-signoff; do
  python3 - "$ROOT/formulas/$f.toml" > "$TMP/$f.txt" <<'PY'
import sys, tomllib
d = tomllib.load(open(sys.argv[1], 'rb'))
print('\n'.join([d.get('description', '')] + [s.get('title', '') + '\n' + s.get('description', '') for s in d.get('steps', [])]))
PY
  [ -s "$TMP/$f.txt" ] && ok "$f: its text is read" || bad "$f: its text is read"
done
# The dimensions are the bold bullets of the correctness method's What to check list.
awk '/^### What to check$/ {f = 1; next} f && /^#/ {exit} f' "$METHOD" \
  | sed -n 's/^- \*\*\([^*]*\)\*\*.*/\1/p' > "$TMP/dimensions"
DIMS=$(grep -c . "$TMP/dimensions" || true)
[ "$DIMS" -ge 5 ] && ok "the What to check list names its dimensions ($(paste -sd, - < "$TMP/dimensions"))" \
  || bad "the What to check list names its dimensions" "only $DIMS read"
# hit <file> <ERE> [-i] : the first line that matches, empty for none.
hit() { grep -E ${3:-} -m1 -- "$2" "$1" || true; }
for f in mol-review mol-review-quorum-signoff; do
  T="$TMP/$f.txt"
  eq "$(hit "$T" '(^|[^[:alnum:]_])(tests?|tested|testing|suites?)([^[:alnum:]_]|$)' -i)" "" "$f names no test or suite"
  eq "$(hit "$T" '(^|[^[:alnum:]_])P[0-2]([^[:alnum:]_]|$)')" "" "$f names no P0, P1 or P2 grade"
  eq "$(grep -F -m1 -- 'Verification:' "$T" || true)" "" "$f has no Verification line"
  eq "$(grep -F -m1 -- 'What to check' "$T" || true)" "" "$f points at no What to check list"
  while IFS= read -r d; do
    eq "$(grep -F -m1 -- "**$d**" "$T" || true)" "" "$f carries no '$d' dimension"
  done < "$TMP/dimensions"
done
eq "$(grep -cE '^ *```(bash|sh|zsh|shell) *$' "$METHOD" || true)" "0" "the correctness method carries no shell block"
eq "$(grep -n -m1 -- '--check' "$METHOD" || true)" "" "the correctness method reads no record itself"

echo "# no review text forbids subagents, and the correctness method says how it uses them"
# The formulas a review pours and the skills it loads, read flat so a phrase
# may wrap.
for f in "$ROOT/formulas/mol-review.toml" "$ROOT/formulas/mol-review-quorum-signoff.toml" \
  "$ROOT"/skills/review-*/SKILL.md "$ROOT/skills/specialist-stance/SKILL.md"; do
  eq "$(flat "$f" | grep -Eio -- 'single honest pass|no subagents|no persona|no fan-out' | head -1)" "" \
    "${f#"$ROOT"/} forbids no subagents"
done
hasF "$METHOD" '### Finders and verifiers' "the correctness method says when it hands an angle to a finder or a candidate to a verifier"
hasF "$METHOD" 'the diff and the files its angle or candidate runs through, never your whole context' \
  "…and gives each the diff and the files it needs, never the reviewer's whole context"
hasF "$METHOD" 'start it with none of your conversation' "…and none of the reviewer's conversation"
hasF "$METHOD" 'Its brief states those rules, because a subagent can hold every tool you hold' \
  "…and states the formula's rules for subagents in its brief"

echo "# one fresh pass after the hunt looks only for the defects the hunt missed"
hasF "$METHOD" '### The fresh-eyes sweep' "the correctness method sweeps once more after the hunt"
hasF "$METHOD" 'When the hunt is done and its candidates are deduped, one fresh pass looks only for defects that no candidate names yet.' \
  "…once the hunt's candidates are deduped, for defects no candidate names yet"
for t in 'Moved code that dropped a guard' 'Setup and teardown asymmetry in tests' 'Config defaults that flipped' 'Second-tier footguns'; do
  hasF "$METHOD" "- **$t** —" "…aimed at: $t"
done
hasF "$METHOD" 'Where your provider offers subagents, hand the sweep to a finder of its own' "…by a finder of its own where the provider offers subagents"
hasF "$METHOD" 'Where it offers none, sweep yourself in a separate pass' "…and in a separate pass where it offers none"
hasF "$METHOD" 'the sweep is given the candidates so far, each as its locus and failure scenario' "…either way given the candidates so far, each as its locus and failure scenario"
hasF "$METHOD" "The sweep's finder gets the sweep's targets in place of an angle, and the candidates so far." \
  "…which its finder's brief carries, with the targets in place of an angle"
hasF "$METHOD" 'or `Fresh-eyes sweep` for a defect the sweep below found' "…a defect it adds names the sweep as its category"
hasF "$TMP/verdict.correctness" '"category": "<the dimension of What to check that found it, or Fresh-eyes sweep>"' \
  "…which the finding set's template offers beside the dimension"
hasF "$METHOD" 'each P0 and P1 among them is verified with the rest' "…and is verified with the rest"
hasF "$TMP/verdict.correctness" 'the trail carries a `Swept:` line that says how the sweep ran and what it added' \
  "…and the trail the verdict section shapes records the sweep on a Swept: line"
eq "$(grep -oE '^(Swept|Refuted|Verification): ' "$TMP/verdict.correctness" | tr -d ' ' | paste -sd' ' -)" "Swept: Refuted: Verification:" \
  "…above the trail's Refuted: and Verification: lines"

echo "# each blocking candidate is checked in a context that did not raise it, before the verdict"
hasF "$METHOD" '### Verify each blocking candidate' "the correctness method verifies each blocking candidate"
hasF "$METHOD" 'Before the verdict, check each candidate P0 and P1 in a context that did not raise it.' "…before the verdict, in a context that did not raise it"
hasF "$METHOD" 'Where your provider offers subagents, hand each one to a verifier' "…by a verifier subagent where the provider offers one"
hasF "$METHOD" 'Where it offers none, check each one yourself in a separate pass once the hunt and the sweep are done' "…and in a separate pass where it offers none, once the hunt and the sweep are done"
for r in CONFIRMED PLAUSIBLE REFUTED; do
  hasF "$METHOD" "- **$r** —" "…which returns $r as one of its results"
done
hasF "$METHOD" 'the check quotes the line that proves it' "…a refutation quotes the line that proves it"
hasF "$METHOD" 'A REFUTED candidate is dropped: it is not a finding, it does not block, and `findings.json` does not carry it.' \
  "…a refuted candidate does not block, and the finding set does not carry it"
awk '/^## The verdict$/ {f = 1; next} f && /^## / {exit} f' "$METHOD" > "$TMP/verdict.refuted"
hasF "$TMP/verdict.refuted" 'a `Refuted:` line for each candidate its check refuted' "…and its refutation stays in the trail the verdict section shapes"
hasF "$TMP/verdict.refuted" 'an entry whose verification is REFUTED' "…and names signoff.sh's refusal of a set that carries one"

echo "# prose is graded under the same contract, and a diff no suite touches has nothing to run"
hasF "$METHOD" 'Prose is text that a person or an agent reads and acts on, such as a document, a spec, a prompt, a skill or a comment.' \
  "the correctness method says what prose is"
hasF "$METHOD" 'A finding on prose has a reader where code has an input, so its failure scenario names the text, the reader who acts on it, and the wrong action or false belief that follows on the tree as merged.' \
  "…that a finding on prose names the text, its reader and the wrong action or belief on the tree as merged"
hasF "$METHOD" 'On prose, the tree the text describes answers that question.' "…and that its check reads the tree the text describes"
awk '/^## What blocks$/ {f = 1; next} f && /^## / {exit} f' "$METHOD" > "$TMP/blocks"
hasF "$TMP/blocks" 'On prose, a finding blocks when its failure scenario is one of these:' "what blocks says which failures on prose block"
for b in 'A claim about the tree that the tree as merged contradicts.' \
  'An instruction that does the wrong thing when it is followed as written.' \
  'A behavior the text commits to that fails on a reachable case.'; do
  hasF "$TMP/blocks" "- $b" "…$b"
done
hasF "$TMP/blocks" 'A failure that depends on how work the text leaves open is later built does not block' \
  "…and that a failure which depends on how open work is built does not"
hasF "$TMP/blocks" 'It is a P2 at most, or a note in the trail for that work.' "…being a P2 at most, or a note for that work"
awk '/^### Settle the test evidence$/ {f = 1; next} f && /^#/ {exit} f' "$METHOD" > "$TMP/evidence"
hasF "$TMP/evidence" 'When the diff touches none, as when it changes only a document that no suite reads, there is nothing to run.' \
  "the test evidence of a diff no suite touches is that there is nothing to run"
hasF "$TMP/evidence" 'Run nothing, and the Verification line says so, with how you found that no suite touches the diff.' \
  "…which the Verification line says, with how the reviewer found it"
hasF "$TMP/verdict.correctness" 'or that no suite touches the diff, and how you found it>' \
  "…in the form the verdict section's Verification line offers"

echo "# a demo shows a reviewer what the change does, concisely, and the demo method posts only what such a demo needs"
DEMO="$ROOT/skills/review-demo/SKILL.md"
awk '/^# The demo check$/ {f = 1; next} f && /^## / {exit} f' "$DEMO" > "$TMP/demo.intro"
hasF "$TMP/demo.intro" 'A demo shows a reviewer what the change does, concisely, as a sprint demo does' \
  "the demo method says a demo shows a reviewer what the change does, concisely, as a sprint demo does"
hasF "$TMP/demo.intro" 'the few items that present the change as a whole, an example or two of a change that repeats across many places, and each problem the check finds.' \
  "…the items that present the change as a whole, an example or two of what repeats, and each problem found"
hasF "$TMP/demo.intro" 'It does not walk the reviewer through every place the change reaches.' \
  "…and not every place the change reaches"
hasF "$TMP/demo.intro" "Checking every place is the check's own work, and the verdict says what it checked." \
  "…which the check checks itself, saying in the verdict what it checked"
hasF "$TMP/demo.intro" 'Whatever the change, the check posts only the visuals such a demo needs.' \
  "…so whatever the change, the check posts only the visuals such a demo needs"

echo "# the demo method shows each message a change adds or alters, as its recipient sees it"
awk '/^### When triage adds it$/ {f = 1; next} f && /^#/ {exit} f' "$DEMO" > "$TMP/demo.triage"
hasF "$TMP/demo.triage" "a message the rig's app sends people, such as an email" \
  "triage adds the demo check for a message the rig's app sends people"
hasF "$TMP/demo.triage" 'even when no screen changes.' "…even when no screen changes"
awk '/^### Decide need$/ {f = 1; next} f && /^#/ {exit} f' "$DEMO" > "$TMP/demo.need"
hasF "$TMP/demo.need" 'A message the change adds or alters settles need the same way' \
  "a message the change adds or alters settles need"
awk '/^### Show each message$/ {f = 1; next} f && /^#/ {exit} f' "$DEMO" > "$TMP/demo.messages"
hasF "$TMP/demo.messages" 'as its recipient would see it: the sender, the subject and the body.' \
  "each message is shown as its recipient would see it, sender, subject and body"
hasF "$TMP/demo.messages" 'Each comes from a run of the reviewed commit.' \
  "…from a run of the reviewed commit"
notF "$TMP/demo.messages" 'fixture' "…and the method assumes no fixture data of its own for that run"
hasF "$TMP/demo.messages" 'beside the clip or the screenshot of any screen the change alters.' \
  "…beside any clip of the screens"
hasF "$TMP/demo.messages" 'When the change alters many messages in the same way, such as a footer they share, capture and check each one, then deliver an example or two and list the rest in the verdict.' \
  "…and of many messages a change alters in the same way, it checks each one and delivers an example or two"
hasF "$TMP/verdict.demo" 'names each message it shows, by its subject' "the demo verdict names each message it shows"
hasF "$TMP/verdict.demo" 'Where it shows an example or two of many messages the change alters in the same way, it also names the rest, by subject.' \
  "…and the rest of many messages altered in the same way"

echo "# the demo method reviews changed screens and messages against the standards the rig's guidance names"
awk '/^## What it reads$/ {f = 1; next} f && /^#/ {exit} f' "$DEMO" > "$TMP/demo.reads"
hasF "$TMP/demo.reads" 'A rig can also name its design and writing standards there, and the states to capture for each screen or message.' \
  "the rig's guidance for the demo check can name its standards and the states to capture"
hasF "$TMP/demo.need" 'any change to what a screen renders settles need, whatever its size.' \
  "under a standard, any change to what a screen renders settles need, whatever its size"
hasF "$TMP/demo.need" "as the section Review against the rig's standards says." \
  "…and the need decision points at the section that does the review"
awk '/^### Review against the rig.s standards$/ {f = 1; next} f && /^#/ {exit} f' "$DEMO" > "$TMP/demo.standard"
[ -s "$TMP/demo.standard" ] && ok "the demo method has a section that reviews against the rig's standards" \
  || bad "the demo method has a section that reviews against the rig's standards"
hasF "$TMP/demo.standard" 'A rig'"'"'s guidance, its `docs/review-demo.md`, can name a design standard, a writing standard, or both.' \
  "…which a rig opts into through its guidance"
hasF "$TMP/demo.standard" 'If the guidance names neither, skip this section.' \
  "…and which the check skips when the guidance names no standard"
hasF "$TMP/demo.standard" 'read each named standard at the reviewed commit' "…reads each standard at the reviewed commit"
hasF "$TMP/demo.standard" 'through the screen'"'"'s own source or through a part it shows, such as a component, a style or its words.' \
  "…counts a screen as changed through a component, a style or its words"
hasF "$TMP/demo.standard" 'list the screens the guidance names for such a change. If it names none, list every screen that shows the part.' \
  "…takes a shared part's screens from the guidance, otherwise every screen that shows it"
hasF "$TMP/demo.standard" 'The required states of a screen or message are the ones the guidance names for it' \
  "…requires each state the guidance names"
hasF "$TMP/demo.standard" 'A changed screen also needs the state that shows the change.' \
  "…and a changed screen also in the state that shows the change"
hasF "$TMP/demo.standard" 'List each changed screen, each message the change adds or alters, and the states to capture each one in.' \
  "…lists each changed screen and message, and the states to capture each one in"
hasF "$TMP/demo.standard" 'Capture each message as the section Show each message says.' \
  "…captures each message by its existing method"
hasF "$TMP/demo.standard" 'Keep each capture in the review workspace, in a PNG named for the screen or message and the state.' \
  "…keeps each capture in the review workspace, in a PNG named for what it shows"
hasF "$TMP/demo.standard" 'The captures are your working evidence, and step 6 says what the PR gets.' \
  "…as the check's working evidence, while step 6 says what the PR gets"
hasF "$TMP/demo.standard" '**Check each capture against the standards.** Apply every rule that covers what the capture shows.' \
  "…and checks every capture against every rule that covers it"
hasF "$TMP/demo.standard" 'When a capture cannot be made for a reason the change did not cause, such as a state the capture tools cannot reach, that is not a finding and it does not block.' \
  "…does not block on a capture that fails for a reason the change did not cause"
hasF "$TMP/demo.standard" 'Name in the verdict each screen, message or state you could not capture, and what stopped it.' \
  "…and names what it could not capture in the verdict"
hasF "$TMP/demo.standard" 'If the change itself makes a capture fail, that failure is a finding.' \
  "…but a failure the change causes is a finding"
hasF "$TMP/demo.standard" 'Design rules cover each screen. Writing rules cover the words on each screen and in each message.' \
  "…applies design rules to screens, and writing rules to the words of screens and messages"
hasF "$TMP/demo.standard" 'Read the words as the person the screen or message is for reads them' \
  "…reads the words as the person the screen or message is for reads them"
hasF "$TMP/demo.standard" 'knowing what that person knows, and knowing nothing of the change or its anchor.' \
  "…knowing what that person knows, and nothing of the change"
hasF "$TMP/demo.standard" 'Words can state every fact the change claims and still violate the writing standard.' \
  "…so words that state every fact can still violate the writing standard"
hasF "$TMP/demo.standard" 'A violation the change introduces is a finding. A violation already on a changed screen or message is also a finding' \
  "…makes a violation the change introduces, or one already on a changed surface, a finding"
hasF "$TMP/demo.standard" 'Both block approval, and both go in this verdict, not in a separate bug.' \
  "…both of which block approval in this verdict"
hasF "$TMP/demo.standard" 'File a violation on a screen or message the change does not alter as a separate bug' \
  "…and files one on an unchanged surface as a separate bug"
hasF "$TMP/demo.standard" 'A violation with one cause is one finding, wherever it shows, as when a shared component is drawn wrong on every screen.' \
  "…makes a violation with one cause one finding, wherever it shows"
hasF "$TMP/demo.standard" 'Violations with different causes are separate findings.' \
  "…and violations with different causes separate findings"
hasF "$TMP/demo.standard" "the rule, in the standard's words, and where the standard states it" "…that names the rule and where it stands"
hasF "$TMP/demo.standard" 'every screen or message where it shows, and in which states' \
  "…every screen or message where it shows, and in which states"
hasF "$TMP/demo.standard" 'what is wrong, and what would meet the rule' "…what is wrong and what would meet the rule"
hasF "$TMP/demo.standard" 'its evidence: where the demo shows it, as step 6 says' \
  "…with where the demo shows it as its evidence"
hasF "$TMP/demo.standard" 'its `locus`: the file and the component, template or style that draws the part that is wrong' \
  "…and the source as its locus"
hasF "$TMP/demo.standard" '**Deliver the demo.** The demo is one narrated `video` that walks a reviewer through the change and through each finding on a screen.' \
  "…delivers the demo as one narrated video of the change and of each finding on a screen"
hasF "$TMP/demo.standard" 'It is a video even when the change is static, because a walkthrough presents several screens and states better than a set of screenshots does.' \
  "…even when the change is static, because a walkthrough presents several screens and states better than a set of screenshots"
hasF "$TMP/demo.standard" 'Record it as the section Produce it and deliver it says for a video.' \
  "…recorded the way every video is"
hasF "$TMP/demo.standard" 'Its script reaches each state the way your captures did.' \
  "…whose script reaches each state as the captures did"
hasF "$TMP/demo.standard" 'It can visit several screens, with a `goto` step for each, and change the size with a `resize` step.' \
  "…visiting several screens and sizes in one script"
hasF "$TMP/demo.standard" 'The showcase: what the change does, on an example screen or two, in the states that show the change best.' \
  "…whose showcase is an example screen or two, in the states that show the change best"
hasF "$TMP/demo.standard" 'Each finding on a screen: a screen where it shows, in a state that shows it, under a caption that names the rule it breaks.' \
  "…and which shows each finding on a screen under a caption that names its rule"
hasF "$TMP/demo.standard" 'The finding names that caption as its evidence.' \
  "…a caption the finding names as its evidence"
hasF "$TMP/demo.standard" 'The PR gets no other capture of a screen.' \
  "…and the PR gets no other capture of a screen"
hasF "$TMP/demo.standard" 'When a single capture shows the whole demo, such as one changed screen in one state with no finding, deliver that capture as a `screenshot` instead.' \
  "…except that a single capture showing the whole demo is delivered as a screenshot"
hasF "$TMP/demo.standard" 'When the video cannot be produced here, its fallback is a screenshot of each state the showcase shows and one of each finding, which the finding names as its evidence.' \
  "…and that screenshots of the showcase and of each finding are the video's fallback"
hasF "$TMP/demo.standard" 'Deliver the messages as the section Show each message says.' \
  "…which delivers the messages as the method shows them"
hasF "$TMP/demo.standard" 'A finding in a message names that message'"'"'s capture as its evidence.' \
  "…and a finding in a message names that message's capture as its evidence"
hasF "$TMP/demo.standard" 'When the change alters no screen, the messages are the whole demo.' \
  "…and the messages are the whole demo when no screen changes"
awk '/^## What blocks$/ {f = 1; next} f && /^## / {exit} f' "$DEMO" > "$TMP/demo.blocks"
hasF "$TMP/demo.blocks" 'a violation on a changed screen or message is also a finding against the change, whether the change introduced it or it was already there.' \
  "a violation of the rig's standard blocks, whether the change introduced it or not"
hasF "$TMP/demo.blocks" 'Request changes, and name where the demo shows it as the evidence.' \
  "…with where the demo shows it as the evidence"
hasF "$TMP/demo.blocks" 'or the capture tools may be unable to reach a required state.' \
  "a required state the capture tools cannot reach does not block"
hasF "$TMP/verdict.demo" "**Delivered, and it shows a violation of the rig's standard.** Request changes" \
  "the demo verdict requests changes on a violation of the rig's standard"
hasF "$TMP/verdict.demo" 'Each cause of a violation is one finding in `findings.json` that names the rule, and where the demo shows it as its evidence.' \
  "…with one finding for each cause, naming the rule and where the demo shows it"
hasF "$TMP/verdict.demo" 'If the rig names a standard, approve only when every capture meets it.' \
  "…approves under a standard only when every capture meets it"
hasF "$TMP/verdict.demo" 'If the rig names a standard, the verdict names it.' "…names the standard"
hasF "$TMP/verdict.demo" 'lists each screen and message you checked against it, in which states, and each screen, message or state you could not check, with what stopped it.' \
  "…and lists what it checked against the standard and what it could not"
hasF "$TMP/verdict.demo" 'The PR shows only the demo, so this list is how a person sees what the check covered.' \
  "…which is how a person sees what the check covered"
hasF "$DEMO" 'The page renders at 1280 by 900 by default.' "a page's capture size has a stated default"
hasF "$DEMO" 'line can name another size, such as `390x844`, or a device the engine knows by name' \
  "…which the script's Device line can change"
hasF "$DEMO" 'A `resize <width>x<height>` step changes the size from that step on.' "…as a resize step can"
hasF "$ROOT/skills/review-pm/SKILL.md" "whether a visual proves its claim and whether a screen or message meets the rig's standards." \
  "the pm method leaves the rig's standards to the demo check"

echo "# the pm method says when triage adds it, and asks a rig once for missing product goals"
PM="$ROOT/skills/review-pm/SKILL.md"
awk '/^### When triage adds it$/ {f = 1; next} f && /^#/ {exit} f' "$PM" > "$TMP/pm.triage"
hasF "$TMP/pm.triage" "Triage adds \`pm\` when the diff changes what the rig's product does for the people it serves, or what it promises them" \
  "triage adds pm for a change to what the rig's product does for the people it serves"
hasF "$TMP/pm.triage" 'including a fix that changes how the product behaves for them' "…a fix that changes how it behaves for them included"
hasF "$TMP/pm.triage" 'A diff that adds or changes that page makes this check mandatory.' "…and always for a change to the product goals page"
hasF "$TMP/pm.triage" 'An edit that changes neither what the product does for the people it serves nor what it promises them, such as a refactor, a typo fixed or a link mended, needs no product review.' \
  "…but not for an edit that changes neither what the product does for them nor what it promises them"
hasF "$TMP/pm.triage" 'neither do tests and the fixtures they use' "…or for tests and their fixtures"
awk '/^### A rig with no product goals$/ {f = 1; next} f && /^#/ {exit} f' "$PM" > "$TMP/pm.missing"
hasF "$TMP/pm.missing" "judge the change against the anchor's stated problem alone" "with no product goals, a pm review judges the change against its anchor alone"
hasF "$TMP/pm.missing" 'no finding asks the change to add it' "…asks the change for no page"
hasF "$TMP/pm.missing" '`docs/product-goals.md: missing`' "…files one request for the page under one token"
hasF "$TMP/pm.missing" "Add \`--all\` to that duplicate probe's \`gc bd list\`" "…whose duplicate probe counts a request that has closed"
notF "$PM" 'reading of `docs/foundation.md`' "the pm method defines the goals page without the foundation doc only this repo keeps"

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
