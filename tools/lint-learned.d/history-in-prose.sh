#!/usr/bin/env bash
# history-in-prose.sh — hardened learned rule: living prose states what is
# true NOW. Living code, agent prompts and docs instruct; specs and bead
# descriptions are where the record of how something was learned belongs.
#
# MECHANICAL DETECTOR. It flags three markers that reliably indicate a
# passage is narrating history rather than instructing:
#   1. bead ids, by the store prefixes in use;
#   2. PR references — #<n> and pull/<n>;
#   3. absolute dates, ISO or written out.
# Narration in general — a comment restating the line below it — is a
# DELIBERATE NON-GOAL: it needs judgment, and the false positives would get
# the detector switched off. These three markers are mechanical and cheap.
#
# WHAT COUNTS AS PROSE:
#   • markdown-family files — the document body, minus fenced code blocks,
#     inline code spans and HTML comments;
#   • every other text file — comment lines only. A bead id in a shell
#     command is an argument, not a narrative.
#
# WHERE HISTORY IS CORRECT, and so exempt:
#   • specs/** and any bead-keyed directory — the record of how something
#     was learned;
#   • CHANGELOG-shaped files, whose whole job is history;
#   • HTML comments in markdown: here they carry the learning system's
#     provenance anchors (docs/feedback-learning.md), which are REQUIRED to
#     name a source ref and an adoption date;
#   • a path INTO specs — `specs/<bead-id>/…` names where the record lives,
#     which is the rule working rather than a violation;
#   • generated files, by tier or by header marker: their text is emitted by
#     a tool, so a finding there names nothing the author can fix.
#
# Tuned to PREFER FALSE NEGATIVES over false positives:
#   • a marker inside an inline code span is a command argument, not a
#     citation, and is dropped;
#   • a written-out date must carry a year, so "August" alone stays prose;
#   • `#<n>` must be a bare token, so `#!`, headings and `${#arr[@]}` never
#     match.
#
# Escape hatch, where a real instruction must cite an identifier: a
# co-located history-in-prose.allow file, one extended regex per line (blank
# lines and #-comments ignored); any candidate line matching any allow regex
# is skipped. Prefer it over a bare inline suppression comment, which is
# itself the kind of noise this rule exists to remove.
#
# Matching is pure bash: the runner may hand a detector every changed file on
# every bead, so the per-line path forks no processes.
#
# Exit: 0 clean, 1 findings as `<file>:<line>: <message>`.

set -uo pipefail

# ── THE TUNABLE PART: the store prefixes in use ─────────────────────────
# A bead id is <prefix>-<5-8 base36>, one prefix per store. The live city
# stores are the ones `gc rig list --json` reports; `ga` is the upstream
# gascity store, whose ids the tracking ledgers under docs/ cite. A store
# joining the set needs a prefix here and a fixture in
# assets/scripts/history-in-prose.test.sh, which fails on drift either way.
# `lx` is the city's own store, so it also spells session ids and mail
# wisps; those cite provenance the same way a work-bead id does.
BEAD_PREFIXES=(lx tk sl gc su ga)

# `gc-` is also this pack's command namespace — gc-toolkit, gc-status,
# gc-sling — and `lx-` is the shape tests use for synthetic session names,
# lx-codex and lx-clean. Requiring a digit in the suffix separates an id
# from either. The cost is all-alpha ids of those two stores, which is the
# false negative this rule prefers over lighting up on every file that
# names the toolkit or stubs a session.
DIGIT_REQUIRED_PREFIXES=(gc lx)

# Both capitalisations, so "August" and "august" match and "AUGUST" does not.
MONTHS='([Jj]an(uary)?|[Ff]eb(ruary)?|[Mm]ar(ch)?|[Aa]pr(il)?|[Mm]ay|[Jj]un(e)?|[Jj]ul(y)?|[Aa]ug(ust)?|[Ss]ep(t|tember)?|[Oo]ct(ober)?|[Nn]ov(ember)?|[Dd]ec(ember)?)'
# ── end tunable part ────────────────────────────────────────────────────

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
allow_file="$here/history-in-prose.allow"

allow=()
if [ -f "$allow_file" ]; then
    while IFS= read -r rx; do
        case "$rx" in "" | \#*) continue ;; esac
        allow+=("$rx")
    done < "$allow_file"
fi

prefix_alt=""
for p in ${BEAD_PREFIXES[@]+"${BEAD_PREFIXES[@]}"}; do
    prefix_alt="${prefix_alt:+$prefix_alt|}$p"
