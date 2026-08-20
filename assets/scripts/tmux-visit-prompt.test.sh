#!/usr/bin/env bash
# Test for tmux-visit-prompt.sh — the `prefix + a` operator-origin visit
# intake (tk-bn1oi), and for the binding tmux-bindings.sh installs for it.
#
# Two halves, because the defect classes are different:
#
#   HERMETIC — the handler run directly with `tmux` and `gc-visit-open.sh`
#     stubbed on PATH / in a fake config dir. No tmux server, no city.
#   LIVE     — a real tmux server on a private socket, driven through a real
#     pty client with real key presses. Guarded on tmux + script(1); skipped
#     with a notice where either is missing.
#
# What the cases are guarding, and why each was worth a test:
#
#   (BIND)      tmux-bindings.sh must bind prefix+a to command-prompt ->
#               set-buffer -> the handler, and must NOT reference the retired
#               tmux-spawn-thread.sh. `%%%`, not `%%`: the escaping variant is
#               the whole reason quotation marks survive.
#   (ROUNDTRIP) THE acceptance criterion. `command-prompt` substitutes the
#               response as TEXT and then PARSES the result as a tmux command,
#               so a message containing `;` or `"` spliced into a command line
#               is mangled or partly EXECUTED — the predecessor shipped exactly
#               that hazard and documented it (specs/tk-1zd25/design.md). Typed
#               through a real pty, an apostrophe + semicolon + quotes + `$` +
#               `~` + backslash must reach the handler's argv byte-for-byte.
#   (THREE)     three presses in a row are three independent topics. The buffer
#               name is FIXED, so press N+1 overwrites the slot press N is
#               reading: only a foreground read serialises them. A lost topic
#               here is silent, which is the one failure this channel exists to
#               prevent.
#   (NOFREEZE)  ...and the foreground read must still not block the server for
#               the length of the intake. A second press has to be able to
#               start while the first `gc-visit-open` is still running.
#   (BLANK)     a blank Enter files nothing — no bead with an empty title —
#               and still says so.
#   (STALE)     the buffer is deleted after the read, so the next press cannot
#               re-file the previous topic. Esc never runs the template, so a
#               surviving buffer would otherwise be read as a fresh topic.
#   (DASH)      a message may begin with "-"; it must reach gc-visit-open
#               behind `--` rather than being read as a flag.
#   (IDPASS)    a bare bead id is NOT forced to a topic (no --topic): opening a
#               conversation on an existing bead is a real thing to want from
#               this key, and gc-visit-open already fails loudly on an id no
#               ledger answers for.
#   (SAYOK)     success names the ids. An intake whose result you cannot see is
#               an intake you do not trust.
#   (SAYFAIL)   failure is visible AND names the subject bead when one was
#               already created — that id is the difference between retrying
#               and losing the thought. `run-shell` output goes nowhere, so
#               display-message is the only channel.
#   (REACT)     the react path reports that the visit is still to come, rather
#               than claiming one was filed.
#   (INDICATOR) the in-flight status-line slot is written while the intake
#               runs and cleared when it ends — however it ends. (That the
#               agent behind it is resolved in the FOREGROUND is not asserted
#               here: it takes a multi-session server to show the difference.
#               `#{client_tty}`/`#{client_session}` are empty in the detached
#               half, and `#{session_name}` answers with whichever session
#               tmux considers current — on a real city, not necessarily the
#               operator who pressed the key. ROUNDTRIP covers the message
#               target, which fails outright without the foreground capture.)
#   (TIMEOUT)   a wedged intake is reported rather than hanging with the
#               indicator lit and no message. A silent hang is the same
#               outcome as a silent failure: a thought the operator believes
#               was filed and was not.
#   (GONE)      tmux-spawn-thread.sh is deleted and nothing live still points
#               at it (specs/ is a historical record and is exempt).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/tmux-visit-prompt.sh"
BINDINGS="$HERE/tmux-bindings.sh"
TMP="$(mktemp -d)"
SOCKET="gcvp-test-$$"
PROBE_SOCKET="gcvp-probe-$$"
cleanup() {
    tmux -L "$SOCKET" kill-server >/dev/null 2>&1 || true
    tmux -L "$PROBE_SOCKET" kill-server >/dev/null 2>&1 || true
    rm -rf "$TMP"
}
trap cleanup EXIT

