#!/usr/bin/env bash
# session-list-no-api.sh — hardened rule: the pack runs `gc session list` with
# GC_NO_API=1 on the command itself.
#
# gc chooses where a session list comes from on every call. While the city's
# controller answers gc's ping, the command renders locally, and those rows are
# the schema-versioned output the pack parses. When the ping misses, as it does
# under load, gc asks the supervisor's HTTP API instead and prints that API's
# rows. They lack fields the pack reads (agent_name, session_key, provider, rig,
# closed), and under --state all they also list every session the city has
# closed. Only GC_DEBUG makes gc say which path a call took. GC_NO_API=1 makes
# gc render locally on every call, so a slow controller slows the read and
# leaves its rows alone.
#
# The assignment rides the one command and is never exported: GC_NO_API moves
# every routed gc command off the API, and the pack's other calls stay on it.
# Put it on gc itself. Under a wrapper that runs its arguments, that is
# `run_bounded env GC_NO_API=1 gc session list …`. A prefix in front of a shell
# function is not the same thing, because POSIX sh (macOS /bin/sh among them)
# keeps the assignment set after the function returns.
#
# Scanned: *.sh, and the fenced code of *.toml and *.md: ``` fences and
# `# >>> name`…`# <<< name` marker blocks, which agents and extraction tests run
# verbatim. specs/ and generated/ are records, not recipes. A finding is the
# words `session list` in command code, whatever name reaches gc (`gc`, `"$GC"`,
# a wrapper that adds gc itself), when the simple command they sit in has no
# GC_NO_API assignment in front of them that gc reads as switching the API off:
# 1, true or yes, in any case, quoted or not. Quoted strings, here-doc bodies
# and comments are data, and a command substitution inside double quotes stays
# code. Go code that execs gc sets the variable in the command's Env instead,
# and this scan does not read Go.
#
# Exempt: this directory. No exception list otherwise: every call can carry the
# assignment.
#
# Exit: 0 clean, 1 findings as `<file>:<line>: <message>`, 2 when a file cannot
# be scanned.

set -uo pipefail

FIX='fix: GC_NO_API=1 gc session list …, or `env GC_NO_API=1 gc session list …` where a wrapper runs the command (learned rule: session-list-no-api)'
WHY='a controller slow to answer gc'"'"'s ping sends the read to the supervisor API, whose rows lack fields the pack reads'

# A line worth a closer look names the subcommand.
GATE='session[[:space:]]+list'

# A `\` at a line's end continues the command onto the next physical line, so
# every surface folds continuations before scanning: the joined text is judged
# under the first line's number. line_continues reports an ACTIVE continuation
# backslash, one reached outside single quotes and not itself escaped.
FOLD_AWK='
    function line_continues(line,   n, i, c, sq, dq) {
        n = length(line)
        for (i = 1; i <= n; i++) {
            c = substr(line, i, 1)
            if (sq)          { if (c == "'\''") sq = 0; continue }
            if (c == "\\")   { if (i == n) return 1; i++; continue }
            if (dq)          { if (c == "\"") dq = 0; continue }
            if (c == "'\''") { sq = 1; continue }
            if (c == "\"")   { dq = 1; continue }
        }
        return 0
    }
'

