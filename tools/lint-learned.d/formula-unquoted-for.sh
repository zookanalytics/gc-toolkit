#!/usr/bin/env bash
# formula-unquoted-for.sh — hardened learned rule: no agent-executed shell
# block iterates an UNQUOTED parameter expansion. These blocks are pasted into
# whatever shell the agent or operator has. zsh does NOT word-split an unquoted
# $VAR or ${VAR}, so `for X in $LIST` runs the body ONCE on the whole joined
# list: the per-element command fails on the joined token, and the step
# reports an honest-looking failure having silently skipped every real element.
# zsh does split the output of an unquoted command substitution, as sh does,
# so a list built from $(cmd) or backticks iterates per word in both shells
# and is not a finding. Words inside a substitution are argument quoting,
# which this rule does not judge. Quoted lists, literal/glob lists, zsh's
# explicit ${=VAR} split, and a ${#VAR} length are fine too. Quoting is read
# left to right, so a `;`, `#` or quote character inside a quoted span, an
# escape or a substitution is data: it neither ends the list nor hides an
# expansion after it. Scope: fenced shell blocks in formula
# TOMLs, agent prompt templates, startup fragments, skills, and named
# paste-to-run docs runbooks. Rendered (generated/, base-snapshots/) and
# frozen (specs/) trees are excluded. Fix: capture to a file and
# `while IFS= read -r X`, or pipe into it.
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
# Blank every span of s that is not unquoted text at the top level of the
# list: quoted strings ('…', $'…', "…"), backslash escapes, command, process
# and arithmetic substitutions ($(…), <(…), >(…), $((…)), `…`, nested to any
# depth), and two expansions that are not findings: zsh's explicit ${=VAR}
# split, and a ${#VAR} length, which is one number. zsh splits a
# substitution's output, so neither the span nor the words inside it decide
# how the list splits. Each blanked character becomes a dot, so a `;`, `#` or
# `$` inside a span can neither end the list nor read as an unquoted
# expansion, and a dot after a bare `$` names no parameter. An unterminated
# span is blanked to the end of s. Context stack, top last: S single quote,
# E $'…', D double quote, K backtick, Z ${=…} or ${#…}, C a substitution
# opened by `(`, P a ( nested inside one. Each step reads one token of w
# characters at i, and every token that is not unquoted top-level text is
# blanked at the one append at the bottom of the loop.
function mask_spans(s,   out, i, n, c, nx, k, top, st, w) {
    out = ""; n = length(s); top = 0
    for (i = 1; i <= n; i += w) {
        c = substr(s, i, 1); nx = substr(s, i + 1, 1)
        k = top ? st[top] : ""
        w = 1
        if (k == "S") { if (c == "'") top-- }
        else if (k == "Z") { if (c == "}") top-- }
        else if (c == "\\") w = 2
        else if (k == "E") { if (c == "'") top-- }
        else if (k == "K") { if (c == "`") top-- }
        else if (k == "D") {
            if (c == "\"") top--
            else if (c == "`") st[++top] = "K"
            else if (c == "$" && nx == "(") { st[++top] = "C"; w = 2 }
        }
        # Unquoted from here on: at the top level, or inside a substitution.
        else if (c == "'") st[++top] = "S"
        else if (c == "\"") st[++top] = "D"
        else if (c == "`") st[++top] = "K"
        else if (c == "$" && nx == "'") { st[++top] = "E"; w = 2 }
        else if ((c == "$" || c == "<" || c == ">") && nx == "(") { st[++top] = "C"; w = 2 }
        else if (c == "$" && nx == "{" && (substr(s, i + 2, 1) == "=" || substr(s, i + 2, 1) == "#")) { st[++top] = "Z"; w = 3 }
        else if (top) {
            if (c == "(") st[++top] = "P"
            else if (c == ")") top--
        }
        else { out = out c; continue }
        out = out substr("...", 1, w)
    }
    return out
}
# The word list of a for-statement whose `in` ends where s begins, as
# mask_spans blanks it: s up to the first top-level `;`, or up to a `#` that
# starts a word and so opens a comment. A newline ends a list too, and the
# scan reads one line at a time. `do` does not end a list: the shells reserve
# it only after the `;` or newline that does, so inside a list it is an
# ordinary word, and the body that follows `do` is never part of the list.
function list_of(s,   m, e) {
    m = mask_spans(s)
    e = length(m) + 1
    if (match(m, /;/)) e = RSTART
    if (match(m, /(^|[[:space:]])#/) && RSTART + RLENGTH - 1 < e) e = RSTART + RLENGTH - 1
    return substr(m, 1, e - 1)
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
    # Every for-statement on the line is judged, one nested inside another's
    # list included: each search resumes just after the previous `in`.
    remain = text
    while (match(remain, /(^|[;&|(){}]|\$\(|[[:space:]](do|then|else))[[:space:]]*for[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]+in[[:space:]]/)) {
        remain = substr(remain, RSTART + RLENGTH)
        if (list_of(remain) ~ /\$([A-Za-z_0-9]|\{)/) { print start ":" stripped; break }
    }
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
    # fragments injected into every prompt, the skills agents load and run,
    # and the dispatch-containment runbook operators paste and run. Docs are
    # named here one by one rather than matched by a docs/* glob: most docs
    # are prose whose fenced examples are illustrative, and flagging those
    # trains readers to ignore the rule. Add a runbook to this list when it
    # becomes paste-to-run.
    case "$f" in
        */formulas/*.toml | formulas/*.toml) ;;
        */template-fragments/*.template.md | template-fragments/*.template.md) ;;
        */agents/*/prompt.template.md | agents/*/prompt.template.md) ;;
        */skills/*/SKILL.md | skills/*/SKILL.md) ;;
        */docs/gascity-dispatch-containment.md | docs/gascity-dispatch-containment.md) ;;
        *) continue ;;
    esac
    while IFS= read -r hit; do
        [ -n "$hit" ] || continue
        no="${hit%%:*}"
        echo "$f:$no: shell block iterates an UNQUOTED parameter expansion — zsh does not word-split \$VAR, so the body runs once on the joined list; capture to a file and \`while IFS= read -r X\`, or write \${=VAR} and mean it (learned rule: formula-unquoted-for)"
        found=1
    done < <(awk "$SCAN_AWK" "$f" 2>/dev/null)
done

[ "$found" -eq 0 ]
