#!/usr/bin/env bash
# Hermetic test for quiesce-completed-workflows.sh (tk-p9ji9, tk-z27pw,
# tk-q5r65). Stubs `gc` (bd list/show/update, convoy status) AND `bd` (update) on
# PATH. No live city, Dolt, or network.
#
# The pass retires the dead step beads of a graph.v2 molecule whose inline
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
#   (HANDOFF) anchor in the refinery-handoff WINDOW — status=open, merge_result
#            not yet stamped, assignee=<rig>/<prefix>refinery — also counts as
#            done (tk-yxlqb); the polecat is past its work whether or not the
#            refinery has stamped merge_result yet
#   (HELD)   anchor PARKED FOR A HUMAN — status=blocked, merge_result never
#            stamped (the refinery held it before dispatching a review), assignee
#            CLEARED by the park, gc.routed_to=human — counts as done (tk-rlm94).
#            The longest-lived husk shape: it lasts the whole human-decision wait,
#            not a window of minutes
#   (BARE)   bare `blocked` with NO routed_to is NOT terminal — the escalation
#            path sets blocked before it drains, so a live session is reachable in
#            that state and quiescing it would drain a polecat mid-implementation
#   (ROUTEONLY) routed_to=human on an anchor that is still `open` is NOT terminal
#            either — the predicate is a CONJUNCTION, and each half alone is a
#            shape a live molecule can wear
#   (LIVE)   anchor NOT terminal -> molecule untouched (a running polecat still
#            needs its assignee to claim the next step), INCLUDING an anchor that
#            is assigned — to a polecat, not a refinery: the handoff predicate
#            matches the refinery specifically, not "has an assignee". The polecat
#            holding it is the molecule's OWN session, which is what separates this
#            from (RECLAIM)
#   (RECLAIM) anchor re-pooled after a refinery REJECTION and re-claimed by ANOTHER
#            polecat session (tk-nv3qr) — in_progress, unstamped, polecat-held, so
#            no older predicate fires — also counts as done: the new owner works it
#            as a bare bead and never re-walks this molecule's step graph
#   (STALE)  the fail-closed half of (RECLAIM): a gc.session_name the anchor is NOT
#            currently held under is a leftover from an earlier claim, never proof
#            of a new owner -> left alone
#   (NOSESS) the other fail-closed half: an anchor holding no session record at all
#            leaves nothing to compare -> left alone
#   (CROSS-RECLAIM) / (CROSS-HELD) the INTERSECTION of the park and re-claim
#            predicates. They were written in parallel against the same function and
#            both claimed $4, so on their own branches each was only ever exercised
#            with the other's field absent and the collision was resolved by hand.
#            Every other fixture populates exactly one of the two fields, so crossing
#            the argument positions still satisfies all of them; these populate BOTH
#            and each must still be decided by its OWN clause
#   (NOCLOSE) no step bead is ever closed, and `status` is never rewritten — the
#            DANGER clause: closing load-context walks a polecat onto an already
#            green-gated branch and stales check.<gate>, blocking the open PR
#   (FINAL)  the workflow-finalize step keeps its control-dispatcher route — it is
#            the molecule's only escape path
#   (CLOSED) a CLOSED anchor also counts as done (strictly later than pull_request)
#   (FAILSAFE) unresolvable anchor -> skipped, never quiesced
#   (CONTRACT) steps are selected by the graph.v2 CONTRACT, not by formula name
#            (tk-q5r65): a mol-scoped-work husk quiesces exactly like a
#            mol-polecat-work one, and its workflow-finalize step is just as
#            protected. The old startswith("mol-polecat-work.") row filter
#            dropped every other formula BEFORE the anchor verdict, so those
#            husks re-offered forever and showed up in neither summary list
#   (NOTV2)  a bead with no gc.step_ref is not a graph.v2 step and is never a
#            candidate — asserted under a TERMINAL anchor, so the membership
#            test is the only thing holding it back
#   (NOROOT) a step with no gc.root_bead_id is never touched (nothing could
#            anchor-verify it)
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
# root-LIVE  : anchor still open, no merge_result, assigned to the POLECAT that is
#              still working it -> a live molecule, hands off.
# root-CLOSED: anchor CLOSED (landed) -> also done.
# root-HANDOFF: anchor open + UNSTAMPED but already assigned to the refinery — the
#              handoff window (tk-yxlqb) -> done.
# root-ORPHAN: root has no input convoy -> anchor unresolvable -> fail closed.
# root-QUIET : already quiesced by an earlier pass -> counted, not re-updated.
# root-SCOPED: a graph.v2 molecule that is NOT mol-polecat-work (mol-scoped-work,
#              a core pack formula) with a terminal anchor -> quiesced all the
#              same. The pass selects by CONTRACT, not by formula name (tk-q5r65).
# root-NOREF : terminal anchor, but its bead carries NO gc.step_ref — not a
#              graph.v2 step, so it is never a candidate. Its anchor is DONE on
#              purpose: the membership test is the only thing holding it back.
# root-HELD  : anchor PARKED FOR A HUMAN (blocked + gc.routed_to=human, assignee
#              cleared, merge_result never stamped) -> done (tk-rlm94).
# root-BARE  : anchor `blocked` with NO route -> still live; the escalation path
#              passes through this state while a session is still alive.
# root-ROUTEONLY: anchor routed_to=human but still `open` -> still live; the park
#              predicate is a conjunction and neither half alone is terminal.
# root-RECLAIM: anchor re-pooled after a refinery rejection and re-claimed by
#              ANOTHER polecat session (tk-nv3qr) -> done, this molecule is dead.
# root-STALE : anchor records a DIFFERENT session, but is not held by it — a
#              leftover from an earlier claim -> fail closed, left alone.
# root-NOSESS: anchor held under a session name it does not record -> nothing to
#              compare -> fail closed, left alone.
# root-RECLAIMROUTED / root-HELDSESS: the INTERSECTION of the park predicate
#              (tk-rlm94) and the re-claim predicate (tk-nv3qr). The two clauses were
#              written in parallel against the same function and both wanted $4, so
#              they were only ever exercised on branches where the other did not
#              exist. Each of these carries the OTHER clause's field populated, and
#              must still be decided by its own: RECLAIMROUTED is a re-claim that
#              also carries a live pool route (the shape a re-pooled anchor really
#              has), HELDSESS is a park that also records a session. Cross the
#              argument positions in the merge and exactly these two flip.
cat > "$TMP/steps" <<'S'
s-pool|mol-polecat-work.workspace-setup|root-DONE|gc-toolkit/gc-toolkit.polecat||open
s-affine|mol-polecat-work.load-context|root-DONE|gc-toolkit/gc-toolkit.polecat|gc-toolkit__polecat-lx-dead|in_progress
s-final|mol-polecat-work.workflow-finalize|root-DONE|gc-toolkit/core.control-dispatcher||open
s-live|mol-polecat-work.load-context|root-LIVE|gc-toolkit/gc-toolkit.polecat|gc-toolkit__polecat-lx-busy|in_progress
s-closed|mol-polecat-work.implement|root-CLOSED|gc-toolkit/gc-toolkit.polecat|gc-toolkit__polecat-lx-gone|open
s-handoff|mol-polecat-work.load-context|root-HANDOFF|gc-toolkit/gc-toolkit.polecat|gc-toolkit__polecat-lx-drained|in_progress
s-orphan|mol-polecat-work.implement|root-ORPHAN|gc-toolkit/gc-toolkit.polecat|gc-toolkit__polecat-lx-x|open
s-quiet|mol-polecat-work.implement|root-QUIET|||open
s-scoped|mol-scoped-work.load-context|root-SCOPED|gc-toolkit/gc-toolkit.polecat|gc-toolkit__polecat-lx-scoped|in_progress
s-scopedfin|mol-scoped-work.workflow-finalize|root-SCOPED|gc-toolkit/core.control-dispatcher||open
s-noref||root-NOREF|gc-toolkit/gc-toolkit.polecat|gc-toolkit__polecat-lx-noref|open
s-noroot|mol-scoped-work.implement||gc-toolkit/gc-toolkit.polecat|gc-toolkit__polecat-lx-noroot|open
s-held|mol-polecat-work.load-context|root-HELD|gc-toolkit/gc-toolkit.polecat|gc-toolkit__polecat-lx-parked|in_progress
s-bare|mol-polecat-work.load-context|root-BARE|gc-toolkit/gc-toolkit.polecat|gc-toolkit__polecat-lx-esc|in_progress
s-routeonly|mol-polecat-work.load-context|root-ROUTEONLY|gc-toolkit/gc-toolkit.polecat|gc-toolkit__polecat-lx-open|in_progress
s-reclaim|mol-polecat-work.load-context|root-RECLAIM|gc-toolkit/gc-toolkit.polecat|gc-toolkit__polecat-lx-old|in_progress
s-stale|mol-polecat-work.load-context|root-STALE|gc-toolkit/gc-toolkit.polecat|gc-toolkit__polecat-lx-here|in_progress
s-nosess|mol-polecat-work.load-context|root-NOSESS|gc-toolkit/gc-toolkit.polecat|gc-toolkit__polecat-lx-anon|in_progress
s-reclaimrouted|mol-polecat-work.load-context|root-RECLAIMROUTED|gc-toolkit/gc-toolkit.polecat|gc-toolkit__polecat-lx-rrold|in_progress
s-heldsess|mol-polecat-work.load-context|root-HELDSESS|gc-toolkit/gc-toolkit.polecat|gc-toolkit__polecat-lx-hsmol|in_progress
S

