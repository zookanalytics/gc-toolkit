#!/usr/bin/env bash
# doctor/check-cycle-recycle-hook — the two halves of the no-consent boundary
# are wired to the same roles. cycle-recycle recycles a patrol agent at a turn
# boundary without asking (docs/cycle-recycle.md), so every role it can recycle
# must also carry heartbeat-no-consent-ui, the fragment that forbids a heartbeat
# agent a blocking consent UI. The two halves are staged by independent
# mechanisms: the Stop hook rides overlay_dir = "overlays/cycle-recycle" on a
# [[patches.agent]] stanza in pack.toml, and the fragment is injected by the
# agent's own prompt. A role with the overlay but not the fragment recycles with
# nothing telling it not to prompt; a role with the fragment but not the overlay
# never recycles, so the doctrine guards a boundary it does not have. Both are
# silent: check-config-bound asserts each half RESOLVES and check-recycle-capable
# asserts the hook can fire, but neither asserts the two name the same set of
# roles. This asserts that set equality.
#
# The hook signal is the overlay_dir stanza alone: overlay_dir lives only on a
# [[patches.agent]] stanza (pack.toml: "agent.toml has no overlay key"), and the
# cycle-recycle Stop hook is registered in no other overlay's settings.json. The
# doctrine signal is a `{{ template "heartbeat-no-consent-ui" . }}` call in the
# agent's resolved prompt template (pack.toml: "each agent's prompt.template.md
# ... injects shared doctrine from template-fragments/ directly"); an agent.toml
# may point prompt_template at another agent's file, so the resolved path is
# read, not assumed from the directory name.
#
# Read-only and static: reads pack.toml and the agent prompt templates, no gc
# and no network, so no probe budget. Exit 0=OK 1=Warning 2=Error. stdout:
# message, then "  - detail" lines. An unreadable input warns (1), never passes.

set -u

dir="${GC_PACK_DIR:-.}"
OVERLAY="overlays/cycle-recycle"
FRAGMENT="heartbeat-no-consent-ui"

errors=(); warnings=(); notes=()
detail() { local v; for v in "$@"; do printf '  - %s\n' "$v"; done; }

PACK="$dir/pack.toml"
if [ ! -f "$PACK" ]; then
    echo "cycle-recycle wiring undetermined — no pack.toml at $dir"
    detail "the overlay side is declared in pack.toml [[patches.agent]] stanzas; without it the hook carriers are unknown and nothing below was asserted"
    exit 1
fi

# --- The hook side: agents carrying overlay_dir = overlays/cycle-recycle ------
# Walk the [[patches.agent]] stanzas, pairing each stanza's name with its
# overlay_dir (either order), and emit the name when the overlay matches. A
# stanza ends at the next section header of any kind.
hook_roles=$(awk -v target="$OVERLAY" '
    function value(s) { if (match(s, /"[^"]*"/)) return substr(s, RSTART + 1, RLENGTH - 2); return "" }
    function flush() { if (inblk && name != "" && ov == target) print name }
    /^[[:space:]]*\[\[patches\.agent\]\][[:space:]]*$/ { flush(); inblk = 1; name = ""; ov = ""; next }
    /^[[:space:]]*\[/                                   { flush(); inblk = 0; name = ""; ov = ""; next }
    inblk && /^[[:space:]]*name[[:space:]]*=/           { name = value($0); next }
    inblk && /^[[:space:]]*overlay_dir[[:space:]]*=/    { ov = value($0); next }
    END { flush() }
' "$PACK")

# --- The doctrine side: agents whose resolved prompt injects the fragment -----
frag_roles=""
for adir in "$dir"/agents/*/; do
    [ -d "$adir" ] || continue
    role=$(basename "$adir")
    toml="$adir/agent.toml"
    tmpl=""
    [ -f "$toml" ] && tmpl=$(sed -n 's/^[[:space:]]*prompt_template[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$toml" | head -1)
    if [ -n "$tmpl" ]; then tmpl_path="$dir/$tmpl"; else tmpl_path="$adir/prompt.template.md"; fi
    if [ -f "$tmpl_path" ] && grep -qE "template[[:space:]]+\"$FRAGMENT\"" "$tmpl_path"; then
        frag_roles="$frag_roles$role
"
    fi
done

# --- Compare the two sets ----------------------------------------------------
# awk skips blank lines, so an empty set contributes nothing; the output is
# sorted for a deterministic message.
mismatch=$(awk '
    NR == FNR { if ($0 != "") O[$0] = 1; next }
    { if ($0 != "") F[$0] = 1 }
    END {
        for (r in O) if (!(r in F)) print "overlay-only\t" r
        for (r in F) if (!(r in O)) print "fragment-only\t" r
    }
' <(printf '%s\n' "$hook_roles") <(printf '%s\n' "$frag_roles") | sort)

while IFS=$'\t' read -r kind role; do
    [ -n "$role" ] || continue
    case "$kind" in
        overlay-only)
            errors+=("role \"$role\" carries overlay_dir=\"$OVERLAY\" but its prompt injects no \"$FRAGMENT\" — cycle-recycle recycles it at a turn boundary with nothing telling it never to raise a blocking consent UI, which stalls patrol activity on an unanswered prompt. Inject the fragment into its prompt, or drop the overlay.") ;;
        fragment-only)
            errors+=("role \"$role\" injects \"$FRAGMENT\" but carries no overlay_dir=\"$OVERLAY\" — cycle-recycle never recycles it, so the no-consent doctrine guards a boundary the hook does not reach. Add the overlay, or drop the fragment.") ;;
    esac
done <<< "$mismatch"

overlay_list=$(printf '%s\n' "$hook_roles" | awk 'NF' | sort -u | paste -sd, - 2>/dev/null)
frag_list=$(printf '%s\n' "$frag_roles" | awk 'NF' | sort -u | paste -sd, - 2>/dev/null)

if [ "${#errors[@]}" -ne 0 ]; then
    echo "cycle-recycle hook and no-consent doctrine name different roles: ${#errors[@]} finding(s)"
    detail "overlay carriers: ${overlay_list:-<none>}"
    detail "fragment injectors: ${frag_list:-<none>}"
    detail "${errors[@]}"
    detail ${warnings[@]+"${warnings[@]}"}
    detail ${notes[@]+"${notes[@]}"}
    exit 2
fi
if [ "${#warnings[@]}" -ne 0 ]; then
    echo "cycle-recycle wiring partially determined"
    detail "${warnings[@]}"
    detail ${notes[@]+"${notes[@]}"}
    exit 1
fi
if [ -z "$overlay_list" ] && [ -z "$frag_list" ]; then
    echo "OK: this pack wires no $OVERLAY overlay and injects no $FRAGMENT — nothing to assert"
    exit 0
fi
echo "OK: the roles carrying $OVERLAY and the roles injecting $FRAGMENT are the same set ($overlay_list)"
detail ${notes[@]+"${notes[@]}"}
exit 0
