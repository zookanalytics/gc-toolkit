#!/usr/bin/env bash
# measure-context-budget.sh — re-measure the per-agent always-on prompt budget.
#
# Companion to specs/tk-23wdf/context-budget-ledger.md (tk-23wdf, epic tk-yhwfv).
# Run it after any change to template-fragments/, pack.toml, or city.toml to see
# what the change actually cost or saved.
#
# WHY /proc: there is no `gc agent render` and no `gc pack show` (`gc pack` has
# only fetch/list/registry/release). The rendered prompt reaches the provider as
# a POSITIONAL argv element — not --append-system-prompt — so the only way to
# read what an agent was really given is its own /proc entry.
#
# SPLIT ON NUL ONLY. argv is NUL-delimited and the prompt itself contains
# thousands of newlines; `tr '\0' '\n'` shreds it into unusable lines. The
# largest NUL-delimited element is the prompt.
#
# LIVENESS: this measures agents that are RUNNING. A role with no live session
# (keeper asleep, boot retired, *-thread operator-spawned) produces no row —
# absence here means "not spawned", never "costs nothing". Wait for a spawn
# rather than substituting an estimate for a headline number.
#
# Usage:
#   ./measure-context-budget.sh                  # table of live agents
#   ./measure-context-budget.sh -o /tmp/prompts  # also save each rendered prompt
set -uo pipefail

OUTDIR=""
while [ $# -gt 0 ]; do
    case "$1" in
        # CHECK THE VALUE BEFORE SHIFTING. `shift 2` with only one argument left
        # fails and shifts NOTHING, and there is no `set -e` here to stop on it —
        # so `--outdir` with no value would leave $# unchanged and spin this loop
        # forever. Fail with usage instead of hanging.
        -o|--outdir)
            if [ $# -lt 2 ] || [ -z "$2" ]; then
                echo "measure-context-budget: $1 requires a directory argument" >&2
                echo "usage: measure-context-budget.sh [-o|--outdir <dir>]" >&2
                exit 2
            fi
            OUTDIR="$2"; shift 2 ;;
        -h|--help) sed -n '2,26p' "$0"; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done
[ -n "$OUTDIR" ] && mkdir -p "$OUTDIR"

command -v python3 >/dev/null 2>&1 || {
    echo "measure-context-budget: python3 is required (NUL-safe argv split)" >&2
    exit 1
}

# Minimum cmdline size that distinguishes an agent from a helper process.
MIN_BYTES=5000

printf '%-34s %-34s %9s %9s %-7s\n' TEMPLATE ALIAS CMDLINE PROMPT PROVIDER
printf '%-34s %-34s %9s %9s %-7s\n' \
    '---------------------------------' '---------------------------------' \
    '--------' '--------' '------'

found=0
for pid in $(pgrep -f 'claude|codex|gemini' 2>/dev/null); do
    [ -r "/proc/$pid/cmdline" ] || continue
    total=$(wc -c < "/proc/$pid/cmdline" 2>/dev/null) || continue
    [ "${total:-0}" -gt "$MIN_BYTES" ] || continue

    env_txt=$(tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null)
    alias=$(printf '%s\n' "$env_txt" | sed -n 's/^GC_ALIAS=//p' | head -1)
    tmpl=$(printf '%s\n' "$env_txt" | sed -n 's/^GC_TEMPLATE=//p' | head -1)
    # Not a gc-managed agent (a stray editor session, a nested CLI): skip rather
    # than report it as an agent with an empty template.
    [ -n "$tmpl" ] || continue

    slug=$(printf '%s' "${alias:-pid$pid}" | tr '/' '_')
    dest="${OUTDIR:+$OUTDIR/$slug.prompt.txt}"

    prompt_bytes=$(python3 -c '
import sys
pid, dest = sys.argv[1], (sys.argv[2] if len(sys.argv) > 2 else "")
try:
    args = open("/proc/%s/cmdline" % pid, "rb").read().split(b"\0")
except OSError:
    print(0); sys.exit(0)
best = max(args, key=len) if args else b""
if dest:
    open(dest, "wb").write(best)
print(len(best))
' "$pid" "$dest" 2>/dev/null) || prompt_bytes=0

    provider=$(head -c 200 "/proc/$pid/cmdline" 2>/dev/null | tr '\0' '\n' | head -1)
    provider=$(basename "${provider:-?}")

    printf '%-34s %-34s %9s %9s %-7s\n' \
        "${tmpl:0:34}" "${alias:0:34}" "$total" "${prompt_bytes:-0}" "$provider"
    found=$((found + 1))
done

if [ "$found" -eq 0 ]; then
    echo >&2
    echo "measure-context-budget: no live gc agents found." >&2
    echo "  Nothing was measured — this is NOT a zero-cost result." >&2
    echo "  Start the city (or wait for a pool spawn) and re-run." >&2
    exit 1
fi

cat <<'NOTE'

To attribute a captured prompt to its sources, segment it by anchor: take the
first *heading* of each fragment define as a boundary, sort boundaries by byte
offset, and let each span run to the next. The spans must sum to the file size —
that sum is the check that nothing is unattributed.

Two traps (both cost real time; see the ledger's Method section):
  * Anchor on the first HEADING, not the first literal line. `thread-role` and
    `operator-next-step-trailing` both open with `---`, which matches early and
    over-captures by ~15 KB.
  * Rendered != source. Template variables expand — `propulsion-polecat` is
    1,319 source bytes but 2,477 rendered, because {{ .AssignedInProgressQuery }}
    substitutes a ~1.1 KB shell one-liner. Always measure the rendered side.

Base-pack fragments live in the gascity-packs git cache at the pin recorded in
pack.toml [imports.gastown] — NOT in /home/zook/.gc/system/packs/gastown, which
is a stale materialization. Locate the cache with:

    PIN=$(sed -n 's/^version = "sha:\(.*\)"/\1/p' pack.toml | head -1)
    for d in "$HOME"/.gc/cache/repos/*/; do
        git -C "$d" cat-file -t "$PIN" >/dev/null 2>&1 && echo "$d"
    done
    git -C "$REPO" show "${PIN}:gastown/agents/polecat/prompt.template.md"

Brace ${PIN}. In zsh, $PIN:gastown/... parses ":ga" as a history modifier and
silently mangles the path.
NOTE