# Roots: root_id|convoy_id|gc.session_name   (root-ORPHAN deliberately absent -> no
# convoy). The session is the one the molecule's steps are bound to by
# gc.session_affinity=require; the older fixtures leave it empty, which is also the
# shape of a molecule that was never claimed.
cat > "$TMP/roots" <<'R'
root-DONE|convoy-DONE|
root-LIVE|convoy-LIVE|gc-toolkit__polecat-lx-busy
root-CLOSED|convoy-CLOSED|
root-HANDOFF|convoy-HANDOFF|
root-QUIET|convoy-QUIET|
root-SCOPED|convoy-SCOPED|
root-NOREF|convoy-NOREF|
root-HELD|convoy-HELD|
root-BARE|convoy-BARE|
root-ROUTEONLY|convoy-ROUTEONLY|
root-RECLAIM|convoy-RECLAIM|gc-toolkit__polecat-lx-old
root-STALE|convoy-STALE|gc-toolkit__polecat-lx-here
root-NOSESS|convoy-NOSESS|gc-toolkit__polecat-lx-anon
root-RECLAIMROUTED|convoy-RECLAIMROUTED|gc-toolkit__polecat-lx-rrold
root-HELDSESS|convoy-HELDSESS|gc-toolkit__polecat-lx-hsmol
R

