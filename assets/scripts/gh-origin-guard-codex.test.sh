#!/usr/bin/env bash
# gh-origin-guard-codex.test.sh — hermetic test for
# assets/scripts/gh-origin-guard-codex.sh, which registers the gh origin guard
# in the Codex home's hooks.json for every codex-provider agent.
#
# The registration is the only thing standing between a Codex session and an
# unguarded gh write, and a missing one is silent: the session runs, and its
# writes simply go unmeasured. So this test holds the installer to what it
# promises, in both directions: it registers the overlay's own group, it keeps
# whatever else the file holds, it does not churn a registration that is
# already current, and it refuses, loudly and without writing, when it cannot
# register.
#
# It runs the SHIPPED installer against scratch Codex homes. Hermetic: no codex,
# no network, no live Codex home.
#
# Covered:
#   (1) an absent hooks file is created holding the overlay's PreToolUse group
#       for Bash, verbatim, so Codex runs the command every Claude overlay runs
#   (2) a current registration is left alone: a second run rewrites nothing
#   (3) other events and other PreToolUse groups are kept, in order, and the
#       guard's group is appended after them
#   (4) a guard handler in an older form is replaced, not duplicated: a group
#       left empty is dropped, and a group shared with another handler keeps it
#   (5) a current group followed by others is left where it stands; two copies
#       collapse to one
#   (6) a file that is not a hooks document, or a PreToolUse that is not a
#       list, is refused with exit 1 and left byte-identical
#   (7) the Codex home is $CODEX_HOME, else ~/.codex, created when absent
#   (8) an overlay with no guard group, or a missing jq, is refused with exit 1
#       and nothing written

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
INSTALL="$HERE/gh-origin-guard-codex.sh"
OVERLAY="$REPO/overlays/gh-origin-guard/.claude/settings.json"

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n        %s\n' "$1" "$2"; }

[ -x "$INSTALL" ] || { echo "FATAL: installer missing or not executable: $INSTALL" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "FATAL: jq required" >&2; exit 1; }

SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/gctk-gh-origin-guard-codex-test.XXXXXX")"
trap 'rm -rf "$SANDBOX"' EXIT

GROUP="$(jq -c '[.hooks.PreToolUse[] | select(.matcher == "Bash")
                 | select(any(.hooks[]; .command | contains("gh-origin-guard.sh")))] | first' "$OVERLAY")"
GUARD_CMD="$(printf '%s' "$GROUP" | jq -r '.hooks[0].command')"
[ -n "$GUARD_CMD" ] && [ "$GUARD_CMD" != null ] \
    || { echo "FATAL: the overlay registers no guard group: $OVERLAY" >&2; exit 1; }

RC=0
install_into() { # install_into <codex home> — runs the installer, sets RC
    CODEX_HOME="$1" "$INSTALL" >/dev/null 2>"$SANDBOX/stderr"
    RC=$?
}
inode() { ls -i "$1" 2>/dev/null | awk '{ print $1 }'; }
guard_count() { # the guard handlers in a hooks file, wherever they stand
    jq '[.hooks.PreToolUse[]?.hooks[]? | select(.command | contains("gh-origin-guard.sh"))] | length' "$1"
}

echo "gh-origin-guard-codex"

# --- (1) a fresh Codex home ---------------------------------------------
echo "  -- a fresh Codex home"
H="$SANDBOX/fresh"
mkdir -p "$H"
install_into "$H"
[ "$RC" -eq 0 ] && ok "registers into an absent file" || bad "registers into an absent file" "rc=$RC $(cat "$SANDBOX/stderr")"
if jq -e --argjson g "$GROUP" '. == {hooks: {PreToolUse: [$g]}}' "$H/hooks.json" >/dev/null 2>&1; then
    ok "the file holds the overlay's group, verbatim"
else
    bad "the file holds the overlay's group, verbatim" "$(cat "$H/hooks.json" 2>/dev/null)"
fi
[ "$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$H/hooks.json")" = "$GUARD_CMD" ] \
    && ok "Codex runs the command the Claude overlays run" \
    || bad "Codex runs the command the Claude overlays run" "$(jq -c . "$H/hooks.json")"

