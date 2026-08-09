#!/usr/bin/env bash
# Pack doctor check: no agent silently renders the 16-line generic prompt stub.
#
# WHAT ACTUALLY PRODUCES THE STUB. `gc prime` renders the agent's
# prompt_template and, when the render comes back empty, falls through to
# `defaultPrimePrompt` — the 16-line "You are an agent in a Gas City
# workspace. Claim available work and execute it." — and exits 0.
# renderPromptWithMeta returns an empty result whenever the template file
# cannot be READ (gascity cmd/gc/prompt.go: `data, err := fs.ReadFile(...)`
# -> `return PromptRenderResult{}`), and the builtin-worker fallback below it
# is gated on `a.PromptTemplate == ""`, so an agent that DECLARES a template
# pointing at a nonexistent path skips that branch too and lands on the stub.
# It runs with none of its doctrine, and nothing is written to stderr. Only
# `gc prime --strict` turns an unreadable template into an error (the
# readability precondition in cmd/gc/cmd_prime.go is inside `if strictMode`);
# the ordinary spawn path does not.
#
# WHAT DOES NOT PRODUCE IT — the premise this check used to encode (tk-5wdy8).
# It previously warned on any prompt_template written in the cross-pack
# "<pack>//<subpath>" form, on the theory that gascity resolves that form
# against the pack dir and, when the pack is absent, silently degrades to the
# stub. Both halves are wrong. resolvePackQualifiedAgentPaths (gascity
# internal/config/pack_qualified_path.go, called from compose.go) resolves the
# form against the IMPORT CLOSURE — cfg.PackDirs / cfg.RigPackDirs, i.e. the
# content-addressed cache dir — and an unknown OR ambiguous pack name is a
# hard error that fails config load rather than degrading (gascity's own
# TestResolvePackQualifiedAgentPaths_{UnknownPack,AmbiguousPack}). The form is
# safe. What resolution does NOT validate is that the SUBPATH exists inside
# the resolved pack: it is a plain filepath.Join with no existence test. That
# gap — a valid pack name plus a stale subpath — is a route to the stub, and
# it is invisible to any check that reads agent.toml alone.
#
# The other route is a config that does not load at all, which is why this
# check treats an unresolvable config as a finding rather than a skip: `gc
# prime` does not inherit that failure. Verified against a scratch city — an
# unknown pack makes `gc config show` exit 1 naming the pack, while `gc prime`
# on the same city prints the stub and exits 0.
#
# So this check no longer pattern-matches the form. It asks gascity for the
# RESOLVED config and asserts that every agent's prompt_template names a
# readable file, whatever form it was written in. That is city-wide by
# nature: an unreadable prompt is a defect wherever the agent is declared,
# and scoping to this pack's own agents would miss precisely the cross-pack
# references that motivated the check.
#
# Exit codes: 0=OK, 1=Warning, 2=Error
# stdout: first line=message, rest=details

set -u

dir="${GC_PACK_DIR:-.}"
city="${GC_CITY_PATH:-${GC_CITY:-}}"

if [ ! -d "$dir/agents" ]; then
    echo "OK: no agents/ directory — nothing to check"
    exit 0
fi

# Resolution is a runtime property, so the check is a no-op outside a city
# (pack-only checkouts, CI linting a pack in isolation). Reporting a problem
# there would be the same false-positive-by-construction this check was
# rewritten to remove: nothing has been observed to be wrong.
if ! command -v gc >/dev/null 2>&1; then
    echo "OK: gc is not on PATH — prompt resolution is a runtime property, not verifiable here"
    exit 0
fi
if [ -z "$city" ]; then
    echo "OK: no city in scope (GC_CITY_PATH/GC_CITY unset) — prompt resolution not verifiable here"
    exit 0
fi

# stdout only: a warning on stderr would otherwise be parsed as config.
config_out="$(gc --city "$city" config show 2>/dev/null)"
config_rc=$?
if [ "$config_rc" -ne 0 ] || [ -z "$config_out" ]; then
    if [ -z "$config_out" ]; then
        detail="no output"
    else
        detail="output"
    fi
    echo "Could not resolve the city config — agent prompt integrity is UNVERIFIED"
    echo "gc --city $city config show exited $config_rc with $detail"
    echo "This is not a benign skip: gc prime does NOT inherit config show's exit status — on a config that fails to load it emits the 16-line default prompt and returns 0, so every agent primes stubbed while nothing reports an error. Fix the config load first."
    exit 1
fi

# Pull (agent name, resolved prompt_template) out of the resolved TOML. Blocks
# open with [[agent]] and carry flat keys until the next table header.
resolved="$(printf '%s\n' "$config_out" | awk '
    function flush() {
        if (inb == 1 && pt != "") {
            print (name == "" ? "<unnamed>" : name) "\t" pt
        }
    }
    /^\[\[agent\]\]/ { flush(); inb = 1; name = ""; pt = ""; next }
    /^\[/            { flush(); inb = 0; name = ""; pt = ""; next }
    inb == 1 && /^name = "/ {
        if (name == "") { v = $0; sub(/^name = "/, "", v); sub(/"$/, "", v); name = v }
        next
    }
    inb == 1 && /^prompt_template = "/ {
        v = $0; sub(/^prompt_template = "/, "", v); sub(/"$/, "", v); pt = v
        next
    }
    END { flush() }
')"

missing=()
crosspack=()
checked=0

while IFS=$'\t' read -r agent_name template_path; do
    [ -n "${template_path:-}" ] || continue
    # gascity applies no template expansion to this field: the value is used
    # verbatim (promptTemplateSourcePath joins it with the city path when
    # relative), so the readability test below is the whole contract.
    case "$template_path" in
        /*) abs="$template_path" ;;
        *)  abs="$city/$template_path" ;;
    esac
    checked=$((checked + 1))
    if [ -r "$abs" ]; then
        case "$abs" in
            "$city"/*) : ;;
            *) crosspack+=("$agent_name -> $abs") ;;
        esac
    else
        missing+=("$agent_name: prompt_template does not resolve to a readable file -> $abs")
    fi
done <<EOF
$resolved
EOF

if [ "${#missing[@]}" -gt 0 ]; then
    echo "${#missing[@]} agent(s) would render the generic stub — prompt_template does not resolve to a readable file"
    printf '%s\n' "${missing[@]}"
    echo "gc prime falls back to the 16-line default prompt when a template cannot be read, and still exits 0, so such an agent claims real work with none of its doctrine."
    echo "Confirm per agent: gc prime --strict <name> — it fails loudly on exactly this condition."
    exit 2
fi

if [ "$checked" -eq 0 ]; then
    echo "OK: no agent declares a prompt_template — none can render the stub"
    exit 0
fi

echo "OK: all $checked agent prompt_template reference(s) resolve to readable files"
if [ "${#crosspack[@]}" -gt 0 ]; then
    # Deduped: pool agents are expanded per rig, so the same agent->path pair
    # repeats once per importing rig and would otherwise bury the detail.
    unique_crosspack="$(printf '%s\n' "${crosspack[@]}" | sort -u)"
    unique_count="$(printf '%s\n' "$unique_crosspack" | wc -l | tr -d ' ')"
    echo "${#crosspack[@]} reference(s), $unique_count distinct, resolve outside the city tree — imported packs, incl. the <pack>//<subpath> cross-pack form:"
    printf '%s\n' "$unique_crosspack"
fi
