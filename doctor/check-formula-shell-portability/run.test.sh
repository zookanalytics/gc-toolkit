#!/usr/bin/env bash
# Hermetic test for doctor/check-formula-shell-portability (tk-1c9vf).
#
# THE BUG the check guards: `for C in $IDS` in a formula shell block. zsh — the
# shell an agent actually pastes these blocks into — performs NO word splitting
# on an unquoted expansion, so the body runs ONCE with every id joined into a
# single token. Measured on the `worked-via-convoy` loop this check's first fix
# removed: under bash three convoys resolved, under zsh WORKED came back `[]`
# and the pass reported `unverified` having asked about nothing.
#
# What is exercised here:
#   * the ERROR arm, and that it names file, line and the offending text;
#   * the QUOTED list — `for cand in "${A:-}" "$(cmd)"` — which is correct in
#     every shell and is the pack's dominant for-loop shape (~18 live
#     instances). A check that flagged it would be deleted within the day;
#   * literals and globs, on which both shells agree;
#   * `${=VAR}`, zsh's explicit split: the sanctioned way to ASK for splitting,
#     so the check must not punish saying so out loud;
#   * command substitution — `for x in $(cmd)` — which zsh declines to split
#     for exactly the same reason and is the same defect;
#   * the loop BODY, which must not be scanned: `for f in *.sh; do echo $f`
#     is correct, and scanning past the `do` would flag it for its body;
#   * a `for` that is not at the start of a line (`R=$(for x in $Y; do`);
#   * backslash continuations, so a list split over lines is judged whole;
#   * comments and prose, which quote the banned shape all over this pack —
#     including in this check's own header — and must never be findings;
#   * fence discipline: ```json is not shell, and text outside any fence is
#     documentation rather than something an agent pastes;
#   * scope: a non-formula path and vendored base-snapshots are not scanned;
#   * the SHIPPED pack tree, asserted clean — the regression anchor. If a
#     future change reintroduces the pattern in a formula, this line goes red.
#
# No live city, Dolt, network, or beads — only a tmpdir and the check itself.
#
# The fixtures are shell TEXT that the check reads, never shell this file runs,
# so single quotes are load-bearing: `'for C in $IDS'` must reach the fixture
# with the `$IDS` unexpanded or there is nothing to detect. Same for the
# trailing backslash in the line-continuation fixtures. Unlike
# doctor/check-pipefail-grep-q's test, this one can safely spell the banned
# shape out in full — that check scans every *.sh in the pack and would have
# flagged its own fixtures, whereas this one scans only */formulas/*.toml.
# shellcheck disable=SC2016,SC1003
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

# Write a formula fixture. Findings are reported at the line number IN THE FILE,
# so every fixture opens its fence on line 1 and the first body line is line 2.
formula() { # formula <dir> [lines...]
    local d="$TMP/$1"; shift
    mkdir -p "$d/formulas"
    { echo '```bash'; printf '%s\n' "$@"; echo '```'; } > "$d/formulas/mol-fixture.toml"
    echo "$d"
}

# --- 1. the ERROR arm -------------------------------------------------------
D=$(formula dirty 'IDS=$(jq -r ".[].id" "$F")' 'for C in $IDS; do' '  gc bd show "$C"' 'done')
OUT1="$(run "$D")"
eq "$(rc_of "$D")" "2" "(1) an unquoted expansion in a for-list is an ERROR (exit 2)"
has "$OUT1" "mol-fixture.toml:3" "(2) the finding names the file and the line"
has "$OUT1" 'for C in $IDS' "(3) the finding quotes the offending text"
has "$OUT1" 'while IFS= read -r' "(4) the message names the while-read remedy"
has "$OUT1" "FILE" "(5) the message says a file, not a pipe"

# --- 2. the quoted list, the pack's dominant shape --------------------------
D=$(formula quoted \
    'for cand in "${GC_RIG_ROOT:-}" "$(git rev-parse --show-toplevel 2>/dev/null)"; do' \
    '  [ -d "$cand" ] && break' \
    'done')
eq "$(rc_of "$D")" "0" "(6) a list of QUOTED expansions is one word each in every shell — not flagged"

# --- 3. literals and globs --------------------------------------------------
D=$(formula literal 'for MR_STATE in pull_request pre_open_gate; do' '  echo "$MR_STATE"' 'done')
eq "$(rc_of "$D")" "0" "(7) a literal list is not flagged"
D=$(formula glob 'for d in "$BACKUP_ROOT"/*/; do' '  [ -d "$d" ] || continue' 'done')
eq "$(rc_of "$D")" "0" "(8) a glob list is not flagged — both shells expand it"

# --- 4. the sanctioned explicit split ---------------------------------------
D=$(formula explicit 'for X in ${=WANTED_SPLIT}; do' '  echo "$X"' 'done')
eq "$(rc_of "$D")" "0" "(9) \${=VAR}, zsh's explicit split, is the sanctioned form and is not flagged"

