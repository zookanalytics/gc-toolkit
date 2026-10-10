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
#   (5)  GH_REPO — inline, exported earlier on the line, or ambient — is a target
#   (6)  --repo/-R spellings: -R X, --repo=X, -R=X, attached -RX, and either
#        form standing before the noun as a global flag
#   (7)  read verbs (view/list/status/checkout) -> allow, at any repository
#   (8)  a write behind &&, ;, | or a subshell is still inspected, and a cd —
#        including one scoped inside a subshell — resolves where it really lands
#   (9)  prose in --title/--body that contains "issue create" is not a target
#   (10) host is part of identity: same owner/name on another forge -> deny
#   (11) URL, scp and .git spellings of the same repository -> allow
#   (12) case differences do not change identity
#   (13) unresolvable rig origin + a write verb -> deny (fail closed)
#   (14) non-Bash tool, non-gh command, empty and malformed stdin -> silent
#   (15) every case exits 0, and every refusal is one valid JSON deny object
#   (16) a repeated --repo/-R binds to its LAST value, matching gh
#   (17) GH_HOST — inline, exported, or ambient — selects the forge that
#        completes an unqualified owner/name
#   (18) env options and assignments ahead of the command are parsed, and -C
#        moves where an implicit write lands
#   (19) pushd moves the working directory as cd does; popd and stack rotations
#        resolve to no repository
#   (20) a rig root that is set but resolves no origin fails closed, it does not
#        widen to the city or the working directory
#   (21) a URL operand on issue/pr comment or pr review names the repository, so
#        an off-origin URL is refused with no --repo, and it wins over an owned
#        --repo the way gh does; a number, a branch or a URL inside a body is not
#        a target
#   (22) `gh issue new` and `gh pr new`, gh's aliases for create, are guarded
#   (23) wrapper options (`time -p`, `command --`, `exec -l`) still reach the
#        wrapped write; `command -v gh` is a lookup and stays unguarded
#   (24) a backslash-newline is a line continuation, so a noun or verb split
#        across lines is still read
#   (25) `gh api` with a writing method (POST/PATCH/PUT/DELETE, explicit via -X
#        or implicit when fields are added) is guarded off the endpoint path;
#        a run of shorthand flags such as -iX POST is read the way gh reads it;
#        {owner}/{repo} placeholders, and the older :owner/:repo, fill only the
#        owner and name, so the host stays the endpoint's and a concrete owner
#        or name beside one stays in the target; GET and graphql are left alone,
#        and an endpoint naming no repository is out of the guard's domain
#   (26) a post on our own repository — gh pr|issue comment, gh pr review, a
#        gh api write to a comment, reply or review endpoint, a graphql mutation
#        that posts — passes only when its body, inline or in a readable file,
#        carries the city's provenance mark; an approval or change request, an
#        editor body, standard input and a shell-built body are refused; a
#        reaction, dismissal, re-request or delete posts no body and passes; a
#        post inside a here-document body is not held to the mark, while the
#        origin rule still reads the body and the commands after it
#   (27) a call that names no repository is measured against the one gh picks
#        from the working directory's remotes, not against `origin`: the
#        remote marked by gh-resolved, else the first of upstream, github,
#        origin and the rest; a remote that names no repository is skipped, a
#        URL this guard cannot read for sure is not, and a choice that depends
#        on which forges gh is logged in to is refused

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/gh-origin-guard.sh"

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n        %s\n' "$1" "$2"; }

[ -s "$HOOK" ] || { echo "FATAL: missing hook script: $HOOK" >&2; exit 1; }
[ -x "$HOOK" ] || { echo "FATAL: hook script is not executable: $HOOK" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "FATAL: jq required" >&2; exit 1; }

SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/gctk-gh-origin-guard-test.XXXXXX")"
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
allowed "pr comment at own origin"     "$RIG" "gh pr comment 587 --repo zookanalytics/gc-toolkit --body 'y <!-- gc:city -->'"
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
# An `export GH_REPO=` earlier on the line reaches the later gh in the same
# shell, so it is the target even though it is not the inline prefix form. The
# last export wins, and an `unset` between it and the write clears it.
denied  "exported GH_REPO at third party"         "$RIG" "export GH_REPO=get-convex/agent; gh issue create --title 'x'"
denied  "exported GH_REPO via && at third party"  "$RIG" "export GH_REPO=get-convex/agent && gh pr create --title 'x'"
allowed "exported GH_REPO at own origin"          "$RIG" "export GH_REPO=zookanalytics/gc-toolkit; gh issue create --title 'x'"
denied  "re-exported GH_REPO, last value wins"    "$RIG" "export GH_REPO=zookanalytics/gc-toolkit; export GH_REPO=get-convex/agent; gh issue create --title 'x'"
allowed "exported then unset GH_REPO, cwd owned"   "$RIG" "export GH_REPO=get-convex/agent; unset GH_REPO; gh issue create --title 'x'"

# --- (5b) GH_HOST selects the forge --------------------------------------
# An unqualified owner/name is completed with the host gh would use, and GH_HOST
# chooses it — inline, exported earlier on the line, or ambient. The same
# owner/name on another forge is not our origin. Normalising against the hook's
# own environment instead read an off-forge write as one of ours.
echo "  -- GH_HOST"
denied  "inline GH_HOST to another forge"    "$RIG" "GH_HOST=gitlab.example.com gh issue create --repo zookanalytics/gc-toolkit --title 'x'"
allowed "inline GH_HOST github, own origin"  "$RIG" "GH_HOST=github.com gh issue create --repo zookanalytics/gc-toolkit --title 'x'"
denied  "exported GH_HOST to another forge"  "$RIG" "export GH_HOST=gitlab.example.com; gh issue create --repo zookanalytics/gc-toolkit --title 'x'"
denied  "GH_HOST beside an inline GH_REPO"   "$RIG" "GH_HOST=gitlab.example.com GH_REPO=zookanalytics/gc-toolkit gh issue create --title 'x'"
# An unset GH_HOST returns to the default forge, not the value it held.
allowed "exported then unset GH_HOST, own"   "$RIG" "export GH_HOST=gitlab.example.com; unset GH_HOST; gh issue create --repo zookanalytics/gc-toolkit --title 'x'"

