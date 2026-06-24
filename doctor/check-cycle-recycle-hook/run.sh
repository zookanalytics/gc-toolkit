#!/usr/bin/env bash
# Pack doctor check: the deterministic cycle-recycle Stop hook is shipped and wired.
#
# Context recycling for patrol agents (witness/deacon/refinery) at the 200K
# input_tokens threshold is enforced by a Claude `Stop` hook shipped in
# overlays/cycle-recycle/ and staged into each patrol agent's work dir via the
# `overlay_dir` patch in pack.toml — NOT by soft formula prose, which degraded
# exactly as context filled so the recycle never fired (tk-g8pfg). This check
# guards that the hook stays shipped and wired, so the mechanism can't be
# silently un-shipped and regress to that bug.
#
# Supersedes the former pour-before-handoff check: the hook hands off + resets
# and delegates the next wisp to the inheriting session's startup-adopt, so
# there is no pour-before-handoff step left to validate. See specs/tk-fyzvk for
# the original cycle-recycle diagnostic and tk-g8pfg for the hook decision.
#
# Exit codes: 0=OK, 1=Warning, 2=Error
# stdout: first line=message, rest=details

set -u

dir="${GC_PACK_DIR:-.}"
hook="$dir/overlays/cycle-recycle/.claude/hooks/cycle-recycle.sh"
settings="$dir/overlays/cycle-recycle/.claude/settings.json"
pack="$dir/pack.toml"
errors=()

# 1. Hook script: present, non-empty, self-gates to patrol roles, keeps the
#    200K threshold, and performs the handoff + reset recycle.
if [ ! -s "$hook" ]; then
    errors+=("missing or empty hook script: overlays/cycle-recycle/.claude/hooks/cycle-recycle.sh")
else
    grep -Eq 'witness *\| *deacon *\| *refinery' "$hook" \
        || errors+=("hook script does not self-gate to witness/deacon/refinery roles")
    grep -q '200000' "$hook" \
        || errors+=("hook script does not reference the 200000 (200K) input_tokens threshold")
    grep -q 'gc handoff' "$hook" \
        || errors+=("hook script does not call 'gc handoff' (durable HANDOFF mail)")
    grep -q 'gc session reset' "$hook" \
        || errors+=("hook script does not call 'gc session reset' (restart trigger)")
fi

# 2. Overlay settings register a Claude `Stop` hook.
if [ ! -s "$settings" ]; then
    errors+=("missing overlay settings: overlays/cycle-recycle/.claude/settings.json")
else
    grep -q '"Stop"' "$settings" \
        || errors+=('overlay settings.json does not register a "Stop" hook')
fi

# 3. pack.toml wires overlay_dir = "overlays/cycle-recycle" onto all three
#    patrol agents (witness, deacon, refinery). Pure-bash TOML parsing is
#    brittle, so assert the literal wiring line appears at least three times —
#    one per patrol-agent patch.
if [ ! -f "$pack" ]; then
    errors+=("missing pack.toml")
else
    n=$(grep -c 'overlay_dir = "overlays/cycle-recycle"' "$pack")
    if [ "${n:-0}" -lt 3 ]; then
        errors+=("pack.toml wires overlay_dir=overlays/cycle-recycle on ${n:-0} agent patch(es); want 3 (witness/deacon/refinery)")
    fi
fi

if [ ${#errors[@]} -eq 0 ]; then
    echo "cycle-recycle Stop hook is shipped and wired on all three patrol agents"
    exit 0
fi

echo "${#errors[@]} cycle-recycle hook integrity problem(s) — see tk-g8pfg"
for e in "${errors[@]}"; do
    echo "$e"
done
exit 2
