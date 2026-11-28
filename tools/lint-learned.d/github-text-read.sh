#!/usr/bin/env bash
# github-text-read.sh — the pack reads the text people post on GitHub only
# through gctk github quote.
#
# gctk github quote holds a post by an account outside the repository for the
# operator and quotes every other post inert, so the text reaches an agent in a
# form that runs nothing when it is quoted into a command. A read with gh hands
# the agent the text as GitHub gives it.
#
# Scanned as pr-post-bypass.sh scans, through shell-lines.lib: *.sh, and the
# fenced code of *.toml and *.md. specs/ and generated/ are records, and
# .github/ is the repository's CI, which runs no agent. Three findings:
#   1. `gh pr view` or `gh issue view` in command position that reads posted
#      text: given --comments, given --json naming title, body, comments,
#      reviews or latestReviews, or given neither --json nor --web, which
#      prints the title and the body. A --json whose field list is a variable
#      is not judged;
#   2. `gh api`, or a gh_api* wrapper, reading a comment or review endpoint: a
#      path under issues/…/comments, issues/comments, pulls/…/comments,
#      pulls/comments or pulls/…/reviews, with no write method or body field,
#      which pr-post-bypass.sh judges, and not a dismissal, a reaction or a
#      reviewer re-request;
#   3. a GraphQL document that pages a conversation connection: reviewThreads,
#      comments, reviews, latestReviews or latestOpinionatedReviews called with
#      first, last, after or before.
# Quoted strings and here-doc bodies are data, so 1 and 2 read command
# positions only. 3 reads the call wherever it sits, here-doc bodies included,
# because a GraphQL document is always a string. Whole-line comments are
# skipped.
#
# Exempt: this directory, where the shapes are stated. gctk itself is Go, which
# no detector scans.
#
# Exit: 0 clean, 1 findings as `<file>:<line>: <message>`, 2 when a file cannot
# be scanned.

set -uo pipefail

FIX='fix: read it through gctk github quote <issue, PR or post URL> (rule: github-text-read)'
WHY='reaches the agent as GitHub gives it, so an outside account'"'"'s post is not held for the operator and no text is quoted inert'

# A line worth a closer look: a gh call, a gh_api wrapper, or a conversation
# connection's name. awk reads it as a -v value, where a backslash escapes, so
# it spells a parenthesis as a bracket expression.
GATE='(^|[^[:alnum:]_])gh([[:space:]]|_api)|reviewThreads|latestReviews|latestOpinionatedReviews|(comments|reviews)[[:space:]]*[(]'

# Leading `VAR=value` assignments ride in front of a command.
ASSIGNS='([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*'
# Command position, in two shapes: after a separator, and after a word that runs
# the command that follows it.
SEP='(^|[;&|(){}]|\$\(|`)[[:space:]]*'"$ASSIGNS"
WRAP='(^|[^[:alnum:]_./-])(then|do|else|elif|if|while|until|run_bounded|bounded|command|exec|env|nohup|xargs|time|!)[[:space:]]+'"$ASSIGNS"
GH_VIEW='gh[[:space:]]+(pr|issue)[[:space:]]+view([[:space:]]|;|\)|$)'
GH_API='(gh[[:space:]]+api|gh_api[[:alnum:]_]*)([[:space:]]|$)'
# A comment or review endpoint, and the three that carry no posted text.
TEXT_PATH='(issues|pulls)/([^[:space:]/"'"'"']+/)?comments([^[:alnum:]_]|$)|pulls/[^[:space:]/"'"'"']+/reviews([^[:alnum:]_]|$)'
NOT_TEXT='/(dismissals|reactions|requested_reviewers)([^[:alnum:]_]|$)'
# gh api writes when the method says so, or when it is handed a body.
WRITE='(^|[[:space:]])(-X|--method)[[:space:]=]*["'"'"']?(POST|PATCH|PUT|DELETE)|(^|[[:space:]])(-f|-F|--field|--raw-field)[[:space:]]+["'"'"']?body=|(^|[[:space:]])--input([[:space:]=]|$)'
CONNECTION='(^|[^[:alnum:]_])(reviewThreads|comments|reviews|latestReviews|latestOpinionatedReviews)[[:space:]]*\([[:space:]]*(first|last|after|before)[[:space:]]*:'
# The fields of a --json list that carry posted text.
TEXT_FIELD='(^|,)(title|body|comments|reviews|latestReviews)(,|$)'

