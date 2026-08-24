#!/usr/bin/env bash
# Hermetic test for doctor/check-state-space-declared (tk-jozah0).
#
# THE BUG the check guards: `merge_result` had seven values written across five
# files and no declaration anywhere, so every reader kept its own hand-rolled
# list and the lists disagreed on the value none of them had heard of — one read
# an unknown as *not yet anchored* and reported it forever, the other read it as
# *terminal* and left it alone. Neither contained `blocked` or
# `refused_false_completion`.
#
# The fixtures use SYNTHETIC state names (alpha_gate, beta_open, gamma_done,
# delta_void) rather than the pack's real ones. The mechanism is what is under
# test, and the real state space is expected to grow; a test written against it
# would have to be edited every time it does, which is exactly the maintenance
# burden the check exists to remove. The one case that does bind to reality is
# the last: the SHIPPED tree, asserted clean. That is the regression anchor.
#
# What is exercised here:
#   * the declaration is fail-closed — missing doc, empty table, a table with
#     only one kind, and an unrecognised kind are each an ERROR, never a
#     silent pass. "Nothing to check" is the state this check exists to leave
#     behind, so it must never be reachable by breaking the declaration;
#   * a write of an undeclared literal, reported with file, line and value;
#   * a declared state nothing writes — the declaration rotting into fiction,
#     which is the failure mode a doc-only fix would have shipped with;
#   * a non-literal write (`merge_result=$VAR`), which defeats the scan and so
#     must be reported rather than passed over;
#   * a hand-rolled reader: a set that is neither a declared kind-set nor
#     declared in a comment;
#   * every accepting shape — the handoff set, the disposition set, the whole
#     space, and an explicit `merge-result-reader:` declaration;
#   * a declaration that covers a state the doc does not declare, and one with
#     no default= at all: both malformed, both ERRORs. Without these the escape
#     hatch would accept anything containing the marker text;
#   * the ten-line window: a declaration too far above its reader does not
#     count, or the marker would license every list in the file below it;
#   * the shapes that are NOT readers and must never be flagged — a
#     single-value selector, a presence test, a comment, and backticked prose.
#     These names are ordinary English ("merged", "blocked", "abandoned") and
#     this pack's prose uses them on nearly every page, so a check that flagged
#     them would be turned off within the day;
#   * scope: tests, specs and generated/ are not writers or readers;
#
# and, from the pre-open review of this branch (tk-2ep3gw), the three ways the
# first cut of the check reported green over code it had not actually held:
#   * QUOTEDWRITE — the write scanner saw only the bare
#     `--set-metadata merge_result=X`, so a quoted undeclared write shipped
#     while the summary line said every literal written by pack code was
#     declared. Every CLI spelling is now scanned, and each is pinned here
#     together with its mirror, so widening the pattern cannot instead reject
#     the declared writes;
#   * COVERSDRIFT — `covers=` was only checked for naming DECLARED states, never
#     for naming THIS reader's states, so the comment could drift from the line
#     it describes and the check stayed green: the hand-rolled-list drift the
#     check exists to end, reintroduced inside its own escape hatch. The set
#     comparison is pinned, with mirrors for ordering, for an exactly-matching
#     declaration, and for `absent`;
#   * MULTILINE — reader detection was line-local, so a `case` block with one
#     state per arm was invisible and reformatting a flagged reader bypassed the
#     invariant. Grouping is pinned for case blocks, backslash continuations and
#     multi-line single-quoted jq, along with the two ways grouping itself can
#     go wrong: prose reading "so in the common case ... in" must NOT open a
#     block (this pack ships exactly that sentence), and an unbalanced `case`
#     must not swallow the rest of the file.
#
# No live city, Dolt, network, or beads — only a tmpdir and the check itself.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
CHECK="$HERE/run.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 (found '$2' in: $1)" ;; *) ok "$3" ;; esac; }

[ -x "$CHECK" ] || chmod +x "$CHECK" 2>/dev/null

run()   { GC_PACK_DIR="$1" bash "$CHECK" 2>&1; }
rc_of() { GC_PACK_DIR="$1" bash "$CHECK" >/dev/null 2>&1; echo $?; }

