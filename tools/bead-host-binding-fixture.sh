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
# assignee is a top-level bead field (not metadata) — grounding writes it there.
assignee_of() { gc bd show "$1" --json 2>/dev/null | jq -r '.[0].assignee // empty'; }

WORK=""; SESS=""; SHIM_DIR=""
W2=""; DEAD=""; OLD=""; NEW=""; RECREATE_SHIM=""; BACKFILL_SHIM=""
cleanup() {
    [ -n "$SHIM_DIR" ] && rm -rf "$SHIM_DIR" || true
    [ -n "$RECREATE_SHIM" ] && rm -rf "$RECREATE_SHIM" || true
    [ -n "$BACKFILL_SHIM" ] && rm -rf "$BACKFILL_SHIM" || true
    [ "$KEEP" = "1" ] && { note "--keep: leaving WORK=$WORK SESS=$SESS W2=$W2 DEAD=$DEAD OLD=$OLD NEW=$NEW open"; return; }
    for b in "$WORK" "$SESS" "$W2" "$DEAD" "$OLD" "$NEW"; do
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
# Grounding (tk-z130v.3): link ALSO sets the work bead's `assignee` to the
# session NAME — the assigned-work wake reason that makes the reconciler revive
# the host after an involuntary drain (compute_awake_set has no Drained gate).
[ "$(assignee_of "$WORK")" = "bead-host--$WORK" ] \
    && ok "grounding: WORK.assignee == session_name (host revives across a drain)" \
    || bad "grounding missing: WORK.assignee=$(assignee_of "$WORK") (want bead-host--$WORK)"

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
# Grounding is idempotent: a re-bind (even at a new epoch) re-writes the same
# assignee=session_name, so it never thrashes the assignment.
[ "$(assignee_of "$WORK")" = "bead-host--$WORK" ] \
    && ok "grounding idempotent across re-bind (WORK.assignee still == session_name)" \
    || bad "re-bind changed grounding: WORK.assignee=$(assignee_of "$WORK")"
# Re-binding the SAME session+epoch must NOT grow the lineage (idempotent).
"$TOOL" link "$WORK" "$SESS" "" "2" >/dev/null
LEN3="$("$TOOL" lineage "$WORK" 2>/dev/null | jq 'length' 2>/dev/null || echo 0)"
[ "$LEN3" = "2" ] \
    && ok "re-bind at the same epoch is idempotent (lineage stays 2)" \
    || bad "lineage grew on idempotent re-bind = $LEN3 (want 2)"

hdr "Backfill — grounds an already-linked host that predates grounding (tk-z130v.3)"
# A host linked BEFORE grounding shipped is linked (SESS.hosts_bead set) but its
# work bead has no assignee. `backfill` enumerates the reverse link and grounds
# each hosted work bead from its session's session_name. Shim `gc session list`
# to EMPTY so backfill only touches this fixture's listable stand-in (found via
# `gc bd list --has-metadata-key hosts_bead`) and never real live hosts — the
# same hermetic discipline the resolve-contract section uses (a polecat must not
# mutate real sessions).
"$TOOL" link "$WORK" "$SESS" "" "2" >/dev/null                 # ensure linked
gc bd update "$WORK" --assignee= >/dev/null 2>&1               # simulate pre-grounding (ungrounded)
[ -z "$(assignee_of "$WORK")" ] \
    && ok "precondition: WORK linked but ungrounded (assignee empty)" \
    || bad "precondition: could not clear assignee (got '$(assignee_of "$WORK")')"
BACKFILL_SHIM="$(mktemp -d)"
REAL_GC="$(command -v gc)"
cat >"$BACKFILL_SHIM/gc" <<SHIM
#!/usr/bin/env bash
if [ "\${1:-}" = "session" ] && [ "\${2:-}" = "list" ]; then
    printf '%s\n' '{"sessions":[]}'   # hide real hosts; backfill sees only stand-ins
    exit 0
fi
exec "$REAL_GC" "\$@"
SHIM
chmod +x "$BACKFILL_SHIM/gc"
PATH="$BACKFILL_SHIM:$PATH" "$TOOL" backfill >/dev/null 2>&1 || true
rm -rf "$BACKFILL_SHIM"; BACKFILL_SHIM=""
[ "$(assignee_of "$WORK")" = "bead-host--$WORK" ] \
    && ok "backfill re-grounded WORK from the reverse link (assignee == session_name)" \
    || bad "backfill did not ground WORK: assignee='$(assignee_of "$WORK")'"

hdr "Preserve a non-host assignee — unlink/backfill must not clobber a real owner (tk-5bygy)"
# Grounding sets WORK.assignee = the host's session_name. If a REAL agent later
# takes the bead (assignee != host_session_name — the exact case the witness
# filter KEEPS; host-bead-skip.test.sh:66), neither unlink NOR backfill may strip
# that assignment: unlink clears ONLY its own grounding, backfill skips a bead a
# non-host owner already holds. Otherwise ungrounding a stale host would strand a
# live owner's work.
OTHER="someone-else-fixture-$$"                                # synthetic non-host owner (matches no real session)
"$TOOL" link "$WORK" "$SESS" "" "2" >/dev/null                # ensure grounded + linked
gc bd update "$WORK" --assignee "$OTHER" >/dev/null 2>&1       # a real agent takes the bead
[ "$(assignee_of "$WORK")" = "$OTHER" ] \
    && ok "precondition: WORK reassigned to a non-host owner ($OTHER)" \
    || bad "precondition: could not reassign WORK (got '$(assignee_of "$WORK")')"
# (a) unlink preserves the non-host assignee while still tearing down the links.
"$TOOL" unlink "$WORK" >/dev/null
[ "$(assignee_of "$WORK")" = "$OTHER" ] \
    && ok "unlink PRESERVED the non-host assignee (did not clear $OTHER)" \
    || bad "unlink clobbered a non-host assignee: assignee='$(assignee_of "$WORK")' (want $OTHER)"
[ -z "$(meta "$WORK" host_session)" ] && [ -z "$(meta "$SESS" hosts_bead)" ] \
    && ok "unlink still cleared the links (teardown intact despite the preserved assignee)" \
    || bad "unlink left a dangling link (cache=$(meta "$WORK" host_session) reverse=$(meta "$SESS" hosts_bead))"
# (b) backfill skips a host bead a non-host agent already owns.
"$TOOL" link "$WORK" "$SESS" "" "2" >/dev/null                # re-link (re-grounds to session_name)
gc bd update "$WORK" --assignee "$OTHER" >/dev/null 2>&1       # a real agent takes it again
BACKFILL_SHIM="$(mktemp -d)"
REAL_GC="$(command -v gc)"
cat >"$BACKFILL_SHIM/gc" <<SHIM
#!/usr/bin/env bash
if [ "\${1:-}" = "session" ] && [ "\${2:-}" = "list" ]; then
    printf '%s\n' '{"sessions":[]}'   # hide real hosts; backfill sees only stand-ins
    exit 0
fi
exec "$REAL_GC" "\$@"
SHIM
chmod +x "$BACKFILL_SHIM/gc"
PATH="$BACKFILL_SHIM:$PATH" "$TOOL" backfill >/dev/null 2>&1 || true
rm -rf "$BACKFILL_SHIM"; BACKFILL_SHIM=""
[ "$(assignee_of "$WORK")" = "$OTHER" ] \
    && ok "backfill SKIPPED the bead a non-host agent owns ($OTHER preserved)" \
    || bad "backfill clobbered a non-host assignee: assignee='$(assignee_of "$WORK")' (want $OTHER)"
# Restore the grounded binding for the sections below (they expect WORK linked to
# SESS at epoch 2 and grounded to its session_name).
gc bd update "$WORK" --assignee= >/dev/null 2>&1             # drop the non-host owner
"$TOOL" link "$WORK" "$SESS" "" "2" >/dev/null              # re-ground to the host

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

hdr "Unlink without the forward cache — reverse link cleared + ungrounded (codex PR#98 blocking; tk-v369i)"
# Regression guard for the SECOND codex finding on PR#98: `unlink <work>` must
# clear the source-of-truth reverse link even when the optional forward cache
# (host_session on the work bead) is absent — a partial `link`, a manually
# cleared cache, or the documented "perf cache only" case. Reproduces the
# reviewer's repro: link a pair, drop ONLY the forward cache, unlink, then assert
# the reverse hosts_bead is gone (else `resolve` keeps finding the host via the
# source of truth and `up` re-wakes a host that was meant to be unbound). No
# shim/live session needed: SESS is a listable stand-in, so unlink's reverse
# search finds it via `gc bd list --metadata-field hosts_bead=WORK` (the same
# enumerate-and-confirm covers real session beads via `gc session list`).
#
# The SAME no-forward-cache path must ALSO unground the work bead (tk-v369i):
# grounding set assignee = the host's session_name, so with the forward cache
# gone the ungrounding decision must fall back to that reverse-link session_name.
# The pre-tk-v369i bug decided ungrounding from host_session_name ALONE, so this
# path left assignee=<session_name> behind and the host revived ~20s after every
# drain. Assert both: reverse link cleared AND assignee cleared.
"$TOOL" link "$WORK" "$SESS" "" "2" >/dev/null                    # ensure bound
gc bd update "$WORK" --unset-metadata host_session \
                     --unset-metadata host_session_name \
                     --unset-metadata host_session_epoch >/dev/null 2>&1
[ -z "$(meta "$WORK" host_session)" ] && [ "$(meta "$SESS" hosts_bead)" = "$WORK" ] \
    && ok "precondition: forward cache cleared, reverse link still intact" \
    || bad "precondition not met (cache=$(meta "$WORK" host_session) reverse=$(meta "$SESS" hosts_bead))"
# Grounding is in place going in — assignee == the host's session_name — so the
# post-unlink check below proves unlink CLEARED a set wake reason (not that it was
# never grounded).
[ "$(assignee_of "$WORK")" = "bead-host--$WORK" ] \
    && ok "precondition: WORK grounded (assignee == session_name) with the forward cache gone" \
    || bad "precondition: WORK not grounded going in (assignee=$(assignee_of "$WORK"), want bead-host--$WORK)"
"$TOOL" unlink "$WORK" >/dev/null
[ -z "$(meta "$SESS" hosts_bead)" ] \
    && ok "unlink cleared SESS.hosts_bead with NO forward cache (reverse = source of truth)" \
    || bad "unlink left SESS.hosts_bead=$(meta "$SESS" hosts_bead) — reverse link not cleared"
# The grounding assignee must be cleared too (tk-v369i): with the forward cache
# gone, unlink must still derive the host's session_name from the reverse link
# (the source of truth) and unground. Leaving assignee=<session_name> keeps the
# host's assigned-work wake reason alive so it revives ~20s after every drain.
[ -z "$(assignee_of "$WORK")" ] \
    && ok "unlink ungrounded WORK with NO forward cache (assignee cleared via reverse-link session_name)" \
    || bad "unlink left WORK grounded without a forward cache: assignee=$(assignee_of "$WORK") (want cleared)"
# Restore the binding for the teardown-sanity section below.
"$TOOL" link "$WORK" "$SESS" "" "2" >/dev/null

hdr "Default verb — bare '<bead-id>' routes to 'up' (codex PR#98 non-blocking)"
# `gc bead-host <id>` (hence `gc-bead-host.sh <id>`) is advertised as shorthand
# for `up <id>`. Prove the dispatch routes a bare id to `up` instead of failing
# with "unknown command". A definitely-absent id hits up's require_bead guard,
# so no live session is spawned.
ABSENT="tk-no-such-bead-$$"
DEFOUT="$("$TOOL" "$ABSENT" 2>&1 || true)"
printf '%s' "$DEFOUT" | grep -q "unknown command" \
    && bad "bare id still treated as a command: $DEFOUT" \
    || ok "bare id routes to 'up' (no 'unknown command'; up reported: $(printf '%s' "$DEFOUT" | head -1 | cut -c1-60))"
# A genuine unknown OPTION still errors — only bare words default to 'up'.
"$TOOL" --frobnicate >/dev/null 2>&1 \
    && bad "unknown option --frobnicate did not error" \
    || ok "unknown option still rejected (only bare ids default to 'up')"

hdr "Teardown sanity — unlink clears links + ungrounds, preserves lineage"
"$TOOL" unlink "$WORK" >/dev/null
[ -z "$(meta "$WORK" host_session)" ] && [ -z "$(meta "$SESS" hosts_bead)" ] \
    && ok "unlink cleared both links" \
    || bad "unlink left a dangling link"
# Ungrounding (tk-z130v.3): unlink clears the work bead's assignee too, so the
# host loses its wake reason and a drain can actually stop it (no ~20s revive).
[ -z "$(assignee_of "$WORK")" ] \
    && ok "unlink ungrounded WORK (assignee cleared — host now stoppable)" \
    || bad "unlink left WORK grounded: assignee=$(assignee_of "$WORK")"
[ "$("$TOOL" lineage "$WORK" 2>/dev/null | jq 'length' 2>/dev/null || echo 0)" = "2" ] \
    && ok "lineage preserved through unlink (durable record)" \
    || bad "unlink dropped the lineage"

hdr "tk-8v5j0 — a dead bound host must not resolve; 'up' re-creates a fresh one"
# Two regressions behind the gc-helm 'open' failure (tk-8v5j0): a
# failed-create corpse left bound to a work bead (a) must NOT resolve as a
# resumable host — the forward-cache fallback skips dead pointers so 'up'
# recreates; and (b) when a bound host fails to wake, 'up' must unlink the stale
# binding and create a FRESH host instead of masking the failure as a phantom
# "up". No live session is spawned (a polecat must not): a PATH shim stubs
# 'gc session new/wake/list' and stand-in task beads model the sessions.
W2="$(gc bd create "FIXTURE: tk-8v5j0 recreate work stand-in" -t task --json 2>/dev/null | jq -r '.id')"
DEAD="$(gc bd create "FIXTURE: tk-8v5j0 dead (failed-create) host stand-in" -t task --json 2>/dev/null | jq -r '.id')"
OLD="$(gc bd create "FIXTURE: tk-8v5j0 stale bound host stand-in" -t task --json 2>/dev/null | jq -r '.id')"
NEW="$(gc bd create "FIXTURE: tk-8v5j0 fresh host stand-in" -t task --json 2>/dev/null | jq -r '.id')"
[ -n "$W2" ] && [ -n "$DEAD" ] && [ -n "$OLD" ] && [ -n "$NEW" ] \
    || { echo "failed to create tk-8v5j0 stand-in beads" >&2; exit 2; }
# Stand-in session beads carry the lifecycle field 'up' reads (metadata.state):
# DEAD is a failed-create corpse; OLD looks live (its WAKE is what fails); NEW is
# the freshly-created host that registers immediately.
gc bd update "$DEAD" --set-metadata session_name="s-$DEAD" --set-metadata continuation_epoch="1" --set-metadata state="failed-create" >/dev/null 2>&1
gc bd update "$OLD"  --set-metadata session_name="s-$OLD"  --set-metadata continuation_epoch="1" --set-metadata state="awake" >/dev/null 2>&1
gc bd update "$NEW"  --set-metadata session_name="s-$NEW"  --set-metadata continuation_epoch="1" --set-metadata state="awake" >/dev/null 2>&1
note "W2=$W2  DEAD=$DEAD(failed-create)  OLD=$OLD(stale-live)  NEW=$NEW(fresh)"

# (a) resolve must skip a failed-create cache pointer → reports "no host".
"$TOOL" link "$W2" "$DEAD" >/dev/null
if "$TOOL" resolve "$W2" >/dev/null 2>&1; then
    bad "resolve returned a host for a failed-create cache pointer (must be 'no host')"
else
    ok "resolve treats a failed-create cache pointer as 'no host' (so 'up' recreates)"
fi
"$TOOL" unlink "$W2" >/dev/null

# (b) a bound host whose wake fails → 'up' unlinks the stale binding, creates fresh.
"$TOOL" link "$W2" "$OLD" >/dev/null
RECREATE_SHIM="$(mktemp -d)"
REAL_GC="$(command -v gc)"
cat >"$RECREATE_SHIM/gc" <<SHIM
#!/usr/bin/env bash
if [ "\${1:-}" = "session" ] && [ "\${2:-}" = "list" ]; then
    printf '%s\n' '{"sessions":[{"id":"$OLD","session_name":"s-$OLD","alias":"$W2","state":"active","template":"agents/bead-host"}]}'
    exit 0
fi
if [ "\${1:-}" = "session" ] && [ "\${2:-}" = "wake" ]; then
    echo "gc session wake: session not found" >&2   # the dead host can't wake
    exit 1
fi
if [ "\${1:-}" = "session" ] && [ "\${2:-}" = "new" ]; then
    printf '%s\n' '{"session_id":"$NEW","session_name":"s-$NEW"}'   # create, no real spawn
    exit 0
fi
exec "$REAL_GC" "\$@"
SHIM
chmod +x "$RECREATE_SHIM/gc"

PATH="$RECREATE_SHIM:$PATH" "$TOOL" up "$W2" >/dev/null 2>&1 || true
rm -rf "$RECREATE_SHIM"; RECREATE_SHIM=""
[ "$(meta "$W2" host_session)" = "$NEW" ] \
    && ok "up re-created: W2.host_session now points at the FRESH host ($NEW)" \
    || bad "up did not re-create: W2.host_session=$(meta "$W2" host_session) (want $NEW)"
[ "$(meta "$W2" host_session_name)" = "s-$NEW" ] \
    && ok "forward cache carries the fresh session_name (s-$NEW)" \
    || bad "host_session_name=$(meta "$W2" host_session_name) (want s-$NEW)"
[ "$(meta "$NEW" hosts_bead)" = "$W2" ] \
    && ok "fresh host's reverse link points back at W2" \
    || bad "NEW.hosts_bead=$(meta "$NEW" hosts_bead) (want $W2)"
[ -z "$(meta "$OLD" hosts_bead)" ] \
    && ok "stale host was unlinked (OLD.hosts_bead cleared, no phantom resume)" \
    || bad "stale binding survived: OLD.hosts_bead=$(meta "$OLD" hosts_bead) (want empty)"
"$TOOL" unlink "$W2" >/dev/null 2>&1 || true

hdr "Operator-deferred (NOT run here — need a live LLM session)"
note "Assertion 2: a resumed host RECALLS a distinctive marker across suspend/wake."
note "Assertion 5 (conversational half): the resumed host re-reads the mid-suspend change."
note "Assertion 3 (fidelity half): resume-carries vs logged-degraded fresh re-prime."
note "Run specs/tk-husu6/binding-report.md §'Operator confirmatory checklist'."

hdr "Result"
printf 'automated assertions: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