PASS=0; FAIL=0; SKIP=0
ok()   { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad()  { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
skip() { SKIP=$((SKIP + 1)); echo "skip - $1"; }
eq()   { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }
has()  { grep -qF -- "$2" <<< "$1" && ok "$3" || bad "$3 (in: $1)"; }
hasnt() { grep -qF -- "$2" <<< "$1" && bad "$3 (in: $1)" || ok "$3"; }

[ -f "$SCRIPT" ] && ok "tmux-visit-prompt.sh present" || { bad "missing at $SCRIPT"; exit 1; }
[ -x "$SCRIPT" ] && ok "tmux-visit-prompt.sh executable" || bad "tmux-visit-prompt.sh not executable"

# The hostile message. Every piece of it breaks a different layer if the
# response is ever spliced into a command line: `'` the shell's single quotes,
# `;` tmux's command separator, `"` its argument quoting, `$`/`\`/`~` the
# shell again, and `#{}`/`#()`/`#H` tmux's FORMAT layer — `#(...)` runs a
# shell command wherever a format is expanded, so a message that reaches one
# is not a mangling bug but an execution one. It is one string, so a
# regression in any layer fails one case.
HOSTILE="ship it; don't wait \"ok\" \$HOME ~x back\\sl #{session_name} #(id -un) #H"

# ── Fake config dir: the handler resolves gc-visit-open.sh under it ──────────
# Passing the stub this way (rather than through the environment) matches how
# the real binding wires the two together, and keeps the test honest about the
# path the handler actually computes.
mkcfg() {           # mkcfg <dir> <stub-body>
    mkdir -p "$1/assets/scripts"
    printf '%s\n' "$2" > "$1/assets/scripts/gc-visit-open.sh"
    chmod +x "$1/assets/scripts/gc-visit-open.sh"
    # tmux-bindings.sh derives the handler path from the config dir too, so
    # the live half reaches the REAL handler only if it is linked in here.
    ln -sf "$SCRIPT" "$1/assets/scripts/tmux-visit-prompt.sh"
}

STUB_OK='#!/bin/sh
{ printf "=== call ===\n"; for a in "$@"; do printf "argv=[%s]\n" "$a"; done; } >> "$CALLS"
echo "gc-visit-open: subject tk-sub01 created in rig gc-toolkit (task)" >&2
echo "gc-helm: visit tk-vis01 filed on tk-sub01 (pool gc-toolkit/gc-toolkit.converse)"
echo "gc-visit-open: subject tk-sub01 — visit filed (--no-react: filing the visit directly)."'

STUB_REACT='#!/bin/sh
{ printf "=== call ===\n"; for a in "$@"; do printf "argv=[%s]\n" "$a"; done; } >> "$CALLS"
echo "gc-visit-open: subject tk-sub02 created in rig gc-toolkit (task)" >&2
echo "gc-visit-open: subject tk-sub02 — first reaction slung (yes: proactive is deliverable)."'

STUB_FAIL='#!/bin/sh
{ printf "=== call ===\n"; for a in "$@"; do printf "argv=[%s]\n" "$a"; done; } >> "$CALLS"
echo "gc-visit-open: subject tk-sub03 created in rig gc-toolkit (task)" >&2
echo "gc-visit-open: could not file the visit on tk-sub03 (the subject bead exists)" >&2
exit 4'

###############################################################################
# HERMETIC — handler run directly, `tmux` stubbed.
###############################################################################
# The tmux stub answers show-buffer from $FAKE_BUFFER and logs every call, so
# "what the operator was told" is asserted against real argv rather than
# against exit status. delete-buffer clears the file, which is what (STALE)
# checks.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/tmux" <<'TMUXSTUB'
#!/usr/bin/env bash
printf 'tmux %s\n' "$*" >> "$TMUX_CALLS"
case "$1 ${2:-}" in
  "show-buffer -b")   cat "$FAKE_BUFFER" 2>/dev/null || exit 1 ;;
  "delete-buffer -b") : > "$FAKE_BUFFER" ;;
  "display-message"*)
    # -p means "print the format", which is how the handler reads the client
    # and session. Everything else is a message to the operator.
    for a in "$@"; do [ "$a" = "-p" ] && { echo "${FAKE_FORMAT:-}"; exit 0; }; done ;;
  "show-environment"*) printf 'GC_AGENT=%s\n' "${FAKE_AGENT:-}" ;;
