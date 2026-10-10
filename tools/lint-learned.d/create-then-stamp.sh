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
# `gc_bd`) whose first argument is a variable holding a bead that a `bd create`
# with no --metadata filed, and whose own words include --set-metadata. The
# variable holds that bead when it was assigned from the create's command
# substitution, or from a substitution that reads `.id` out of a variable that
# holds it (the `VISIT=$(printf '%s' "$VISIT_JSON" | jq … .id …)` step). Any other
# assignment to the variable, a create that carries --metadata, and the start of
# a shell function forget it, so the scan tracks a bead only along the straight
# line from its create.
#
# The scan folds continuation lines, carries quote state across lines, and
# skips comments and here-doc bodies. Quoted text is data, so a message that
# quotes the shape is not a finding; a double-quoted word that is exactly one
# variable (`"$VISIT"`) stays a word, because that is how a script names the
# bead it writes. A fence boundary resets the scan.
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
# reference.
function reset_lex() { top = 1; st[1] = "c"; nhd = 0; hdi = 0; inhd = 0; stmt = ""; raw = ""; sline = 0; dq = ""; dqx = 0 }
function reset_track(   k) { for (k in trk) delete trk[k] }

function emit(s) { stmt = stmt s }

function dq_render(   v) {
    v = dq
    if (!dqx && (v ~ /^\$[A-Za-z_][A-Za-z0-9_]*$/ || v ~ /^\$\{[A-Za-z_][A-Za-z0-9_]*\}$/)) return " " v " "
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
            if (ctx == "d") { dq = dq "\\" substr(line, i, 1) } else emit("_")
            continue
        }
        if (ctx == "d") {
            if (c == "\"") { top--; emit(dq_render()); dq = ""; dqx = 0; prev = c; continue }
            if (c == "$" && substr(line, i + 1, 1) == "(") { i++; dqx = 1; st[++top] = "c"; emit(" "); prev = "("; continue }
            dq = dq c; continue
        }
        if (c == "#" && prev ~ /[[:space:];&|(]/) break
        if (c == "\047") { st[++top] = "s"; emit(" "); prev = c; continue }
        if (c == "\"") { st[++top] = "d"; dq = ""; dqx = 0; prev = c; continue }
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

function judge(s, r, ln,   asg, rhs, k, pat, cmd, src) {
    if (s ~ /^[[:space:]]*(function[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\(\)/) reset_track()
    for (k in trk) {
        pat = "(^|[^[:alnum:]_.-])(gc[[:space:]]+bd|gc_bd|bd)[[:space:]]+update[[:space:]]+[$][{]?" k "[}]?([^[:alnum:]_]|$)"
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
