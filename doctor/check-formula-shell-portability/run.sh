#!/usr/bin/env bash
# Pack doctor check: no formula shell block iterates an UNQUOTED expansion.
#
# THE DEFECT.
#
#     IDS=$(jq -r '...' "$FILE")
#     for C in $IDS; do ... gc bd show "$C" ... done
#
# Formula shell blocks are authored as POSIX sh, but the shell that runs them is
# whatever the agent pasting them happens to have. On this city that is zsh, and
# zsh does NOT word-split unquoted parameter expansions or command
# substitutions. The list arrives as ONE word: the body runs exactly once with
# every id joined into a single token, the per-id command fails on the nonsense
# id, and the step records an honest-looking failure having silently skipped
# every real element.
#
# Measured on bead sl-e7l4 with a byte-identical re-run as the control
# (observation sl-vxqu), on the `for C in $INPUT_CONVOYS` loop this check's
# first fix removed:
#
#   under zsh:   WARN: convoy read FAILED for sl-fwy9\nsl-itxi\nsl-ycx3
#                CONVOY_LIVENESS=unverified   WORKED=[]
#   under bash:  CONVOY_LIVENESS=verified     WORKED=[sl-5us4, sl-ew4w, sl-merz]
#
# WHY A CHECK AND NOT A CONVENTION. The ambient shell is invisible at the moment
# an agent pastes a block, so "run formula blocks under bash" is advice an agent
# fully intending to follow it still trips — nothing in the block, the formula
# or the prompt says which shell arrived. It is also not self-announcing: the
# failure direction is usually fail-SAFE for the step's output (unresolved ids
# get reported, never hidden), so the pass looks clean while doing none of the
# work. mol-feedback-distiller diagnosed this exact trap in a comment and worked
# around it locally in one loop; the lesson never generalized, and five more
# instances were live in shipped formulas when this check was written. That is
# the argument for a lint rather than more prose.
#
# WHAT IS ASSERTED. Every `for NAME in <list>` inside a fenced shell block of a
# formula TOML (`*/formulas/*.toml`), where <list> contains an expansion that is
# not quoted. Fenced blocks only, and never comment lines: this pack quotes the
# banned shape in prose constantly — including in this header — and a raw grep
# would scope the check by how well a file is documented.
#
# WHAT IS NOT ASSERTED.
#   * Quoted lists — `for cand in "${GC_RIG_ROOT:-}" "$(git rev-parse ...)"`.
#     Each element is its own word in EVERY shell; this is the pack's dominant
#     for-loop shape (~18 live instances) and is correct as written.
#   * Literal and glob lists — `for S in pull_request pre_open_gate`,
#     `for d in "$BACKUP_ROOT"/*/`. Both shells agree.
#   * `${=VAR}`, zsh's explicit split operator. Where a split is genuinely
#     wanted, saying so is the fix, so the check must not punish it.
#   * Anything outside a formula TOML. Agent prompt templates, startup
#     fragments and docs runbooks carry the same hazard on the same mechanism;
#     they are NOT covered here (see tk-1c9vf's follow-up, and the site list in
#     its notes) because widening the scope and rewriting those loops is a
#     separate, larger change than the one this check was filed for.
#
# THE FIX, in order of preference:
#   * a captured list  ->  write it to a file, then
#                          `while IFS= read -r X; do ... done < "$FILE"`.
#                          Redirect from a FILE, not a pipe: `cmd | while read`
#                          puts the loop in a SUBSHELL, so a fail-safe `exit`
#                          leaves only the subshell and every variable the loop
#                          set (a liveness verdict, an accumulator) is lost on
#                          the way out.
#   * a space-separated list  ->  split it explicitly first:
#                          `printf '%s\n' "$V" | tr ' \t' '\n\n' | awk NF > "$F"`
#   * a split genuinely wanted  ->  `for X in ${=VAR}` and mean it.
#
# There is deliberately NO exception list, following doctor/check-pipefail-grep-q:
# a rule with no exceptions is a better guard than one whose exceptions have to
# be re-litigated at every review. The two sites that carried an explicit
# `# shellcheck disable=SC2086` "intentional word-splitting" comment were the
# two most clearly BROKEN — the intent was real and zsh silently refused it.
#
# Exit codes: 0=OK, 1=Warning, 2=Error
# stdout: first line=message, rest=details

set -u

dir="${GC_PACK_DIR:-.}"

