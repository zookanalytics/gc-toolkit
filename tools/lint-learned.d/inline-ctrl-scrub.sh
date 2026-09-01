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
# Consolidating onto one helper also retires the names it replaced, and a call
# to a retired name is invisible to the tools that would normally catch it: an
# undefined function is a runtime failure, so `bash -n` passes and the script
# dies with `command not found` only on the branch that reaches the call.
#
# Scanned: *.sh. Four findings:
#   1. a control-character `tr -d` outside the canonical fence;
#   2. a canonical fence whose helper line disagrees with the one byte set;
#   3. a call to a retired scrub helper name, which is defined nowhere;
#   4. a `| scrub` in a file that defines `scrub` nowhere, so the helper it
#      pipes into does not exist there either.
#
# Findings 3 and 4 are the two ways a scrub call names a function the file does
# not define. Both are read lexically and neither needs a shell parser: 3 is a
# fixed set of dead names, and 4 pairs one call shape with the one definition
# shape. The fence markers say where the definition belongs; only the
# definition line proves it is there. A general undefined-caller check is out
# of reach here: `|` is also jq's and awk's own operator, and telling a dead
# call from a live external command needs the parse this file does not do.
#
# NOT a finding: a control-character `tr -d` inside SOME OTHER `# >>> name`
# fence. Those blocks are lifted verbatim into prompt templates and formula
# TOMLs, where no shell function is in scope and every copy must stay
# byte-identical; `tr -d '[:cntrl:]'` is the portable form and belongs there.
# A `| scrub` inside such a fence is skipped for the same reason: what is in
# scope at the destination is the destination's question. A retired NAME is a
# finding wherever it appears, fence or not — no destination defines it.
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
# A set held in a variable (`tr -d "$SET"`) names no bytes here and is invisible.
CTRL_TR="tr[[:space:]]+-d[[:space:]]+[\"']?[^\"']*(\\\\0[0-9]|\[:cntrl:\])"
# The names the consolidation onto `scrub` retired. Nothing defines them and
# nothing may call them; they are listed rather than inferred because deciding
# whether an arbitrary pipeline target resolves needs a shell parser.
RETIRED_RE='(^|[^[:alnum:]_])(strip_ctl|strip_ctrl)([^[:alnum:]_]|$)'
# `scrub` reached as a pipeline target, the one shape the pack calls it in.
# The terminator is any non-identifier byte, so a call closing a command
# substitution (`| scrub)`) reads the same as `| scrub | jq .`, while a longer
# name that merely starts with it (`| scrubbed`) is not a call to this helper.
CALL_RE='\|[[:space:]]*scrub([^[:alnum:]_]|$)'
OPEN_RE='^[[:space:]]*#[[:space:]]*>>>[[:space:]]+([A-Za-z0-9_-]+)[[:space:]]*$'
CLOSE_RE='^[[:space:]]*#[[:space:]]*<<<[[:space:]]+([A-Za-z0-9_-]+)[[:space:]]*$'
FIX="fix: use the shared \`scrub\` helper (learned rule: inline-ctrl-scrub)"
FIX_CALL="fix: call \`scrub\`, and carry the \`# >>> $FENCE\` block that defines it (learned rule: inline-ctrl-scrub)"

found=0

for f in "$@"; do
    [ -f "$f" ] || continue
    case "$f" in
        */lint-learned.d/* | */lint-learned.sh | */base-snapshots/*) continue ;;
        *.sh) ;;
        *) continue ;;
    esac
    # One cheap read decides whether the file is worth a line scan at all.
    # A file with no `tr -d` can still call a scrub helper it never defines,
    # so the names are part of the same read.
    grep -Eq 'tr[[:space:]]+-d|scrub|strip_ct' "$f" 2>/dev/null || continue

    fence="" lineno=0 defines_scrub=0
    calls=()
    while IFS= read -r line || [ -n "$line" ]; do
        lineno=$((lineno + 1))
        case "$line" in *tr*-d* | *'>>>'* | *'<<<'* | *scrub* | *strip_ct*) ;; *) continue ;; esac

        if [[ "$line" =~ $OPEN_RE ]]; then fence="${BASH_REMATCH[1]}"; continue; fi
        if [[ "$line" =~ $CLOSE_RE ]]; then fence=""; continue; fi

        # Whole-line comments only; `cmd  # note` is code.
        trimmed="${line#"${line%%[![:space:]]*}"}"
        case "$trimmed" in '#'*) continue ;; esac

        # The fence markers say where the helper is meant to live; only a
        # definition line proves the file has one. An empty or renamed fence
        # defines nothing, and a fence carrying the wrong byte set is finding 2.
        case "$trimmed" in 'scrub()'* | 'scrub ()'* | 'function scrub'*) defines_scrub=1 ;; esac

        if [[ "$line" =~ $RETIRED_RE ]]; then
            echo "$f:$lineno: \`${BASH_REMATCH[2]}\` is a retired scrub helper name, defined nowhere — the call dies at runtime and \`bash -n\` cannot see it; $FIX_CALL"
            found=1
        fi

        if [ "$fence" = "$FENCE" ]; then
            # Inside the canonical fence only the canonical helper may appear.
            case "$line" in
                *tr*-d*)
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

        # Held until the whole file is read: the fence may sit below the call.
        [[ "$line" =~ $CALL_RE ]] && calls+=("$lineno")
    done < "$f"

    if [ "$defines_scrub" -eq 0 ]; then
        for lineno in ${calls+"${calls[@]}"}; do
            echo "$f:$lineno: \`scrub\` is called here but the file defines it nowhere — the pack has no include mechanism, so every caller carries its own \`# >>> $FENCE\` block; $FIX_CALL"
            found=1
        done
    fi
done

[ "$found" -eq 0 ]