# --- (6) flag spellings --------------------------------------------------
echo "  -- flag spellings"
denied "--repo= form" "$RIG" "gh issue create --repo=get-convex/agent --title 'x'"
denied "-R form"      "$RIG" "gh issue create -R get-convex/agent --title 'x'"
denied "-R= form"     "$RIG" "gh issue create -R=get-convex/agent --title 'x'"
# -R takes its value attached, with no space and no `=`. gh binds it, so the
# guard must read it too, in either position.
denied  "-R attached, after the verb"   "$RIG" "gh issue create -Rget-convex/agent --title 'x'"
denied  "-R attached, before the verb"  "$RIG" "gh -Rget-convex/agent issue create --title 'x'"
allowed "-R attached, own origin"       "$RIG" "gh issue create -Rzookanalytics/gc-toolkit --title 'x'"
# The split --repo/-R can stand before the noun as a global flag. Its value is
# not the noun, and skipping the flag without its value read the repository as
# the subcommand and cleared the write.
denied  "split --repo before the noun"          "$RIG" "gh --repo get-convex/agent issue create --title 'x'"
denied  "split -R before the noun"              "$RIG" "gh -R get-convex/agent issue create --title 'x'"
allowed "split --repo before the noun, own origin" "$RIG" "gh --repo zookanalytics/gc-toolkit issue create --title 'x'"
# gh binds a repeated --repo/-R to its LAST value: a command-level selector
# overrides a global one before the noun. Reading the first selector let an
# owned --repo shield an off-origin one standing after it.
denied  "conflicting --repo, last is third party"  "$RIG" "gh --repo zookanalytics/gc-toolkit issue create --repo get-convex/agent --title 'x'"
allowed "conflicting --repo, last is own origin"    "$RIG" "gh --repo get-convex/agent issue create --repo zookanalytics/gc-toolkit --title 'x'"
denied  "global -R own, command --repo third party" "$RIG" "gh -R zookanalytics/gc-toolkit issue create --repo get-convex/agent --title 'x'"

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

# --- (8c) a cd inside a subshell is scoped to it -------------------------
# A subshell runs with a copy of the cwd, so a cd inside `( )` does not move
# where a later command resolves. Both directions matter: the cd must not leak
# out to clear a third-party write, and it must not leak out to refuse an own
# one.
echo "  -- cd scoped inside a subshell"
denied  "subshell cd owned, real cwd third party" "$SANDBOX/third" "(cd $RIG); gh issue create --title 'x'"
allowed "subshell cd elsewhere, real cwd owned"   "$RIG" "(cd $SANDBOX/third); gh issue create --title 'x'"

# --- (8d) env carries options before the wrapped command -----------------
# env takes its own options and NAME=VALUE assignments ahead of the command.
# Skipping only the word `env` left an option like -i standing as the command,
# so the wrapped write was never reached. The assignments set the target the way
# an inline prefix does, -C moves where an implicit write lands, and an option
# taking a separate argument is stepped over rather than mistaken for the write.
echo "  -- env options ahead of the write"
denied  "env -i wraps a third-party write"  "$RIG" "env -i HOME=/h PATH=/b gh issue create --repo get-convex/agent --title 'x'"
allowed "env -i wraps an own write"         "$RIG" "env -i HOME=/h PATH=/b gh issue create --repo zookanalytics/gc-toolkit --title 'x'"
allowed "env with a bare assignment"        "$RIG" "env GH_REPO=zookanalytics/gc-toolkit gh issue create --title 'x'"
denied  "env sets GH_REPO to a third party" "$RIG" "env GH_REPO=get-convex/agent gh issue create --title 'x'"
denied  "env -C into a third-party clone"   "$RIG" "env -C $SANDBOX/third gh issue create --title 'x'"
denied  "env -u before a third-party write" "$RIG" "env -u GH_TOKEN gh issue create --repo get-convex/agent --title 'x'"

# --- (8e) pushd and popd move the working directory ----------------------
# pushd changes where an implicit gh write resolves the way cd does; following
# only cd measured the write against the directory the session started in. Its
# stack rotations and popd land somewhere this one-line scan cannot follow, so
# they resolve to no repository and an implicit write after one is refused.
echo "  -- pushd and popd"
denied  "pushd into a third-party clone"    "$RIG" "pushd $SANDBOX/third >/dev/null && gh issue create --title 'x'"
allowed "pushd into our own checkout"       "$SANDBOX/third" "pushd $RIG >/dev/null && gh issue create --title 'x'"
denied  "popd leaves the target unresolved" "$RIG" "pushd $SANDBOX/third >/dev/null; popd >/dev/null; gh issue create --title 'x'"

# --- (9) prose is not a target -------------------------------------------
# A --body or --title can contain anything, including text that reads like
# another command. Matching the verb by position rather than by search keeps
# these from becoming false refusals that teach agents to distrust the guard.
echo "  -- prose that looks like a command"
allowed "verb words inside a title" "$RIG" "gh issue create --title 'gh issue create fails on --repo get-convex/agent'"
allowed "verb words inside a body"  "$RIG" "gh pr comment 587 --body 'run gh pr review --repo get-convex/agent next <!-- gc:city -->'"
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

# A rig root that is set but resolves no origin is a BROKEN root, not a signal
# to look wider. It yields an empty owned set and fails closed, rather than
# falling through to the city or the working directory — otherwise a checkout of
# someone else's repository, reached through a broken rig, would authorize its
# own writes.
GC_RIG_ROOT="$SANDBOX/plain"; export GC_RIG_ROOT
denied "broken rig root, no fallthrough to city" "$SANDBOX/plain" "gh issue create --repo suandl/shutupandlisten --title 'x'"
denied "broken rig root, no fallthrough to cwd"  "$SANDBOX/third" "gh issue create --title 'x'"
GC_RIG_ROOT="$RIG"; export GC_RIG_ROOT

