#!/usr/bin/env bash
# pr-post-bypass.sh — hardened learned rule: the pack posts on a pull request
# only through assets/scripts/pr-post.sh.
#
# The city posts under the same GitHub login the operator's own review tools can
# post under, so pr-facts.sh tells the city's notices from feedback by the
# provenance mark pr-post.sh appends, not by the author. A post that bypasses the
# helper carries no mark, so the next reconcile pass reads the city's own notice
# back as feedback and routes it into rework: a rework child that answers the
# city's own words, and whose answer, posted the same way, is read back again.
#
# Scanned: *.sh, and the fenced code of *.toml and *.md — ``` fences and
# `# >>> name`…`# <<< name` marker blocks, which agents and extraction tests run
# verbatim. specs/ and generated/ are records, not recipes. Three findings:
#   1. `gh pr comment`, `gh pr review` or `gh issue comment` in command position,
#      and a `gh pr` or `gh issue` close or reopen given `--comment`, which posts
#      that comment;
#   2. `gh api`, or a gh_api* wrapper, writing to a comment or review endpoint:
#      a write method or a body field, on a path under issues/…/comments,
#      pulls/…/comments or pulls/…/reviews. A dismissal, a reaction or a reviewer
#      re-request posts no body, so its path is not one;
#   3. a GraphQL mutation that posts or edits a comment or review body, called
#      with its arguments (`addPullRequestReviewThreadReply(`, `addComment(`, …).
# Quoted strings and here-doc bodies are data, so 1 and 2 read command
# positions only, and a command substitution inside double quotes stays code. 3
# reads the field call wherever it sits, here-doc bodies included, because a
# GraphQL document is always a string; a stub's case pattern or a JSON response
# that names the field is not a call. Whole-line comments are skipped.
#
# Exempt: pr-post.sh itself, the one place the raw calls belong, and this
# directory. No exception list otherwise: every post has a pr-post.sh verb.
#
# Exit: 0 clean, 1 findings as `<file>:<line>: <message>`.

set -uo pipefail

FIX='fix: post through assets/scripts/pr-post.sh comment|review|reply|edit|file-comment (learned rule: pr-post-bypass)'
WHY='carries no city mark, so pr-facts.sh reads it back as feedback and routes the city'"'"'s own words into rework'

# A line worth a closer look: a gh call, a gh_api wrapper, or a mutation name.
GATE='(^|[^[:alnum:]_])gh([[:space:]]|_api)|addComment|addPullRequestReview|submitPullRequestReview|updateIssueComment|updatePullRequestReview'

# Leading `VAR=value` assignments ride in front of a command.
ASSIGNS='([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*'
# Command position, in two shapes: after a separator, and after a word that runs
# the command that follows it.
SEP='(^|[;&|(){}]|\$\(|`)[[:space:]]*'"$ASSIGNS"
WRAP='(^|[^[:alnum:]_./-])(then|do|else|elif|if|while|until|run_bounded|command|exec|env|nohup|xargs|time|!)[[:space:]]+'"$ASSIGNS"
GH_POST='gh[[:space:]]+(pr[[:space:]]+(comment|review)|issue[[:space:]]+comment)([[:space:]]|;|\)|$)'
# A close or reopen posts only when handed a comment, so the option has to sit
# in the same command, before any separator.
GH_STATE_POST='gh[[:space:]]+(pr|issue)[[:space:]]+(close|reopen)[[:space:]]([^;&|()`]*[[:space:]])?(-c|--comment)([[:space:]=]|$)'
GH_API='(gh[[:space:]]+api|gh_api[[:alnum:]_]*)([[:space:]]|$)'
# A comment, reply or review endpoint, and the three that post no body.
POST_PATH='(issues|pulls)/([^[:space:]/"'"'"']+/)?comments([^[:alnum:]_]|$)|pulls/[^[:space:]/"'"'"']+/reviews([^[:alnum:]_]|$)'
NOT_A_POST='/(dismissals|reactions|requested_reviewers)([^[:alnum:]_]|$)'
# gh api writes when the method says so, or when it is handed a body.
WRITE='(^|[[:space:]])(-X|--method)[[:space:]=]*["'"'"']?(POST|PATCH|PUT)|(^|[[:space:]])(-f|-F|--field|--raw-field)[[:space:]]+["'"'"']?body=|(^|[[:space:]])--input([[:space:]=]|$)'
MUTATION_CALL='(^|[^[:alnum:]_])(addComment|addPullRequestReview|addPullRequestReviewComment|addPullRequestReviewThread|addPullRequestReviewThreadReply|submitPullRequestReview|updateIssueComment|updatePullRequestReview|updatePullRequestReviewComment)[[:space:]]*\('

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

