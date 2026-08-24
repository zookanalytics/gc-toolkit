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
# ALSO ASSERTED: the no-consent-UI DOCTRINE reaches the same three roles. The
# hook and the `heartbeat-no-consent-ui` fragment are two halves of one
# guardrail — the hook is why the recycle never prompts, the fragment is the
# only place any agent is TOLD never to prompt, and the hook's own invariant
# list cites the fragment by name. They were wired to different sets: all three
# patrol agents got the overlay, only two got the fragment, so the refinery had
# a hook that will not prompt and an agent that was never told not to
# (tk-17wggn). That asymmetry is invisible from outside — the role primes fine,
# patrols fine, and prompts once, on the rare occasion it judges exceptional,
# then parks until a human walks past the pane. lx-nc2kw is the 12h25m witness
# park that this fragment is written from.
#
# Exit codes: 0=OK, 1=Warning, 2=Error
# stdout: first line=message, rest=details

set -u

dir="${GC_PACK_DIR:-.}"
hook="$dir/overlays/cycle-recycle/.claude/hooks/cycle-recycle.sh"
settings="$dir/overlays/cycle-recycle/.claude/settings.json"
pack="$dir/pack.toml"
errors=()

# The doctrine fragment that must accompany the overlay, and the roles that
# must carry both. This list is the hook's own self-gate (`witness | deacon |
# refinery`) and the fragment's own closing sentence; keep all three in step.
FRAGMENT_NAME="heartbeat-no-consent-ui"
PATROL_ROLES=(witness deacon refinery)
fragment="$dir/template-fragments/$FRAGMENT_NAME.template.md"

# Quote-aware TOML comment stripper + array reader: emit every quoted string in
# the array that starts at `<key> =` and ends at the first `]`, reading the
# block on stdin. Stripping comments is load-bearing, not cosmetic — the patch
# arrays in pack.toml carry long explanatory comments INSIDE the brackets and
# several of them quote agent names, which a naive quote-scrape would read as
# entries. Borrowed from doctor/check-polecat-fragment-sync.
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
    ' | grep -o '"[^"]*"' | tr -d '"'
}

# The lines of the [[patches.agent]] block whose name is $2. Scoped rather than
# grepped globally: pack.toml holds several inject_fragments_append arrays, and
# the wrong one compares cleanly against nothing.
agent_patch_block() { # $1 = pack.toml path, $2 = agent name
    awk -v want_name="$2" '
        function flush() { if (want) { printf "%s", buf; exit } inb = 0; buf = ""; want = 0 }
        /^[[:space:]]*\[\[patches\.agent\]\][[:space:]]*$/ { flush(); inb = 1; buf = ""; want = 0; next }
        /^[[:space:]]*\[/ { flush(); inb = 0; buf = ""; want = 0; next }
        inb {
            buf = buf $0 "\n"
            if ($0 ~ ("^[[:space:]]*name[[:space:]]*=[[:space:]]*\"" want_name "\"[[:space:]]*$")) want = 1
        }
        END { flush() }
    ' "$1"
}

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

# 3. pack.toml wires BOTH halves of the guardrail onto each patrol role:
#    `overlay_dir` (the hook, which recycles without ever prompting) and
#    `inject_fragments_append` (the doctrine, the only place an agent is told
#    never to prompt). Each is resolved inside that role's own
#    [[patches.agent]] block rather than counted across the file.
#
#    The count form this replaced — "the literal wiring line appears >= 3
#    times" — is green for two different un-wirings. Commenting a line out
#    leaves its text in place, so `# overlay_dir = "overlays/cycle-recycle"`
#    still counts. And the fragment NAME appears in pack.toml's own header
#    comment listing the pack's doctrine fragments, so a count of 3 is
#    reachable with only two agents wired: the state that actually shipped for
#    three months, refinery un-wired (tk-17wggn). Neither hole is visible from
#    a green check, which is the whole failure class here.
if [ ! -f "$pack" ]; then
    errors+=("missing pack.toml")
else
    no_block=()
    missing_overlay=()
    missing_frag=()
    for role in "${PATROL_ROLES[@]}"; do
        block="$(agent_patch_block "$pack" "$role")"
        if [ -z "$block" ]; then
            no_block+=("$role")
            continue
        fi
        grep -Eq '^[[:space:]]*overlay_dir[[:space:]]*=[[:space:]]*"overlays/cycle-recycle"' <<< "$block" \
            || missing_overlay+=("$role")
        role_frags="$(printf '%s' "$block" | array_values inject_fragments_append)"
        grep -qxF "$FRAGMENT_NAME" <<< "$role_frags" \
            || missing_frag+=("$role")
    done
    if [ "${#no_block[@]}" -gt 0 ]; then
        errors+=("pack.toml has no [[patches.agent]] block for: ${no_block[*]} — a role with no patch can carry neither the overlay nor the doctrine")
    fi
    if [ "${#missing_overlay[@]}" -gt 0 ]; then
        errors+=("pack.toml does not wire overlay_dir=overlays/cycle-recycle on: ${missing_overlay[*]}; want it on all of ${PATROL_ROLES[*]}")
    fi
    if [ "${#missing_frag[@]}" -gt 0 ]; then
        errors+=("pack.toml does not inject $FRAGMENT_NAME on: ${missing_frag[*]} — the hook recycles all of ${PATROL_ROLES[*]}, so every role it recycles must also read the doctrine that says never to prompt")
    fi
fi

# 4. The fragment itself is present and still claims the roles it is wired to.
#    Its closing sentence names the trio, and that sentence is what a deacon or
#    witness reads to conclude the refinery is covered too — so a fragment that
#    stops naming a role, or a role that stops being injected, are the same
#    finding from opposite ends.
if [ ! -s "$fragment" ]; then
    errors+=("missing or empty doctrine fragment: template-fragments/$FRAGMENT_NAME.template.md")
else
    grep -q 'AskUserQuestion' "$fragment" \
        || errors+=("fragment does not name AskUserQuestion — the tool the prohibition is about")
    unclaimed=()
    for role in "${PATROL_ROLES[@]}"; do
        grep -q "$role" "$fragment" || unclaimed+=("$role")
    done
    if [ "${#unclaimed[@]}" -gt 0 ]; then
        errors+=("fragment does not name ${unclaimed[*]} among the heartbeat agents it governs, but pack.toml injects it there")
    fi
fi

if [ ${#errors[@]} -eq 0 ]; then
    echo "cycle-recycle Stop hook is shipped and wired on all three patrol agents, and all three read $FRAGMENT_NAME"
    exit 0
fi

echo "${#errors[@]} cycle-recycle guardrail integrity problem(s) — see tk-g8pfg (hook), tk-17wggn (doctrine)"
for e in "${errors[@]}"; do
    echo "$e"
done
exit 2