# --- (21) a URL operand names the repository -----------------------------
# gh issue comment, pr comment and pr review take {<number> | <url>}. Given a
# URL, gh reads the repository straight from it, so an off-origin URL with no
# --repo is a send to a third party. Ignoring the operand let that through.
echo "  -- URL operand names the repository"
denied  "issue comment url at third party" "$RIG" "gh issue comment https://github.com/get-convex/agent/issues/353 --body 'x'"
denied  "pr comment url at third party"    "$RIG" "gh pr comment https://github.com/get-convex/agent/pull/12 --body 'x'"
denied  "pr review url at third party"     "$RIG" "gh pr review https://github.com/get-convex/agent/pull/12 --request-changes --body 'x'"
allowed "issue comment url at own origin"  "$RIG" "gh issue comment https://github.com/zookanalytics/gc-toolkit/issues/1 --body 'x <!-- gc:city -->'"
allowed "pr comment url at own origin"     "$RIG" "gh pr comment https://github.com/zookanalytics/gc-toolkit/pull/12 --body 'x <!-- gc:city -->'"
# gh writes where the URL points even when --repo disagrees, so an owned --repo
# must not shield an off-origin URL.
denied  "off-origin url beats owned --repo" "$RIG" "gh pr comment https://github.com/get-convex/agent/pull/12 --repo zookanalytics/gc-toolkit --body 'x'"
# A number or a branch names no repository, so it resolves the way a flagless
# call does — against the working directory — and a URL sitting in a --body is
# prose, not the operand.
allowed "number operand resolves to cwd"   "$RIG" "gh pr comment 12 --body 'x <!-- gc:city -->'"
allowed "branch operand resolves to cwd"   "$RIG" "gh pr comment feature/x --body 'x <!-- gc:city -->'"
allowed "url in a body is not the target"  "$RIG" "gh pr comment 12 --body 'see https://github.com/get-convex/agent/pull/1 for context <!-- gc:city -->'"

# --- (22) issue new / pr new are create ----------------------------------
# gh exposes create as `issue new` and `pr new`. The whitelist named only
# create, so the aliases reached the same write unguarded.
echo "  -- issue new / pr new aliases"
denied  "issue new at third party"   "$RIG" "gh issue new --repo get-convex/agent --title 'x' --body 'y'"
denied  "pr new at third party"       "$RIG" "gh pr new --repo get-convex/agent --title 'x' --body 'y'"
allowed "issue new at own origin"     "$RIG" "gh issue new --repo zookanalytics/gc-toolkit --title 'x'"
allowed "pr new at own origin"        "$RIG" "gh pr new --repo zookanalytics/gc-toolkit --title 'x'"
allowed "issue new implicit own cwd"  "$RIG" "gh issue new --title 'x' --body 'y'"

# --- (23) wrapper options ahead of the write -----------------------------
# command/exec/time carry options of their own. Skipping only the bare word left
# `-p` or the `--` sentinel standing as the command, so the wrapped write was
# never reached. command -v looks the command up and runs nothing, so it is not
# a send and stays out of the guard.
echo "  -- wrapper options ahead of the write"
denied  "time -p wraps a third-party write"     "$RIG" "time -p gh issue create --repo get-convex/agent --title 'x'"
denied  "command -- wraps a third-party write"  "$RIG" "command -- gh issue create --repo get-convex/agent --title 'x'"
denied  "exec -l wraps a third-party write"     "$RIG" "exec -l gh issue create --repo get-convex/agent --title 'x'"
allowed "time -p wraps an own write"            "$RIG" "time -p gh issue create --repo zookanalytics/gc-toolkit --title 'x'"
allowed "command -- wraps an own write"         "$RIG" "command -- gh issue create --repo zookanalytics/gc-toolkit --title 'x'"
allowed "command -v gh is a lookup, not a send" "$RIG" "command -v gh issue create --repo get-convex/agent --title 'x'"

# --- (24) a backslash-newline is a line continuation ---------------------
# gh runs `gh issue \<newline>create ...` as one command. The lexer must delete
# the escaped newline; leaving it glued to the next token hides the noun or verb
# and an off-origin write on the far side of the split reads as a non-write.
echo "  -- backslash-newline continuations"
denied "continuation between gh and the noun" "$RIG" 'gh \
issue create --repo get-convex/agent --title x'
denied "continuation between noun and verb"   "$RIG" 'gh issue \
create --repo get-convex/agent --title x'
denied "continuation before issue comment"    "$RIG" 'gh issue \
comment 353 --repo get-convex/agent --body x'
denied "continuation before pr comment"       "$RIG" 'gh pr \
comment 12 --repo get-convex/agent --body x'
denied "continuation before pr review"        "$RIG" 'gh pr \
review 12 --repo get-convex/agent --approve'
allowed "continuation into an own write"      "$RIG" 'gh issue \
create --repo zookanalytics/gc-toolkit --title x'

