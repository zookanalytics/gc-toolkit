#!/usr/bin/env bash
# Pack doctor check: the polecat fragment lists do not drift apart.
#
# THE SHAPE. gc-toolkit does not mirror gastown's polecat prompt. It reuses the
# base template verbatim and expresses every local divergence as a named
# fragment appended to it, which means the fragment LIST is the whole of this
# pack's polecat doctrine. That list is written twice:
#
#   * pack.toml, `[[patches.agent]] name = "polecat"` -> inject_fragments_append,
#     which patches the IMPORTED gastown polecat pool;
#   * agents/<pool>/agent.toml -> inject_fragments, for each NATIVE pool that
#     shares the base prompt by reference (`prompt_template =
#     "gastown//agents/polecat/prompt.template.md"`) instead of carrying a copy.
#     agents/polecat-codex/agent.toml is that pool today.
#
# There is no propagation between them. agents/polecat-codex/agent.toml says so
# in its own header — "must be kept in sync by hand" — and a rule that depends
# on somebody remembering is the failure class this check exists to end.
#
# WHY IT MATTERS AND WHY IT IS INVISIBLE. A pool whose list is missing a
# fragment is not broken in any way an operator can see. It resolves its
# prompt, primes with exit 0, claims work, and executes the UNPATCHED base
# doctrine — confidently and wrongly — for exactly the behaviour the missing
# fragment was written to correct. Nothing downstream can notice guidance it
# never received.
#
# tk-t41dq is the live case. Base ships the impl done sequence twice (the
# approval-fallacy "### The Done Sequence" fragment and the prompt's own
# "## FINAL REMINDER"), and both write the handoff note with `--notes`, which
# REPLACES rather than appends: every handoff silently destroyed whatever the
# bead already carried, typically the mayor's dispatch note, at the moment the
# bead was passed to the refinery. The correction ships as the
# `polecat-append-notes` fragment. Wired into pack.toml but not into
# polecat-codex, codex polecats would have gone on destroying notes while the
# bug read as fixed.
#
# WHAT IS ASSERTED. Set equality, not order: order changes reading sequence,
# not doctrine. A native pool that shares the base prompt and declares NO
# fragments at all is the same finding as one missing a single name — it is the
# maximal drift, not an opt-out.
#
# WHAT IS NOT ASSERTED. That the named fragments exist or render;
# check-base-artifact-collision owns define-name shadowing and
# check-agent-prompt-integrity owns template resolution.
#
# Exit codes: 0=OK, 1=Warning, 2=Error
# stdout: first line=message, rest=details

set -u

dir="${GC_PACK_DIR:-.}"

# The base prompt whose reuse defines this class of pool. An agent carrying its
# own colocated prompt file is NOT in the class (it has no base doctrine to
# patch), which is why agents/_polecat-gemini — a whole-file prompt, and
# disabled by its `_` prefix besides — is correctly out of scope here.
BASE_PROMPT_SUBPATH="agents/polecat/prompt.template.md"

if [ ! -f "$dir/pack.toml" ]; then
    echo "OK: no pack.toml — nothing to compare"
    exit 0
fi
if [ ! -d "$dir/agents" ]; then
    echo "OK: no agents/ directory — no native pool can share the base polecat prompt"
    exit 0
fi

# Strip TOML comments quote-awarely, then emit every quoted string found in the
# array that starts at `<key> =` and ends at the first `]`. Comment stripping is
# load-bearing, not cosmetic: the pack.toml list carries an explanatory comment
# INSIDE the array that itself quotes prompt section headings, and a naive
# quote-scrape would read those headings as fragment names.
array_values() { # $1 = key; TOML text on stdin
    awk -v key="$1" '
        function strip_comment(s,   i, c, inq, out) {
            inq = 0; out = ""
            for (i = 1; i <= length(s); i++) {
                c = substr(s, i, 1)
                if (c == "\"") { inq = !inq }
                else if (c == "#" && !inq) { break }
                out = out c
            }
            return out
        }
        {
            line = strip_comment($0)
            if (!cap && line ~ ("^[[:space:]]*" key "[[:space:]]*=")) { cap = 1 }
            if (cap) {
                buf = buf " " line
                if (index(line, "]") > 0) { print buf; exit }
            }
        }
    ' | grep -o '"[^"]*"' | tr -d '"' | sort -u
}

