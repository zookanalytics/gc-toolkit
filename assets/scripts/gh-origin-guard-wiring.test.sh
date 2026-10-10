#!/usr/bin/env bash
# gh-origin-guard-wiring.test.sh — assert every agent actually receives the gh
# origin guard, through the registration its provider reads.
#
# The guard only protects an agent whose settings register it, and nothing at
# runtime reports an agent that was left out: an unwired agent looks exactly
# like one whose writes were all legitimate. A new agent added to agents/ with
# no registration would be silently unguarded, which is the failure this test
# exists to make loud.
#
# Covered:
#   (1) every agent that is not codex-provider has a pack.toml overlay_dir
#   (2) that overlay registers a PreToolUse/Bash hook naming the guard
#   (3) every codex-provider agent runs gh-origin-guard-codex.sh as pre_start,
#       since Codex reads no .claude overlay
#   (4) the registered command is identical across overlays and the Codex
#       registration, so they cannot drift into guarding different things
#   (5) the command resolves the script only from gc-controlled roots — never
#       from the working directory, which on a third-party checkout would let
#       that repository supply the code judging its own writes
#   (6) the script it names exists, is executable, and parses
#
# run-tests-scope: tree

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
GUARD_REL="assets/scripts/gh-origin-guard.sh"
CODEX_REL="assets/scripts/gh-origin-guard-codex.sh"

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n        %s\n' "$1" "$2"; }

command -v jq >/dev/null 2>&1 || { echo "FATAL: jq required" >&2; exit 1; }

echo "gh-origin-guard wiring"

# --- (6) the script itself -----------------------------------------------
if [ -x "$REPO/$GUARD_REL" ]; then ok "guard script is executable"
else bad "guard script is executable" "$REPO/$GUARD_REL"; fi
if sh -n "$REPO/$GUARD_REL" 2>/dev/null; then ok "guard script parses"
else bad "guard script parses" "sh -n failed"; fi

# --- pack.toml: agent -> overlay_dir -------------------------------------
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

# --- (1)(2)(3) coverage, agent by agent ----------------------------------
GUARD_CMDS=""
for dir in "$REPO"/agents/*/; do
    agent="$(basename "$dir")"
    [ -f "$dir/agent.toml" ] || continue

    # A declared codex provider reads no .claude/settings.json, so its guard is
    # the Codex home's registration, made by its pre_start before the session
    # starts. Anything else may run under claude and must have an overlay.
    if grep -Eq '^provider *= *"codex"' "$dir/agent.toml"; then
        if awk '/^pre_start *=/, /\]/' "$dir/agent.toml" \
            | grep -Fq "{{.ConfigDir}}/$CODEX_REL"; then
            ok "$agent is guarded (codex: pre_start runs $CODEX_REL)"
        else
            bad "$agent is guarded" "codex-provider, and its pre_start does not run {{.ConfigDir}}/$CODEX_REL"
        fi
        continue
    fi

    overlay="$(overlay_of "$agent")"
    if [ -z "$overlay" ]; then
        bad "$agent has an overlay" "no [[patches.agent]] overlay_dir in pack.toml"
        continue
    fi

    settings="$REPO/$overlay/.claude/settings.json"
    if [ ! -s "$settings" ]; then
        bad "$agent overlay has settings" "missing $settings"
        continue
    fi

    cmd="$(jq -r --arg g "gh-origin-guard.sh" '
        [ (.hooks.PreToolUse // [])[]
          | select((.matcher // "") == "Bash")
          | (.hooks // [])[]
          | select((.command // "") | contains($g))
          | .command ] | first // ""' "$settings" 2>/dev/null)"

    if [ -z "$cmd" ]; then
        bad "$agent is guarded" "$overlay registers no PreToolUse/Bash gh-origin-guard hook"
        continue
    fi
    ok "$agent is guarded (via $overlay)"
    GUARD_CMDS="$GUARD_CMDS$cmd
"
done

# --- (4) the registrations agree -----------------------------------------
# The Codex registration is what the installer writes into a Codex home, read
# back from a scratch one.
CODEX_HOME_DIR="$(mktemp -d "${TMPDIR:-/tmp}/gctk-gh-origin-guard-wiring.XXXXXX")"
trap 'rm -rf "$CODEX_HOME_DIR"' EXIT
if CODEX_HOME="$CODEX_HOME_DIR" "$REPO/$CODEX_REL" >/dev/null 2>&1; then
    codex_cmd="$(jq -r --arg g "gh-origin-guard.sh" '
        [ (.hooks.PreToolUse // [])[]
          | select((.matcher // "") == "Bash")
          | (.hooks // [])[]
          | select((.command // "") | contains($g))
          | .command ] | first // ""' "$CODEX_HOME_DIR/hooks.json" 2>/dev/null)"
    if [ -n "$codex_cmd" ]; then
        ok "the Codex registration is a PreToolUse/Bash hook naming the guard"
        GUARD_CMDS="$GUARD_CMDS$codex_cmd
"
    else
        bad "the Codex registration is a PreToolUse/Bash hook naming the guard" \
            "$(cat "$CODEX_HOME_DIR/hooks.json" 2>/dev/null)"
    fi
else
    bad "the Codex registration is a PreToolUse/Bash hook naming the guard" "$CODEX_REL failed"
fi

DISTINCT="$(printf '%s' "$GUARD_CMDS" | grep -c . || true)"
UNIQUE="$(printf '%s' "$GUARD_CMDS" | sort -u | grep -c . || true)"
if [ "$DISTINCT" -gt 0 ] && [ "$UNIQUE" -eq 1 ]; then
    ok "every registration runs the same command ($DISTINCT registrations, 1 spelling)"
else
    bad "every registration runs the same command" "$DISTINCT registrations, $UNIQUE distinct spellings"
fi

CMD="$(printf '%s' "$GUARD_CMDS" | head -1)"

# --- (5) the command resolves from gc-controlled roots only --------------
case "$CMD" in
    *'rev-parse'*|*'--show-toplevel'*)
        bad "resolution is not cwd-derived" "the command consults the working directory's repository" ;;
    *) ok "resolution is not cwd-derived" ;;
esac
case "$CMD" in
    *'GC_RIG_ROOT'*) ok "resolution consults GC_RIG_ROOT" ;;
    *) bad "resolution consults GC_RIG_ROOT" "$CMD" ;;
esac
case "$CMD" in
    *'GC_CITY_PATH'*) ok "resolution falls back to the city rig" ;;
    *) bad "resolution falls back to the city rig" "$CMD" ;;
esac
case "$CMD" in
    *"$GUARD_REL"*) ok "resolution names $GUARD_REL" ;;
    *) bad "resolution names $GUARD_REL" "$CMD" ;;
esac

echo
printf 'gh-origin-guard wiring: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
