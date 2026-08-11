#!/usr/bin/env bash
# Hermetic test for doctor/check-pipefail-grep-q (tk-zfjg9).
#
# THE BUG the check guards: `printf ... | grep -q PAT` under `set -o pipefail`.
# `grep -q` exits at its first match, the writer takes SIGPIPE, pipefail promotes
# the 141, and a match that SUCCEEDED is reported as a failure. It is a race on
# how much the writer flushed, so the same line is silent at 105 B and fires 76%
# of the time at 64 KB — which is why the rule needs a check rather than a
# convention.
#
# What is exercised here:
#   * the ERROR arm, and that it names file, line and the offending text;
#   * the pipefail SCOPE — the identical line in a file that sets no pipefail is
#     correctly NOT flagged, because with no promotion `grep -q` answers right;
#   * `||` adjacency, which is not a pipe and must never be flagged (the pack has
#     a live instance: quota-park-nudge.test.sh's two file greps);
#   * comments, which quote the banned shape all over this pack — including in
#     the check's own header — and must not be findings;
#   * the quiet-flag spellings actually in use (-q, -qxF, -Fxq, -qiE, --quiet);
#   * every accepted remedy — here-string, process substitution, </dev/null —
#     recognised as clean, so the check cannot demand a shape nobody can write;
#   * marker-fenced snippets in non-shell files, which their tests EXTRACT and
#     run under the extracting suite's pipefail, so the defect travels with the
#     snippet even though a .toml sets nothing itself;
#   * base-snapshots exclusion (vendored upstream, never executed);
#   * the SHIPPED pack tree, asserted clean — the regression anchor. If a future
#     change reintroduces the pattern anywhere, this line goes red.
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

# The banned shape is assembled at runtime and never written literally in this
# file: the check scans every pipefail-setting *.sh in the pack, this file is
# one, and a fixture spelled out in full would make the suite flag itself.
G='grep'
BAD_PIPE="| $G -q"

run() { GC_PACK_DIR="$1" bash "$CHECK" 2>&1; }
rc_of() { GC_PACK_DIR="$1" bash "$CHECK" >/dev/null 2>&1; echo $?; }

# --- 1. the ERROR arm -------------------------------------------------------
mkdir -p "$TMP/dirty"
{
    echo '#!/usr/bin/env bash'
    echo 'set -euo pipefail'
    printf '%s\n' "printf '%s\\n' \"\$OUT\" $BAD_PIPE NEEDLE && ok || bad"
} > "$TMP/dirty/offender.sh"

OUT1="$(run "$TMP/dirty")"
eq "$(rc_of "$TMP/dirty")" "2" "(1) a pipefail file piping into grep -q is an ERROR (exit 2)"
has "$OUT1" "offender.sh:3" "(2) the finding names the file and the line"
has "$OUT1" "NEEDLE" "(3) the finding quotes the offending text"
has "$OUT1" '<<<' "(4) the message names the here-string remedy"

# --- 2. scope: no pipefail, no finding --------------------------------------
mkdir -p "$TMP/nopf"
{
    echo '#!/usr/bin/env bash'
    echo 'set -eu'
    printf '%s\n' "printf '%s\\n' \"\$OUT\" $BAD_PIPE NEEDLE && ok || bad"
} > "$TMP/nopf/fine.sh"
eq "$(rc_of "$TMP/nopf")" "0" "(5) the same line without pipefail is NOT flagged — no promotion, no defect"

# A file that only MENTIONS pipefail in prose is not a pipefail file.
mkdir -p "$TMP/prose"
{
    echo '#!/usr/bin/env bash'
    echo 'set -eu'
    echo '# This script deliberately does not set -o pipefail.'
    printf '%s\n' "printf '%s\\n' \"\$OUT\" $BAD_PIPE NEEDLE && ok || bad"
} > "$TMP/prose/fine.sh"
eq "$(rc_of "$TMP/prose")" "0" "(6) a comment mentioning pipefail does not put a file in scope"

# --- 3. || is not a pipe ----------------------------------------------------
mkdir -p "$TMP/orr"
{
    echo '#!/usr/bin/env bash'
    echo 'set -euo pipefail'
    echo "if $G -qF \"\$v\" \"\$DOC\" || $G -qF \"_\$v\" \"\$DOC\"; then :; fi"
} > "$TMP/orr/fine.sh"
eq "$(rc_of "$TMP/orr")" "0" "(7) two file greps joined by || are not a pipeline and are not flagged"

# --- 4. comments are not findings -------------------------------------------
mkdir -p "$TMP/cmt"
{
    echo '#!/usr/bin/env bash'
    echo 'set -euo pipefail'
    echo "# Never write printf '%s' \"\$V\" $BAD_PIPE PAT — it SIGPIPEs under pipefail."
    echo "    # indented explanation of printf \"\$V\" $BAD_PIPE PAT as well"
    echo "$G -q PAT <<< \"\$V\" && ok || bad"
} > "$TMP/cmt/fine.sh"
eq "$(rc_of "$TMP/cmt")" "0" "(8) the shape quoted in a comment is not a finding"