# sh_lines <file> — the gated lines of a shell file as `<lineno>\t<kind>\t<text>`.
# kind C is a command line; kind H is a here-doc body line, which is data for
# findings 1 and 2 and still read for 3. An opener counts only in shell syntax:
# hd_open walks the line tracking quote state, so a `<<WORD` inside a string is
# data, while a quoted terminator (`<<-'END'`) still opens a body. `<<<` is a
# here-string and opens none.
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
            if (t == hd) { hd = ""; next }
            if ($0 ~ gate) print NR "\tH\t" $0
            next
        }
        {
            if (pend != "") { $0 = pend $0; pend = "" } else { pno = NR }
            if (line_continues($0)) { sub(/\\$/, "", $0); pend = $0; next }
            term = hd_open($0)
            if (term != "") { hd = term; dash = HD_DASH }
            if ($0 ~ gate) print pno "\tC\t" $0
        }
        END { if (pend != "" && pend ~ gate) print pno "\tC\t" pend }
    ' "$1" 2>/dev/null
}

# fenced_lines <file> — the gated lines inside ``` fences and `# >>>` marker
# blocks of a *.toml or *.md file, folded, as `<lineno>\tC\t<text>`.
fenced_lines() {
    awk -v gate="$GATE" "$FOLD_AWK"'
        /^[[:space:]]*```/            { inf = !inf; pend = ""; next }
        /#[[:space:]]*>>>[[:space:]]/ { inm = 1; pend = "" }
        /#[[:space:]]*<<<[[:space:]]/ { inm = 0; pend = "" }
        inf || inm {
            if (pend != "") { $0 = pend $0; pend = "" } else { pno = FNR }
            if (line_continues($0)) { sub(/\\$/, "", $0); pend = $0; next }
            if ($0 ~ gate) print pno "\tC\t" $0
        }
        END { if (pend != "" && pend ~ gate) print pno "\tC\t" pend }' "$1" 2>/dev/null
}

# strip_quoted <line> — blanks quoted STRING content so a command spelled inside
# a string literal cannot read as one, while keeping command substitutions
# ($(...) and `...`) as code: a post made inside "$(gh pr comment ...)" runs
# even though it sits within double quotes. Single-quoted spans expand nothing
# and stay fully blanked; a backslash escape consumes the character it protects.
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

found=0

# judge <file> <lineno> <kind> <text> — report each finding the line makes.
judge() {
    local f="$1" no="$2" kind="$3" text="$4" trimmed code
    trimmed="${text#"${text%%[![:space:]]*}"}"
    case "$trimmed" in '#'*) return 0 ;; esac
    if [[ "$text" =~ $MUTATION_CALL ]]; then
        echo "$f:$no: calls the GraphQL mutation \`${BASH_REMATCH[2]}\` outside pr-post.sh — the body it posts $WHY; $FIX"
        found=1
    fi
    [ "$kind" = C ] || return 0
    code="$(strip_quoted "$text")"
    if [[ "$code" =~ $SEP$GH_POST ]] || [[ "$code" =~ $WRAP$GH_POST ]]; then
        local verb="pr comment"
        [[ "$code" =~ gh[[:space:]]+(pr[[:space:]]+(comment|review)|issue[[:space:]]+comment) ]] \
            && verb="$(printf '%s' "${BASH_REMATCH[1]}" | tr -s '[:space:]' ' ')"
        echo "$f:$no: posts with \`gh $verb\` outside pr-post.sh — the post $WHY; $FIX"
        found=1
        return 0
    fi
    if [[ "$code" =~ $SEP$GH_STATE_POST ]] || [[ "$code" =~ $WRAP$GH_STATE_POST ]]; then
        local sverb="pr close"
        [[ "$code" =~ gh[[:space:]]+(pr|issue)[[:space:]]+(close|reopen) ]] \
            && sverb="${BASH_REMATCH[1]} ${BASH_REMATCH[2]}"
        echo "$f:$no: posts a comment with \`gh $sverb --comment\` outside pr-post.sh — the post $WHY; $FIX"
        found=1
        return 0
    fi
    if { [[ "$code" =~ $SEP$GH_API ]] || [[ "$code" =~ $WRAP$GH_API ]]; } \
       && [[ "$text" =~ $POST_PATH ]] && ! [[ "$text" =~ $NOT_A_POST ]] && [[ "$text" =~ $WRITE ]]; then
        echo "$f:$no: writes a PR comment or review through \`gh api\` outside pr-post.sh — the body $WHY; $FIX"
        found=1
    fi
}

for f in "$@"; do
    [ -f "$f" ] || continue
    case "$f" in
        */lint-learned.d/* | */lint-learned.sh | */base-snapshots/*) continue ;;
        */pr-post.sh | pr-post.sh) continue ;;
        specs/* | */specs/* | generated/* | */generated/*) continue ;;
    esac
    case "$f" in *.sh | *.toml | *.md) ;; *) continue ;; esac
    # One cheap read gates the line scan.
    grep -Eq "$GATE" "$f" 2>/dev/null || continue
    case "$f" in
        *.sh) lines="$(sh_lines "$f")" ;;
        *)    lines="$(fenced_lines "$f")" ;;
    esac
    [ -n "$lines" ] || continue
    while IFS=$'\t' read -r no kind text; do
        [ -n "$no" ] || continue
        judge "$f" "$no" "$kind" "$text"
    done <<< "$lines"
done

[ "$found" -eq 0 ]
