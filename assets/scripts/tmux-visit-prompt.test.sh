#!/usr/bin/env bash
# Test for tmux-visit-prompt.sh — the `prefix + a` operator-origin visit
# intake (tk-bn1oi, input surface restored in tk-7z8c6), and for the binding
# tmux-bindings.sh installs for it.
#
# Two halves, because the defect classes are different:
#
#   HERMETIC — the handler run directly with `tmux`, `gum` and
#     `gc-visit-open.sh` stubbed on PATH / in a fake config dir. No tmux
#     server, no city. The tmux stub RUNS the popup body it is handed, with
#     the gum stub on PATH, so the command string the handler assembles is
#     executed rather than merely inspected.
#   LIVE     — a real tmux server on a private socket, driven through a real
#     pty client with real key presses into a real `gum write` popup. Guarded
#     on tmux + script(1) + gum; skipped with a notice where any is missing.
#
# What the cases are guarding, and why each was worth a test:
#
#   (BIND)      tmux-bindings.sh must bind prefix+a to a plain backgrounded
#               run-shell of the handler, and must NOT reference the retired
#               tmux-spawn-thread.sh. No `command-prompt`, no `set-buffer`:
#               that shape is what cost the operator multi-line input, and
#               `-b` is load-bearing now that the handler holds a modal popup
#               open for as long as the operator is typing.
#   (MULTILINE) THE acceptance criterion (tk-7z8c6). `command-prompt` is
#               single-line by construction, so the operator could file a
#               sentence and nothing longer. A message with embedded newlines
#               must reach gc-visit-open's argv with every line intact — which
#               is what reaches the bead, since gc-visit-open writes the topic
#               verbatim into the subject bead's body as well as its title.
#   (ROUNDTRIP) the OTHER acceptance criterion, and the reason tk-02v4g moved
#               to a popup in the first place. `command-prompt` substitutes the
#               response as TEXT and then PARSES the result as a tmux command,
#               so a message containing `;` or `"` spliced into a command line
#               is mangled or partly EXECUTED (specs/tk-1zd25/design.md). Typed
#               through a real pty, an apostrophe + semicolon + quotes + `$` +
#               `~` + backslash must reach the handler's argv byte-for-byte.
#   (THREE)     three presses in a row are three independent topics, with no
#               cross-talk and nothing lost.
#   (NOFREEZE)  a press must be able to start while the PREVIOUS intake is
#               still running. The popup is modal for the length of the
#               typing, so the slow half has to stay backgrounded or the key
#               serialises the operator behind `gc bd create`.
#   (TMPFILE)   each press reads its own mktemp file, and the file is gone when
#               the handler exits. The predecessor parked the message in a
#               paste buffer with a FIXED name, so press N+1 could overwrite
#               what press N had not read yet — the foreground read existed
#               only to sequence around that. A file per press removes the
#               collision instead, and this is what pins it.
#   (CANCEL)    Esc is a true cancel: gum exits non-zero, `display-popup -E`
#               propagates it, and nothing is filed and nothing is said.
#   (POPUPFAIL) ...but a popup that could not OPEN is not a cancel. tmux
#               writes a diagnostic to stderr in that case and nothing in the
#               cancel case, which is the only thing telling them apart. A
#               broken key that looks like a cancel is a silent failure.
#   (GUMMISS)   gum absent surfaces an install hint instead of an opaque
#               "command not found" inside a popup that closes instantly.
#   (PREFLIGHT) a missing intake script is reported BEFORE the popup opens.
#               Asking the operator to type a paragraph and only then admitting
#               there is nothing to file it with wastes the thought this key
#               exists to catch.
#   (SHAPE)     the popup runs `gum write` — gum's long-form primitive — not
#               `gum input`, which is single-line and would reproduce this bug
#               one layer down; with a textarea more than one row high, and
#               with gum's own key hints on, which is what keeps submit and
#               newline discoverable without this file hardcoding keys that
#               differ across gum versions.
#   (BLANK)     a blank submit files nothing — no bead with an empty title —
#               and still says so.
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
# Substring tests via bash pattern matching rather than grep: a needle here can
# legitimately span LINES (a multi-line topic is the whole point of MULTILINE),
# and `grep -F` would quietly degrade that to "any one of these lines appears".
# The needle is quoted inside the pattern, so it stays literal — the hostile
# message below is full of glob characters.
has()  { [[ "$1" == *"$2"* ]] && ok "$3" || bad "$3 (in: $1)"; }
hasnt() { [[ "$1" == *"$2"* ]] && bad "$3 (in: $1)" || ok "$3"; }

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

# The multi-line message. Blank line included: a paragraph break is the first
# thing a real operator types that `command-prompt` could not carry.
MULTI="the refinery stalled again