esac
exit 0
TMUXSTUB
chmod +x "$TMP/bin/tmux"

# run_handler <cfg-dir> <topic> — seed the buffer, run the handler, wait for
# the backgrounded half to report. Returns the handler's exit code; the tmux
# and gc-visit-open call logs are left in $TMUX_CALLS / $CALLS.
run_handler() {           # [VAR=val ...] run_handler <cfg-dir> <topic>
    local cfg="$1" topic="$2" rc=0
    export CALLS="$TMP/calls.log" TMUX_CALLS="$TMP/tmux.log" FAKE_BUFFER="$TMP/buffer"
    : > "$CALLS"; : > "$TMUX_CALLS"
    printf '%s' "$topic" > "$FAKE_BUFFER"
    # The stub is prepended for THIS call only: the live half below needs the
    # real tmux, and a global override would silently hand it the stub.
    PATH="$TMP/bin:$PATH" sh "$SCRIPT" "$cfg" || rc=$?
    # The outcome is reported from a background subshell; poll for it rather
    # than sleeping a guessed interval.
    for _ in $(seq 1 100); do
        grep -q 'display-message .*-d ' "$TMUX_CALLS" && break
        sleep 0.05
    done
    return "$rc"
}

CFG_OK="$TMP/cfg-ok"; mkcfg "$CFG_OK" "$STUB_OK"
CFG_REACT="$TMP/cfg-react"; mkcfg "$CFG_REACT" "$STUB_REACT"
CFG_FAIL="$TMP/cfg-fail"; mkcfg "$CFG_FAIL" "$STUB_FAIL"

# (SAYOK) + (DASH) + argv shape
run_handler "$CFG_OK" "$HOSTILE"
calls=$(cat "$TMP/calls.log")
has "$calls" "argv=[--]" "DASH: the topic is passed behind --, never read as a flag"
has "$calls" "argv=[$HOSTILE]" "SAYOK: the handler forwards the message verbatim"
hasnt "$calls" "argv=[--topic]" "IDPASS: --topic is not forced, so a bead id still resolves as one"
tcalls=$(cat "$TMP/tmux.log")
has "$tcalls" "gc visit: subject tk-sub01 — visit tk-vis01 filed" "SAYOK: success names both ids"
has "$tcalls" "delete-buffer -b gc-visit-topic" "STALE: the topic buffer is deleted after the read"

# (REACT)
run_handler "$CFG_REACT" "why is dolt slow?"
tcalls=$(cat "$TMP/tmux.log")
has "$tcalls" "first reaction slung" "REACT: the react path is reported as such"
hasnt "$tcalls" "visit tk-vis" "REACT: no visit id is claimed when none was filed"

# (SAYFAIL)
run_handler "$CFG_FAIL" "something that will fail"
tcalls=$(cat "$TMP/tmux.log")
has "$tcalls" "gc visit FAILED (rc=4)" "SAYFAIL: failure is surfaced with its exit code"
has "$tcalls" "subject tk-sub03 exists" "SAYFAIL: the surviving subject bead is named"

