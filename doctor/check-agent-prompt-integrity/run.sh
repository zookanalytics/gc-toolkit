#!/usr/bin/env bash
# Pack doctor check: no agent silently renders the generic prompt stub.
#
# A `prompt_template` in the `<pack>//<subpath>` cross-pack form is
# resolved against the PACK directory (`<pack-root>/<pack>/…`), not the
# import cache. When the referenced pack is not materialized there the
# path does not exist — and gascity's resolver does not fail config
# load; it silently
# falls back to the 16-line generic stub ("You are an agent in a Gas City
# workspace. Claim available work and execute it."), so e.g. a codex
# polecat would claim real work with none of its doctrine. A doctor check
# cannot render prompts, so this is a static guard: any agent carrying the
# cross-pack form is listed as a WARNING with the manual confirmation
# (rendered-prompt size) spelled out. The referenced pack must be
# import-materialized for the reference to resolve at all.
#
# Exit codes: 0=OK, 1=Warning, 2=Error
# stdout: first line=message, rest=details

set -u

dir="${GC_PACK_DIR:-.}"

if [ ! -d "$dir/agents" ]; then
    echo "OK: no agents/ directory — nothing to check"
    exit 0
fi

findings=()
for f in "$dir"/agents/*/agent.toml; do
    [ -s "$f" ] || continue
    ref="$(grep -E '^prompt_template *= *"[^"]+//[^"]+"' "$f" | head -1 | sed 's/.*"\(.*\)".*/\1/')"
    [ -n "$ref" ] || continue
    findings+=("agents/$(basename "$(dirname "$f")")/agent.toml: prompt_template = \"$ref\"")
done

if [ "${#findings[@]}" -eq 0 ]; then
    echo "OK: no cross-pack (<pack>//<subpath>) prompt_template references — no stub-fallback exposure"
    exit 0
fi

echo "${#findings[@]} agent(s) carry a cross-pack prompt_template — stub-fallback exposure"
printf '%s\n' "${findings[@]}"
echo "The referenced pack must be import-materialized: gascity resolves <pack>//<subpath> against the pack dir and, when the path is absent, silently renders the 16-line generic stub instead of failing config load."
echo "Confirm manually per agent: gc agent render <name> | wc -l — expect >100 lines; 16 means the stub."
exit 1