# --- (2) idempotent -----------------------------------------------------
before="$(inode "$H/hooks.json")"
install_into "$H"
after="$(inode "$H/hooks.json")"
{ [ "$RC" -eq 0 ] && [ -n "$before" ] && [ "$before" = "$after" ]; } \
    && ok "a current registration is not rewritten" \
    || bad "a current registration is not rewritten" "rc=$RC inode $before -> $after"

# --- (3) the rest of the file is kept -----------------------------------
echo "  -- the rest of the file"
H="$SANDBOX/shared"
mkdir -p "$H"
cat > "$H/hooks.json" <<'JSON'
{
  "description": "operator hooks",
  "hooks": {
    "SessionStart": [{"matcher": "startup", "hooks": [{"type": "command", "command": "echo hello"}]}],
    "PreToolUse": [
      {"matcher": "Bash", "hooks": [{"type": "command", "command": "audit-bash"}]},
      {"matcher": "apply_patch", "hooks": [{"type": "command", "command": "audit-patch"}]}
    ]
  }
}
JSON
install_into "$H"
[ "$RC" -eq 0 ] && ok "extends a file the operator keeps" || bad "extends a file the operator keeps" "rc=$RC $(cat "$SANDBOX/stderr")"
jq -e --argjson g "$GROUP" '
    .description == "operator hooks"
    and .hooks.SessionStart[0].hooks[0].command == "echo hello"
    and (.hooks.PreToolUse | length) == 3
    and .hooks.PreToolUse[0].hooks[0].command == "audit-bash"
    and .hooks.PreToolUse[1].hooks[0].command == "audit-patch"
    and .hooks.PreToolUse[2] == $g' "$H/hooks.json" >/dev/null 2>&1 \
    && ok "keeps other events and groups, guard appended last" \
    || bad "keeps other events and groups, guard appended last" "$(jq -c . "$H/hooks.json")"

# --- (4) an older form is replaced --------------------------------------
echo "  -- an older registration"
H="$SANDBOX/stale"
mkdir -p "$H"
cat > "$H/hooks.json" <<'JSON'
{"hooks": {"PreToolUse": [
  {"matcher": "Bash", "hooks": [{"type": "command", "command": "sh /old/assets/scripts/gh-origin-guard.sh"}]},
  {"matcher": "Bash", "hooks": [
    {"type": "command", "command": "audit-bash"},
    {"type": "command", "command": "exec sh /older/gh-origin-guard.sh"}]}
]}}
JSON
install_into "$H"
[ "$RC" -eq 0 ] && ok "replaces an older form" || bad "replaces an older form" "rc=$RC $(cat "$SANDBOX/stderr")"
[ "$(guard_count "$H/hooks.json")" = 1 ] \
    && ok "leaves one guard handler" || bad "leaves one guard handler" "$(jq -c . "$H/hooks.json")"
jq -e --argjson g "$GROUP" '
    (.hooks.PreToolUse | length) == 2
    and .hooks.PreToolUse[0] == {matcher: "Bash", hooks: [{type: "command", command: "audit-bash"}]}
    and .hooks.PreToolUse[1] == $g' "$H/hooks.json" >/dev/null 2>&1 \
    && ok "drops an emptied group, keeps a shared one's other handler" \
    || bad "drops an emptied group, keeps a shared one's other handler" "$(jq -c . "$H/hooks.json")"

# --- (5) where a current group stands -----------------------------------
H="$SANDBOX/placed"
mkdir -p "$H"
jq -n --argjson g "$GROUP" '{hooks: {PreToolUse: [$g, {matcher: "Bash", hooks: [{type: "command", command: "audit-bash"}]}]}}' > "$H/hooks.json"
before="$(inode "$H/hooks.json")"
install_into "$H"
after="$(inode "$H/hooks.json")"
{ [ "$RC" -eq 0 ] && [ "$before" = "$after" ]; } \
    && ok "a current group followed by others stays put" \
    || bad "a current group followed by others stays put" "rc=$RC $(jq -c . "$H/hooks.json")"

