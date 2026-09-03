#!/usr/bin/env bash
# gh-origin-guard.test.sh — hermetic test for the shipped PreToolUse hook
# assets/scripts/gh-origin-guard.sh.
#
# The guard refuses an agent-typed `gh` write aimed at a repository the rig does
# not own. Both of its verdicts are quiet in production: an allowed call prints
# nothing, and a broken guard also prints nothing, so nothing at runtime tells
# "correctly stayed silent" apart from "stopped guarding". That is what this
# test exists to distinguish, in both directions — the deny cases prove it still
# refuses, and the allow cases prove it has not become a blanket refusal that
# would wedge the rig's own PR flow.
#
# It runs the SHIPPED script, never a copy. Hermetic: local git repositories
# with fabricated remote URLs, no network, no gh, no live city.
#
# Covered:
#   (1)  --repo at a third-party repository -> deny, for all five write verbs
#   (2)  --repo at the rig's own origin -> allow
#   (3)  implicit target (no --repo) inside the rig checkout -> allow
#   (4)  implicit target inside a THIRD-PARTY clone, GC_RIG_ROOT set -> deny.
#        This is the case an explicit-flag-only guard misses: gh resolves the
#        repository from the working directory, so the guard must too.
#   (5)  GH_REPO, inline and ambient, is a target like any other
#   (6)  --repo=X, -R X and -R=X spellings
#   (7)  read verbs (view/list/status/checkout) -> allow, at any repository
#   (8)  a write behind &&, ;, | or a subshell is still inspected
#   (9)  prose in --title/--body that contains "issue create" is not a target
#   (10) host is part of identity: same owner/name on another forge -> deny
#   (11) URL, scp and .git spellings of the same repository -> allow
#   (12) case differences do not change identity
#   (13) unresolvable rig origin + a write verb -> deny (fail closed)
#   (14) non-Bash tool, non-gh command, empty and malformed stdin -> silent
#   (15) every case exits 0, and every refusal is one valid JSON deny object

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/gh-origin-guard.sh"

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n        %s\n' "$1" "$2"; }

[ -s "$HOOK" ] || { echo "FATAL: missing hook script: $HOOK" >&2; exit 1; }
[ -x "$HOOK" ] || { echo "FATAL: hook script is not executable: $HOOK" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "FATAL: jq required" >&2; exit 1; }

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

# --- fixtures ------------------------------------------------------------
# Local repositories carrying fabricated origins. `git remote get-url` reads
# config only, so none of these URLs is ever contacted.
mkrepo() { # mkrepo <dir> <origin-url>
    mkdir -p "$1"
    git -C "$1" init -q 2>/dev/null
    git -C "$1" remote add origin "$2" 2>/dev/null
}
mkrepo "$SANDBOX/rig"    "git@github.com:zookanalytics/gc-toolkit.git"
mkrepo "$SANDBOX/third"  "https://github.com/get-convex/agent.git"
mkrepo "$SANDBOX/other"  "https://gitlab.example.com/zookanalytics/gc-toolkit.git"
mkdir -p "$SANDBOX/plain"          # a directory, deliberately not a repository
mkrepo "$SANDBOX/noremote" ""      # a repository with no usable origin
git -C "$SANDBOX/noremote" remote remove origin 2>/dev/null || true

# A city of two rigs, for the city-scope agents that carry no GC_RIG_ROOT. The
# second rig's origin sits outside the operator's org on purpose: it is the case
# an org-keyed rule would have broken, so the fixture keeps that honest.
mkrepo "$SANDBOX/city/rigs/gc-toolkit"      "git@github.com:zookanalytics/gc-toolkit.git"
mkrepo "$SANDBOX/city/rigs/shutupandlisten" "https://github.com/suandl/shutupandlisten.git"

RIG="$SANDBOX/rig"
OWN="github.com/zookanalytics/gc-toolkit"

# --- driver --------------------------------------------------------------
# GC_RIG_ROOT defaults to the rig fixture; GH_REPO defaults to unset. A case
# overrides either by assigning before the call and clearing after.
LAST_RC=0
run() { # run <cwd> <command> -> stdout of the hook
    local out
    out="$(jq -n --arg c "$2" --arg w "$1" \
              '{tool_name:"Bash", tool_input:{command:$c}, cwd:$w}' \
           | "$HOOK" 2>/dev/null)"
    LAST_RC=$?
    printf '%s' "$out"
}

