#!/usr/bin/env bash
# Hermetic test for assets/scripts/rejection-repool.sh — the refinery's
# rejection, handed back to the polecat pool as a mol-polecat-work pour.
# Covers: the usage refusals; the release (one lifecycle transition that clears
# the assignee, the claim route and the last pour's execution stamp, and records
# rejection_reason and existing_pr) landing before the pour; the row read before
# the write, on stdout; the pool route proved and rig-qualified before any pour
# or arm, whether --pool names the pool or the default does; the pour proved by
# its own stamp and never by the one the last pour left; a failed sling armed
# for a retry, an exit-0 pour that does not read back never armed, and neither
# routed bare; a human gate on the handoff for every other way the repool stops
# short, and a patrol finding naming a handoff it could not read. The real
# lifecycle.sh (through a gctk built from this tree), pool-route.sh and
# deferred-dispatch.sh run against the harness store, and human-gate.sh and
# patrol-finding.sh are stubs that record their argv.
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
PF_STUB='#!/usr/bin/env bash
printf "%s\n" "$*" >> "${STUB_PF_LOG:?}"
exit 0'
SD="$TMP/scripts"
mk_sut_dir "$SD" "$HERE/rejection-repool.sh" "$HERE/lifecycle.sh" "$HERE/pool-route.sh" \
  "$HERE/deferred-dispatch.sh"
printf '%s\n' "$ESC_STUB" > "$SD/human-gate.sh"; chmod +x "$SD/human-gate.sh"
printf '%s\n' "$PF_STUB" > "$SD/patrol-finding.sh"; chmod +x "$SD/patrol-finding.sh"
# The same SUT beside a deferred-dispatch.sh whose arm does not land.
SD_NOARM="$TMP/scripts-noarm"
mk_sut_dir "$SD_NOARM" "$HERE/rejection-repool.sh" "$HERE/lifecycle.sh" "$HERE/pool-route.sh"
printf '%s\n' "$ESC_STUB" > "$SD_NOARM/human-gate.sh"; chmod +x "$SD_NOARM/human-gate.sh"
printf '%s\n' "$PF_STUB" > "$SD_NOARM/patrol-finding.sh"; chmod +x "$SD_NOARM/patrol-finding.sh"
printf '#!/usr/bin/env bash\necho "deferred-dispatch: arm refused (stub)" >&2\nexit 1\n' > "$SD_NOARM/deferred-dispatch.sh"
chmod +x "$SD_NOARM/deferred-dispatch.sh"
# A gc whose sling exits 0 and stamps nothing, the shape of a pour whose own
# execution stamp did not land. Every other call reaches the harness stub.
NOSTAMP="$TMP/bin-nostamp"; mkdir -p "$NOSTAMP"
printf '#!/usr/bin/env bash\n[ "${1:-}" = sling ] && { printf "%%s\\n" "$*" >> "${STUB_GC_LOG:?}"; exit 0; }\nexec "%s/gc" "$@"\n' "$BIN" > "$NOSTAMP/gc"
chmod +x "$NOSTAMP/gc"
# A gc whose sling pours and stamps as the harness does, and whose every read
# after it fails: a pour that launched while the store stopped answering.
READFAIL="$TMP/bin-readfail"; mkdir -p "$READFAIL"
printf '#!/usr/bin/env bash\nif [ "${1:-}" = sling ]; then "%s/gc" "$@"; rc=$?; : > "%s/slung"; exit $rc; fi\n[ "${1:-} ${2:-}" = "bd show" ] && [ -e "%s/slung" ] && exit 1\nexec "%s/gc" "$@"\n' "$BIN" "$TMP" "$TMP" "$BIN" > "$READFAIL/gc"
chmod +x "$READFAIL/gc"

export STUB_ESC_LOG="$TMP/esc.log" STUB_PF_LOG="$TMP/pf.log"
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
  : > "$STUB_GC_LOG"; : > "$STUB_ESC_LOG"; : > "$STUB_PF_LOG"; rm -f "$TMP/slung"
  export STUB_SLING_FAIL="" STUB_UPDATE_FAIL="" STUB_SHOW_FAIL="" STUB_AGENTS="" STUB_ESC_RC=""
}
# $out is stderr and stdout together; $TMP/stdout holds stdout alone.
_run() { "$@" > "$TMP/stdout" 2> "$TMP/stderr"; rc=$?; out=$(cat "$TMP/stderr" "$TMP/stdout"); }
run()  { _run "$SD/rejection-repool.sh" "$@"; }
run_noarm() { _run "$SD_NOARM/rejection-repool.sh" "$@"; }
stdout_meta() { jq -r --arg k "$1" '(.[0].metadata[$k] // "<absent>") | tostring' "$TMP/stdout" 2>/dev/null; }
slings() { grep -c '^sling ' "$STUB_GC_LOG" || true; }
gates() { wc -l < "$STUB_ESC_LOG" | tr -d ' '; }
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
eq "$(gates)" "0" "a proved pour files no gate"
eq "$(wc -l < "$TMP/stdout" | tr -d ' ')" "1" "stdout is one line"
eq "$(jq -r '.[0].id' "$TMP/stdout" 2>/dev/null)" "tk-w" "stdout is the bead's row"
eq "$(stdout_meta rejection_reason)" "<absent>" "the row is the read before the release: no rejection_reason yet"
eq "$(stdout_meta branch)" "polecat/tk-w" "the row carries the branch decision's inputs"

