#!/usr/bin/env bash
# converse-compact-wiring.test.sh — assert that a converse sitting goes on
# through a full context. Each Claude sitting carries the hook that steers its
# compaction summary, and no other agent does. Gas City's context advisory,
# which tells a session to hand off and reset itself, is off for every sitting
# and for no other agent.
#
# Covered:
#   (1) pack.toml gives overlays/converse-compact to exactly the converse
#       agents whose provider is claude
#   (2) the overlay's PreCompact hook, for every trigger, prints the steer
#       staged in the home and exits 0, finds the home through
#       CLAUDE_PROJECT_DIR when GC_DIR is unset, and exits 0 printing nothing
#       when no steer is staged, since exit 2 would block the compaction
#   (3) no other Claude settings file in the repository registers a PreCompact
#       hook
#   (4) the steer fits in the 10,000 characters Claude Code keeps of a hook's
#       output, and asks for each part a sitting needs back
#   (5) every converse agent turns the advisory off, and no other agent, nor
#       the pack, sets it
#   (6) under the real gc GC_BIN names, a scratch city that imports the pack
#       resolves the advisory off on each converse agent and unset on every
#       other, and gives the overlay to the Claude sittings alone
#
# Hermetic but for (6): reads the repository and runs the hook in a temporary
# directory. (6) points the real gc at a scratch city that is never started,
# and prints SKIP when no GC_BIN names one, as in CI.
#
# run-tests-scope: tree

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
OVERLAY="overlays/converse-compact"
SETTINGS="$REPO/$OVERLAY/.claude/settings.json"
STEER_REL=".claude/hooks/converse-compact.md"
STEER="$REPO/$OVERLAY/$STEER_REL"

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n        %s\n' "$1" "$2"; }