# Every assertion below also asserts exit 0: a guard that fails must never take
# the session's Bash tool down with it.
denied() { # denied <label> <cwd> <command>
    local out; out="$(run "$2" "$3")"
    if [ "$LAST_RC" -ne 0 ]; then
        bad "$1" "exit $LAST_RC (must always exit 0)"; return
    fi
    if ! printf '%s' "$out" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1; then
        bad "$1" "expected a JSON deny, got: ${out:-<empty>}"; return
    fi
    ok "$1"
}

allowed() { # allowed <label> <cwd> <command>
    local out; out="$(run "$2" "$3")"
    if [ "$LAST_RC" -ne 0 ]; then
        bad "$1" "exit $LAST_RC (must always exit 0)"; return
    fi
    if [ -n "$out" ]; then
        bad "$1" "expected silence, got: $out"; return
    fi
    ok "$1"
}

export GC_RIG_ROOT="$RIG"
export GC_CITY_PATH="$SANDBOX/city"
unset GH_REPO || true

echo "gh-origin-guard"

# --- (1) the incident shape: an explicit third-party target --------------
echo "  -- write verbs at a third-party repository"
denied "issue create --repo third party"  "$RIG" "gh issue create --repo get-convex/agent --title 'Bug' --body 'x'"
denied "pr create --repo third party"     "$RIG" "gh pr create --repo get-convex/agent --title 'Fix' --body 'x'"
denied "issue comment --repo third party" "$RIG" "gh issue comment 353 --repo get-convex/agent --body 'ping'"
denied "pr comment --repo third party"    "$RIG" "gh pr comment 12 --repo get-convex/agent --body 'ping'"
denied "pr review --repo third party"     "$RIG" "gh pr review 12 --repo get-convex/agent --approve"

# --- (2)(3) the rig's own work must keep flowing -------------------------
echo "  -- the rig's own origin"
allowed "issue create at own origin"   "$RIG" "gh issue create --repo zookanalytics/gc-toolkit --title 'x' --body 'y'"
allowed "pr create at own origin"      "$RIG" "gh pr create --repo zookanalytics/gc-toolkit --base main --title 'x'"
allowed "pr comment at own origin"     "$RIG" "gh pr comment 587 --repo zookanalytics/gc-toolkit --body 'y'"
allowed "implicit target in rig cwd"   "$RIG" "gh pr create --base main --title 'x' --body 'y'"
allowed "implicit issue in rig cwd"    "$RIG" "gh issue create --title 'x' --body 'y'"

# --- (4) the implicit third-party target ---------------------------------
# gh with no --repo resolves against the working directory's remote, so an agent
# standing in a clone of someone else's repository sends there. A guard that
# only read the flag would wave this through.
echo "  -- implicit target resolved from the working directory"
denied "implicit issue in third-party clone" "$SANDBOX/third" "gh issue create --title 'Bug' --body 'x'"
denied "implicit pr in third-party clone"    "$SANDBOX/third" "gh pr create --title 'Fix' --body 'x'"

# --- (5) GH_REPO ---------------------------------------------------------
echo "  -- GH_REPO"
denied "inline GH_REPO at third party" "$RIG" "GH_REPO=get-convex/agent gh issue create --title 'x' --body 'y'"
allowed "inline GH_REPO at own origin" "$RIG" "GH_REPO=zookanalytics/gc-toolkit gh issue create --title 'x'"
GH_REPO="get-convex/agent"; export GH_REPO
denied "ambient GH_REPO at third party" "$RIG" "gh issue create --title 'x' --body 'y'"
unset GH_REPO

# --- (6) flag spellings --------------------------------------------------
echo "  -- flag spellings"
denied "--repo= form" "$RIG" "gh issue create --repo=get-convex/agent --title 'x'"
denied "-R form"      "$RIG" "gh issue create -R get-convex/agent --title 'x'"
denied "-R= form"     "$RIG" "gh issue create -R=get-convex/agent --title 'x'"

# --- (7) reads are untouched ---------------------------------------------
# The ruling covers sends. Research at a third-party repository stays available,
# and a guard that broke reads would be worse than the problem it solves.
echo "  -- read verbs"
allowed "issue view elsewhere"  "$RIG" "gh issue view 353 --repo get-convex/agent"
allowed "issue list elsewhere"  "$RIG" "gh issue list --repo get-convex/agent"
allowed "pr view elsewhere"     "$RIG" "gh pr view 12 --repo get-convex/agent"
allowed "pr diff elsewhere"     "$RIG" "gh pr diff 12 --repo get-convex/agent"
allowed "pr checkout elsewhere" "$RIG" "gh pr checkout 12 --repo get-convex/agent"
allowed "api read elsewhere"    "$RIG" "gh api repos/get-convex/agent/issues"
allowed "repo view elsewhere"   "$RIG" "gh repo view get-convex/agent"

