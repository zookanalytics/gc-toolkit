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
#   * scope: tests, specs and generated/ are not writers or readers.
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
