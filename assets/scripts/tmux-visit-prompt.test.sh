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
#   (TMPFILE)   each press reads its own file, and the file is gone once the
#               intake CONFIRMS an id. The predecessor parked the message in a
#               paste buffer with a FIXED name, so press N+1 could overwrite
#               what press N had not read yet — the foreground read existed
#               only to sequence around that. A file per press removes the
#               collision instead, and this is what pins it.
#   (DRAFTKEEP) tk-w4dp4, and the reason the rest of this group exists: the
#               handler used to arm `trap 'rm -f' EXIT` over the draft, so
#               EVERY exit destroyed the only copy of what was typed. An
#               operator lost a paragraph to it with zero trace — no subject,
#               no visit, no bead in any ledger. A failed intake must now leave
#               the text on disk and NAME its path, because a draft that
#               survives is a retry and a deleted one is the bug.
#   (DRAFTOK)   the inverse, and what keeps DRAFTKEEP from being "never delete
#               anything": a confirmed filing DOES remove it. An id came back,
#               the thought is durable, and a draft left behind would train the
#               operator to ignore the directory.
#   (UNCONFIRM) rc=0 is not the confirmation — the id is. An intake that exits
#               clean having named neither subject nor visit has said nothing
#               about what survived, so the draft is kept.
#   (MKTEMPFAIL) the draft file could not be created. This was unguarded under
#               `set -eu`, so the handler died before the popup with no message
#               at all — indistinguishable, from the operator's seat, from a
#               key that does nothing. /tmp here is a shared tmpfs whose
#               pressure fluctuates, so this is a live path. Driven by refusing
#               `mktemp`, NOT by an unwritable directory: those are two guards
#               and the directory one has a fallback, so it never reaches the
#               call. An unwritable-dir fixture passes against the unguarded
#               script and proves nothing.
#   (DRAFTDIRFAIL) the other half of that split — an unwritable draft directory
#               falls back and the press still files. A bad directory must not
#               cost the thought.
#   (CANCELSAY)  a cancel is never silent. The FILE cannot tell a cancel-after-
#               typing from an Esc on an empty buffer: `gum write` holds the
#               buffer in memory and prints it only on submit, so Esc after five
#               paragraphs exits 1 having written NOTHING. An earlier version of
#               this suite asserted the opposite via a stub that printed text
#               and THEN failed — behaviour the real primitive never exhibits —
#               so the branch was green and dead at once. CANCELPTY below pins
#               what gum actually does; this case pins the consequence: since
#               the two cannot be distinguished, silence is the wrong default,
#               because silence is exactly what makes a cancel and a broken key
#               identical from the operator's seat.
#   (CANCELPTY) the live control for that, through a real pty: type text, press
#               Esc, and assert the draft file is EMPTY and the handler reports
#               rather than staying silent. Without this the hermetic case is a
#               statement about a stub.
#   (CANCELKEEP) the preserve branch is still correct IF anything ever reaches
#               the file on a non-zero exit (a partial write, a different popup
#               failure, a future gum). Kept and tested as that, not as a claim
#               about Esc.
#   (REAPSCOPE) the reaper must not reach a file this script does not own. The
#               unwritable-dir fallback used to land on the shared temp ROOT,
#               where `draft-*` from any other tool was inside its scope — a
#               real deletion, reproduced in review.
#   (BLANKDUR)  the blank branch is also where a truncated write lands: a
#               paragraph whose redirect wrote nothing arrives here looking
#               exactly like an empty submit. It flashed for 3s. Too short
#               when the cost is a paragraph.
#   (DRAFTDIR)  drafts default off the city's shared /tmp, and the directory is
#               stable and greppable rather than a random name, so "where did
#               my text go" has one answer.
#   (REAP)      ...and the directory that never deletes anything is a new
#               problem, so drafts older than the retention window are reaped
#               and fresh ones are not.
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
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-tmux-visit-prompt-test.XXXXXX")"
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
# A cancel that still put text in the buffer: gum writes, THEN exits non-zero.
# The tmux layer cannot tell this from an Esc on an empty buffer — same exit
# code, same empty stderr — so only the file distinguishes them.
if [ -n "${FAKE_GUM_PARTIAL:-}" ]; then
    printf '%s\n' "${FAKE_TOPIC:-}"
    exit "${FAKE_GUM_PARTIAL}"
