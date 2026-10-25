#!/usr/bin/env bash
# review-methods.test.sh — a check's method is the skill named from the check,
# held by iterating the pack's index rather than by any list of checks.
#
#   - Every row of the pack's review-checks.toml has skills/review-<check>/,
#     whose SKILL.md is named review-<check> and has a `## The verdict` section,
#     and every skills/review-* directory has a row.
#   - Every signoff.sh flag a check's verdict section names is one signoff.sh
#     accepts, and every skill a check's skill says to load is one the pack ships.
#   - The correctness method reads the work-quality fragments and the exemplar
#     corpus from its own references/ directory, through relative links that
#     resolve to template-fragments/, and resolves no pack file by path.
#   - A rig index that adds a check with no skill resolves it to its purpose
#     through --check, and a token no index declares resolves to nothing, which
#     are the two no-skill cases the review formulas send a reviewer to.
#   - Each region the review formulas repeat across steps, the method load, the
#     record check and the gather, is the same text in every step carrying it.
#   - Neither review formula names a check's judgment: no test or suite, no
#     P0, P1 or P2 grade, no Verification line, and neither the correctness
#     method's What to check list nor any dimension of it. The correctness
#     method is method alone: it carries no shell block and reads no record
#     itself, because the review formula gathers what it reads.
#   - The arch skill approves no commit without a docs/architecture.md, files a
#     gap in architecture the change does not touch without holding the change,
#     and passes no change on a gap in architecture it does touch. This repo's
#     own docs/review-arch.md and docs/review-triage.md, read the way a review
#     reads them at its commit, carry the divergence lens and the changes that
#     make arch mandatory, and the pack's arch skill carries none of that lens.
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

echo "# a region the review formulas repeat is one text in every step carrying it"
python3 - "$ROOT/formulas/mol-review.toml" "$ROOT/formulas/mol-review-quorum-signoff.toml" > "$TMP/regions" <<'PY'
import sys, tomllib, re, json
out = {}
for path in sys.argv[1:]:
    d = tomllib.load(open(path, 'rb'))
    for s in d['steps']:
        text = s['description']
        for m in re.finditer(r'(?:<!-- |# )>>> (review-method-load|review-record-check|review-gather)(?: -->)?\n(.*?)\n(?:<!-- |# )<<< \1', text, re.S):
            out.setdefault(m.group(1), []).append([d['formula'] + '.' + s['id'], m.group(2)])
print(json.dumps(out))
PY
for r in review-method-load:4 review-record-check:4 review-gather:4; do
  name=${r%%:*}; want=${r#*:}
  eq "$(jq -r --arg r "$name" '.[$r] | length' "$TMP/regions")" "$want" "$name: the steps that carry it carry it ($want)"
  eq "$(jq -r --arg r "$name" '[.[$r][][1]] | unique | length' "$TMP/regions")" "1" "$name: every copy is the same text"
done
case "$(jq -r '."review-method-load"[0][1]' "$TMP/regions")" in
  *'`{{binding_prefix}}review-{{check}}`'*'`{{binding_prefix}}specialist-stance`'*) ok "the method load names the skill from the check, and the stance for the purpose case" ;;
  *) bad "the method load names the skill from the check, and the stance for the purpose case" ;;
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

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
