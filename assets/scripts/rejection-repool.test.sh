#!/usr/bin/env bash
# Hermetic test for assets/scripts/rejection-repool.sh — the refinery's
# rejection, handed back to the polecat pool as a mol-polecat-work pour.
# Covers: the usage refusals; the release (one lifecycle transition that clears
# the assignee, the claim route and the last pour's execution stamp, and records
# rejection_reason and existing_pr) landing before the pour; the pour proved by
# its own stamp and never by the one the last pour left; an unproved pour armed
# for a retry and never routed bare; and a visit on every other way the repool
# stops short. The real lifecycle.sh (through a gctk built from this tree),
# pool-route.sh and deferred-dispatch.sh run against the harness store, and
# escalate.sh is a stub that records its argv.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-rejection-repool-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"
# The release is a lifecycle transition, and lifecycle.sh execs gctk.
harness_build_gctk
harness_init

ESC_STUB='#!/usr/bin/env bash
printf "%s\n" "$*" >> "${STUB_ESC_LOG:?}"
exit "${STUB_ESC_RC:-0}"'
SD="$TMP/scripts"
mk_sut_dir "$SD" "$HERE/rejection-repool.sh" "$HERE/lifecycle.sh" "$HERE/pool-route.sh" \
  "$HERE/deferred-dispatch.sh"
printf '%s\n' "$ESC_STUB" > "$SD/escalate.sh"; chmod +x "$SD/escalate.sh"
# The same SUT beside a deferred-dispatch.sh whose arm does not land.
SD_NOARM="$TMP/scripts-noarm"
mk_sut_dir "$SD_NOARM" "$HERE/rejection-repool.sh" "$HERE/lifecycle.sh" "$HERE/pool-route.sh"
printf '%s\n' "$ESC_STUB" > "$SD_NOARM/escalate.sh"; chmod +x "$SD_NOARM/escalate.sh"
printf '#!/usr/bin/env bash\necho "deferred-dispatch: arm refused (stub)" >&2\nexit 1\n' > "$SD_NOARM/deferred-dispatch.sh"
chmod +x "$SD_NOARM/deferred-dispatch.sh"
# A gc whose sling exits 0 and stamps nothing, the shape of a pour whose own
# execution stamp did not land. Every other call reaches the harness stub.
NOSTAMP="$TMP/bin-nostamp"; mkdir -p "$NOSTAMP"
printf '#!/usr/bin/env bash\n[ "${1:-}" = sling ] && { printf "%%s\\n" "$*" >> "${STUB_GC_LOG:?}"; exit 0; }\nexec "%s/gc" "$@"\n' "$BIN" > "$NOSTAMP/gc"
chmod +x "$NOSTAMP/gc"

export STUB_ESC_LOG="$TMP/esc.log"
export GC_RIG="gc-toolkit"
ROUTE="gc-toolkit/gc-toolkit.polecat"
REASON="Conflicts with main at abc123; resume in prepare_mode=merge"

# The bead as the rejection arms leave it for this script: reopen-source has
# reopened it with no assignee, and it still carries the stamp of the pour that
# built it.
work() { # [extra-metadata-fields]
  printf '{"id":"tk-w","status":"open","assignee":"","notes":"","title":"w","metadata":{"branch":"polecat/tk-w","target":"main","gc.routed_to":"","gc.execution_routed_to":"%s"%s}}' \
    "$ROUTE" "${1:-}"
}
reset() { # [extra-metadata-fields]
  store "[$(work "${1:-}")]"
  : > "$STUB_GC_LOG"; : > "$STUB_ESC_LOG"
  export STUB_SLING_FAIL="" STUB_UPDATE_FAIL="" STUB_SHOW_FAIL="" STUB_AGENTS="" STUB_ESC_RC=""
}
run()  { out=$("$SD/rejection-repool.sh" "$@" 2>&1); rc=$?; }
run_noarm() { out=$("$SD_NOARM/rejection-repool.sh" "$@" 2>&1); rc=$?; }
slings() { grep -c '^sling ' "$STUB_GC_LOG" || true; }
visits() { wc -l < "$STUB_ESC_LOG" | tr -d ' '; }
no_bare_route() { # <label>
  case "$(meta tk-w gc.routed_to)" in
    ""|"<absent>") ok "$1" ;;
    *) bad "$1 (gc.routed_to='$(meta tk-w gc.routed_to)')" ;;
  esac
}