# --- (25) gh api writes reach the same REST endpoints --------------------
# `gh api` with a writing method reaches issue/PR/comment creation the porcelain
# verbs cover. The method is explicit via -X/--method, else POST when fields are
# added and GET otherwise, the way gh resolves it. The repository is read from
# the endpoint path, not --repo. Reads and graphql stay untouched, and an
# endpoint that names no repository is out of the guard's domain.
echo "  -- gh api writes"
denied  "api POST issue at third party"          "$RIG" "gh api -X POST repos/get-convex/agent/issues -f title=x"
denied  "api --method POST at third party"       "$RIG" "gh api --method POST repos/get-convex/agent/issues"
allowed "api POST issue at own origin"           "$RIG" "gh api -X POST repos/zookanalytics/gc-toolkit/issues -f title=x"
# gh switches to POST when fields are added, so a fielded call with no -X writes.
denied  "api implicit POST (fields) third party" "$RIG" "gh api repos/get-convex/agent/issues -f title=x"
# An explicit GET keeps a fielded call a read, the way --method GET does in gh.
allowed "api explicit GET with fields"           "$RIG" "gh api --method GET repos/get-convex/agent/issues -f per_page=1"
denied  "api DELETE a third-party repo"          "$RIG" "gh api -X DELETE repos/get-convex/agent"
denied  "api PATCH a third-party issue"          "$RIG" "gh api -X PATCH repos/get-convex/agent/issues/1 -f state=closed"
allowed "api PATCH own issue"                     "$RIG" "gh api -X PATCH repos/zookanalytics/gc-toolkit/issues/1 -f state=closed"
# gh parses a single-dash token as a run of shorthand flags, so the boolean -i
# can lead a run that sets the method or adds a field, and a value flag in the
# run takes the next token as its value rather than leaving it as the endpoint.
denied  "api -X=POST at third party"             "$RIG" "gh api -X=POST repos/get-convex/agent/issues"
denied  "api -iX POST run at third party"        "$RIG" "gh api -iX POST repos/get-convex/agent/issues"
denied  "api -iXPOST run at third party"         "$RIG" "gh api -iXPOST repos/get-convex/agent/issues"
denied  "api -iftitle=x run implies POST"        "$RIG" "gh api -iftitle=x repos/get-convex/agent/issues"
denied  "api -iH run keeps the endpoint"         "$RIG" "gh api -iH Accept:x -X PATCH repos/get-convex/agent/issues/1"
allowed "api -iX POST run at own origin"         "$RIG" "gh api -iX POST repos/zookanalytics/gc-toolkit/issues"
allowed "api -iX GET run with fields is a read"  "$RIG" "gh api -iX GET repos/get-convex/agent/issues -f per_page=1"
# A leading slash and a full REST URL name the same repository; the api host
# (api.github.com, or HOST/api/v3) maps back to the forge host a remote names.
denied  "api POST leading-slash third party"     "$RIG" "gh api -X POST /repos/get-convex/agent/issues"
denied  "api POST full-url third party"          "$RIG" "gh api -X POST https://api.github.com/repos/get-convex/agent/issues"
allowed "api POST full-url own origin"           "$RIG" "gh api -X POST https://api.github.com/repos/zookanalytics/gc-toolkit/issues"
# {owner}/{repo} placeholders are filled from the working directory, the way gh
# fills them, so the same command writes wherever the cwd belongs.
allowed "api placeholder from own cwd"           "$RIG" "gh api -X POST repos/{owner}/{repo}/issues -f title=x"
denied  "api placeholder from third-party cwd"   "$SANDBOX/third" "gh api -X POST repos/{owner}/{repo}/issues -f title=x"
# gh fills the older :owner and :repo spellings the same way.
allowed "api :owner/:repo from own cwd"          "$RIG" "gh api -X POST repos/:owner/:repo/issues -f title=x"
denied  "api :owner/:repo from third-party cwd"  "$SANDBOX/third" "gh api -X POST repos/:owner/:repo/issues -f title=x"
denied  "api concrete owner beside :repo"        "$RIG" "gh api -X POST repos/get-convex/:repo/issues -f title=x"
# gh takes only the owner and the name from the repository it fills from. The
# host is the one the endpoint names: a full URL's own host, else the forge
# --hostname or GH_HOST selects. Filling the whole target from GH_REPO or the
# cwd would read a placeholder URL on another forge as our own origin.
denied  "api placeholder URL on another forge"   "$RIG" "gh api -X POST 'https://gitlab.example.com/api/v3/repos/{owner}/{repo}/issues' -f title=x"
denied  "api placeholder URL, GH_REPO own"       "$RIG" "GH_REPO=zookanalytics/gc-toolkit gh api -X POST 'https://gitlab.example.com/api/v3/repos/{owner}/{repo}/issues' -f title=x"
allowed "api placeholder URL on our forge"       "$RIG" "gh api -X POST 'https://api.github.com/repos/{owner}/{repo}/issues' -f title=x"
denied  "api placeholder URL, third-party cwd"   "$SANDBOX/third" "gh api -X POST 'https://api.github.com/repos/{owner}/{repo}/issues' -f title=x"
denied  "api placeholder, --hostname elsewhere"  "$RIG" "gh api --hostname gitlab.example.com -X POST 'repos/{owner}/{repo}/issues' -f title=x"
denied  "api placeholder, GH_HOST elsewhere"     "$RIG" "GH_HOST=gitlab.example.com GH_REPO=github.com/zookanalytics/gc-toolkit gh api -X POST 'repos/{owner}/{repo}/issues' -f title=x"
allowed "api placeholder, GH_REPO host unused"   "$RIG" "GH_REPO=gitlab.example.com/zookanalytics/gc-toolkit gh api -X POST 'repos/{owner}/{repo}/issues' -f title=x"
# A placeholder fills only its own slot, so a concrete owner or name beside one
# stays part of the target.
denied  "api concrete owner, placeholder name"   "$RIG" "gh api -X POST 'repos/get-convex/{repo}/issues' -f title=x"
denied  "api placeholder owner, concrete name"   "$RIG" "gh api -X POST 'repos/{owner}/agent/issues' -f title=x"
allowed "api own owner, placeholder name"        "$RIG" "gh api -X POST 'repos/zookanalytics/{repo}/issues' -f title=x"
# A placeholder with no GH_REPO and no checkout to fill it names nothing.
denied  "api placeholder with nothing to fill"   "$SANDBOX/plain" "gh api -X POST 'repos/{owner}/{repo}/issues' -f title=x"
# --hostname chooses the forge an unqualified endpoint resolves on.
denied  "api --hostname to another forge"        "$RIG" "gh api --hostname gitlab.example.com -X POST repos/zookanalytics/gc-toolkit/issues"
# A writing method whose endpoint names no repos/OWNER/REPO path resolves to
# nothing and is refused; graphql and non-repo endpoints are left alone by the
# origin rule (a graphql post is held to the mark, in section 26).
denied  "api POST a malformed repos path"        "$RIG" "gh api -X POST repos/zookanalytics"
allowed "api graphql mutation is left alone"     "$RIG" "gh api graphql -f query=mutation{x}"
allowed "api POST to a non-repo endpoint"        "$RIG" "gh api -X POST gists -f files=x"
allowed "api GET own repo detail is a read"      "$RIG" "gh api repos/zookanalytics/gc-toolkit"