# Vendored upstream copies, kept for collision detection and never executed.
is_excluded() {
    case "$1" in
        */base-snapshots/*) return 0 ;;
        *) return 1 ;;
    esac
}

# Extraction and classification live in awk so that quote-stripping is done by
# something that can actually see a quote. The program is heredoc'd rather than
# inlined so its own single quotes survive.
SCAN_AWK=$(cat <<'AWKEOF'
# Emit "LINENO:TEXT" for each unquoted-expansion for-loop in a fenced shell
# block. Fences: ```bash, ```sh, ```shell, and bare ``` (formula TOMLs use the
# bare form for shell too). ```json and friends are skipped.
function is_shell_fence(l,   lang) {
    lang = l
    sub(/^[[:space:]]*```[[:space:]]*/, "", lang)
    sub(/[[:space:]].*$/, "", lang)
    return (lang == "" || lang == "bash" || lang == "sh" || lang == "shell")
}

# True when s still holds an expansion after every QUOTED span is removed.
function unquoted_expansion(s,   t) {
    t = s
    gsub(/\$\{=[^}]*\}/, " ", t)   # ${=VAR}: zsh's explicit split — sanctioned
    gsub(/'[^']*'/, " ", t)        # single-quoted spans
    gsub(/"[^"]*"/, " ", t)        # double-quoted spans
    sub(/#.*$/, "", t)             # trailing comment (quotes are gone by now)
    return (t ~ /\$/ || t ~ /`/)
}

# The word list of a for-statement: text after `in`, up to the `;` or the `do`
# that ends it. Without this truncation the loop BODY would be scanned too, and
# `for f in *.sh; do echo $f; done` — correct in every shell — would be flagged
# for its body.
function word_list(s,   rest, p) {
    rest = s
    if (!match(rest, /(^|[;&|(){}]|\$\(|[[:space:]](do|then|else))[[:space:]]*for[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]+in[[:space:]]/)) return ""
    rest = substr(rest, RSTART + RLENGTH)
    p = index(rest, ";")
    if (p > 0) rest = substr(rest, 1, p - 1)
    if (match(rest, /[[:space:]]do([[:space:]]|$)/)) rest = substr(rest, 1, RSTART - 1)
    return rest
}

/^[[:space:]]*```/ {
    if (inb) { inb = 0 } else { inb = is_shell_fence($0) }
    next
}
!inb { next }

{
    # Join backslash continuations so a list spread over several lines is
    # judged whole. TOML basic strings spell the continuation `\\`.
    if (pending != "") {
        text = pending " " $0
    } else {
        text = $0
        start = FNR
    }
    if (text ~ /\\+[[:space:]]*$/) {
        sub(/\\+[[:space:]]*$/, "", text)
        pending = text
        next
    }
    pending = ""

    stripped = text
    sub(/^[[:space:]]+/, "", stripped)
    if (stripped ~ /^#/) next          # a comment, not code

    list = word_list(text)
    if (list == "") next
    if (unquoted_expansion(list)) print start ":" stripped
}
AWKEOF
)

findings=()
scanned=0

while IFS= read -r f; do
    is_excluded "$f" && continue
    scanned=$((scanned + 1))
    while IFS= read -r hit; do
        [ -n "$hit" ] || continue
        findings+=("$f:$hit")
    done < <(awk "$SCAN_AWK" "$f" 2>/dev/null)
done < <(find "$dir" -type f -path '*/formulas/*.toml' 2>/dev/null | sort)

if [ "${#findings[@]}" -gt 0 ]; then
    echo "${#findings[@]} formula shell block(s) iterate an UNQUOTED expansion — zsh does not word-split, so the body runs ONCE on the whole joined list"
    printf '%s\n' "${findings[@]}"
    echo "zsh (this city's default agent shell) performs no word splitting on unquoted \$VAR or \$(cmd). Every element arrives as a single token: the per-element command fails on the joined string and the step reports an honest-looking failure having silently skipped every real element. The direction is usually fail-safe for the step's OUTPUT, so the pass looks clean while doing none of the work."
    printf '%s\n' "Fix: capture the list to a file and \`while IFS= read -r X; do ... done < \"\$FILE\"\` — a FILE, not a pipe, so a fail-safe \`exit\` leaves the step rather than a subshell and the loop's variables survive it. Split a space-separated list explicitly first (\`tr ' \\t' '\\n\\n' | awk NF\`). Where a split is genuinely intended, write \`\${=VAR}\` and say so."
    exit 2
fi

if [ "$scanned" -eq 0 ]; then
    echo "OK: no formula TOML found under $dir — nothing to check"
    exit 0
fi

echo "OK: $scanned formula TOML(s) iterate no unquoted expansion in a shell block"