# Convoys: convoy_id|anchor_id
cat > "$TMP/convoys" <<'C'
convoy-DONE|anchor-DONE
convoy-LIVE|anchor-LIVE
convoy-CLOSED|anchor-CLOSED
convoy-HANDOFF|anchor-HANDOFF
convoy-QUIET|anchor-QUIET
convoy-SCOPED|anchor-SCOPED
convoy-NOREF|anchor-NOREF
convoy-HELD|anchor-HELD
convoy-BARE|anchor-BARE
convoy-ROUTEONLY|anchor-ROUTEONLY
convoy-RECLAIM|anchor-RECLAIM
convoy-STALE|anchor-STALE
convoy-NOSESS|anchor-NOSESS
convoy-RECLAIMROUTED|anchor-RECLAIMROUTED
convoy-HELDSESS|anchor-HELDSESS
C

# Anchors: anchor_id|status|merge_result|assignee|routed_to|gc.session_name
#
# anchor-LIVE and anchor-HANDOFF are the same shape except for WHO holds them
# (status=open, merge_result unstamped) — that is the whole discrimination the
# handoff predicate has to make, so the fixture pins both sides of it.
#
# anchor-HELD, anchor-BARE and anchor-ROUTEONLY do the same job for the park
# predicate (tk-rlm94): all three are unstamped and unassigned, and they differ
# only in the two fields the conjunction reads. HELD has both (blocked + human) and
# is terminal; each of the others has exactly one and must NOT be.
#
# anchor-LIVE, anchor-RECLAIM, anchor-STALE and anchor-NOSESS pin the four corners
# of the re-claim predicate. All four are held by a POLECAT with no merge_result, so
# none of them is separable by the older predicates:
#
#   LIVE    held by the molecule's OWN session          -> live, hands off
#   RECLAIM held by a DIFFERENT session, and records it  -> done
#   STALE   records a different session but is NOT held by it (assignee is an agent
#           name): the record is a leftover, not a current holder -> fail closed
#   NOSESS  held by a session name it does not record    -> fail closed
#
# The park and re-claim predicates are disjoint on this fixture and the two groups
# above are how that is held: no park row records a session, and no re-claim row is
# blocked or routed. anchor-RECLAIMHELD is the deliberate exception — see below.
cat > "$TMP/anchors" <<'A'
anchor-DONE|open|pull_request|||
anchor-LIVE|open||gc-toolkit__polecat-lx-busy||gc-toolkit__polecat-lx-busy
anchor-CLOSED|closed||||
anchor-HANDOFF|open||gc-toolkit/gc-toolkit.refinery||
anchor-QUIET|open|pre_open_gate|||
anchor-SCOPED|open|pre_open_gate|||
anchor-NOREF|open|pull_request|||
anchor-HELD|blocked|||human|
anchor-BARE|blocked||||
anchor-ROUTEONLY|open|||human|
anchor-RECLAIM|in_progress||gc-toolkit__polecat-lx-new||gc-toolkit__polecat-lx-new
anchor-STALE|in_progress||gc-toolkit/gc-toolkit.polecat||gc-toolkit__polecat-lx-ghost
anchor-NOSESS|in_progress||gc-toolkit__polecat-lx-other||
anchor-RECLAIMROUTED|in_progress||gc-toolkit__polecat-lx-rr|gc-toolkit/gc-toolkit.polecat|gc-toolkit__polecat-lx-rr
anchor-HELDSESS|blocked|||human|gc-toolkit__polecat-lx-hsanch
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
    rsess=$(awk -F'|' -v r="$id" '$1==r{print $3; exit}' "$FAKE_ROOTS")
    arow=$(awk -F'|' -v a="$id" '$1==a{print; exit}' "$FAKE_ANCHORS")
    if [ -n "$arow" ]; then
      st=$(printf '%s' "$arow" | cut -d'|' -f2); mr=$(printf '%s' "$arow" | cut -d'|' -f3)
      as=$(printf '%s' "$arow" | cut -d'|' -f4); rt=$(printf '%s' "$arow" | cut -d'|' -f5)
      an=$(printf '%s' "$arow" | cut -d'|' -f6)
      jq -n --arg s "$st" --arg m "$mr" --arg a "$as" --arg r "$rt" --arg n "$an" \
        '[{status:$s, assignee:$a,
           metadata:{merge_result:$m, "gc.routed_to":$r, "gc.session_name":$n}}]'
    elif [ -n "$convoy" ]; then
      jq -n --arg c "$convoy" --arg n "$rsess" \
        '[{metadata:{"gc.input_convoy_id":$c, "gc.session_name":$n}}]'
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
grep -q '(dry-run)' <<< "$OUT0" \
  && ok "(DRY) summary marks the pass as a dry run" || bad "(DRY) summary marks dry run (got: $OUT0)"
