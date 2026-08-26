#!/usr/bin/env bash
# Hermetic test for assets/scripts/refinery-reconcile.sh — the merge-cadence
# driver. Covers: GC_RIG required; refinery discovery + pool derivation;
# the arm ORDER (gate-ensure, pr-open, merge, pr-facts, convoy-graduate);
# the heal-gates-merge interlock (rc=3 from gate-ensure HOLDS merge.sh in the
# same pass, without failing the order), exercised by extracting and executing
# the marked block against stubs; BEADS_ACTOR / GC_AGENT projections scoped to
# their arms; a failing arm not skipping the arms after it; and the exit-1
# failure report.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"
harness_init
RUNNER="$HERE/refinery-reconcile.sh"

# Stub arms record invocation order, args and the projected identities.
SD="$TMP/scripts"
mkdir -p "$SD"
cp "$RUNNER" "$SD/refinery-reconcile.sh"
chmod +x "$SD/refinery-reconcile.sh"
mkarm() { # <name> [rc]
  cat > "$SD/$1" <<ARM
#!/usr/bin/env bash
printf '%s|%s|%s|%s\n' "$1" "\$*" "\${BEADS_ACTOR:-}" "\${GC_AGENT:-}" >> "\${ARM_LOG:?}"
exit ${2:-0}
ARM
  chmod +x "$SD/$1"
}
export ARM_LOG="$TMP/arms.log"
export STUB_AGENTS="$TMP/agents.json"
printf '{"agents":[{"qualified_name":"myrig/gc-toolkit.refinery"},{"qualified_name":"myrig/gc-toolkit.polecat"}]}' > "$STUB_AGENTS"
export REFINERY_RECONCILE_STATE_DIR="$TMP/state"
export STUB_ORIGIN_HEAD="main"
unset BEADS_ACTOR GC_AGENT GC_PACK_NAME 2>/dev/null || true

drive() { GC_RIG=myrig GC_RIG_ROOT="$TMP" "$SD/refinery-reconcile.sh" 2>&1; }

echo "# GC_RIG is required"
out=$(env -u GC_RIG "$SD/refinery-reconcile.sh" 2>&1); rc=$?
eq "$rc" 2 "no GC_RIG exits 2"
has "$out" "GC_RIG is unset" "…and says why"

echo "# arms run in order with derived pools and scoped identities"
for a in gate-ensure.sh pr-open.sh merge.sh pr-facts.sh convoy-graduate.sh; do mkarm "$a"; done
: > "$ARM_LOG"
out=$(drive); rc=$?
eq "$rc" 0 "a clean pass exits 0"
order=$(cut -d'|' -f1 "$ARM_LOG" | paste -sd, -)
eq "$order" "gate-ensure.sh,pr-open.sh,merge.sh,pr-facts.sh,convoy-graduate.sh" "the five arms ran in the load-bearing order"
has "$(grep '^gate-ensure' "$ARM_LOG")" "--default codex,triage --review-pool myrig/gc-toolkit.polecat-codex --fix-pool myrig/gc-toolkit.polecat" "gate-ensure got the declared default + derived review AND fix pools"
merge_line=$(grep '^merge.sh' "$ARM_LOG")
has "$merge_line" "|myrig/gc-toolkit.refinery|" "merge.sh ran as BEADS_ACTOR=<refinery>"
facts_line=$(grep '^pr-facts' "$ARM_LOG")
has "$facts_line" "--fix-pool myrig/gc-toolkit.polecat --review-pool myrig/gc-toolkit.polecat-codex" "pr-facts got both derived pools"
has "$facts_line" "|myrig/gc-toolkit.refinery|" "pr-facts ran as BEADS_ACTOR=<refinery>"
grad_line=$(grep '^convoy-graduate' "$ARM_LOG")
has "$grad_line" "--target main" "convoy-graduate got the origin/HEAD target"
has "$grad_line" "|myrig/gc-toolkit.refinery" "convoy-graduate ran with GC_AGENT=<refinery>"
gate_line=$(grep '^gate-ensure' "$ARM_LOG")
case "$gate_line" in
  *"|myrig/gc-toolkit.refinery|"*) bad "gate-ensure must NOT inherit BEADS_ACTOR (projection is scoped to the closing arms)" ;;
  *) ok "identity projections are scoped, not process-wide" ;;
esac

echo "# gate-ensure rc=3 HOLDS merge.sh without failing the order"
mkarm gate-ensure.sh 3
: > "$ARM_LOG"
out=$(drive); rc=$?
eq "$rc" 0 "the designed hold does not fail the order"
has "$out" "merge.sh HELD this pass" "the hold is reported"
if grep -q '^merge.sh' "$ARM_LOG"; then bad "merge.sh RAN despite an unsafe gate-ensure"; else ok "merge.sh did not run"; fi
grep -q '^pr-facts' "$ARM_LOG" && ok "pr-facts still ran (arms are independent)" || bad "pr-facts was skipped by the hold"

