#!/usr/bin/env bash
# Pack doctor check: the work-bead description reaches the polecat.
#
# A filer who writes a spec into a bead's description has no guarantee the
# worker reads it. Upstream mol-polecat-work/mol-polecat-base (gastown pack, not
# editable from here) read the work bead five times and every read is
# jq-filtered to one metadata field; the description reaches the worker only via
# the `load-context` step's prose `gc bd show`, which the `implement` step never
# repeats and a mid-workflow respawn never runs. Delivery is therefore made
# deterministic by a Claude `PostToolUse` hook shipped in overlays/work-context/
# and staged into the polecat's work dir via `overlay_dir` in pack.toml
# (tk-osf13). This check guards that it stays shipped and wired.
#
# It also pins the two traps that make this hook fail SILENTLY — it exits 0 and
# prints nothing by design, so neither trap is observable at runtime:
#   * the claim response arrives tojson-escaped (\"bead_id\":\"...\"), so a
#     scanner without the unescape matches nothing, forever;
#   * `cut -c` caps per LINE, so a multi-line description sails past the size
#     bound; only a whole-payload cap (`head -c`) actually bounds it.
# Both are covered by assets/scripts/work-context-hook.test.sh, which runs the
# shipped script; this check is the cheaper always-on gate that the artifacts
# still exist and are still connected.
#
# Exit codes: 0=OK, 1=Warning, 2=Error
# stdout: first line=message, rest=details

set -u

dir="${GC_PACK_DIR:-.}"
overlay="$dir/overlays/work-context/.claude"
hook="$overlay/hooks/work-context.sh"
settings="$overlay/settings.json"
pack="$dir/pack.toml"
test_script="$dir/assets/scripts/work-context-hook.test.sh"
errors=()

# 1. Hook script: present, correctly gated, resolves the work bead, and emits
#    the injection in the shape the client consumes.
if [ ! -s "$hook" ]; then
    errors+=("missing or empty hook script: overlays/work-context/.claude/hooks/work-context.sh")
else
    grep -q 'GC_TEMPLATE' "$hook" \
        || errors+=("hook script does not gate on GC_TEMPLATE (GC_AGENT is the pool name, not the role — pool polecats are named after people)")
    grep -q 'gc convoy status' "$hook" \
        || errors+=("hook script does not resolve the work bead through 'gc convoy status' (a claimed formula step is not the work bead)")
    # Every assertion below scores CODE, not prose. This script's own header
    # explains each trap by name, so a comment-inclusive grep would score the
    # explanation of the fix as the fix — the exact way a negative assertion
    # goes vacuously green.
    code="$(grep -vE '^[[:space:]]*#' "$hook")"
    printf '%s' "$code" | grep -q 'hookEventName.*PostToolUse' \
        || errors+=("hook script does not emit hookEventName=PostToolUse (the only event that fires AFTER the claim in the same turn)")
    printf '%s' "$code" | grep -q 'additionalContext' \
        || errors+=("hook script does not emit additionalContext")
    printf '%s' "$code" | grep -q 'bead_id' \
        || errors+=("hook script does not read bead_id from the claim response")
    # The silent-forever trap: Bash's tool_response is an object, so the JSON
    # the command printed comes back re-escaped.
    printf '%s' "$code" | grep -q 's/\\\\"/"/g' \
        || errors+=("hook script does not unescape the tojson-escaped tool_response; the bead_id scan will match nothing on the real payload shape")
    # The unbounded-injection trap.
    printf '%s' "$code" | grep -q 'head -c' \
        || errors+=("hook script does not bound the injection with a whole-payload cap ('head -c'); 'cut -c' truncates per line and does not bound a multi-line description")
    printf '%s' "$code" | grep -q 'cut -c' \
        && errors+=("hook script uses 'cut -c' to cap the description; that truncates per LINE and silently caps nothing on a multi-line body")
    [ -x "$hook" ] \
        || errors+=("hook script is not executable (staging preserves mode; a non-executable hook is a silent no-op)")
fi

# 2. Overlay settings register the PostToolUse hook against Bash and point at
#    the shipped script.
if [ ! -s "$settings" ]; then
    errors+=("missing overlay settings: overlays/work-context/.claude/settings.json")
else
    grep -q '"PostToolUse"' "$settings" \
        || errors+=('overlay settings.json does not register a "PostToolUse" hook')
    grep -q '"matcher": *"Bash"' "$settings" \
        || errors+=('overlay settings.json does not match the Bash tool (the claim is a Bash call)')
    grep -q 'work-context.sh' "$settings" \
        || errors+=("overlay settings.json does not invoke work-context.sh")
fi

# 3. pack.toml wires the overlay onto the polecat patch. Pure-bash TOML parsing
#    is brittle, so assert the literal wiring line is present.
if [ ! -f "$pack" ]; then
    errors+=("missing pack.toml")
else
    grep -q 'overlay_dir = "overlays/work-context"' "$pack" \
        || errors+=("pack.toml does not wire overlay_dir=overlays/work-context onto any agent patch — the hook ships but never stages")
fi

# 4. The hermetic test stays shipped: it is the only thing that can tell
#    "correctly stayed quiet" from "broken and stayed quiet".
[ -s "$test_script" ] \
    || errors+=("missing hermetic test: assets/scripts/work-context-hook.test.sh")

if [ ${#errors[@]} -eq 0 ]; then
    echo "work-bead description delivery is shipped and wired onto the polecat pool"
    exit 0
fi

echo "${#errors[@]} work-context hook integrity problem(s) — see tk-osf13"
for e in "${errors[@]}"; do
    echo "  - $e"
done
exit 2
