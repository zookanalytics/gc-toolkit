#!/usr/bin/env bash
# step-number-citation.test.sh — no text names another text's step by its
# number.
#
# A formula step numbers its parts by their place in its text, and so do a skill
# and a prompt. A rewrite renumbers them. A number cited from another text has
# nothing tying it to the part it meant, so the rewrite leaves the citation
# naming another part or none, and a search for the number cannot find it. A
# text names another text's step by its id, a marked block's name, the skill,
# the command the step runs, or what the step does (docs/pack-authoring.md, "A
# text names another text's step by what it is").
#
# This suite fails a step or part number that the citation itself gives to
# another text: one after a possessive, one after a backquoted name, one after
# the name of a formula, a formula step or a skill, and one followed by "of" and
# such a name or a kind of text, such as a formula, a prompt or a skill. A bare
# number is the text's own and passes. A citation that a line break splits is
# read across the break, and a blank line ends the text it joins.
#
# Every tracked text file is read except generated/, whose renders are checked
# at their source, specs/, which records what was true when each was written,
# and this suite, whose cases quote the forms it fails.
#
# Hermetic: reads tracked files through git ls-files and git grep. No gc, no
# city, no network.
#
# run-tests-scope: tree
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SELF="assets/scripts/step-number-citation.test.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-step-number-citation-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }

# names <root> — the names a citation can give a number to, as one ERE
# alternation: each formula's name, each formula step's id, each skill, and
# submit, the name the pack's texts give submit-and-exit.
names() {
  local root="$1"
  {
    echo submit
    git -C "$root" ls-files -- 'formulas/*.toml' 'packs/*/formulas/*.toml' \
      | while IFS= read -r f; do
          sed -n -E 's/^(id|formula) = "([a-z0-9][a-z0-9_-]*)".*/\2/p' "$root/$f"
        done
    git -C "$root" ls-files -- 'skills/*/SKILL.md' 'packs/*/skills/*/SKILL.md' \
      | sed -E 's#^(packs/[^/]+/)?skills/([^/]+)/SKILL\.md$#\2#'
  } | tr '[:upper:]' '[:lower:]' | grep -x -E '[a-z0-9_-]+' | sort -u | paste -sd'|' -
}

