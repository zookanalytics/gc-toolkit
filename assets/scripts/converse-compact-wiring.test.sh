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
#       when no steer is staged. Once its own tmux session's environment holds
#       GC_DRAIN_ACK=1, which every drain-ack of the session sets, it prints
#       no steer, writes one line to stderr and exits 2, the hook's refusal
#       of the compaction. A read of the flag that fails or answers anything
#       else, and a hook run outside tmux, print the steer and exit 0, so a
#       sitting whose drain is not acknowledged is never refused
#   (2t) against a private tmux server, the hook reads the flag of the session
#       whose pane runs it: it refuses while the flag is set, compacts once
#       Gas City removes it, ignores another session's flag, and compacts in a
#       session started again under the same name, which holds no flag
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
# Hermetic but for (2t) and (6): reads the repository and runs the hook in a
# temporary directory, with a stub tmux on PATH for (2). (2t) runs a private
# tmux server, and prints SKIP where tmux is missing. (6) points the real gc at
# a scratch city that is never started, and prints SKIP when no GC_BIN names
# one, as in CI.
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
SOCK="converse-compact-test-$$"
# kill-server leaves the socket file behind, so the suite removes its own.
SOCKET_DIR="${TMUX_TMPDIR:-/tmp}/tmux-$(id -u)"
T() { env -u TMUX -u TMUX_PANE tmux -L "$SOCK" -f /dev/null "$@"; }
cleanup() {
    if command -v tmux >/dev/null 2>&1; then T kill-server >/dev/null 2>&1 || true; fi
    rm -f "$SOCKET_DIR/$SOCK"
    rm -rf "$TMP"
}
trap cleanup EXIT

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

mkdir -p "$TMP/home/.claude/hooks" "$TMP/empty" "$TMP/away" "$TMP/stub"
cp "$STEER" "$TMP/home/$STEER_REL"
WANT_OUT="$(cat "$STEER")"
# A stub tmux that logs how it was asked and answers as the case sets, the way
# show-environment answers: the variable's line on stdout, or an error on
# stderr and a non-zero exit.
cat >"$TMP/stub/tmux" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >>"$STUB_LOG"
[ -z "${STUB_OUT:-}" ] || printf '%s\n' "$STUB_OUT"
[ -z "${STUB_ERR:-}" ] || printf '%s\n' "$STUB_ERR" >&2
exit "${STUB_RC:-0}"
STUB
chmod +x "$TMP/stub/tmux"
# hook <shell> [VAR=value ...] — run the hook's command under <shell>, from a
# directory that is not the home, with no tmux session, home or stub answer in
# its environment but those the arguments name. Its stdout, stderr and exit
# land in OUT, ERR and RC, and what it asked the stub in ASKED.
hook() {
    local sh_="$1"; shift
    : >"$TMP/stub.log"
    (cd "$TMP/away" && env -u TMUX -u TMUX_PANE -u GC_DIR -u CLAUDE_PROJECT_DIR \
        -u STUB_OUT -u STUB_ERR -u STUB_RC STUB_LOG="$TMP/stub.log" "$@" "$sh_" -c "$CMD") >"$TMP/out" 2>"$TMP/err"
    RC=$?
    OUT="$(cat "$TMP/out")"; ERR="$(cat "$TMP/err")"; ASKED="$(cat "$TMP/stub.log")"
}
steers() { # steers <label> — the hook printed the steer and exited 0
    if [ "$RC" -eq 0 ] && [ "$OUT" = "$WANT_OUT" ]; then ok "$1"
    else bad "$1" "rc $RC, $(printf '%s' "$OUT" | wc -c | tr -d ' ') bytes out, stderr '$ERR'"; fi
}
refuses() { # refuses <label> — the hook printed no steer, one line on stderr, and exited 2
    if [ "$RC" -eq 2 ] && [ -z "$OUT" ] && [ -n "$ERR" ] && [ "$(printf '%s\n' "$ERR" | wc -l | tr -d ' ')" = 1 ]; then ok "$1"
    else bad "$1" "rc $RC, $(printf '%s' "$OUT" | wc -c | tr -d ' ') bytes out, stderr '$ERR'"; fi
}
shells="sh bash"
command -v zsh >/dev/null 2>&1 && shells="$shells zsh"
PANE="TMUX=/tmp/tmux-0/city,1,0"
for sh_ in $shells; do
    hook "$sh_" GC_DIR="$TMP/home"
    steers "($sh_) the hook prints the steer staged in GC_DIR and exits 0"
    hook "$sh_" CLAUDE_PROJECT_DIR="$TMP/home"
    steers "($sh_) …finds the home through CLAUDE_PROJECT_DIR when GC_DIR is unset"
    hook "$sh_" GC_DIR="$TMP/empty"
    [ "$RC" -eq 0 ] && [ -z "$OUT$ERR" ] && ok "($sh_) …and with no steer staged, prints nothing and exits 0, so the compaction goes on" \
        || bad "($sh_) …and with no steer staged, prints nothing and exits 0, so the compaction goes on" "rc $RC, out '$OUT', stderr '$ERR'"
    hook "$sh_" GC_DIR="$TMP/home" "$PANE" TMUX_PANE=%7 PATH="$TMP/stub:$PATH" STUB_OUT=GC_DRAIN_ACK=1
    refuses "($sh_) once its session's environment holds GC_DRAIN_ACK=1, the hook prints no steer, says why on stderr and exits 2"
    [ "$ASKED" = "show-environment -t %7 GC_DRAIN_ACK" ] && ok "($sh_) …reading the flag of the session whose pane runs it" \
        || bad "($sh_) …reading the flag of the session whose pane runs it" "asked tmux: '$ASKED'"
    hook "$sh_" GC_DIR="$TMP/home" "$PANE" TMUX_PANE=%7 PATH="$TMP/stub:$PATH" STUB_ERR="unknown variable: GC_DRAIN_ACK" STUB_RC=1
    steers "($sh_) …and steers a session whose environment holds no flag"
    hook "$sh_" GC_DIR="$TMP/home" "$PANE" TMUX_PANE=%7 PATH="$TMP/stub:$PATH" STUB_OUT=-GC_DRAIN_ACK
    steers "($sh_) …or holds it marked removed"
    hook "$sh_" GC_DIR="$TMP/home" "$PANE" TMUX_PANE=%7 PATH="$TMP/stub:$PATH" STUB_ERR="no server running" STUB_RC=1
    steers "($sh_) …or whose read of the flag fails"
    hook "$sh_" GC_DIR="$TMP/home" TMUX_PANE=%7 PATH="$TMP/stub:$PATH" STUB_OUT=GC_DRAIN_ACK=1
    if [ "$RC" -eq 0 ] && [ "$OUT" = "$WANT_OUT" ] && [ -z "$ASKED" ]; then
        ok "($sh_) …and outside tmux it asks no server, so it never reads a pane of another server"
    else
        bad "($sh_) …and outside tmux it asks no server, so it never reads a pane of another server" "rc $RC, asked tmux: '$ASKED'"
    fi