# A pack fixture: the standard four-state declaration plus one writer per state,
# so the "declared but never written" arm is satisfied and every other case is
# testing only what it names.
mkpack() { # mkpack <name> [decl-rows-override...]
    local d="$TMP/$1"; shift
    mkdir -p "$d/docs" "$d/assets/scripts"
    {
        echo '# fixture'
        echo '<!-- merge-result-state-space: declared -->'
        echo ''
        echo '| state | kind | written by | means |'
        echo '|---|---|---|---|'
        if [ "$#" -gt 0 ]; then
            printf '%s\n' "$@"
        else
            echo '| `alpha_gate` | handoff | w | y |'
            echo '| `beta_open` | handoff | w | y |'
            echo '| `gamma_done` | disposition | w | y |'
            echo '| `delta_void` | disposition | w | y |'
        fi
        echo ''
        echo '<!-- /merge-result-state-space -->'
    } > "$d/docs/work-bead-state-machine.md"
    {
        echo '#!/usr/bin/env bash'
        echo 'gc bd update "$1" --set-metadata merge_result=alpha_gate'
        echo 'gc bd update "$1" --set-metadata merge_result=beta_open'
        echo 'gc bd update "$1" --set-metadata merge_result=gamma_done'
        echo 'gc bd update "$1" --set-metadata merge_result=delta_void'
    } > "$d/assets/scripts/writers.sh"
    echo "$d"
}

# Append a scripts file to a fixture pack.
code() { # code <dir> <name> [lines...]
    local d="$1" n="$2"; shift 2
    mkdir -p "$d/assets/scripts"
    printf '%s\n' "$@" > "$d/assets/scripts/$n"
}

echo "# --- the declaration is fail-closed -------------------------------------"

D="$TMP/nodoc"; mkdir -p "$D/assets/scripts"; echo 'x' > "$D/assets/scripts/a.sh"
eq "$(rc_of "$D")" 2 "a missing declaration doc is an ERROR"
has "$(run "$D")" "work-bead-state-machine.md" "and it names the file it wanted"

D=$(mkpack empty '')
eq "$(rc_of "$D")" 2 "an empty declaration table is an ERROR"
has "$(run "$D")" "empty or one-sided" "and says the table is empty or one-sided"

D=$(mkpack onlyhandoff '| `alpha_gate` | handoff | w | y |')
eq "$(rc_of "$D")" 2 "a declaration with no disposition row is an ERROR"

D=$(mkpack onlydisp '| `gamma_done` | disposition | w | y |')
eq "$(rc_of "$D")" 2 "a declaration with no handoff row is an ERROR"

D=$(mkpack badkind '| `alpha_gate` | handoff | w | y |' '| `gamma_done` | disposition | w | y |' '| `zeta_odd` | terminal | w | y |')
eq "$(rc_of "$D")" 2 "a row whose kind is neither handoff nor disposition is an ERROR"
has "$(run "$D")" "zeta_odd" "and it names the offending state"

echo "# --- writes -------------------------------------------------------------"

D=$(mkpack undeclwrite)
code "$D" w2.sh '#!/usr/bin/env bash' 'gc bd update "$1" --set-metadata merge_result=omega_new'
eq "$(rc_of "$D")" 2 "writing an undeclared literal is an ERROR"
OUT="$(run "$D")"
has "$OUT" "UNDECLARED WRITE" "and it is labelled an undeclared write"
has "$OUT" "w2.sh:2" "and reported at file and line"
has "$OUT" "omega_new" "and names the literal"

D=$(mkpack deadstate '| `alpha_gate` | handoff | w | y |' '| `gamma_done` | disposition | w | y |' '| `never_written` | disposition | w | y |')
eq "$(rc_of "$D")" 2 "a declared state nothing writes is an ERROR"
has "$(run "$D")" "never_written" "and names the fictional state"

D=$(mkpack varwrite)
code "$D" w3.sh '#!/usr/bin/env bash' 'gc bd update "$1" --set-metadata merge_result=$STATE'
eq "$(rc_of "$D")" 2 "a non-literal write is an ERROR — it defeats the scan"
has "$(run "$D")" "NON-LITERAL WRITE" "and is labelled as such"

echo "# --- readers: the accepting shapes --------------------------------------"

