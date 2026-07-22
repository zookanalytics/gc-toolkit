#!/usr/bin/env bash
# Hermetic test for quiesce-completed-workflows.sh (tk-p9ji9). Stubs `gc` (bd
# list/show/update, convoy status) on PATH. No live city, Dolt, or network.
#
# The pass retires the dead step beads of a mol-polecat-work molecule whose inline
# execution has finished, so the pool stops re-offering them. Covered:
#   (POOL)   unassigned + routed step under a DONE anchor  -> gc.routed_to cleared
#   (AFFINE) assigned + routed step under a DONE anchor    -> assignee cleared TOO
#            (clearing only routed_to is a no-op for this shape — it rides the
#            assigned-work path, which is keyed on the assignee)
#   (ATOMIC) both keys are cleared in ONE `gc bd update`, never two — a two-call
#            sequence briefly leaves the bead open+unassigned+routed, the exact
#            pool-offer shape, racing a fresh polecat into the husk
#   (LIVE)   anchor NOT terminal -> molecule untouched (a running polecat still
#            needs its assignee to claim the next step)
#   (NOCLOSE) no step bead is ever closed, and `status` is never rewritten — the
#            DANGER clause: closing load-context walks a polecat onto an already
#            green-gated branch and stales check.<gate>, blocking the open PR
#   (FINAL)  the workflow-finalize step keeps its control-dispatcher route — it is
#            the molecule's only escape path
#   (CLOSED) a CLOSED anchor also counts as done (strictly later than pull_request)
#   (FAILSAFE) unresolvable anchor -> skipped, never quiesced
#   (IDEM)   a second pass is a no-op; already-quiet steps are not re-updated
#   (DRY)    --dry-run reports the same selection but issues no update at all
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/quiesce-completed-workflows.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }

mkdir -p "$TMP/bin"

# --- Fixture ------------------------------------------------------------------
# Step beads: id|step_ref|root|routed_to|assignee|status
#
# root-DONE  : anchor parked in the merge gate (merge_result=pull_request).
#              Carries BOTH re-offer shapes plus its finalize step.
# root-LIVE  : anchor still open, no merge_result -> a live molecule, hands off.
# root-CLOSED: anchor CLOSED (landed) -> also done.
# root-ORPHAN: root has no input convoy -> anchor unresolvable -> fail closed.
# root-QUIET : already quiesced by an earlier pass -> counted, not re-updated.
cat > "$TMP/steps" <<'S'
s-pool|mol-polecat-work.workspace-setup|root-DONE|gc-toolkit/gc-toolkit.polecat||open
s-affine|mol-polecat-work.load-context|root-DONE|gc-toolkit/gc-toolkit.polecat|gc-toolkit__polecat-lx-dead|in_progress
s-final|mol-polecat-work.workflow-finalize|root-DONE|gc-toolkit/core.control-dispatcher||open
s-live|mol-polecat-work.load-context|root-LIVE|gc-toolkit/gc-toolkit.polecat|gc-toolkit__polecat-lx-busy|in_progress
s-closed|mol-polecat-work.implement|root-CLOSED|gc-toolkit/gc-toolkit.polecat|gc-toolkit__polecat-lx-gone|open
s-orphan|mol-polecat-work.implement|root-ORPHAN|gc-toolkit/gc-toolkit.polecat|gc-toolkit__polecat-lx-x|open
s-quiet|mol-polecat-work.implement|root-QUIET|||open
S

# Roots: root_id|convoy_id   (root-ORPHAN deliberately absent -> no convoy)
cat > "$TMP/roots" <<'R'
root-DONE|convoy-DONE
root-LIVE|convoy-LIVE
root-CLOSED|convoy-CLOSED
root-QUIET|convoy-QUIET
R

# Convoys: convoy_id|anchor_id
cat > "$TMP/convoys" <<'C'
convoy-DONE|anchor-DONE
convoy-LIVE|anchor-LIVE
convoy-CLOSED|anchor-CLOSED
convoy-QUIET|anchor-QUIET
C

# Anchors: anchor_id|status|merge_result
cat > "$TMP/anchors" <<'A'
anchor-DONE|open|pull_request
anchor-LIVE|open|
anchor-CLOSED|closed|
anchor-QUIET|open|pre_open_gate
A

: > "$TMP/updates"     # one line per `gc bd update` invocation (the full argv)
: > "$TMP/cleared"     # id -> which keys this pass cleared