fi
# Esc (or ^C): gum exits non-zero having written nothing.
[ "${FAKE_GUM_RC:-0}" = 0 ] || exit "${FAKE_GUM_RC}"
printf '%s\n' "${FAKE_TOPIC:-}"
GUMSTUB
chmod +x "$TMP/gumbin/gum"

# `mktemp` stubbed as a PASS-THROUGH, so the handler's own mktemp guard can be
# driven without touching the directory — which is a DIFFERENT guard. Making a
# directory unwritable exercises the mkdir/-w check and its /tmp fallback; it
# never reaches the mktemp call, so an unguarded mktemp survives that case
# entirely. Only refusing mktemp itself tests the guard that was missing.
REAL_MKTEMP="$(command -v mktemp)"; export REAL_MKTEMP
cat > "$TMP/bin/mktemp" <<'MKSTUB'
#!/usr/bin/env bash
[ -n "${FAKE_MKTEMP_RC:-}" ] && exit "${FAKE_MKTEMP_RC}"
exec "$REAL_MKTEMP" "$@"
MKSTUB
chmod +x "$TMP/bin/mktemp"

# run_handler <cfg-dir> <topic> — "type" the topic into the stubbed popup, run
# the handler, wait for the backgrounded half to report. Returns the handler's
# exit code; the tmux, gum and gc-visit-open call logs are left in
# $TMUX_CALLS / $GUM_CALLS / $CALLS. Set EXPECT_SAY=0 for the paths that
# deliberately say nothing, so the poll below does not burn its full budget.
run_handler() {           # [VAR=val ...] run_handler <cfg-dir> <topic>
    local cfg="$1" topic="$2" rc=0
    export CALLS="$TMP/calls.log" TMUX_CALLS="$TMP/tmux.log" GUM_CALLS="$TMP/gum.log"
    export FAKE_TOPIC="$topic" TMPDIR="$TMP/tmpfiles"
    # Drafts are durable by design now, so the test must own the directory or
    # a run would write into the operator's real XDG state.
    export GC_VISIT_DRAFT_DIR="${DRAFT_DIR_OVERRIDE:-$TMP/drafts}"
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
# (DRAFTOK) — the confirmed filing above removed its draft. Asserted on the
# draft directory, not on TMPDIR: drafts are durable state now and live where
# the handler puts them.
eq "$(find "$TMP/drafts" -mindepth 1 2>/dev/null | wc -l | tr -d ' ')" "0" \
   "DRAFTOK: a confirmed filing removes the draft"
eq "$(find "$TMP/tmpfiles" -mindepth 1 2>/dev/null | wc -l | tr -d ' ')" "0" \
   "TMPFILE: nothing is left in TMPDIR either"

# (CANCEL) + (CANCELSAY) — a cancel. The gum stub does what real gum does on
# Esc: exits non-zero having written NOTHING, whatever was "typed".
FAKE_GUM_RC=1 run_handler "$CFG_OK" "typed, then thought better of it"
eq "$(cat "$TMP/calls.log")" "" "CANCEL: Esc files nothing"
eq "$(find "$TMP/drafts" -mindepth 1 2>/dev/null | wc -l | tr -d ' ')" "0" \
   "CANCEL: an empty buffer leaves no draft behind"
tcalls=$(cat "$TMP/tmux.log")
has "$tcalls" "cancelled — nothing filed" \
    "CANCELSAY: a cancel says so — silence is what makes it indistinguishable from a broken key"
has "$tcalls" "Esc discards" \
    "CANCELSAY: ...and names the reason the text is gone, which is the one fact that makes it legible"

# (CANCELKEEP) — the preserve branch, exercised on the ONLY thing that can
# reach it: a non-zero exit that nonetheless left bytes in the file. Real `gum
# write` never does this on Esc (CANCELPTY proves it), so this case is a
# statement about a partial write, a different popup failure, or a future gum —
# NOT about cancelling. It is kept because the branch is correct if that ever
# happens; it is labelled this way because the previous label claimed it
# satisfied the bead's cancel acceptance, and it does not.
FAKE_GUM_PARTIAL=1 run_handler "$CFG_OK" "half a thought I did not mean to lose" || true
tcalls=$(cat "$TMP/tmux.log")
has "$tcalls" "DRAFT KEPT" "CANCELKEEP: bytes in the file on a non-zero exit are preserved, not dropped"
kept=$(find "$TMP/drafts" -type f -name 'draft-*' 2>/dev/null | head -1)
{ [ -n "$kept" ] && grep -q 'half a thought I did not mean to lose' "$kept"; } \
    && ok "CANCELKEEP: the typed text is still on disk" \
    || bad "CANCELKEEP: the typed text is gone (kept='${kept:-none}')"
has "$tcalls" "$(basename "${kept:-none}")" "CANCELKEEP: the message names the draft's path"
rm -f "$TMP"/drafts/draft-*

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

# (DRAFTKEEP) — the bead. The same failing intake as SAYFAIL: the subject bead
# survives, and so must the text, because the subject id alone does not let the
# operator retry — the paragraph does. The path leads the message because
# display-message truncates at the client width and the recovery handle is the
# half that must survive.
kept=$(find "$TMP/drafts" -type f -name 'draft-*' 2>/dev/null | head -1)
{ [ -n "$kept" ] && grep -q 'something that will fail' "$kept"; } \
    && ok "DRAFTKEEP: a failed intake leaves the typed text on disk" \
    || bad "DRAFTKEEP: a failed intake destroyed the draft (kept='${kept:-none}')"
has "$tcalls" "DRAFT KEPT" "DRAFTKEEP: ...and says so"
has "$tcalls" "$(basename "${kept:-none}")" "DRAFTKEEP: ...naming the path it was kept at"
case "$tcalls" in *"DRAFT KEPT"*"gc visit FAILED"*) ok "DRAFTKEEP: the path leads, so a truncated message still carries it" ;;
                  *) bad "DRAFTKEEP: the draft path is not first in the message" ;; esac