echo "# a live PR goes with the rework"
reset ',"pr_url":"https://github.com/o/r/pull/7"'
run tk-w --reason "$REASON"
eq "$rc" 0 "a bead with a PR pours"
eq "$(meta tk-w existing_pr)" "https://github.com/o/r/pull/7" "pr_url carried over as existing_pr"

echo "# the stamp the last pour left proves nothing, and an exit-0 pour is not poured again"
# The bead starts with gc.execution_routed_to naming this very pool. A pour that
# exits 0 without stamping it must not read back as proved off that stale value.
# It launched, and deferred-dispatch's reconcile keys its retry on its own
# marker, never on that stamp, so an arm would pour the work a second time.
reset
PATH="$NOSTAMP:$PATH" run tk-w --reason "$REASON"
eq "$rc" 2 "a pour that leaves no stamp of its own exits 2"
eq "$(slings)" "1" "it was poured once"
eq "$(meta tk-w gc.execution_routed_to)" "<absent>" "the stale stamp was cleared before the pour"
eq "$(meta tk-w gc.dispatch_when_ready)" "<absent>" "an exit-0 pour is never armed for a retry"
no_bare_route "an unproved pour is never routed bare"
eq "$(gates)" "1" "a gate carries it instead"
has "$(cat "$STUB_ESC_LOG")" "after gc sling exited 0" "the gate says the sling succeeded"
has "$(cat "$STUB_ESC_LOG")" "check that no mol-polecat-work workflow is live on it" "the gate asks for the live-workflow check before any re-pour"

echo "# a read that fails after an exit-0 pour is not poured again"
reset
PATH="$READFAIL:$PATH" run tk-w --reason "$REASON"
eq "$rc" 2 "an unreadable stamp after an exit-0 pour exits 2"
eq "$(slings)" "1" "it was poured once"
eq "$(meta tk-w gc.dispatch_when_ready)" "<absent>" "nothing is armed to pour it again"
eq "$(gates)" "1" "a gate carries it"
has "$(cat "$STUB_ESC_LOG")" "check that no mol-polecat-work workflow is live on it" "the gate asks for the live-workflow check"

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
eq "$(gates)" "0" "an armed retry files no gate"
eq "$(wc -l < "$TMP/stdout" | tr -d ' ')" "1" "stdout is still the one row: the arm's own output goes to stderr"

echo "# an arm that does not land files the gate"
reset
export STUB_SLING_FAIL=1
run_noarm tk-w --reason "$REASON"
eq "$rc" 2 "a gate carries the bead: exit 2"
eq "$(gates)" "1" "one gate"
esc=$(cat "$STUB_ESC_LOG")
has "$esc" "--subject tk-w --key rejection-repool-failed" "filed on the bead under its situation key"
has "$esc" "gc sling $ROUTE tk-w --on mol-polecat-work" "the gate names the pour that finishes it"
has "$esc" "rejection reason: $REASON)" "the gate carries the reason"
has "$esc" "--message A rejected handoff may never be rebuilt:" "the gate leads with the stake"
no_bare_route "no bare route behind the gate either"

echo "# nothing recorded: exit 3"
reset
export STUB_SLING_FAIL=1 STUB_ESC_RC=1
run_noarm tk-w --reason "$REASON"
eq "$rc" 3 "no arm and no gate -> exit 3"
has "$out" "NOTHING dispatches tk-w" "the run says nothing carries the bead"

echo "# the pool route is proved before any pour"
# A readable roster without the polecat identity, run once on the default pool
# and once with --pool named the way the patrol's rejection arms name it.
printf '%s\n' '{"agents":[{"qualified_name":"gc-toolkit/gc-toolkit.refinery"}]}' > "$TMP/no-polecat.json"
for pool_args in "" "--pool gc-toolkit.polecat"; do
  reset
  export STUB_AGENTS="$TMP/no-polecat.json"
  # shellcheck disable=SC2086 # $pool_args is the flag and its value, or nothing
  run tk-w --reason "$REASON" $pool_args
  how="${pool_args:-the default pool}"
  eq "$rc" 2 "an unclaimed pool ($how) -> gate, exit 2"
  eq "$(slings)" "0" "nothing is poured to a pool nobody claims ($how)"
  eq "$(meta tk-w rejection_reason)" "$REASON" "the reason is recorded for whoever finishes it ($how)"
  has "$(cat "$STUB_ESC_LOG")" "no live pool claims 'gc-toolkit.polecat'" "the gate names the missing pool ($how)"
  eq "$(meta tk-w gc.dispatch_when_ready)" "<absent>" "nothing is armed to an unproved route ($how)"
  no_bare_route "no route is stamped in its place ($how)"