# --- (26) a post on our own repository carries the city's mark ------------
# pr-facts.sh tells the city's own posts from feedback by the provenance mark
# pr-post.sh appends, not by the author, so an unmarked post under the city's
# login reads back as feedback and loops into rework. On an owned repository a
# post passes only when its body visibly carries the mark; the write-back's
# marker counts, as it does for pr-facts. The mark is read from the body or from
# a body file, never guessed at in a body the shell builds as the command runs.
echo "  -- unmarked posts on our own repository"
MARKED="$SANDBOX/marked.md";     printf 'Fixed on the branch.\n\n<!-- gc:city -->\n' > "$MARKED"
UNMARKED="$SANDBOX/unmarked.md"; printf 'Fixed on the branch.\n' > "$UNMARKED"
printf 'Fixed.\n\n<!-- gc:city -->\n' > "$RIG/reply.md"
printf '{"body":"plain"}\n' > "$SANDBOX/unmarked.json"
denied  "pr comment, unmarked body"                 "$RIG" "gh pr comment 5 --body 'Fixed on the branch.'"
allowed "pr comment, marked body"                   "$RIG" "gh pr comment 5 --body 'Fixed on the branch. <!-- gc:city -->'"
allowed "pr comment, the write-back marker"         "$RIG" "gh pr comment 5 --body 'Fixed. <!-- gc-writeback -->'"
denied  "issue comment, unmarked body"              "$RIG" "gh issue comment 5 --body 'Fixed on the branch.'"
denied  "pr comment by url, unmarked"               "$RIG" "gh pr comment https://github.com/zookanalytics/gc-toolkit/pull/5 -b 'x'"
allowed "pr comment, attached -b, marked"           "$RIG" "gh pr comment 5 -b'x <!-- gc:city -->'"
allowed "pr comment, -b= form, marked"              "$RIG" "gh pr comment 5 -b='x <!-- gc:city -->'"
allowed "pr comment, --body= form, marked"          "$RIG" "gh pr comment 5 --body='x <!-- gc:city -->'"
denied  "pr comment, the last body wins"            "$RIG" "gh pr comment 5 -b 'x <!-- gc:city -->' -b 'plain'"
denied  "pr comment, a shell-built body"            "$RIG" 'gh pr comment 5 --body "$(cat body.md)"'
denied  "pr comment, a variable body"               "$RIG" 'gh pr comment 5 --body "$BODY"'
allowed "pr comment, marked body file"              "$RIG" "gh pr comment 5 --body-file $MARKED"
allowed "pr comment, -F marked body file"           "$RIG" "gh pr comment 5 -F $MARKED"
allowed "pr comment, relative body file"            "$RIG" "gh pr comment 5 --body-file reply.md"
allowed "pr comment, relative body file after cd"   "$SANDBOX/plain" "cd $RIG && gh pr comment 5 --body-file=reply.md"
denied  "pr comment, unmarked body file"            "$RIG" "gh pr comment 5 --body-file $UNMARKED"
denied  "pr comment, a body file that is not there" "$RIG" "gh pr comment 5 --body-file $SANDBOX/nope.md"
denied  "pr comment, body from standard input"      "$RIG" "cat $MARKED | gh pr comment 5 --body-file -"
denied  "pr comment, editor body"                   "$RIG" "gh pr comment 5 --editor"
denied  "pr comment, browser body"                  "$RIG" "gh pr comment 5 -w"
denied  "pr comment, edit-last unmarked"            "$RIG" "gh pr comment 5 --edit-last --body 'plain'"
allowed "pr comment, delete-last posts nothing"     "$RIG" "gh pr comment 5 --delete-last --yes"
denied  "pr review, unmarked comment review"        "$RIG" "gh pr review 5 --comment --body 'looks fine'"
allowed "pr review, marked comment review"          "$RIG" "gh pr review 5 --comment --body 'looks fine <!-- gc:city -->'"
denied  "pr review, an approval"                    "$RIG" "gh pr review 5 --approve"
denied  "pr review, a marked change request"        "$RIG" "gh pr review 5 --request-changes --body 'x <!-- gc:city -->'"
denied  "pr review, -r in a shorthand run"          "$RIG" "gh pr review 5 -rb 'x <!-- gc:city -->'"
denied  "pr review, -a with a marked body"          "$RIG" "gh pr review 5 -a -b 'x <!-- gc:city -->'"
allowed "issue and pr create post no feedback"      "$RIG" "gh pr create --title 'x' --body 'plain'"
# gh api reaches the same comment and review endpoints.
denied  "api thread reply, unmarked"                "$RIG" "gh api repos/zookanalytics/gc-toolkit/pulls/5/comments/9/replies -f body=plain"
allowed "api thread reply, write-back marker"       "$RIG" "gh api repos/zookanalytics/gc-toolkit/pulls/5/comments/9/replies -f 'body=Fixed. <!-- gc-writeback -->'"
denied  "api comment edit, unmarked"                "$RIG" "gh api -X PATCH repos/zookanalytics/gc-toolkit/issues/comments/9 -f body=plain"
allowed "api comment edit, marked"                  "$RIG" "gh api --method PATCH repos/zookanalytics/gc-toolkit/issues/comments/9 --raw-field 'body=x <!-- gc:city -->'"
denied  "api conversation comment, unmarked"        "$RIG" "gh api repos/zookanalytics/gc-toolkit/issues/5/comments --field body=plain"
allowed "api conversation comment, marked file"     "$RIG" "gh api repos/zookanalytics/gc-toolkit/issues/5/comments -F body=@$MARKED"
denied  "api conversation comment, unmarked input"  "$RIG" "gh api repos/zookanalytics/gc-toolkit/issues/5/comments --input $SANDBOX/unmarked.json"
denied  "api review with no body"                   "$RIG" "gh api repos/zookanalytics/gc-toolkit/pulls/5/reviews -f event=APPROVE"
denied  "api placeholder reply, unmarked"           "$RIG" "gh api repos/{owner}/{repo}/pulls/5/comments/9/replies -f body=plain"
allowed "api reaction posts no body"                "$RIG" "gh api -X POST repos/zookanalytics/gc-toolkit/issues/comments/9/reactions -f content=eyes"
allowed "api dismissal posts no body"               "$RIG" "gh api -X PUT repos/zookanalytics/gc-toolkit/pulls/5/reviews/7/dismissals -f message=x"
allowed "api re-request posts no body"              "$RIG" "gh api -X POST repos/zookanalytics/gc-toolkit/pulls/5/requested_reviewers -f 'reviewers[]=x'"
allowed "api delete posts nothing"                  "$RIG" "gh api -X DELETE repos/zookanalytics/gc-toolkit/issues/comments/9"
allowed "api issue create is not a comment"         "$RIG" "gh api -X POST repos/zookanalytics/gc-toolkit/issues -f title=x -f body=plain"
denied  "api marked comment off origin is refused"  "$RIG" "gh api repos/get-convex/agent/issues/5/comments -f 'body=x <!-- gc:city -->'"
# A graphql mutation that posts names no repository; its body rides in a
# variable of any name, so any field carrying the mark counts. The mutation's
# name is held in a variable here: spelled as a call, the pack's bypass lint
# would read this test as a post.
MUT="addPullRequestReviewThreadReply"
GQL="mutation(\$t:ID!,\$b:String!){${MUT}(input:{pullRequestReviewThreadId:\$t,body:\$b}){clientMutationId}}"
denied  "graphql thread reply, unmarked"            "$RIG" "gh api graphql -f query='$GQL' -f t=PRRT_x -f b=plain"
allowed "graphql thread reply, marked"              "$RIG" "gh api graphql -f query='$GQL' -f t=PRRT_x -f 'b=Fixed. <!-- gc-writeback -->'"
allowed "graphql thread reply, marked body file"    "$RIG" "gh api graphql -f query='$GQL' -f t=PRRT_x -F b=@$MARKED"
allowed "graphql query is not a post"               "$RIG" "gh api graphql -f query='query{viewer{login}}'"
allowed "graphql resolve is not a post"             "$RIG" "gh api graphql -f query='mutation{resolveReviewThread(input:{threadId:\"x\"}){thread{id}}}'"
UREFUSAL="$(run "$RIG" "gh pr comment 5 --body 'plain'")"
printf '%s' "$UREFUSAL" | jq -e '.hookSpecificOutput.permissionDecisionReason | test("pr-post.sh")' >/dev/null 2>&1 \
    && ok "the refusal names pr-post.sh" || bad "the refusal names pr-post.sh" "$UREFUSAL"