# --- gc stub ------------------------------------------------------------------
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
case "$1 ${2:-}" in
  "convoy status")
    anchor=$(awk -F'|' -v c="$3" '$1==c{print $2; exit}' "$FAKE_CONVOYS")
    if [ -n "$anchor" ]; then jq -n --arg a "$anchor" '{children:[{id:$a}]}'
    else printf '{"children":[]}\n'; fi ;;
  "bd list")
    out=""
    while IFS='|' read -r id step root routed assignee status; do
      [ -n "$id" ] || continue
      # Re-read live (post-update) routed/assignee so pass 2 sees pass 1's writes.
      cur=$(awk -F'\t' -v i="$id" '$1==i{print $2"|"$3}' "$FAKE_STATE" 2>/dev/null)
      [ -n "$cur" ] && { routed="${cur%%|*}"; assignee="${cur##*|}"; }
      obj=$(jq -n --arg id "$id" --arg st "$step" --arg rt "$root" \
                  --arg ro "$routed" --arg as "$assignee" --arg s "$status" \
        '{id:$id, status:$s, assignee:$as,
          metadata:{"gc.step_ref":$st, "gc.root_bead_id":$rt, "gc.routed_to":$ro}}')
      if [ -z "$out" ]; then out="$obj"; else out="$out,$obj"; fi
    done < "$FAKE_STEPS"
    printf '[%s]\n' "$out" ;;
  "bd show")
    id="$3"
    convoy=$(awk -F'|' -v r="$id" '$1==r{print $2; exit}' "$FAKE_ROOTS")
    arow=$(awk -F'|' -v a="$id" '$1==a{print; exit}' "$FAKE_ANCHORS")
    if [ -n "$arow" ]; then
      st=$(printf '%s' "$arow" | cut -d'|' -f2); mr=$(printf '%s' "$arow" | cut -d'|' -f3)
      jq -n --arg s "$st" --arg m "$mr" '[{status:$s, metadata:{merge_result:$m}}]'
    elif [ -n "$convoy" ]; then
      jq -n --arg c "$convoy" '[{metadata:{"gc.input_convoy_id":$c}}]'
    else printf '[{"metadata":{}}]\n'; fi ;;
  "bd update")
    printf '%s\n' "$*" >> "$FAKE_UPDATES"
    id="$3"; keys=""
    case "$*" in *"--unset-metadata gc.routed_to"*) keys="routed" ;; esac
    case "$*" in *"--assignee"*) keys="${keys:+$keys+}assignee" ;; esac
    printf '%s\t%s\n' "$id" "$keys" >> "$FAKE_CLEARED"
    # Apply to live state so a second pass observes the result.
    routed=""; assignee=""
    case "$keys" in
      *routed*)   : ;;
    esac
    old=$(awk -F'|' -v i="$id" '$1==i{print $4"|"$5}' "$FAKE_STEPS")
    routed="${old%%|*}"; assignee="${old##*|}"
    case "$*" in *"--unset-metadata gc.routed_to"*) routed="" ;; esac
    case "$*" in *"--assignee"*) assignee="" ;; esac
    printf '%s\t%s\t%s\n' "$id" "$routed" "$assignee" >> "$FAKE_STATE" ;;
esac
exit 0
GC
chmod +x "$TMP/bin/gc"

export PATH="$TMP/bin:$PATH"
export FAKE_STEPS="$TMP/steps" FAKE_ROOTS="$TMP/roots" FAKE_CONVOYS="$TMP/convoys" \
       FAKE_ANCHORS="$TMP/anchors" FAKE_UPDATES="$TMP/updates" \
       FAKE_CLEARED="$TMP/cleared" FAKE_STATE="$TMP/state"
: > "$TMP/state"

# --- Run 0: --dry-run must select the same work but write nothing. ------------
OUT0="$(bash "$SCRIPT" --dry-run)"
eq "$(wc -l < "$TMP/updates" | tr -d ' ')" "0" "(DRY) --dry-run issues no gc bd update at all"
printf '%s\n' "$OUT0" | grep -q '(dry-run)' \
  && ok "(DRY) summary marks the pass as a dry run" || bad "(DRY) summary marks dry run (got: $OUT0)"
printf '%s\n' "$OUT0" | grep -q 's-affine' \
  && ok "(DRY) dry run still reports the steps it would quiesce" || bad "(DRY) dry run reports selection"

# --- Run 1: the real pass. ----------------------------------------------------
: > "$TMP/updates"; : > "$TMP/cleared"; : > "$TMP/state"
OUT1="$(bash "$SCRIPT" 2>"$TMP/err1")"
ERR1="$(cat "$TMP/err1")"

# (POOL) unassigned+routed under a done anchor -> routed_to cleared.
grep -q '^s-pool	routed$' "$TMP/cleared" \
  && ok "(POOL) unassigned+routed step -> gc.routed_to cleared (leaves the pool query)" \
  || bad "(POOL) routed_to cleared (got: $(grep '^s-pool' "$TMP/cleared" || echo none))"

