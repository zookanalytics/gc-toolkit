#!/usr/bin/env bash
# doctor/check-seed-audit-current — generated/seed-audit/ matches its inputs.
# The audit is the rendered standing prompt of every agent and the compiled
# recipe of every formula, committed for review; SOURCES.txt records a
# sha256 per input file, and this check recomputes them from the pack tree —
# cheap by construction (hashes, no re-render; the authoritative check is
# `assets/scripts/render-seed-audit.sh --check`). A drifting input is an
# error: the committed audit describes a seed no agent receives. An ABSENT
# audit is a WARNING, not an error — a fresh clone before the first render
# is expected, and it re-renders on first install (--install-hook).
# A gc-version-only drift and an unwired pre-commit hook are warnings too.
# Read-only. Exit 0=OK 1=Warning 2=Error. stdout: message, "  - detail" lines.

set -u

dir="${GC_PACK_DIR:-.}"
audit="$dir/generated/seed-audit"
index="$audit/INDEX.md"
sources="$audit/SOURCES.txt"
script="$dir/assets/scripts/render-seed-audit.sh"

warnings=()
detail() { local v; for v in "$@"; do printf '  - %s\n' "$v"; done; }

# ABSENT and PRESENT-BUT-NOT-EXECUTABLE are different facts: a renderer that
# ships is one this pack expects to keep the audit current, whatever its mode
# bit says (every read below goes through bash so the bit cannot decide).
if [ ! -e "$script" ]; then
    echo "OK: no render-seed-audit.sh in this pack — nothing to keep current"
    exit 0
fi
[ -x "$script" ] || warnings+=("assets/scripts/render-seed-audit.sh is NOT executable — the staleness read still works (it runs through bash), but the documented operator command and --install-hook invoke it directly and will fail; chmod +x it")

if [ ! -f "$index" ]; then
    echo "seed audit ABSENT — generated/seed-audit/INDEX.md does not exist (warning, not error)"
    detail "A fresh clone ships without the rendered audit and regenerates it on first install; until then nothing shows what any agent receives and nothing detects a drifting fragment."
    detail "Render it: assets/scripts/render-seed-audit.sh && git add generated/seed-audit (wire upkeep with --install-hook)."
    detail ${warnings[@]+"${warnings[@]}"}
    exit 1
fi

recorded_gcver=$(sed -n 's/^- `gc` version: `\(.*\)`$/\1/p' "$index" | head -1)

if [ ! -f "$sources" ]; then
    echo "seed audit records no input manifest — staleness is UNVERIFIABLE"
    detail "generated/seed-audit/SOURCES.txt does not exist beside INDEX.md; the tree was hand-edited or written by an older renderer, so the artifact cannot be checked at all."
    detail "Fix: assets/scripts/render-seed-audit.sh && git add generated/seed-audit"
    exit 2
fi

# --print-sources hashes files and shells out to nothing (works with no gc).
actual_sources=$(bash "$script" --root "$dir" --print-sources 2>/dev/null)
if [ -z "$actual_sources" ]; then
    echo "could not recompute the seed-audit input manifest — staleness UNVERIFIED"
    detail "bash $script --print-sources produced no output; the one cheap staleness signal is dark, which is not a benign skip."
    detail ${warnings[@]+"${warnings[@]}"}
    exit 1
fi

if [ "$actual_sources" != "$(cat "$sources")" ]; then
    echo "seed audit STALE — a prompt input moved without the artifact moving"
    # The manifest is two lines per input, path then hash; folding it back to
    # path<TAB>hash is what a set comparison can be taken over. A changed input
    # contributes its recorded pair and its actual one, so the paths are
    # deduplicated; an added or removed input contributes one. `comm -3` indents
    # its second column with a TAB, which is also the pair separator.
    pairs() { grep -v '^#' | paste - - | LC_ALL=C sort; }
    drifted=$(comm -3 <(pairs < "$sources") <(printf '%s\n' "$actual_sources" | pairs) \
        | sed 's/^\t//' | cut -f1 | LC_ALL=C sort -u | head -10)
    if [ -n "$drifted" ]; then
        detail "inputs that moved since generated/seed-audit/ was generated:"
        while IFS= read -r f; do detail "  $f"; done <<< "$drifted"
    else
        # Reachable only by editing the manifest outside its records, since a
        # renderer that writes them differently is itself a hashed input and
        # would appear in the list above. Saying so beats an empty heading.
        detail "No input accounts for it: SOURCES.txt differs from a fresh manifest outside its per-input records, so it was hand-edited or written by another tool."
    fi
    detail "The committed audit describes a seed no agent receives — and every file in it still reads as a valid prompt, which is why this is a check and not a review."
    detail "Fix: assets/scripts/render-seed-audit.sh && git add generated/seed-audit"
    exit 2
fi

# Version drift is a warning, not an error: prompt composition lives in the gc
# binary, and a host upgrade moves the artifact with no commit here.
if command -v gc >/dev/null 2>&1; then
    actual_gcver=$(gc version 2>/dev/null | head -1)
    if [ -n "$actual_gcver" ] && [ -n "$recorded_gcver" ] && [ "$actual_gcver" != "$recorded_gcver" ]; then
        warnings+=("gc version drift: artifact rendered with \"$recorded_gcver\", host runs \"$actual_gcver\" — the rendered text may have moved with no change in this repo; re-render: assets/scripts/render-seed-audit.sh")
    fi
fi

# The pre-commit hook is what keeps the artifact current between doctor runs.
if command -v git >/dev/null 2>&1 && git -C "$dir" rev-parse --git-dir >/dev/null 2>&1; then
    hookspath=$(git -C "$dir" config --get core.hooksPath 2>/dev/null)
    if [ "$hookspath" != "assets/hooks" ]; then
        shown="${hookspath:+\"$hookspath\"}"
        warnings+=("core.hooksPath is ${shown:-unset}, not assets/hooks — nothing regenerates the audit on commit, so it goes stale silently between doctor runs; wire it: assets/scripts/render-seed-audit.sh --install-hook (deliberate on rigs that disable hooks — there, this check IS the mechanism)")
    fi
fi

n_agents=$(find "$audit/agents" -name '*.md' -type f 2>/dev/null | wc -l | tr -d ' ')
n_formulas=$(find "$audit/formulas" -name '*.md' -type f 2>/dev/null | wc -l | tr -d ' ')

if [ "${#warnings[@]}" -ne 0 ]; then
    echo "seed audit content is current ($n_agents agents, $n_formulas formulas) but its upkeep is not fully wired"
    detail "${warnings[@]}"
    exit 1
fi
n_inputs=$(printf '%s\n' "$actual_sources" | grep -v '^#' | paste - - | wc -l | tr -d ' ')
echo "OK: seed audit current — $n_agents agent prompt(s), $n_formulas formula recipe(s), $n_inputs input(s) hashed, hook wired"
exit 0