# --- (8) the write is not always the first command -----------------------
echo "  -- compound commands"
denied "after &&"      "$RIG" "git push && gh pr create --repo get-convex/agent --title 'x'"
denied "after ;"       "$RIG" "cd /tmp; gh issue create --repo get-convex/agent --title 'x'"
denied "after a pipe"  "$RIG" "cat body.md | gh issue create --repo get-convex/agent --title 'x' --body-file -"
denied "in a subshell" "$RIG" "(gh issue create --repo get-convex/agent --title 'x')"
denied "second of two writes" "$RIG" "gh issue create --title 'ours' && gh issue create --repo get-convex/agent --title 'theirs'"

# --- (8b) a cd ahead of the write moves where it lands -------------------
# The hook payload reports the directory the session started the call in, but a
# cd earlier on the same line is where gh actually resolves its repository. A
# guard reading only the payload would clear a write into someone else's clone.
echo "  -- cd ahead of the write"
denied  "cd into a third-party clone"    "$RIG" "cd $SANDBOX/third && gh issue create --title 'x'"
denied  "cd into a non-repository"       "$RIG" "cd /tmp && gh issue create --title 'x'"
allowed "cd into our own checkout"       "$SANDBOX/plain" "cd $RIG && gh issue create --title 'x'"
allowed "relative cd into our checkout"  "$SANDBOX" "cd rig && gh issue create --title 'x'"
denied  "relative cd into a third party" "$SANDBOX" "cd third && gh issue create --title 'x'"
denied  "cd to an unexpandable path"     "$RIG" 'cd "$SOMEWHERE" && gh issue create --title x'
# An explicit target does not depend on the working directory either way.
allowed "cd elsewhere, own repo by flag" "$RIG" "cd $SANDBOX/third && gh issue create --repo zookanalytics/gc-toolkit --title 'x'"
denied  "cd home, third party by flag"   "$SANDBOX/third" "cd $RIG && gh issue create --repo get-convex/agent --title 'x'"

# --- (9) prose is not a target -------------------------------------------
# A --body or --title can contain anything, including text that reads like
# another command. Matching the verb by position rather than by search keeps
# these from becoming false refusals that teach agents to distrust the guard.
echo "  -- prose that looks like a command"
allowed "verb words inside a title" "$RIG" "gh issue create --title 'gh issue create fails on --repo get-convex/agent'"
allowed "verb words inside a body"  "$RIG" "gh pr comment 587 --body 'run gh pr review --repo get-convex/agent next'"
allowed "a plain echo"              "$RIG" "echo 'gh issue create --repo get-convex/agent'"
allowed "a grep for the verb"       "$RIG" "grep -rn 'gh issue create' assets/"
denied  "quoted third-party target"  "$RIG" "gh issue create --repo \"get-convex/agent\" --title 'x'"
allowed "quoted own target"          "$RIG" "gh issue create --repo \"zookanalytics/gc-toolkit\" --title 'x'"
denied  "third-party target after a prose body" "$RIG" "gh issue create --body 'see --repo zookanalytics/gc-toolkit' --repo get-convex/agent"

# --- (10)(11)(12) repository identity ------------------------------------
echo "  -- repository identity"
denied  "same owner/name, another forge" "$RIG" "gh issue create --repo gitlab.example.com/zookanalytics/gc-toolkit --title 'x'"
allowed "host-qualified own origin"      "$RIG" "gh issue create --repo github.com/zookanalytics/gc-toolkit --title 'x'"
allowed "url spelling of own origin"     "$RIG" "gh issue create --repo https://github.com/zookanalytics/gc-toolkit --title 'x'"
allowed ".git suffix on own origin"      "$RIG" "gh issue create --repo zookanalytics/gc-toolkit.git --title 'x'"
allowed "case differs from own origin"   "$RIG" "gh issue create --repo ZookAnalytics/GC-Toolkit --title 'x'"
allowed "own origin from an ssh remote"  "$SANDBOX/rig" "gh pr create --title 'x'"

# --- (13) the owned set, and failing closed ------------------------------
# A rig agent is measured against its OWN rig, narrowly: another rig in the same
# city is still someone else's repository for it.
echo "  -- the owned set"
denied "rig agent writing to another rig" "$RIG" "gh issue create --repo suandl/shutupandlisten --title 'x'"