grep -q 's-affine' <<< "$OUT0" \
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
grep -q -- '--assignee' < <(grep '^gc bd update s-affine' "$TMP/updates") \
  && bad "(SPLIT) the route call must NOT also carry --assignee (that is the batched update that fails closed)" \
  || ok "(SPLIT) route call carries only --unset-metadata, never --assignee"
grep -q -- '--unset-metadata' < <(grep '^bd update s-affine' "$TMP/updates") \
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
grep -q -- '--force' < <(grep '^bd update s-affine' "$TMP/updates") \
  && ok "(FORCE) assignee clear passes --force past the claim guard" \
  || bad "(FORCE) assignee clear must pass --force (got: $(grep '^bd update s-affine' "$TMP/updates" || echo none))"
grep -qE '^gc bd update .*--force' "$TMP/updates" \
  && bad "(FORCE) --force must never be sent through gc bd — the wrapper rejects it and exits 1" \
  || ok "(FORCE) --force is never routed through the gc wrapper"

# (LIVE) a molecule whose anchor is still live is left completely alone. This is
# also the discrimination that keeps (HANDOFF) safe: anchor-LIVE has the SAME
# shape as anchor-HANDOFF (open, merge_result unstamped) and differs only in being
# assigned to a POLECAT. A loose "the anchor has an assignee" predicate would pass
# here and drain the polecat still working it.
grep -q '^s-live' "$TMP/cleared" \
  && bad "(LIVE) must NOT touch a live molecule's steps — a polecat-assigned anchor is not a refinery handoff" \
  || ok "(LIVE) live anchor assigned to a POLECAT -> steps untouched (not mistaken for a refinery handoff)"