done
bead_token_re="^(${prefix_alt})-[0-9a-z]{5,8}\$"

# Cheap gates. A line with no digit and no store prefix carries no marker at
# all; a line with no candidate bead-id shape need not be tokenised.
gate_re="[0-9]|(${prefix_alt})-"
bead_line_re="(^|[^[:alnum:]_])(${prefix_alt})-[0-9a-z]{5,8}([^[:alnum:]_]|\$)"

# `#<n>` as a bare token: not glued to an identifier, and not the `#` of a
# shebang, a heading, `$#` or `${#arr[@]}`. A trailing `-` is excluded so a
# markdown heading anchor — [Verification](#5-verification) — is not a PR.
pr_hash_re='(^|[^[:alnum:]_$#{])(#[0-9]{1,6})([^[:alnum:]_-]|$)'
pr_path_re='(^|[^[:alnum:]_])(pull/[0-9]{1,6})([^[:alnum:]_]|$)'
iso_date_re='(^|[^0-9-])((19|20)[0-9]{2}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01]))([^0-9-]|$)'
month_first_re="(^|[^[:alnum:]_])(${MONTHS}\.?[[:space:]]+([0-9]{1,2}(st|nd|rd|th)?,?[[:space:]]+)?(19|20)[0-9]{2})([^0-9]|$)"
day_first_re="(^|[^[:alnum:]_])([0-9]{1,2}(st|nd|rd|th)?[[:space:]]+${MONTHS}\.?,?[[:space:]]+(19|20)[0-9]{2})([^0-9]|$)"

generated_re='([Cc]ode generated|DO NOT EDIT|@generated|[Aa]uto(matically |-)?generated)'
fence_re='^[[:space:]]{0,3}(`{3,}|~{3,})'
block_cont_re='^[[:space:]]*\*+[[:space:]](.*)$'

# A token is a bead id if it has a store prefix, the base36 shape, and — for
# a prefix that doubles as a namespace — a digit.
is_bead_id() {
    local tok="$1" pfx p
    [[ "$tok" =~ $bead_token_re ]] || return 1
    pfx="${tok%%-*}"
    for p in ${DIGIT_REQUIRED_PREFIXES[@]+"${DIGIT_REQUIRED_PREFIXES[@]}"}; do
        if [ "$p" = "$pfx" ]; then
            [[ "$tok" =~ [0-9] ]] || return 1
        fi
    done
    return 0
}

# Any path component that is itself a bead id makes the file bead-keyed.
path_is_bead_keyed() {
    local part
    local IFS='/'
    for part in $1; do
        is_bead_id "$part" && return 0
    done
    return 1
}

