#!/usr/bin/env bash
# bead-host-binding-fixture.sh — automatable assertions for the durable
# bead<->session binding (tk-husu6, Phase 1). Exercises the metadata
# contract end-to-end against the live rig ledger using THROWAWAY plain
# `task` beads as stand-ins — no live sessions are spawned, so a polecat
# can run it (the tk-oml75 / tk-k9s0k precedent: a polecat must not
# spawn/reset live-city sessions). Self-cleaning: the stand-in beads are
# closed on exit.
#
# It covers the parts of the 5-assertion binding gate that do NOT need a
# live LLM. The live halves — does a resumed host RECALL a marker
# (assertion 2), and does it re-read a mid-suspend change (assertion 5's
# conversational half) — are operator-deferred; see
# specs/tk-husu6/binding-report.md §"Operator confirmatory checklist".
#
#   Assertion 1  create + dual-link resolves both ways ............ AUTOMATED
#   Assertion 2  resume carries a marker across suspend/wake ...... OPERATOR
#   Assertion 3  links persist across drain/respawn .............. AUTOMATED (link half)
#   Assertion 4  reverse-resolvable (search finds the host) ...... AUTOMATED
#   Assertion 5  resume reflects a mid-suspend change ............ AUTOMATED (data half)
#   + lineage append is carried from day one .................... AUTOMATED
#   + resolve requires hosts_bead (alias is a prefilter only) ... AUTOMATED
#
# Exit 0 iff every automated assertion passes.
#
# Usage: bead-host-binding-fixture.sh [--keep]
#   --keep   leave the stand-in beads open (for debugging)

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL="$HERE/gc-bead-host.sh"
KEEP=0
[ "${1:-}" = "--keep" ] && KEEP=1

PASS=0; FAIL=0
ok()   { printf '  \033[32mPASS\033[0m %s\n' "$*"; PASS=$((PASS+1)); }
bad()  { printf '  \033[31mFAIL\033[0m %s\n' "$*"; FAIL=$((FAIL+1)); }
note() { printf '  ---- %s\n' "$*"; }
hdr()  { printf '\n== %s ==\n' "$*"; }

meta() { gc bd show "$1" --json 2>/dev/null | jq -r --arg k "$2" '.[0].metadata[$k] // empty'; }

WORK=""; SESS=""; SHIM_DIR=""
cleanup() {
    [ -n "$SHIM_DIR" ] && rm -rf "$SHIM_DIR" || true
    [ "$KEEP" = "1" ] && { note "--keep: leaving WORK=$WORK SESS=$SESS open"; return; }
    for b in "$WORK" "$SESS"; do
        [ -n "$b" ] && gc bd close "$b" --reason "binding fixture teardown" >/dev/null 2>&1 || true
    done
}
trap cleanup EXIT

[ -x "$TOOL" ] || { echo "tool not found/executable: $TOOL" >&2; exit 2; }

hdr "Setup: create throwaway stand-in beads (rig ledger, plain task type)"
WORK="$(gc bd create "FIXTURE: bead-host binding work stand-in" -t task --json 2>/dev/null | jq -r '.id')"
SESS="$(gc bd create "FIXTURE: bead-host binding session stand-in" -t task --json 2>/dev/null | jq -r '.id')"
[ -n "$WORK" ] && [ -n "$SESS" ] || { echo "failed to create stand-in beads" >&2; exit 2; }
# Make SESS look like a session bead (the fields the binding keys on).
gc bd update "$SESS" --set-metadata session_name="bead-host--$WORK" \
                     --set-metadata continuation_epoch="1" \
                     --set-metadata generation="1" >/dev/null 2>&1
note "WORK (work bead)    = $WORK"
note "SESS (session bead) = $SESS  session_name=bead-host--$WORK epoch=1"

hdr "Assertion 1 — create + dual-link resolves both ways"
"$TOOL" link "$WORK" "$SESS" >/dev/null
[ "$(meta "$SESS" hosts_bead)" = "$WORK" ] \
    && ok "reverse link: SESS.hosts_bead == WORK (source of truth on the session bead)" \
    || bad "reverse link missing/wrong: SESS.hosts_bead=$(meta "$SESS" hosts_bead)"
[ "$(meta "$WORK" host_session)" = "$SESS" ] \
    && ok "forward cache: WORK.host_session == SESS" \
    || bad "forward cache missing/wrong: WORK.host_session=$(meta "$WORK" host_session)"