printf '%s' "$UREFUSAL" | jq -e '.hookSpecificOutput.permissionDecisionReason | test("carries no city mark")' >/dev/null 2>&1 \
    && ok "…and says the body carries no mark" || bad "…and says the body carries no mark" "$UREFUSAL"
printf '%s' "$(run "$RIG" "gh pr review 5 --approve")" | jq -e '.hookSpecificOutput.permissionDecisionReason | test("never approves")' >/dev/null 2>&1 \
    && ok "an approval is refused for what it is" || bad "an approval is refused for what it is" "no 'never approves' in the reason"
rm -f "$RIG/reply.md"

# A here-document body is far more often text an agent is writing, a note or a
# doc that names these commands, than commands it runs, so a post found in one
# is not held to the mark. The origin rule still reads it, and quote state
# starts fresh on each side of a body, so the commands after one are still seen.
echo "  -- here-document bodies"
# lines <line>... — the lines joined into one command, so no line of a test
# command stands on a physical line of its own here, where the pack's bypass
# lint would read it as one.
lines() { local IFS=$'\n'; printf '%s' "$*"; }
BTK='`'
allowed "a body that names a post verb"           "$RIG" "$(lines "cat > notes.md <<'R'" "Post with ${BTK}gh pr comment${BTK}, never by hand." 'R')"
allowed "a body that spells out an unmarked post" "$RIG" "$(lines "cat > notes.md <<'R'" "Run ${BTK}gh pr comment 5 --body x${BTK} to see the refusal." 'R')"
allowed "a <<- body with a tab-indented end"      "$RIG" "$(lines 'cat > notes.md <<-R' "	${BTK}gh pr comment 5 --body x${BTK}" '	R' 'echo done')"
allowed "two bodies queued on one line"           "$RIG" "$(lines 'cat <<A >a; cat <<B >b' "${BTK}gh pr comment 5 --body x${BTK}" 'A' "${BTK}gh pr review 5 --approve${BTK}" 'B')"
allowed "a body naming a posting mutation"        "$RIG" "$(lines "cat > notes.md <<'R'" "gh api graphql -f query='mutation{${MUT}(input:{}){clientMutationId}}' -f b=plain" 'R')"
denied  "the origin rule still reads a body"      "$RIG" "$(lines "bash <<'EOF'" 'gh issue create --repo get-convex/agent --title x' 'EOF')"
denied  "a post after a body is held to the mark" "$RIG" "$(lines "cat > notes.md <<'R'" 'text' 'R' 'gh pr comment 5 --body plain')"
denied  "a quote in a body does not hide a post"  "$RIG" "$(lines "cat > notes.md <<'R'" "don't" 'R' 'gh pr comment 5 --body plain')"
allowed "…and a marked post after it passes"      "$RIG" "$(lines "cat > notes.md <<'R'" "don't" 'R' "gh pr comment 5 --body 'x <!-- gc:city -->'")"
denied  "a here-string opens no body"             "$RIG" "$(lines "cat <<< 'x'" 'gh pr comment 5 --body plain')"
denied  "<<EOF inside a quoted body is no opener" "$RIG" "$(lines 'gh pr comment 5 --body "see <<EOF here <!-- gc:city -->"' 'gh pr comment 6 --body plain')"

