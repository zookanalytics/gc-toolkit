#!/usr/bin/env bash
# doctor/check-work-context-hook — a polecat's claim delivers its work bead's
# description.
#
# mol-polecat-work prints the whole work bead once, in load-context, and every
# later read filters it to one field. A respawn mid-workflow never re-runs
# load-context. So a filed description reaches the worker reliably through one
# path: a Claude PostToolUse hook, staged into the polecat's work dir by the
# overlay_dir pack.toml puts on the polecat agent, that prints the claimed work
# bead's description as additionalContext (specs/tk-osf13/). The hook exits 0
# and prints nothing whenever it cannot deliver, by design, so an unwired or
# broken hook looks the same as a claim with no description to deliver.
#
# The check runs that path instead of reading the hook's source. It copies the
# polecat agent's overlay into a scratch work dir and runs each PostToolUse
# command the overlay's .claude/settings.json registers for the Bash tool,
# the way Claude runs a hook: `sh -c`, in the work dir, with the hook input on
# stdin. The input is a claim of a formula step. The environment carries a
# polecat's role, and a stub gc answers the reads that resolve the step to its
# work bead: the step, its workflow root, the root's input convoy and the work
# bead. The check passes when a command prints the work bead's description as
# PostToolUse additionalContext; an error means the simulated claim got no
# description back, or the wrong bead's.
#
# What it does not cover. The hook's other branches (the role and provider
# gates, once per session, the size cap, a claim that printed no bead id) are
# exercised by assets/scripts/work-context-hook.test.sh, and a pack without
# that test is a warning here. gascity merges the overlay's settings.json into
# the session's own settings, keying hook entries by matcher; the check reads
# the overlay's file and does not reproduce that merge. The stub answers in the
# JSON shapes gc prints today, so a change to those shapes is invisible here.
# A registered command that starts to need an environment variable or a gc
# read the probe does not provide fails here, and run.test.sh runs this check
# against the shipped tree, so that failure lands on the change that caused it.
#
# Read-only: everything it writes is under one mktemp dir it removes. No live
# gc, no store, no network. Exit 0=OK 1=Warning 2=Error. stdout: message, then
# "  - detail" lines.

set -u

dir="${GC_PACK_DIR:-.}"
AGENT="polecat"
# The GC_TEMPLATE a gc-toolkit polecat session carries.
TEMPLATE="gc-toolkit/gc-toolkit.$AGENT"
BEHAVIOR_TEST="assets/scripts/work-context-hook.test.sh"
# The work bead's description, as the stub below serves it.
MARKER="WORK-CONTEXT-PROBE"

errors=(); warnings=(); notes=()
detail() { local v; for v in "$@"; do printf '  - %s\n' "$v"; done; }

# --- 1. The overlay pack.toml puts on the polecat agent ----------------------
# overlay_dir is carried only on [[patches.agent]] stanzas (pack.toml: "agent.toml
# has no overlay key"). A value is read in either TOML quote style, and a
# trailing comment is ignored.
overlay=""
if [ ! -f "$dir/pack.toml" ]; then
    warnings+=("no pack.toml at $dir, so the polecat agent's overlay is unknown and nothing was run")