[ "$(meta "$WORK" host_session_name)" = "bead-host--$WORK" ] \
    && ok "forward cache carries session_name" \
    || bad "host_session_name=$(meta "$WORK" host_session_name)"
[ "$(meta "$WORK" host_session_epoch)" = "1" ] \
    && ok "forward cache carries continuation_epoch (the incarnation marker)" \
    || bad "host_session_epoch=$(meta "$WORK" host_session_epoch)"

hdr "Assertion 4 — reverse-resolvable: the search finds the bead's host(s)"
# (a) The design's intended mechanism, ListByMetadata hosts_bead=<bead>,
#     shown on a LISTABLE stand-in (real session beads aren't bd-listable;
#     see the report — the tool's resolve uses gc session list instead).
HITS="$(gc bd list --metadata-field "hosts_bead=$WORK" --json 2>/dev/null | jq -r '[.[].id] | @csv' 2>/dev/null)"
printf '%s' "$HITS" | grep -q "$SESS" \
    && ok "ListByMetadata hosts_bead=$WORK finds the host ($HITS)" \
    || bad "ListByMetadata hosts_bead search did not find SESS (got: $HITS)"
# (b) The tool's resolve (forward-cache + session-list path) finds it too.
"$TOOL" resolve "$WORK" 2>/dev/null | grep -q "$SESS" \
    && ok "gc-bead-host.sh resolve $WORK returns the host" \
    || bad "resolve did not return the host"

hdr "Assertion 5 — resume reflects a mid-suspend change (data half)"
MARKER="MIDSUSPEND-$$-$RANDOM"
gc bd update "$WORK" --notes "$MARKER" >/dev/null 2>&1
# The fed slice is recomputed from the live bead on resume — a fresh read
# reflects the change made while 'suspended', not a stale snapshot.
gc bd show "$WORK" --json 2>/dev/null | jq -r '.[0].notes // ""' | grep -q "$MARKER" \
    && ok "freshly-read fed slice reflects the mid-suspend note ($MARKER)" \
    || bad "fed slice did not reflect the mid-suspend change"

hdr "Assertion 3 — links persist across drain/respawn (link half)"
# A drain/respawn bumps the session's generation; resume mode preserves the
# continuation_epoch. The bead<->session links are metadata and survive
# regardless — assert they still resolve after a simulated respawn.
gc bd update "$SESS" --set-metadata generation="2" >/dev/null 2>&1   # respawn: generation++
[ "$(meta "$SESS" hosts_bead)" = "$WORK" ] && [ "$(meta "$WORK" host_session)" = "$SESS" ] \
    && ok "links intact after respawn (generation 1->2, epoch preserved)" \
    || bad "links did not survive the simulated respawn"
"$TOOL" resolve "$WORK" 2>/dev/null | grep -q "$SESS" \
    && ok "still reverse-resolvable after respawn" \
    || bad "not reverse-resolvable after respawn"

hdr "Lineage — carried from day one; appends on re-bind at a new epoch"
LEN1="$("$TOOL" lineage "$WORK" 2>/dev/null | jq 'length' 2>/dev/null || echo 0)"
[ "$LEN1" = "1" ] \
    && ok "lineage has 1 entry after first bind" \
    || bad "lineage length after first bind = $LEN1 (want 1)"
# Re-bind at a new continuation_epoch (a conversation-lineage reset).
gc bd update "$SESS" --set-metadata continuation_epoch="2" >/dev/null 2>&1
"$TOOL" link "$WORK" "$SESS" "" "2" >/dev/null
LEN2="$("$TOOL" lineage "$WORK" 2>/dev/null | jq 'length' 2>/dev/null || echo 0)"
[ "$LEN2" = "2" ] \
    && ok "lineage appends a 2nd entry on re-bind at epoch 2 (0..N hook)" \
    || bad "lineage length after re-bind = $LEN2 (want 2)"
[ "$(meta "$WORK" host_session_epoch)" = "2" ] \
    && ok "forward cache epoch updated to the new incarnation (2)" \
    || bad "host_session_epoch=$(meta "$WORK" host_session_epoch) (want 2)"