# --- (27) the working directory's repository is gh's choice ---------------
# gh does not read `origin` first. With no --repo and no GH_REPO it takes the
# remote `gh repo set-default` marked (remote.<name>.gh-resolved), else the
# first remote in the order upstream, github, origin, then the rest as git
# lists them. A clone whose origin is ours and whose upstream is someone else's
# therefore writes upstream, and a guard reading origin cleared that write.
echo "  -- the working directory's repository is gh's choice"
OURS_URL="git@github.com:zookanalytics/gc-toolkit.git"
THEIRS_URL="https://github.com/get-convex/agent.git"
FORK="$SANDBOX/fork"
mkrepo "$FORK" "$OURS_URL"
git -C "$FORK" remote add upstream "$THEIRS_URL"
denied  "origin ours, upstream theirs, no default: pr create" "$FORK" "gh pr create --title 'x' --body 'y'"
denied  "…issue create"                                       "$FORK" "gh issue create --title 'x' --body 'y'"
denied  "…a marked pr comment"                                "$FORK" "gh pr comment 5 --body 'x <!-- gc:city -->'"
denied  "…an api placeholder fill"                            "$FORK" "gh api -X POST 'repos/{owner}/{repo}/issues' -f title=x"
denied  "…reached by a cd"                                    "$RIG" "cd $FORK && gh issue create --title 'x'"
allowed "…an explicit --repo at our own origin"               "$FORK" "gh issue create --repo zookanalytics/gc-toolkit --title 'x'"
WREFUSAL="$(run "$FORK" "gh issue create --title 'x'")"
printf '%s' "$WREFUSAL" | jq -e '.hookSpecificOutput.permissionDecisionReason | test("github.com/get-convex/agent") and test("gh repo set-default")' >/dev/null 2>&1 \
    && ok "the refusal names upstream and how gh picked it" || bad "the refusal names upstream and how gh picked it" "$WREFUSAL"
XREFUSAL="$(run "$FORK" "gh issue create --repo get-convex/agent --title 'x'")"
printf '%s' "$XREFUSAL" | jq -e '.hookSpecificOutput.permissionDecisionReason | test("get-convex/agent") and (test("set-default") | not)' >/dev/null 2>&1 \
    && ok "an explicit target carries no note on gh's pick" || bad "an explicit target carries no note on gh's pick" "$XREFUSAL"
# gh repo set-default marks the remote gh writes to.
git -C "$FORK" config remote.origin.gh-resolved base
allowed "origin marked base: pr create"                       "$FORK" "gh pr create --title 'x' --body 'y'"
allowed "origin marked base: api placeholder fill"            "$FORK" "gh api -X POST 'repos/{owner}/{repo}/issues' -f title=x"
git -C "$FORK" config remote.origin.gh-resolved Base
denied  "a mark gh cannot read stops the call"                "$FORK" "gh issue create --title 'x'"
git -C "$FORK" config remote.origin.gh-resolved get-convex/agent
denied  "origin marked with someone else's OWNER/REPO"        "$FORK" "gh issue create --title 'x'"
git -C "$FORK" config --unset remote.origin.gh-resolved
git -C "$FORK" config remote.upstream.gh-resolved zookanalytics/gc-toolkit
allowed "upstream marked with our OWNER/REPO"                 "$FORK" "gh issue create --title 'x'"
git -C "$FORK" config remote.upstream.gh-resolved github.com/zookanalytics/gc-toolkit
allowed "…as HOST/OWNER/REPO"                                 "$FORK" "gh issue create --title 'x'"
git -C "$FORK" config remote.upstream.gh-resolved https://github.com/zookanalytics/gc-toolkit.git
allowed "…as a URL"                                           "$FORK" "gh issue create --title 'x'"
git -C "$FORK" config remote.upstream.gh-resolved base
denied  "upstream marked base"                                "$FORK" "gh issue create --title 'x'"
git -C "$FORK" config remote.origin.gh-resolved base
denied  "two marks: the first in gh's order wins"             "$FORK" "gh issue create --title 'x'"
# The order of the unmarked: upstream, github, origin, then the rest by name.
mkrepo "$SANDBOX/ghremote" "$OURS_URL"
git -C "$SANDBOX/ghremote" remote add github "$THEIRS_URL"
denied  "a remote named github comes before origin"           "$SANDBOX/ghremote" "gh issue create --title 'x'"
mkrepo "$SANDBOX/caps" "$OURS_URL"
git -C "$SANDBOX/caps" remote add Upstream "$THEIRS_URL"
denied  "a remote named Upstream ranks as upstream"           "$SANDBOX/caps" "gh issue create --title 'x'"
mkrepo "$SANDBOX/forkrem" "$OURS_URL"
git -C "$SANDBOX/forkrem" remote add fork "$THEIRS_URL"
allowed "origin comes before any other name"                  "$SANDBOX/forkrem" "gh issue create --title 'x'"
mkdir -p "$SANDBOX/rest1" "$SANDBOX/rest2"
git -C "$SANDBOX/rest1" init -q; git -C "$SANDBOX/rest1" remote add alpha "$OURS_URL"; git -C "$SANDBOX/rest1" remote add beta "$THEIRS_URL"
git -C "$SANDBOX/rest2" init -q; git -C "$SANDBOX/rest2" remote add alpha "$THEIRS_URL"; git -C "$SANDBOX/rest2" remote add beta "$OURS_URL"
allowed "the rest by name: ours first"                        "$SANDBOX/rest1" "gh issue create --title 'x'"
denied  "the rest by name: theirs first"                      "$SANDBOX/rest2" "gh issue create --title 'x'"
# gh's sort keeps that order among equal ranks for twelve remotes or fewer and
# can reorder a longer list, so a longer list is not resolved.
mkdir -p "$SANDBOX/many"; git -C "$SANDBOX/many" init -q
git -C "$SANDBOX/many" remote add a00 "$OURS_URL"
for n in 01 02 03 04 05 06 07 08 09 10 11; do git -C "$SANDBOX/many" remote add "a$n" "$THEIRS_URL"; done
allowed "twelve remotes keep the listed order"                "$SANDBOX/many" "gh issue create --title 'x'"
git -C "$SANDBOX/many" remote add a12 "$THEIRS_URL"
denied  "thirteen remotes are not resolved"                   "$SANDBOX/many" "gh issue create --title 'x'"
# gh skips a remote it reads no repository from, and reads the push URL when
# the fetch URL names none.
mkrepo "$SANDBOX/localup" "$OURS_URL"
git -C "$SANDBOX/localup" remote add upstream "/srv/mirror/agent.git"
allowed "an upstream at a local path is skipped"              "$SANDBOX/localup" "gh issue create --title 'x'"
git -C "$SANDBOX/localup" remote set-url --push upstream "$THEIRS_URL"
denied  "…unless its push URL names a repository"             "$SANDBOX/localup" "gh issue create --title 'x'"
mkrepo "$SANDBOX/deepup" "$OURS_URL"
git -C "$SANDBOX/deepup" remote add upstream "https://github.com/get-convex/agent/tree"
allowed "an upstream path that is not OWNER/REPO is skipped"  "$SANDBOX/deepup" "gh issue create --title 'x'"
mkrepo "$SANDBOX/slashup" "$OURS_URL"
git -C "$SANDBOX/slashup" remote add upstream "https://github.com/get-convex/agent/"
denied  "a trailing slash still names OWNER/REPO"             "$SANDBOX/slashup" "gh issue create --title 'x'"
# A URL this reading cannot be sure of is not skipped: gh decodes %61 to `a`
# and writes to get-convex/agent.
mkrepo "$SANDBOX/escup" "$OURS_URL"
git -C "$SANDBOX/escup" remote add upstream "https://github.com/get-convex/%61gent.git"
denied  "an upstream URL with an escape is not skipped"       "$SANDBOX/escup" "gh issue create --title 'x'"
# gh reads a URL that opens with // as naming a host.
mkrepo "$SANDBOX/dslashup" "$OURS_URL"
git -C "$SANDBOX/dslashup" remote add upstream "//github.com/get-convex/agent.git"
denied  "an upstream //host/path is not skipped"              "$SANDBOX/dslashup" "gh issue create --title 'x'"
# gh skips a URL whose port is not a number, so a remote naming our repository
# behind one does not clear a write that gh sends to the next remote.
mkrepo "$SANDBOX/portours" "$THEIRS_URL"
git -C "$SANDBOX/portours" remote add upstream "https://github.com:abc/zookanalytics/gc-toolkit.git"
denied  "our repository behind a bad port is not read as ours" "$SANDBOX/portours" "gh issue create --title 'x'"
# gh drops www. from a remote's host, so www.github.com is github.com.
mkrepo "$SANDBOX/wwwup" "$OURS_URL"
git -C "$SANDBOX/wwwup" remote add upstream "https://www.github.com/get-convex/agent.git"
printf '%s' "$(run "$SANDBOX/wwwup" "gh issue create --title 'x'")" | jq -e '.hookSpecificOutput.permissionDecisionReason | test("aimed at github.com/get-convex/agent")' >/dev/null 2>&1 \
    && ok "an upstream on www.github.com is github.com" || bad "an upstream on www.github.com is github.com" "not refused as github.com/get-convex/agent"
