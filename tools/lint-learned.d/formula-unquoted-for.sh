#!/usr/bin/env bash
# formula-unquoted-for.sh — hardened learned rule: no agent-executed shell
# block iterates an UNQUOTED expansion. These blocks are pasted into whatever
# shell the agent or operator has; zsh does NOT word-split unquoted $VAR or
# $(cmd), so `for X in $LIST` runs the body ONCE on the whole joined list —
# the per-element command fails on the joined token and the step reports an
# honest-looking failure having silently skipped every real element. Scope:
# fenced shell blocks in formula TOMLs, agent prompt templates, startup
# fragments, and named paste-to-run docs runbooks; rendered (generated/,
# base-snapshots/) and frozen (specs/) trees are excluded. Quoted lists,
# literal/glob lists, and zsh's explicit ${=VAR} split are all fine. Fix:
# capture to a file and `while IFS= read -r X`, or pipe into it.
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
    # Excluded trees first: the detector's own fixtures, frozen spec records,
    # and rendered artifacts. generated/seed-audit re-renders from the agent
    # prompts and fragments below, so a finding there would duplicate the
    # source finding it re-renders; base-snapshots is a frozen render too.
    case "$f" in
        */lint-learned.d/* \
        | */base-snapshots/* | base-snapshots/* \
        | */generated/* | generated/* \
        | */specs/* | specs/*) continue ;;
    esac
    # In scope: surfaces whose fenced shell blocks are pasted into a shell and
    # run, not prose. Formula TOMLs, agent prompt templates, the startup
    # fragments injected into every prompt, and the dispatch-containment
    # runbook operators paste and run. Docs are named here one by one rather
    # than matched by a docs/* glob: most docs are prose whose fenced examples
    # are illustrative, and flagging those trains readers to ignore the rule.
    # Add a runbook to this list when it becomes paste-to-run.
    case "$f" in
        */formulas/*.toml | formulas/*.toml) ;;
        */template-fragments/*.template.md | template-fragments/*.template.md) ;;
        */agents/*/prompt.template.md | agents/*/prompt.template.md) ;;
        */docs/gascity-dispatch-containment.md | docs/gascity-dispatch-containment.md) ;;
        *) continue ;;
    esac
    while IFS= read -r hit; do
        [ -n "$hit" ] || continue
        no="${hit%%:*}"
        echo "$f:$no: shell block iterates an UNQUOTED expansion — zsh does not word-split, so the body runs once on the joined list; capture to a file and \`while IFS= read -r X\`, or write \${=VAR} and mean it (learned rule: formula-unquoted-for)"
        found=1
    done < <(awk "$SCAN_AWK" "$f" 2>/dev/null)
done

[ "$found" -eq 0 ]
