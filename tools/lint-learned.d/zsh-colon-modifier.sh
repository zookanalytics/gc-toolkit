#!/usr/bin/env bash
# zsh-colon-modifier.sh — hardened learned rule: agent-run shell never follows
# an unbraced parameter expansion with a colon and a zsh modifier letter.
# Agents paste these blocks into zsh. zsh reads `$NAME:x` as a modifier on the
# expansion when x is one of a c e h l q r s t u A P Q, alone or after a run of
# the g, w and f prefixes. The modifier consumes the colon and rewrites the
# text after it: "$REV:review-checks.toml" hands git `<rev>eview-checks.toml`,
# and "bead:$ID:turn:" stores `bead:<id>urn:`. bash keeps the same text
# literal, so the block reads right, passes under bash, and fails silently in
# the shell agents run. Those letters are the finding. Other letters stay
# literal in zsh, except F and W, which read a delimited argument and rewrite
# or not depending on the text after it; they are not flagged. A braced
# `${NAME}:x` is literal in both shells.
#
# The scan follows shell quoting. Single-quoted spans, $'…', \$, comments and
# quoted-delimiter heredoc bodies never expand, and the text after a braced
# ${…} takes no modifier. Double quotes, $(…), backticks, here-strings and
# unquoted-delimiter heredoc bodies expand, and a quote character inside a
# double-quoted string or an unquoted heredoc body is literal there. Formula
# TOML is read through its basic-string escapes, so a `\\` in the file is the
# one backslash the agent's shell sees.
#
# Scope: ```bash, ```sh and ```shell fences in formula TOMLs, agent prompt
# templates, startup fragments, skills, and the paste-to-run docs runbooks
# named below. Untagged fences in these files mostly hold checklists, templates
# and diagrams, so only a fence tagged as shell is read as shell. Docs are
# named one by one because a reference doc can show a broken command as a
# counter-example. Rendered (generated/, base-snapshots/) and frozen (specs/)
# trees are excluded. Scripts are out of scope: bash runs them, and the shape
# is literal there. Fix: brace the name, `${NAME}:x`.
# Exit: 0 clean, 1 findings as `<file>:<line>: <message>`, 2 a file it could
# not scan.

set -uo pipefail

