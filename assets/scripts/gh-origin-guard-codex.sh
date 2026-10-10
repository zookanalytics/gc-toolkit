#!/bin/sh
# gh-origin-guard-codex.sh — register gh-origin-guard.sh as a Codex PreToolUse
# hook in the Codex home's hooks.json, the one hooks file every Codex session
# reads whatever directory it runs in.
#
# Codex reads a project's hooks from <project root>/.codex/hooks.json, and for a
# linked git worktree the project root is the repository's main checkout, so a
# hooks file staged into an agent's worktree is never read. polecat-codex and
# converse-codex run in worktrees. The Codex home is read by every session, so
# the guard is registered there (docs/gh-origin-guard.md, "Codex").
#
# Codex sends a shell call in the payload shape Claude does and reads the same
# deny object back, so the registration is the gh-origin-guard overlay's own
# PreToolUse group for Bash, copied verbatim: one command for both providers.
#
# Every codex-provider agent runs this as pre_start. It is idempotent: a
# registration already in the current form is left alone, so the trust Codex
# keys to the hook's position and content survives restarts. A registration in
# an older form is replaced, and everything else in the file is kept.
#
# The Codex home is $CODEX_HOME, else ~/.codex, the way Codex resolves it.
#
# exit: 0 the guard is registered · 1 it could not be, and the session must not
# start unguarded (a failed pre_start aborts the start)

set -u

HERE=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd) || exit 1
OVERLAY="$HERE/../../overlays/gh-origin-guard/.claude/settings.json"

fail() {
    printf 'gh-origin-guard-codex: %s\n' "$1" >&2
    exit 1
}

command -v jq >/dev/null 2>&1 || fail "jq is required to register the guard"

GROUP=$(jq -c '
    [ .hooks.PreToolUse[]?
      | select(.matcher == "Bash")
      | select(any(.hooks[]?; (.command // "") | contains("gh-origin-guard.sh"))) ]
    | first // empty' "$OVERLAY" 2>/dev/null)
[ -n "$GROUP" ] || fail "no PreToolUse group for Bash naming gh-origin-guard.sh in $OVERLAY"

CODEX_DIR=${CODEX_HOME:-${HOME:-}/.codex}
[ -n "${CODEX_HOME:-}${HOME:-}" ] || fail "neither CODEX_HOME nor HOME is set, so there is no Codex home"
FILE="$CODEX_DIR/hooks.json"

CURRENT='{}'
if [ -e "$FILE" ]; then
    CURRENT=$(cat -- "$FILE") || fail "cannot read $FILE"
fi

# Our handlers are the ones naming gh-origin-guard.sh. When they amount to the
# current group, standing alone, the document is left as it is. Otherwise they
# are removed wherever they stand, a group left empty is dropped, and the
# current group is appended after everything else. A file that is not a hooks
# document stops the transform, and is not overwritten: it may be the
# operator's, and Codex cannot load hooks from it either.
NEXT=$(printf '%s' "$CURRENT" | jq --argjson g "$GROUP" '
    def ours: (.command // "") | contains("gh-origin-guard.sh");
    if type != "object" or ((.hooks // {}) | type) != "object"
       or ((.hooks.PreToolUse // []) | type) != "array"
    then error("not a hooks document") else . end
    | (.hooks.PreToolUse // []) as $pre
    | [ $pre[] | select(any((.hooks // [])[]; ours)) ] as $mine
    | if $mine == [$g] then .
      else .hooks.PreToolUse = (
          [ $pre[]
            | .hooks = [ (.hooks // [])[] | select(ours | not) ]
            | select(.hooks | length > 0) ]
          + [$g])
      end' 2>/dev/null) \
    || fail "$FILE is not a hooks document this script can extend; fix or remove it"

[ "$NEXT" = "$(printf '%s' "$CURRENT" | jq .)" ] && exit 0

mkdir -p -- "$CODEX_DIR" || fail "cannot create $CODEX_DIR"
TMP=$(mktemp "$CODEX_DIR/hooks.json.XXXXXX") || fail "cannot write in $CODEX_DIR"
if ! printf '%s\n' "$NEXT" > "$TMP" || ! mv -f -- "$TMP" "$FILE"; then
    rm -f -- "$TMP"
    fail "cannot write $FILE"
fi
printf 'gh-origin-guard-codex: registered the gh origin guard in %s\n' "$FILE"