rm -f "$TMP"/drafts/draft-*

# (UNCONFIRM) — rc=0 is not the confirmation; the id is. An intake that exits
# clean and names neither subject nor visit has said nothing about what
# survived, so the draft is kept rather than assumed durable.
CFG_QUIET="$TMP/cfg-quiet"; mkcfg "$CFG_QUIET" '#!/bin/sh
echo "gc-visit-open: done."'
run_handler "$CFG_QUIET" "a topic whose fate nobody reported"
tcalls=$(cat "$TMP/tmux.log")
has "$tcalls" "named no subject or visit" "UNCONFIRM: a clean exit with no id is reported as unconfirmed"
kept=$(find "$TMP/drafts" -type f -name 'draft-*' 2>/dev/null | head -1)
{ [ -n "$kept" ] && grep -q 'a topic whose fate nobody reported' "$kept"; } \
    && ok "UNCONFIRM: ...and the draft is kept" \
    || bad "UNCONFIRM: the draft was dropped on an unconfirmed filing"
rm -f "$TMP"/drafts/draft-*

# (MKTEMPFAIL) — the draft file cannot be created. This was an unguarded
# `mktemp` under `set -eu`: the handler died before the popup with NO message
# at all, which is exactly what "the key does nothing" looks like from the
# operator's seat. Driven by refusing mktemp rather than by an unwritable
# directory, because those are two different guards and only this one reaches
# the call: the directory check below has a fallback and never gets there.
FAKE_MKTEMP_RC=1 EXPECT_SAY=0 run_handler "$CFG_OK" "a topic with nowhere to land" || true
tcalls=$(cat "$TMP/tmux.log")
has "$tcalls" "cannot create a draft file" "MKTEMPFAIL: a draft file that cannot be created is reported, not silent"
eq "$(cat "$TMP/gum.log")" "" "MKTEMPFAIL: ...and the popup never opens, so no typing is wasted"
eq "$(cat "$TMP/calls.log")" "" "MKTEMPFAIL: ...and nothing is filed"

