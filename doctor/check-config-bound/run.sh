#!/usr/bin/env bash
# doctor/check-config-bound — everything the config names resolves. Static
# arms (always run): every fragment named in an inject_fragments /
# inject_fragments_append list resolves in template-fragments/ — as
# <name>.template.md or a {{ define "<name>" }} block; sub-pack files check
# their own tree first, then the root's — and every declared overlay_dir
# exists. Live arm (needs gc + a city): every agent prompt_template in the
# RESOLVED config names a readable file — `gc prime` renders an unreadable
# template as the 16-line generic stub and exits 0, so the agent claims real
# work with none of its doctrine and nothing reports an error.
# Read-only. Exit 0=OK 1=Warning 2=Error. stdout: message, then "  - detail"
# lines. Bounded probes; an unreadable RESOLVED config warns (1), never passes.

set -u

dir="${GC_PACK_DIR:-.}"
city="${GC_CITY_PATH:-${GC_CITY:-}}"

errors=(); warnings=(); notes=()
# >>> doctor-budget
# One deadline for the whole check, anchored at process start. `gc doctor
# --check-timeout` (default 60s) abandons an overrunning check and discards
# everything it had buffered, so a check that has not printed by then is never
# heard. A per-probe constant does not hold that line: the probes below run
# once per rig, so their ceilings sum. Each probe gets the time still left
# instead, capped at half the budget so one wedged store cannot eat the rest,
# and a probe that no longer fits is refused with 124 — `timeout`'s own expiry
# code, which every caller's "this store was NOT checked" arm already handles.
# GC_DOCTOR_CHECK_TIMEOUT overrides the default, in whole seconds. Nothing
# exports it: the runner passes GC_CITY_PATH and GC_PACK_DIR and no budget.
BUDGET_DEFAULT=60; BUDGET_RESERVE=5; BUDGET_MIN_PROBE=2
budget_now() { if [ -n "${EPOCHSECONDS:-}" ]; then printf %s "$EPOCHSECONDS"; else date +%s; fi; }
budget_init() {
    BUDGET_TOTAL="${GC_DOCTOR_CHECK_TIMEOUT:-$BUDGET_DEFAULT}"; BUDGET_TOTAL="${BUDGET_TOTAL%s}"
    case "$BUDGET_TOTAL" in ''|*[!0-9]*) BUDGET_TOTAL="$BUDGET_DEFAULT" ;; esac
    BUDGET_CAP=$(( BUDGET_TOTAL / 2 ))
    BUDGET_DEADLINE=$(( $(budget_now) - SECONDS + BUDGET_TOTAL - BUDGET_RESERVE ))
}
budget_slice() {
    local left=$(( BUDGET_DEADLINE - $(budget_now) ))
    [ "$left" -le "$BUDGET_CAP" ] || left="$BUDGET_CAP"
    [ "$left" -ge 0 ] || left=0
    printf %s "$left"
}
budget_spent() { [ "$(budget_slice)" -lt "$BUDGET_MIN_PROBE" ]; }
run_bounded() { local s; s=$(budget_slice); [ "$s" -ge "$BUDGET_MIN_PROBE" ] || return 124
    if command -v timeout >/dev/null 2>&1; then timeout "$s" "$@" </dev/null; else "$@" </dev/null; fi; }
# A probe fed from a pipe cannot borrow run_bounded's </dev/null.
run_piped() { local s; s=$(budget_slice); [ "$s" -ge "$BUDGET_MIN_PROBE" ] || return 124
    if command -v timeout >/dev/null 2>&1; then timeout "$s" "$@"; else "$@"; fi; }
budget_init
# <<< doctor-budget
detail() { local v; for v in "$@"; do printf '  - %s\n' "$v"; done; }

