#!/usr/bin/env bash
# pr-post-bypass.sh — hardened learned rule: the pack posts on a pull request
# only through assets/scripts/pr-post.sh.
#
# The city posts under the bot account that backs every agent's gh token, so
# pr-facts.sh tells the city's notices from feedback by the provenance mark
# pr-post.sh appends, not by the author. A post that bypasses the
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
# Exit: 0 clean, 1 findings as `<file>:<line>: <message>`, 2 when a file cannot
# be scanned.

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

# The line scanner (FOLD_AWK, sh_lines, fenced_lines and strip_quoted), shared
# with the other detectors that judge shell commands.
# shellcheck source=shell-lines.lib
. "${BASH_SOURCE[0]%/*}/shell-lines.lib" || { echo "pr-post-bypass: cannot source shell-lines.lib beside it" >&2; exit 2; }

found=0

# cannot_scan <file> <tool> — a tool that failed on a file left it unscanned,
# and reporting nothing would pass it as clean, so the run ends in an error.
cannot_scan() {
    echo "pr-post-bypass: $2 failed on $1 — detector cannot scan it" >&2
    exit 2
}

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
    # One cheap read gates the line scan. Exit 1 is a file with no gh call and
    # no mutation name; anything past it is a file grep could not read, which a
    # skip would pass unscanned.
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