# Emitted by a tool, not authored: the tier, or the marker conventions that
# generators write into a header.
is_generated() {
    local f="$1" i=0 line
    case "$f" in generated/* | */generated/*) return 0 ;; esac
    while [ "$i" -lt 8 ] && IFS= read -r line; do
        i=$((i + 1))
        [[ "$line" =~ $generated_re ]] && return 0
    done < "$f"
    return 1
}

found=0
finding() {
    echo "$1:$2: $3 in living prose ('$4') — state what is true now; the record of how it was learned belongs in specs or the bead (learned rule: history-in-prose)"
    found=1
}

# One finding per line, first marker wins: a paragraph of history trips every
# marker at once, and repeating it per marker buries the rest of the file.
check_line() {
    local f="$1" lineno="$2" prose="$3" tok rx

    [[ "$prose" =~ $gate_re ]] || return 0

    for rx in ${allow[@]+"${allow[@]}"}; do
        [[ "$prose" =~ $rx ]] && return 0
    done

    if [[ "$prose" =~ $bead_line_re ]]; then
        for tok in ${prose//[^0-9a-zA-Z_-]/ }; do
            is_bead_id "$tok" || continue
            # A path into specs points at where the record lives.
            [[ "$prose" == *"specs/$tok"* ]] && continue
            finding "$f" "$lineno" "cites bead id" "$tok"
            return 0
        done
    fi

    if [[ "$prose" =~ $pr_hash_re ]] || [[ "$prose" =~ $pr_path_re ]]; then
        finding "$f" "$lineno" "cites PR reference" "${BASH_REMATCH[2]}"
        return 0
    fi

    if [[ "$prose" =~ $iso_date_re ]] || [[ "$prose" =~ $month_first_re ]] \
       || [[ "$prose" =~ $day_first_re ]]; then
        finding "$f" "$lineno" "cites absolute date" "${BASH_REMATCH[2]}"
        return 0
    fi
    return 0
}

# Inline code spans, replaced with a space. An unmatched trailing backtick
# leaves the remainder as prose rather than swallowing the rest of the line.
STRIPPED=""
strip_inline_code() {
    local s="$1" pre rest
    STRIPPED=""
    while [[ "$s" == *'`'* ]]; do
        pre="${s%%\`*}"
        rest="${s#*\`}"
        if [[ "$rest" == *'`'* ]]; then
            STRIPPED+="$pre "
            s="${rest#*\`}"
        else
            STRIPPED+="$pre$rest"
            s=""
        fi
    done
    STRIPPED+="$s"
}

scan_markdown() {
    local f="$1" line prose tok pre rest lines
    local in_fence=0 fence_tok="" in_html=0 i n
    mapfile -t lines < "$f"
    n="${#lines[@]}"

    for ((i = 0; i < n; i++)); do
        line="${lines[$i]}"

        if [[ "$line" =~ $fence_re ]]; then
            tok="${BASH_REMATCH[1]:0:1}"
            if [ "$in_fence" -eq 0 ]; then
                in_fence=1; fence_tok="$tok"
            elif [ "$tok" = "$fence_tok" ]; then
                in_fence=0; fence_tok=""
            fi
            continue
        fi
        [ "$in_fence" -eq 1 ] && continue

        prose="$line"
        if [ "$in_html" -eq 1 ]; then
            case "$prose" in
                *'-->'*) prose="${prose#*-->}"; in_html=0 ;;
                *) continue ;;
            esac
        fi
        while [[ "$prose" == *'<!--'* ]]; do
            pre="${prose%%<!--*}"
            rest="${prose#*<!--}"
            if [[ "$rest" == *'-->'* ]]; then
                prose="$pre ${rest#*-->}"
            else
                prose="$pre"
                in_html=1
            fi
        done

        strip_inline_code "$prose"
        check_line "$f" "$((i + 1))" "$STRIPPED"
    done
}

# Comment portion of a source line: text from the LEFTMOST comment leader,
# or a block-comment continuation line. A leader counts only at line start or
# after whitespace — a `#` or `//` mid-token (sed delimiters, URLs, awk
# patterns) is not a comment.
scan_comments() {
    local f="$1" line comment pre best l i n lines
    mapfile -t lines < "$f"
    n="${#lines[@]}"

    for ((i = 0; i < n; i++)); do
        line="${lines[$i]}"
        comment=""
        best=${#line}
        for l in '#' '//' '/*' '<!--'; do
            pre="${line%%"$l"*}"
            if [ "$pre" != "$line" ] && [ "${#pre}" -lt "$best" ] \
               && { [ -z "$pre" ] || [[ "$pre" =~ [[:space:]]$ ]]; }; then
                best="${#pre}"
                # `#` is both a comment leader and the PR sigil, so it stays
                # in the prose; every other leader is dropped.
                if [ "$l" = '#' ]; then
                    comment="${line:$best}"
                else
                    comment="${line:$((best + ${#l}))}"
                fi
            fi
        done
        if [ -z "$comment" ] && [[ "$line" =~ $block_cont_re ]]; then
            comment="${BASH_REMATCH[1]}"
        fi
        [ -n "$comment" ] || continue

        strip_inline_code "$comment"
        check_line "$f" "$((i + 1))" "$STRIPPED"
    done
}

for f in "$@"; do
    [ -f "$f" ] || continue

    # Never lint the detectors themselves: a header documenting the markers
    # it hunts necessarily contains them.
    case "$f" in */lint-learned.d/* | */lint-learned.sh) continue ;; esac

    # specs/** and bead-keyed directories ARE the record; history belongs there.
    case "$f" in specs/* | */specs/*) continue ;; esac
    path_is_bead_keyed "$f" && continue

    # A changelog's whole job is history.
    case "${f##*/}" in
        [Cc]hange[Ll]og* | CHANGELOG* | [Cc]hanges.* | CHANGES.* \
        | [Hh]istory.* | HISTORY.* | [Nn]ews.* | NEWS.* \
        | [Rr]elease-[Nn]otes* | RELEASE-NOTES* | [Rr]eleases.* | RELEASES.*) continue ;;
    esac

    grep -qI . -- "$f" 2>/dev/null || continue
    is_generated "$f" && continue

    case "$f" in
        *.md | *.markdown) scan_markdown "$f" ;;
        *) scan_comments "$f" ;;
    esac
done

[ "$found" -eq 0 ]