# --- 5. quiet-flag spellings ------------------------------------------------
for flag in '-q' '-qxF' '-Fxq' '-qiE' '--quiet'; do
    d="$TMP/flag$(printf '%s' "$flag" | tr -dc 'A-Za-z')"
    mkdir -p "$d"
    {
        echo '#!/usr/bin/env bash'
        echo 'set -euo pipefail'
        printf '%s\n' "printf '%s\\n' \"\$V\" | $G $flag PAT && ok || bad"
    } > "$d/x.sh"
    eq "$(rc_of "$d")" "2" "(9) quiet spelling '$flag' is detected"
done

# A non-quiet grep is NOT a finding: it drains its input, so nothing SIGPIPEs.
mkdir -p "$TMP/loud"
{
    echo '#!/usr/bin/env bash'
    echo 'set -euo pipefail'
    printf '%s\n' "printf '%s\\n' \"\$V\" | $G -E PAT > /dev/null && ok || bad"
} > "$TMP/loud/x.sh"
eq "$(rc_of "$TMP/loud")" "0" "(10) a non-quiet grep drains its input and is not flagged"

# --- 6. every accepted remedy is clean --------------------------------------
mkdir -p "$TMP/clean"
{
    echo '#!/usr/bin/env bash'
    echo 'set -euo pipefail'
    echo "$G -q PAT <<< \"\$VAR\" && ok || bad"
    echo "$G -q PAT < <(some_command --with args) && ok || bad"
    echo "$G -Eq -- \"\$RE\" </dev/null >/dev/null 2>&1 || rc=\$?"
    printf '%s\n' "$G -qxF -- \"\$x\" <<< \"\${LIST//,/\$'\\n'}\" && ok || bad"
} > "$TMP/clean/fine.sh"
OUT2="$(run "$TMP/clean")"
eq "$(rc_of "$TMP/clean")" "0" "(11) here-string, process substitution, </dev/null and \${VAR//,/} are all clean"
has "$OUT2" "OK:" "(12) the clean run reports OK"

# --- 7. marker-fenced snippets in non-shell files ---------------------------
# The .toml sets no shell options of its own; the test that extracts it does.
mkdir -p "$TMP/snip"
{
    echo 'description = """'
    echo '# >>> some-snippet'
    printf '%s\n' "printf '%s\\n' \"\$OUT\" $BAD_PIPE SNIPNEEDLE && ok || bad"
    echo '# <<< some-snippet'
    echo '"""'
} > "$TMP/snip/formula.toml"
OUT3="$(run "$TMP/snip")"
eq "$(rc_of "$TMP/snip")" "2" "(13) a marker-fenced snippet carrying the shape is flagged"
has "$OUT3" "extracted snippet" "(14) the finding says it came from an extracted snippet"
has "$OUT3" "SNIPNEEDLE" "(15) the snippet finding quotes the offending line"

# ...but the same shape OUTSIDE the markers is prose, not an executed snippet.
mkdir -p "$TMP/snipout"
{
    echo 'description = """'
    echo "Agents may run: printf '%s' \"\$M\" $BAD_PIPE PAT (their own shell, no pipefail)."
    echo '# >>> some-snippet'
    echo "$G -q PAT <<< \"\$OUT\" && ok || bad"
    echo '# <<< some-snippet'
    echo '"""'
} > "$TMP/snipout/formula.toml"
eq "$(rc_of "$TMP/snipout")" "0" "(16) the shape outside the snippet markers is not executed and not flagged"

# --- 8. vendored snapshots are out of scope ---------------------------------
mkdir -p "$TMP/vend/doctor/check-x/base-snapshots/assets/scripts"
{
    echo '#!/usr/bin/env bash'
    echo 'set -euo pipefail'
    printf '%s\n' "printf '%s\\n' \"\$OUT\" $BAD_PIPE NEEDLE && ok || bad"
} > "$TMP/vend/doctor/check-x/base-snapshots/assets/scripts/upstream.sh"
eq "$(rc_of "$TMP/vend")" "0" "(17) vendored base-snapshots are not executed and are excluded"

# --- 9. nothing to check ----------------------------------------------------
mkdir -p "$TMP/empty"
OUT4="$(run "$TMP/empty")"
eq "$(rc_of "$TMP/empty")" "0" "(18) an empty tree is OK, not an error"
has "$OUT4" "nothing to check" "(19) the empty-tree message says so plainly"

# --- 10. the shipped pack is clean (regression anchor) ----------------------
OUT5="$(run "$ROOT")"
eq "$(rc_of "$ROOT")" "0" "(20) the shipped pack tree has no pipeline feeding grep -q under pipefail"
hasnt "$OUT5" "pipeline(s) feed" "(21) the shipped pack produces no findings"

echo
echo "check-pipefail-grep-q: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