# (BLANK) — blank and whitespace-only both file nothing.
for blank in "" "   "; do
    run_handler "$CFG_OK" "$blank"
    eq "$(cat "$TMP/calls.log")" "" "BLANK: '${blank}' invokes gc-visit-open not at all"
    has "$(cat "$TMP/tmux.log")" "nothing typed" "BLANK: '${blank}' still tells the operator"
done

# (INDICATOR)
FAKE_AGENT_NAME="gcvp.test-$$"
INDICATOR_PATH="/tmp/gc-status-gcvp-test-$$.indicator"
CFG_SLOW="$TMP/cfg-slow"; mkcfg "$CFG_SLOW" '#!/bin/sh
sleep 1
echo "gc-visit-open: subject tk-sub04 — visit filed (x)."'
rm -f "$INDICATOR_PATH"
(
    export CALLS="$TMP/calls.log" TMUX_CALLS="$TMP/tmux.log" FAKE_BUFFER="$TMP/buffer"
    export FAKE_FORMAT="gc-toolkit__probe" FAKE_AGENT="$FAKE_AGENT_NAME"
    : > "$TMUX_CALLS"
    printf '%s' "a slow topic" > "$FAKE_BUFFER"
    PATH="$TMP/bin:$PATH" sh "$SCRIPT" "$CFG_SLOW"
)
seen=0
for _ in $(seq 1 40); do
    [ -f "$INDICATOR_PATH" ] && { seen=1; break; }
    sleep 0.05
done
[ "$seen" -eq 1 ] \
    && ok "INDICATOR: the in-flight slot is written while the intake runs" \
    || bad "INDICATOR: no indicator at $INDICATOR_PATH while the intake ran"
for _ in $(seq 1 100); do
    [ -f "$INDICATOR_PATH" ] || break
    sleep 0.05
done
[ -f "$INDICATOR_PATH" ] \
    && { bad "INDICATOR: the slot was not cleared when the intake finished"; rm -f "$INDICATOR_PATH"; } \
    || ok "INDICATOR: the slot is cleared when the intake finishes"

# (TIMEOUT)
CFG_HANG="$TMP/cfg-hang"; mkcfg "$CFG_HANG" '#!/bin/sh
sleep 60'
if command -v timeout >/dev/null 2>&1; then
    GC_VISIT_INTAKE_TIMEOUT=1 run_handler "$CFG_HANG" "a topic that wedges"
    has "$(cat "$TMP/tmux.log")" "gc visit FAILED (rc=124)" "TIMEOUT: a wedged intake is reported, not left hanging"
    has "$(cat "$TMP/tmux.log")" "timed out after 1s" "TIMEOUT: the message says what happened"
else
    skip "TIMEOUT: timeout(1) not installed"
fi

# A missing intake script is reported, not silently swallowed.
CFG_NONE="$TMP/cfg-none"; mkdir -p "$CFG_NONE/assets/scripts"
run_handler "$CFG_NONE" "a topic" || true
has "$(cat "$TMP/tmux.log")" "intake script missing" "MISSING: an absent gc-visit-open.sh is reported to the pane"

###############################################################################
# BIND — what tmux-bindings.sh installs.
###############################################################################
if command -v tmux >/dev/null 2>&1; then
    tmux -L "$SOCKET" new-session -d -x 80 -y 24 'sleep 600' >/dev/null 2>&1
    GC_TMUX_SOCKET="$SOCKET" sh "$BINDINGS" "$CFG_OK" >/dev/null 2>&1
    bound=$(tmux -L "$SOCKET" list-keys -T prefix 2>/dev/null | grep -E '^bind-key +-T prefix +a ' || true)
    has "$bound" "command-prompt" "BIND: prefix+a opens a command-prompt"
    has "$bound" '%%%' "BIND: uses %%% (the quote-escaping form), not bare %%"
    has "$bound" "set-buffer -b gc-visit-topic" "BIND: the response is parked in a paste buffer"
    has "$bound" "tmux-visit-prompt.sh" "BIND: run-shell invokes the visit handler"
    hasnt "$bound" "tmux-spawn-thread.sh" "BIND: the retired thread spawner is gone from the binding"
    hasnt "$bound" "run-shell -b" "BIND: the handler runs FOREGROUND so presses serialise on the buffer"
