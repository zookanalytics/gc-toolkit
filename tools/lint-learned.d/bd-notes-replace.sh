#!/usr/bin/env bash
# bd-notes-replace.sh — hardened learned rule: a write to a bead's notes appends
# with `--append-notes`, never `bd update --notes`.
#
# `--notes` replaces the whole notes field, and the field is shared: the
# dispatcher's routing note, a coordinator's correction, and every earlier
# step's record all live there. A replace erases them at the moment the bead
# reaches its next reader, and nothing reports it. `--append-notes` is always
# available: on a bead with no notes yet it writes the text alone, the same
# value `--notes` would. No write needs the replace, so the rule takes no
# exception list.
#
# Scanned: *.sh; fenced code (``` fences and `# >>>`…`# <<<` markers) in *.toml
# and *.md. Formula descriptions, prompts and fragments carry their recipes in
# fences, and an agent runs those as written. Prose outside a fence quotes the
# shape rather than running it. Skipped: this directory, specs/ (dated records
# that quote the shape), generated/ (render duplicates, reported at their
# source).
#
# A finding is one command: `bd` (bare, as `gc bd`, through a wrapper such as
# `gc_bd`, or with gc reached by path) running `update` with `--notes` among its
# words. The scan folds continuation lines and carries quote state across
# lines, so a flag on a continued line belongs to its command. Quoted text,
# comments and here-doc bodies are data rather than code, so a message or a
# note that states the shape is not a finding. A command substitution is
# judged as a command of its own, even inside double quotes, and counts as one
# word of the command around it.
# Exit: 0 clean, 1 findings as `<file>:<line>: <message>`, 2 when a file cannot
# be scanned.

set -uo pipefail

MSG='`bd update --notes` replaces the bead'"'"'s whole notes field and erases every note other writers left there; fix: --append-notes (learned rule: bd-notes-replace)'

# Prints the line number of each command that opens a finding. `mode` is `sh`
# (every line is shell) or `fenced` (only lines inside a fence or a marker
# block are). A fence boundary resets the lexer, so a placeholder carrying a
# stray quote cannot leak its state into the next recipe.
SCAN_AWK='
# The context stack survives across lines: st[k] is "c" for code, "d" for a
# double-quoted span and "s" for a single-quoted one. Each code context owns a
# command buffer cb[k], opened on line cs[k], and quoted text never reaches one.
# A `$(` or `(` opens a nested code context, even inside double quotes. Its `)`
# judges the nested buffer as commands of their own and leaves one word in the
# parent, so a substitution between `update` and `--notes` stays inside the
# command it belongs to.
function reset() { top = 1; st[1] = "c"; cb[1] = ""; nhd = 0; hdi = 0; inhd = 0 }

function judge(k) { if (cb[k] ~ FINDING) print cs[k]; cb[k] = "" }

function judge_all(   k) { for (k = top; k >= 1; k--) if (st[k] == "c") judge(k) }

function emit(s,   k) {
    for (k = top; k > 1 && st[k] != "c"; k--) ;
    if (cb[k] == "") cs[k] = FNR
    cb[k] = cb[k] s
}

function open_code() { st[++top] = "c"; cb[top] = ""; cs[top] = FNR }

# lex feeds one physical line to the buffers. It sets cont when the line ends
# in an active continuation backslash, and queues the terminator of each
# here-doc the line opens. A comment ends the line.
function lex(line,   n, i, c, ctx, prev, r, d, tok) {
    n = length(line); cont = 0; prev = " "
    for (i = 1; i <= n; i++) {
        c = substr(line, i, 1); ctx = st[top]
        if (ctx == "s") { if (c == "\047") { top--; prev = c }; continue }
        if (c == "\\") {
            if (i == n) { cont = 1; break }
            i++; prev = "\\"; if (ctx == "c") emit("_"); continue
        }
        if (ctx == "d") {
            if (c == "\"") { top--; emit(" "); prev = c; continue }
            if (c == "$" && substr(line, i + 1, 1) == "(") { i++; open_code(); prev = "("; continue }
            continue
        }
        if (c == "#" && prev ~ /[[:space:];&|(]/) break
        if (c == "\047") { st[++top] = "s"; emit(" "); continue }
        if (c == "\"") { st[++top] = "d"; emit(" "); continue }
        if (c == "(") { open_code(); prev = c; continue }
        if (c == ")") {
            if (top > 1) { judge(top); top--; emit(" _ ") } else emit(c)
            prev = c; continue
        }
        if (c == "<" && substr(line, i + 1, 1) == "<") {
            if (substr(line, i + 2, 1) == "<") { emit("<<<"); i += 2; prev = "<"; continue }
            r = substr(line, i + 2); d = 0
            if (substr(r, 1, 1) == "-") { d = 1; r = substr(r, 2) }
            sub(/^[[:space:]]+/, "", r)
            if (match(r, /^[^[:space:]<>;&|()]+/)) {
                tok = substr(r, 1, RLENGTH); gsub(/["\047\\]/, "", tok)
                if (tok != "" && tok !~ /^[0-9]+$/) { hdq[++nhd] = tok; hdd[nhd] = d }
            }
            emit("<<"); i++; prev = "<"; continue
        }
        emit(c); prev = c
    }
}

BEGIN {
    FINDING = "(^|[^[:alnum:]])bd[[:space:]]+([^;&|()`]*[[:space:]])?update([[:space:]][^;&|()`]*)?[[:space:]]--notes([[:space:]=]|$)"
    reset(); infence = 0; inmark = 0
}

{
    line = $0
    if (mode == "fenced") {
        if (line ~ /^[[:space:]]*```/) { judge_all(); reset(); infence = !infence; next }
        if (line ~ /#[[:space:]]*>>>[[:space:]]/) { judge_all(); reset(); inmark = 1; next }
        if (line ~ /#[[:space:]]*<<<[[:space:]]/) { judge_all(); reset(); inmark = 0; next }
        if (!infence && !inmark) next
    }
    if (inhd) {
        t = line
        if (hdd[hdi]) sub(/^\t+/, "", t)
        if (t == hdq[hdi]) { if (hdi < nhd) hdi++; else { inhd = 0; nhd = 0; hdi = 0 } }
        next
    }
    lex(line)
    if (!cont && st[top] == "c") {
        if (top > 1) emit(" ; ")
        else judge(1)
    }
    if (nhd > 0 && !inhd && !cont) { inhd = 1; hdi = 1 }
}

END { judge_all() }
'

found=0
for f in "$@"; do
    [ -f "$f" ] || continue
    case "$f" in
        */lint-learned.d/* | */specs/* | specs/* | */generated/* | generated/*) continue ;;
        *.sh) mode='sh' ;;
        *.toml | *.md) mode='fenced' ;;
        *) continue ;;
    esac
    # One cheap read decides whether the file is worth a scan at all.
    grep -Eq -- '--notes([^[:alnum:]_-]|$)' "$f" 2>/dev/null || continue
    # A nested substitution is judged when it closes, ahead of the command
    # around it, so the line numbers are sorted back into file order.
    hits="$(awk -v mode="$mode" "$SCAN_AWK" "$f" | sort -n -u)" || {
        echo "bd-notes-replace: awk failed on $f — detector cannot scan it" >&2
        exit 2
    }
    while IFS= read -r no; do
        [ -n "$no" ] || continue
        echo "$f:$no: $MSG"
        found=1
    done <<< "$hits"
done

[ "$found" -eq 0 ]