# (AFFINE) assigned shape -> the assignee must go too, else the hand-back survives.
grep -q '^s-affine	routed+assignee$' "$TMP/cleared" \
  && ok "(AFFINE) assigned+affine step -> assignee cleared too (kills the existing_assignment hand-back)" \
  || bad "(AFFINE) assignee must also be cleared (got: $(grep '^s-affine' "$TMP/cleared" || echo none))"

# (ATOMIC) one update per bead — never a clear-assignee-then-clear-route sequence.
eq "$(grep -c '^s-affine' "$TMP/cleared")" "1" \
  "(ATOMIC) both keys cleared in a SINGLE update (no open+unassigned+routed race window)"
grep 'bd update s-affine' "$TMP/updates" | grep -q -- '--unset-metadata gc.routed_to' \
  && grep 'bd update s-affine' "$TMP/updates" | grep -q -- '--assignee' \
  && ok "(ATOMIC) the single update carries BOTH flags" || bad "(ATOMIC) one update carries both flags"

# (LIVE) a molecule whose anchor is still live is left completely alone.
grep -q '^s-live' "$TMP/cleared" \
  && bad "(LIVE) must NOT touch a live molecule's steps" \
  || ok "(LIVE) live anchor -> steps untouched (running polecat keeps its assignee)"
printf '%s\n' "$OUT1" | grep -q 'anchor anchor-LIVE still live' \
  && ok "(LIVE) summary explains why the live root was skipped" || bad "(LIVE) live-skip reason"

# (CLOSED) a closed anchor counts as done.
grep -q '^s-closed	routed+assignee$' "$TMP/cleared" \
  && ok "(CLOSED) closed anchor -> steps quiesced (landed is strictly past pull_request)" \
  || bad "(CLOSED) closed anchor treated as done"

# (FINAL) the finalize step keeps its control-dispatcher route.
grep -q '^s-final' "$TMP/cleared" \
  && bad "(FINAL) must NOT de-route workflow-finalize — it is the escape path" \
  || ok "(FINAL) workflow-finalize keeps its control-dispatcher route"

# (FAILSAFE) unresolvable anchor -> skipped, not quiesced.
grep -q '^s-orphan' "$TMP/cleared" \
  && bad "(FAILSAFE) must NOT quiesce a root whose anchor cannot be resolved" \
  || ok "(FAILSAFE) unresolved anchor -> skipped (fail closed)"
# The warning is a diagnostic, so it goes to stderr (matching the other passes);
# capture both streams to assert on it.
printf '%s\n' "$ERR1" | grep -q 'anchor unresolved' \
  && ok "(FAILSAFE) unresolved root is reported on stderr" || bad "(FAILSAFE) unresolved root reported"

# (NOCLOSE) the DANGER clause: nothing is ever closed and status is never written.
grep -qE -- '--status|--close|bd close' "$TMP/updates" \
  && bad "(NOCLOSE) pass must never close a step bead or rewrite status" \
  || ok "(NOCLOSE) no step bead closed, no status rewritten (DANGER clause honored)"
# Static guard: no close/status-write COMMAND may exist in the script at all.
# Matches invocations only — the header comments legitimately discuss closing,
# since explaining why this pass must never close is half the point of the file.
grep -qE -- 'bd close|--status[ =]+closed|--close([ =]|$)' "$SCRIPT" \
  && bad "(NOCLOSE) script must contain no close/status-write command" \
  || ok "(NOCLOSE) script contains no bead-close command whatsoever"

# (ANCHOR) the anchor bead itself is never updated.
grep -qE 'bd update anchor-' "$TMP/updates" \
  && bad "(ANCHOR) must never write to the anchor" || ok "(ANCHOR) anchor never modified"

# (QUIET) an already-quiesced step is counted, not re-updated.
grep -q '^s-quiet' "$TMP/cleared" \
  && bad "(QUIET) already-quiet step must not be re-updated" \
  || ok "(QUIET) already-quiet step skipped (idempotent)"

printf '%s\n' "$OUT1" | grep -q '3 steps quiesced across 3 completed workflow(s); 1 still live, 1 already quiet, 1 unresolved' \
  && ok "run 1 summary counts are exact" || bad "run 1 summary (got: $(printf '%s' "$OUT1" | tail -1))"

# --- Run 2: convergence — a swept molecule stays swept. -----------------------
: > "$TMP/cleared"; : > "$TMP/updates"
OUT2="$(bash "$SCRIPT")"
eq "$(wc -l < "$TMP/updates" | tr -d ' ')" "0" \
  "(IDEM) second pass issues no updates — quiesced steps stay quiesced"
printf '%s\n' "$OUT2" | grep -q '0 steps quiesced' \
  && ok "(IDEM) second pass reports nothing left to do" || bad "(IDEM) second-pass summary (got: $(printf '%s' "$OUT2" | tail -1))"

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