else
    skip "BIND: tmux not installed"
fi

###############################################################################
# LIVE — real key presses through a real pty client.
###############################################################################
# `command-prompt` only exists inside an attached client, and its response can
# only be delivered by typing. script(1) supplies the pty; the sleeps let tmux
# attach and open the prompt before keys arrive. \002 is C-b, the default
# prefix on a fresh server.
#
# The pty needs a TERM the local terminfo database can actually drive: tmux
# refuses to attach under a terminal it cannot drive, and an agent shell
# frequently has TERM=dumb (or no TERM at all), where every case below fails
# with `open terminal failed: terminal does not support clear` rather than
# telling you anything about the handler. So the TERM for the private attach
# is resolved here, not inherited — and resolved by ATTACHING, not by name: a
# candidate is accepted only if a throwaway server takes a real client under
# it. A machine with no usable entry at all skips the live half instead of
# reporting a wall of red.
#
# The oracle is the `client-attached` hook firing — POSITIVE evidence from
# tmux that a client really connected — not the absence of an error string.
# tmux has more than one way to say no (`open terminal failed: ...` for a
# TERM it cannot drive, `missing or unsuitable terminal: ...` for one that is
# not in terminfo at all), so matching any single message silently accepts
# the terminals it does not happen to mention.
term_attaches() {   # term_attaches <term>
    local t=$1 flag="$TMP/term-attached" rc=1
    rm -f "$flag"
    tmux -L "$PROBE_SOCKET" kill-server >/dev/null 2>&1 || true
    tmux -L "$PROBE_SOCKET" new-session -d -x 80 -y 24 'sleep 30' >/dev/null 2>&1 || return 1
    tmux -L "$PROBE_SOCKET" set-hook -g client-attached "run-shell \"touch '$flag'\"" >/dev/null 2>&1 || true
    { sleep 0.7; printf '\002d'; sleep 0.3; } \
        | TERM="$t" script -qec "tmux -L $PROBE_SOCKET attach" /dev/null >/dev/null 2>&1
    [ -f "$flag" ] && rc=0
    tmux -L "$PROBE_SOCKET" kill-server >/dev/null 2>&1 || true
    rm -f "$flag"
    return $rc
}

LIVE_TERM=""
if command -v tmux >/dev/null 2>&1 && command -v script >/dev/null 2>&1; then
    for cand in "${TERM:-}" xterm-256color xterm screen ansi vt100; do
        [ -n "$cand" ] || continue
        if term_attaches "$cand"; then LIVE_TERM="$cand"; break; fi
    done
fi

press() {           # press <message>...
    local feed=("$@") m
    { sleep 1.5
      for m in "${feed[@]}"; do
          printf '\002'; sleep 0.3; printf 'a'; sleep 0.4; printf '%s\r' "$m"; sleep 0.6
      done
      sleep 2; printf '\002d'; sleep 0.5
    } | TERM="$LIVE_TERM" script -qec "tmux -L $SOCKET attach" /dev/null >/dev/null 2>&1
}