command -v jq >/dev/null 2>&1 || { echo "FATAL: jq required" >&2; exit 1; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/converse-compact-wiring.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

echo "converse compaction wiring"

# overlay_of <agent> — the overlay_dir pack.toml's [[patches.agent]] stanza
# gives the agent, the one place this pack sets it.
overlay_of() {
    awk -v want="$1" '
        /^\[\[patches\.agent\]\]/ { name = ""; next }
        /^name *=/ { gsub(/^name *= *"|" *$/, ""); name = $0; next }
        /^overlay_dir *=/ {
            gsub(/^overlay_dir *= *"|" *$/, "")
            if (name == want) { print; exit }
        }
    ' "$REPO/pack.toml"
}
provider_of() { sed -n 's/^provider *= *"\([^"]*\)".*/\1/p' "$1" | head -1; }

# --- (1) the overlay reaches the Claude sittings alone ---------------------
WANT=""; GOT=""; SITTINGS=""; OTHERS=""
for dir in "$REPO"/agents/*/; do
    agent="$(basename "$dir")"
    [ -f "$dir/agent.toml" ] || continue
    case "$agent" in
        converse-*)
            SITTINGS="$SITTINGS $agent"
            [ "$(provider_of "$dir/agent.toml")" = claude ] && WANT="$WANT $agent" ;;
        *) OTHERS="$OTHERS $agent" ;;
    esac
    [ "$(overlay_of "$agent")" = "$OVERLAY" ] && GOT="$GOT $agent"
done
if [ -n "$WANT" ] && [ "$WANT" = "$GOT" ]; then
    ok "pack.toml gives $OVERLAY to the Claude converse agents and no other agent:$GOT"
else
    bad "pack.toml gives $OVERLAY to the Claude converse agents and no other agent" "want:$WANT got:$GOT"
fi

# --- (2) the hook prints the steer and never blocks ------------------------
HOOKS="$(jq -c '[.hooks.PreCompact[]? | {matcher, cmds: [.hooks[]? | .command]}]' "$SETTINGS" 2>/dev/null)"
CMD="$(printf '%s' "$HOOKS" | jq -r 'if length == 1 and (.[0].cmds | length) == 1 then .[0].cmds[0] else empty end')"
if [ -n "$CMD" ]; then
    ok "the overlay registers one PreCompact hook"
else
    bad "the overlay registers one PreCompact hook" "PreCompact: ${HOOKS:-unreadable}"
fi
MATCHER="$(printf '%s' "$HOOKS" | jq -r '.[0].matcher // "absent"')"
[ "$MATCHER" = "" ] && ok "…for every trigger, manual and auto (its matcher is empty)" \
    || bad "…for every trigger, manual and auto (its matcher is empty)" "matcher '$MATCHER'"

mkdir -p "$TMP/home/.claude/hooks" "$TMP/empty" "$TMP/away"
cp "$STEER" "$TMP/home/$STEER_REL"
WANT_OUT="$(cat "$STEER")"
shells="sh bash"
command -v zsh >/dev/null 2>&1 && shells="$shells zsh"
for sh_ in $shells; do
    OUT="$(cd "$TMP/away" && env -u CLAUDE_PROJECT_DIR GC_DIR="$TMP/home" "$sh_" -c "$CMD")"; RC=$?
    [ "$RC" -eq 0 ] && [ "$OUT" = "$WANT_OUT" ] && ok "($sh_) the hook prints the steer staged in GC_DIR and exits 0" \
        || bad "($sh_) the hook prints the steer staged in GC_DIR and exits 0" "rc $RC, $(printf '%s' "$OUT" | wc -c) bytes"
    OUT="$(cd "$TMP/away" && env -u GC_DIR CLAUDE_PROJECT_DIR="$TMP/home" "$sh_" -c "$CMD")"; RC=$?
    [ "$RC" -eq 0 ] && [ "$OUT" = "$WANT_OUT" ] && ok "($sh_) …finds the home through CLAUDE_PROJECT_DIR when GC_DIR is unset" \
        || bad "($sh_) …finds the home through CLAUDE_PROJECT_DIR when GC_DIR is unset" "rc $RC, $(printf '%s' "$OUT" | wc -c) bytes"
    OUT="$(cd "$TMP/away" && env -u CLAUDE_PROJECT_DIR GC_DIR="$TMP/empty" "$sh_" -c "$CMD" 2>&1)"; RC=$?
    [ "$RC" -eq 0 ] && [ -z "$OUT" ] && ok "($sh_) …and with no steer staged, prints nothing and exits 0, so the compaction goes on" \
        || bad "($sh_) …and with no steer staged, prints nothing and exits 0, so the compaction goes on" "rc $RC, out '$OUT'"
done

# --- (3) no other settings file steers a summary ---------------------------
OTHER_PC=""; READ=0
LISTED="$(git -C "$REPO" ls-files | grep -E '(^|/)\.claude/settings(\.local)?\.json$')"
while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    [ "$rel" = "$OVERLAY/.claude/settings.json" ] && continue
    READ=$((READ + 1))
    n="$(jq '[.hooks.PreCompact[]?] | length' "$REPO/$rel" 2>/dev/null || echo unreadable)"
    [ "$n" = 0 ] || OTHER_PC="$OTHER_PC $rel($n)"
done <<<"$LISTED"
if [ "$READ" -eq 0 ]; then
    bad "no other Claude settings file in the repository registers a PreCompact hook" "git ls-files listed no other .claude/settings.json to read"
elif [ -z "$OTHER_PC" ]; then
    ok "no other Claude settings file in the repository registers a PreCompact hook ($READ read)"
else
    bad "no other Claude settings file in the repository registers a PreCompact hook" "$OTHER_PC"
fi

# --- (4) the steer fits and asks for what a sitting needs back -------------
BYTES="$(wc -c <"$STEER" | tr -d ' ')"
[ "$BYTES" -lt 10000 ] && ok "the steer is under the 10,000 characters Claude Code keeps of a hook's output ($BYTES bytes)" \
    || bad "the steer is under the 10,000 characters Claude Code keeps of a hook's output" "$BYTES bytes"
tr -s '[:space:]' ' ' <"$STEER" >"$TMP/steer"
asks() { # asks <what> <text>
    if grep -qF -- "$2" "$TMP/steer"; then ok "the steer asks for $1"; else bad "the steer asks for $1" "missing: $2"; fi
}
asks "the operator's words the record does not hold yet, word for word" \
    'What the operator said that the record does not hold yet. Quote word for word'
asks "the open decision and the recommendation as they stood" \
    'State the decision that is still open, the recommendation as it last stood'
asks "the last hand-back, word for word" \
    'Then quote word for word the hand-back that ended the last message posted to the operator'
asks "the entry's names for the conversation, the subject and the gates" \
    'Copy the CONV, CONVERSATION, SUBJECT and GATES lines exactly as the converse entry last printed them'
asks "a last line that sends the sitting through its entry before anything else" \
    'End the summary by telling the sitting to run the converse entry again before anything else'
asks "the message of a sign-off that closed the conversation before it was posted, posted before the drain" \
    'When a sign-off in this session closed the conversation before its message was posted, say so, and tell the sitting to record and post that message before it drains'

# --- (5) the advisory is off for the sittings alone ------------------------
OFF='context_advisory = { enabled = false }'
for agent in $SITTINGS; do
    f="$REPO/agents/$agent/agent.toml"
    if [ "$(grep -E '^context_advisory' "$f")" = "$OFF" ]; then
        ok "$agent turns Gas City's context advisory off"
    else
        bad "$agent turns Gas City's context advisory off" "$(grep -E '^context_advisory' "$f" || echo 'no context_advisory line')"
    fi
done
SET=""
for agent in $OTHERS; do
    grep -Eq '^[^#]*context_advisory' "$REPO/agents/$agent/agent.toml" && SET="$SET $agent"
done
grep -Eq '^[^#]*context_advisory' "$REPO/pack.toml" && SET="$SET pack.toml"
[ -z "$SET" ] && ok "no other agent, nor the pack, sets context_advisory, so each keeps the city's advisory" \
    || bad "no other agent, nor the pack, sets context_advisory, so each keeps the city's advisory" "set in:$SET"

# --- (6) Gas City resolves it so ------------------------------------------
# A scratch city that imports the pack into one rig, never started: gc reads
# its config and composes the agents, with GC_CITY naming it and nothing in the
# environment naming a live city, rig or store. tools/run-tests.sh hands the
# real gc on as RUN_TESTS_GC_BIN.
REAL_GC="${RUN_TESTS_GC_BIN:-${GC_BIN:-}}"
if [ -z "$REAL_GC" ] || [ ! -x "$REAL_GC" ]; then
    printf '  SKIP  GC_BIN names no gc, so the composed config was not read (set GC_BIN to run it)\n'
else
    CITY="$TMP/city"
    mkdir -p "$CITY/.gc" "$CITY/rigs/probe" "$TMP/gc-home"
    printf '[workspace]\nprovider = "claude"\n\n[providers.claude]\nbase = "builtin:claude"\n\n[providers.codex]\nbase = "builtin:codex"\n\n[providers.gemini]\nbase = "builtin:gemini"\n\n[[rigs]]\nname = "probe"\nprefix = "zq"\n[rigs.imports]\n[rigs.imports.gc-toolkit]\nsource = "%s"\n' "$REPO" >"$CITY/city.toml"
    printf '[pack]\nname = "converse-compact-probe"\nschema = 2\n\n[imports.gc-toolkit]\nsource = "%s"\n' "$REPO" >"$CITY/pack.toml"
    printf 'workspace_prefix = "zp"\n\n[[rig]]\nname = "probe"\npath = "%s"\n' "$CITY/rigs/probe" >"$CITY/.gc/site.toml"
    if (cd "$CITY" && env -u GC_CITY_PATH -u GC_RIG -u GC_RIG_ROOT -u GC_DIR -u GC_PACK_DIR \
            -u BEADS_DIR -u GC_BEADS_SCOPE_ROOT -u GC_DOLT_PORT -u BEADS_DOLT_SERVER_PORT \
            GC_CITY="$CITY" GC_HOME="$TMP/gc-home" "$REAL_GC" config show --json) >"$TMP/show.json" 2>"$TMP/show.err"; then
        # Every agent the city composes, the rig's and the city's own. jq's //
        # would read a false Enabled as absent, so the advisory is read by hand.
        ROWS="$(jq -r '.config.Agents[] | [.Name, (if .ContextAdvisory == null then "unset" else (.ContextAdvisory.Enabled | tostring) end), ((.OverlayDir // "") | sub(".*/overlays/"; "overlays/"))] | @tsv' "$TMP/show.json")"
        [ -n "$ROWS" ] && ok "gc composes the rig's agents from the pack" \
            || bad "gc composes the rig's agents from the pack" "$(head -c 400 "$TMP/show.err")"
        for agent in $SITTINGS; do
            row="$(printf '%s\n' "$ROWS" | awk -F'\t' -v a="$agent" '$1 == a')"
            [ "$(printf '%s' "$row" | cut -f2)" = false ] && ok "gc resolves $agent's advisory off" \
                || bad "gc resolves $agent's advisory off" "row '$row'"
        done
        UNSET_BAD="$(printf '%s\n' "$ROWS" | awk -F'\t' '$1 !~ /^converse-/ && $2 != "unset" { print $1 "=" $2 }' | tr '\n' ' ')"
        [ -z "$UNSET_BAD" ] && ok "…and leaves every other agent's advisory unset, so the city's and the built-in default apply" \
            || bad "…and leaves every other agent's advisory unset, so the city's and the built-in default apply" "$UNSET_BAD"
        GOT_OVERLAY="$(printf '%s\n' "$ROWS" | awk -F'\t' -v o="$OVERLAY" '$3 == o { print $1 }' | sort -u | tr '\n' ' ')"
        WANT_SORTED="$(printf '%s\n' $WANT | sort -u | tr '\n' ' ')"
        [ "$GOT_OVERLAY" = "$WANT_SORTED" ] && ok "gc gives $OVERLAY to the Claude sittings alone: $GOT_OVERLAY" \
            || bad "gc gives $OVERLAY to the Claude sittings alone" "want: $WANT_SORTED got: $GOT_OVERLAY"
    else
        bad "gc composes the rig's agents from the pack" "gc config show failed: $(head -c 400 "$TMP/show.err")"
    fi
fi

echo
printf 'converse compaction wiring: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