echo "# usage refusals do nothing"
reset
run --reason "$REASON";        eq "$rc" 1 "no work bead -> exit 1"
run tk-w;                      eq "$rc" 1 "no --reason -> exit 1"
run tk-w --reason "$REASON" --bogus; eq "$rc" 1 "an unknown flag -> exit 1"
run tk-w tk-x --reason "$REASON"; eq "$rc" 1 "two work beads -> exit 1"
eq "$(wc -l < "$STUB_GC_LOG" | tr -d ' ')" "0" "a usage refusal runs no gc"

echo "# the rejection is released, then poured"
reset
run tk-w --reason "$REASON"
eq "$rc" 0 "a proved pour exits 0"
eq "$(meta tk-w rejection_reason)" "$REASON" "rejection_reason recorded"
eq "$(meta tk-w merge_result)" "<absent>" "merge_result absent: unanchored"
eq "$(bassignee tk-w)" "" "no assignee"
eq "$(meta tk-w gc.execution_routed_to)" "$ROUTE" "the pour stamped the pool it dispatched to"
no_bare_route "no claim route on the bead: the pour is the only dispatch"
eq "$(slings)" "1" "one pour"
has "$(cat "$STUB_GC_LOG")" "sling --rig gc-toolkit $ROUTE tk-w --on mol-polecat-work" "poured mol-polecat-work for the proved route"
release=$(grep '^bd update tk-w' "$STUB_GC_LOG" | head -n 1)
has "$release" "--unset-metadata merge_result" "the release unanchors the bead"
has "$release" "--unset-metadata gc.execution_routed_to" "the release clears the last pour's stamp"
has "$release" "gc.routed_to=" "the release clears the claim route"
has "$release" "--assignee=" "the release clears the assignee"
first_update=$(grep -n '^bd update tk-w' "$STUB_GC_LOG" | head -n 1 | cut -d: -f1)
first_sling=$(grep -n '^sling ' "$STUB_GC_LOG" | head -n 1 | cut -d: -f1)
if [ -n "$first_update" ] && [ -n "$first_sling" ] && [ "$first_update" -lt "$first_sling" ]; then
  ok "the release lands before the pour"
else
  bad "the release lands before the pour (update line '$first_update', sling line '$first_sling')"
fi
eq "$(meta tk-w gc.dispatch_when_ready)" "<absent>" "a proved pour arms nothing"
eq "$(visits)" "0" "a proved pour files no visit"

echo "# a live PR goes with the rework"
reset ',"pr_url":"https://github.com/o/r/pull/7"'
run tk-w --reason "$REASON"
eq "$rc" 0 "a bead with a PR pours"
eq "$(meta tk-w existing_pr)" "https://github.com/o/r/pull/7" "pr_url carried over as existing_pr"

echo "# the stamp the last pour left proves nothing"
# The bead starts with gc.execution_routed_to naming this very pool. A pour that
# exits 0 without stamping it must not read back as proved off that stale value.
reset
out=$(PATH="$NOSTAMP:$PATH" "$SD/rejection-repool.sh" tk-w --reason "$REASON" 2>&1); rc=$?
eq "$rc" 2 "a pour that leaves no stamp of its own exits 2"
eq "$(meta tk-w gc.execution_routed_to)" "<absent>" "the stale stamp was cleared before the pour"
eq "$(meta tk-w gc.dispatch_when_ready)" "$ROUTE" "the re-dispatch is armed to the proved route"
eq "$(meta tk-w gc.dispatch_when_ready_args)" '["--on","mol-polecat-work"]' "the arm replays the pour"
no_bare_route "an unproved pour is never routed bare"
eq "$(visits)" "0" "an armed retry files no visit"