first: the anchor is unrouted; second: nobody re-gates it
so it just sits there"

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
# HERMETIC — handler run directly, `tmux` and `gum` stubbed.
###############################################################################
# The tmux stub logs every call and, for display-popup, RUNS the popup body the
# handler assembled — the same string the real tmux hands to `sh -c`, with the
# same exit-code propagation `-E` performs. So the redirect, the shell quoting
# of the tmpfile path and the read-back are exercised, not simulated.
mkdir -p "$TMP/bin" "$TMP/gumbin" "$TMP/tmpfiles"
cat > "$TMP/bin/tmux" <<'TMUXSTUB'
#!/usr/bin/env bash
printf 'tmux %s\n' "$*" >> "$TMUX_CALLS"
case "$1" in
  display-popup)
    # A popup that cannot open at all (no current client, a client too small
    # for the geometry): tmux writes a diagnostic to stderr and returns
    # non-zero WITHOUT running the body. Reproduced here because that stderr
    # is the handler's only way to tell this apart from a cancel.
    if [ -n "${FAKE_POPUP_OPEN_ERR:-}" ]; then
        echo "$FAKE_POPUP_OPEN_ERR" >&2
        exit 1
    fi
    body="${!#}"
    rc=0
    sh -c "$body" || rc=$?
    exit "$rc" ;;
  display-message)
    # -p means "print the format", which is how the handler reads the client
    # and session. Everything else is a message to the operator.
    for a in "$@"; do [ "$a" = "-p" ] && { echo "${FAKE_FORMAT:-}"; exit 0; }; done ;;
  show-environment) printf 'GC_AGENT=%s\n' "${FAKE_AGENT:-}" ;;
esac
exit 0
TMUXSTUB
chmod +x "$TMP/bin/tmux"

# The gum stub stands in for the operator: it prints what was "typed" on
# stdout, exactly as `gum write` does, and can refuse like an Esc.
cat > "$TMP/gumbin/gum" <<'GUMSTUB'
#!/usr/bin/env bash
printf 'gum %s\n' "$*" >> "$GUM_CALLS"
# Esc (or ^C): gum exits non-zero having written nothing.
[ "${FAKE_GUM_RC:-0}" = 0 ] || exit "${FAKE_GUM_RC}"
printf '%s\n' "${FAKE_TOPIC:-}"
GUMSTUB
chmod +x "$TMP/gumbin/gum"

