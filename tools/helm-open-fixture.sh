#!/usr/bin/env bash
# helm-open-fixture.sh — hermetic regression for gc-helm.sh `open`'s
# tmux landing logic (tk-8v5j0).
#
# `open` must switch the tmux client to the host's session_name (`s-<id>`) ONLY
# when that session lives on the tmux server we're attached to right now — i.e.
# the board picker's `run-shell`, where $TMUX is the GC city server. From a
# SEPARATE-window tmux (a different server) the host session isn't there and a
# switch can never land: `open` must NOT switch (switching would hijack an
# unrelated client) and must NOT poll (the old 45s budget turned that into a
# hang). It brings the host up, prints a land-it hint, and returns promptly.
#
# Because `up` now blocks until the host registers (gc-bead-host.sh), `cmd_open`
# discriminates with an IMMEDIATE `tmux has-session` probe on the current server
# and talks to tmux directly (no switch helper). So this fixture shims `tmux`:
#   - has-session -t <t>   : exit 0 iff FIXTURE_HAS_SESSION=1 AND <t> matches the
#                            expected session_name — models "is the host on THIS
#                            tmux server?" (true = same server, false = separate)
#   - switch-client -t <t> : records <t> instead of touching a real client
# and stubs the bead-host `up` (GC_BEAD_HOST_TOOL) to a no-op so no live session
# is spawned and no real tmux client is touched (a polecat must not).
#
# Cases (revision acceptance #4):
#   (a) same server     -> switch-client lands on session_name (s-<id>)
#   (b) different server -> no switch-client, hint printed, returns fast (no hang)
#
# Exit 0 iff both assertions pass.  Usage: helm-open-fixture.sh [--keep]
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ATTENTION="$HERE/../assets/scripts/gc-helm.sh"
KEEP=0
[ "${1:-}" = "--keep" ] && KEEP=1

PASS=0; FAIL=0
ok()   { printf '  \033[32mPASS\033[0m %s\n' "$*"; PASS=$((PASS+1)); }
bad()  { printf '  \033[31mFAIL\033[0m %s\n' "$*"; FAIL=$((FAIL+1)); }
note() { printf '  ---- %s\n' "$*"; }
hdr()  { printf '\n== %s ==\n' "$*"; }

[ -x "$ATTENTION" ] || { echo "gc-helm.sh not found/executable: $ATTENTION" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 2; }

WORK=""; SHIM_DIR=""
cleanup() {
    [ -n "$SHIM_DIR" ] && rm -rf "$SHIM_DIR" || true
    [ "$KEEP" = "1" ] && { note "--keep: leaving WORK=$WORK open"; return; }
    [ -n "$WORK" ] && gc bd close "$WORK" --reason "helm-open fixture teardown" >/dev/null 2>&1 || true
}
trap cleanup EXIT

hdr "Setup: stand-in work bead + stub up / fake tmux"
WORK="$(gc bd create "FIXTURE: tk-8v5j0 helm-open work stand-in" -t task --json 2>/dev/null | jq -r '.id')"
[ -n "$WORK" ] || { echo "failed to create stand-in bead" >&2; exit 2; }
note "WORK = $WORK"

SHIM_DIR="$(mktemp -d)"
SWITCH_REC="$SHIM_DIR/switch-target.txt"
ERR_LOG="$SHIM_DIR/open.err"

# Stub bead-host tool: `open` calls `<tool> up <bead>`; the forward cache is
# pre-seeded by the test (host_session_name on the work bead), so the stub only
# needs to succeed without spawning a host.
cat >"$SHIM_DIR/bead-host-stub.sh" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
chmod +x "$SHIM_DIR/bead-host-stub.sh"

# Fake tmux: cmd_open now talks to tmux directly (no switch helper). Reads its
# behavior from the env the test exports (quoted heredoc -> nothing expanded at
# write time; all `$` are resolved when the fake runs):
#   FIXTURE_HAS_SESSION=1 + target == FIXTURE_EXPECT_SESSION -> has-session ok
#   switch-client target -> recorded to $SWITCH_REC
cat >"$SHIM_DIR/tmux" <<'STUB'
#!/usr/bin/env bash
sub="${1:-}"; shift 2>/dev/null || true
target=""
while [ $# -gt 0 ]; do
    case "$1" in
        -t) target="${2:-}"; shift 2 2>/dev/null || shift ;;
        *)  shift ;;
    esac
done
case "$sub" in
    has-session)
        if [ "${FIXTURE_HAS_SESSION:-0}" = "1" ] && [ "$target" = "${FIXTURE_EXPECT_SESSION:-}" ]; then
            exit 0
        fi
        exit 1
        ;;
    switch-client)
        printf '%s' "$target" > "${SWITCH_REC:?SWITCH_REC unset}"
        exit 0
        ;;
    *) exit 0 ;;
esac
STUB
chmod +x "$SHIM_DIR/tmux"

# Run `open` with $TMUX set (in-tmux path) and the shims wired in. $1 = the
# has-session mode (1 = host session present on THIS server, 0 = not here).
# Wrapped in `timeout` so a reintroduced poll surfaces as a hang (rc 124), not
# a silently-slow pass. Captures stderr for the hint assertion.
RC=0
run_open() {
    : > "$SWITCH_REC"; : > "$ERR_LOG"
    RC=0
    FIXTURE_HAS_SESSION="$1" \
    FIXTURE_EXPECT_SESSION="s-$WORK" \
    SWITCH_REC="$SWITCH_REC" \
    TMUX="fake-tmux,1,0" \
    GC_BEAD_HOST_TOOL="$SHIM_DIR/bead-host-stub.sh" \
    PATH="$SHIM_DIR:$PATH" \
        timeout 10 "$ATTENTION" open "$WORK" >/dev/null 2>"$ERR_LOG" || RC=$?
}

# Pre-seed the forward cache: a healthy resolved host_session_name. Both cases
# share it — the only thing that differs is whether that session is on the
# current tmux server (same-server vs separate-window).
gc bd update "$WORK" --set-metadata host_session_name="s-$WORK" >/dev/null 2>&1

hdr "Assertion 1 — same server (has-session true): switch-client lands on session_name"
run_open 1
GOT="$(cat "$SWITCH_REC" 2>/dev/null || true)"
{ [ "$GOT" = "s-$WORK" ] && [ "$RC" -ne 124 ]; } \
    && ok "switch-client targeted session_name s-$WORK on the current server (rc=$RC)" \
    || bad "want switch to s-$WORK with no hang (got switch='$GOT', rc=$RC)"

hdr "Assertion 2 — different server (has-session false): no switch, hint, returns fast"
run_open 0
GOT="$(cat "$SWITCH_REC" 2>/dev/null || true)"
{ [ -z "$GOT" ] && [ "$RC" -ne 124 ] && grep -q 'Land it' "$ERR_LOG"; } \
    && ok "no switch-client on a separate-window server; hint printed; open returned promptly (rc=$RC)" \
    || { bad "want NO switch + land-it hint + prompt return (got switch='$GOT', rc=$RC)"; note "stderr:"; sed 's/^/    /' "$ERR_LOG" >&2 || true; }

hdr "Result"
printf 'helm-open assertions: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