# The OTHER guard, and the reason the case above cannot stand in for it: an
# unwritable draft directory must not kill the key. It falls back, says so, and
# the press still files.
if [ "$(id -u)" -eq 0 ]; then
    # root ignores directory modes, so the unwritable dir cannot be staged.
    ok "DRAFTDIRFAIL: skipped (running as root; chmod cannot make a dir unwritable)"
else
    UNWRITABLE="$TMP/nodraft"
    mkdir -p "$UNWRITABLE"; chmod 500 "$UNWRITABLE"
    DRAFT_DIR_OVERRIDE="$UNWRITABLE" run_handler "$CFG_OK" "a topic whose dir is read-only" || true
    tcalls=$(cat "$TMP/tmux.log")
    has "$tcalls" "not writable" "DRAFTDIRFAIL: an unwritable draft dir is reported"
    has "$(cat "$TMP/calls.log")" "argv=[a topic whose dir is read-only]" \
        "DRAFTDIRFAIL: ...and the press still files, because a bad dir must not cost the thought"
    chmod 700 "$UNWRITABLE"
fi

# (BLANKDUR) — the blank branch is also where a truncated write lands, so a
# paragraph can be lost behind it. Three seconds was too short for that.
run_handler "$CFG_OK" ""
blankdur=$(sed -n 's/.*-d \([0-9][0-9]*\) gc visit: nothing typed.*/\1/p' "$TMP/tmux.log" | head -1)
{ [ -n "$blankdur" ] && [ "$blankdur" -gt 3000 ]; } \
    && ok "BLANKDUR: the blank message holds longer than the old 3s flash (${blankdur}ms)" \
    || bad "BLANKDUR: the blank message is still a flash (-d '${blankdur:-unset}')"
has "$(cat "$TMP/tmux.log")" "draft write failed" \
    "BLANKDUR: ...and names the other thing it might have been"

# (DRAFTDIR) — with no override, drafts land off the city's shared /tmp, in a
# stable directory rather than a random name.
FAKE_HOME="$TMP/fakehome"; mkdir -p "$FAKE_HOME"
(
    export CALLS="$TMP/calls.log" TMUX_CALLS="$TMP/tmux-dd.log" GUM_CALLS="$TMP/gum.log"
    export FAKE_TOPIC="where does this land" TMPDIR="$TMP/tmpfiles"
    export HOME="$FAKE_HOME"
    unset GC_VISIT_DRAFT_DIR GC_PACK_STATE_DIR XDG_STATE_HOME
    : > "$TMUX_CALLS"
    PATH="$TMP/gumbin:$TMP/bin:$PATH" sh "$SCRIPT" "$CFG_OK" >/dev/null 2>&1 || true
    for _ in $(seq 1 100); do grep -q 'display-message .*-d ' "$TMUX_CALLS" && break; sleep 0.05; done
)
ddpath=$(sed -n "s/.*> '\([^']*\)'.*/\1/p" "$TMP/tmux-dd.log" | head -1)
case "$ddpath" in "$FAKE_HOME"/.local/state/gc/visit-drafts/draft-*)
    ok "DRAFTDIR: with no override the draft lands in XDG state, off the shared /tmp" ;;
  *) bad "DRAFTDIR: the draft landed at '${ddpath:-none}'" ;; esac

# (REAP) — a directory that never deletes anything is a new problem. Drafts
# past the retention window go; anything inside it stays.
REAPDIR="$TMP/reap"; mkdir -p "$REAPDIR"
: > "$REAPDIR/draft-old"; touch -d '30 days ago' "$REAPDIR/draft-old" 2>/dev/null || touch -t 202001010000 "$REAPDIR/draft-old"
: > "$REAPDIR/draft-recent"
: > "$REAPDIR/not-a-draft"; touch -d '30 days ago' "$REAPDIR/not-a-draft" 2>/dev/null || touch -t 202001010000 "$REAPDIR/not-a-draft"
DRAFT_DIR_OVERRIDE="$REAPDIR" run_handler "$CFG_OK" "a fresh press that reaps"
[ -e "$REAPDIR/draft-old" ] && bad "REAP: a draft past the window was not reaped" || ok "REAP: a draft past the retention window is reaped"
[ -e "$REAPDIR/draft-recent" ] && ok "REAP: a fresh draft is left alone" || bad "REAP: a fresh draft was reaped"
[ -e "$REAPDIR/not-a-draft" ] && ok "REAP: only this script's own drafts are touched" || bad "REAP: it deleted a file it does not own"