echo "# a failing arm fails the order but does not skip later arms"
mkarm gate-ensure.sh
mkarm pr-open.sh 1
: > "$ARM_LOG"
out=$(drive); rc=$?
eq "$rc" 1 "a failing arm exits 1"
has "$out" "pr-open rc=1" "…naming the failed arm"
grep -q '^merge.sh' "$ARM_LOG" && ok "merge.sh still ran after the pr-open failure" || bad "merge.sh was skipped"
grep -q '^convoy-graduate' "$ARM_LOG" && ok "convoy-graduate still ran" || bad "convoy-graduate was skipped"

echo "# integration_auto_land=false disables graduation only"
mkarm pr-open.sh
: > "$ARM_LOG"
out=$(REFINERY_RECONCILE_INTEGRATION_AUTO_LAND=false drive); rc=$?
eq "$rc" 0 "the disabled pass exits 0"
if grep -q '^convoy-graduate' "$ARM_LOG"; then bad "convoy-graduate ran despite the kill-switch"; else ok "convoy-graduate disabled"; fi
grep -q '^merge.sh' "$ARM_LOG" && ok "the merge arm is untouched by the switch" || bad "merge arm missing"

echo "# no refinery bound = nothing to reconcile"
printf '{"agents":[]}' > "$STUB_AGENTS"
out=$(drive); rc=$?
eq "$rc" 0 "no bound refinery exits 0"
has "$out" "no refinery agent bound" "…and says so"
printf '{"agents":[{"qualified_name":"myrig/gc-toolkit.refinery"}]}' > "$STUB_AGENTS"

echo "# the marked interlock block executes standalone against stubs"
GATE="$(awk '/# >>> heal-gates-merge/{f=1;next} /# <<< heal-gates-merge/{f=0} f' "$RUNNER")"
[ -n "$GATE" ] && ok "heal-gates-merge block extracted" || bad "heal-gates-merge markers missing"
hasnt "$GATE" '{{' "the block is template-free (executable verbatim)"
GSD="$TMP/gsd"; mkdir -p "$GSD"
printf '#!/usr/bin/env bash\nexit 3\n' > "$GSD/gate-ensure.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$GSD/pr-open.sh"
printf '#!/usr/bin/env bash\necho ran >> "${MERGE_SENTINEL:?}"\n' > "$GSD/merge.sh"
chmod +x "$GSD"/*.sh
export MERGE_SENTINEL="$TMP/merge-ran"; : > "$MERGE_SENTINEL"
{
  printf 'set -u\nSCRIPTS_DIR=%q\nPASS_OUT=""\nNOTED=""\nFAILED=""\n' "$GSD"
  printf 'AGENT=%q\nCHECK_SET_DEFAULT=%q\nREVIEW_POOL=%q\nFIX_POOL=%q\n' \
    'myrig/gc-toolkit.refinery' codex 'myrig/p-codex' 'myrig/p'
  printf '%s\n' "$GATE"
  printf 'echo "MERGE_HELD=$MERGE_HELD"\n'
} > "$TMP/gaterun.sh"
gout=$(bash "$TMP/gaterun.sh" 2>/dev/null)
[ -s "$MERGE_SENTINEL" ] && bad "(block) merge.sh RAN despite rc=3" || ok "(block) rc=3 held merge.sh"
has "$gout" "MERGE_HELD=1" "(block) the hold flag is set"
printf '#!/usr/bin/env bash\nexit 0\n' > "$GSD/gate-ensure.sh"
: > "$MERGE_SENTINEL"
gout=$(bash "$TMP/gaterun.sh" 2>/dev/null)
[ -s "$MERGE_SENTINEL" ] && ok "(block) a clean gate-ensure lets merge.sh run" || bad "(block) merge.sh did not run after a clean gate-ensure"
has "$gout" "MERGE_HELD=0" "(block) the hold flag is clear"

echo "# the shipped order stays wired to this runner"
ORDER="$(cd "$HERE/../.." && pwd)/orders/refinery-reconcile.toml"
o=$(cat "$ORDER" 2>/dev/null)
has "$o" 'trigger = "cooldown"' "order is cooldown-triggered"
has "$o" 'interval = "60s"' "order keeps the 60s cadence"
has "$o" 'timeout = "300s"' "order timeout stays under the 10m tracking sweep"
has "$o" 'scope = "rig"' "order is rig-scoped (single-flight per rig)"
has "$o" 'refinery-reconcile.sh' "order execs this runner"
if grep -qE '^[[:space:]]*no_work_gate' "$ORDER"; then
  bad "no_work_gate must never be set (it opts out of the single-flight gate)"
else
  ok "no_work_gate is not set"
fi

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
