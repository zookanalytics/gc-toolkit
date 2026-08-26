#!/usr/bin/env bash
# inline-ctrl-scrub.sh — hardened learned rule: a shell script scrubs control
# characters out of JSON with the shared `scrub` helper, never with its own
# inline `tr -d`.
#
# Independent inline scrubs drift. The pack has carried three disagreeing byte
# sets at once, two of them deleting TAB and one sparing it, so the same bead
# text parsed differently depending on which script read it. The helper lives
# as a marker-fenced copy (# >>> control-char-scrub) in every script that
# needs it — formula bodies are plain string substitution and there is no
# include mechanism, so identical copies are the pack's sharing idiom.
#
# Scanned: *.sh. Two findings:
#   1. a control-character `tr -d` outside the canonical fence;
#   2. a canonical fence whose helper line disagrees with the one byte set.
#
# NOT a finding: a control-character `tr -d` inside SOME OTHER `# >>> name`
# fence. Those blocks are lifted verbatim into prompt templates and formula
# TOMLs, where no shell function is in scope and every copy must stay
# byte-identical; `tr -d '[:cntrl:]'` is the portable form and belongs there.
# Whole-line comments are skipped — the shape gets quoted in prose.
#
# Matching is pure bash: this runs inside a gate on every bead, so it must
# not spawn a process per line.
#
# Exit: 0 clean, 1 findings as `<file>:<line>: <message>`.

set -uo pipefail

FENCE="control-char-scrub"
# The one byte set: every C0 byte except LF. This file is exempt from its own
# scan, so it may state the canonical line literally.
CANON="scrub() { tr -d '\\000-\\011\\013-\\037'; }"
# A `tr -d` whose set names C0 bytes, spelled as octal escapes or as the class.
CTRL_TR="tr[[:space:]]+-d[[:space:]]+'[^']*(\\\\0[0-9]|\[:cntrl:\])[^']*'"
OPEN_RE='^[[:space:]]*#[[:space:]]*>>>[[:space:]]+([A-Za-z0-9_-]+)[[:space:]]*$'
CLOSE_RE='^[[:space:]]*#[[:space:]]*<<<[[:space:]]+([A-Za-z0-9_-]+)[[:space:]]*$'
FIX="fix: use the shared \`scrub\` helper (learned rule: inline-ctrl-scrub)"

found=0

for f in "$@"; do
    [ -f "$f" ] || continue
    case "$f" in
        */lint-learned.d/* | */lint-learned.sh | */base-snapshots/*) continue ;;
        *.sh) ;;
        *) continue ;;
    esac
    # One cheap read decides whether the file is worth a line scan at all.
    grep -q "tr -d" "$f" 2>/dev/null || continue

    fence="" lineno=0
    while IFS= read -r line || [ -n "$line" ]; do
        lineno=$((lineno + 1))
        case "$line" in *"tr -d"* | *'>>>'* | *'<<<'*) ;; *) continue ;; esac

        if [[ "$line" =~ $OPEN_RE ]]; then fence="${BASH_REMATCH[1]}"; continue; fi
        if [[ "$line" =~ $CLOSE_RE ]]; then fence=""; continue; fi

        # Whole-line comments only; `cmd  # note` is code.
        trimmed="${line#"${line%%[![:space:]]*}"}"
        case "$trimmed" in '#'*) continue ;; esac

        if [ "$fence" = "$FENCE" ]; then
            # Inside the canonical fence only the canonical helper may appear.
            case "$line" in
                *"tr -d"*)
                    if [ "$line" != "$CANON" ]; then
                        echo "$f:$lineno: the $FENCE block disagrees with the pack's one byte set — copies must be byte-identical; $FIX"
                        found=1
                    fi ;;
            esac
            continue
        fi

        # Any other fence is a portable snippet: no helper is in scope there.
        [ -n "$fence" ] && continue

        if [[ "$line" =~ $CTRL_TR ]]; then
            echo "$f:$lineno: inline control-character scrub — independent byte sets drift apart; $FIX"
            found=1
        fi
    done < "$f"
done

[ "$found" -eq 0 ]
