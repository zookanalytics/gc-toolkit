#!/usr/bin/env bash
# Hermetic test for doctor/check-work-context-hook/run.sh.
#
# The check runs the PostToolUse hook the polecat agent's overlay registers, on
# a simulated claim, and errors when the work bead's description does not come
# back. This suite holds it to both directions:
#   - a change that stops a claim from delivering the description is an ERROR,
#     whether it breaks the hook or the wiring that reaches it;
#   - a change that still delivers is OK, including ones that rewrite the
#     hook's text: a different read of the claim, an unrelated `cut -c`, the
#     event name passed as a jq argument, a hook file without its executable
#     bit, a wider matcher, another TOML spelling, a renamed overlay.
# Where a case changes the hook itself, the hook's own behavior test
# (assets/scripts/work-context-hook.test.sh) runs on the same copy and must
# agree: it fails where the check errors and passes where the check passes.
# Every case must change its copy, so a substitution that matched nothing
# cannot read as a pass.
#
# Every case works on a throwaway copy of the shipped pack.toml, overlay and
# behavior test. No live city, Dolt, or network. Edits go through awk and jq,
# not `sed -i`, whose flags differ between BSD and GNU, and are written back
# with cat so each file keeps its mode.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
CHECK="$HERE/run.sh"
OVERLAY_REL="overlays/work-context"
HOOK_REL="$OVERLAY_REL/.claude/hooks/work-context.sh"
SET_REL="$OVERLAY_REL/.claude/settings.json"
TEST_REL="assets/scripts/work-context-hook.test.sh"

