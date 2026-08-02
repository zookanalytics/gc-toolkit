#!/usr/bin/env bash
# Hermetic test for quiesce-completed-workflows.sh (tk-p9ji9, tk-z27pw). Stubs
# `gc` (bd list/show/update, convoy status) AND `bd` (update) on PATH. No live
# city, Dolt, or network.
#
# The pass retires the dead step beads of a mol-polecat-work molecule whose inline
# execution has finished, so the pool stops re-offering them. Covered:
#   (POOL)   unassigned + routed step under a DONE anchor  -> gc.routed_to cleared
#   (AFFINE) assigned + routed step under a DONE anchor    -> assignee cleared TOO
#            (clearing only routed_to is a no-op for this shape — it rides the
#            assigned-work path, which is keyed on the assignee)
#   (SPLIT)  the two keys go in TWO calls, never one batched update: bd's claim
#            guard refuses `--assignee ""` on a step held in_progress, and batched
#            that rejection rolls the route clear back too (tk-z27pw)
#   (ORDER)  route first, THEN assignee — the reverse order leaves the bead briefly
#            open+unassigned+routed, the exact pool-offer shape, racing a fresh
#            polecat into the husk
#   (FORCE)  the assignee clear passes --force and goes through bare `bd`, because
#            `gc bd` rejects --force in its bead-ID safety pre-check
#   (GUARD)  when the assignee clear is REFUSED, the route clear still lands — the
#            whole point of splitting; a refusal must not roll back the safe half
#   (ROUTEFAIL) the inverse: when the ROUTE clear is refused, the assignee clear is
#            SKIPPED, not attempted — clearing it while gc.routed_to survives makes
#            the open+unassigned+routed pool-offer shape the step's resting state
#   (EXIT)   a failed step update makes the pass exit NON-ZERO; exit 0 over failed
#            writes is what hid this bug for a day
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

: > "$TMP/updates"     # one line per update: "<binary> <argv>"
: > "$TMP/cleared"     # id -> which single key that call cleared

# --- Shared stub state --------------------------------------------------------
# Live (post-update) view of each step, so a later call and a second pass observe
# what earlier calls wrote. Last write for an id wins; absent -> fixture value.
cat > "$TMP/bin/_state.sh" <<'LIB'
state_get() {
  local cur
  cur=$(awk -F'\t' -v i="$1" '$1==i{r=$2"|"$3} END{if(r!="")print r}' "$FAKE_STATE" 2>/dev/null)
  if [ -n "$cur" ]; then printf '%s\n' "$cur"
  else awk -F'|' -v i="$1" '$1==i{print $4"|"$5; exit}' "$FAKE_STEPS"; fi
}
state_set() { printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$FAKE_STATE"; }
LIB

# --- gc stub ------------------------------------------------------------------
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
. "$FAKE_LIB"
case "$1 ${2:-}" in
  "convoy status")
    anchor=$(awk -F'|' -v c="$3" '$1==c{print $2; exit}' "$FAKE_CONVOYS")
    if [ -n "$anchor" ]; then jq -n --arg a "$anchor" '{children:[{id:$a}]}'
    else printf '{"children":[]}\n'; fi ;;
  "bd list")
    out=""
    while IFS='|' read -r id step root routed assignee status; do
      [ -n "$id" ] || continue
      cur=$(state_get "$id"); routed="${cur%%|*}"; assignee="${cur##*|}"
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
    printf 'gc %s\n' "$*" >> "$FAKE_UPDATES"
    id="$3"
    # Real wrapper behavior: `gc bd` aborts on --force in its bead-ID safety
    # pre-check ("unrecognized flag in args") and exits 1 — the clear never lands.
    case "$*" in
      *--force*) echo "gc bd: cannot safely verify bead IDs (unrecognized flag in args)" >&2
                 exit 1 ;;
    esac
    # Store-level refusal of the route clear — a wedged write, a transient error.
    # FAKE_GC_REFUSE_ROUTE lists ids whose --unset-metadata gc.routed_to call
    # fails, so the test can drive the route-first FAILURE path (tk-d553m). No
    # claim is involved in this half, so nothing but an injected fault reaches it.
    case "$*" in
      *"--unset-metadata gc.routed_to"*)
        case " ${FAKE_GC_REFUSE_ROUTE:-} " in
          *" $id "*) echo "gc bd: update failed for $id: store write refused" >&2; exit 1 ;;
        esac ;;
    esac
    cur=$(state_get "$id"); routed="${cur%%|*}"; assignee="${cur##*|}"
    # bd's claim guard, modeled on the gc path too: reassigning a bead that is
    # currently held is REFUSED without --force — which gc cannot pass. The refusal
    # fails the WHOLE update, so a batched call loses its --unset-metadata half as
    # well. That rollback IS the bug (tk-z27pw); re-batch the call and the test
    # reproduces it rather than quietly appearing to work.
    case "$*" in
      *"--assignee"*)
        if [ -n "$assignee" ]; then
          echo "cannot reassign $id: held by \"$assignee\" (in_progress)" >&2; exit 1
        fi ;;
    esac
    case "$*" in
      *"--unset-metadata gc.routed_to"*)
        routed=""; printf '%s\t%s\n' "$id" "routed" >> "$FAKE_CLEARED" ;;
    esac
    case "$*" in
      *"--assignee"*)
        assignee=""; printf '%s\t%s\n' "$id" "assignee" >> "$FAKE_CLEARED" ;;
    esac
    state_set "$id" "$routed" "$assignee" ;;