done

# --- (2t) the hook reads its own session's flag on a tmux server -----------
# Gas City sets and removes the flag with set-environment on the session, stops
# a session with kill-session and starts one with new-session. A pane hands
# TMUX and TMUX_PANE to the agent it runs, and so to the agent's hooks.
if ! command -v tmux >/dev/null 2>&1; then
    printf '  SKIP  tmux is not installed, so the hook was not run against a tmux server\n'
else
    # start <session> <file> — start <session> with a pane that writes the
    # TMUX and TMUX_PANE it was given to <file>, and wait for them.
    start() {
        T new-session -d -s "$1" -x 80 -y 24 \
            "printf '%s %s\n' \"\$TMUX\" \"\$TMUX_PANE\" >'$2.tmp' && mv '$2.tmp' '$2'; sleep 600" >/dev/null 2>&1
        local i=0
        while [ ! -s "$2" ] && [ "$i" -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
    }
    # in_pane <file> — run the hook as the agent in the pane <file> names runs it.
    in_pane() {
        local tmux_ pane_
        read -r tmux_ pane_ <"$1" 2>/dev/null || { tmux_=""; pane_=""; }
        hook sh GC_DIR="$TMP/home" TMUX="$tmux_" TMUX_PANE="$pane_"
    }
    start sit "$TMP/pane-1"
    if [ ! -s "$TMP/pane-1" ]; then
        bad "(2t) a private tmux server runs a pane that names itself" "no TMUX or TMUX_PANE read from the pane"
    else
        T set-environment -t =sit GC_DRAIN_ACK 1
        in_pane "$TMP/pane-1"
        refuses "(2t) the hook refuses while its own session's environment holds GC_DRAIN_ACK=1"
        T set-environment -t =sit -u GC_DRAIN_ACK
        in_pane "$TMP/pane-1"
        steers "(2t) …and steers once the flag is removed"
        T new-session -d -s other -x 80 -y 24 'sleep 600' >/dev/null 2>&1
        T set-environment -t =other GC_DRAIN_ACK 1
        in_pane "$TMP/pane-1"
        steers "(2t) …and another session's flag leaves it alone"
        T set-environment -t =sit GC_DRAIN_ACK 1
        T kill-session -t =sit
        start sit "$TMP/pane-2"
        in_pane "$TMP/pane-2"
        steers "(2t) a session started again under the same name after a stop holds no flag, so it is compacted"
    fi
fi

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
asks "the facts the decision rests on, each with where its source lives" \
    'State the facts the decision rests on, each figure with where its source lives, such as a bead'"'"'s notes, a file or a command, so the sitting can act on a ruling without finding them again.'
asks "the last hand-back, word for word" \
    'Then quote word for word the hand-back that ended the last message posted to the operator'
asks "the entry's names for the conversation, the subject and the gates" \
    'Copy the CONV, CONVERSATION, SUBJECT and GATES lines exactly as the converse entry last printed them'
asks "a last line that sends the sitting through its entry before anything else" \
    'End the summary by telling the sitting to run the converse entry again before anything else'
asks "…and has it work from the summary and the entry, reading again only what the operator's message needs" \
    'Tell it also to work from this summary and from what the entry prints, and to read again only what the operator'"'"'s message needs that neither holds.'
asks "each step still owed after a sign-off, whichever way it left the conversation" \
    'When a sign-off in this session ran and a step after it has not landed, say which steps are still owed, whether the sign-off closed the conversation or handed it back to the operator'"'"'s queue: the send or the close of the subject that some rulings make after the sign-off, and the hand-back, recorded and posted.'
asks "…taken before the drain" \
    'Tell the sitting to take those steps before it drains, because the entry then finds no conversation and prints NEXT=drain.'

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
