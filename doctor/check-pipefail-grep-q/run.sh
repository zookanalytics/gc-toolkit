#!/usr/bin/env bash
# Pack doctor check: nothing that sets `pipefail` pipes into `grep -q`.
#
# THE DEFECT.
#
#     set -o pipefail
#     printf '%s\n' "$OUT" | grep -q "PATTERN" && ok "..." || bad "..."
#
# `grep -q` exits 0 the INSTANT it matches. That closes the read end while the
# writer is still writing, the writer dies of SIGPIPE (141), `pipefail` promotes
# that to the pipeline's status, and the `&&`/`||` chain takes the FAILURE branch
# even though the match SUCCEEDED. The assertion passed and was reported red.
#
# WHY A CHECK AND NOT A CONVENTION. It is a race on how much the writer flushed
# before grep quit, so a payload that fits one write() never fires and the same
# line starts failing when the payload grows past the stdio buffer. Measured on
# the host that filed tk-zfjg9: 0/500 false failures at 105 B, 0.47% at 2552 B
# (a real merge-skill.test.sh payload), 76% at 64 KB, 100% at ~4 MB. Nothing
# about the source line changes between the safe and unsafe versions — only the
# data — so review cannot catch it and a green suite does not prove its absence.
#
# WHY IT IS WORTH AN ERROR. In the test suites the cost is spurious red on the
# gate that reviews every mr-mode PR, which rejects good work and costs a review
# cycle. In the shipped scripts it is worse than red: reconcile-graduated-
# convoys.sh read a convoy that IS in this rig's ledger as one that is not and
# silently skipped it; quota-park-nudge.sh read a parked session as clean and
# vouched for it. Those do not report anything at all. Same mechanism, one layer
# down, where the wrong branch is a merge decision rather than a test verdict.
#
# WHAT IS ASSERTED. Every `*.sh` in the pack whose `set` line enables pipefail,
# plus every marker-fenced snippet in a non-shell file — those blocks are
# EXTRACTED and executed by the tests that own them (assets/scripts/*.test.sh),
# so they inherit the extracting suite's pipefail and carry the defect with them
# even though their own file sets nothing.
#
# WHAT IS NOT ASSERTED. Files that do not set pipefail. There the writer still
# takes SIGPIPE but its status is discarded, `grep -q` answers correctly, and the
# idiom is fine — doctor/check-startup-discovery and doctor/check-base-artifact-
# collision use it deliberately. This check is about the PROMOTION, not the pipe.
#
# THE FIX, in order of preference:
#   * payload in a variable      ->  grep -q PAT <<< "$VAR"       (no pipe at all)
#   * payload from a command     ->  grep -q PAT < <(cmd)         (writer's status
#                                                                  is not the
#                                                                  pipeline's)
#   * no payload wanted at all   ->  grep -q PAT < /dev/null
#   * splitting a delimited list ->  "${VAR//,/$'\n'}" as the here-string body,
#                                    rather than piping through `tr`
#
# There is deliberately NO exception list. An empty-payload probe is provably
# safe and is still written `< /dev/null` here (assets/scripts/quota-park-nudge.sh
# valid_ere), because a rule with no exceptions is a better guard than one whose
# exceptions have to be re-litigated at every review.
#
# Exit codes: 0=OK, 1=Warning, 2=Error
# stdout: first line=message, rest=details

set -u

dir="${GC_PACK_DIR:-.}"

# A `set` COMMAND that enables pipefail — never a comment that merely mentions
# it. Several scripts here explain the trap at length in prose; matching that
# would scope the check by how well a file is documented.
SETS_PIPEFAIL='^[[:space:]]*set[[:space:]]+[^#]*pipefail'

# A pipeline feeding `grep` in quiet mode. Assembled from pieces so this file
# does not contain the very shape it bans and flag itself.
#
# `(^|[^|])` keeps `||` out: in `grep -qF a "$f" || grep -qF b "$f"` neither grep
# reads a pipe, so there is no writer to kill and nothing to promote.
QUIET_PIPE='(^|[^|])\|[[:space:]]*'"grep"'([[:space:]]+[^|]*)?[[:space:]]+(-[A-Za-z]*q[A-Za-z]*|--quiet|--silent)([[:space:]]|$)'