esac
exit 0
GC
chmod +x "$TMP/bin/gc"

# --- bd stub ------------------------------------------------------------------
# Models the claim guard the whole bug turns on: a reassign is REFUSED unless
# --force is passed. FAKE_BD_REFUSE lists ids that are refused even WITH --force,
# so the test can drive the failure path.
cat > "$TMP/bin/bd" <<'BD'
#!/usr/bin/env bash
. "$FAKE_LIB"
case "${1:-}" in
  update)
    printf 'bd %s\n' "$*" >> "$FAKE_UPDATES"
    id="$2"
    case " ${FAKE_BD_REFUSE:-} " in
      *" $id "*)
        echo "cannot reassign $id: held by \"gc-toolkit__polecat-lx-x\" (in_progress)" >&2
        exit 1 ;;
    esac
    case "$*" in
      *--force*) : ;;
      *) echo "cannot reassign $id: held by \"gc-toolkit__polecat-lx-x\" (in_progress); pass --force only if their claim is abandoned" >&2
         exit 1 ;;
    esac
    cur=$(state_get "$id"); routed="${cur%%|*}"; assignee="${cur##*|}"
    case "$*" in
      *"--assignee"*)
        assignee=""; printf '%s\t%s\n' "$id" "assignee" >> "$FAKE_CLEARED" ;;
    esac
    state_set "$id" "$routed" "$assignee" ;;
esac
exit 0
BD
chmod +x "$TMP/bin/bd"

export PATH="$TMP/bin:$PATH"
export FAKE_STEPS="$TMP/steps" FAKE_ROOTS="$TMP/roots" FAKE_CONVOYS="$TMP/convoys" \
       FAKE_ANCHORS="$TMP/anchors" FAKE_UPDATES="$TMP/updates" \
       FAKE_CLEARED="$TMP/cleared" FAKE_STATE="$TMP/state" FAKE_LIB="$TMP/bin/_state.sh"
: > "$TMP/state"

# --- Run 0: --dry-run must select the same work but write nothing. ------------
OUT0="$(bash "$SCRIPT" --dry-run)"
eq "$(wc -l < "$TMP/updates" | tr -d ' ')" "0" "(DRY) --dry-run issues no update at all"
printf '%s\n' "$OUT0" | grep -q '(dry-run)' \
  && ok "(DRY) summary marks the pass as a dry run" || bad "(DRY) summary marks dry run (got: $OUT0)"
printf '%s\n' "$OUT0" | grep -q 's-affine' \
  && ok "(DRY) dry run still reports the steps it would quiesce" || bad "(DRY) dry run reports selection"