# run_handler <cfg-dir> <topic> — "type" the topic into the stubbed popup, run
# the handler, wait for the backgrounded half to report. Returns the handler's
# exit code; the tmux, gum and gc-visit-open call logs are left in
# $TMUX_CALLS / $GUM_CALLS / $CALLS. Set EXPECT_SAY=0 for the paths that
# deliberately say nothing, so the poll below does not burn its full budget.
run_handler() {           # [VAR=val ...] run_handler <cfg-dir> <topic>
    local cfg="$1" topic="$2" rc=0
    export CALLS="$TMP/calls.log" TMUX_CALLS="$TMP/tmux.log" GUM_CALLS="$TMP/gum.log"
    export FAKE_TOPIC="$topic" TMPDIR="$TMP/tmpfiles"
    : > "$CALLS"; : > "$TMUX_CALLS"; : > "$GUM_CALLS"
    # The stubs are prepended for THIS call only: the live half below needs the
    # real tmux and the real gum, and a global override would hand it the stubs.
    # HANDLER_PATH replaces that prefix outright for the one case that needs a
    # PATH with no gum on it at all.
    PATH="${HANDLER_PATH:-$TMP/gumbin:$TMP/bin:$PATH}" sh "$SCRIPT" "$cfg" || rc=$?
    # The outcome is reported from a background subshell; poll for it rather
    # than sleeping a guessed interval.
    if [ "${EXPECT_SAY:-1}" = 1 ]; then
        for _ in $(seq 1 100); do
            grep -q 'display-message .*-d ' "$TMUX_CALLS" && break
            sleep 0.05
        done
    fi
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

# (SHAPE) — what the popup actually runs.
gcalls=$(cat "$TMP/gum.log")
has "$tcalls" "display-popup -E" "SHAPE: the input surface is a popup with -E (so the inner exit code propagates)"
hasnt "$tcalls" "command-prompt" "SHAPE: the single-line command-prompt is gone from the handler"
has "$gcalls" "gum write" "SHAPE: the popup runs gum write, gum's long-form primitive"
hasnt "$gcalls" "gum input" "SHAPE: not gum input, which is single-line and would reproduce the bug"
has "$gcalls" "--show-help" "SHAPE: gum renders its own key hints, so submit/newline stay discoverable"
has "$gcalls" "Esc" "SHAPE: the header names the cancel key, which gum's hint line omits"
gh=$(sed -n 's/.*--height \([0-9][0-9]*\).*/\1/p' "$TMP/gum.log" | head -1)
{ [ -n "$gh" ] && [ "$gh" -ge 2 ]; } \
    && ok "SHAPE: the textarea is more than one row high (--height $gh)" \
    || bad "SHAPE: the textarea is not sized for multi-line input (--height '${gh:-unset}')"

# (MULTILINE) — the acceptance criterion. Every line, and the blank line
# between them, reaches gc-visit-open as ONE argument.
run_handler "$CFG_OK" "$MULTI"
has "$(cat "$TMP/calls.log")" "argv=[$MULTI]" "MULTILINE: a multi-line message reaches the intake with every line intact"
eq "$(grep -c '=== call ===' < "$TMP/calls.log")" "1" "MULTILINE: it arrives as one topic, not one per line"

# (TMPFILE) — a file per press, and no file left behind.
run_handler "$CFG_OK" "first topic"
tmpf1=$(sed -n "s/.*> '\([^']*\)'.*/\1/p" "$TMP/tmux.log" | head -1)
run_handler "$CFG_OK" "second topic"
tmpf2=$(sed -n "s/.*> '\([^']*\)'.*/\1/p" "$TMP/tmux.log" | head -1)
{ [ -n "$tmpf1" ] && [ "$tmpf1" != "$tmpf2" ]; } \
    && ok "TMPFILE: each press reads its own file, so no press can overwrite another's topic" \
    || bad "TMPFILE: both presses used '${tmpf1:-none}' — a shared slot is exactly the hazard"
eq "$(find "$TMP/tmpfiles" -mindepth 1 | wc -l | tr -d ' ')" "0" "TMPFILE: the topic file is removed when the handler exits"

# (CANCEL)
EXPECT_SAY=0 FAKE_GUM_RC=1 run_handler "$CFG_OK" "typed, then thought better of it"
eq "$(cat "$TMP/calls.log")" "" "CANCEL: Esc files nothing"
hasnt "$(cat "$TMP/tmux.log")" "-d " "CANCEL: ...and says nothing, because it was deliberate"

# (POPUPFAIL) — the same non-zero exit, but with tmux complaining on stderr.
FAKE_POPUP_OPEN_ERR="no current client" run_handler "$CFG_OK" "a topic nobody can type" || true
has "$(cat "$TMP/tmux.log")" "could not open the input popup: no current client" \
    "POPUPFAIL: a popup that never opened is reported, not mistaken for a cancel"

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
    export CALLS="$TMP/calls.log" TMUX_CALLS="$TMP/tmux.log" GUM_CALLS="$TMP/gum.log"
    export FAKE_TOPIC="a slow topic" TMPDIR="$TMP/tmpfiles"
    export FAKE_FORMAT="gc-toolkit__probe" FAKE_AGENT="$FAKE_AGENT_NAME"
    : > "$TMUX_CALLS"
    PATH="$TMP/gumbin:$TMP/bin:$PATH" sh "$SCRIPT" "$CFG_SLOW"
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

# (PREFLIGHT) — a missing intake script is reported before anything is typed.
CFG_NONE="$TMP/cfg-none"; mkdir -p "$CFG_NONE/assets/scripts"
run_handler "$CFG_NONE" "a topic" || true
tcalls=$(cat "$TMP/tmux.log")
has "$tcalls" "intake script missing" "PREFLIGHT: an absent gc-visit-open.sh is reported to the pane"
hasnt "$tcalls" "display-popup" "PREFLIGHT: ...before the popup opens, so no typing is wasted"

# (GUMMISS) — needs a PATH with the tmux stub and no gum of any kind.
if PATH="/usr/bin:/bin" command -v gum >/dev/null 2>&1; then
    skip "GUMMISS: gum is installed under /usr/bin, cannot construct a gum-free PATH"
else
    HANDLER_PATH="$TMP/bin:/usr/bin:/bin" run_handler "$CFG_OK" "a topic" || true
    tcalls=$(cat "$TMP/tmux.log")
    has "$tcalls" "'gum' not on PATH" "GUMMISS: a missing gum surfaces an install hint"
    hasnt "$tcalls" "display-popup" "GUMMISS: ...instead of an opaque failure inside a popup"
fi

###############################################################################
# BIND — what tmux-bindings.sh installs.
###############################################################################
if command -v tmux >/dev/null 2>&1; then
    tmux -L "$SOCKET" new-session -d -x 80 -y 24 'sleep 600' >/dev/null 2>&1
    GC_TMUX_SOCKET="$SOCKET" sh "$BINDINGS" "$CFG_OK" >/dev/null 2>&1
    bound=$(tmux -L "$SOCKET" list-keys -T prefix 2>/dev/null | grep -E '^bind-key +-T prefix +a ' || true)
    has "$bound" "run-shell -b" "BIND: prefix+a backgrounds the handler (a modal popup must not hold the command queue)"
    has "$bound" "tmux-visit-prompt.sh" "BIND: run-shell invokes the visit handler"
    hasnt "$bound" "command-prompt" "BIND: the single-line command-prompt is gone"
    hasnt "$bound" "set-buffer" "BIND: and so is the shared paste buffer it needed"
    hasnt "$bound" "tmux-spawn-thread.sh" "BIND: the retired thread spawner is gone from the binding"
else
    skip "BIND: tmux not installed"
fi

###############################################################################
# LIVE — real key presses into a real gum popup through a real pty client.
###############################################################################
# The popup only exists inside an attached client, and its contents can only
# be delivered by typing. script(1) supplies the pty; the sleeps let tmux
# attach, then let the popup open and gum start, before keys arrive. \002 is
# C-b, the default prefix on a fresh server.
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
if command -v tmux >/dev/null 2>&1 && command -v script >/dev/null 2>&1 && command -v gum >/dev/null 2>&1; then
    for cand in "${TERM:-}" xterm-256color xterm screen ansi vt100; do
        [ -n "$cand" ] || continue
        if term_attaches "$cand"; then LIVE_TERM="$cand"; break; fi
    done
fi

# Submit is sent as CR and then, after a beat, as C-d. gum's write keymap has
# moved between versions — Enter submits and C-j takes a newline in current
# gum, older builds submit on C-d — and pinning either here would make this
# test a statement about a gum version rather than about the handler. Sending
# both is safe in both worlds: whichever is the newline key adds one trailing
# blank line, and the handler's `$(cat …)` strips it, so the topic that
# arrives is identical. The spare keystroke lands in a `sleep 600` pane, which
# has no shell to read it. Newlines inside a message are sent as C-j (\012),
# which every gum build takes as a newline.
press() {           # press <message>...
    local feed=("$@") m
    { sleep 1.5
      for m in "${feed[@]}"; do
          printf '\002'; sleep 0.4; printf 'a'
          sleep 1.5
          printf '%s' "$m"; sleep 0.4
          printf '\r'; sleep 0.5; printf '\004'; sleep 0.6
      done
      sleep 2; printf '\002d'; sleep 0.5
    } | TERM="$LIVE_TERM" script -qec "tmux -L $SOCKET attach" /dev/null >/dev/null 2>&1
}

if [ -n "$LIVE_TERM" ]; then
    LIVE_CALLS="$TMP/live-calls.log"
    LIVE_CFG="$TMP/cfg-live"
    mkcfg "$LIVE_CFG" "$STUB_OK"
    # The stub inherits its CALLS path from the tmux server's environment,
    # which run-shell jobs and popup commands inherit in turn.
    tmux -L "$SOCKET" kill-server >/dev/null 2>&1 || true
    tmux -L "$SOCKET" new-session -d -x 100 -y 30 'sleep 600' >/dev/null 2>&1
    tmux -L "$SOCKET" set-environment -g CALLS "$LIVE_CALLS" >/dev/null 2>&1
    GC_TMUX_SOCKET="$SOCKET" sh "$BINDINGS" "$LIVE_CFG" >/dev/null 2>&1

    : > "$LIVE_CALLS"
    press "$HOSTILE" "$MULTI" "third one's here; yes"
    live=$(cat "$LIVE_CALLS" 2>/dev/null)

    has "$live" "argv=[$HOSTILE]" "ROUNDTRIP: apostrophe, semicolon and quotes survive a real key press"
    has "$live" "argv=[$MULTI]" "MULTILINE: a paragraph typed into the popup arrives whole"
    has "$live" "argv=[third one's here; yes]" "THREE: the third press lands"
    eq "$(grep -c '=== call ===' <<< "$live")" "3" "THREE: three presses, three independent invocations"
    msgs=$(tmux -L "$SOCKET" show-messages 2>/dev/null || true)
    has "$msgs" "visit tk-vis01 filed" "ROUNDTRIP: the outcome reaches the operator's client"

    # (NOFREEZE) A press must be able to start while the previous intake is
    # still running: the popup is modal for as long as the operator types, so
    # the intake behind it has to stay backgrounded.
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
        [ "$gap" -lt 5 ] \
            && ok "NOFREEZE: the second intake starts ${gap}s in, while the first still runs" \
            || bad "NOFREEZE: the second intake waited ${gap}s — the slow half is not backgrounded"
    else
        bad "NOFREEZE: expected 2 intakes, got ${#starts[@]}"
    fi
else
    if command -v tmux >/dev/null 2>&1 && command -v script >/dev/null 2>&1 && command -v gum >/dev/null 2>&1; then
        skip "ROUNDTRIP/MULTILINE/THREE/NOFREEZE: no TERM in the local terminfo database can attach a tmux client"
    else
        skip "ROUNDTRIP/MULTILINE/THREE/NOFREEZE: need tmux, script(1) and gum for a real popup"
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