grep -q 'anchor anchor-LIVE still live' <<< "$OUT1" \
  && ok "(LIVE) summary explains why the live root was skipped" || bad "(LIVE) live-skip reason"
grep -q 'anchor-LIVE still live.*assignee=gc-toolkit__polecat-lx-busy' <<< "$OUT1" \
  && ok "(LIVE) skip line records the assignee that was inspected" || bad "(LIVE) skip line records assignee"
# anchor-LIVE is held by the molecule's OWN session, which is what separates it from
# (RECLAIM) below — the two are otherwise the same shape (polecat-held, unstamped).
grep -q 'anchor-LIVE still live.*session=gc-toolkit__polecat-lx-busy molecule_session=gc-toolkit__polecat-lx-busy' <<< "$OUT1" \
  && ok "(LIVE) the anchor is held by this molecule's own session -> not a re-claim" \
  || bad "(LIVE) skip line records both sessions compared"

# (RECLAIM) the fifth re-offer shape (tk-nv3qr). The refinery REJECTED the branch,
# cleared the handoff and re-pooled the anchor; another polecat session claimed it
# and works it as a bare bead, never re-walking this molecule's step graph. The
# anchor is in_progress, unstamped and polecat-held, so none of the four older
# predicates fires — and these steps are bound to a session that can never advance
# them again.
grep -q '^s-reclaim	routed$' "$TMP/cleared" && grep -q '^s-reclaim	assignee$' "$TMP/cleared" \
  && ok "(RECLAIM) anchor re-claimed by ANOTHER session -> steps quiesced (both keys)" \
  || bad "(RECLAIM) re-claimed anchor must count as done (got: $(grep '^s-reclaim' "$TMP/cleared" || echo none))"
grep -q 'anchor anchor-RECLAIM DONE' <<< "$OUT1" \
  && ok "(RECLAIM) summary reports the re-claimed anchor as DONE" \
  || bad "(RECLAIM) summary reports the re-claimed anchor DONE"
grep -q 'anchor-RECLAIM DONE.*session=gc-toolkit__polecat-lx-new molecule_session=gc-toolkit__polecat-lx-old' <<< "$OUT1" \
  && ok "(RECLAIM) the verdict line names BOTH sessions it compared (the pass is hand-reversible)" \
  || bad "(RECLAIM) verdict line names both sessions"

# (STALE) fail closed on a session record that is not the CURRENT holder.
# gc.session_name is stamped at claim time and is not cleared on release, so a bare
# "recorded session != molecule session" test would fire on a leftover while the
# molecule's own polecat is still running — draining it mid-implementation. The
# assignee must EQUAL the recorded session before it may be believed.
grep -q '^s-stale' "$TMP/cleared" \
  && bad "(STALE) a stale gc.session_name is not a current holder — must NOT quiesce" \
  || ok "(STALE) recorded session that does not match the assignee -> left alone (fail closed)"
grep -q 'anchor anchor-STALE still live' <<< "$OUT1" \
  && ok "(STALE) summary reports the stale-record root as still live" || bad "(STALE) stale-record skip reason"

# (NOSESS) fail closed when there is nothing to compare: the anchor is held under a
# session name it never recorded, so the pass declines to guess.
grep -q '^s-nosess' "$TMP/cleared" \
  && bad "(NOSESS) an anchor with no recorded session must NOT be quiesced on a guess" \
  || ok "(NOSESS) anchor records no session -> left alone (fail closed)"