# --- Run 1: the real pass. ----------------------------------------------------
: > "$TMP/updates"; : > "$TMP/cleared"; : > "$TMP/state"
RC1=0
OUT1="$(bash "$SCRIPT" 2>"$TMP/err1")" || RC1=$?
ERR1="$(cat "$TMP/err1")"

# (POOL) unassigned+routed under a done anchor -> routed_to cleared, nothing else.
grep -q '^s-pool	routed$' "$TMP/cleared" \
  && ok "(POOL) unassigned+routed step -> gc.routed_to cleared (leaves the pool query)" \
  || bad "(POOL) routed_to cleared (got: $(grep '^s-pool' "$TMP/cleared" || echo none))"
grep -q '^s-pool	assignee$' "$TMP/cleared" \
  && bad "(POOL) an unassigned step needs no assignee call" \
  || ok "(POOL) unassigned step -> no assignee call issued (nothing to clear)"

# (AFFINE) assigned shape -> the assignee must go too, else the hand-back survives.
grep -q '^s-affine	routed$' "$TMP/cleared" && grep -q '^s-affine	assignee$' "$TMP/cleared" \
  && ok "(AFFINE) assigned+affine step -> BOTH keys cleared (kills the existing_assignment hand-back)" \
  || bad "(AFFINE) both keys must be cleared (got: $(grep '^s-affine' "$TMP/cleared" || echo none))"

# (SPLIT) two separate calls — a single batched update is the bug (tk-z27pw): the
# claim guard rejects the assignee half and rolls the route clear back with it.
eq "$(grep -c '^gc bd update s-affine' "$TMP/updates")" "1" \
  "(SPLIT) exactly one gc call for the route clear"
eq "$(grep -c '^bd update s-affine' "$TMP/updates")" "1" \
  "(SPLIT) exactly one bd call for the assignee clear"
grep '^gc bd update s-affine' "$TMP/updates" | grep -q -- '--assignee' \
  && bad "(SPLIT) the route call must NOT also carry --assignee (that is the batched update that fails closed)" \
  || ok "(SPLIT) route call carries only --unset-metadata, never --assignee"
grep '^bd update s-affine' "$TMP/updates" | grep -q -- '--unset-metadata' \
  && bad "(SPLIT) the assignee call must NOT also carry --unset-metadata" \
  || ok "(SPLIT) assignee call carries only --assignee"

# (ORDER) route FIRST. Clearing the assignee first would leave the bead briefly
# open+unassigned+routed — the pool-offer shape — racing in a fresh polecat.
# `|| true` on both: under set -e + pipefail a no-match grep would abort the whole
# suite here, hiding every assertion below it — exactly what a regression run needs
# to see when this check is the one that broke.
GCLINE="$(grep -n '^gc bd update s-affine' "$TMP/updates" | head -1 | cut -d: -f1 || true)"
BDLINE="$(grep -n '^bd update s-affine' "$TMP/updates" | head -1 | cut -d: -f1 || true)"
{ [ -n "$GCLINE" ] && [ -n "$BDLINE" ] && [ "$GCLINE" -lt "$BDLINE" ]; } \
  && ok "(ORDER) route cleared BEFORE the assignee (never open+unassigned+routed)" \
  || bad "(ORDER) route must be cleared first (route line '$GCLINE', assignee line '$BDLINE')"

# (FORCE) the assignee clear must pass --force and must not go via the gc wrapper,
# which aborts on --force in its bead-ID safety pre-check.
grep '^bd update s-affine' "$TMP/updates" | grep -q -- '--force' \
  && ok "(FORCE) assignee clear passes --force past the claim guard" \
  || bad "(FORCE) assignee clear must pass --force (got: $(grep '^bd update s-affine' "$TMP/updates" || echo none))"
grep -qE '^gc bd update .*--force' "$TMP/updates" \
  && bad "(FORCE) --force must never be sent through gc bd — the wrapper rejects it and exits 1" \
  || ok "(FORCE) --force is never routed through the gc wrapper"

# (LIVE) a molecule whose anchor is still live is left completely alone.
grep -q '^s-live' "$TMP/cleared" \
  && bad "(LIVE) must NOT touch a live molecule's steps" \
  || ok "(LIVE) live anchor -> steps untouched (running polecat keeps its assignee)"
