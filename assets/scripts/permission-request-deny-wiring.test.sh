#!/usr/bin/env bash
# permission-request-deny-wiring.test.sh — assert that each Claude agent no
# person attends refuses Claude Code's permission prompts, and that no agent a
# person attends does.
#
# Claude Code asks a person before some calls even in bypass permissions mode.
# In a session nobody attends, that prompt waits until someone happens to look,
# and the session holds its claim and its slot the whole time. A
# PermissionRequest hook that answers with a deny ends the wait at once and
# tells the agent what to send instead. Nothing at runtime reports an agent
# whose overlay lost the hook, since it looks like an agent that has met no
# prompt yet, and the hook on a seat a person attends would refuse what that
# person is there to approve.
#
# Covered:
#   (1) every Claude agent under agents/ is classified below, as one no person
#       attends or one a person attends, so an agent added to either set is a
#       decision and not an accident
#   (2) every agent no person attends takes an overlay that registers the hook
#       for every tool (matcher ""), and no agent a person attends does
#   (3) every registration runs the same command
#   (4) the command prints one PermissionRequest decision: a deny that carries
#       a message
#
# run-tests-scope: tree

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"

# The pools and the heartbeat roles run with nobody at their terminal. The
# seats are the operator's own, and a demo capture is watched while it runs.
UNATTENDED="polecat proactive refinery witness deacon"
ATTENDED="mechanik po demo converse-claude-fable converse-claude-opus converse-fable converse-opus"

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n        %s\n' "$1" "$2"; }

command -v jq >/dev/null 2>&1 || { echo "FATAL: jq required" >&2; exit 1; }

echo "permission-request deny wiring"

in_list() { # in_list <word> <list>
    case " $2 " in *" $1 "*) return 0 ;; esac
    return 1
}

overlay_of() { # overlay_of <agent>
    awk -v want="$1" '
        /^\[\[patches\.agent\]\]/ { name = ""; overlay = ""; next }
        /^name *=/    { gsub(/^name *= *"|" *$/, ""); name = $0; next }
        /^overlay_dir *=/ {
            gsub(/^overlay_dir *= *"|" *$/, ""); overlay = $0
            if (name == want) { print overlay; exit }
        }
    ' "$REPO/pack.toml"
}

deny_command() { # deny_command <settings.json>: the registered command, or nothing
    jq -r '[ (.hooks.PermissionRequest // [])[]
             | select((.matcher // "") == "")
             | (.hooks // [])[]
             | select((.type // "") == "command")
             | .command ] | first // ""' "$1" 2>/dev/null
}

CMDS=""
SEEN=0
for dir in "$REPO"/agents/*/; do
    agent="$(basename "$dir")"
    [ -f "$dir/agent.toml" ] || continue
    # A codex agent reads no .claude/settings.json, so no Claude hook reaches it.
    grep -Eq '^provider *= *"codex"' "$dir/agent.toml" && continue
    SEEN=$((SEEN + 1))

    # --- (1) classified ---------------------------------------------------
    if in_list "$agent" "$UNATTENDED"; then want=deny
    elif in_list "$agent" "$ATTENDED"; then want=prompt
    else
        bad "$agent is classified" "add it to UNATTENDED or ATTENDED in this test"
        continue
    fi

    # --- (2) the overlay matches the class --------------------------------
    overlay="$(overlay_of "$agent")"
    settings="$REPO/$overlay/.claude/settings.json"
    if [ -z "$overlay" ] || [ ! -s "$settings" ]; then
        bad "$agent has an overlay with settings" "no overlay_dir in pack.toml, or no $settings"
        continue
    fi
    cmd="$(deny_command "$settings")"
    if [ "$want" = deny ]; then
        if [ -n "$cmd" ]; then
            ok "$agent refuses permission prompts (via $overlay)"
            CMDS="$CMDS$cmd
"
        else
            bad "$agent refuses permission prompts" "$overlay registers no PermissionRequest hook with matcher \"\""
        fi
    else
        n="$(jq -r '(.hooks.PermissionRequest // []) | length' "$settings" 2>/dev/null)"
        if [ "$n" = 0 ]; then
            ok "$agent leaves permission prompts to its person (via $overlay)"
        else
            bad "$agent leaves permission prompts to its person" "$overlay registers ${n:-an unreadable set of} PermissionRequest hooks"
        fi
    fi
done

if [ "$SEEN" -gt 0 ]; then ok "found $SEEN Claude agents"
else bad "found Claude agents" "none under $REPO/agents"; fi

# --- (3) one command -------------------------------------------------------
COUNT="$(printf '%s' "$CMDS" | grep -c . || true)"
UNIQUE="$(printf '%s' "$CMDS" | sort -u | grep -c . || true)"
if [ "$COUNT" -gt 0 ] && [ "$UNIQUE" -eq 1 ]; then
    ok "every registration runs the same command ($COUNT registrations)"
else
    bad "every registration runs the same command" "$COUNT registrations, $UNIQUE distinct spellings"
fi

# --- (4) the decision it prints --------------------------------------------
CMD="$(printf '%s' "$CMDS" | head -1)"
if [ -n "$CMD" ]; then
    OUT="$(sh -c "$CMD" </dev/null 2>/dev/null)"
    if printf '%s' "$OUT" | jq -e '
        .hookSpecificOutput.hookEventName == "PermissionRequest"
        and .hookSpecificOutput.decision.behavior == "deny"
        and ((.hookSpecificOutput.decision.message // "") | length > 0)' >/dev/null 2>&1; then
        ok "the command prints a deny decision with a message"
    else
        bad "the command prints a deny decision with a message" "printed: $OUT"
    fi
    if [ "$(printf '%s\n' "$OUT" | grep -c .)" -eq 1 ]; then
        ok "the command prints one line"
    else
        bad "the command prints one line" "printed: $OUT"
    fi
fi

echo
printf 'permission-request deny wiring: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