# (REAPSCOPE) — the reaper's scope is only safe because every directory
# $DRAFT_DIR can name is one this script owns. The unwritable-dir fallback used
# to land on the shared temp ROOT, which put `draft-*` from any other tool
# inside its reach — a real deletion, reproduced in review on this branch. The
# fallback is now a script-owned subdirectory, so an unrelated stale draft in
# the temp root survives a press that falls back.
SHAREDTMP="$TMP/sharedtmp"; mkdir -p "$SHAREDTMP"
: > "$SHAREDTMP/draft-unrelated"
touch -d '30 days ago' "$SHAREDTMP/draft-unrelated" 2>/dev/null || touch -t 202001010000 "$SHAREDTMP/draft-unrelated"
if [ "$(id -u)" -eq 0 ]; then
    ok "REAPSCOPE: skipped (running as root; chmod cannot make a dir unwritable)"
else
    NOWRITE="$TMP/nowrite2"; mkdir -p "$NOWRITE"; chmod 500 "$NOWRITE"
    (
        export CALLS="$TMP/calls.log" TMUX_CALLS="$TMP/tmux-rs.log" GUM_CALLS="$TMP/gum.log"
        export FAKE_TOPIC="a press that has to fall back" TMPDIR="$SHAREDTMP"
        export GC_VISIT_DRAFT_DIR="$NOWRITE"
        : > "$TMUX_CALLS"; : > "$CALLS"
        PATH="$TMP/gumbin:$TMP/bin:$PATH" sh "$SCRIPT" "$CFG_OK" >/dev/null 2>&1 || true
        for _ in $(seq 1 100); do grep -q 'display-message .*-d ' "$TMUX_CALLS" && break; sleep 0.05; done
    )
    chmod 700 "$NOWRITE"
    [ -e "$SHAREDTMP/draft-unrelated" ] \
        && ok "REAPSCOPE: an unrelated stale draft-* in the shared temp root survives the fallback" \
        || bad "REAPSCOPE: the fallback reaper deleted a file this script does not own"
    has "$(cat "$TMP/tmux-rs.log")" "gc-visit-drafts" \
        "REAPSCOPE: ...because the fallback is a script-owned subdirectory, and the message names it"
    has "$(cat "$TMP/calls.log")" "argv=[a press that has to fall back]" \
        "REAPSCOPE: ...and the press still files"