# The line scanner (FOLD_AWK, sh_lines, fenced_lines and strip_quoted), shared
# with the other detectors that judge shell commands.
# shellcheck source=shell-lines.lib
. "${BASH_SOURCE[0]%/*}/shell-lines.lib" || { echo "github-text-read: cannot source shell-lines.lib beside it" >&2; exit 2; }

found=0

# cannot_scan <file> <tool> — a tool that failed on a file left it unscanned,
# and reporting nothing would pass it as clean, so the run ends in an error.
cannot_scan() {
    echo "github-text-read: $2 failed on $1 — detector cannot scan it" >&2
    exit 2
}

# view_reads_text <text> — whether the gh pr view or gh issue view in text
# reads posted text, judged from the view to the end of its command.
view_reads_text() {
    local rest="$1" fields
    [[ "$rest" =~ gh[[:space:]]+(pr|issue)[[:space:]]+view(.*)$ ]] || return 1
    rest="${BASH_REMATCH[2]}"
    rest="${rest%%[|;&\`)]*}"
    [[ "$rest" =~ (^|[[:space:]])(--comments|-c)([[:space:]=]|$) ]] && return 0
    if [[ "$rest" =~ (^|[[:space:]])--json([[:space:]]+|=)[\"\']?([^[:space:]\"\']*) ]]; then
        fields="${BASH_REMATCH[3]}"
        case "$fields" in '$'* | '') return 1 ;; esac
        [[ "$fields" =~ $TEXT_FIELD ]]
        return
    fi
    [[ "$rest" =~ (^|[[:space:]])(--web|-w)([[:space:]]|$) ]] && return 1
    return 0
}

# judge <file> <lineno> <kind> <text> — report each finding the line makes.
judge() {
    local f="$1" no="$2" kind="$3" text="$4" trimmed code
    trimmed="${text#"${text%%[![:space:]]*}"}"
    case "$trimmed" in '#'*) return 0 ;; esac
    if [[ "$text" =~ $CONNECTION ]]; then
        echo "$f:$no: a GraphQL document pages \`${BASH_REMATCH[2]}\` outside gctk — the text $WHY; $FIX"
        found=1
    fi
    [ "$kind" = C ] || return 0
    code="$(strip_quoted "$text")"
    if { [[ "$code" =~ $SEP$GH_VIEW ]] || [[ "$code" =~ $WRAP$GH_VIEW ]]; } && view_reads_text "$text"; then
        local verb="pr view"
        [[ "$code" =~ gh[[:space:]]+(pr|issue)[[:space:]]+view ]] && verb="${BASH_REMATCH[1]} view"
        echo "$f:$no: reads posted text with \`gh $verb\` — the text $WHY; $FIX"
        found=1
        return 0
    fi
    if { [[ "$code" =~ $SEP$GH_API ]] || [[ "$code" =~ $WRAP$GH_API ]]; } \
       && [[ "$text" =~ $TEXT_PATH ]] && ! [[ "$text" =~ $NOT_TEXT ]] && ! [[ "$text" =~ $WRITE ]]; then
        echo "$f:$no: reads a comment or review endpoint with \`gh api\` — the text $WHY; $FIX"
        found=1
    fi
}

for f in "$@"; do
    [ -f "$f" ] || continue
    case "$f" in
        */lint-learned.d/* | */lint-learned.sh | */base-snapshots/*) continue ;;
        specs/* | */specs/* | generated/* | */generated/* | .github/* | */.github/*) continue ;;
    esac
    case "$f" in *.sh | *.toml | *.md) ;; *) continue ;; esac
    # One cheap read gates the line scan. Exit 1 is a file with no gh call and
    # no connection name; anything past it is a file grep could not read, which
    # a skip would pass unscanned.
    grep -Eq "$GATE" "$f" 2>/dev/null; rc=$?
    [ "$rc" -eq 1 ] && continue
    [ "$rc" -eq 0 ] || cannot_scan "$f" grep
    case "$f" in
        *.sh) lines="$(sh_lines "$f")" || cannot_scan "$f" awk ;;
        *)    lines="$(fenced_lines "$f")" || cannot_scan "$f" awk ;;
    esac
    [ -n "$lines" ] || continue
    while IFS=$'\t' read -r no kind text; do
        [ -n "$no" ] || continue
        judge "$f" "$no" "$kind" "$text"
    done <<< "$lines"
done

[ "$found" -eq 0 ]
