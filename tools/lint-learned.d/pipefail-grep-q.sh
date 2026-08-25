#!/usr/bin/env bash
# pipefail-grep-q.sh — hardened learned rule: nothing that sets `pipefail`
# pipes into `grep -q` (ported from the retired doctor/check-pipefail-grep-q).
# `grep -q` exits at its first match and SIGPIPEs the writer; pipefail
# promotes that 141 to the pipeline's status, so an `&&`/`||` chain takes the
# failure branch on a match that SUCCEEDED — a race on how much the writer
# flushed, invisible at small payloads and firing as they grow. Scanned: *.sh
# files whose `set` line enables pipefail, plus `# >>> name`…`# <<< name`
# marker-fenced snippets in TOML/MD (they run under the extracting suite's
# shell options). Comment lines are skipped — the shape is quoted in prose.
# No exception list: an empty-payload probe is still written `< /dev/null`.
# Exit: 0 clean, 1 findings as `<file>:<line>: <message>`.

set -uo pipefail

SETS_PIPEFAIL='^[[:space:]]*set[[:space:]]+[^#]*pipefail'
# Assembled from pieces so this file does not contain the shape it bans.
# `(^|[^|])` keeps `||` out: `a || grep -q b` has no pipe feeding grep.
QUIET_PIPE='(^|[^|])\|[[:space:]]*'"grep"'([[:space:]]+[^|]*)?[[:space:]]+(-[A-Za-z]*q[A-Za-z]*|--quiet|--silent)([[:space:]]|$)'
FIX="fix: grep -q PAT <<< \"\$VAR\" | grep -q PAT < <(cmd) | grep -q PAT < /dev/null (learned rule: pipefail-grep-q)"

found=0

is_comment() { # whole-line comments only; `cmd  # note` is code
    case "$(printf '%s' "$1" | tr -d '[:space:]')" in '#'*) return 0 ;; esac
    return 1
}

for f in "$@"; do
    [ -f "$f" ] || continue
    case "$f" in */lint-learned.d/* | */lint-learned.sh | */base-snapshots/*) continue ;; esac
    case "$f" in
        *.sh)
            grep -qE "$SETS_PIPEFAIL" "$f" 2>/dev/null || continue
            while IFS= read -r hit; do
                no="${hit%%:*}"; body="${hit#*:}"
                is_comment "$body" && continue
                echo "$f:$no: pipeline feeds \`grep -q\` under \`set -o pipefail\` — a successful match can be reported as a failure; $FIX"
                found=1
            done < <(grep -nE "$QUIET_PIPE" "$f" 2>/dev/null)
            ;;
        *.toml | *.md)
            # Marker-fenced snippets are lifted verbatim by a test and run
            # under that test's shell options, so the defect travels with them.
            block="$(awk '/#[[:space:]]*>>>[[:space:]]/{inb=1} inb{print FNR": "$0} /#[[:space:]]*<<<[[:space:]]/{inb=0}' "$f" 2>/dev/null)"
            [ -n "$block" ] || continue
            while IFS= read -r line; do
                no="${line%%: *}"; body="${line#*: }"
                is_comment "$body" && continue
                case "$body" in *[!A-Za-z0-9]grep* | grep*) ;; *) continue ;; esac
                if grep -qE "$QUIET_PIPE" <<< "$body" 2>/dev/null; then
                    echo "$f:$no: extracted snippet pipes into \`grep -q\` and inherits the extracting suite's pipefail; $FIX"
                    found=1
                fi
            done < <(printf '%s\n' "$block")
            ;;
    esac
done

[ "$found" -eq 0 ]
