#!/usr/bin/env bash
# formula-unquoted-for.sh — hardened learned rule: no formula shell block
# iterates an UNQUOTED expansion (ported from the retired
# doctor/check-formula-shell-portability). Formula blocks are pasted into
# whatever shell the agent has; zsh does NOT word-split unquoted $VAR or
# $(cmd), so `for X in $LIST` runs the body ONCE on the whole joined list —
# the per-element command fails on the joined token and the step reports an
# honest-looking failure having silently skipped every real element. Scope:
# fenced shell blocks in */formulas/*.toml only; quoted lists, literal/glob
# lists, and zsh's explicit ${=VAR} split are all fine. No exception list.
# Fix: capture to a file and `while IFS= read -r X; do …; done < "$FILE"`.
# Exit: 0 clean, 1 findings as `<file>:<line>: <message>`.

set -uo pipefail

# Extraction/classification in awk so quote-stripping is done by something
# that can see a quote; heredoc'd so its own single quotes survive.
SCAN_AWK=$(cat <<'AWKEOF'
function is_shell_fence(l,   lang) {
    lang = l
    sub(/^[[:space:]]*```[[:space:]]*/, "", lang)
    sub(/[[:space:]].*$/, "", lang)
    return (lang == "" || lang == "bash" || lang == "sh" || lang == "shell")
}
# True when s still holds an expansion after every QUOTED span is removed.
function unquoted_expansion(s,   t) {
    t = s
    gsub(/\$\{=[^}]*\}/, " ", t)   # ${=VAR}: zsh's explicit split — sanctioned
    gsub(/'[^']*'/, " ", t)
    gsub(/"[^"]*"/, " ", t)
    sub(/#.*$/, "", t)
    return (t ~ /\$/ || t ~ /`/)
}
# The word list of a for-statement: after `in`, up to the `;` or `do` that
# ends it — without the truncation the BODY would be scanned too.
function word_list(s,   rest, p) {
    rest = s
    if (!match(rest, /(^|[;&|(){}]|\$\(|[[:space:]](do|then|else))[[:space:]]*for[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]+in[[:space:]]/)) return ""
    rest = substr(rest, RSTART + RLENGTH)
    p = index(rest, ";")
    if (p > 0) rest = substr(rest, 1, p - 1)
    if (match(rest, /[[:space:]]do([[:space:]]|$)/)) rest = substr(rest, 1, RSTART - 1)
    return rest
}
/^[[:space:]]*```/ {
    if (inb) { inb = 0 } else { inb = is_shell_fence($0) }
    next
}
!inb { next }
{
    # Join backslash continuations so a spread-out list is judged whole.
    if (pending != "") { text = pending " " $0 } else { text = $0; start = FNR }
    if (text ~ /\\+[[:space:]]*$/) { sub(/\\+[[:space:]]*$/, "", text); pending = text; next }
    pending = ""
    stripped = text
    sub(/^[[:space:]]+/, "", stripped)
    if (stripped ~ /^#/) next
    list = word_list(text)
    if (list == "") next
    if (unquoted_expansion(list)) print start ":" stripped
}
AWKEOF
)

found=0
for f in "$@"; do
    [ -f "$f" ] || continue
    case "$f" in */lint-learned.d/* | */base-snapshots/*) continue ;; esac
    case "$f" in */formulas/*.toml | formulas/*.toml) ;; *) continue ;; esac
    while IFS= read -r hit; do
        [ -n "$hit" ] || continue
        no="${hit%%:*}"
        echo "$f:$no: formula shell block iterates an UNQUOTED expansion — zsh does not word-split, so the body runs once on the joined list; capture to a file and \`while IFS= read -r X\`, or write \${=VAR} and mean it (learned rule: formula-unquoted-for)"
        found=1
    done < <(awk "$SCAN_AWK" "$f" 2>/dev/null)
done

[ "$found" -eq 0 ]