printf '%s\n' "$OUT1" | grep -q 'anchor anchor-LIVE still live' \
  && ok "(LIVE) summary explains why the live root was skipped" || bad "(LIVE) live-skip reason"

# (CLOSED) a closed anchor counts as done.
grep -q '^s-closed	routed$' "$TMP/cleared" && grep -q '^s-closed	assignee$' "$TMP/cleared" \
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

printf '%s\n' "$OUT1" | grep -q '3 steps quiesced across 3 completed workflow(s); 1 still live, 1 already quiet, 1 unresolved, 0 failed' \
  && ok "run 1 summary counts are exact" || bad "run 1 summary (got: $(printf '%s' "$OUT1" | tail -1))"
eq "$RC1" "0" "(EXIT) a clean pass exits 0"

# --- Run 2: convergence — a swept molecule stays swept. -----------------------
: > "$TMP/cleared"; : > "$TMP/updates"
RC2=0
OUT2="$(bash "$SCRIPT")" || RC2=$?
eq "$(wc -l < "$TMP/updates" | tr -d ' ')" "0" \
  "(IDEM) second pass issues no updates — quiesced steps stay quiesced"
printf '%s\n' "$OUT2" | grep -q '0 steps quiesced' \
  && ok "(IDEM) second pass reports nothing left to do" || bad "(IDEM) second-pass summary (got: $(printf '%s' "$OUT2" | tail -1))"
eq "$RC2" "0" "(IDEM) a no-op pass exits 0"

# --- Run 3: the claim guard refuses the assignee clear. -----------------------
# THE regression this bead is about. Batched into one update, the refusal rolled
# the route clear back too, the step stayed fully re-offerable, and the pass still
# exited 0. Split, the route clear must land anyway — and the pass must say it
# failed.
: > "$TMP/cleared"; : > "$TMP/updates"; : > "$TMP/state"
RC3=0
OUT3="$(FAKE_BD_REFUSE="s-affine" bash "$SCRIPT" 2>"$TMP/err3")" || RC3=$?
ERR3="$(cat "$TMP/err3")"

grep -q '^s-affine	routed$' "$TMP/cleared" \
  && ok "(GUARD) refused assignee clear does NOT roll back the route clear (the split's whole point)" \
  || bad "(GUARD) route clear must still land when the assignee clear is refused"
grep -q '^s-affine	assignee$' "$TMP/cleared" \
  && bad "(GUARD) the refused assignee clear must not be recorded as applied" \
  || ok "(GUARD) refused assignee clear leaves the assignee intact"
printf '%s\n' "$ERR3" | grep -q 's-affine assignee clear failed' \
  && ok "(GUARD) the refused half is reported on stderr, naming the key" \
  || bad "(GUARD) refusal reported on stderr (got: $ERR3)"
printf '%s\n' "$ERR3" | grep -q 's-affine route clear failed' \
  && bad "(GUARD) the route half succeeded and must not be reported as failed" \
  || ok "(GUARD) the successful route half is not reported as a failure"

# A partial clear is a failure, never a success: the step still rides the affine
# hand-back, so counting it quiesced would be the same lie in a new place.
printf '%s\n' "$OUT3" | grep -q '2 steps quiesced across 3 completed workflow(s); 1 still live, 1 already quiet, 1 unresolved, 1 failed' \
  && ok "(EXIT) a partially-cleared step counts as failed, not quiesced" \
  || bad "(EXIT) run 3 summary (got: $(printf '%s' "$OUT3" | tail -1))"
[ "$RC3" -ne 0 ] \
  && ok "(EXIT) a failed step update makes the pass exit non-zero (exit 0 is what hid this)" \
  || bad "(EXIT) pass must exit non-zero when a step update failed (got rc=$RC3)"