# gh drops only a lowercase www., before it lowercases the host, so it reads a
# remote on WWW.github.com as on the forge www.github.com. Logged in to
# github.com alone, gh passes over that remote and writes to the next one.
mkrepo "$SANDBOX/wwwcaps" "$THEIRS_URL"
git -C "$SANDBOX/wwwcaps" remote add upstream "https://WWW.github.com/zookanalytics/gc-toolkit.git"
denied  "our repository on WWW.github.com is not read as ours" "$SANDBOX/wwwcaps" "gh issue create --title 'x'"
# gh reads the remote name in a gh-resolved key as the text between its first
# two dots, so a mark on my.fork marks the remote named my.
mkrepo "$SANDBOX/dotted" "$OURS_URL"
git -C "$SANDBOX/dotted" remote add my "$THEIRS_URL"
git -C "$SANDBOX/dotted" remote add my.fork "$OURS_URL"
git -C "$SANDBOX/dotted" config remote.my.fork.gh-resolved base
denied  "a mark on my.fork marks the remote my"               "$SANDBOX/dotted" "gh issue create --title 'x'"
# gh narrows the remotes by forge, using the hosts it is logged in to, or
# GH_HOST alone. The guard does not read that configuration, so a remote on
# another forge that would change the choice leaves it unresolved.
mkrepo "$SANDBOX/labup" "$OURS_URL"
git -C "$SANDBOX/labup" remote add upstream "https://gitlab.example.com/get-convex/agent.git"
denied  "an upstream on another forge leaves it open"         "$SANDBOX/labup" "gh issue create --title 'x'"
mkrepo "$SANDBOX/labfork" "$OURS_URL"
git -C "$SANDBOX/labfork" remote add fork "https://gitlab.example.com/get-convex/agent.git"
allowed "a remote on another forge that ranks after origin"   "$SANDBOX/labfork" "gh issue create --title 'x'"
# The same holds when the remote on the other forge is the one we own: gh, not
# logged in there, would skip it and write to origin.
mkrepo "$SANDBOX/labours" "$THEIRS_URL"
git -C "$SANDBOX/labours" remote add upstream "https://gitlab.example.com/zookanalytics/gc-toolkit.git"
GC_RIG_ROOT="$SANDBOX/other"; export GC_RIG_ROOT
denied  "our remote on another forge does not clear the write" "$SANDBOX/labours" "gh issue create --title 'x'"
GC_RIG_ROOT="$RIG"; export GC_RIG_ROOT
denied  "GH_HOST elsewhere leaves no remote to choose"        "$RIG" "GH_HOST=gitlab.example.com gh issue create --title 'x'"
denied  "an exported GH_HOST elsewhere, the same"             "$RIG" "export GH_HOST=gitlab.example.com; gh issue create --title 'x'"
# gh api --hostname sends the request to another forge, but the remotes are
# narrowed by GH_HOST alone, so the placeholders still fill from our checkout.
mkrepo "$SANDBOX/ghe" "https://ghe.example.com/zookanalytics/gc-toolkit.git"
GC_RIG_ROOT="$SANDBOX/ghe"; export GC_RIG_ROOT
allowed "api --hostname fills from the default forge's remote" "$RIG" "gh api --hostname ghe.example.com -X POST 'repos/{owner}/{repo}/issues' -f title=x"
GC_RIG_ROOT="$RIG"; export GC_RIG_ROOT

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