# A city-scope agent carries no rig root and works across rigs, so every rig in
# the city is a legitimate target — including the one outside the operator's org,
# which is the case an org allowlist would have refused.
GC_RIG_ROOT=""; export GC_RIG_ROOT
allowed "city agent, first rig"        "$SANDBOX/city/rigs/gc-toolkit" "gh issue create --title 'x'"
allowed "city agent, out-of-org rig"   "$SANDBOX/city/rigs/shutupandlisten" "gh pr create --title 'x'"
allowed "city agent, rig named by flag" "$SANDBOX/plain" "gh issue create --repo suandl/shutupandlisten --title 'x'"
denied  "city agent, third-party clone" "$SANDBOX/third" "gh issue create --title 'x'"
denied  "city agent, third-party flag"  "$SANDBOX/city/rigs/gc-toolkit" "gh issue create --repo get-convex/agent --title 'x'"
denied  "city agent, no target at all"  "$SANDBOX/plain" "gh issue create --title 'x'"

# With neither a rig root nor a city there is nothing to prove ownership
# against, and an unprovable target is treated as someone else's.
GC_CITY_PATH="$SANDBOX/nocity"; export GC_CITY_PATH
denied "no rig, no city, explicit target" "$SANDBOX/plain" "gh issue create --repo get-convex/agent --title 'x'"
denied "no rig, no city, no repo at all"  "$SANDBOX/noremote" "gh issue create --title 'x'"
# The last resort is the working directory, so a lone checkout still works.
allowed "no rig, no city, cwd is a repo"  "$RIG" "gh issue create --title 'x'"
GC_CITY_PATH="$SANDBOX/city"; export GC_CITY_PATH
GC_RIG_ROOT="$RIG"; export GC_RIG_ROOT

# A resolvable owned set with an unresolvable target still refuses.
denied "own rig, target unresolvable" "$SANDBOX/plain" "gh issue create --title 'x'"

# --- (14) everything else stays silent -----------------------------------
echo "  -- non-events"
allowed "no gh at all"         "$RIG" "git status --short"
allowed "gh inside a word"     "$RIG" "echo highlight && echo right"
allowed "gh as a path"         "$RIG" "ls /usr/bin/gh"

non_bash="$(jq -n '{tool_name:"Read", tool_input:{file_path:"/tmp/x"}, cwd:"/tmp"}' | "$HOOK" 2>/dev/null)"; rc=$?
{ [ $rc -eq 0 ] && [ -z "$non_bash" ]; } \
    && ok "non-Bash tool is silent" || bad "non-Bash tool is silent" "rc=$rc out=${non_bash:-<empty>}"

empty="$(printf '' | "$HOOK" 2>/dev/null)"; rc=$?
{ [ $rc -eq 0 ] && [ -z "$empty" ]; } \
    && ok "empty stdin is silent" || bad "empty stdin is silent" "rc=$rc out=${empty:-<empty>}"

junk="$(printf 'not json at all' | "$HOOK" 2>/dev/null)"; rc=$?
{ [ $rc -eq 0 ] && [ -z "$junk" ]; } \
    && ok "malformed stdin is silent" || bad "malformed stdin is silent" "rc=$rc out=${junk:-<empty>}"

# --- (15) the refusal is well-formed and it teaches ----------------------
echo "  -- refusal shape"
REFUSAL="$(run "$RIG" "gh issue create --repo get-convex/agent --title 'x'")"
printf '%s' "$REFUSAL" | jq -e '.hookSpecificOutput.hookEventName == "PreToolUse"' >/dev/null 2>&1 \
    && ok "names the PreToolUse event" || bad "names the PreToolUse event" "$REFUSAL"
printf '%s' "$REFUSAL" | jq -e '.hookSpecificOutput.permissionDecisionReason | test("tk-k80q5m")' >/dev/null 2>&1 \
    && ok "points at the prepare-only path" || bad "points at the prepare-only path" "$REFUSAL"
printf '%s' "$REFUSAL" | jq -e '.hookSpecificOutput.permissionDecisionReason | test("get-convex/agent")' >/dev/null 2>&1 \
    && ok "names the repository it refused" || bad "names the repository it refused" "$REFUSAL"
printf '%s' "$REFUSAL" | jq -e ".hookSpecificOutput.permissionDecisionReason | test(\"$OWN\")" >/dev/null 2>&1 \
    && ok "names the origin it allows" || bad "names the origin it allows" "$REFUSAL"

# A body carrying quotes and newlines must not produce invalid JSON.
TRICKY="$(run "$RIG" 'gh issue create --repo get-convex/agent --body "he said \"no\"
and left"')"
printf '%s' "$TRICKY" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1 \
    && ok "quotes and newlines stay valid JSON" || bad "quotes and newlines stay valid JSON" "$TRICKY"

echo
printf 'gh-origin-guard: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