done

echo "# a readable roster that carries the pool proves the route"
reset
printf '%s\n' "{\"agents\":[{\"qualified_name\":\"$ROUTE\"}]}" > "$TMP/agents.json"
export STUB_AGENTS="$TMP/agents.json"
run tk-w --reason "$REASON" --pool gc-toolkit.polecat
eq "$rc" 0 "a proved route pours"
has "$(cat "$STUB_GC_LOG")" "sling --rig gc-toolkit $ROUTE tk-w --on mol-polecat-work" "poured to the rig-qualified identity the roster lists"
case "$out" in *UNVERIFIED*) bad "the route was verified, not passed through unverified" ;; *) ok "the route was verified, not passed through unverified" ;; esac

echo "# --pool names the pool"
reset
run tk-w --reason "$REASON" --pool gc-toolkit.polecat
eq "$rc" 0 "a bare --pool qualified by GC_RIG pours"
has "$(cat "$STUB_GC_LOG")" "sling --rig gc-toolkit $ROUTE tk-w --on mol-polecat-work" "poured to <GC_RIG>/<pool>"
reset
GC_RIG="" run tk-w --reason "$REASON" --pool "$ROUTE"
eq "$rc" 0 "a rig-qualified --pool pours with GC_RIG unset"
has "$(cat "$STUB_GC_LOG")" "sling $ROUTE tk-w --on mol-polecat-work" "poured to the route --pool named"

echo "# a bare route is refused before any pour or arm"
# GC_RIG unset and an unreadable roster leave pool-route.sh only the bare name,
# returned unverified. A polecat pool's pour stamps its rig-qualified identity,
# so a pour to the bare name could never read back as proved.
reset
GC_RIG="" run tk-w --reason "$REASON"
eq "$rc" 2 "a bare route -> gate, exit 2"
eq "$(slings)" "0" "nothing is poured to a bare name"
eq "$(meta tk-w gc.dispatch_when_ready)" "<absent>" "nothing is armed to a bare name"
eq "$(meta tk-w rejection_reason)" "$REASON" "the release stands for whoever finishes it"
no_bare_route "the bare name is not stamped as a route either"
has "$(cat "$STUB_ESC_LOG")" "the bare 'gc-toolkit.polecat'" "the gate names the bare route"
has "$(cat "$STUB_ESC_LOG")" "gc sling <rig>/gc-toolkit.polecat tk-w --on mol-polecat-work" "the gate names the rig-qualified pour that finishes it"
reset
GC_RIG="" run tk-w --reason "$REASON" --pool gc-toolkit.polecat
eq "$rc" 2 "a bare --pool with GC_RIG unset is refused the same way"
eq "$(slings)" "0" "nothing is poured to the bare --pool"

echo "# a refused release pours nothing"
reset
export STUB_UPDATE_FAIL="tk-w"
run tk-w --reason "$REASON"
eq "$rc" 2 "a refused transition -> gate, exit 2"
eq "$(slings)" "0" "nothing is poured onto a bead the release did not reach"
eq "$(meta tk-w rejection_reason)" "<absent>" "the refused release wrote nothing"
has "$(cat "$STUB_ESC_LOG")" "lifecycle transition did not land or did not verify" "the gate names the refused release"
eq "$(jq -r '.[0].id' "$TMP/stdout" 2>/dev/null)" "tk-w" "the row read before the refused release is still on stdout"

echo "# an unreadable bead pours nothing"
reset
export STUB_SHOW_FAIL=1
run tk-w --reason "$REASON"
eq "$rc" 2 "an unreadable bead -> patrol finding, exit 2"
eq "$(grep -c '^bd update' "$STUB_GC_LOG" || true)" "0" "no write"
eq "$(slings)" "0" "no pour"
eq "$(cat "$STUB_ESC_LOG")" "" "no human gate: a bead no read reaches cannot be blocked"
has "$(cat "$STUB_PF_LOG")" "it could not be read" "the patrol finding names the unreadable bead"
has "$(cat "$STUB_PF_LOG")" "--key rejection-repool-unread.tk-w" "…under a key naming the bead"
eq "$(wc -c < "$TMP/stdout" | tr -d ' ')" "0" "no row on stdout"

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
