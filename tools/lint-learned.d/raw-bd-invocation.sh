#!/usr/bin/env bash
# raw-bd-invocation.sh — hardened learned rule: a shell script reaches the bead
# store through `gc bd`, never by running `bd` itself.
#
# The two clients do not resolve the same store. `bd` takes its store and its
# Dolt connection from the ambient environment, so a stale GC_DOLT_PORT in a
# long-lived shell answers from a store nobody asked about or trips the circuit
# breaker — and a caller that reads an unreadable probe as empty renders either
# one as a clean pass. `gc bd` resolves the store from the city's own
# configuration and carries the wiring that makes a write honest: it forces
# BD_EXPORT_AUTO=false, exits 4 when bd falls back to on-disk auto-import mode
# rather than reporting a write that never persisted, and replaces bd's
# `bd dolt start` advice, which would start a second unmanaged Dolt server on
# the managed server's own data directory.
#
# Selecting a store is not a reason to reach for `bd`: `gc bd --db <path>` takes
# the same path and reaches every store, the city's own included, which the
# `--rig` form cannot name.
#
# Scanned: *.sh, command position only. `gc bd` is masked first in every
# spelling, including gc invoked by path (`exec "$BIN/gc" bd`), and quoted
# spans are blanked before matching — so the shape stated in a message or a
# usage string is not a finding, and neither is a function whose name merely
# begins with bd.
#
# Waiver: `# raw-bd: <reason>` trailing the invocation, or standing alone on
# the line above it, for a call site a documented gc limitation shuts out —
# `gc bd` loads the full city config, so it dies wherever that config is cold
# or unloadable, which is the minimal condition-exec env. The reason travels
# with the line, so a later call site in the same file inherits nothing.
#
# Exit: 0 clean, 1 findings as `<file>:<line>: <message>`.

set -uo pipefail

WAIVER='#[[:space:]]*raw-bd:[[:space:]]*[^[:space:]]'
WAIVER_LINE='^[[:space:]]*'"$WAIVER"
# Command position, in two shapes: after a separator, and after a word that
# takes a command as its argument. The wrapper shape is separate because a
# wrapper is often itself the first word of a substitution — `$(run_bounded bd`
# has no whitespace in front of it.
CMD_SEP='(^|[;&|(){}]|\$\(|`)[[:space:]]*bd([[:space:]]|;|$)'
CMD_WRAP='(^|[^[:alnum:]_./-])(then|do|else|elif|run_bounded|command|exec|env|nohup|xargs|time)[[:space:]]+bd([[:space:]]|;|$)'
# Every spelling of the correct form, rewritten to a token that is not `bd`:
# bare `gc bd`, and gc reached by path or variable — `$BIN/gc`, `$GC`, `${GC}`
# — whose closing brace and quote sit between the two words. Applied to the
# whole file in one pass, before quoting is blanked: blanking "$BIN/gc" first
# would leave a bare `exec bd`.
MASK_GC_BD='s#(^|[^[:alnum:]_-])([^[:space:]]*[Gg][Cc])(["'"'"'}]*)[[:space:]]+bd([[:space:]]|;|$)#\1\2\3 gcbd\4#g'
FIX="fix: gc bd (keep --db <path> to select a store) (learned rule: raw-bd-invocation)"

# strip_quoted <line> — blanks single- and double-quoted spans so prose inside
# a string cannot read as a command. Backslash escapes are consumed with the
# character they protect. Backticks are left alone: outside a quoted span a
# backtick opens command substitution, and inside one it went with the span.
strip_quoted() {
    local s="$1" out="" q="" ch i n=${#1}
    for (( i = 0; i < n; i++ )); do
        ch="${s:i:1}"
        if [ "$ch" = "\\" ]; then i=$((i + 1)); [ -n "$q" ] || out+="  "; continue; fi
        if [ -n "$q" ]; then
            [ "$ch" = "$q" ] && { q=""; out+=" "; continue; }
            out+=" "; continue
        fi
        case "$ch" in
            "'" | '"') q="$ch"; out+=" "; continue ;;
        esac
        out+="$ch"
    done
    printf '%s' "$out"
}

found=0

for f in "$@"; do
    [ -f "$f" ] || continue
    case "$f" in
        */lint-learned.d/* | */lint-learned.sh | */base-snapshots/*) continue ;;
        *.sh) ;;
        *) continue ;;
    esac
    # One cheap read decides whether the file is worth a line scan at all.
    grep -Eq '(^|[^[:alnum:]_./-])bd[[:space:]]' "$f" 2>/dev/null || continue

    masked=()
    while IFS= read -r m || [ -n "$m" ]; do masked+=("$m"); done < <(sed -E "$MASK_GC_BD" "$f" 2>/dev/null)
    # The file reached here because it mentions bd, so the masked copy cannot
    # be empty. If it is, the mask did not run, and every correct `gc bd` in
    # the file would read as a raw one. Exit 2: the runner reports a detector
    # error distinctly and still fails the run.
    if [ "${#masked[@]}" -eq 0 ]; then
        echo "raw-bd-invocation: could not mask \`gc bd\` in $f — detector cannot scan it" >&2
        exit 2
    fi

    lineno=0 prev=""
    while IFS= read -r line || [ -n "$line" ]; do
        lineno=$((lineno + 1))
        prevline="$prev"; prev="$line"
        case "$line" in *bd[[:space:]]*) ;; *) continue ;; esac

        # Whole-line comments only; `cmd  # note` is code.
        trimmed="${line#"${line%%[![:space:]]*}"}"
        case "$trimmed" in '#'*) continue ;; esac

        code="$(strip_quoted "${masked[lineno - 1]-$line}")"
        [[ "$code" =~ $CMD_SEP ]] || [[ "$code" =~ $CMD_WRAP ]] || continue

        # The waiver states why this line cannot use gc bd. A trailing marker
        # waives its own line; a marker standing alone waives the line below
        # it. A waived invocation is code, so it never waives its successor.
        if grep -Eq "$WAIVER" <<< "$line" || grep -Eq "$WAIVER_LINE" <<< "$prevline"; then
            continue
        fi

        echo "$f:$lineno: runs \`bd\` directly — it resolves its store from the ambient environment, so a stale one answers from the wrong store or fails in a way a caller can read as a clean pass; $FIX"
        found=1
    done < "$f"
done

[ "$found" -eq 0 ]