PASS=0; FAIL=0; N=0
ok()  { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n        %s\n' "$1" "$2"; }

command -v jq >/dev/null 2>&1 || { echo "FATAL: jq required" >&2; exit 1; }

SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/gctk-check-work-context-hook-test.XXXXXX")"
trap 'rm -rf "$SANDBOX"' EXIT

# A pristine copy of everything the check and the behavior test read.
mkpack() { # mkpack <dir>
    mkdir -p "$1/overlays" "$1/assets/scripts"
    cp "$REPO/pack.toml" "$1/pack.toml"
    cp -R "$REPO/$OVERLAY_REL" "$1/overlays/"
    cp "$REPO/$TEST_REL" "$1/$TEST_REL"
}

# Content and executable bit of every file, to prove a mutation changed something.
fingerprint() { # fingerprint <dir>
    (cd "$1" && find . -type f | LC_ALL=C sort | while IFS= read -r f; do
        printf '%s %s %s\n' "$f" "$(cksum < "$f")" "$([ -x "$f" ] && echo x || echo -)"
    done)
}

# Replace the line containing a literal substring with the text on stdin,
# keeping the file's mode.
replace_line() { # replace_line <file> <substring> <<'EOF' ... EOF
    local new; new="$(cat)"
    PAT="$2" NEW="$new" awk 'index($0, ENVIRON["PAT"]) { print ENVIRON["NEW"]; next } { print }' "$1" > "$1.new" \
        && cat "$1.new" > "$1" && rm -f "$1.new"
}

set_json() { # set_json <dir> <jq-program>
    local f="$1/$SET_REL"
    jq "$2" "$f" > "$f.new" && cat "$f.new" > "$f" && rm -f "$f.new"
}

# check_case <name> <want-exit> <behavior-test: pass|fail|-> <mutation>
check_case() {
    local name="$1" want="$2" behavior="$3" mutate="$4"
    N=$((N + 1))
    local d="$SANDBOX/case-$N" before out rc trc
    mkpack "$d"
    before="$(fingerprint "$d")"
    "$mutate" "$d"
    if [ "$mutate" != none ] && [ "$(fingerprint "$d")" = "$before" ]; then
        bad "$name" "the mutation changed nothing, so this case proves nothing"
        rm -rf "$d"; return
    fi
    out="$(GC_PACK_DIR="$d" bash "$CHECK" 2>&1)"; rc=$?
    if [ "$rc" -eq "$want" ]; then
        ok "$name: check exits $rc"
    else
        bad "$name: check exits $want" "got $rc: $(printf '%s' "$out" | head -4 | tr '\n' ' ')"
    fi
    if [ "$behavior" != - ]; then
        bash "$d/$TEST_REL" >/dev/null 2>&1; trc=$?
        if { [ "$behavior" = pass ] && [ "$trc" -eq 0 ]; } || { [ "$behavior" = fail ] && [ "$trc" -ne 0 ]; }; then
            ok "$name: the hook's behavior test agrees ($behavior)"
        else
            bad "$name: the hook's behavior test agrees ($behavior)" "it exited $trc"
        fi
    fi
    rm -rf "$d"
}

none() { :; }

# --- changes to the hook that stop delivery ---
rm_hook() { rm -f "$1/$HOOK_REL"; }
# The role gate reads the pool name instead of the role. A polecat's GC_AGENT
# is a person's name, so the gate never opens.
gate_on_agent() { replace_line "$1/$HOOK_REL" 'template="${GC_TEMPLATE:-}"' <<'EOF'
template="${GC_AGENT:-}"
EOF
}
# The claim arrives inside the Bash tool's response object, re-escaped by
# tojson; without the unescape the bead id is never found.
drop_unescape() { replace_line "$1/$HOOK_REL" 'else tojson end' <<'EOF'
  | if type == "string" then . else tojson end' 2>/dev/null)"
EOF
}
# The step is never resolved to its work bead.
skip_convoy() { replace_line "$1/$HOOK_REL" 'gc convoy status' <<'EOF'
    member="$(run_bounded gc convoy stat_us "$convoy" --json 2>/dev/null \
EOF
}
# The description is printed without the PostToolUse JSON envelope.
drop_envelope() { replace_line "$1/$HOOK_REL" '| jq -Rs' <<'EOF'
  | cat
EOF
}

# --- changes to the wiring that stop delivery ---
drop_post()   { set_json "$1" 'del(.hooks.PostToolUse)'; }
match_edit()  { set_json "$1" '.hooks.PostToolUse[0].matcher = "Edit"'; }
match_exact() { set_json "$1" '.hooks.PostToolUse[0].matcher = "Bashful, Edit"'; }
run_true()    { set_json "$1" '.hooks.PostToolUse[0].hooks[0].command = "true"'; }
# Still names work-context.sh, at a path the overlay does not stage it to.
wrong_path()  { set_json "$1" '.hooks.PostToolUse[0].hooks[0].command = "S=\"$HOME/.claude/hooks/work-context.sh\"; [ -f \"$S\" ] && sh \"$S\" || true"'; }
bad_json()    { printf '{"hooks": {' > "$1/$SET_REL"; }
unwire() { replace_line "$1/pack.toml" 'overlay_dir = "overlays/work-context"' <<'EOF'
# overlay_dir removed
EOF
}
# Swap the polecat and refinery overlays: the pack stays well-formed and the
# work-context overlay_dir line survives, on the wrong agent.
move_wiring() {
    awk '
      /^[[:space:]]*\[/ { blk = "" }
      /^[[:space:]]*name[[:space:]]*=/ { if (match($0, /"[^"]*"/)) blk = substr($0, RSTART + 1, RLENGTH - 2) }
      blk == "polecat"  && /overlay_dir = "overlays\/work-context"/  { sub(/work-context/, "cycle-recycle") }
      blk == "refinery" && /overlay_dir = "overlays\/cycle-recycle"/ { sub(/cycle-recycle/, "work-context") }
      { print }
    ' "$1/pack.toml" > "$1/pack.toml.new" && cat "$1/pack.toml.new" > "$1/pack.toml" && rm -f "$1/pack.toml.new"
    cp -R "$REPO/overlays/cycle-recycle" "$1/overlays/"
}

# --- undetermined or uncovered: WARNING ---
rm_test() { rm -f "$1/$TEST_REL"; }
rm_pack() { rm -f "$1/pack.toml"; }

# --- changes that still deliver ---
# settings.json runs the hook with `sh <path>`, so the mode bit is never read.
unexec() { chmod -x "$1/$HOOK_REL"; }
# Read the response object's stdout as a string, which needs no unescape.
read_stdout() { replace_line "$1/$HOOK_REL" 'else tojson end' <<'EOF'
  | if type == "string" then . else (.stdout // "") end' 2>/dev/null)"
EOF
}
# `cut -c` bounding the marker file name, nowhere near the description.
unrelated_cut() { replace_line "$1/$HOOK_REL" 'safe_key="$(printf' <<'EOF'
safe_key="$(printf '%s.%s' "$session" "$work" | tr -c 'A-Za-z0-9._-' '_' | cut -c 1-200)"
EOF
}
event_as_arg() { replace_line "$1/$HOOK_REL" '| jq -Rs' <<'EOF'
  | jq -Rs --arg event PostToolUse '{hookSpecificOutput: {hookEventName: $event, additionalContext: .}}' 2>/dev/null
EOF
}
match_any()   { set_json "$1" '.hooks.PostToolUse[0].matcher = "*"'; }
match_list()  { set_json "$1" '.hooks.PostToolUse[0].matcher = "Edit | Bash"'; }
match_regex() { set_json "$1" '.hooks.PostToolUse[0].matcher = "^Ba"'; }
quote_style() { replace_line "$1/pack.toml" 'overlay_dir = "overlays/work-context"' <<'EOF'
overlay_dir = './overlays/work-context/'   # single-quoted literal string
EOF
}
rename_overlay() {
    mv "$1/overlays/work-context" "$1/overlays/polecat-context"
    replace_line "$1/pack.toml" 'overlay_dir = "overlays/work-context"' <<'EOF'
overlay_dir = "overlays/polecat-context"
EOF
}

echo "── shipped tree ──"
check_case "pristine shipped artifacts"                           0 pass none

echo "── the hook stops delivering: ERROR ──"
check_case "hook deleted"                                         2 fail rm_hook
check_case "role gate reads GC_AGENT, not GC_TEMPLATE"            2 fail gate_on_agent
check_case "tojson unescape removed"                              2 fail drop_unescape
check_case "step never resolved to its work bead"                 2 fail skip_convoy
check_case "description printed without the JSON envelope"        2 fail drop_envelope

echo "── the wiring stops reaching the hook: ERROR ──"
check_case "PostToolUse registration removed"                     2 -    drop_post
check_case "PostToolUse matcher is Edit (PreToolUse Bash remains)" 2 -   match_edit
check_case "PostToolUse matcher lists Bashful, not Bash"          2 -    match_exact
check_case "PostToolUse command runs something else"             2 -    run_true
check_case "PostToolUse command names the hook at the wrong path" 2 -    wrong_path
check_case "overlay settings.json is not JSON"                    2 -    bad_json
check_case "pack.toml overlay_dir removed"                        2 -    unwire
check_case "overlay_dir moved off the polecat patch"              2 -    move_wiring

echo "── not verified or not covered: WARNING ──"
check_case "hook's behavior test deleted"                         1 -    rm_test
check_case "no pack.toml"                                         1 -    rm_pack

echo "── the hook still delivers: OK ──"
check_case "hook not executable"                                  0 pass unexec
check_case "claim read from the response's stdout, no unescape"   0 pass read_stdout
check_case "cut -c used away from the description"                0 pass unrelated_cut
check_case "event name passed to jq as --arg"                     0 pass event_as_arg
check_case "PostToolUse matcher is *"                             0 -    match_any
check_case "PostToolUse matcher lists Edit | Bash"                0 -    match_list
check_case "PostToolUse matcher is the regex ^Ba"                 0 -    match_regex
check_case "overlay_dir single-quoted, ./ and trailing /"         0 -    quote_style
check_case "overlay renamed, pack.toml following it"              0 -    rename_overlay

echo
echo "check-work-context-hook: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