# The lines of the [[patches.agent]] block whose name is "polecat". Scoped
# rather than grepped globally: several patch blocks in pack.toml carry an
# inject_fragments_append, and the wrong one would compare cleanly against
# nothing.
polecat_patch_block() {
    awk '
        function flush() { if (want) { printf "%s", buf; found = 1; exit } inb = 0; buf = ""; want = 0 }
        /^[[:space:]]*\[\[patches\.agent\]\][[:space:]]*$/ { flush(); inb = 1; buf = ""; want = 0; next }
        /^[[:space:]]*\[/ { flush(); inb = 0; buf = ""; want = 0; next }
        inb {
            buf = buf $0 "\n"
            if ($0 ~ /^[[:space:]]*name[[:space:]]*=[[:space:]]*"polecat"[[:space:]]*$/) want = 1
        }
        END { flush() }
    ' "$1"
}

patch_block="$(polecat_patch_block "$dir/pack.toml")"
if [ -z "$patch_block" ]; then
    echo "No [[patches.agent]] block for \"polecat\" in pack.toml — fragment sync is UNVERIFIED"
    echo "This check compares that block's inject_fragments_append against each native pool that shares the base polecat prompt. With no block to compare, a native pool's list could be anything and nothing would say so."
    echo "If the polecat patch was deliberately removed, remove this check with it."
    exit 1
fi

patch_frags="$(printf '%s' "$patch_block" | array_values inject_fragments_append)"
if [ -z "$patch_frags" ]; then
    echo "The polecat patch declares no inject_fragments_append — fragment sync is UNVERIFIED"
    echo "Either the key is absent from the [[patches.agent]] name = \"polecat\" block, or it could not be parsed out of it."
    echo "An empty expected set would make every native pool compare clean, which is the false-green this check exists to prevent."
    exit 1
fi

mismatched=()
checked=0
shared=()

for agent_toml in "$dir"/agents/*/agent.toml; do
    [ -f "$agent_toml" ] || continue
    agent_dir="$(basename "$(dirname "$agent_toml")")"
    # Only pools that REUSE the base prompt are in the class.
    grep -q "prompt_template[[:space:]]*=.*$BASE_PROMPT_SUBPATH" "$agent_toml" || continue
    shared+=("$agent_dir")
    checked=$((checked + 1))
    agent_frags="$(array_values inject_fragments < "$agent_toml")"
    missing="$(comm -23 <(printf '%s\n' "$patch_frags") <(printf '%s\n' "$agent_frags") | tr '\n' ' ')"
    extra="$(comm -13 <(printf '%s\n' "$patch_frags") <(printf '%s\n' "$agent_frags") | tr '\n' ' ')"
    missing="${missing% }"; extra="${extra% }"
    if [ -n "$missing" ] || [ -n "$extra" ]; then
        detail="agents/$agent_dir/agent.toml:"
        [ -n "$missing" ] && detail="$detail missing [$missing]"
        [ -n "$extra" ] && detail="$detail extra [$extra]"
        mismatched+=("$detail")
    fi
done

if [ "${#mismatched[@]}" -gt 0 ]; then
    echo "${#mismatched[@]} native polecat pool(s) inject a different fragment set than the pack.toml polecat patch"
    printf '%s\n' "${mismatched[@]}"
    echo "Expected (pack.toml [[patches.agent]] name = \"polecat\" -> inject_fragments_append): $(printf '%s' "$patch_frags" | tr '\n' ' ')"
    echo "A pool missing a fragment primes fine and runs the UNPATCHED base doctrine for whatever that fragment corrects — no error, no stderr, just the old behaviour. Copy the list across; there is no propagation between the two files."
    exit 2
fi

if [ "$checked" -eq 0 ]; then
    echo "OK: no native agent shares gastown's polecat prompt by reference — nothing to keep in sync"
    exit 0
fi

echo "OK: all $checked native polecat pool(s) (${shared[*]}) inject the same $(printf '%s\n' "$patch_frags" | grep -c .) fragment(s) as the pack.toml polecat patch"
echo "Fragments: $(printf '%s' "$patch_frags" | tr '\n' ' ')"