# Each of these asserts the reader was COUNTED, not merely that the check
# exited 0. rc=0 is also what a scanner that detected nothing returns, so
# without the count these cases would pass against a broken detector — which is
# exactly how the first draft of this file did pass.
D=$(mkpack handoffset)
code "$D" r.sh '#!/usr/bin/env bash' "jq 'select(\$mr == \"alpha_gate\" or \$mr == \"beta_open\")'"
eq "$(rc_of "$D")" 0 "a reader naming exactly the handoff set passes with no comment"
has "$(run "$D")" "1 reader(s) on a declared kind-set" "and the handoff set was actually detected"

D=$(mkpack dispset)
code "$D" r.sh '#!/usr/bin/env bash' "jq 'select(\$mr == \"gamma_done\" or \$mr == \"delta_void\")'"
eq "$(rc_of "$D")" 0 "a reader naming exactly the disposition set passes"
has "$(run "$D")" "1 reader(s) on a declared kind-set" "and the disposition set was detected"

D=$(mkpack allset)
code "$D" r.sh '#!/usr/bin/env bash' "jq '[\"alpha_gate\",\"beta_open\",\"gamma_done\",\"delta_void\"] | index(\$mr)'"
eq "$(rc_of "$D")" 0 "a reader naming the whole declared space passes"
has "$(run "$D")" "1 reader(s) on a declared kind-set" "and the whole-space set was detected"

D=$(mkpack forloop)
code "$D" r.sh '#!/usr/bin/env bash' 'for S in alpha_gate beta_open; do echo "$S"; done'
eq "$(rc_of "$D")" 0 "a for-in list naming exactly a kind-set passes"
has "$(run "$D")" "1 reader(s) on a declared kind-set" "and the for-in list was detected"

D=$(mkpack casepat)
code "$D" r.sh '#!/usr/bin/env bash' 'case "$1" in' '  alpha_gate|beta_open) echo hi ;;' 'esac'
eq "$(rc_of "$D")" 0 "a case pattern naming exactly a kind-set passes"
has "$(run "$D")" "1 reader(s) on a declared kind-set" "and the case pattern was detected"

echo "# --- readers: hand-rolled and declared ----------------------------------"

D=$(mkpack handrolled)
code "$D" r.sh '#!/usr/bin/env bash' "jq 'select(\$mr == \"alpha_gate\" or \$mr == \"gamma_done\")'"
eq "$(rc_of "$D")" 2 "a set spanning both kinds and matching neither is an ERROR"
OUT="$(run "$D")"
has "$OUT" "HAND-ROLLED READER" "and is labelled a hand-rolled reader"
has "$OUT" "r.sh:2" "and reported at file and line"
has "$OUT" "alpha_gate gamma_done" "and names the set it keys on"

D=$(mkpack declared)
code "$D" r.sh '#!/usr/bin/env bash' \
  '# merge-result-reader: covers=alpha_gate,gamma_done default=left alone, the safe direction' \
  "jq 'select(\$mr == \"alpha_gate\" or \$mr == \"gamma_done\")'"
eq "$(rc_of "$D")" 0 "the same set passes once its default is declared"
has "$(run "$D")" "1 with an explicit default" "and is counted as a declared reader"

D=$(mkpack declfar)
code "$D" r.sh '#!/usr/bin/env bash' \
  '# merge-result-reader: covers=alpha_gate,gamma_done default=left alone' \
  '#' '#' '#' '#' '#' '#' '#' '#' '#' '#' '#' \
  "jq 'select(\$mr == \"alpha_gate\" or \$mr == \"gamma_done\")'"
eq "$(rc_of "$D")" 2 "a declaration more than ten lines above its reader does not count"

D=$(mkpack declbadcov)
code "$D" r.sh '#!/usr/bin/env bash' \
  '# merge-result-reader: covers=alpha_gate,omega_new default=left alone' \
  "jq 'select(\$mr == \"alpha_gate\" or \$mr == \"gamma_done\")'"
eq "$(rc_of "$D")" 2 "a declaration covering an undeclared state is an ERROR"
has "$(run "$D")" "MALFORMED DECLARATION" "and is labelled malformed"

D=$(mkpack declnodefault)
code "$D" r.sh '#!/usr/bin/env bash' \
  '# merge-result-reader: covers=alpha_gate,gamma_done' \
  "jq 'select(\$mr == \"alpha_gate\" or \$mr == \"gamma_done\")'"