# --- 5. command substitution is the same defect -----------------------------
D=$(formula cmdsub 'for N in $(seq 1 "$LIMIT"); do' '  echo "$N"' 'done')
eq "$(rc_of "$D")" "2" "(10) an unquoted \$(cmd) list is flagged — zsh does not split it either"
D=$(formula backtick 'for N in `cat "$F"`; do' '  echo "$N"' 'done')
eq "$(rc_of "$D")" "2" "(11) a backtick list is flagged too"

# --- 6. the loop BODY is not the word list ----------------------------------
D=$(formula body 'for f in *.sh; do' '  echo $f' 'done')
eq "$(rc_of "$D")" "0" "(12) an unquoted expansion in the BODY is not a finding — only the word list is scanned"
D=$(formula oneline 'for f in *.sh; do echo $f; done')
eq "$(rc_of "$D")" "0" "(13) the same on one line — the scan stops at the ';'"

# --- 7. a `for` that does not start the line --------------------------------
D=$(formula midline 'ROOTS=$(for convoy in $CONVOYS; do' '  gc bd list --json' 'done)')
OUT7="$(run "$D")"
eq "$(rc_of "$D")" "2" "(14) a for-loop inside a command substitution is still found"
has "$OUT7" 'for convoy in $CONVOYS' "(15) the mid-line finding quotes the loop"

# --- 8. backslash continuations are judged whole ----------------------------
# The unquoted element is on the CONTINUATION line; the `for` is on the first.
D=$(formula cont 'for cand in "${A:-}" \' '    $UNQUOTED; do' '  echo "$cand"' 'done')
eq "$(rc_of "$D")" "2" "(16) a list continued with a backslash is joined before judging"
D=$(formula contclean 'for cand in "${A:-}" \' '    "${B:-}"; do' '  echo "$cand"' 'done')
eq "$(rc_of "$D")" "0" "(17) a continued list that stays quoted is clean"

# --- 9. comments and prose are not findings ---------------------------------
D=$(formula comment '# never write `for C in $IDS` — zsh will not split it' '  # nor indented: for R in $RIGS' 'echo ok')
eq "$(rc_of "$D")" "0" "(18) the shape quoted in a comment is not a finding"

mkdir -p "$TMP/prose/formulas"
{
    echo 'The old loop was `for C in $INPUT_CONVOYS`, which zsh runs once.'
    echo '```bash'
    echo 'while IFS= read -r C; do echo "$C"; done < "$LIST"'
    echo '```'
} > "$TMP/prose/formulas/mol-fixture.toml"
eq "$(rc_of "$TMP/prose")" "0" "(19) the shape in prose OUTSIDE a fence is documentation, not code"

# --- 10. fence discipline ---------------------------------------------------
mkdir -p "$TMP/json/formulas"
{
    echo '```json'
    echo 'for C in $IDS; do'
    echo '```'
} > "$TMP/json/formulas/mol-fixture.toml"
eq "$(rc_of "$TMP/json")" "0" "(20) a json-tagged fence is not a shell block"

# A bare ``` fence IS scanned: formula TOMLs use it for shell too.
mkdir -p "$TMP/bare/formulas"
{
    echo '```'
    echo 'for C in $IDS; do echo "$C"; done'
    echo '```'
} > "$TMP/bare/formulas/mol-fixture.toml"
eq "$(rc_of "$TMP/bare")" "2" "(21) a bare, language-less fence is scanned — formula TOMLs use it for shell"

# --- 11. scope --------------------------------------------------------------
mkdir -p "$TMP/elsewhere/docs"
{ echo '```bash'; echo 'for C in $IDS; do echo "$C"; done'; echo '```'; } \
    > "$TMP/elsewhere/docs/runbook.md"
eq "$(rc_of "$TMP/elsewhere")" "0" "(22) a non-formula path is out of scope"

mkdir -p "$TMP/vend/doctor/check-x/base-snapshots/formulas"
{ echo '```bash'; echo 'for C in $IDS; do echo "$C"; done'; echo '```'; } \
    > "$TMP/vend/doctor/check-x/base-snapshots/formulas/mol-upstream.toml"
eq "$(rc_of "$TMP/vend")" "0" "(23) vendored base-snapshots are never executed and are excluded"

# --- 12. nothing to check ---------------------------------------------------
mkdir -p "$TMP/empty"
OUT12="$(run "$TMP/empty")"
eq "$(rc_of "$TMP/empty")" "0" "(24) a tree with no formula is OK, not an error"
has "$OUT12" "nothing to check" "(25) the empty-tree message says so plainly"

# --- 13. every finding is reported, not just the first ----------------------
D=$(formula many 'for A in $ONE; do echo "$A"; done' 'for B in $TWO; do echo "$B"; done')
OUT13="$(run "$D")"
eq "$(rc_of "$D")" "2" "(26) multiple offenders are an error"
has "$OUT13" 'for A in $ONE' "(27) the first offender is reported"
has "$OUT13" 'for B in $TWO' "(28) the second offender is reported too"

# --- 14. the shipped pack is clean (regression anchor) ----------------------
OUT14="$(run "$ROOT")"
eq "$(rc_of "$ROOT")" "0" "(29) no shipped formula iterates an unquoted expansion"
hasnt "$OUT14" "iterate an UNQUOTED" "(30) the shipped pack produces no findings"

echo
echo "check-formula-shell-portability: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