# The scanner walks each fenced line a character at a time on a stack of
# quoting frames that persists across lines, so a string or substitution that
# spans lines keeps its context. Heredoc'd so its own quotes survive.
SCAN_AWK=$(cat <<'AWKEOF'
# Frames, FR[1..sp], with a nesting depth in DP[] where one is needed:
#   T top level   S '…'   A $'…'   Q "…"   C $(…)   B `…`
#   H unquoted heredoc body   R $((…))   K ${…}
# T, Q, C, B and H expand parameters. S, A, R and K are skipped whole.
function reset_state() { sp = 1; FR[1] = "T"; DP[1] = 0; hn = 0; hi = 0; hb = 0 }
function push(t, d) { FR[++sp] = t; DP[sp] = d }
function pop() { if (sp > 1) sp-- }
function shell_fence(l,   lang) {
    lang = l
    sub(/^[[:space:]]*```[[:space:]]*/, "", lang)
    sub(/[[:space:]].*$/, "", lang)
    return (lang == "bash" || lang == "sh" || lang == "shell")
}
# A TOML basic string spells one backslash `\\` and a quote `\"`.
function toml_text(s,   out, i, n, c, d) {
    out = ""; n = length(s)
    for (i = 1; i <= n; i++) {
        c = substr(s, i, 1)
        if (c == "\\" && i < n) {
            d = substr(s, i + 1, 1)
            if (d == "\\" || d == "\"") { out = out d; i++; continue }
        }
        out = out c
    }
    return out
}
function body_begin() {
    hb = 1; hbt = HT[hi]; hbq = HQ[hi]; hbd = HD[hi]; hbsp = sp
    if (!hbq) push("H", 0)
}
function body_end() {
    if (!hbq) sp = hbsp
    if (++hi <= hn) body_begin(); else { hb = 0; hn = 0; hi = 0 }
}
# Returns "name<TAB>modifiers" for the first expansion on the line that a zsh
# modifier rewrites, or "". CONT is set when the line ends in an escaping
# backslash, which continues the command onto the next line.
function scan(s,   n, i, c, t, hit, rest, nm, w, dash, tok) {
    n = length(s); hit = ""; CONT = 0
    for (i = 1; i <= n; i++) {
        c = substr(s, i, 1); t = FR[sp]
        if (t == "S") { if (c == "'") pop(); continue }
        if (t == "A") { if (c == "\\") i++; else if (c == "'") pop(); continue }
        if (t == "R") { if (c == "(") DP[sp]++; else if (c == ")" && --DP[sp] <= 0) pop(); continue }
        if (t == "K") { if (c == "{") DP[sp]++; else if (c == "}" && --DP[sp] <= 0) pop(); continue }
        if (c == "\\") { if (i == n) CONT = 1; i++; continue }
        if (c == "$") {
            rest = substr(s, i + 1)
            if (substr(rest, 1, 2) == "((") { push("R", 2); i += 2; continue }
            c = substr(rest, 1, 1)
            if (c == "(") { push("C", 0); i++; continue }
            if (c == "{") { push("K", 1); i++; continue }
            if (t != "Q" && t != "H") {
                if (c == "'") { push("A", 0); i++; continue }
                if (c == "\"") { push("Q", 0); i++; continue }
            }
            # zsh reads a run of digits as one positional parameter.
            if (match(rest, /^[A-Za-z_][A-Za-z0-9_]*/) || match(rest, /^[0-9]+/) || match(rest, /^[?#$!*@-]/)) {
                nm = substr(rest, 1, RLENGTH)
                i += RLENGTH
                if (hit == "" && match(substr(s, i + 1), /^:[fgw]*[acehlqrstuAPQ]/))
                    hit = nm "\t" substr(s, i + 2, RLENGTH - 1)
            }
            continue
        }
        if (c == "`") { if (t == "B") pop(); else push("B", 0); continue }
        if (t == "Q") { if (c == "\"") pop(); continue }
        if (t == "H") continue
        # T, C and B are unquoted.
        if (c == "'") { push("S", 0); continue }
        if (c == "\"") { push("Q", 0); continue }
        if (c == "#" && (i == 1 || substr(s, i - 1, 1) ~ /[[:space:];&|()<>]/)) break
        if (t == "C" && c == "(") { DP[sp]++; continue }
        if (t == "C" && c == ")") { if (DP[sp] > 0) DP[sp]--; else pop(); continue }
        if (c == "<" && substr(s, i + 1, 1) == "<") {
            if (substr(s, i + 2, 1) == "<") { i += 2; continue }
            rest = substr(s, i + 2); w = 0; dash = 0
            if (substr(rest, 1, 1) == "-") { dash = 1; rest = substr(rest, 2); w = 1 }
            match(rest, /^[[:space:]]*/); w += RLENGTH; rest = substr(rest, RLENGTH + 1)
            if (match(rest, /^[A-Za-z_'"\\][^[:space:]<>;&|()]*/)) {
                tok = substr(rest, 1, RLENGTH)
                HQ[++hn] = (tok ~ /['"\\]/)
                gsub(/['"\\]/, "", tok)
                HT[hn] = tok; HD[hn] = dash
                i += 1 + w + RLENGTH
            } else i++
            continue
        }
    }
    return hit
}
BEGIN { reset_state() }
/^[[:space:]]*```/ {
    if (inb) { inb = 0; reset_state() }
    else if (other) other = 0
    else if (shell_fence($0)) { inb = 1; reset_state() }
    else other = 1
    next
}
!inb { next }
{
    line = toml ? toml_text($0) : $0
    if (hb) {
        t = line
        if (hbd) sub(/^\t+/, "", t)
        sub(/[[:space:]]+$/, "", t)
        if (t == hbt) { body_end(); next }
        if (hbq) next
    }
    hit = scan(line)
    if (hit != "") print FNR "\t" hit
    # A heredoc body starts on the line after the command that opened it ends.
    if (!hb && hn > 0 && !CONT && FR[sp] != "S" && FR[sp] != "Q" && FR[sp] != "A") { hi = 1; body_begin() }
}
AWKEOF
)

found=0
for f in "$@"; do
    [ -f "$f" ] || continue
    case "$f" in
        */lint-learned.d/* \
        | */base-snapshots/* | base-snapshots/* \
        | */generated/* | generated/* \
        | */specs/* | specs/*) continue ;;
    esac
    # Add a docs runbook here when it becomes paste-to-run.
    case "$f" in
        */formulas/*.toml | formulas/*.toml) ;;
        */template-fragments/*.template.md | template-fragments/*.template.md) ;;
        */agents/*/prompt.template.md | agents/*/prompt.template.md) ;;
        */skills/*/SKILL.md | skills/*/SKILL.md) ;;
        */docs/gascity-dispatch-containment.md | docs/gascity-dispatch-containment.md) ;;
        *) continue ;;
    esac
    toml=0
    case "$f" in *.toml) toml=1 ;; esac
    if ! hits=$(awk -v toml="$toml" "$SCAN_AWK" < "$f"); then
        echo "zsh-colon-modifier: cannot scan $f" >&2
        exit 2
    fi
    while IFS=$'\t' read -r no name mod; do
        [ -n "$no" ] || continue
        echo "$f:$no: unbraced \$$name:$mod — zsh reads :$mod as a modifier on \$$name and rewrites the text after it, where bash keeps it literal; write \${$name}:$mod (learned rule: zsh-colon-modifier)"
        found=1
    done <<< "$hits"
done

[ "$found" -eq 0 ]