eq "$(rc_of "$D")" 2 "a declaration with no default= is an ERROR"
has "$(run "$D")" "no default=" "and says which half is missing"

echo "# --- the shapes that are NOT readers ------------------------------------"

D=$(mkpack selector)
code "$D" r.sh '#!/usr/bin/env bash' 'gc bd list --metadata-field merge_result=alpha_gate' "jq 'select(\$mr == \"beta_open\")'"
eq "$(rc_of "$D")" 0 "single-value selectors on separate lines are not a reader"
has "$(run "$D")" "0 reader(s) on a declared kind-set" "and nothing was counted as a reader"

D=$(mkpack presence)
code "$D" r.sh '#!/usr/bin/env bash' "jq 'select((.metadata.merge_result // \"\") == \"\")'" "jq 'select((.metadata.merge_result // \"\") != \"\")'"
eq "$(rc_of "$D")" 0 "presence tests are not a reader — absence is closed by construction"
has "$(run "$D")" "0 reader(s) on a declared kind-set" "and no presence test was counted"

D=$(mkpack comment)
code "$D" r.sh '#!/usr/bin/env bash' '# alpha_gate|beta_open|gamma_done are handled below' '# "alpha_gate" and "gamma_done" disagree' 'echo hi'
eq "$(rc_of "$D")" 0 "comment lines naming several states are not readers"
has "$(run "$D")" "0 reader(s) on a declared kind-set" "and no comment was counted"

D=$(mkpack prose)
mkdir -p "$D/template-fragments"
printf '%s\n' 'A pass writes `alpha_gate`, `beta_open` or `gamma_done` and moves on.' \
              'The words merged, blocked and abandoned are ordinary English here.' \
    > "$D/template-fragments/x.template.md"
eq "$(rc_of "$D")" 0 "backticked prose and bare English are not readers"


echo "# --- the write scanner sees every CLI spelling (P1, review tk-2ep3gw) ---"
# The scanner matched only the bare `--set-metadata merge_result=X`. The quoted
# form is just as ordinary and appears in this pack, and it slipped through
# while the summary line reported that every literal written by pack code was
# declared — the check stating the opposite of the truth.

D=$(mkpack quotedwrite)
code "$D" wq.sh '#!/usr/bin/env bash' 'gc bd update "$1" --set-metadata "merge_result=omega_new"'
eq "$(rc_of "$D")" 2 "QUOTEDWRITE: a QUOTED undeclared write is an ERROR"
OUT="$(run "$D")"
has "$OUT" "UNDECLARED WRITE" "QUOTEDWRITE: labelled an undeclared write"
has "$OUT" "wq.sh:2" "QUOTEDWRITE: reported at file and line"
has "$OUT" "omega_new" "QUOTEDWRITE: and names the literal, with the quote stripped"

D=$(mkpack squotedwrite)
code "$D" ws.sh '#!/usr/bin/env bash' "gc bd update \"\$1\" --set-metadata 'merge_result=omega_sq'"
eq "$(rc_of "$D")" 2 "QUOTEDWRITE: a single-quoted undeclared write is an ERROR too"
has "$(run "$D")" "omega_sq" "QUOTEDWRITE: and names that literal"

D=$(mkpack eqwrite)
code "$D" we.sh '#!/usr/bin/env bash' 'gc bd update "$1" --set-metadata=merge_result=omega_eq'
eq "$(rc_of "$D")" 2 "QUOTEDWRITE: the --set-metadata=k=v spelling is an ERROR too"
has "$(run "$D")" "omega_eq" "QUOTEDWRITE: and names that literal"

# The mirror: a DECLARED write in each spelling must still be accepted, or the
# widened pattern would fail every pack file instead of none.
D=$(mkpack quotedok)
code "$D" wok.sh '#!/usr/bin/env bash' 'gc bd update "$1" --set-metadata "merge_result=alpha_gate"' \
                                        "gc bd update \"\$1\" --set-metadata 'merge_result=gamma_done'" \
                                        'gc bd update "$1" --set-metadata=merge_result=beta_open'
eq "$(rc_of "$D")" 0 "QUOTEDWRITE: declared literals in every spelling still pass"