# (CLOSED) a closed anchor counts as done.
grep -q '^s-closed	routed$' "$TMP/cleared" && grep -q '^s-closed	assignee$' "$TMP/cleared" \
  && ok "(CLOSED) closed anchor -> steps quiesced (landed is strictly past pull_request)" \
  || bad "(CLOSED) closed anchor treated as done"

# (HANDOFF) the refinery-handoff window (tk-yxlqb): the polecat pushed and
# reassigned the anchor, but the refinery has not stamped merge_result yet. The
# status/merge_result predicates all miss this shape, so without the assignee
# predicate the husk keeps being re-offered for the whole window — ~17 min and two
# burned polecat sessions, observed on tk-2l13a.
grep -q '^s-handoff	routed$' "$TMP/cleared" && grep -q '^s-handoff	assignee$' "$TMP/cleared" \
  && ok "(HANDOFF) anchor handed to the refinery -> steps quiesced though merge_result is unstamped" \
  || bad "(HANDOFF) refinery-assigned anchor must count as done (got: $(grep '^s-handoff' "$TMP/cleared" || echo none))"
grep -q 'anchor anchor-HANDOFF DONE' <<< "$OUT1" \
  && ok "(HANDOFF) summary reports the handoff anchor as DONE" \
  || bad "(HANDOFF) summary reports the handoff anchor DONE"

# (HELD) the human-decision park (tk-rlm94): the refinery held the bead BEFORE
# dispatching a review, so merge_result was never stamped; parking to a human
# cleared the assignee. status/merge_result/assignee therefore all miss, and the
# husk kept minting a fresh full-context polecat per session restart for the whole
# human-decision wait — five re-offers of tk-vgxlu in ~40 minutes, observed live.
grep -q '^s-held	routed$' "$TMP/cleared" && grep -q '^s-held	assignee$' "$TMP/cleared" \
  && ok "(HELD) anchor parked for a human (blocked + routed_to=human) -> steps quiesced" \
  || bad "(HELD) parked anchor must count as done (got: $(grep '^s-held' "$TMP/cleared" || echo none))"
grep -q 'anchor anchor-HELD DONE' <<< "$OUT1" \
  && ok "(HELD) summary reports the parked anchor as DONE" \
  || bad "(HELD) summary reports the parked anchor DONE"
grep -q 'anchor-HELD DONE.*routed_to=human' <<< "$OUT1" \
  && ok "(HELD) the verdict line records the route it was decided on" \
  || bad "(HELD) verdict line records routed_to"

# (BARE) bare `blocked` is NOT terminal. The escalation path sets blocked before it
# drains, so a LIVE session is reachable in that state; relaxing the predicate to
# bare `blocked` would strip the assignee off steps that polecat still has to claim
# and drain it mid-implementation.
grep -q '^s-bare' "$TMP/cleared" \
  && bad "(BARE) bare blocked must NOT be treated as terminal — a live escalating session passes through it" \
  || ok "(BARE) blocked with no route -> steps untouched (the conjunction is what keeps this fail-closed)"
grep -q 'anchor anchor-BARE still live' <<< "$OUT1" \
  && ok "(BARE) summary reports the bare-blocked anchor as still live" \
  || bad "(BARE) bare-blocked anchor reported still live"

# (ROUTEONLY) the other half alone is not terminal either: routed_to=human on an
# `open` anchor is a bead handed to a human while its work may still be live.
grep -q '^s-routeonly' "$TMP/cleared" \
  && bad "(ROUTEONLY) routed_to=human alone must NOT be treated as terminal" \
  || ok "(ROUTEONLY) open + routed_to=human -> steps untouched (both halves are required)"
grep -q 'anchor anchor-ROUTEONLY still live' <<< "$OUT1" \
  && ok "(ROUTEONLY) summary reports the route-only anchor as still live" \
  || bad "(ROUTEONLY) route-only anchor reported still live"