H="$SANDBOX/twice"
mkdir -p "$H"
jq -n --argjson g "$GROUP" '{hooks: {PreToolUse: [$g, $g]}}' > "$H/hooks.json"
install_into "$H"
{ [ "$RC" -eq 0 ] && [ "$(guard_count "$H/hooks.json")" = 1 ]; } \
    && ok "two copies collapse to one" || bad "two copies collapse to one" "rc=$RC $(jq -c . "$H/hooks.json")"

# --- (6) what it will not overwrite -------------------------------------
echo "  -- refusals"
refused_untouched() { # refused_untouched <label> <file contents>
    local h="$SANDBOX/refuse.$PASS.$FAIL"
    mkdir -p "$h"
    printf '%s' "$2" > "$h/hooks.json"
    install_into "$h"
    if [ "$RC" -ne 1 ]; then bad "$1" "rc=$RC (want 1)"; return; fi
    if [ "$(cat "$h/hooks.json")" != "$2" ]; then bad "$1" "the file was changed"; return; fi
    grep -Fq "$h/hooks.json" "$SANDBOX/stderr" || { bad "$1" "stderr names no file: $(cat "$SANDBOX/stderr")"; return; }
    ok "$1"
}
refused_untouched "refuses a file that is not JSON"          '{"hooks": {'
refused_untouched "refuses a JSON document that is a list"   '[1, 2]'
refused_untouched "refuses hooks that are not an object"     '{"hooks": []}'
refused_untouched "refuses a PreToolUse that is not a list"  '{"hooks": {"PreToolUse": {"g": {"matcher": "Bash", "hooks": []}}}}'

# --- (7) which Codex home -----------------------------------------------
echo "  -- the Codex home"
FAKE_HOME="$SANDBOX/home"
mkdir -p "$FAKE_HOME"
(unset CODEX_HOME; HOME="$FAKE_HOME" "$INSTALL" >/dev/null 2>&1); rc=$?
{ [ "$rc" -eq 0 ] && [ "$(guard_count "$FAKE_HOME/.codex/hooks.json" 2>/dev/null)" = 1 ]; } \
    && ok "with no CODEX_HOME, ~/.codex is the home" || bad "with no CODEX_HOME, ~/.codex is the home" "rc=$rc"
install_into "$SANDBOX/not/yet/made"
{ [ "$RC" -eq 0 ] && [ -s "$SANDBOX/not/yet/made/hooks.json" ]; } \
    && ok "creates a Codex home that does not exist" || bad "creates a Codex home that does not exist" "rc=$RC"

# --- (8) nothing to register --------------------------------------------
echo "  -- nothing to register"
T="$SANDBOX/tree"
mkdir -p "$T/assets/scripts" "$T/overlays/gh-origin-guard/.claude"
cp "$INSTALL" "$T/assets/scripts/"
printf '{"hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "true"}]}]}}' \
    > "$T/overlays/gh-origin-guard/.claude/settings.json"
CODEX_HOME="$SANDBOX/nogroup" "$T/assets/scripts/gh-origin-guard-codex.sh" >/dev/null 2>&1; rc=$?
{ [ "$rc" -eq 1 ] && [ ! -e "$SANDBOX/nogroup/hooks.json" ]; } \
    && ok "an overlay with no guard group is refused" || bad "an overlay with no guard group is refused" "rc=$rc"

BIN="$SANDBOX/bin"
mkdir -p "$BIN"
for t in dirname cat mkdir mktemp mv rm; do ln -s "$(command -v "$t")" "$BIN/$t"; done
CODEX_HOME="$SANDBOX/nojq" PATH="$BIN" "$INSTALL" >/dev/null 2>&1; rc=$?
{ [ "$rc" -eq 1 ] && [ ! -e "$SANDBOX/nojq/hooks.json" ]; } \
    && ok "a missing jq is refused" || bad "a missing jq is refused" "rc=$rc"

echo
printf 'gh-origin-guard-codex: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