echo "# --- covers= must describe THIS reader (P1, review tk-2ep3gw) -----------"
# Validating only that the covered names are declared left the comment free to
# drift from the line it sits above: edit the reader, keep the stale covers=,
# and the check stays green — the hand-rolled-list drift the check exists to
# end, reintroduced inside its own escape hatch.

D=$(mkpack coversdrift)
code "$D" drift.sh '#!/usr/bin/env bash' \
    '# merge-result-reader: covers=beta_open,delta_void default=x' \
    'case "$mr" in' \
    '  alpha_gate|gamma_done) echo hi ;;' \
    'esac'
eq "$(rc_of "$D")" 2 "COVERSDRIFT: a declaration naming a different declared set is an ERROR"
OUT="$(run "$D")"
has "$OUT" "MALFORMED DECLARATION" "COVERSDRIFT: labelled a malformed declaration"
has "$OUT" "has drifted from the line it describes" "COVERSDRIFT: and says the comment drifted"
has "$OUT" "beta_open delta_void" "COVERSDRIFT: naming what the comment claims"
has "$OUT" "alpha_gate gamma_done" "COVERSDRIFT: and what the reader actually keys on"

D=$(mkpack coverspartial)
code "$D" part.sh '#!/usr/bin/env bash' \
    '# merge-result-reader: covers=alpha_gate default=x' \
    "jq 'select(\$mr == \"alpha_gate\" or \$mr == \"gamma_done\")'"
eq "$(rc_of "$D")" 2 "COVERSDRIFT: a declaration covering only SOME of the states it reads is an ERROR"

# The mirror. Without it the equality check could tighten into rejecting every
# declaration, and the escape hatch would be gone rather than fixed.
D=$(mkpack coversexact)
code "$D" exact.sh '#!/usr/bin/env bash' \
    '# merge-result-reader: covers=alpha_gate,gamma_done default=x' \
    "jq 'select(\$mr == \"alpha_gate\" or \$mr == \"gamma_done\")'"
eq "$(rc_of "$D")" 0 "COVERSDRIFT: a declaration matching its reader exactly still passes"
has "$(run "$D")" "1 with an explicit default" "COVERSDRIFT: and is counted as a declared reader"

D=$(mkpack coversorder)
code "$D" ord.sh '#!/usr/bin/env bash' \
    '# merge-result-reader: covers=gamma_done,alpha_gate default=x' \
    "jq 'select(\$mr == \"alpha_gate\" or \$mr == \"gamma_done\")'"
eq "$(rc_of "$D")" 0 "COVERSDRIFT: covers= is compared as a SET, so order does not matter"

D=$(mkpack coversabsent)
code "$D" abs.sh '#!/usr/bin/env bash' \
    '# merge-result-reader: covers=alpha_gate,gamma_done,absent default=x' \
    "jq 'select(\$mr == \"alpha_gate\" or \$mr == \"gamma_done\")'"
eq "$(rc_of "$D")" 0 "COVERSDRIFT: 'absent' is still tolerated in covers= — it is not a declared state and never a matchable literal"

echo "# --- a reader is not always one line (P1, review tk-2ep3gw) -------------"
# case/esac with one state per arm is the most ordinary multi-state
# discriminator in shell, and line-locally every arm names exactly ONE state —
# so the whole construct counted as ZERO readers and passed in silence.
# Reformatting a flagged one-line reader into a case block bypassed the
# invariant entirely.

D=$(mkpack multicase)
code "$D" mc.sh '#!/usr/bin/env bash' \
    'case "$mr" in' \
    '  alpha_gate) a ;;' \
    '  gamma_done) b ;;' \
    'esac'
eq "$(rc_of "$D")" 2 "MULTILINE: a case block with one state per arm IS a reader"
OUT="$(run "$D")"
has "$OUT" "HAND-ROLLED READER" "MULTILINE: and is reported as hand-rolled"
has "$OUT" "mc.sh:2" "MULTILINE: attributed to the case line, where its declaration belongs"
has "$OUT" "alpha_gate gamma_done" "MULTILINE: naming the set the whole block keys on"

D=$(mkpack multicasekind)
code "$D" mk.sh '#!/usr/bin/env bash' \
    'case "$mr" in' \
    '  alpha_gate) a ;;' \
    '  beta_open) b ;;' \
    'esac'