# (CROSS) The INTERSECTION of the park predicate (tk-rlm94) and the re-claim
# predicate (tk-nv3qr). The two were written in parallel against this same
# function and BOTH claimed $4 — park for gc.routed_to, re-claim for the session
# pair — so each branch could only ever test its own clause with the other's field
# absent, and the positional collision was resolved by hand when the second landed.
# Nothing above pins that resolution: every fixture so far populates exactly one of
# the two fields, so crossing the arguments still satisfies all of them. These two
# populate BOTH, and each must still be decided by its OWN clause.
#
# (CROSS-RECLAIM) a re-claimed anchor that also carries a live pool route — the
# shape a re-pooled anchor really has, since the refinery re-routes to the pool on
# rejection. The route is not `human`, so the park clause must not fire on it, and
# the route must not be read where the session is expected: cross $4/$5 and the
# re-claim conjunction compares the assignee against `gc-toolkit/gc-toolkit.polecat`
# instead of the recorded session, fails, and this husk is left armed.
grep -q '^s-reclaimrouted	routed$' "$TMP/cleared" && grep -q '^s-reclaimrouted	assignee$' "$TMP/cleared" \
  && ok "(CROSS-RECLAIM) re-claimed anchor + non-human pool route -> quiesced by the re-claim clause" \
  || bad "(CROSS-RECLAIM) a live pool route must not shadow the session pair (got: $(grep '^s-reclaimrouted' "$TMP/cleared" || echo none))"
grep -q 'anchor-RECLAIMROUTED DONE.*routed_to=gc-toolkit/gc-toolkit.polecat.*session=' <<< "$OUT1" \
  && ok "(CROSS-RECLAIM) the verdict line carries BOTH fields, in their own slots" \
  || bad "(CROSS-RECLAIM) verdict names route and session separately (got: $(printf '%s\n' "$OUT1" | grep RECLAIMROUTED || echo none))"

# (CROSS-HELD) the mirror: a parked anchor that also RECORDS a session. The park
# clause must still decide it. The re-claim clause has to stay out of the way on its
# own terms — the assignee is empty (parking clears it), so its first conjunct fails
# — and the recorded session must not be read where the route is expected.
grep -q '^s-heldsess	routed$' "$TMP/cleared" && grep -q '^s-heldsess	assignee$' "$TMP/cleared" \
  && ok "(CROSS-HELD) parked anchor that also records a session -> quiesced by the park clause" \
  || bad "(CROSS-HELD) a recorded session must not shadow routed_to (got: $(grep '^s-heldsess' "$TMP/cleared" || echo none))"
grep -q 'anchor-HELDSESS DONE.*routed_to=human.*session=gc-toolkit__polecat-lx-hsanch' <<< "$OUT1" \
  && ok "(CROSS-HELD) the verdict line carries BOTH fields, in their own slots" \
  || bad "(CROSS-HELD) verdict names route and session separately (got: $(printf '%s\n' "$OUT1" | grep HELDSESS || echo none))"

# (FINAL) the finalize step keeps its control-dispatcher route.
grep -q '^s-final' "$TMP/cleared" \
  && bad "(FINAL) must NOT de-route workflow-finalize — it is the escape path" \
  || ok "(FINAL) workflow-finalize keeps its control-dispatcher route"

# (CONTRACT) the row filter selects by CONTRACT, not by formula name (tk-q5r65).
# mol-scoped-work is the same graph.v2 shape — materialized steps, chained so
# load-context is the only ready one, executed inline, never closed — but the old
# startswith("mol-polecat-work.") filter dropped it at the row select, BEFORE any
# anchor verdict. Its husks therefore appeared in neither list of the summary and
# re-offered forever: observed on root tk-917ov, 28 live steps burning ~1 fresh
# full-context polecat per session restart while --dry-run reported it nowhere.
grep -q '^s-scoped	routed$' "$TMP/cleared" && grep -q '^s-scoped	assignee$' "$TMP/cleared" \
  && ok "(CONTRACT) a non-mol-polecat-work graph.v2 husk is quiesced too (selected by contract, not by name)" \
  || bad "(CONTRACT) mol-scoped-work step must be quiesced (got: $(grep '^s-scoped' "$TMP/cleared" || echo none))"
grep -q 'anchor anchor-SCOPED DONE' <<< "$OUT1" \
  && ok "(CONTRACT) the mol-scoped-work root reaches an anchor verdict at all (it used to be dropped before one)" \
  || bad "(CONTRACT) mol-scoped-work root must reach the anchor verdict"