# scan <root> — each citation in the tree at <root> that gives a step or part
# number to another text, as `<file>:<line>: <the line>`. Returns 2 when git
# cannot list the tree's files, which must never read as a tree with none.
scan() {
  local root="$1" alts listed
  alts="$(names "$root")" || return 2
  [ -n "$alts" ] || return 2
  listed="$(git -C "$root" grep -I -l -i -E -e 'step' -e 'part' -- . \
      ':(exclude)generated/' ':(exclude)specs/' ":(exclude)$SELF")"
  case $? in 0|1) ;; *) return 2 ;; esac
  [ -n "$listed" ] || return 0
  ( cd "$root" && printf '%s\n' "$listed" | tr '\n' '\0' | xargs -0 awk -v names="$alts" '
    BEGIN {
      N = "(step|part)s?[ -]?[0-9]"
      POSS = "[a-z0-9_.)`-]+(\047s|\047|\342\200\231s)[[:space:]]+(own[[:space:]]+)?" N
      QUOTED = "`[^`]+`[[:space:]]+" N
      NAMED = "(^|[^a-z0-9_.-])(" names ")[[:space:]]+" N
      HYPHENATED = "(^|[^a-z0-9_.-])([a-z0-9_.]+-[a-z0-9_.-]+)[,:][[:space:]]+" N
      OF = "(step|part)s?[ -][0-9]+[a-z]?[[:space:]]+of[[:space:]]+((the|that|this|its|a|an)[[:space:]]+)?(formula|prompt|skill|fragment|template|step|" names ")([^a-z0-9_-]|$)"
    }
    FNR == 1 { tail = "" }
    {
      line = tolower($0)
      sub(/^[[:space:]]*(#+|\/\/+|;+|--|\*+|>+)?[[:space:]]*/, "", line)
      if (line == "") { tail = ""; next }
      joined = (tail == "") ? line : tail " " line
      before = (tail == "") ? 0 : length(tail) + 1
      if (found(joined, POSS, before, "poss") || found(joined, QUOTED, before, "") \
          || found(joined, NAMED, before, "") || found(joined, HYPHENATED, before, "named") \
          || found(joined, OF, before, ""))
        printf "%s:%d: %s\n", FILENAME, FNR, $0
      tail = (length(line) > 60) ? substr(line, length(line) - 59) : line
    }
    # found s re before kind — whether re matches s in a stretch that reaches past
    # the first <before> characters, which the previous line already had judged.
    # A possessive that is a contraction (it is, that is) names no text, and a
    # hyphenated name before a comma or colon counts only when it is a name above.
    function found(s, re, before, kind,    off) {
      off = 0
      while (match(s, re)) {
        if (off + RSTART + RLENGTH - 1 > before && admitted(substr(s, RSTART, RLENGTH), kind)) return 1
        off += RSTART + RLENGTH - 1
        s = substr(s, RSTART + RLENGTH)
      }
      return 0
    }
    function admitted(m, kind,    w) {
      if (kind == "poss") {
        w = m
        sub(/(\047s|\047|\342\200\231s)[[:space:]].*$/, "", w)
        return w !~ /^(it|that|there|what|here|let|who|he|she)$/
      }
      if (kind == "named") {
        w = m
        sub(/^[^a-z0-9_.]/, "", w)
        sub(/[,:][[:space:]].*$/, "", w)
        return w ~ ("^(" names ")$")
      }
      return 1
    }
  ' )
}

echo "--- the scan tells a citation of another text's step from a text's own ---"
FIX="$TMP/fixture"
mkdir -p "$FIX/formulas" "$FIX/skills/hold-it" "$FIX/docs" "$FIX/generated" "$FIX/specs"
git -C "$FIX" init -q
cat >"$FIX/formulas/mol-demo.toml" <<'EOF'
formula = "mol-demo"
[[steps]]
id = "submit-and-exit"
[[steps]]
id = "merge-push"
[[steps]]
id = "recover-orphaned-beads"
[[steps]]
id = "review"
EOF
printf -- '---\nname: hold-it\n---\n' >"$FIX/skills/hold-it/SKILL.md"
# Each line that names another text's number says so as its last word: cited.
cat >"$FIX/docs/cases.md" <<'EOF'
landing branch (resolved once, in submit step 1b) cited
Submit step 4's `--anchor-only` call prints it. cited
The rule reaches a title only through submit's step 4. cited
Find or file its tracker as preflight-tests' step 3 does. cited
a warrant (the formula's step 2b carries the command) cited
exactly as `formulas/mol-demo.toml`'s `review` step 5b specifies. cited
the hold skill's own step-3 block runs here cited
THE BUG: mol-demo Step 2 salvage reads the bead. cited
(formulas/mol-demo.toml merge-push step 4). cited
Callers: mol-demo's submit-and-exit, step 0. cited
it hands the bead on in part 5 of recover-orphaned-beads. cited
the hold-it step 3 block writes held. cited
the launch delivers the prompt, and step 1
of that prompt is the claim block. cited
the rule runs in submit
step 4 as written. cited
the submit’s step 4 loads the skill. cited

go to step 2 and continue the step you are on.
close this step (step 4).
Step 1's restart rule names later steps by number.
the step-5 hold and the step-7 sign-off both.
it's step 2 that runs, and that's step 3.
re-open it at steps 3–4 and then step 5.
step 1 of 3 runs first.
the next step: run it, then a two-step check.
`work-submit.sh --anchor-only` prints it.
the `warrant-file` block of recover-orphaned-beads.
a re-run, step 2 of this list, comes after.
the merge-push step closes it.
then submit.
Step 2 opens this paragraph.
EOF
printf 'the formula'"'"'s step 2b carries it.\n' >"$FIX/generated/render.md"
printf 'the formula'"'"'s step 2b carries it.\n' >"$FIX/specs/record.md"
git -C "$FIX" add -A
OUT="$(scan "$FIX")"; RC=$?
eq "$RC" 0 "the scan reads a fixture tree"
want="$(grep -n ' cited$' "$FIX/docs/cases.md" | cut -d: -f1 | paste -sd' ' -)"
got="$(printf '%s\n' "$OUT" | sed -n 's#^docs/cases\.md:\([0-9]*\):.*#\1#p' | paste -sd' ' -)"
eq "$got" "$want" "the scan names each citation of another text's step, and no text's own step"
if grep -q -e '^generated/' -e '^specs/' <<< "$OUT"; then
  bad "the scan reads no render and no spec: $OUT"
else
  ok "the scan reads no render and no spec"
fi
NOGIT="$TMP/not-a-repo"; mkdir -p "$NOGIT"
scan "$NOGIT" >/dev/null 2>&1; RC=$?
eq "$RC" 2 "a tree git cannot list is an error, not a clean tree"

echo "--- no text in the tree names another text's step by its number ---"
OUT="$(scan "$ROOT")"; RC=$?
eq "$RC" 0 "the scan reads the tree"
if [ -z "$OUT" ]; then
  ok "every step a text names in another text is named by what it is"
else
  bad "a text names another text's step by its number; name the step by its id, a marked block, the skill, the command it runs, or what it does:"
  printf '%s\n' "$OUT" | sed 's/^/    /'
fi

echo
echo "step-number-citation: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