fi

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

    # (CANCELPTY) THE CONTROL THIS SUITE WAS MISSING. Everything hermetic here
    # runs against a gum STUB, and a stub can be taught to do things the real
    # primitive cannot — which is how the cancel branch shipped green and dead:
    # the stub printed text and THEN exited non-zero, and no case asked whether
    # `gum write` ever does that. It does not. Type into a real popup through a
    # real pty, press Esc, and pin BOTH halves: what gum leaves in the file, and
    # what the handler does about it.
    #
    # Part one — the primitive itself, with no handler in the way. This is the
    # fact every cancel decision rests on, so it is asserted directly rather
    # than inferred from the handler's behaviour.
    CANCEL_RAW="$TMP/cancel-raw.txt"; : > "$CANCEL_RAW"
    tmux -L "$SOCKET" kill-server >/dev/null 2>&1 || true
    tmux -L "$SOCKET" new-session -d -x 100 -y 30 'sleep 600' >/dev/null 2>&1
    tmux -L "$SOCKET" bind-key b run-shell -b \
        "tmux -L $SOCKET display-popup -E -w 80% -h 50% 'gum write --show-help --height 5 > $CANCEL_RAW'" >/dev/null 2>&1
    {   sleep 1.5
        printf '\002'; sleep 0.4; printf 'b'
        sleep 1.5
        printf 'a paragraph I typed and then abandoned'; sleep 0.5
        printf '\033'; sleep 1.2
        printf '\002d'; sleep 0.5
    } | TERM="$LIVE_TERM" script -qec "tmux -L $SOCKET attach" /dev/null >/dev/null 2>&1
    raw_bytes=$(wc -c < "$CANCEL_RAW" | tr -d ' ')

    # POSITIVE CONTROL, and the assertion above is worthless without it: an
    # empty file is also what a popup that never opened leaves behind, so
    # "0 bytes" only means "gum discarded the buffer" if the SAME binding,
    # the same pty and the same keystrokes demonstrably produce bytes on
    # submit. Run it before judging the cancel.
    SUBMIT_RAW="$TMP/submit-raw.txt"; : > "$SUBMIT_RAW"
    tmux -L "$SOCKET" kill-server >/dev/null 2>&1 || true
    tmux -L "$SOCKET" new-session -d -x 100 -y 30 'sleep 600' >/dev/null 2>&1
    tmux -L "$SOCKET" bind-key b run-shell -b \
        "tmux -L $SOCKET display-popup -E -w 80% -h 50% 'gum write --show-help --height 5 > $SUBMIT_RAW'" >/dev/null 2>&1
    {   sleep 1.5
        printf '\002'; sleep 0.4; printf 'b'
        sleep 1.5
        printf 'a paragraph I typed and then submitted'; sleep 0.5
        printf '\r'; sleep 0.5; printf '\004'; sleep 1.2
        printf '\002d'; sleep 0.5
    } | TERM="$LIVE_TERM" script -qec "tmux -L $SOCKET attach" /dev/null >/dev/null 2>&1
    has "$(cat "$SUBMIT_RAW")" "a paragraph I typed and then submitted" \
        "CANCELPTY control: the same popup, pty and keystrokes DO deliver the buffer on submit"

    eq "$raw_bytes" "0" \
       "CANCELPTY: real gum write emits NOTHING on Esc after typing — the buffer cannot be recovered"

    # Part two — the handler over that same primitive. Since the buffer is
    # unknowable, the requirement is that a cancel is not SILENT: a silent
    # cancel and a broken key are the same event from the operator's seat.
    CANCEL_DRAFTS="$TMP/live-cancel-drafts"; mkdir -p "$CANCEL_DRAFTS"
    CANCEL_CALLS="$TMP/live-cancel-calls.log"; : > "$CANCEL_CALLS"
    tmux -L "$SOCKET" kill-server >/dev/null 2>&1 || true
    tmux -L "$SOCKET" new-session -d -x 100 -y 30 'sleep 600' >/dev/null 2>&1
    tmux -L "$SOCKET" set-environment -g CALLS "$CANCEL_CALLS" >/dev/null 2>&1
    tmux -L "$SOCKET" set-environment -g GC_VISIT_DRAFT_DIR "$CANCEL_DRAFTS" >/dev/null 2>&1
    GC_TMUX_SOCKET="$SOCKET" sh "$BINDINGS" "$LIVE_CFG" >/dev/null 2>&1
    {   sleep 1.5
        printf '\002'; sleep 0.4; printf 'a'
        sleep 1.5
        printf 'another one I abandon'; sleep 0.5
        printf '\033'; sleep 1.5
        printf '\002d'; sleep 0.5
    } | TERM="$LIVE_TERM" script -qec "tmux -L $SOCKET attach" /dev/null >/dev/null 2>&1
    eq "$(cat "$CANCEL_CALLS")" "" "CANCELPTY: a real Esc files nothing"
    eq "$(find "$CANCEL_DRAFTS" -type f 2>/dev/null | wc -l | tr -d ' ')" "0" \
       "CANCELPTY: ...and leaves no draft, because gum wrote none to keep"
    cmsgs=$(tmux -L "$SOCKET" show-messages 2>/dev/null || true)
    has "$cmsgs" "cancelled" \
        "CANCELPTY: ...and the operator is told, so a cancel is not mistaken for a dead key"

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