# (CONTRACT) and the finalize guard is formula-agnostic — it matches the step
# SUFFIX and the route, so widening the filter must not start de-routing another
# formula's only escape path.
grep -q '^s-scopedfin' "$TMP/cleared" \
  && bad "(CONTRACT) must NOT de-route mol-scoped-work's workflow-finalize step" \
  || ok "(CONTRACT) workflow-finalize keeps its route under any formula, not just mol-polecat-work"

# (NOTV2) a bead with NO gc.step_ref is not a graph.v2 step and is never a
# candidate — even though root-NOREF's anchor is DONE, so the membership test is
# the ONLY thing holding it back. This is what makes widening the filter a wider
# net over graph.v2 steps rather than a blanket sweep of every open bead.
grep -q '^s-noref' "$TMP/cleared" \
  && bad "(NOTV2) a bead without gc.step_ref must never be quiesced, terminal anchor or not" \
  || ok "(NOTV2) no gc.step_ref -> not a graph.v2 step -> never a candidate (its anchor is DONE regardless)"

# (NOROOT) a step_ref with no gc.root_bead_id can never be matched to an anchor,
# so it is never touched. Note this holds via the ROOTS reduction even without
# the row filter's explicit root select — the select is belt-and-braces, and this
# assertion pins the OUTCOME so any future rework of either reduction keeps it.
grep -q '^s-noroot' "$TMP/cleared" \
  && bad "(NOROOT) a step with no root bead can never be anchor-verified and must not be touched" \
  || ok "(NOROOT) step_ref without gc.root_bead_id -> excluded (no anchor could ever gate it)"

# (FAILSAFE) unresolvable anchor -> skipped, not quiesced.
grep -q '^s-orphan' "$TMP/cleared" \
  && bad "(FAILSAFE) must NOT quiesce a root whose anchor cannot be resolved" \
  || ok "(FAILSAFE) unresolved anchor -> skipped (fail closed)"
# The warning is a diagnostic, so it goes to stderr (matching the other passes);
# capture both streams to assert on it.
grep -q 'anchor unresolved' <<< "$ERR1" \
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

grep -q '9 steps quiesced across 9 completed workflow(s); 5 still live, 1 already quiet, 1 unresolved, 0 failed' <<< "$OUT1" \
  && ok "run 1 summary counts are exact" || bad "run 1 summary (got: $(printf '%s' "$OUT1" | tail -1))"
eq "$RC1" "0" "(EXIT) a clean pass exits 0"

# --- Run 2: convergence — a swept molecule stays swept. -----------------------
: > "$TMP/cleared"; : > "$TMP/updates"
RC2=0
OUT2="$(bash "$SCRIPT")" || RC2=$?
eq "$(wc -l < "$TMP/updates" | tr -d ' ')" "0" \
  "(IDEM) second pass issues no updates — quiesced steps stay quiesced"
grep -q '0 steps quiesced' <<< "$OUT2" \
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
grep -q 's-affine assignee clear failed' <<< "$ERR3" \
  && ok "(GUARD) the refused half is reported on stderr, naming the key" \
  || bad "(GUARD) refusal reported on stderr (got: $ERR3)"
grep -q 's-affine route clear failed' <<< "$ERR3" \
  && bad "(GUARD) the route half succeeded and must not be reported as failed" \
  || ok "(GUARD) the successful route half is not reported as a failure"

# A partial clear is a failure, never a success: the step still rides the affine
# hand-back, so counting it quiesced would be the same lie in a new place.
grep -q '8 steps quiesced across 9 completed workflow(s); 5 still live, 1 already quiet, 1 unresolved, 1 failed' <<< "$OUT3" \
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

grep -q 's-affine route clear failed' <<< "$ERR4" \
  && ok "(ROUTEFAIL) the failed route half is reported on stderr, naming the key" \
  || bad "(ROUTEFAIL) route failure reported on stderr (got: $ERR4)"
grep -q 's-affine assignee clear skipped' <<< "$ERR4" \
  && ok "(ROUTEFAIL) the skipped assignee half is reported, and says why" \
  || bad "(ROUTEFAIL) skip reason reported on stderr (got: $ERR4)"
grep -q 's-affine assignee clear failed' <<< "$ERR4" \
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

grep -q '7 steps quiesced across 9 completed workflow(s); 5 still live, 1 already quiet, 1 unresolved, 2 failed' <<< "$OUT4" \
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
