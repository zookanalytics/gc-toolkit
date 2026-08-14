#!/usr/bin/env bash
# stale-reference.sh — hardened learned rule: no comments that describe code
# in terms of what it USED TO BE.
#
# Flags comment lines, in the changed files the runner hands us, that match a
# historical-artifact phrase family ("used to", "previously", "formerly", …).
# A comment that narrates history goes stale the moment the history stops
# mattering; describe the current behavior or delete the comment. The runner's
# changed-file scoping is what makes these NEWLY PRESENT lines — this detector
# never sweeps the whole tree, so pre-existing prose elsewhere is not churned.
#
# Comment leaders handled generically: #, //, /* … */, <!-- … -->, and the
# leading-`*` continuation of block comments. Markdown/HTML/XML files only
# count <!-- --> comments — a `#` there is a heading, not a comment, and
# specs/docs legitimately discuss history in prose.
#
# Built-in exclusion: the passive purpose form "…is/are/was/were/be/been/being
# used to <verb>…" describes what something is FOR, not what it used to be,
# and is dropped (prefer false negatives).
#
# Allowlist: a co-located stale-reference.allow file, one extended regex per
# line (blank lines and #-comments ignored); any candidate line matching any
# allow regex is skipped. Use it for phrases a repo legitimately needs
# (e.g. a changelog convention).
#
# Exit: 0 clean, 1 findings as `<file>:<line>: <message>`.

set -uo pipefail

# ── THE TUNABLE PART: the historical-artifact phrase family ────────────
# Extended-regex alternatives, matched case-insensitively and word-boundary
# aware. Widen or narrow the learned rule here — everything below is plumbing.
PHRASES=(
    "used to"
    "previously"
    "formerly"
    "was originally"
    "historical"
    "legacy note"
    "left over from"
    "back when"
)

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
allow_file="$here/stale-reference.allow"

# Allowlist regexes (optional file; absent = empty allowlist).
allow=()
if [ -f "$allow_file" ]; then
    while IFS= read -r rx; do
        case "$rx" in "" | \#*) continue ;; esac
        allow+=("$rx")
    done < "$allow_file"
fi

# Build one alternation from the phrase array.
phrase_alt=""
for p in "${PHRASES[@]}"; do
    phrase_alt="${phrase_alt:+$phrase_alt|}$p"
done

# Word-boundary framing without GNU-only \b: a phrase hit must not be glued
# to an identifier character on either side.
bounded="([^[:alnum:]_]|^)($phrase_alt)([^[:alnum:]_]|$)"

# The passive purpose form of "used to" — not a stale reference.
purpose_form="(^|[^[:alnum:]_])(is|are|was|were|be|been|being)[[:space:]]+used[[:space:]]+to[[:space:]]"

# The ELLIPTICAL purpose form: "Used to translate X" at the start of a
# comment, or "— used to align Y" after punctuation, means "this is used
# to…". Excluded UNLESS followed by be/have, which keeps the genuinely
# historical "Used to be…" / "— used to have…" (prefer false negatives).
ellipsis_form="((#|//|<!--|/\*)[[:space:]]*|[.;:,][[:space:]]+|[-—][[:space:]]+)used[[:space:]]+to[[:space:]]"
history_follow="used[[:space:]]+to[[:space:]]+(be|have)[[:space:]]"

found=0

for f in "$@"; do
    [ -f "$f" ] || continue

    # Never lint the detectors themselves: their phrase arrays and headers
    # necessarily contain the phrases they hunt, so self-lint is pure noise.
    case "$f" in */lint-learned.d/* | */lint-learned.sh) continue ;; esac

    # Per-filetype comment leaders. Markdown/HTML/XML: <!-- --> only.
    case "$f" in
        *.md | *.markdown | *.html | *.htm | *.xml)
            leader='<!--'
            ;;
        *)
            leader='(#|//|/\*|<!--|^[[:space:]]*\*[[:space:]])'
            ;;
    esac

    while IFS= read -r hit; do
        lineno="${hit%%:*}"
        text="${hit#*:}"

        # Drop the purpose-passive "…be used to <verb>" form.
        if grep -qiE "$purpose_form" <<< "$text"; then
            continue
        fi
        # Drop the elliptical purpose form, keeping "used to be/have".
        if grep -qiE "$ellipsis_form" <<< "$text" \
            && ! grep -qiE "$history_follow" <<< "$text"; then
            continue
        fi

        # Allowlist: skip lines matching any operator-supplied regex.
        skip=""
        for rx in ${allow[@]+"${allow[@]}"}; do
            if grep -qE "$rx" <<< "$text"; then
                skip=1
                break
            fi
        done
        [ -n "$skip" ] && continue

        phrase="$(printf '%s' "$text" | grep -oiE "($phrase_alt)" | head -n 1)"
        echo "$f:$lineno: comment describes what the code used to be (\"$phrase\") — describe current behavior or delete (learned rule: stale-reference)"
        found=1
    done < <(grep -nIiE "${leader}.*${bounded}" -- "$f" 2>/dev/null || true)
done

[ "$found" -eq 0 ]
