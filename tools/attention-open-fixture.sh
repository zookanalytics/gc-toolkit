#!/usr/bin/env bash
# attention-open-fixture.sh — hermetic regression for gc-attention.sh `open`'s
# tmux switch target (tk-8v5j0). From inside tmux, `open` must switch the client
# to the host's session_name (`s-<session-id>`) — NOT the bead id and NOT the
# (rig-prefixed) alias. Passing the bead id, as it did before this fix, can
# never match `tmux has-session`, so every in-tmux open timed out at the switch
# helper's poll budget and the operator never landed.
#
# No live session is spawned and no tmux client is touched (a polecat must not):
#   - GC_BEAD_HOST_TOOL points at a stub `up` that no-ops (the forward cache is
#     pre-seeded by the test), so `open` does not spawn a host.
#   - GC_TMUX_SWITCH_TOOL points at a recorder that captures its argument
#     instead of switching a client.
# Toggling host_session_name on the work bead drives the two cases:
#   (1) cache present  -> open switches to session_name (s-<id>)
#   (2) cache absent   -> open falls back to the bead id (best-effort, non-fatal)
#
# Exit 0 iff both assertions pass.  Usage: attention-open-fixture.sh [--keep]
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ATTENTION="$HERE/../assets/scripts/gc-attention.sh"
KEEP=0
[ "${1:-}" = "--keep" ] && KEEP=1

PASS=0; FAIL=0
ok()   { printf '  \033[32mPASS\033[0m %s\n' "$*"; PASS=$((PASS+1)); }
bad()  { printf '  \033[31mFAIL\033[0m %s\n' "$*"; FAIL=$((FAIL+1)); }
note() { printf '  ---- %s\n' "$*"; }
hdr()  { printf '\n== %s ==\n' "$*"; }

[ -x "$ATTENTION" ] || { echo "gc-attention.sh not found/executable: $ATTENTION" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 2; }

WORK=""; SHIM_DIR=""
cleanup() {
    [ -n "$SHIM_DIR" ] && rm -rf "$SHIM_DIR" || true
    [ "$KEEP" = "1" ] && { note "--keep: leaving WORK=$WORK open"; return; }
    [ -n "$WORK" ] && gc bd close "$WORK" --reason "attention-open fixture teardown" >/dev/null 2>&1 || true
}
trap cleanup EXIT

hdr "Setup: stand-in work bead + stub up / recorder switch tool"
WORK="$(gc bd create "FIXTURE: tk-8v5j0 attention-open work stand-in" -t task --json 2>/dev/null | jq -r '.id')"
[ -n "$WORK" ] || { echo "failed to create stand-in bead" >&2; exit 2; }
note "WORK = $WORK"

SHIM_DIR="$(mktemp -d)"
REC="$SHIM_DIR/switch-target.txt"
# Stub bead-host tool: `open` calls `<tool> up <bead>`; the forward cache is
# pre-seeded by the test, so the stub only needs to succeed without spawning.
cat >"$SHIM_DIR/bead-host-stub.sh" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
chmod +x "$SHIM_DIR/bead-host-stub.sh"
# Recorder switch tool: capture the target it was handed instead of switching a
# real tmux client. Writes to a fixed path so the test can read it back.
cat >"$SHIM_DIR/switch-recorder.sh" <<STUB
#!/usr/bin/env bash
printf '%s' "\${1:-}" > "$REC"
exit 0
STUB
chmod +x "$SHIM_DIR/switch-recorder.sh"

# Run `open` with TMUX set (so it takes the in-tmux switch path) and the stubs
# wired in; echo whatever target the recorder captured.
run_open() {
    : > "$REC"
    TMUX=fake-tmux \
    GC_BEAD_HOST_TOOL="$SHIM_DIR/bead-host-stub.sh" \
    GC_TMUX_SWITCH_TOOL="$SHIM_DIR/switch-recorder.sh" \
        "$ATTENTION" open "$WORK" >/dev/null 2>&1 || true
    cat "$REC" 2>/dev/null || true
}

hdr "Assertion 1 — open switches to host_session_name (s-<id>), not the bead id"
gc bd update "$WORK" --set-metadata host_session_name="s-$WORK" >/dev/null 2>&1
GOT="$(run_open)"
[ "$GOT" = "s-$WORK" ] \
    && ok "open targeted the session_name s-$WORK (not the bead id $WORK)" \
    || bad "open targeted '$GOT' (want s-$WORK — the bead id would time out has-session)"

hdr "Assertion 2 — fallback to the bead id when the cache is unresolved"
gc bd update "$WORK" --unset-metadata host_session_name >/dev/null 2>&1
GOT="$(run_open)"
[ "$GOT" = "$WORK" ] \
    && ok "open fell back to the bead id $WORK when host_session_name is unset" \
    || bad "open targeted '$GOT' (want $WORK)"

hdr "Result"
printf 'attention-open assertions: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