# --- Run 4: the ROUTE clear is refused. ---------------------------------------
# The inverse of run 3, and the reason the assignee clear is GATED on route
# success (tk-d553m). Route-first ordering only rules out the pool-offer shape
# while the route clear LANDS. If it fails and the forced assignee clear runs
# anyway, the step comes to rest open + UNASSIGNED + still-routed — that shape as
# a durable state rather than a momentary window, and strictly worse than the
# assigned+routed husk the pass found. So the assignee half must be SKIPPED, the
# step left exactly as it was, and the pass must still say it failed.
: > "$TMP/cleared"; : > "$TMP/updates"; : > "$TMP/state"
RC4=0
OUT4="$(FAKE_GC_REFUSE_ROUTE="s-affine s-pool" bash "$SCRIPT" 2>"$TMP/err4")" || RC4=$?
ERR4="$(cat "$TMP/err4")"

# The gating assertion: no assignee call may be ISSUED at all for a step whose
# route is still set — not merely refused downstream by the claim guard.
grep -q '^bd update s-affine' "$TMP/updates" \
  && bad "(ROUTEFAIL) forced assignee clear must be SKIPPED when the route clear failed (it would leave the step open+unassigned+routed)" \
  || ok "(ROUTEFAIL) route-clear failure skips the forced assignee clear entirely"
grep -q '^s-affine	assignee$' "$TMP/cleared" \
  && bad "(ROUTEFAIL) the assignee must stay intact while gc.routed_to survives" \
  || ok "(ROUTEFAIL) assignee left intact — step stays assigned+routed, as it was found"
grep -q '^s-affine	routed$' "$TMP/cleared" \
  && bad "(ROUTEFAIL) a refused route clear must not be recorded as applied" \
  || ok "(ROUTEFAIL) refused route clear leaves gc.routed_to set"

printf '%s\n' "$ERR4" | grep -q 's-affine route clear failed' \
  && ok "(ROUTEFAIL) the failed route half is reported on stderr, naming the key" \
  || bad "(ROUTEFAIL) route failure reported on stderr (got: $ERR4)"
printf '%s\n' "$ERR4" | grep -q 's-affine assignee clear skipped' \
  && ok "(ROUTEFAIL) the skipped assignee half is reported, and says why" \
  || bad "(ROUTEFAIL) skip reason reported on stderr (got: $ERR4)"
printf '%s\n' "$ERR4" | grep -q 's-affine assignee clear failed' \
  && bad "(ROUTEFAIL) a SKIPPED assignee clear must not be reported as a failed one" \
  || ok "(ROUTEFAIL) skipped is reported as skipped, never as an attempted-and-failed clear"

# The route-only shape has no assignee to skip, but a refused clear must still be
# counted failed rather than silently passed over.
grep -q '^s-pool	routed$' "$TMP/cleared" \
  && bad "(ROUTEFAIL) a refused route clear on the pool shape must not be recorded as applied" \
  || ok "(ROUTEFAIL) route-only step -> refused clear leaves gc.routed_to set"
grep -q '^bd update s-pool' "$TMP/updates" \
  && bad "(ROUTEFAIL) an unassigned step must never reach the assignee call" \
  || ok "(ROUTEFAIL) route-only step issues no assignee call"

printf '%s\n' "$OUT4" | grep -q '1 steps quiesced across 3 completed workflow(s); 1 still live, 1 already quiet, 1 unresolved, 2 failed' \
  && ok "(ROUTEFAIL) both route failures count as failed, not quiesced" \
  || bad "(ROUTEFAIL) run 4 summary (got: $(printf '%s' "$OUT4" | tail -1))"
[ "$RC4" -ne 0 ] \
  && ok "(ROUTEFAIL) a failed route clear makes the pass exit non-zero" \
  || bad "(ROUTEFAIL) pass must exit non-zero when the route clear failed (got rc=$RC4)"

# The unaffected root still sweeps: one failing step must not strand its siblings.
grep -q '^s-closed	routed$' "$TMP/cleared" && grep -q '^s-closed	assignee$' "$TMP/cleared" \
  && ok "(ROUTEFAIL) a route failure under one root leaves other roots fully swept" \
  || bad "(ROUTEFAIL) unaffected root must still quiesce (got: $(grep '^s-closed' "$TMP/cleared" || echo none))"

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