eq "$(rc_of "$D")" 0 "MULTILINE: a case block spanning exactly one kind-set passes"
has "$(run "$D")" "1 reader(s) on a declared kind-set" "MULTILINE: and is counted once, not per arm"

D=$(mkpack multicasedecl)
code "$D" md.sh '#!/usr/bin/env bash' \
    '# merge-result-reader: covers=alpha_gate,gamma_done default=x' \
    'case "$mr" in' \
    '  alpha_gate) a ;;' \
    '  gamma_done) b ;;' \
    'esac'
eq "$(rc_of "$D")" 0 "MULTILINE: a declaration above the case line covers the whole block"

D=$(mkpack multicont)
code "$D" cont.sh '#!/usr/bin/env bash' \
    'for s in alpha_gate \' \
    '         gamma_done; do echo "$s"; done'
eq "$(rc_of "$D")" 2 "MULTILINE: a backslash-continued list IS a reader"

D=$(mkpack multijq)
code "$D" mj.sh '#!/usr/bin/env bash' \
    "PROG='" \
    '  select($mr == "alpha_gate"' \
    '      or $mr == "gamma_done")' \
    "'" \
    'jq "$PROG"'
eq "$(rc_of "$D")" 2 "MULTILINE: a jq program split across lines inside a single-quoted assignment IS a reader"
has "$(run "$D")" "mj.sh:2" "MULTILINE: attributed to the assignment that opens it"

# --- and the grouping must not over-join ---------------------------------
# Each of these passed BEFORE the multi-line fix too. They are here because the
# fix is what could break them: a looser `case` test matches English, and this
# pack ships formula prose reading "in the common case the two readings
# coincide". Under a substring test that opens a phantom block which swallows
# the rest of the file, and the check starts classifying prose — its answer
# depending on wording rather than on code.
D=$(mkpack prosecase)
code "$D" pc.sh '#!/usr/bin/env bash' \
    'echo "the wrapper tracks one member, so in the common case the two readings coincide"' \
    'echo "alpha_gate"' \
    'echo "gamma_done"'
eq "$(rc_of "$D")" 0 "MULTILINE: prose saying 'case ... in' does NOT open a block"

D=$(mkpack apostrophe)
code "$D" ap.sh '#!/usr/bin/env bash' \
    'echo "do not guess what it is"' \
    'echo "alpha_gate"' \
    'echo "gamma_done"'
eq "$(rc_of "$D")" 0 "MULTILINE: an apostrophe in a double-quoted message does not open a quoted region"

# The GROUP_CAP fail-safe. An unbalanced `case` — one buried in a heredoc, say
# — would otherwise swallow the rest of the file into a single record and
# report it as one enormous reader at line 1.
D=$(mkpack runaway)
{
    echo '#!/usr/bin/env bash'
    echo 'case "$x" in'
    for i in $(seq 1 100); do echo "  filler_$i=1"; done
    echo "jq 'select(\$mr == \"alpha_gate\" or \$mr == \"gamma_done\")'"
} > "$D/assets/scripts/run.sh"
eq "$(rc_of "$D")" 2 "MULTILINE: an unbalanced case does not swallow the file — the later reader is still found"
hasnt "$(run "$D")" "run.sh:2:" "MULTILINE: and the finding is not attributed to the runaway opener"

echo "# --- scope --------------------------------------------------------------"

D=$(mkpack scope)
code "$D" 'r.test.sh' '#!/usr/bin/env bash' "jq 'select(\$mr == \"alpha_gate\" or \$mr == \"gamma_done\")'"
mkdir -p "$D/specs/x" "$D/generated/y"
printf '%s\n' 'jq "select($mr == "alpha_gate" or $mr == "gamma_done")"' > "$D/specs/x/note.md"
printf '%s\n' 'jq "select($mr == "alpha_gate" or $mr == "gamma_done")"' > "$D/generated/y/rendered.md"
eq "$(rc_of "$D")" 0 "tests, specs and generated/ are neither writers nor readers"

echo "# --- the shipped pack tree ----------------------------------------------"

RC=$(rc_of "$ROOT")
eq "$RC" 0 "the shipped pack tree satisfies the declared state space"
OUT="$(run "$ROOT")"
has "$OUT" "OK:" "and reports OK"
hasnt "$OUT" "HAND-ROLLED READER" "with no hand-rolled reader left in it"

echo ""
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ]