# Re-binding the SAME session+epoch must NOT grow the lineage (idempotent).
"$TOOL" link "$WORK" "$SESS" "" "2" >/dev/null
LEN3="$("$TOOL" lineage "$WORK" 2>/dev/null | jq 'length' 2>/dev/null || echo 0)"
[ "$LEN3" = "2" ] \
    && ok "re-bind at the same epoch is idempotent (lineage stays 2)" \
    || bad "lineage grew on idempotent re-bind = $LEN3 (want 2)"

hdr "Resolve contract — session-list path requires hosts_bead; alias is a prefilter (codex PR#98 / tk-mv7qu)"
# Regression guard for the codex finding on PR#98: in the `gc session list`
# search path, alias==<bead> is a PREFILTER ONLY — resolution requires the
# source-of-truth reverse link hosts_bead==<bead>, confirmed by id. Without
# it, `unlink` can't unbind a still-live host (resolve keeps returning it by
# alias and `up` re-wakes it), and a foreign session sharing the alias is
# mis-reported as the host.
#
# No live session is spawned (a polecat must not). A PATH shim stubs
# `gc session list` to present SESS as a live bead-host aliased to WORK and
# delegates every other `gc` call to the real binary; toggling SESS.hosts_bead
# drives the two cases. WORK is linked to SESS at epoch 2 coming in.
SHIM_DIR="$(mktemp -d)"
REAL_GC="$(command -v gc)"
cat >"$SHIM_DIR/gc" <<SHIM
#!/usr/bin/env bash
if [ "\${1:-}" = "session" ] && [ "\${2:-}" = "list" ]; then
    printf '%s\n' '{"sessions":[{"id":"$SESS","session_name":"bead-host--$WORK","alias":"$WORK","state":"running","template":"agents/bead-host"}]}'
    exit 0
fi
exec "$REAL_GC" "\$@"
SHIM
chmod +x "$SHIM_DIR/gc"

# (a) Positive: SESS still carries hosts_bead==WORK → the stubbed session-list
#     row resolves via the reverse-link confirmation (proves the prefilter
#     still admits a genuine host — the fix is not an over-correction).
PATH="$SHIM_DIR:$PATH" "$TOOL" resolve "$WORK" 2>/dev/null | grep -q "$SESS" \
    && ok "session-list row WITH hosts_bead==WORK resolves (reverse link confirmed by id)" \
    || bad "resolve missed a genuine host on the session-list path"

# (b) Negative: clear the reverse link (the post-unlink / foreign-alias case).
#     The SAME live alias-matching row must now NOT resolve.
"$TOOL" unlink "$WORK" >/dev/null
[ -z "$(meta "$SESS" hosts_bead)" ] \
    || bad "precondition: SESS.hosts_bead should be clear after unlink (got '$(meta "$SESS" hosts_bead)')"
if PATH="$SHIM_DIR:$PATH" "$TOOL" resolve "$WORK" >/dev/null 2>&1; then
    bad "alias-only live session resolved as host (alias wrongly treated as proof of hosting)"
else
    ok "alias-only live session does NOT resolve once hosts_bead is cleared (alias is a prefilter)"
fi

# Restore the binding so the teardown-sanity checks below see a bound pair.
"$TOOL" link "$WORK" "$SESS" "" "2" >/dev/null
rm -rf "$SHIM_DIR"; SHIM_DIR=""

hdr "Teardown sanity — unlink clears links, preserves lineage"
"$TOOL" unlink "$WORK" >/dev/null
[ -z "$(meta "$WORK" host_session)" ] && [ -z "$(meta "$SESS" hosts_bead)" ] \
    && ok "unlink cleared both links" \
    || bad "unlink left a dangling link"
[ "$("$TOOL" lineage "$WORK" 2>/dev/null | jq 'length' 2>/dev/null || echo 0)" = "2" ] \
    && ok "lineage preserved through unlink (durable record)" \
    || bad "unlink dropped the lineage"

hdr "Operator-deferred (NOT run here — need a live LLM session)"
note "Assertion 2: a resumed host RECALLS a distinctive marker across suspend/wake."
note "Assertion 5 (conversational half): the resumed host re-reads the mid-suspend change."
note "Assertion 3 (fidelity half): resume-carries vs logged-degraded fresh re-prime."
note "Run specs/tk-husu6/binding-report.md §'Operator confirmatory checklist'."

hdr "Result"
printf 'automated assertions: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