if command -v tmux >/dev/null 2>&1 && command -v script >/dev/null 2>&1 && [ -n "$LIVE_TERM" ]; then
    LIVE_CALLS="$TMP/live-calls.log"
    LIVE_CFG="$TMP/cfg-live"
    mkcfg "$LIVE_CFG" "$STUB_OK"
    # The stub inherits its CALLS path from the tmux server's environment,
    # which run-shell jobs inherit in turn.
    tmux -L "$SOCKET" kill-server >/dev/null 2>&1 || true
    tmux -L "$SOCKET" new-session -d -x 100 -y 30 'sleep 600' >/dev/null 2>&1
    tmux -L "$SOCKET" set-environment -g CALLS "$LIVE_CALLS" >/dev/null 2>&1
    GC_TMUX_SOCKET="$SOCKET" sh "$BINDINGS" "$LIVE_CFG" >/dev/null 2>&1

    : > "$LIVE_CALLS"
    press "$HOSTILE" "second topic; also fine" "third one's here; yes"
    live=$(cat "$LIVE_CALLS" 2>/dev/null)

    has "$live" "argv=[$HOSTILE]" "ROUNDTRIP: apostrophe, semicolon and quotes survive a real key press"
    has "$live" "argv=[second topic; also fine]" "THREE: the second press lands"
    has "$live" "argv=[third one's here; yes]" "THREE: the third press lands"
    eq "$(grep -c '=== call ===' <<< "$live")" "3" "THREE: three presses, three independent invocations"
    msgs=$(tmux -L "$SOCKET" show-messages 2>/dev/null || true)
    has "$msgs" "visit tk-vis01 filed" "ROUNDTRIP: the outcome reaches the operator's client"

    # (NOFREEZE) A press must be able to start while the previous intake is
    # still running: the foreground half exists only to order the buffer read.
    NOFREEZE_CFG="$TMP/cfg-nofreeze"
    mkcfg "$NOFREEZE_CFG" '#!/bin/sh
printf "%s\n" "$(date +%s)" >> "$CALLS"
sleep 5'
    tmux -L "$SOCKET" kill-server >/dev/null 2>&1 || true
    tmux -L "$SOCKET" new-session -d -x 100 -y 30 'sleep 600' >/dev/null 2>&1
    tmux -L "$SOCKET" set-environment -g CALLS "$TMP/nofreeze.log" >/dev/null 2>&1
    GC_TMUX_SOCKET="$SOCKET" sh "$BINDINGS" "$NOFREEZE_CFG" >/dev/null 2>&1
    : > "$TMP/nofreeze.log"
    press "first slow topic" "second while first runs"
    mapfile -t starts < "$TMP/nofreeze.log"
    if [ "${#starts[@]}" -eq 2 ]; then
        gap=$(( starts[1] - starts[0] ))
        [ "$gap" -lt 4 ] \
            && ok "NOFREEZE: the second intake starts ${gap}s in, while the first still runs" \
            || bad "NOFREEZE: the second intake waited ${gap}s — the foreground half is blocking"
    else
        bad "NOFREEZE: expected 2 intakes, got ${#starts[@]}"
    fi
else
    if command -v tmux >/dev/null 2>&1 && command -v script >/dev/null 2>&1; then
        skip "ROUNDTRIP/THREE/NOFREEZE: no TERM in the local terminfo database can attach a tmux client"
    else
        skip "ROUNDTRIP/THREE/NOFREEZE: need both tmux and script(1) for a pty client"
    fi
fi

###############################################################################
# GONE — the retired spawner, and every live pointer at it.
###############################################################################
[ -e "$HERE/tmux-spawn-thread.sh" ] \
    && bad "GONE: tmux-spawn-thread.sh still exists" \
    || ok "GONE: tmux-spawn-thread.sh is deleted"

# specs/ is the historical record of what was decided at the time and is
# deliberately not rewritten; everything else must not point at a dead script.
# This file is excluded too — it has to name what it forbids, and a case
# label is not a pointer at live code.
REPO="$(cd "$HERE/../.." && pwd)"
if command -v git >/dev/null 2>&1 && git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1; then
    dangling=$(git -C "$REPO" grep -ln 'tmux-spawn-thread' \
        -- . ':(exclude)specs' ':(exclude)assets/scripts/tmux-visit-prompt.test.sh' 2>/dev/null || true)
    eq "$dangling" "" "GONE: no live file still references tmux-spawn-thread.sh"
else
    skip "GONE: not a git checkout, cannot sweep for references"
fi

echo
echo "passed: $PASS  failed: $FAIL  skipped: $SKIP"
[ "$FAIL" -eq 0 ]