# Vendored upstream copies, kept for collision detection and never executed.
is_excluded() {
    case "$1" in
        */base-snapshots/*) return 0 ;;
        *) return 1 ;;
    esac
}

findings=()
scanned=0
snippets=0

scan_lines() {
    # $1 = path, $2 = label suffix. Comment lines are skipped: the pattern is
    # quoted in prose all over this pack (including in this file).
    local path="$1" suffix="$2" line no body
    while IFS= read -r line; do
        no="${line%%:*}"
        body="${line#*:}"
        case "$body" in
            [[:space:]]*'#'*)
                # Only a leading-# line is a comment; `cmd  # note` is code.
                case "$(printf '%s' "$body" | tr -d '[:space:]')" in
                    '#'*) continue ;;
                esac
                ;;
            '#'*) continue ;;
        esac
        findings+=("$path:$no:$suffix${body#"${body%%[![:space:]]*}"}")
    done < <(grep -nE "$QUIET_PIPE" "$path" 2>/dev/null)
}

# --- shell files ------------------------------------------------------------
while IFS= read -r f; do
    is_excluded "$f" && continue
    grep -qE "$SETS_PIPEFAIL" "$f" 2>/dev/null || continue
    scanned=$((scanned + 1))
    scan_lines "$f" ""
done < <(find "$dir" -type f -name '*.sh' 2>/dev/null | sort)

# --- marker-fenced snippets in non-shell files ------------------------------
# `# >>> name` ... `# <<< name` blocks are lifted verbatim by a test and run
# under that test's shell options, so the defect travels with the snippet.
while IFS= read -r f; do
    is_excluded "$f" && continue
    block="$(awk '/#[[:space:]]*>>>[[:space:]]/{inb=1} inb{print FNR": "$0} /#[[:space:]]*<<<[[:space:]]/{inb=0}' "$f" 2>/dev/null)"
    [ -n "$block" ] || continue
    snippets=$((snippets + 1))
    while IFS= read -r line; do
        no="${line%%: *}"
        body="${line#*: }"
        case "$(printf '%s' "$body" | tr -d '[:space:]')" in
            '#'*) continue ;;
        esac
        case "$body" in
            *[!A-Za-z0-9]grep*|grep*) ;;
            *) continue ;;
        esac
        # Here-string, not a pipe — this check does not get to exempt itself.
        grep -qE "$QUIET_PIPE" <<< "$body" 2>/dev/null \
            && findings+=("$f:$no: (extracted snippet) ${body#"${body%%[![:space:]]*}"}")
    done < <(printf '%s\n' "$block")
done < <(find "$dir" -type f \( -name '*.toml' -o -name '*.md' \) 2>/dev/null | sort)

if [ "${#findings[@]}" -gt 0 ]; then
    echo "${#findings[@]} pipeline(s) feed \`grep -q\` under \`set -o pipefail\` — a SUCCESSFUL match can be reported as a failure"
    printf '%s\n' "${findings[@]}"
    echo "\`grep -q\` exits at its first match and SIGPIPEs the writer; pipefail promotes that 141 to the pipeline's status, so the \`&&\`/\`||\` chain takes the failure branch on a match that succeeded. It is a race on how much the writer flushed, so it is invisible at small payloads and fires as they grow."
    printf '%s\n' "Fix: \`grep -q PAT <<< \"\$VAR\"\` for a variable payload, \`grep -q PAT < <(cmd)\` for a command's output, \`grep -q PAT < /dev/null\` when no input is wanted. Split a delimited list with \"\${VAR//,/\$'\\n'}\" rather than piping through \`tr\`."
    exit 2
fi

if [ "$scanned" -eq 0 ] && [ "$snippets" -eq 0 ]; then
    echo "OK: no pipefail-setting shell file and no extracted snippet found under $dir — nothing to check"
    exit 0
fi

echo "OK: $scanned pipefail-setting shell file(s) and $snippets file(s) of extracted snippets feed no pipeline into \`grep -q\`"