else
    overlay=$(awk -v agent="$AGENT" -v q="'" '
        function value(s,   v, c, i) {
            v = s; sub(/^[^=]*=[[:space:]]*/, "", v)
            c = substr(v, 1, 1)
            if (c != "\"" && c != q) return ""
            v = substr(v, 2); i = index(v, c)
            return i ? substr(v, 1, i - 1) : ""
        }
        function flush() { if (inblk && name == agent && ov != "") print ov; inblk = 0; name = ""; ov = "" }
        /^[[:space:]]*\[\[[[:space:]]*patches\.agent[[:space:]]*\]\]/ { flush(); inblk = 1; next }
        /^[[:space:]]*\[/                                            { flush(); next }
        inblk && /^[[:space:]]*name[[:space:]]*=/                    { name = value($0); next }
        inblk && /^[[:space:]]*overlay_dir[[:space:]]*=/             { ov = value($0); next }
        END { flush() }
    ' "$dir/pack.toml" | tail -n 1)
    overlay="${overlay#./}"; overlay="${overlay%/}"
    if [ -z "$overlay" ]; then
        errors+=("no [[patches.agent]] stanza named \"$AGENT\" in pack.toml carries an overlay_dir, so no hook is staged into polecat sessions")
    elif [ ! -d "$dir/$overlay" ]; then
        errors+=("the $AGENT agent's overlay_dir \"$overlay\" names no directory in the pack, so nothing is staged into polecat sessions")
        overlay=""
    fi
fi

# --- 2. What that overlay registers, run on a claim --------------------------
# Claude's matcher rules: "*", "" or no matcher matches every tool; a matcher
# of only letters, digits, _, -, spaces, commas and | is a list of exact tool
# names; anything else is a regular expression tested unanchored.
REGISTERED='
def runs_on_bash:
  (.matcher // "") as $m
  | if ($m | type) != "string" then false
    elif $m == "" or $m == "*" then true
    elif ($m | test("^[A-Za-z0-9_ ,|-]+$")) then any($m | splits("[|,]") | gsub("^ +| +$"; ""); . == "Bash")
    else (try ("Bash" | test($m)) catch false)
    end;
(.hooks.PostToolUse? // [])[]? | objects | select(runs_on_bash)
| .hooks[]? | objects | select((.type // "command") == "command")
| .command | strings | select(length > 0)
| (., "\u0000")'

if [ -n "$overlay" ]; then
    settings="$dir/$overlay/.claude/settings.json"
    if [ ! -f "$settings" ]; then
        errors+=("$overlay ships no .claude/settings.json, so Claude registers no hook in polecat sessions")
    elif ! command -v jq >/dev/null 2>&1; then
        warnings+=("jq is not on PATH, so the registered hook was not run. The hook needs jq as well, but a polecat's PATH may carry it where this one does not.")
    elif ! jq -e 'type == "object"' "$settings" >/dev/null 2>&1; then
        errors+=("$overlay/.claude/settings.json is not a JSON object, so Claude registers no hook from it")
    else
        cmds=()
        while IFS= read -r -d '' c; do cmds+=("$c"); done < <(jq -j "$REGISTERED" "$settings" 2>/dev/null)
        probe=""
        if [ "${#cmds[@]}" -eq 0 ]; then
            errors+=("$overlay/.claude/settings.json registers no PostToolUse command whose matcher matches the Bash tool, so nothing runs after a claim")
        elif ! probe=$(mktemp -d "${TMPDIR:-/tmp}/gctk-check-work-context-hook.XXXXXX" 2>/dev/null) || [ -z "$probe" ]; then
            warnings+=("could not create a temp dir, so the registered hook was not run")
        else
            trap 'rm -rf "$probe"' EXIT
            mkdir -p "$probe/work" "$probe/home/go/bin" "$probe/tmp"
            cp -R "$dir/$overlay/." "$probe/work/"
            cat > "$probe/home/go/bin/gc" <<'STUB'
#!/bin/sh
case "$1 $2 $3" in
    "bd show probe-step")         echo '[{"id":"probe-step","title":"probe step","description":"the claimed step bead, not the work bead","metadata":{"gc.root_bead_id":"probe-root"}}]' ;;
    "bd show probe-root")         echo '[{"id":"probe-root","title":"probe workflow root","metadata":{"gc.input_convoy_id":"probe-convoy"}}]' ;;
    "convoy status probe-convoy") echo '{"children":[{"id":"probe-work"}]}' ;;
    "bd show probe-work")         echo '[{"id":"probe-work","title":"probe work bead","description":"WORK-CONTEXT-PROBE: the work bead description"}]' ;;
    *) exit 1 ;;
esac
STUB
            chmod +x "$probe/home/go/bin/gc"
            # What `gc hook --claim --json` prints, as Claude hands it to the
            # hook: the Bash tool's response is an object, not a string.
            claim='{"schema_version":"1","ok":true,"command":"hook","action":"work","reason":"claimed","bead_id":"probe-step","assignee":"probe","route":"probe/probe.polecat"}'
            payload=$(jq -nc --arg out "$claim" '{session_id: "work-context-doctor-probe",
                hook_event_name: "PostToolUse", tool_name: "Bash",
                tool_input: {command: "gc hook --claim --json"},
                tool_response: {stdout: $out, stderr: "", interrupted: false, isImage: false}}')
            delivered=0; seen=(); n=0
            for c in "${cmds[@]}"; do
                n=$((n + 1))
                # The stub's directory leads PATH, and HOME points at it too, so
                # every gc the command or the hook resolves is the stub.
                out=$(cd "$probe/work" && printf '%s' "$payload" | env -i \
                    HOME="$probe/home" PATH="$probe/home/go/bin:$PATH" TMPDIR="$probe/tmp" \
                    GC_DIR="$probe/work" CLAUDE_PROJECT_DIR="$probe/work" \
                    GC_PROVIDER=claude GC_TEMPLATE="$TEMPLATE" \
                    sh -c "$c" 2>/dev/null)
                rc=$?
                # Claude reads one JSON object from a hook that exits 0.
                ctx=$(printf '%s' "$out" | jq -rs 'if length == 1 then (.[0].hookSpecificOutput? // {})
                    | select(.hookEventName? == "PostToolUse") | (.additionalContext? // "") | strings
                    else empty end' 2>/dev/null)
                if [ "$rc" -eq 0 ]; then
                    case "$ctx" in *"$MARKER"*) delivered=1; break ;; esac
                fi
                shown=$(printf '%s' "$out" | tr '\n' ' ')
                if [ -n "$shown" ]; then
                    seen+=("command $n of ${#cmds[@]} exited $rc and printed: ${shown:0:200}")
                else
                    seen+=("command $n of ${#cmds[@]} exited $rc and printed nothing")
                fi
            done
            if [ "$delivered" -eq 0 ]; then
                errors+=("a simulated claim of a formula step did not get the work bead's description back as PostToolUse additionalContext from what $overlay/.claude/settings.json registers for Bash, so a polecat's claim would receive no description, or the wrong bead's. Run $BEHAVIOR_TEST next: when it passes, the hook works and the registered command is not reaching it.")
                notes+=(${seen[@]+"${seen[@]}"})
            fi
            rm -rf "$probe"
        fi
    fi
fi

# --- 3. The hook's own behavior test still ships ----------------------------
[ -s "$dir/$BEHAVIOR_TEST" ] \
    || warnings+=("$BEHAVIOR_TEST is missing; it is the only test of the hook's role and provider gates, its once-per-session guard, its size cap and its claim-without-a-bead-id branch")

if [ "${#errors[@]}" -ne 0 ]; then
    echo "a polecat's claim would not receive its work bead's description: ${#errors[@]} finding(s)"
    detail "${errors[@]}"
    detail ${notes[@]+"${notes[@]}"}
    detail ${warnings[@]+"${warnings[@]}"}
    exit 2
fi
if [ "${#warnings[@]}" -ne 0 ]; then
    echo "work-bead description delivery not fully verified"
    detail "${warnings[@]}"
    exit 1
fi
echo "OK: a simulated polecat claim gets its work bead's description back from the PostToolUse hook $overlay registers for Bash"
exit 0
