#!/usr/bin/env bash
# create-then-stamp.sh — hardened learned rule: a bead's metadata rides the
# create that files it. A `bd create` that carries no `--metadata` is never
# followed by a `--set-metadata` write to the bead it created.
#
# The metadata a bead is born with is what its readers select it by: its
# task_kind, the anchor it hangs on, the key its producer dedups on. Stamped in
# a second write, it is missing whenever that write fails or the create's id
# never comes back. No reader can see such a bead, so nothing closes it, and the
# producer's next run files a stamped twin beside it. `bd create --metadata`
# lands the payload in the bead's own row insert, so every key a stamp could
# write can ride the create instead, and assets/scripts/bd-lib.sh's bd_create
# does that and reads it back. A create that carries --metadata is free to be
# followed by later writes: the bead was born findable, and what comes after is
# a change of state, not its identity.
#
# Scanned: *.sh; fenced code (``` fences and `# >>>`…`# <<<` markers) in *.toml
# and *.md, where formulas, prompts and skills keep the commands an agent runs.
# Skipped: this directory, specs/ (dated records that quote the shape),
# generated/ (render duplicates, reported at their source).
#
# A finding is one `bd update` (bare, as `gc bd`, or through a wrapper such as
# `gc_bd`) whose id is a variable holding a bead that a `bd create` with no
# --metadata filed, and whose own words include --set-metadata. The id is the
# first word after any flags, so a write that names its store first
# (`--db "$DB"`, or `${STORE_DB:+--db "$STORE_DB"}`) is read the same way. The
# variable holds that bead when it was assigned from the create's command
# substitution, quoted or not, or from a substitution that reads `.id` out of a
# variable that holds it (the `VISIT=$(printf '%s' "$VISIT_JSON" | jq … .id …)`
# step). Any other assignment to the variable, a create that carries
# --metadata, and the start of a shell function forget it, so the scan tracks a
# bead only along the straight line from its create.
#
# The scan folds continuation lines, carries quote state across lines, and
# skips comments and here-doc bodies. Quoted text is data, so a message that
# quotes the shape is not a finding; a double-quoted word that is exactly one
# variable (`"$VISIT"`) stays a word, because that is how a script names the
# bead it writes, and one that is exactly one substitution (`"$(…)"`) stays
# that substitution. The commands of one line are judged in the order they
# run, after the words that only open one (if, then, do, a group, a function
# header). A fence boundary resets the scan.
#
# Exit: 0 clean, 1 findings as `<file>:<line>: <message>`, 2 when a file cannot
# be scanned.

set -uo pipefail

SCAN_AWK='
# Context stack: st[k] is "c" for code, "d" for a double-quoted span, "s" for a
# single-quoted one. A `(` or `$(` opens a nested code context, inside double
# quotes too, and its `)` returns to the context below. Code characters are
# appended to the statement buffer; quoted text is not, except that a
# double-quoted span holding exactly one variable reference is kept as that
# reference, and one holding exactly one `$(…)` is kept as that substitution.
# Each double-quoted level keeps its own state, so a span nested inside a
# substitution inside another span does not overwrite the outer one: dqv holds
# the literal text of the span, dqn counts its substitutions, and dqp is where
# the `$(` of the first one sits in the statement buffer.
function reset_lex() { top = 1; st[1] = "c"; nhd = 0; hdi = 0; inhd = 0; stmt = ""; raw = ""; sline = 0 }
function reset_track(   k) { for (k in trk) delete trk[k] }

function emit(s) { stmt = stmt s }

function dq_open() { st[++top] = "d"; dqv[top] = ""; dqn[top] = 0; dqp[top] = 0 }

# Closes the double-quoted span at the top of the stack and renders it.
function dq_close(   v, n, p) {
    v = dqv[top]; n = dqn[top]; p = dqp[top]; top--
    if (n == 1 && p > 0 && v == "") return " "
    # The `$(` the span opened with stands for a substitution the span does not
    # hold alone, so it is no longer an assignment of the substitution.
    if (p > 0) stmt = substr(stmt, 1, p - 1) "_" substr(stmt, p + 1)
    if (n == 0 && (v ~ /^\$[A-Za-z_][A-Za-z0-9_]*$/ || v ~ /^\$\{[A-Za-z_][A-Za-z0-9_]*\}$/)) return " " v " "
    return " _ "
}