# --- Static arm 1: inject_fragments lists resolve --------------------------
frag_resolves() { # <pack-root> <name>
    [ -f "$1/template-fragments/$2.template.md" ] && return 0
    grep -qE "\{\{-?[[:space:]]*define[[:space:]]+\"$2\"" "$1"/template-fragments/*.template.md 2>/dev/null
}
extract_fragments() { # <file> — one fragment name per line
    awk '
        /^[[:space:]]*inject_fragments(_append)?[[:space:]]*=[[:space:]]*\[/ { inl = 1 }
        inl {
            line = $0; sub(/#.*$/, "", line)
            while (match(line, /"[^"]*"/)) {
                print substr(line, RSTART + 1, RLENGTH - 2)
                line = substr(line, RSTART + RLENGTH)
            }
            if (line ~ /\]/) inl = 0
        }' "$1" 2>/dev/null
}
config_files=()
for f in "$dir/pack.toml" "$dir"/agents/*/agent.toml \
         "$dir"/packs/*/pack.toml "$dir"/packs/*/agents/*/agent.toml; do
    [ -f "$f" ] && config_files+=("$f")
done
frags_checked=0
for f in ${config_files[@]+"${config_files[@]}"}; do
    rel="${f#"$dir"/}"
    # The pack root whose template-fragments/ this file's names resolve in.
    root="$dir"
    case "$rel" in packs/*) root="$dir/packs/${rel#packs/}"; root="${root%%/agents/*}"; root="${root%/pack.toml}" ;; esac
    while IFS= read -r name; do
        [ -n "$name" ] || continue
        frags_checked=$((frags_checked + 1))
        frag_resolves "$root" "$name" && continue
        [ "$root" != "$dir" ] && frag_resolves "$dir" "$name" && continue
        errors+=("$rel: fragment \"$name\" resolves in no template-fragments/ (no $name.template.md and no {{ define \"$name\" }} block) — the render silently drops it and the agent runs without that doctrine")
    done <<< "$(extract_fragments "$f")"
done

# --- Static arm 2: declared overlay_dir paths exist -------------------------
overlays_checked=0
for f in ${config_files[@]+"${config_files[@]}"}; do
    rel="${f#"$dir"/}"
    root="$dir"
    case "$rel" in packs/*) root="$dir/packs/${rel#packs/}"; root="${root%%/agents/*}"; root="${root%/pack.toml}" ;; esac
    while IFS= read -r ov; do
        [ -n "$ov" ] || continue
        overlays_checked=$((overlays_checked + 1))
        if [ ! -d "$root/$ov" ] && [ ! -d "$dir/$ov" ]; then
            errors+=("$rel: overlay_dir = \"$ov\" names no directory in the pack — the overlay's hooks are silently never staged")
        fi
    done <<< "$(sed -n 's/^[[:space:]]*overlay_dir[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$f" 2>/dev/null)"
done

# --- Live arm: resolved prompt_template paths readable -----------------------
# Resolution is a runtime property; outside a city this arm is a note, not a
# finding — nothing has been observed to be wrong.
prompts_checked=0
if ! command -v gc >/dev/null 2>&1; then
    notes+=("gc is not on PATH — prompt_template resolution is a runtime property, not verifiable here")
elif [ -z "$city" ]; then
    notes+=("no city in scope (GC_CITY_PATH/GC_CITY unset) — prompt_template resolution not verifiable here")
else
    config_out=$(run_bounded gc --city "$city" config show 2>/dev/null); config_rc=$?
    if [ "$config_rc" -ne 0 ] || [ -z "$config_out" ]; then
        warnings+=("could not resolve the city config (gc --city $city config show rc=$config_rc) — prompt integrity UNVERIFIED. Not a benign skip: on a config that fails to load, \`gc prime\` emits the 16-line default prompt and returns 0, so every agent primes stubbed while nothing reports an error.")
    else
        # (agent, resolved prompt_template) pairs from the resolved TOML.
        resolved=$(printf '%s\n' "$config_out" | awk '
            function flush() { if (inb == 1 && pt != "") print (name == "" ? "<unnamed>" : name) "\t" pt }
            /^\[\[agent\]\]/ { flush(); inb = 1; name = ""; pt = ""; next }
            /^\[/            { flush(); inb = 0; name = ""; pt = ""; next }
            inb == 1 && /^name = "/ { if (name == "") { v = $0; sub(/^name = "/, "", v); sub(/"$/, "", v); name = v }; next }
            inb == 1 && /^prompt_template = "/ { v = $0; sub(/^prompt_template = "/, "", v); sub(/"$/, "", v); pt = v; next }
            END { flush() }')
        while IFS=$'\t' read -r agent_name template_path; do
            [ -n "${template_path:-}" ] || continue
            case "$template_path" in /*) abs="$template_path" ;; *) abs="$city/$template_path" ;; esac
            prompts_checked=$((prompts_checked + 1))
            [ -r "$abs" ] || errors+=("agent $agent_name: prompt_template does not resolve to a readable file ($abs) — \`gc prime\` will render the 16-line generic stub at exit 0; confirm with \`gc prime --strict $agent_name\`")
        done <<< "$resolved"
    fi
fi

if budget_spent; then
    warnings+=("this run reached its ${BUDGET_TOTAL}s doctor budget before every probe ran — what follows is partial, and an arm skipped for time is not an arm that passed")
fi
if [ "${#errors[@]}" -ne 0 ]; then
    echo "config names things that do not resolve: ${#errors[@]} finding(s)"
    detail "${errors[@]}"
    detail ${warnings[@]+"${warnings[@]}"}
    detail ${notes[@]+"${notes[@]}"}
    exit 2
fi
if [ "${#warnings[@]}" -ne 0 ]; then
    echo "config binding partially determined"
    detail "${warnings[@]}"
    detail ${notes[@]+"${notes[@]}"}
    exit 1
fi
echo "OK: $frags_checked fragment reference(s), $overlays_checked overlay_dir(s), $prompts_checked resolved prompt_template(s) all bind"
detail ${notes[@]+"${notes[@]}"}
exit 0
