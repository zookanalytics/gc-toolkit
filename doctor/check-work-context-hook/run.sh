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
    # Every assertion scores CODE, not prose. This check's header and the hook's
    # own comments name each trap — and the GC_TEMPLATE role gate — in words, so
    # a comment-inclusive grep would score the explanation of a fix as the fix:
    # the check would stay green after the operative line was mutated and only
    # its comment left behind, the exact way a negative assertion goes vacuously
    # green. Strip comments once, score the remainder.
    code="$(grep -vE '^[[:space:]]*#' "$hook")"
    printf '%s' "$code" | grep -qE '[$][{]?GC_TEMPLATE' \
        || errors+=("hook script does not read the role from GC_TEMPLATE in code (GC_AGENT is the pool name, not the role — pool polecats are named after people); a comment that merely mentions GC_TEMPLATE does not count")
    printf '%s' "$code" | grep -q 'gc convoy status' \
        || errors+=("hook script does not resolve the work bead through 'gc convoy status' (a claimed formula step is not the work bead)")
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

# 2. Overlay settings register the PostToolUse hook against the Bash tool and
#    point it at the shipped script. settings.json now carries a second Bash
#    matcher (the PreToolUse gh-origin-guard), so "some matcher is Bash" no
#    longer proves the PostToolUse hook is the one bound to Bash — scope the
#    assertion to the PostToolUse block. settings.json is JSON, so read it with
#    jq, not a line-grep that cannot tell one block from another.
if [ ! -s "$settings" ]; then
    errors+=("missing overlay settings: overlays/work-context/.claude/settings.json")
elif ! command -v jq >/dev/null 2>&1; then
    errors+=("jq is unavailable, so overlay settings.json wiring cannot be verified")
elif ! jq -e '
      (.hooks.PostToolUse // [])
      | any(.matcher == "Bash"
            and ((.hooks // []) | any((.command // "") | contains("work-context.sh"))))
    ' "$settings" >/dev/null 2>&1; then
    errors+=("overlay settings.json does not register a PostToolUse hook that matches Bash and invokes work-context.sh")
fi

# 3. pack.toml wires the overlay onto the POLECAT patch specifically. A literal
#    grep proves only that some agent carries the line, so a pack.toml that moved
#    the overlay onto another agent's patch would read green while no polecat
#    session ever stages the hook. Walk the [[patches.agent]] blocks and require
#    that the block named "polecat" is the one carrying the work-context overlay.
if [ ! -f "$pack" ]; then
    errors+=("missing pack.toml")
elif ! awk '
      function finalize() { if (inblock && name == "polecat" && has) found = 1; inblock = 0; name = ""; has = 0 }
      /^[[:space:]]*\[\[patches\.agent\]\]/ { finalize(); inblock = 1; next }
      /^[[:space:]]*\[/                     { finalize(); next }
      inblock && /^[[:space:]]*name[[:space:]]*=/        { if (match($0, /"[^"]*"/)) name = substr($0, RSTART + 1, RLENGTH - 2); next }
      inblock && /^[[:space:]]*overlay_dir[[:space:]]*=[[:space:]]*"overlays\/work-context"/ { has = 1; next }
      END { finalize(); exit (found ? 0 : 1) }
    ' "$pack"; then
    errors+=("pack.toml does not wire overlay_dir=overlays/work-context onto the polecat agent patch — another agent carrying it does not stage the hook into polecat sessions")
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