function lex(line,   n, i, c, ctx, prev, r, d, tok) {
    n = length(line); cont = 0; prev = " "
    for (i = 1; i <= n; i++) {
        c = substr(line, i, 1); ctx = st[top]
        if (ctx == "s") { if (c == "\047") { top--; emit(" ") }; continue }
        if (c == "\\") {
            if (i == n) { cont = 1; break }
            i++; prev = "\\"
            if (ctx == "d") { dqv[top] = dqv[top] "\\" substr(line, i, 1) } else emit("_")
            continue
        }
        if (ctx == "d") {
            if (c == "\"") { emit(dq_close()); prev = c; continue }
            if (c == "$" && substr(line, i + 1, 1) == "(") {
                i++; dqn[top]++
                if (dqn[top] == 1 && dqv[top] == "") { dqp[top] = length(stmt) + 1; emit("$(") } else emit(" ")
                st[++top] = "c"; prev = "("; continue
            }
            dqv[top] = dqv[top] c; continue
        }
        if (c == "#" && prev ~ /[[:space:];&|(]/) break
        if (c == "\047") { st[++top] = "s"; emit(" "); prev = c; continue }
        if (c == "\"") { dq_open(); prev = c; continue }
        if (c == "(") { st[++top] = "c"; emit(c); prev = c; continue }
        if (c == ")") {
            if (top > 1) top--
            emit(c); prev = c; continue
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

# The substring of s from the match at p to the end of that one command.
function one_command(s, p,   t) {
    t = substr(s, p)
    if (match(t, /;|&&|\|\||\||\)/)) t = substr(t, 1, RSTART - 1)
    return t
}

# Splits a statement into its commands at the separators outside any
# parenthesis, so a create and the stamp after it on one line are judged in
# order. Returns the count; the commands are in parts[1..n].
function split_commands(s, parts,   n, i, c, d, cur, two) {
    n = 0; d = 0; cur = ""
    for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1); two = substr(s, i, 2)
        if (c == "(") d++
        else if (c == ")") { if (d > 0) d-- }
        else if (d == 0 && (two == "&&" || two == "||" || two == ";;")) { parts[++n] = cur; cur = ""; i++; continue }
        else if (d == 0 && (c == ";" || c == "&" || c == "|")) { parts[++n] = cur; cur = ""; continue }
        cur = cur c
    }
    parts[++n] = cur
    return n
}

function judge(s, r, ln,   parts, n, k) {
    if (s ~ /^[[:space:]]*(function[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\(\)/) reset_track()
    n = split_commands(s, parts)
    for (k = 1; k <= n; k++) judge_command(parts[k], r, ln)
}

function judge_command(s, r, ln,   asg, rhs, k, pat, cmd, src) {
    # The words that can open a command without being its name: a function
    # header, a group, a negation, and the reserved words of if, while and for.
    sub(/^[[:space:]]*(function[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\(\)/, "", s)
    while (match(s, /^[[:space:]]*(if|elif|while|until|then|do|else|[{]|!)([[:space:]]|$)/)) s = substr(s, RSTART + RLENGTH)
    for (k in trk) {
        pat = "(^|[^[:alnum:]_.-])(gc[[:space:]]+bd|gc_bd|bd)[[:space:]]+update[[:space:]]+" UPDATE_FLAGS "[$][{]?" k "[}]?([^[:alnum:]_]|$)"
        if (match(s, pat)) {
            cmd = one_command(s, RSTART)
            if (cmd ~ /--set-metadata/) print ln "\t" k "\t" trk[k]
        }
    }
    if (match(s, /^[[:space:]]*((local|export|readonly|declare)[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*=/)) {
        asg = substr(s, RSTART, RLENGTH)
        rhs = substr(s, RSTART + RLENGTH)
        sub(/^[[:space:]]*((local|export|readonly|declare)[[:space:]]+)?/, "", asg)
        sub(/=$/, "", asg)
        if (rhs ~ /^\$\(/ && s ~ CREATE) {
            if (s ~ /(^|[[:space:]])--metadata([[:space:]=]|$)/) delete trk[asg]
            else trk[asg] = ln
            return
        }
        if (rhs ~ /^\$\(/ && r ~ /\.id/) {
            for (k in trk) {
                if (rhs ~ ("[$][{]?" k "[}]?([^[:alnum:]_]|$)")) { src = k; break }
            }
            if (src != "") { trk[asg] = trk[src]; return }
        }
        delete trk[asg]
    }
}

BEGIN {
    CREATE = "(^|[^[:alnum:]_.-])(gc[[:space:]]+bd|gc_bd|bd)[[:space:]]+create([^[:alnum:]_-]|$)"
    # The words an update can carry ahead of its id: a flag, with its value as
    # the next word or after `=`, and a `${VAR:+…}` expansion that adds one, the
    # form a write pinned to a store takes (`${STORE_DB:+--db "$STORE_DB"}`).
    UPDATE_FLAGS = "((--?[A-Za-z][A-Za-z0-9_-]*(=[^[:space:]]*)?([[:space:]]+[^-[:space:]][^[:space:]]*)?|[$][{][A-Za-z_][A-Za-z0-9_]*:?[-+=?][^}]*[}])[[:space:]]+)*"
    reset_lex(); reset_track(); infence = 0; inmark = 0
}

{
    line = $0
    if (mode == "fenced") {
        if (line ~ /^[[:space:]]*```/) { reset_lex(); reset_track(); infence = !infence; next }
        if (line ~ /#[[:space:]]*>>>[[:space:]]/) { reset_lex(); reset_track(); inmark = 1; next }
        if (line ~ /#[[:space:]]*<<<[[:space:]]/) { reset_lex(); reset_track(); inmark = 0; next }
        if (!infence && !inmark) next
    }
    if (inhd) {
        t = line
        if (hdd[hdi]) sub(/^\t+/, "", t)
        if (t == hdq[hdi]) { if (hdi < nhd) hdi++; else { inhd = 0; nhd = 0; hdi = 0 } }
        next
    }
    if (stmt == "" && raw == "") sline = FNR
    lex(line)
    raw = raw " " line
    if (!cont && top == 1) {
        judge(stmt, raw, sline)
        stmt = ""; raw = ""
    } else emit(" ")
    if (nhd > 0 && !inhd && !cont) { inhd = 1; hdi = 1 }
}
'

MSG_HEAD='holds a bead filed by the `bd create` at line'
MSG_TAIL='with no --metadata, and this write stamps its metadata second. A bead whose stamp fails, or whose create id never comes back, carries nothing a reader selects it by, and the next run files a twin; fix: carry the keys on the create (`--metadata`, or bd_create in assets/scripts/bd-lib.sh) (learned rule: create-then-stamp)'

found=0
for f in "$@"; do
    [ -f "$f" ] || continue
    case "$f" in
        */lint-learned.d/* | */specs/* | specs/* | */generated/* | generated/* | */base-snapshots/*) continue ;;
        *.sh) mode='sh' ;;
        *.toml | *.md) mode='fenced' ;;
        *) continue ;;
    esac
    # One cheap read decides whether the file is worth a scan at all.
    grep -Eq -- '--set-metadata' "$f" 2>/dev/null || continue
    grep -Eq -- '(gc_bd|(^|[^[:alnum:]_.-])bd)[[:space:]]+create([^[:alnum:]_-]|$)' "$f" 2>/dev/null || continue
    hits="$(awk -v mode="$mode" "$SCAN_AWK" "$f")" || {
        echo "create-then-stamp: awk failed on $f — detector cannot scan it" >&2
        exit 2
    }
    while IFS=$'\t' read -r no var made; do
        [ -n "$no" ] || continue
        echo "$f:$no: \`\$$var\` $MSG_HEAD $made $MSG_TAIL"
        found=1
    done <<< "$hits"
done

[ "$found" -eq 0 ]