# sh_lines <file> — the gated command lines of a shell file, folded, as
# `<lineno>\t<text>`. Here-doc bodies are data and are dropped. An opener counts
# only in shell syntax: hd_open walks the line tracking quote state, so a
# `<<WORD` inside a string is data, while a quoted terminator (`<<-'END'`)
# still opens a body. `<<<` is a here-string and opens none.
sh_lines() {
    awk -v gate="$GATE" "$FOLD_AWK"'
        function hd_open(line,   n, i, c, q, r, d, tok) {
            n = length(line); q = ""
            for (i = 1; i <= n; i++) {
                c = substr(line, i, 1)
                if (q != "") { if (c == q) q = ""; continue }
                if (c == "\"" || c == "'\''") { q = c; continue }
                if (c == "<" && substr(line, i + 1, 1) == "<") {
                    if (substr(line, i + 2, 1) == "<") { i += 2; continue }
                    r = substr(line, i + 2); d = 0
                    if (substr(r, 1, 1) == "-") { d = 1; r = substr(r, 2) }
                    sub(/^[[:space:]]+/, "", r)
                    if (match(r, /^[^[:space:]<>;&|()]+/) == 0 || RLENGTH < 1) return ""
                    tok = substr(r, 1, RLENGTH)
                    gsub(/["'\''\\]/, "", tok)
                    HD_DASH = d
                    return tok
                }
            }
            return ""
        }
        hd != "" {
            t = $0
            if (dash) sub(/^\t+/, "", t)
            if (t == hd) hd = ""
            next
        }
        {
            if (pend != "") { $0 = pend $0; pend = "" } else { pno = NR }
            if (line_continues($0)) { sub(/\\$/, "", $0); pend = $0; next }
            term = hd_open($0)
            if (term != "") { hd = term; dash = HD_DASH }
            if ($0 ~ gate) print pno "\t" $0
        }
        END { if (pend != "" && pend ~ gate) print pno "\t" pend }
    ' "$1" 2>/dev/null
}

# fenced_lines <file> — the gated lines inside ``` fences and `# >>>` marker
# blocks of a *.toml or *.md file, folded, as `<lineno>\t<text>`.
fenced_lines() {
    awk -v gate="$GATE" "$FOLD_AWK"'
        /^[[:space:]]*```/            { inf = !inf; pend = ""; next }
        /#[[:space:]]*>>>[[:space:]]/ { inm = 1; pend = "" }
        /#[[:space:]]*<<<[[:space:]]/ { inm = 0; pend = "" }
        inf || inm {
            if (pend != "") { $0 = pend $0; pend = "" } else { pno = FNR }
            if (line_continues($0)) { sub(/\\$/, "", $0); pend = $0; next }
            if ($0 ~ gate) print pno "\t" $0
        }
        END { if (pend != "" && pend ~ gate) print pno "\t" pend }' "$1" 2>/dev/null
}

# strip_quoted <line> — blanks quoted STRING content so words spelled inside a
# string literal cannot read as a command, while keeping command substitutions
# ($(...) and `...`) as code: a call made inside "$(gc session list)" runs even
# though it sits within double quotes. Single-quoted spans expand nothing and
# stay fully blanked; a backslash escape consumes the character it protects.
strip_quoted() {
    local s="$1" out="" ch nx i n=${#1}
    # Context stack, top last: S single-quote, D double-quote, C $(...), B `...`.
    # An empty stack is unquoted code. Each C frame carries a paren depth in `pd`
    # so a nested ( ) or a $(( )) closes on its own matching ), not the first one.
    local -a st=() pd=()
    local top si pi
    for (( i = 0; i < n; i++ )); do
        ch="${s:i:1}"
        top=""; [ "${#st[@]}" -gt 0 ] && top="${st[${#st[@]}-1]}"
        if [ "$top" = S ]; then
            out+=" "
            [ "$ch" = "'" ] && { si=$(( ${#st[@]} - 1 )); unset "st[$si]"; }
            continue
        fi
        if [ "$top" = D ]; then
            if [ "$ch" = "\\" ]; then out+="  "; i=$((i + 1)); continue; fi
            if [ "$ch" = '"' ]; then out+=" "; si=$(( ${#st[@]} - 1 )); unset "st[$si]"; continue; fi
            if [ "$ch" = '`' ]; then out+='`'; st+=(B); continue; fi
            if [ "$ch" = '$' ]; then
                nx="${s:i+1:1}"
                [ "$nx" = '(' ] && { out+='$('; st+=(C); pd+=(1); i=$((i + 1)); continue; }
            fi
            out+=" "
            continue
        fi
        if [ "$ch" = "\\" ]; then out+="  "; i=$((i + 1)); continue; fi
        case "$ch" in
            "'") out+=" "; st+=(S); continue ;;
            '"') out+=" "; st+=(D); continue ;;
            '`')
                if [ "$top" = B ]; then out+='`'; si=$(( ${#st[@]} - 1 )); unset "st[$si]"
                else out+='`'; st+=(B); fi
                continue ;;
            '$')
                nx="${s:i+1:1}"
                if [ "$nx" = '(' ]; then out+='$('; st+=(C); pd+=(1); i=$((i + 1)); continue; fi
                out+='$'; continue ;;
            '(')
                out+='('
                [ "$top" = C ] && { pi=$(( ${#pd[@]} - 1 )); pd[pi]=$(( pd[pi] + 1 )); }
                continue ;;
            ')')
                out+=')'
                if [ "$top" = C ]; then
                    pi=$(( ${#pd[@]} - 1 )); pd[pi]=$(( pd[pi] - 1 ))
                    if [ "${pd[pi]}" -le 0 ]; then
                        si=$(( ${#st[@]} - 1 )); unset "st[$si]"; unset "pd[$pi]"
                    fi
                fi
                continue ;;
            *) out+="$ch"; continue ;;
        esac
    done
    printf '%s' "$out"
}

# canon_pin <line> — rewrites each GC_NO_API=<value> word to GC_NO_API=1 when gc
# reads the value as switching the API off (1, true or yes in any case, quoted
# or not, padded or not) and to GC_NO_API=0 otherwise, so quoting the value
# cannot hide it from the quote-stripped scan.
canon_pin() {
    local s="$1" out="" m v
    local re='GC_NO_API=("[^"]*"|'\''[^'\'']*'\''|[^[:space:];&|()<>"'\'']*)'
    while [[ "$s" =~ $re ]]; do
        m="${BASH_REMATCH[0]}" v="${BASH_REMATCH[1]}"
        v="${v#[\"\']}" v="${v%[\"\']}"
        v="${v#"${v%%[![:space:]]*}"}" v="${v%"${v##*[![:space:]]}"}"
        case "$v" in 1 | [Tt][Rr][Uu][Ee] | [Yy][Ee][Ss]) v=1 ;; *) v=0 ;; esac
        out+="${s%%"$m"*}GC_NO_API=$v"
        s="${s#*"$m"}"
    done
    printf '%s' "$out$s"
}

# unpinned <code> — true when a simple command in the quote-stripped line runs
# `session list` with no GC_NO_API=1 word in front of it. The operators that end
# a simple command split the line, and a comment ends it: a `#` that begins a
# word, which quoted text can no longer supply.
unpinned() {
    local code="$1" head="" rest="$1" pre seg w pinned prev
    local -a words
    while [[ "$rest" == *'#'* ]]; do
        pre="$head${rest%%#*}"
        if [ -z "$pre" ] || [[ "${pre: -1}" == [[:space:]\;\&\|\(\)] ]]; then
            code="$pre"
            break
        fi
        head="$pre#" rest="${rest#*#}"
    done
    while IFS= read -r seg; do
        read -ra words <<< "$seg"
        pinned=0 prev=""
        for w in ${words[@]+"${words[@]}"}; do
            if [ "$w" = GC_NO_API=1 ]; then
                pinned=1
            elif [ "$prev" = session ] && [[ "$w" =~ ^list([^[:alnum:]_./-]|$) ]]; then
                [ "$pinned" -eq 1 ] || return 0
            fi
            prev="$w"
        done
    done <<< "${code//[;&|()\`]/$'\n'}"
    return 1
}

found=0

# cannot_scan <file> <tool> — a tool that failed on a file left it unscanned,
# and reporting nothing would pass it as clean, so the run ends in an error.
cannot_scan() {
    echo "session-list-no-api: $2 failed on $1 — detector cannot scan it" >&2
    exit 2
}

for f in "$@"; do
    [ -f "$f" ] || continue
    case "$f" in
        */lint-learned.d/* | */lint-learned.sh | */base-snapshots/*) continue ;;
        specs/* | */specs/* | generated/* | */generated/*) continue ;;
    esac
    case "$f" in *.sh | *.toml | *.md) ;; *) continue ;; esac
    # One cheap read gates the line scan. Exit 1 is a file that never names the
    # subcommand; anything past it is a file grep could not read, which a skip
    # would pass unscanned.
    grep -Eq "$GATE" "$f" 2>/dev/null; rc=$?
    [ "$rc" -eq 1 ] && continue
    [ "$rc" -eq 0 ] || cannot_scan "$f" grep
    case "$f" in
        *.sh) lines="$(sh_lines "$f")" || cannot_scan "$f" awk ;;
        *)    lines="$(fenced_lines "$f")" || cannot_scan "$f" awk ;;
    esac
    [ -n "$lines" ] || continue
    while IFS=$'\t' read -r no text; do
        [ -n "$no" ] || continue
        trimmed="${text#"${text%%[![:space:]]*}"}"
        case "$trimmed" in '#'*) continue ;; esac
        unpinned "$(strip_quoted "$(canon_pin "$text")")" || continue
        echo "$f:$no: runs \`gc session list\` without GC_NO_API=1 — $WHY; $FIX"
        found=1
    done <<< "$lines"
done

[ "$found" -eq 0 ]