echo "# a failed sling is armed for a retry"
reset
export STUB_SLING_FAIL=1
run tk-w --reason "$REASON"
eq "$rc" 2 "a failed sling exits 2"
eq "$(meta tk-w rejection_reason)" "$REASON" "the release stands"
eq "$(meta tk-w gc.dispatch_when_ready)" "$ROUTE" "the retry is armed to the proved route"
eq "$(meta tk-w gc.dispatch_when_ready_args)" '["--on","mol-polecat-work"]' "the arm replays the pour"
no_bare_route "a failed sling is never routed bare"
has "$out" "armed a deferred dispatch" "the run says the arm carries it"
eq "$(visits)" "0" "an armed retry files no visit"

echo "# an arm that does not land files the visit"
reset
export STUB_SLING_FAIL=1
run_noarm tk-w --reason "$REASON"
eq "$rc" 2 "a visit carries the bead: exit 2"
eq "$(visits)" "1" "one visit"
esc=$(cat "$STUB_ESC_LOG")
has "$esc" "--subject tk-w --key rejection-repool-failed" "filed on the bead under its situation key"
has "$esc" "gc sling $ROUTE tk-w --on mol-polecat-work" "the visit names the pour that finishes it"
has "$esc" "rejection reason: $REASON)" "the visit carries the reason"
has "$esc" "--message A rejected handoff may never be rebuilt:" "the visit leads with the stake"
no_bare_route "no bare route behind the visit either"

echo "# nothing recorded: exit 3"
reset
export STUB_SLING_FAIL=1 STUB_ESC_RC=1
run_noarm tk-w --reason "$REASON"
eq "$rc" 3 "no arm and no visit -> exit 3"
has "$out" "NOTHING dispatches tk-w" "the run says nothing carries the bead"

echo "# the pool route is proved before any pour"
reset
printf '%s\n' '{"agents":[{"qualified_name":"gc-toolkit/gc-toolkit.refinery"}]}' > "$TMP/agents.json"
export STUB_AGENTS="$TMP/agents.json"
run tk-w --reason "$REASON"
eq "$rc" 2 "an unclaimed pool -> visit, exit 2"
eq "$(slings)" "0" "nothing is poured to a pool nobody claims"
eq "$(meta tk-w rejection_reason)" "$REASON" "the reason is recorded for whoever finishes it"
has "$(cat "$STUB_ESC_LOG")" "no live pool claims 'gc-toolkit.polecat'" "the visit names the missing pool"
eq "$(meta tk-w gc.dispatch_when_ready)" "<absent>" "nothing is armed to an unproved route"

echo "# a refused release pours nothing"
reset
export STUB_UPDATE_FAIL="tk-w"
run tk-w --reason "$REASON"
eq "$rc" 2 "a refused transition -> visit, exit 2"
eq "$(slings)" "0" "nothing is poured onto a bead the release did not reach"
eq "$(meta tk-w rejection_reason)" "<absent>" "the refused release wrote nothing"
has "$(cat "$STUB_ESC_LOG")" "lifecycle transition did not land or did not verify" "the visit names the refused release"

echo "# an unreadable bead pours nothing"
reset
export STUB_SHOW_FAIL=1
run tk-w --reason "$REASON"
eq "$rc" 2 "an unreadable bead -> visit, exit 2"
eq "$(grep -c '^bd update' "$STUB_GC_LOG" || true)" "0" "no write"
eq "$(slings)" "0" "no pour"
has "$(cat "$STUB_ESC_LOG")" "it could not be read" "the visit names the unreadable bead"

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
