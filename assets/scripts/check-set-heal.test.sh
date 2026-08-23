#!/usr/bin/env bash
# Hermetic test for check-set-heal.sh (the refinery-boundary check-set
# normalization, tk-i48ca). Stubs `gc` (bead-ledger list/show/update/dep/create/
# session) on PATH. No live city, Dolt, network, or real pull requests.
#
# THE BUG. A hand-RECOVERED anchor never ran the merge-push step, so its check_set
# was never normalized: it reaches the refinery empty, merge-skill.sh reads empty
# as "no gates", and the PR merges with NO codex review. This pass runs BEFORE the
# merge skill and stamps the declared default on any gating anchor whose check_set
# is absent/empty, then dispatches the missing signoff so the armed gate is
# satisfiable. Only the explicit `none`/`off` sentinel is a real opt-out.
#
# Covered:
#   (EMPTY)  merge_result=pull_request, check_set="" -> stamp default + dispatch
#            signoff + BLOCKS edge + route to the codex pool.
#   (ABSENT) check_set key absent entirely -> same heal (absent == empty).
#   (SEP)    check_set=",,," names no gates -> healed (not a real gate list).
#   (NONE)   check_set="none" (the opt-out sentinel) -> LEFT ALONE, no dispatch.
#   (OFF)    check_set="off" -> LEFT ALONE.
#   (NORMAL) check_set="codex" -> LEFT ALONE (already normalized).
#   (GREEN)  empty check_set BUT check.codex already green -> stamp, NO dispatch
#            (the gate is already satisfiable).
#   (INFLGT) empty check_set BUT an open review already references the anchor ->
#            stamp, NO dispatch (reuse the in-flight review, never a twin).
#   The WS4 verdict vocabulary on check.codex — `marker_blocks_dispatch` is TOTAL,
#   and each answer holds a different door shut:
#   (EXCEPT) exception@<sha> -> stamp, NO dispatch (terminal until an operator acts).
#   (FIXABLE) fixable@<sha> -> DISPATCH. The one non-green verb that falls through;
#            the in-flight probe, not the marker, is what prevents a twin.
#   (WEIRD)  weird@<sha> names no verb -> NO dispatch. R12 unmappable belongs to
#            reconcile-gate-verdicts.sh, which runs LATER in the same patrol wake;
#            dispatching first queues a review that can later stamp green over the
#            exception and lift a terminal hold by automation (review tk-i688b).
#   (NOVERB) a bare "green" with no @oid is unmappable too, and skipped the same.
#   (INFLIGHT-CONV/HANDBACK-CONV) the CONVOY-FIRST dispatch form, tk-79zn6: a rework
#            child whose live route is gc.execution_routed_to (gc.routed_to having been
#            retired at pour) is IN FLIGHT and suppresses the re-gate; the same child
#            after its hand-back — same route key, refinery assignee — is NOT, and the
#            re-gate is dispatched. The assignee is the whole discriminator, because
#            nothing retires the execution route on the way back.
#   (PREOPEN) a pre_open_gate anchor (no PR) with empty check_set -> stamp +
#            dispatch a BRANCH review (review_branch/review_base, no pr_number).
#   (ORDER)  the stamp is applied BEFORE the dispatch (fail-closed): the PR cannot
#            be left ungated-but-dispatched.
#   (STAMPFAIL) a stamp that does NOT persist is NOT counted healed and does NOT
#            dispatch — the anchor stays ungated and is retried, flagged once, and
#            the pass EXITS UNSAFE_RC (3) so the formula holds merge-skill.
#   (HEALPARTIAL) the HALF-landed stamp: check_set persists, check_set_healed is
#            dropped. Not counted healed, warned, flagged — but the signoff IS
#            dispatched in the SAME pass, and the pass does NOT exit UNSAFE_RC
#            (the gate is armed, so this anchor's merge is already held and the
#            others must not be held with it).
#   (HEALDEFER) the state that deferral would leave — check_set normalized,
#            check_set_healed absent — reads as "already normalized" and is never
#            re-dispatched. This is WHY (HEALPARTIAL) dispatches in-pass.
#   (HEALPARTIAL+ROUTE) the compound case from review tk-nwi06 finding #1: the mark
#            drops AND the route write fails. The unclaimable review is closed and
#            the operator is given the by-hand repair for the mark.
#   (NOMARK) review tk-y5r1e finding #2: check_set_healed drops AND the fallback
#            check_set_heal_flagged write also drops. The flag is READ BACK and
#            repaired once; when neither mark is durable the pass says so and stops
#            promising a next pass — and still dispatches in-pass, which is now the
#            only pass this anchor will ever get. (NOMARK+ROUTE) is that compounded
#            with a failed route write.
#   (ROUTE-DURABLE-CLAIMED) review tk-y5r1e finding #1: review_pool is persistently
#            dropped while a codex polecat HOLDS the review. route_ok rejects the
#            triple on the durable half before the assignee exception applies, and
#            the failure path used to force-close an in-flight review — erasing the
#            only signoff for an armed gate. Claimed is left OPEN and uncounted.
#   (CONV)   a healed anchor (check_set_healed recorded, gate now satisfiable via
#            the dispatched review) is not re-stamped and not re-dispatched.
#   (RETRY)  a healed anchor whose dispatch FAILED last pass (healed recorded, gate
#            still unsatisfiable, nothing in flight) re-dispatches — the stamp did
#            not hide it from the satisfiability retry.
#   (LIVEOWN) a branch owned by a blocked / deferred / hooked / pinned child ->
#            NO dispatch (only `closed` releases a branch); an OPEN unrouted
#            non-review child is still inert -> DISPATCH.
#   (NOTE)   each re-gate's review_note is non-empty and carries THAT dispatch's
#            reason, and the same reason reaches the review BODY.
#   (MALFORMED) a non-empty marker that is not green@<hex oid> — `green`, `red`,
#            `green@`, `green@<junk>` — can never equal green@<live head>, so it
#            re-gates in BOTH sub-states and needs no head read; a well-formed
#            marker at the live head is untouched.
#   (DEADREV) a review that cannot raise THIS anchor's gate does not suppress the
#            re-gate: one whose anchor_bead write was lost (unrouted, unclaimed,
#            unattributable) and one that names ANOTHER anchor. A review naming
#            this anchor still suppresses it — no twins.
#   (PINNED) the live-head read carries BOTH halves of the origin pin — the `o/r`
#            path and the `--hostname` host — asserted on the argv gh was called
#            with, so a host word that expands to nothing fails by name.
#   (TERMINAL) a post-open anchor whose PR is MERGED or CLOSED is NOT re-gated
#            (that is reconcile-merged-prs.sh's to dispose of); an OPEN one still
#            is, an UNREADABLE state dispatches anyway (fail soft), and a pre-open
#            anchor is untouched by the guard and costs no PR read.
#   (ROUTEFAIL/REPAIR) a dropped gc.routed_to write is not counted as dispatched
#            and leaves the bead unrouted; the next pass re-routes the SAME bead.
#   (GATE)   the REAL cadence wiring (heal-gates-merge, extracted from
#            assets/scripts/refinery-reconcile.sh, the merge-cadence order's pass
#            runner): a stamp-failing heal (rc=UNSAFE_RC) HOLDS the merge-skill
#            stub (no merge attempted); a clean heal lets it run. This is the
#            review tk-z4u2e finding #1 regression — a failed stamp used to fall
#            through to merge-skill in the SAME pass and merge un-reviewed. The
#            snippet moved out of mol-refinery-patrol.toml with the cadence
#            itself (tk-d83wm); the guarantee and this test are unchanged.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/check-set-heal.sh"
# The merge cadence's pass runner — the caller the heal gates (run 6). It used
# to be formulas/mol-refinery-patrol.toml; the gating snippet moved out with the
# cadence itself (tk-d83wm).
RUNNER="$HERE/refinery-reconcile.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }
has() { grep -q "$1" "$2" 2>/dev/null; }
# Assert that PATTERN (a BRE, same as `has`) appears in a CAPTURED STRING.
#
# NOT `printf '%s\n' "$OUT" | grep -q PATTERN`. This file runs under `set -euo
# pipefail`, and `grep -q` exits at its FIRST match — closing the pipe under a
# `printf` still writing the rest of a large captured output. printf takes
# SIGPIPE, the pipeline reports 141, and the assertion reads FALSE even though
# the line IS present. Whether it fires depends on where the match sits relative
# to the ~64KB pipe buffer, so a suite carrying it fails on output SIZE rather
# than on behavior — a phantom red against correct code, which is exactly how
# merge-skill.test.sh went red at 204/1 while the code under test was fine.
#
# A here-string is a REDIRECT, not a pipeline: bash hands grep a file it reads to
# EOF, no upstream writer exists to be signalled, and the exit status is grep's
# alone. Match semantics are unchanged from the pipelines this replaced. Same
# reasoning as merge-skill.test.sh's.
#
# `-e` (as in reconcile-merged-prs.test.sh's copy) so a pattern that BEGINS with
# a dash is still a pattern: the gh-invocation assertions below match on literal
# flags (`--hostname github.com`, `--repo ...`), which bare `grep -q "$2"` would
# parse as grep's own options and die on. Without it those two call sites cannot
# use this helper at all, and the pipeline they would keep instead is the very
# defect the helper exists to remove.
hasin() { grep -q -e "$2" <<< "$1"; }

mkdir -p "$TMP/bin"

# Gating anchors, one per line, across BOTH sub-states:
#   id|merge_result|check_set(literal, __ABSENT__ omits the key)|pr|branch|target|check.codex|check_set_healed
# check_set column values: EMPTY (a literal empty field), __ABSENT__ (omit the
# metadata key), or a real value. The stub reads the raw file each `gc bd list` so
# an `update` that rewrites check_set is reflected on the next pass (convergence).
cat > "$TMP/anchors" <<'A'
bead-EMPTY|pull_request|EMPTY|401|polecat/feat-empty|main||
bead-ABSENT|pull_request|__ABSENT__|402|polecat/feat-absent|main||
bead-SEP|pull_request|,,,|403|polecat/feat-sep|main||
bead-NONE|pull_request|none|404|polecat/feat-none|main||
bead-OFF|pull_request|off|405|polecat/feat-off|main||
bead-NORMAL|pull_request|codex|406|polecat/feat-normal|main|green@406406a|
bead-GREEN|pull_request|EMPTY|407|polecat/feat-green|main|green@407407a|
bead-INFLGT|pull_request|EMPTY|408|polecat/feat-inflgt|main||
bead-PREOPEN|pre_open_gate|EMPTY||polecat/feat-preopen|main||
bead-EXCEPT|pull_request|EMPTY|409|polecat/feat-except|main|exception@HEAD409|
bead-FIXABLE|pull_request|EMPTY|410|polecat/feat-fixable|main|fixable@HEAD410|
bead-WEIRD|pull_request|EMPTY|411|polecat/feat-weird|main|weird@HEAD411|
bead-NOVERB|pull_request|EMPTY|412|polecat/feat-noverb|main|green|
bead-CAPPED|pull_request|EMPTY|413|polecat/feat-capped|main||
A

# An open review already referencing bead-INFLGT (so the heal must NOT dispatch a
# twin). Format: review_id|anchor_bead|pr_number[|status|assignee]. The inflight
# lookup finds it via the pr_number and anchor_bead branches of inflight_for.
#
# anchor_bead is a real COLUMN, emitted only when non-empty, because whether a
# review names THIS anchor is what decides the identity half of the dedup: one that
# names another anchor is somebody else's, and one naming none (a lost write) is
# unroutable and unclaimable — neither may hold this gate (review tk-s8zx3 finding
# #3). A stub that stamped anchor_bead unconditionally could not express either.
cat > "$TMP/reviews" <<'R'
rev-inflgt|bead-INFLGT|408
R

# --- gc stub. ----------------------------------------------------------------
# bd list  : gating-anchor scans (merge_result=pull_request|pre_open_gate) built
#            from the anchors file (skipping any recorded as stamped in
#            $FAKE_STAMPED so a rewritten check_set is honoured next pass); the
#            in-flight lookups (pr_number=, anchor_bead=, branch=) from reviews;
#            the review-dedup lookups.
# bd show  : re-read check_set (from $FAKE_STAMPED overlay) + anchor_bead on a
#            review (from $FAKE_REVMETA).
# bd create: mint a review id, echo {"id":...}.
# bd update: record check_set stamps, routing, and review metadata.
# bd dep / session : record edges / no-op.
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
[ "$1" = "bd" ] || { [ "$1" = "session" ] && exit 0; exit 0; }

# Current check_set for an anchor: the stamped overlay wins, else the anchors file
# (EMPTY/__ABSENT__ -> emitted as an empty metadata value; absent still absent).
cs_for() {
  local id="$1" v
  v=$(awk -F'\t' -v i="$id" '$1==i{print $2; found=1} END{if(!found)print "\x01"}' "$FAKE_STAMPED" 2>/dev/null)
  if [ "$v" != $'\x01' ]; then printf '%s' "$v"; return; fi
  awk -F'|' -v i="$id" '$1==i{print $3; exit}' "$FAKE_ANCHORS"
}
healed_for() {
  # LAST write wins, like the route reads below: the script may re-stamp this field
  # after a partial write, and the read-back must see the repair, not the first try.
  awk -F'\t' -v i="$1" '$1==i{v=$2} END{print v}' "$FAKE_HEALED" 2>/dev/null
}

# One review row (id|anchor_bead|pr_number[|status|assignee]) -> the bead-shaped
# JSON array `gc bd list` returns, or `[]` for no match. Only NON-EMPTY identity
# fields are emitted, so a fixture can model a review whose anchor_bead write was
# lost (column blank) as distinct from one that names another anchor.
emit_review() {
  [ -n "${1:-}" ] || { printf '[]\n'; return; }
  printf '%s' "$1" | jq -R -c 'split("|")
    | {id: .[0], status: (if (.[3] // "") == "" then "open" else .[3] end),
       assignee: (.[4] // ""),
       metadata: ({task_kind: "review"}
                  + (if (.[1] // "") == "" then {} else {anchor_bead: .[1]} end)
                  + (if (.[2] // "") == "" then {} else {pr_number: .[2]} end))}
    | [.]'
}

case "$2" in
  list)
    case "$*" in
      *"merge_result=pull_request"*|*"merge_result=pre_open_gate"*)
        want=$(printf '%s' "$*" | sed -n 's/.*merge_result=\([a-z_]*\).*/\1/p')
        out=""
        while IFS='|' read -r id mr cs pr branch target codex healed hold; do
          [ -n "$id" ] || continue
          [ "$mr" = "$want" ] || continue
          # Live check_set: stamped overlay wins.
          live=$(cs_for "$id")
          # Emit the metadata object. An __ABSENT__ (and no stamp) omits check_set.
          csfield=""
          if [ "$live" != "__ABSENT__" ]; then
            [ "$live" = "EMPTY" ] && live=""
            csfield=$(printf ',"check_set":"%s"' "$live")
          fi
          # Live check_set_healed overlay.
          h=$(healed_for "$id"); [ -n "$h" ] || h="$healed"
          hfield=""; [ -n "$h" ] && hfield=$(printf ',"check_set_healed":"%s"' "$h")
          # check_set_heal_flagged is STATEFUL too: it is the second mark that keeps
          # a partially-healed anchor flowing through the satisfiability retry, so a
          # pass has to see what an earlier pass flagged.
          flfield=""
          grep -qx "$id" "$FAKE_FLAGGED" 2>/dev/null \
            && flfield=',"check_set_heal_flagged":"1"'
          cxfield=""; [ -n "$codex" ] && cxfield=$(printf ',"check.codex":"%s"' "$codex")
          # The pr_url is the one the git stub's origin implies — `github.com/o/r` —
          # not a placeholder host. certify_pr_identity compares the bead's recorded
          # URL against the live one and REFUSES on a mismatch, and it now sits on the
          # dispatch path (the terminal-PR guard, review tk-w9ttd finding #2). A
          # fixture whose pr_url could never match would make every certification fail
          # for the wrong reason, so the fail-soft arm would be the only one any test
          # ever reached.
          prfield=""; [ -n "$pr" ] && prfield=$(printf ',"pr_number":"%s","pr_url":"https://github.com/o/r/pull/%s"' "$pr" "$pr")
          hdfield=""; [ -n "$hold" ] && hdfield=$(printf ',"merge_hold":"%s"' "$hold")
          # flfield (check_set_heal_flagged) is main's THIRD retry mark; hdfield
          # (merge_hold) is the branch's operator gate. Both ride the anchor row now.
          obj=$(printf '{"id":"%s","title":"impl %s","metadata":{"merge_result":"%s","branch":"%s","merged_target":"%s"%s%s%s%s%s%s}}' \
            "$id" "$id" "$mr" "$branch" "$target" "$csfield" "$cxfield" "$hfield" "$flfield" "$prfield" "$hdfield")
          if [ -z "$out" ]; then out="$obj"; else out="$out,$obj"; fi
        done < "$FAKE_ANCHORS"
        printf '[%s]\n' "$out" ;;
      # The in-flight probes. These emit REALISTIC bead rows — id + status +
      # metadata — not a bare {"id":...}: inflight_for now decides whether a
      # candidate will actually ACT on the gate (task_kind=review, or
      # in_progress, or pool-routed), so a row without those fields no longer
      # resembles the bead it stands for (tk-t46nq). Everything reachable through
      # the pr_number / anchor_bead probes IS a signoff review, so both emit
      # task_kind=review.
      *"pr_number="*)
        pnum=$(printf '%s' "$*" | sed -n 's/.*pr_number=\([0-9][0-9]*\).*/\1/p')
        row=$(awk -F'|' -v p="$pnum" '$3==p{print; exit}' "$FAKE_REVIEWS" 2>/dev/null)
        emit_review "$row" ;;
      *"anchor_bead="*)
        aid=$(printf '%s' "$*" | sed -n 's/.*anchor_bead=\([^ ]*\).*/\1/p')
        row=$(awk -F'|' -v a="$aid" '$2==a{print; exit}' "$FAKE_REVIEWS" 2>/dev/null)
        # Also honour a review minted THIS run (recorded in FAKE_REVMETA): it is a
        # review, it names this anchor, and it is unrouted until the route write
        # lands — exactly what the repair arm looks for on the next pass.
        if [ -z "$row" ]; then
          rid=$(awk -F'\t' -v a="$aid" '$2=="anchor_bead" && $3==a{print $1; exit}' "$FAKE_REVMETA" 2>/dev/null)
          [ -n "$rid" ] && row="$rid|$aid||open|"
        fi
        emit_review "$row" ;;
      # Branch-keyed probe: the rework children (and any sibling bead) that live on
      # an anchor's branch. Backed by $FAKE_BRANCHBEADS so a fixture can express
      # the exact discriminator this bug turns on — a rework still being WORKED vs
      # one already handed BACK.
      #   id|branch|status|task_kind|gc.routed_to|assignee|gc.execution_routed_to
      #
      # gc.execution_routed_to IS ALSO A REAL COLUMN, and it is filled on the handed-BACK
      # rows too (tk-79zn6). The convoy-first dispatch that mints rework children now
      # retires gc.routed_to and stamps the live route there instead — but NOTHING retires
      # it on the way back, so the field is set on a live child and on a finished one
      # alike, and only the assignee tells them apart. A fixture that carried it on the
      # live rows alone would let the obvious fix — read gc.execution_routed_to, ignore the
      # assignee — pass this suite while re-parking every pre-open re-gate in production,
      # which is the tk-t46nq bug arriving through a new door. Filled on both sides, that
      # fix fails (HANDBACK-CONV) here.
      #
      # ASSIGNEE IS A REAL COLUMN, and the handed-back fixtures fill it with the
      # refinery identity the refinery actually leaves there (review tk-w9ttd testing
      # gap). A hand-back is OPEN, unrouted and ASSIGNED BACK — three facts, of which
      # only the first two were modelled, so the row stood for a bead that does not
      # exist. That mattered in one direction: with the column blank, a change that
      # started treating a non-empty assignee as LIVENESS would suppress every re-gate
      # in production while this suite stayed green — the tk-t46nq park, re-introduced
      # invisibly. With the real value present, that change fails (HANDBACK) here.
      #
      # `acting()` now does read the assignee, but only in the direction this column was
      # put here to protect (tk-79zn6): a non-empty one DISQUALIFIES the execution-route
      # disjunct below, and can never on its own make a bead count as in flight. The
      # failure the paragraph above describes therefore stays impossible — an assignee
      # can only add a dispatch here, never suppress one.
      #
      # The --status list the caller asked for is HONOURED here, exactly as the real
      # `bd list` honours it. That is what makes the live-owner fixtures a real
      # regression: a probe that asks only for open,in_progress cannot see a
      # blocked/deferred/hooked/pinned branch owner at all, so the pass would
      # dispatch a review against a branch someone else still owns. A stub that
      # returned every row regardless of status would let the un-widened query pass.
      *"branch="*)
        br=$(printf '%s' "$*" | sed -n 's/.*branch=\([^ ]*\).*/\1/p')
        want_st=$(printf '%s' "$*" | sed -n 's/.*--status=\([^ ]*\).*/\1/p')
        out=""
        while IFS='|' read -r bid bbr bst btk brt basg bero; do
          [ -n "$bid" ] || continue
          [ "$bbr" = "$br" ] || continue
          if [ -n "$want_st" ]; then
            case ",$want_st," in *",$bst,"*) ;; *) continue ;; esac
          fi
          tkf=""; [ -n "$btk" ] && tkf=$(printf ',"task_kind":"%s"' "$btk")
          obj=$(printf '{"id":"%s","status":"%s","assignee":"%s","metadata":{"branch":"%s","gc.routed_to":"%s","gc.execution_routed_to":"%s"%s}}' \
            "$bid" "$bst" "${basg:-}" "$bbr" "$brt" "${bero:-}" "$tkf")
          if [ -z "$out" ]; then out="$obj"; else out="$out,$obj"; fi
        done < "$FAKE_BRANCHBEADS"
        printf '[%s]\n' "$out" ;;
      *) printf '[]\n' ;;
    esac ;;
  show)
    id="$3"
    # A bead whose `gc bd show` answers NOTHING — the unreadable read, as distinct
    # from a bead that reads cleanly and says something bad. The route read-back and
    # the REUSE validation both have to tell those apart: unreadable is not proof of
    # a broken route, and acting on it (closing the bead, re-routing it, or counting
    # it as sufficient) is how a live signoff gets erased or duplicated (main tk-tbacg).
    case " ${FAKE_REVSHOWFAIL:-} " in *" $id "*) exit 0 ;; esac
    cs=$(cs_for "$id"); case "$cs" in EMPTY|__ABSENT__) cs="" ;; esac
    # A REALISTIC row: id + status + assignee + metadata. `repair_review_routing`
    # re-routes only a review that is still OPEN, unclaimed and unrouted, and it reads
    # all three through `bd show` — a row carrying metadata alone would leave status=""
    # (never "open"), so every repair would refuse and the arm would be untestable.
    # Defaults are open/unclaimed; $FAKE_REVSTATE (id<TAB>status<TAB>assignee) overrides,
    # which is how the claimed-review guard is exercised (branch).
    st=$(awk -F'\t' -v i="$id" '$1==i{print $2; exit}' "$FAKE_REVSTATE" 2>/dev/null)
    [ -n "$st" ] || st="open"
    # check_set_healed / check_set_heal_flagged as the STAMP READ-BACK sees them.
    # Modelled from their DEDICATED fixtures (FAKE_HEALED via healed_for, else
    # FAKE_ANCHORS col 8; FAKE_FLAGGED) rather than FAKE_REVMETA, because the two persist
    # independently of the other keys and of each other — the half-landed write (gate
    # armed, retry mark lost) has to be representable here (main tk-nwi06 / tk-y5r1e).
    hl=$(healed_for "$id")
    [ -n "$hl" ] || hl=$(awk -F'|' -v i="$id" '$1==i{print $8; exit}' "$FAKE_ANCHORS" 2>/dev/null)
    fl=""
    grep -qx "$id" "$FAKE_FLAGGED" 2>/dev/null && fl="1"
    # gc.routed_to as recorded, so a mid-run claim ($FAKE_CLAIMED) can CONSUME it into
    # assignee: a claim eats gc.routed_to and an assignee appears. The read-back must read
    # that as reachable, not a lost route — re-routing a claimed review offers it to a
    # second pool.
    rt=$(awk -F'\t' -v i="$id" '$1==i && $2=="gc.routed_to"{v=$3} END{print v}' "$FAKE_REVMETA" 2>/dev/null)
    claimed=0; [ -n "${FAKE_CLAIMED:-}" ] && [ -n "$rt" ] && claimed=1
    as=""; [ "$claimed" = 1 ] && as="$rt"
    # A review that arrived at this pass ALREADY claimed (staged directly in FAKE_REVMETA
    # rather than mid-run), then $FAKE_REVSTATE's assignee column ($3).
    [ -n "$as" ] || as=$(awk -F'\t' -v i="$id" '$1==i && $2=="assignee"{v=$3} END{print v}' "$FAKE_REVMETA" 2>/dev/null)
    [ -n "$as" ] || as=$(awk -F'\t' -v i="$id" '$1==i{print $3; exit}' "$FAKE_REVSTATE" 2>/dev/null)
    # EVERY OTHER metadata key recorded this run (last write wins) — merge_result,
    # reopened_not_landed, review_pool, gc.routed_to, anchor_bead, and anything else the
    # script wrote — then overlay the dedicated markers and drop gc.routed_to if a claim
    # consumed it. This is the branch's generic read-back, so route_review's read-back and
    # the repair arm's unrouted-review test are not tautologies.
    awk -F'\t' -v i="$id" '$1==i{v[$2]=$3} END{for (k in v) printf "%s\t%s\n", k, v[k]}' \
      "$FAKE_REVMETA" 2>/dev/null \
      | jq -R -s --arg cs "$cs" --arg hl "$hl" --arg fl "$fl" --arg as "$as" --arg st "$st" \
                 --arg id "$id" --arg claimed "$claimed" '
          ([ split("\n")[] | select(length > 0) | split("\t")
            | {key: .[0], value: (.[1] // "")} ] | from_entries) as $m
          | ($m
             + (if $cs == "" then {} else {check_set: $cs} end)
             + (if $hl == "" then {} else {check_set_healed: $hl} end)
             + (if $fl == "" then {} else {check_set_heal_flagged: $fl} end)
             | if $claimed == "1" then del(.["gc.routed_to"]) else . end) as $meta
          | [{id: $id, status: $st,
              assignee: (if $as == "" then null else $as end),
              metadata: $meta}]' ;;
  close)
    # gc bd close <id> --reason "..." — the script closes a review it minted but
    # could not durably route, so the next pass's dedup does not reuse an
    # unclaimable bead.
    printf '%s\n' "$3" >> "$FAKE_CLOSED" ;;
  create)
    # gc bd create "<title>" -t task [--body-file -] --json
    n=$(cat "$FAKE_SEQ" 2>/dev/null || echo 0); n=$((n + 1)); printf '%s' "$n" > "$FAKE_SEQ"
    # Capture the dispatched BODY (tk-jufvl). The review method arrives on stdin
    # via --body-file -; recording it per-bead is what lets the assertions below
    # prove the dispatch names a method instead of shipping a bare title.
    if grep -q -- '--body-file -' <<< "$*"; then
      cat > "$FAKE_BODIES/rev-new-$n" 2>/dev/null || true
    fi
    printf '{"id":"rev-new-%s"}\n' "$n" ;;
  update)
    id="$3"
    # Record a check_set stamp so the NEXT list/show reflects it (convergence).
    if grep -q 'check_set=' <<< "$*"; then
      val=$(printf '%s' "$*" | sed -n 's/.*--set-metadata check_set=\([^ ]*\).*/\1/p')
      # Honour a deliberate stamp-fail injection: if this id is in FAKE_STAMPFAIL,
      # do NOT persist the check_set (simulate a lost ledger write).
      if ! grep -qx "$id" "$FAKE_STAMPFAIL" 2>/dev/null; then
        printf '%s\t%s\n' "$id" "$val" >> "$FAKE_STAMPED"
      fi
    fi
    if grep -q 'check_set_healed=' <<< "$*"; then
      val=$(printf '%s' "$*" | sed -n 's/.*--set-metadata check_set_healed=\([^ ]*\).*/\1/p')
      # $FAKE_HEALFAIL is the PARTIAL-write injection, and it is deliberately
      # independent of $FAKE_STAMPFAIL: the two fields go out in one update but
      # persist separately, so the interesting failure is the asymmetric one —
      # check_set lands, check_set_healed is silently dropped. Listing an id here
      # discards EVERY write of this field, including the script's repair attempt.
      if ! grep -qx "$id" "$FAKE_HEALFAIL" 2>/dev/null; then
        printf '%s\t%s\n' "$id" "$val" >> "$FAKE_HEALED"
      fi
    fi
    if grep -q 'check_set_heal_flagged=' <<< "$*"; then
      # Every ATTEMPT is recorded, whether or not it persists: the flag is now read
      # back and repaired once, and counting attempts is how the regression proves
      # the repair actually happens instead of the script trusting one blind write.
      printf '%s\n' "$id" >> "${FAKE_FLAGTRIES:-/dev/null}"
      # $FAKE_FLAGFAIL is the same shape as $FAKE_HEALFAIL, aimed at the FALLBACK
      # mark: listing an id discards every write of check_set_heal_flagged. Staged
      # together with $FAKE_HEALFAIL it is the compound case where NEITHER durable
      # retry mark survives, and the anchor would silently fall out of every later
      # pass (review tk-y5r1e finding #2).
      if ! grep -qx "$id" "${FAKE_FLAGFAIL:-/dev/null}" 2>/dev/null; then
        printf '%s\n' "$id" >> "$FAKE_FLAGGED"
      fi
    fi
    # Record review metadata (anchor_bead, routing, task_kind, review_branch,
    # review_note, ...) by walking the ARGUMENT VECTOR rather than "$*". A value
    # containing spaces — review_note carries a whole sentence — used to be
    # truncated at the first word by the old `sed` capture, so an assertion could
    # only prove that SOME review_note key was written, never that the reason
    # survived. The full value is recorded here so the fixtures can assert content
    # (branch tk-s3pzi).
    #
    # $FAKE_DROPKEY names ONE key whose write is silently DISCARDED — the "update
    # returned success but nothing landed" transient the route read-back exists to
    # catch. Dropping `gc.routed_to` and `review_pool` separately distinguishes an
    # unclaimable review from one whose signoff can no longer restore its route
    # (main tk-tbacg).
    prev=""
    for arg in "$@"; do
      if [ "$prev" = "--set-metadata" ]; then
        k=${arg%%=*}; v=${arg#*=}
        case "$k" in
          anchor_bead|gc.routed_to|review_pool|task_kind|check_name|review_branch|review_base|pr_number|pr_url|fix_target_pool|review_note)
            if [ "$k" = "${FAKE_DROPKEY:-}" ]; then prev="$arg"; continue; fi
            # Injected route-write failure ($FAKE_ROUTEFAIL non-empty): drop the
            # write, so the ledger never records the route and the script's
            # read-back sees the miss — the tk-3xy37 shape.
            if [ "$k" = "gc.routed_to" ] && grep -qs . "$FAKE_ROUTEFAIL"; then
              prev="$arg"; continue
            fi
            # $FAKE_STALE_ROUTE models a SPLIT route: the batched update persists
            # review_pool for THIS pool while gc.routed_to keeps an OLDER pool's
            # value. Not a dropped write — a write whose live half never took — so
            # the read-back sees a perfectly non-empty gc.routed_to that offers the
            # review to somebody else entirely.
            if [ "$k" = "gc.routed_to" ] && [ -n "${FAKE_STALE_ROUTE:-}" ]; then
              v="$FAKE_STALE_ROUTE"
            fi
            printf '%s\t%s\t%s\n' "$id" "$k" "$v" >> "$FAKE_REVMETA" ;;
        esac
      fi
      prev="$arg"
    done ;;
  dep)
    # `gc bd dep list <anchor> --direction=up -t parent-child --json` — the shared
    # signoff-round-cap block's read. Answers from $FAKE_ROUNDS (anchor<TAB>n): n
    # rework children, each stamped source_review_bead, which is what one spent
    # round looks like. An anchor absent from the file has none, which is every
    # fixture that is not exercising the cap.
    if [ "$3" = "list" ]; then
      anchor="$4"
      n=$(awk -F'\t' -v a="$anchor" '$1==a{print $2; exit}' "$FAKE_ROUNDS" 2>/dev/null)
      case "${n:-}" in ''|*[!0-9]*) n=0 ;; esac
      out=""; i=0
      while [ "$i" -lt "$n" ]; do
        i=$((i + 1))
        obj=$(printf '{"id":"fix-%s-%s","metadata":{"source_review_bead":"rv-%s"}}' "$anchor" "$i" "$i")
        if [ -z "$out" ]; then out="$obj"; else out="$out,$obj"; fi
      done
      printf '[%s]\n' "$out"
      exit 0
    fi
    # gc bd dep <review> --blocks <anchor>
    rev="$3"; anchor=$(printf '%s' "$*" | sed -n 's/.*--blocks \([^ ]*\).*/\1/p')
    printf '%s\t%s\n' "$rev" "$anchor" >> "$FAKE_DEPS" ;;
esac
exit 0
GC
chmod +x "$TMP/bin/gc"

# --- git stub. ----------------------------------------------------------------
# `git remote get-url origin` is the ONE source the script trusts for "which
# repository is ours" — `live_head_for` pins its head read to it for the same reason
# `certify_pr_identity` pins its PR read (a bare `repos/{owner}/{repo}` resolves in
# whatever repository gh considers CURRENT). Answering it here is what makes the
# marker-vs-head fixtures exercise the real path instead of the unresolvable-origin
# fail-soft. $FAKE_NOORIGIN models a checkout with no usable origin.
cat > "$TMP/bin/git" <<'GIT'
#!/usr/bin/env bash
if [ "$1" = "remote" ] && [ "$2" = "get-url" ] && [ "$3" = "origin" ]; then
  [ -s "$FAKE_NOORIGIN" ] && exit 1
  printf 'https://github.com/o/r.git\n'; exit 0
fi
exit 0
GIT
chmod +x "$TMP/bin/git"

# --- gh stub. -----------------------------------------------------------------
# Two reads are stubbed:
#
#   gh api repos/<owner>/<repo>/commits/<branch> --jq .sha  — a branch's LIVE head,
#     for the marker-vs-head test (tk-t46nq). Backed by $FAKE_HEADS (branch<TAB>sha);
#     a branch with no entry exits non-zero and prints nothing, which is exactly the
#     "head unresolvable / no gh" fail-soft path.
#
#   gh pr view <n> --repo <host/owner/repo> --json ...     — the PR identity+state
#     `certify_pr_identity` certifies, which the terminal-PR guard on the dispatch
#     path now depends on (review tk-w9ttd finding #2). Backed by $FAKE_PRS
#     (number<TAB>state<TAB>headRefName); a number with no entry FAILS the view,
#     which is the unreadable-state fixture.
#
# Both reads are checked for their PIN, not just their subject. A read that is not
# pinned to the origin-derived repository answers for a repository that is not ours,
# and the head or state it returns would gate the wrong work.
#
# THE HOST HALF OF THE PIN IS ENFORCED HERE, not only the `o/r` half (review tk-w9ttd
# finding #1). `o/r` names one repository PER HOST, so a stub that accepted the path
# and ignored `--hostname` would pass a script that dropped the host word entirely —
# which is precisely the regression this file must catch, and precisely the one it
# used to miss. `${ORIGIN_HOST:+--hostname ...}` deletes itself SILENTLY when the
# variable is empty, so nothing but this check stands between a lost host pin and a
# green suite. Arguments are scanned rather than positional — `--hostname`, `--repo`
# and `--jq` may sit on either side of the subject.
#
# Every invocation is logged to $FAKE_GHLOG so a test can assert on the pin DIRECTLY,
# by argv, rather than only through the behaviour a refusal happens to produce.
cat > "$TMP/bin/gh" <<'GH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_GHLOG" 2>/dev/null || true

# Scan for the pinning flags wherever they sit.
host=""; repo_flag=""; prev=""
for a in "$@"; do
  case "$prev" in
    --hostname) host="$a" ;;
    --repo)     repo_flag="$a" ;;
  esac
  prev="$a"
done

if [ "$1" = "pr" ] && [ "$2" = "view" ]; then
  num="$3"
  # HOST-QUALIFIED `--repo`, the form certify_pr_identity pins with.
  [ "$repo_flag" = "github.com/o/r" ] || exit 1
  row=$(awk -F'\t' -v n="$num" '$1==n{print; exit}' "$FAKE_PRS" 2>/dev/null)
  [ -n "$row" ] || exit 1
  st=$(printf '%s' "$row" | cut -f2)
  hd=$(printf '%s' "$row" | cut -f3)
  printf '{"state":"%s","baseRefName":"main","url":"https://github.com/o/r/pull/%s","headRefName":"%s","headRepositoryOwner":{"login":"o"},"headRepository":{"name":"r"}}\n' \
    "$st" "$num" "$hd"
  exit 0
fi

[ "$1" = "api" ] || exit 0
shift
path=""
for a in "$@"; do
  case "$a" in */commits/*) path="$a"; break ;; esac
done
[ -n "$path" ] || exit 1
repo=$(printf '%s' "$path" | sed -n 's|^repos/\(.*\)/commits/.*$|\1|p')
[ "$repo" = "o/r" ] || exit 1
[ "$host" = "github.com" ] || exit 1
ref=$(printf '%s' "$path" | sed -n 's|.*/commits/\(.*\)$|\1|p')
[ -n "$ref" ] || exit 1
sha=$(awk -F'\t' -v b="$ref" '$1==b{print $2; exit}' "$FAKE_HEADS" 2>/dev/null)
[ -n "$sha" ] || exit 1
printf '%s\n' "$sha"
GH
chmod +x "$TMP/bin/gh"

: > "$TMP/stamped"; : > "$TMP/healed"; : > "$TMP/flagged"; : > "$TMP/revmeta"
: > "$TMP/deps"; : > "$TMP/stampfail"; : > "$TMP/healfail"; : > "$TMP/closed"
: > "$TMP/flagfail"; : > "$TMP/flagtries"; echo 0 > "$TMP/seq"
: > "$TMP/branchbeads"; : > "$TMP/heads"; : > "$TMP/routefail"
: > "$TMP/noorigin"; : > "$TMP/revstate"; : > "$TMP/prs"; : > "$TMP/ghlog"
: > "$TMP/rounds"
# anchor<TAB>rework rounds already spent. bead-CAPPED is at the default cap of 3;
# everything else is absent from the file and has spent none.
printf 'bead-CAPPED\t3\n' > "$TMP/rounds"
printf '413\tOPEN\tpolecat/feat-capped\n' > "$TMP/prs"
mkdir -p "$TMP/bodies"

export PATH="$TMP/bin:$PATH"
export FAKE_ANCHORS="$TMP/anchors" FAKE_REVIEWS="$TMP/reviews" \
       FAKE_STAMPED="$TMP/stamped" FAKE_HEALED="$TMP/healed" \
       FAKE_FLAGGED="$TMP/flagged" FAKE_REVMETA="$TMP/revmeta" FAKE_DEPS="$TMP/deps" \
       FAKE_STAMPFAIL="$TMP/stampfail" FAKE_HEALFAIL="$TMP/healfail" \
       FAKE_FLAGFAIL="$TMP/flagfail" FAKE_FLAGTRIES="$TMP/flagtries" \
       FAKE_SEQ="$TMP/seq" FAKE_CLOSED="$TMP/closed" FAKE_BODIES="$TMP/bodies" \
       FAKE_BRANCHBEADS="$TMP/branchbeads" FAKE_HEADS="$TMP/heads" \
       FAKE_ROUTEFAIL="$TMP/routefail" FAKE_NOORIGIN="$TMP/noorigin" \
       FAKE_REVSTATE="$TMP/revstate" FAKE_PRS="$TMP/prs" FAKE_GHLOG="$TMP/ghlog" \
       FAKE_ROUNDS="$TMP/rounds"

# --- Run 1. -------------------------------------------------------------------
RC1=0
OUT1="$(bash "$SCRIPT" \
  --default 'codex' \
  --review-pool 'gc-toolkit/gc-toolkit.polecat-codex' \
  --fix-pool 'gc-toolkit/gc-toolkit.polecat')" || RC1=$?
eq "$RC1" "0" "(EXIT) a pass with no failed stamp exits 0 (merge-skill not held)"

# (EMPTY) empty check_set -> stamped codex.
grep -q '^bead-EMPTY	codex$' "$TMP/stamped" \
  && ok "(EMPTY) empty check_set stamped with the declared default 'codex'" \
  || bad "(EMPTY) empty check_set must be stamped codex (got: $(cat "$TMP/stamped"))"
# ...and a signoff dispatched (routed to the codex pool, anchor_bead recorded).
grep -q '	anchor_bead	bead-EMPTY$' "$TMP/revmeta" \
  && ok "(EMPTY) signoff dispatched with anchor_bead=bead-EMPTY" \
  || bad "(EMPTY) signoff must record anchor_bead (got: $(cat "$TMP/revmeta"))"
grep -q '	gc.routed_to	gc-toolkit/gc-toolkit.polecat-codex$' "$TMP/revmeta" \
  && ok "(EMPTY) signoff routed to the codex pool" || bad "(EMPTY) signoff routed to codex pool"

# (ABSENT) absent check_set key heals the same as empty.
grep -q '^bead-ABSENT	codex$' "$TMP/stamped" \
  && ok "(ABSENT) absent check_set key stamped codex (absent == empty)" \
  || bad "(ABSENT) absent check_set must heal"

# (SEP) separator-only names no gates -> healed.
grep -q '^bead-SEP	codex$' "$TMP/stamped" \
  && ok "(SEP) separator-only ',,,' stamped codex (names no gates)" \
  || bad "(SEP) separator-only must heal"

# (NONE)/(OFF) the opt-out sentinel is LEFT ALONE — never stamped, never dispatched.
has '^bead-NONE	' "$TMP/stamped" && bad "(NONE) opt-out sentinel must NOT be stamped" \
                                  || ok "(NONE) opt-out 'none' left alone (not stamped)"
grep -q '	anchor_bead	bead-NONE$' "$TMP/revmeta" && bad "(NONE) opt-out must NOT dispatch a signoff" \
                                                    || ok "(NONE) opt-out 'none' -> no signoff dispatched"
has '^bead-OFF	' "$TMP/stamped" && bad "(OFF) opt-out 'off' must NOT be stamped" \
                                 || ok "(OFF) opt-out 'off' left alone"

# (NORMAL) an already-normalized anchor is untouched.
has '^bead-NORMAL	' "$TMP/stamped" && bad "(NORMAL) already-normalized anchor must NOT be re-stamped" \
                                    || ok "(NORMAL) already-normalized 'codex' left alone"
grep -q '	anchor_bead	bead-NORMAL$' "$TMP/revmeta" && bad "(NORMAL) must NOT dispatch a twin signoff" \
                                                       || ok "(NORMAL) already-normalized -> no dispatch"

# (GREEN) empty check_set BUT check.codex already green -> stamp, NO dispatch.
grep -q '^bead-GREEN	codex$' "$TMP/stamped" \
  && ok "(GREEN) empty+green anchor still stamped codex (audit trail)" \
  || bad "(GREEN) empty+green anchor must be stamped"
grep -q '	anchor_bead	bead-GREEN$' "$TMP/revmeta" && bad "(GREEN) already-green gate must NOT dispatch" \
                                                     || ok "(GREEN) already-green gate -> stamp only, no dispatch"

# (INFLGT) empty check_set BUT an open review already references the anchor ->
# stamp, NO twin dispatch.
grep -q '^bead-INFLGT	codex$' "$TMP/stamped" \
  && ok "(INFLGT) empty anchor with in-flight review still stamped" \
  || bad "(INFLGT) empty anchor must be stamped"
grep -q '	anchor_bead	bead-INFLGT$' "$TMP/revmeta" && bad "(INFLGT) in-flight review must NOT be twinned" \
                                                       || ok "(INFLGT) in-flight review reused -> no twin dispatch"

# --- The WS4 verdict vocabulary on check.codex, one anchor per verb -----------
# `marker_blocks_dispatch` is a TOTAL classification of the marker value, and the
# three answers below are each load-bearing for a DIFFERENT hold. They are asserted
# together because the bug in each direction is the same shape — a gate nothing can
# raise, or a gate raised by something that should not have raised it.

# (EXCEPT) an exception is terminal until an operator acts and the head moves.
# Dispatching under one would put a reviewer on a gate just declared un-reviewable.
grep -q '^bead-EXCEPT	codex$' "$TMP/stamped" \
  && ok "(EXCEPT) exception-marked anchor still stamped codex (audit trail)" \
  || bad "(EXCEPT) exception-marked anchor must be stamped"
grep -q '	anchor_bead	bead-EXCEPT$' "$TMP/revmeta" && bad "(EXCEPT) exception@ gate must NOT dispatch" \
                                                      || ok "(EXCEPT) exception@ gate -> stamp only, no dispatch"

# (FIXABLE) the one non-green verb that MUST fall through. `fixable` says
# remediation is in flight, and the in-flight probe — not the marker — is what
# stops a twin while it really is running. Blocking on the marker instead would
# leave an anchor whose remediation ended without green with no review, no rework
# child, and no marker that can ever go green: the silent indefinite hold.
grep -q '	anchor_bead	bead-FIXABLE$' "$TMP/revmeta" \
  && ok "(FIXABLE) fixable@ with nothing in flight -> dispatch (not treated as satisfiable)" \
  || bad "(FIXABLE) fixable@ must NOT block dispatch (got: $(cat "$TMP/revmeta"))"

# (WEIRD) review tk-i688b P1 — the R12 unmappable case. A marker naming no verb is
# reconcile-gate-verdicts.sh's to classify, and that pass runs AFTER this one in the
# same patrol wake. Dispatching here queues a review in the window before the
# exception is recorded; that review is claimed on a later wake and can stamp
# green@<head> over the exception, lifting by ordinary automation a hold R12 defines
# as terminal-until-operator. The gate stays HELD either way, so skipping costs a
# wake of latency and nothing else.
grep -q '	anchor_bead	bead-WEIRD$' "$TMP/revmeta" \
  && bad "(WEIRD) unmappable marker must NOT dispatch before the exception arm records the hold" \
  || ok "(WEIRD) unmappable 'weird@<head>' -> no dispatch (left for reconcile-gate-verdicts.sh)"
hasin "$OUT1" 'bead-WEIRD carries an UNMAPPABLE' \
  && ok "(WEIRD) unmappable marker is REPORTED, not silently skipped" \
  || bad "(WEIRD) skipping an unmappable marker must say so on stdout"

# (NOVERB) the same rule reached the other way: a value with no "@" at all names no
# verb either (`gate_marker_verb` splits on the FIRST "@" and a bare token has
# none). A literal `green` is therefore UNMAPPABLE, not green — the answer both
# passes must give it, or a marker nobody can read means two different things.
grep -q '	anchor_bead	bead-NOVERB$' "$TMP/revmeta" \
  && bad "(NOVERB) a bare 'green' with no @oid must NOT dispatch (it is unmappable)" \
  || ok "(NOVERB) bare 'green' (no @oid) -> unmappable, no dispatch"

# (PREOPEN) a pre_open_gate anchor heals + dispatches a BRANCH review.
grep -q '^bead-PREOPEN	codex$' "$TMP/stamped" \
  && ok "(PREOPEN) pre_open_gate anchor stamped codex" || bad "(PREOPEN) pre-open anchor must heal"
grep -q '	review_branch	polecat/feat-preopen$' "$TMP/revmeta" \
  && ok "(PREOPEN) pre-open signoff carries review_branch (BRANCH review, no PR)" \
  || bad "(PREOPEN) pre-open signoff must review the branch"
# The pre-open review must NOT carry a pr_number (no PR yet).
grep -q PREOPEN_HAS_PR < <(
  awk -F'\t' '$2=="anchor_bead" && $3=="bead-PREOPEN"{print $1}' "$TMP/revmeta" | while read -r rid; do
    grep -q "^$rid	pr_number	" "$TMP/revmeta" && echo "PREOPEN_HAS_PR" || true
  done
) && bad "(PREOPEN) pre-open review must NOT carry pr_number" \
  || ok "(PREOPEN) pre-open review has no pr_number (correct)"

# (ORDER) fail-closed: the stamp must be applied BEFORE the dispatch. A stamped +
# routed anchor proves the order held (routing is the last write); assert every
# dispatched anchor was also stamped.
DISPATCHED_ANCHORS=$(awk -F'\t' '$2=="anchor_bead"{print $3}' "$TMP/revmeta" | sort -u)
order_ok=1
for a in $DISPATCHED_ANCHORS; do
  grep -q "^$a	" "$TMP/stamped" || order_ok=0
done
[ "$order_ok" = 1 ] && ok "(ORDER) every dispatched anchor was stamped first (fail-closed)" \
                    || bad "(ORDER) a signoff was dispatched for an UNSTAMPED anchor"

# (BLOCKS) each dispatched review is linked BLOCKS its anchor.
grep -q '	bead-EMPTY$' "$TMP/deps" \
  && ok "(BLOCKS) dispatched review BLOCKS its anchor (gate-as-dep)" \
  || bad "(BLOCKS) review must BLOCK the anchor"

# (METHOD) EVERY dispatched signoff carries the review METHOD in its body
# (tk-jufvl). A title-only review bead names no method, so the reviewing polecat
# matches one out of its own skill catalog — the drift that ran a 6-persona
# fan-out at ~4.7M tokens per review. The body is what closes that vacuum, and it
# must be on every dispatch, PRE-OPEN as well as post-open.
DISPATCH_COUNT=$(awk -F'\t' '$2=="anchor_bead"{print $1}' "$TMP/revmeta" | sort -u | wc -l | tr -d ' ')
BODY_COUNT=$(find "$TMP/bodies" -type f | wc -l | tr -d ' ')
eq "$BODY_COUNT" "$DISPATCH_COUNT" "(METHOD) every dispatched signoff was created with a body"
method_ok=1; nofanout_ok=1; gate_ok=1
for b in "$TMP"/bodies/*; do
  [ -f "$b" ] || continue
  grep -qF 'signoff-review' "$b" || method_ok=0
  grep -qF 'Do NOT spawn' "$b" || nofanout_ok=0
  grep -qF 'green@' "$b" || gate_ok=0
done
[ "$BODY_COUNT" -gt 0 ] && [ "$method_ok" = 1 ] \
  && ok "(METHOD) every dispatched body names the signoff-review method" \
  || bad "(METHOD) a dispatched review body did not name the method"
[ "$BODY_COUNT" -gt 0 ] && [ "$nofanout_ok" = 1 ] \
  && ok "(METHOD) every dispatched body forbids subagent/persona fan-out" \
  || bad "(METHOD) a dispatched review body did not forbid fan-out"
[ "$BODY_COUNT" -gt 0 ] && [ "$gate_ok" = 1 ] \
  && ok "(METHOD) every dispatched body states the green@<oid> gate contract" \
  || bad "(METHOD) a dispatched review body did not state the gate contract"
# The PRE-OPEN dispatch specifically (it is the arm with no PR to fall back on).
PREOPEN_REV=$(awk -F'\t' '$2=="anchor_bead" && $3=="bead-PREOPEN"{print $1; exit}' "$TMP/revmeta")
if [ -n "$PREOPEN_REV" ] && [ -f "$TMP/bodies/$PREOPEN_REV" ]; then
  grep -qF 'signoff-review' "$TMP/bodies/$PREOPEN_REV" \
    && ok "(METHOD) the PRE-OPEN branch review also carries the method" \
    || bad "(METHOD) the PRE-OPEN branch review must carry the method"
else
  bad "(METHOD) no body captured for the PRE-OPEN dispatch"
fi

# Summary: 10 healed (EMPTY, ABSENT, SEP, GREEN, INFLGT, PREOPEN, and the four
# verdict-vocabulary anchors EXCEPT/FIXABLE/WEIRD/NOVERB), and the opt-outs /
# normal untouched. Healed counts the STAMP, which is orthogonal to the dispatch:
# an anchor whose marker blocks the dispatch is still stamped, exactly as (GREEN)
# has always been — the stamp is the audit trail that the gate was normalized, and
# withholding it would leave the anchor ungated to merge-skill.sh.
hasin "$OUT1" '11 healed' \
  && ok "run 1 summary reports 11 healed" || bad "run 1 summary healed count (got: $OUT1)"

# --- (CAP) the convergence cap, on THIS dispatcher (tk-vie5k) ------------------
# Both arms that reach the dispatch — the ABSENT-marker one and the `fixable@`
# re-gate — had no cap at all, so this pass minted round N+1 in exactly the window
# the cap exists to close (tk-vx2et, observed on tk-fdstg as round 4 of a cap of 3).
# bead-CAPPED is at the cap and otherwise dispatches: same shape as bead-EMPTY.
hasin "$OUT1" 'bead-CAPPED has spent 3 rework round(s) against a cap of 3' \
  && ok "(CAP) an anchor at the cap declines to dispatch, and says so" \
  || bad "(CAP) capped anchor should decline the dispatch (got: $OUT1)"
grep -q 'anchor_bead=bead-CAPPED' "$TMP/revmeta" \
  && bad "(CAP) a review was dispatched for an anchor past the cap" \
  || ok "(CAP) no review bead is minted for an anchor past the cap"
# THE STAMP IS NOT THE DISPATCH. The gate is still normalized — that is the audit
# trail that it was armed, and withholding it would leave the anchor ungated to
# merge-skill.sh. Only the SPAWN is declined.
hasin "$OUT1" "bead-CAPPED (pull_request PR#413) has NO normalized check_set" \
  && ok "(CAP) the gate is still stamped; only the spawn is declined" \
  || bad "(CAP) capped anchor must still be normalized"
# AND NOTHING IS WRITTEN UNDER check.<gate> here: the terminal verdict has ONE
# writer, reconcile-gate-verdicts.sh's R11 (signoff-cap-no-gate-write). Stamping an
# exception from this arm too is tk-mf3em, one dispatcher over.
grep -q 'check\.' < <(grep -E '^bead-CAPPED\s' "$TMP/revmeta" 2>/dev/null) \
  && bad "(CAP) the cap arm must write nothing under check.<gate>" \
  || ok "(CAP) the cap arm writes nothing under check.<gate>"
hasin "$OUT1" '2 explicit opt-out' \
  && ok "run 1 summary reports 2 explicit opt-out" || bad "run 1 summary opt-out count (got: $OUT1)"

# --- Run 2: convergence. Healed anchors are not re-stamped; dispatched gates are
#     satisfiable (the review minted in run 1 is now in flight), so no re-dispatch.
: > "$TMP/revmeta2"; cp "$TMP/revmeta" "$TMP/revmeta.r1"
STAMPS_BEFORE=$(wc -l < "$TMP/stamped")
OUT2="$(bash "$SCRIPT" \
  --default 'codex' \
  --review-pool 'gc-toolkit/gc-toolkit.polecat-codex' \
  --fix-pool 'gc-toolkit/gc-toolkit.polecat')"
STAMPS_AFTER=$(wc -l < "$TMP/stamped")
eq "$STAMPS_BEFORE" "$STAMPS_AFTER" "(CONV) no anchor re-stamped on the second pass"
hasin "$OUT2" '0 healed' \
  && ok "(CONV) run 2 heals nothing (all already normalized)" || bad "(CONV) run 2 must heal 0 (got: $OUT2)"
# The run-1 dispatched reviews are now in flight (recorded in FAKE_REVMETA and
# resolvable by anchor_bead), so run 2 dispatches no twins for them.
NEW_DISPATCH=$(comm -13 <(sort -u "$TMP/revmeta.r1") <(sort -u "$TMP/revmeta") | grep -c 'anchor_bead' || true)
eq "$NEW_DISPATCH" "0" "(CONV) no twin signoff dispatched on the second pass"

# --- Run 3: RETRY after a dispatch that failed. A previously-healed anchor whose
#     gate is still unsatisfiable (healed recorded, no marker, nothing in flight)
#     must re-dispatch — the stamp did NOT hide it from the satisfiability retry.
cat > "$TMP/anchors" <<'A'
bead-STRAND|pull_request|codex|409|polecat/feat-strand|main||codex
A
# healed recorded (run happened before) but NO review exists for it and NO marker.
: > "$TMP/reviews"; : > "$TMP/revmeta"; : > "$TMP/stamped"; : > "$TMP/deps"
bash "$SCRIPT" \
  --default 'codex' \
  --review-pool 'gc-toolkit/gc-toolkit.polecat-codex' \
  --fix-pool 'gc-toolkit/gc-toolkit.polecat' >/dev/null
grep -q '	anchor_bead	bead-STRAND$' "$TMP/revmeta" \
  && ok "(RETRY) a healed anchor with an unsatisfiable gate re-dispatches the signoff" \
  || bad "(RETRY) healed-but-stranded anchor must re-dispatch (got: $(cat "$TMP/revmeta"))"
# It must NOT be re-stamped (check_set already 'codex').
has '^bead-STRAND	' "$TMP/stamped" && bad "(RETRY) already-normalized healed anchor must NOT be re-stamped" \
                                    || ok "(RETRY) healed anchor not re-stamped (check_set already normal)"

# --- Run 4: STAMPFAIL. A stamp that does not persist is NOT counted healed and
#     does NOT dispatch; the anchor is flagged once and retried.
cat > "$TMP/anchors" <<'A'
bead-FAIL|pull_request|EMPTY|410|polecat/feat-fail|main||
A
: > "$TMP/reviews"; : > "$TMP/revmeta"; : > "$TMP/stamped"; : > "$TMP/healed"
: > "$TMP/flagged"; : > "$TMP/deps"; echo 'bead-FAIL' > "$TMP/stampfail"
RC4=0
OUT4="$(bash "$SCRIPT" \
  --default 'codex' \
  --review-pool 'gc-toolkit/gc-toolkit.polecat-codex' \
  --fix-pool 'gc-toolkit/gc-toolkit.polecat')" || RC4=$?
grep -q '	anchor_bead	bead-FAIL$' "$TMP/revmeta" && bad "(STAMPFAIL) a failed stamp must NOT dispatch a signoff" \
                                                    || ok "(STAMPFAIL) failed stamp -> no signoff dispatched (fail-closed)"
has '^bead-FAIL$' "$TMP/flagged" && ok "(STAMPFAIL) failed stamp flags the anchor once" \
                                 || bad "(STAMPFAIL) failed stamp must flag the anchor"
hasin "$OUT4" '0 healed' \
  && ok "(STAMPFAIL) a non-persisting stamp is NOT counted healed" || bad "(STAMPFAIL) must report 0 healed (got: $OUT4)"
# The unsafe exit: a still-ungated anchor must make the pass exit UNSAFE_RC (3) so
# the formula holds merge-skill this pass (review tk-z4u2e finding #1).
eq "$RC4" "3" "(STAMPFAIL) a failed stamp makes the pass exit UNSAFE rc=3"

# --- Run 4b: HEALPARTIAL (review tk-nwi06 finding #1). check_set and
#     check_set_healed go out in ONE update and persist SEPARATELY, so the write can
#     land by halves. The asymmetric half is the dangerous one: the GATE lands
#     (merge held — safe) while the retry mark is dropped. Pre-fix the read-back
#     only looked at check_set, so this read as a clean heal; and because check_set
#     now reads normal while check_set_healed is absent, the classifier sends the
#     anchor to `normal` on EVERY later pass. A dispatch that then failed left the
#     anchor codex-gated with nothing able to raise check.codex, and no pass would
#     ever look at it again — permanent, silent.
cat > "$TMP/anchors" <<'A'
bead-HALF|pull_request|EMPTY|412|polecat/feat-half|main||
A
: > "$TMP/reviews"; : > "$TMP/revmeta"; : > "$TMP/stamped"; : > "$TMP/healed"
: > "$TMP/flagged"; : > "$TMP/deps"; : > "$TMP/stampfail"; : > "$TMP/closed"
echo 'bead-HALF' > "$TMP/healfail"
RC4B=0
OUT4B="$(bash "$SCRIPT" \
  --default 'codex' \
  --review-pool 'gc-toolkit/gc-toolkit.polecat-codex' \
  --fix-pool 'gc-toolkit/gc-toolkit.polecat' 2>&1)" || RC4B=$?
grep -q '^bead-HALF	codex$' "$TMP/stamped" \
  && ok "(HEALPARTIAL) the gate half of the stamp did land" \
  || bad "(HEALPARTIAL) fixture must land check_set (got: $(cat "$TMP/stamped"))"
hasin "$OUT4B" '0 healed' \
  && ok "(HEALPARTIAL) a half-landed stamp is NOT counted healed" \
  || bad "(HEALPARTIAL) must report 0 healed (got: $OUT4B)"
hasin "$OUT4B" 'check_set_healed did NOT' \
  && ok "(HEALPARTIAL) the dropped retry mark is reported, not silent" \
  || bad "(HEALPARTIAL) the partial write must warn (got: $OUT4B)"
# THE POINT: the gate is made satisfiable in THIS pass rather than deferred, because
# there is no later pass that will revisit this anchor (see HEALDEFER below).
grep -q '	anchor_bead	bead-HALF$' "$TMP/revmeta" \
  && ok "(HEALPARTIAL) the signoff is dispatched THIS pass, not deferred to one that never comes" \
  || bad "(HEALPARTIAL) a half-stamped anchor must still get a satisfiable gate (got: $(cat "$TMP/revmeta"))"
has '^bead-HALF$' "$TMP/flagged" && ok "(HEALPARTIAL) the partial write flags the anchor once" \
                                 || bad "(HEALPARTIAL) a partial write must flag the anchor"
# NOT unsafe: the gate IS armed, so merge-skill holds this PR on its own. Exiting
# UNSAFE_RC here would hold every OTHER anchor's merge for the pass as collateral.
eq "$RC4B" "0" "(HEALPARTIAL) an armed-but-unmarked anchor does NOT force the UNSAFE exit"

# --- Run 4c: HEALDEFER, under the every-anchor sweep (tk-t46nq). The state a deferred
#     partial write would leave behind — check_set normalized, check_set_healed absent —
#     USED to be a dead end: the classifier read it "already normalized" and skipped it
#     forever, which is why 4b dispatches in-pass rather than trusting "next pass". The
#     satisfiability sweep removes that short-circuit — EVERY gating anchor is examined,
#     regardless of any repair mark — so a lost mark is no longer fatal: the absent marker
#     re-dispatches on the next pass. 4b still dispatches in-pass (one pass sooner is
#     strictly better), but the deferral it avoids is now recoverable, not permanent.
cat > "$TMP/anchors" <<'A'
bead-DEFER|pre_open_gate|codex||polecat/feat-defer|main||
A
: > "$TMP/reviews"; : > "$TMP/revmeta"; : > "$TMP/stamped"; : > "$TMP/healed"
: > "$TMP/flagged"; : > "$TMP/deps"; : > "$TMP/stampfail"; : > "$TMP/healfail"
: > "$TMP/branchbeads"; : > "$TMP/heads"
OUT4C="$(bash "$SCRIPT" \
  --default 'codex' \
  --review-pool 'gc-toolkit/gc-toolkit.polecat-codex' \
  --fix-pool 'gc-toolkit/gc-toolkit.polecat' 2>&1)"
grep -q '	anchor_bead	bead-DEFER$' "$TMP/revmeta" \
  && ok "(HEALDEFER) a lost-mark anchor is no longer a dead end — the every-anchor sweep re-dispatches it (tk-t46nq)" \
  || bad "(HEALDEFER) the sweep must re-dispatch a lost-mark anchor (got: $OUT4C)"
hasin "$OUT4C" '0 already normalized' \
  && ok "(HEALDEFER) nothing short-circuits as 'already normalized' — every gate is examined" \
  || bad "(HEALDEFER) the short-circuit is gone; no anchor classifies as already-normalized (got: $OUT4C)"

# --- Run 4d: the finding's exact compound case — check_set persists,
#     check_set_healed drops, AND the route write fails. Both guards must hold at
#     once: the dispatch is not counted (the review is unclaimable and gets closed
#     so the next pass can re-mint), and the operator is handed the by-hand repair
#     for the mark, because for THIS anchor there is no next pass.
cat > "$TMP/anchors" <<'A'
bead-HALFR|pull_request|EMPTY|414|polecat/feat-halfr|main||
A
: > "$TMP/reviews"; : > "$TMP/revmeta"; : > "$TMP/stamped"; : > "$TMP/healed"
: > "$TMP/flagged"; : > "$TMP/deps"; : > "$TMP/stampfail"; : > "$TMP/closed"
echo 'bead-HALFR' > "$TMP/healfail"
RC4D=0
OUT4D="$(FAKE_DROPKEY='gc.routed_to' bash "$SCRIPT" \
  --default 'codex' \
  --review-pool 'gc-toolkit/gc-toolkit.polecat-codex' \
  --fix-pool 'gc-toolkit/gc-toolkit.polecat' 2>&1)" || RC4D=$?
hasin "$OUT4D" '0 signoffs dispatched' \
  && ok "(HEALPARTIAL+ROUTE) an unroutable signoff is still NOT counted dispatched" \
  || bad "(HEALPARTIAL+ROUTE) unrouted dispatch must not count (got: $OUT4D)"
hasin "$OUT4D" 'did not durably route' \
  && ok "(HEALPARTIAL+ROUTE) the route failure is reported" \
  || bad "(HEALPARTIAL+ROUTE) unrouted dispatch must warn (got: $OUT4D)"
[ -s "$TMP/closed" ] && ok "(HEALPARTIAL+ROUTE) the unclaimable review is closed (no dedup poison)" \
                     || bad "(HEALPARTIAL+ROUTE) an unclaimable review must be closed"
hasin "$OUT4D" 'repair by hand: gc bd update bead-HALFR --set-metadata check_set_healed=codex' \
  && ok "(HEALPARTIAL+ROUTE) the operator gets the exact repair for the lost mark" \
  || bad "(HEALPARTIAL+ROUTE) the compound failure must name its by-hand repair (got: $OUT4D)"
eq "$RC4D" "0" "(HEALPARTIAL+ROUTE) the anchor is held, not UNSAFE — the gate is armed"
# ...and the anchor is NOT lost. Everything durable from run 4d is carried into the
# next pass — check_set landed, check_set_healed still cannot be written, the flag
# did land — and the only thing repaired is the route. The flag is the second mark
# that keeps this anchor visible: without it, check_set reads normal, the healed
# mark is absent, and the classifier drops it forever (see HEALDEFER). The minted
# review was CLOSED as unclaimable last pass, so the in-flight state is cleared too.
: > "$TMP/reviews"; : > "$TMP/revmeta"; : > "$TMP/deps"; : > "$TMP/closed"
OUT4E="$(bash "$SCRIPT" \
  --default 'codex' \
  --review-pool 'gc-toolkit/gc-toolkit.polecat-codex' \
  --fix-pool 'gc-toolkit/gc-toolkit.polecat' 2>&1)"
grep -q '	anchor_bead	bead-HALFR$' "$TMP/revmeta" \
  && ok "(HEALPARTIAL+ROUTE) the next pass DOES retry it — the flag keeps a mark-less anchor visible" \
  || bad "(HEALPARTIAL+ROUTE) a flagged anchor must not fall out of the retry (got: $OUT4E)"
hasin "$OUT4E" '1 signoffs dispatched' \
  && ok "(HEALPARTIAL+ROUTE) and the retry lands the signoff once the route write recovers" \
  || bad "(HEALPARTIAL+ROUTE) the recovered pass must dispatch (got: $OUT4E)"
eq "$(grep -c '^bead-HALFR	' "$TMP/stamped")" "1" \
  "(HEALPARTIAL+ROUTE) the already-armed gate is not re-stamped on the retry"
: > "$TMP/healfail"; : > "$TMP/flagged"

# --- Run 4f: BOTH MARKS LOST (review tk-y5r1e finding #2). check_set_heal_flagged
#     is the fallback that keeps a mark-less anchor visible (that is exactly what
#     run 4e proves), and it was written by the same best-effort update that just
#     dropped check_set_healed — and then trusted. So the shape the fallback exists
#     for is the one where it is ALSO lost: gate armed, both retry marks gone,
#     anchor invisible to every later pass. Pre-fix, nothing here even noticed. The
#     flag is now read back and repaired once, and when it still will not stick the
#     pass says so instead of promising a retry that cannot happen.
cat > "$TMP/anchors" <<'A'
bead-NOMARK|pull_request|EMPTY|415|polecat/feat-nomark|main||
A
: > "$TMP/reviews"; : > "$TMP/revmeta"; : > "$TMP/stamped"; : > "$TMP/healed"
: > "$TMP/flagged"; : > "$TMP/deps"; : > "$TMP/stampfail"; : > "$TMP/closed"
: > "$TMP/flagtries"
echo 'bead-NOMARK' > "$TMP/healfail"
echo 'bead-NOMARK' > "$TMP/flagfail"
RC4F=0
OUT4F="$(bash "$SCRIPT" \
  --default 'codex' \
  --review-pool 'gc-toolkit/gc-toolkit.polecat-codex' \
  --fix-pool 'gc-toolkit/gc-toolkit.polecat' 2>&1)" || RC4F=$?
eq "$(grep -c '^bead-NOMARK$' "$TMP/flagtries")" "2" \
  "(NOMARK) the flag is READ BACK and repaired once when the first write does not stick"
hasin "$OUT4F" 'NO durable retry mark persisted' \
  && ok "(NOMARK) both marks lost is reported — the anchor is invisible to later passes" \
  || bad "(NOMARK) a lost fallback mark must warn (got: $OUT4F)"
hasin "$OUT4F" 'Repair by hand: gc bd update bead-NOMARK --set-metadata check_set_healed=codex' \
  && ok "(NOMARK) the operator is handed the exact by-hand repair" \
  || bad "(NOMARK) the both-marks-lost warning must name the repair (got: $OUT4F)"
# The gate still gets made satisfiable IN THIS PASS — with no retry mark at all,
# this pass is the only one that will ever look at this anchor.
grep -q '	anchor_bead	bead-NOMARK$' "$TMP/revmeta" \
  && ok "(NOMARK) the signoff is still dispatched in-pass (the only pass this anchor gets)" \
  || bad "(NOMARK) a mark-less anchor must still get a satisfiable gate (got: $(cat "$TMP/revmeta"))"
eq "$RC4F" "0" "(NOMARK) an armed gate with no retry mark is held, not UNSAFE"

# --- Run 4g: BOTH MARKS LOST *and* the route write fails. The compound of 4d and
#     4f: the dispatch cannot be counted, and there is no retry mark to bring the
#     anchor back. The failure message must not promise "retrying next pass" — that
#     promise is what would send an operator away from an anchor nothing will ever
#     revisit. It carries the no-retry note instead.
cat > "$TMP/anchors" <<'A'
bead-NOMARKR|pull_request|EMPTY|416|polecat/feat-nomarkr|main||
A
: > "$TMP/reviews"; : > "$TMP/revmeta"; : > "$TMP/stamped"; : > "$TMP/healed"
: > "$TMP/flagged"; : > "$TMP/deps"; : > "$TMP/stampfail"; : > "$TMP/closed"
echo 'bead-NOMARKR' > "$TMP/healfail"
echo 'bead-NOMARKR' > "$TMP/flagfail"
OUT4G="$(FAKE_DROPKEY='gc.routed_to' bash "$SCRIPT" \
  --default 'codex' \
  --review-pool 'gc-toolkit/gc-toolkit.polecat-codex' \
  --fix-pool 'gc-toolkit/gc-toolkit.polecat' 2>&1)"
hasin "$OUT4G" 'did not durably route.*NO durable retry mark persisted' \
  && ok "(NOMARK+ROUTE) the route failure stops promising a next pass that cannot come" \
  || bad "(NOMARK+ROUTE) the dispatch failure must carry the no-retry note (got: $OUT4G)"
hasin "$OUT4G" 'did not durably route.*retrying next pass' \
  && bad "(NOMARK+ROUTE) a mark-less anchor must NOT be told it retries next pass (got: $OUT4G)" \
  || ok "(NOMARK+ROUTE) no false 'retrying next pass' on an anchor nothing will revisit"
: > "$TMP/healfail"; : > "$TMP/flagfail"; : > "$TMP/flagged"

# --- Run 5: a gateless-BY-CONFIG rig (--default none) heals to the sentinel, NOT
#     codex, and dispatches NOTHING — the repair restores declared intent.
cat > "$TMP/anchors" <<'A'
bead-CFGNONE|pull_request|EMPTY|411|polecat/feat-cfgnone|main||
A
: > "$TMP/reviews"; : > "$TMP/revmeta"; : > "$TMP/stamped"; : > "$TMP/healed"
: > "$TMP/flagged"; : > "$TMP/deps"; : > "$TMP/stampfail"
bash "$SCRIPT" --default 'none' --review-pool 'gc-toolkit/gc-toolkit.polecat-codex' >/dev/null
grep -q '^bead-CFGNONE	none$' "$TMP/stamped" \
  && ok "(CFGNONE) a --default none rig heals empty -> the 'none' sentinel (declared intent)" \
  || bad "(CFGNONE) --default none must stamp the sentinel (got: $(cat "$TMP/stamped"))"
grep -q '	anchor_bead	bead-CFGNONE$' "$TMP/revmeta" && bad "(CFGNONE) a gateless rig must NOT dispatch a signoff" \
                                                       || ok "(CFGNONE) gateless-by-config -> no signoff dispatched"

# --- Run 5a: FAIL-SOFT method (tk-jufvl). If review-dispatch-body.sh cannot be
#     found — an older pack checkout, a partial deploy — the dispatch must STILL
#     happen. An un-dispatched signoff leaves the armed gate unsatisfiable and
#     holds the merge forever, which is strictly worse than a title-only bead. So
#     the missing emitter degrades to today's behaviour and WARNs; it never
#     aborts the heal. Proven against the REAL script copied into a directory
#     with no emitter beside it (no test-only env hook in the product code).
SOFT="$TMP/soft"; mkdir -p "$SOFT"
cp "$SCRIPT" "$SOFT/check-set-heal.sh"; chmod +x "$SOFT/check-set-heal.sh"
cat > "$TMP/anchors" <<'A'
bead-SOFT|pull_request|EMPTY|412|polecat/feat-soft|main||
A
: > "$TMP/reviews"; : > "$TMP/revmeta"; : > "$TMP/stamped"; : > "$TMP/healed"
: > "$TMP/flagged"; : > "$TMP/deps"; : > "$TMP/stampfail"
rm -f "$TMP"/bodies/*
RC5B=0
SOFT_ERR="$TMP/soft.err"
bash "$SOFT/check-set-heal.sh" --default 'codex' \
  --review-pool 'gc-toolkit/gc-toolkit.polecat-codex' \
  --fix-pool 'gc-toolkit/gc-toolkit.polecat' >/dev/null 2>"$SOFT_ERR" || RC5B=$?
eq "$RC5B" "0" "(FAILSOFT) a missing method emitter does not fail the heal pass"
grep -q '	anchor_bead	bead-SOFT$' "$TMP/revmeta" \
  && ok "(FAILSOFT) the signoff is STILL dispatched without the emitter (gate stays satisfiable)" \
  || bad "(FAILSOFT) a missing emitter must not suppress the dispatch"
grep -q '	gc.routed_to	gc-toolkit/gc-toolkit.polecat-codex$' "$TMP/revmeta" \
  && ok "(FAILSOFT) the title-only fallback review is still routed" \
  || bad "(FAILSOFT) fallback review must still be routed"
grep -q 'TITLE-ONLY' "$SOFT_ERR" \
  && ok "(FAILSOFT) WARNs loudly that the dispatch carries no method" \
  || bad "(FAILSOFT) missing emitter must WARN (got: $(cat "$SOFT_ERR"))"

# --- Run 5b: THE ROUTE READ-BACK (tk-tmefn). The dispatch wrote gc.routed_to and
#     review_pool best-effort — status discarded — and then counted the signoff as
#     dispatched and woke the pool. If either write is dropped, the review bead
#     still exists and is still OPEN, so the NEXT pass's inflight_for dedup reuses
#     it instead of minting a replacement, while no pool can ever claim it. The
#     gate stays armed, the anchor stays held, and nothing retries: a permanent
#     strand built out of the repair itself. The route is now READ BACK, repaired
#     once, and — if it still will not stick — the unclaimable review is CLOSED so
#     the next pass can mint one that works.
#
#     The two fields are dropped SEPARATELY because they fail differently:
#     gc.routed_to missing = nobody is offered the review at all; review_pool
#     missing = it is offered now, but a signoff that has to put the review BACK
#     in a pool has no record of which pool that was. A third shape (ROUTE-SPLIT,
#     tk-bdfww) has NEITHER field empty and is still wrong: the durable copy names
#     this pool while the live offer still names an older one.
route_run() { # <drop-key> <claimed?> [stale-route-pool] -> OUT
  cat > "$TMP/anchors" <<'A'
bead-ROUTE|pull_request|EMPTY|430|polecat/feat-route|main||
A
  : > "$TMP/reviews"; : > "$TMP/revmeta"; : > "$TMP/stamped"; : > "$TMP/healed"
  : > "$TMP/flagged"; : > "$TMP/deps"; : > "$TMP/stampfail"; : > "$TMP/closed"
  FAKE_DROPKEY="$1" FAKE_CLAIMED="$2" FAKE_STALE_ROUTE="${3:-}" bash "$SCRIPT" \
    --default 'codex' \
    --review-pool 'gc-toolkit/gc-toolkit.polecat-codex' \
    --fix-pool 'gc-toolkit/gc-toolkit.polecat' 2>&1
}
# A SECOND pass over exactly the state the previous route_run left — nothing reset.
# That is what makes the dedup assertions real: a review this pass left open is
# still there to be found (or not) by the next one.
route_run_reuse() { # <drop-key> <claimed?> -> OUT
  FAKE_DROPKEY="$1" FAKE_CLAIMED="$2" bash "$SCRIPT" \
    --default 'codex' \
    --review-pool 'gc-toolkit/gc-toolkit.polecat-codex' \
    --fix-pool 'gc-toolkit/gc-toolkit.polecat' 2>&1
}

# (ROUTE-OK) both writes land -> counted as a dispatch, nothing closed.
OUT5B="$(route_run '' '')"
hasin "$OUT5B" '1 signoffs dispatched' \
  && ok "(ROUTE-OK) a durably-routed signoff is counted as dispatched" \
  || bad "(ROUTE-OK) a good route must count as dispatched (got: $OUT5B)"
[ -s "$TMP/closed" ] && bad "(ROUTE-OK) a durably-routed review must NOT be closed" \
                     || ok "(ROUTE-OK) a durably-routed review is left open for the pool"

# (ROUTE-DROP) gc.routed_to does not persist -> NOT counted, review closed so the
# next pass mints a claimable one instead of deduping onto this corpse.
OUT5C="$(route_run 'gc.routed_to' '')"
hasin "$OUT5C" '0 signoffs dispatched' \
  && ok "(ROUTE-DROP) a signoff whose route did not persist is NOT counted dispatched" \
  || bad "(ROUTE-DROP) an unrouted signoff must not count (got: $OUT5C)"
hasin "$OUT5C" 'did not durably route' \
  && ok "(ROUTE-DROP) the failure is reported, not silent" \
  || bad "(ROUTE-DROP) an unrouted signoff must warn (got: $OUT5C)"
[ -s "$TMP/closed" ] && ok "(ROUTE-DROP) the unclaimable review is closed (next pass re-mints)" \
                     || bad "(ROUTE-DROP) an unclaimable review must be closed or it poisons dedup"

# (ROUTE-DURABLE) review_pool does not persist, gc.routed_to does. The review IS
# claimable right now, so this looks fine — but the durable copy is the only thing
# a signoff can restore the route from when it must re-offer the review, and
# gc.routed_to is consumed by the very claim that would need it. Must NOT count.
OUT5D="$(route_run 'review_pool' '')"
hasin "$OUT5D" '0 signoffs dispatched' \
  && ok "(ROUTE-DURABLE) a missing review_pool is NOT counted dispatched (route is unrestorable)" \
  || bad "(ROUTE-DURABLE) a missing durable route copy must not count (got: $OUT5D)"
[ -s "$TMP/closed" ] && ok "(ROUTE-DURABLE) the review with no durable route is closed" \
                     || bad "(ROUTE-DURABLE) a review with no durable route must be closed"

# (ROUTE-DURABLE-CLAIMED) THE FORCE-CLOSE HAZARD (review tk-y5r1e finding #1). Same
# persistently-dropped review_pool as ROUTE-DURABLE, except a codex polecat has
# ALREADY CLAIMED the review. route_ok tests the durable copy FIRST, so it rejects
# this triple before the assignee exception can apply — and the failure path used to
# read that rejection as "claimed by nobody" and close the bead, `--force` on the
# retry specifically to beat the ownership check that would have stopped it. That
# force-closes an in-flight review and erases the only live signoff for an armed
# gate: the anchor then waits forever on a check.codex nothing is left to stamp.
# Uncounted is right; closed is not.
OUT5DC="$(route_run 'review_pool' '1')"
[ -s "$TMP/closed" ] \
  && bad "(ROUTE-DURABLE-CLAIMED) a CLAIMED review must never be closed, whatever the route reads (closed: $(cat "$TMP/closed"))" \
  || ok "(ROUTE-DURABLE-CLAIMED) a claimed review with a dropped durable route is LEFT OPEN, not force-closed"
hasin "$OUT5DC" 'CLAIMED by' \
  && ok "(ROUTE-DURABLE-CLAIMED) the unverifiable-but-claimed route is reported, not silent" \
  || bad "(ROUTE-DURABLE-CLAIMED) a claimed review with a bad route must warn (got: $OUT5DC)"
hasin "$OUT5DC" '0 signoffs dispatched' \
  && ok "(ROUTE-DURABLE-CLAIMED) it is still NOT counted dispatched (the route never verified)" \
  || bad "(ROUTE-DURABLE-CLAIMED) an unverified route must not count (got: $OUT5DC)"
# The next pass must find it and REUSE it rather than mint a twin — which is the
# whole reason leaving a claimed review open is safe.
hasin "$(route_run_reuse 'review_pool' '1')" '0 signoffs dispatched' \
  && ok "(ROUTE-DURABLE-CLAIMED) the next pass reuses the in-flight review instead of minting a twin" \
  || bad "(ROUTE-DURABLE-CLAIMED) a left-open claimed review must dedup the next pass"

# (ROUTE-CLAIMED) NOT over-firing. A codex polecat claiming the review between the
# write and the read-back CONSUMES gc.routed_to and takes the assignee. That is a
# healthy dispatch, not a lost route — re-routing it would offer a claimed review
# to a second pool, and closing it would yank it from its reviewer.
OUT5E="$(route_run '' '1')"
hasin "$OUT5E" '1 signoffs dispatched' \
  && ok "(ROUTE-CLAIMED) a review claimed the instant it routed still counts as dispatched" \
  || bad "(ROUTE-CLAIMED) a consumed gc.routed_to with an assignee must read as routed (got: $OUT5E)"
[ -s "$TMP/closed" ] && bad "(ROUTE-CLAIMED) a CLAIMED review must never be closed" \
                     || ok "(ROUTE-CLAIMED) a claimed review is left alone"

# (ROUTE-SPLIT) THE THIRD WAY A BATCHED ROUTE WRITE HALF-LANDS (tk-bdfww):
# review_pool persists for THIS pool while gc.routed_to keeps an OLDER pool's
# value. Neither field is empty, so a read-back that only asks "is the live route
# non-empty?" declares it verified — and it is exactly backwards: the durable copy
# says pool A, the live offer says pool B. The dispatch is counted, pool A is woken
# with nothing to claim, and the review that A's gate depends on sits in B's queue.
# Whichever pool eventually takes it, the anchor's gate is owed by a bead nobody
# routed there. The live half must MATCH the pool being dispatched to, not merely
# exist; a mismatch is unverified, which sends it down the repair-then-close path
# so the next pass mints a review that is actually offered to A.
OUT5G="$(route_run '' '' 'gc-toolkit/gc-toolkit.polecat-OTHER')"
hasin "$OUT5G" '0 signoffs dispatched' \
  && ok "(ROUTE-SPLIT) review_pool=A with a live gc.routed_to=B is NOT counted dispatched" \
  || bad "(ROUTE-SPLIT) a route offered to a different pool must not count (got: $OUT5G)"
hasin "$OUT5G" 'did not durably route' \
  && ok "(ROUTE-SPLIT) the split route is reported, not silent" \
  || bad "(ROUTE-SPLIT) a split route must warn (got: $OUT5G)"
[ -s "$TMP/closed" ] \
  && ok "(ROUTE-SPLIT) the misrouted review is closed (next pass mints one offered to this pool)" \
  || bad "(ROUTE-SPLIT) a review offered to another pool must be closed or it poisons dedup"

# --- Run 5f: LONG CHECK_SET (tk-tmefn). `has_codex` piped printf|tr|sed into
#     `grep -qxF codex` under `set -o pipefail`. grep -q exits at its FIRST match,
#     closing the pipe under sed while sed still has the gates AFTER `codex` to
#     write; sed takes SIGPIPE and the pipeline reports 141. `! has_codex` then
#     reads TRUE for a check_set that plainly names codex, and this anchor is
#     skipped — no signoff dispatched for a gate that IS armed, so the anchor is
#     held forever on a check.codex nothing was sent to stamp. Measured 10/10
#     misses at 10k gates, which is why the fixture is that wide: the bug class is
#     what is being pinned, and the in-shell fix makes length irrelevant.
#     `codex` is placed FIRST so there is a long tail left to SIGPIPE on.
LONGCS="codex"
for _i in $(seq 1 10000); do LONGCS="$LONGCS,gate$_i"; done
#     Shaped like the (RETRY) anchor — check_set_healed recorded, no marker,
#     nothing in flight — so it reaches the satisfiability check where has_codex
#     decides. Without the healed mark an already-normalized anchor is counted
#     "normal" and returns before has_codex ever runs, and the case would pass
#     vacuously against the broken pipeline.
printf 'bead-LONGCS|pull_request|%s|431|polecat/feat-longcs|main||%s\n' "$LONGCS" "$LONGCS" > "$TMP/anchors"
: > "$TMP/reviews"; : > "$TMP/revmeta"; : > "$TMP/stamped"; : > "$TMP/healed"
: > "$TMP/flagged"; : > "$TMP/deps"; : > "$TMP/stampfail"; : > "$TMP/closed"
OUT5F="$(bash "$SCRIPT" \
  --default 'codex' \
  --review-pool 'gc-toolkit/gc-toolkit.polecat-codex' \
  --fix-pool 'gc-toolkit/gc-toolkit.polecat' 2>&1)"
hasin "$OUT5F" '1 signoffs dispatched' \
  && ok "(LONGCS) a long check_set naming codex still dispatches a signoff (no SIGPIPE miss)" \
  || bad "(LONGCS) long check_set must be recognized as naming codex (got: $OUT5F)"
grep -q '	anchor_bead	bead-LONGCS$' "$TMP/revmeta" \
  && ok "(LONGCS) the dispatched signoff is linked to the long-check_set anchor" \
  || bad "(LONGCS) long-check_set anchor must get a linked signoff"

# --- Run 6: CADENCE GATING (heal-gates-merge). The finding this rework closes
#     (review tk-z4u2e #1): a stamp that did not persist used to exit 0, so the
#     caller ran merge-skill.sh in the SAME pass and the still-ungated anchor
#     merged un-reviewed. Extract the REAL gating snippet from the merge-cadence
#     pass runner and drive the REAL check-set-heal.sh into it with a merge-skill
#     STUB — a stamp-failing heal must HOLD the merge; a clean heal must let it
#     run.
GATE="$(awk '
  /# >>> heal-gates-merge/ {f=1; next}
  /# <<< heal-gates-merge/ {f=0}
  f' "$RUNNER")"
[ -n "$GATE" ] \
  && ok "(GATE) heal-gates-merge snippet extracted from the pass runner" \
  || bad "(GATE) heal-gates-merge markers missing or renamed in the pass runner"
# Template-free so it executes directly. The runner is plain shell with no
# formula-var channel at all, so this now also guards against someone
# reintroducing one.
hasin "$GATE" '{{' \
  && bad "(GATE) extracted snippet still contains a {{template}} — the pass runner takes no formula vars" \
  || ok "(GATE) heal-gates-merge snippet is template-free (executable verbatim)"

# Stub SCRIPTS_DIR: the REAL heal (symlinked) + a merge-skill STUB that records if
# it ran + a no-op pre-open-resolve. SCRIPTS_DIR must NOT be the real assets dir, or
# the real merge-skill.sh would run.
GSD="$TMP/scripts"; mkdir -p "$GSD"
ln -sf "$SCRIPT" "$GSD/check-set-heal.sh"
printf '#!/usr/bin/env bash\necho ran >> "$MERGE_SENTINEL"\nexit 0\n' > "$GSD/merge-skill.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$GSD/pre-open-resolve.sh"
chmod +x "$GSD/merge-skill.sh" "$GSD/pre-open-resolve.sh"
export MERGE_SENTINEL="$TMP/merge-ran"

# Build the runner: the env prologue IS expanded ($GSD resolves) but the extracted
# snippet is written via `printf %s` so its $? / ${...} survive verbatim (an
# unquoted heredoc would command-substitute them at build time).
{
  printf 'set -u\n'
  printf 'SCRIPTS_DIR=%q\n' "$GSD"
  # Everything the extracted region reads and does not itself define. The runner
  # derives the three addresses from one discovery; here they are pinned.
  printf 'PASS_OUT=""\nNOTED=""\nFAILED=""\n'
  printf 'AGENT=%q\n'             'gc-toolkit/gc-toolkit.refinery'
  printf 'CHECK_SET_DEFAULT=%q\n' 'codex'
  printf 'REVIEW_POOL=%q\n'       'gc-toolkit/gc-toolkit.polecat-codex'
  printf 'FIX_POOL=%q\n'          'gc-toolkit/gc-toolkit.polecat'
  printf '%s\n' "$GATE"
  printf 'echo "MERGE_SKILL_HELD=$MERGE_SKILL_HELD"\n'
} > "$TMP/gaterun.sh"

# 6a: stamp FAILS -> real heal exits UNSAFE -> merge-skill is HELD (never runs).
cat > "$TMP/anchors" <<'A'
bead-GATEFAIL|pull_request|EMPTY|420|polecat/feat-gatefail|main||
A
: > "$TMP/reviews"; : > "$TMP/revmeta"; : > "$TMP/stamped"; : > "$TMP/healed"
: > "$TMP/flagged"; : > "$TMP/deps"; echo 'bead-GATEFAIL' > "$TMP/stampfail"
: > "$MERGE_SENTINEL"
GATEOUT="$(bash "$TMP/gaterun.sh" 2>/dev/null)"
[ -s "$MERGE_SENTINEL" ] && bad "(GATE-FAIL) merge-skill RAN despite an unsafe heal — ungated merge NOT prevented" \
                         || ok "(GATE-FAIL) an unsafe heal HELD merge-skill (no merge attempted)"
hasin "$GATEOUT" 'MERGE_SKILL_HELD=1' \
  && ok "(GATE-FAIL) the pass runner recorded MERGE_SKILL_HELD=1" \
  || bad "(GATE-FAIL) the pass runner did not set MERGE_SKILL_HELD (got: $GATEOUT)"

# 6b: stamp SUCCEEDS -> real heal exits 0 -> merge-skill RUNS.
: > "$TMP/reviews"; : > "$TMP/revmeta"; : > "$TMP/stamped"; : > "$TMP/healed"
: > "$TMP/flagged"; : > "$TMP/deps"; : > "$TMP/stampfail"
: > "$MERGE_SENTINEL"
GATEOUT2="$(bash "$TMP/gaterun.sh" 2>/dev/null)"
[ -s "$MERGE_SENTINEL" ] && ok "(GATE-OK) a clean heal lets merge-skill run" \
                         || bad "(GATE-OK) merge-skill did NOT run after a clean heal (got: $GATEOUT2)"
hasin "$GATEOUT2" 'MERGE_SKILL_HELD=0' \
  && ok "(GATE-OK) the pass runner recorded MERGE_SKILL_HELD=0" \
  || bad "(GATE-OK) the pass runner MERGE_SKILL_HELD should be 0 (got: $GATEOUT2)"

# --- Run 7: RE-GATE an ALREADY-NORMALIZED anchor (tk-t46nq). ------------------
# The bug: the satisfiability sweep was reachable only through the heal path, so
# an anchor the formula normalized normally (check_set=codex, no
# check_set_healed) was counted "already normalized" and its marker was never
# examined. A REQUEST_CHANGES signoff CLEARS check.codex and files a rework
# child; when that child lands and is handed back, the anchor holds a normal
# check_set, NO marker, and nothing in flight — and every automated pass looked
# away (this one skipped it; pre-open-resolve.sh can only HOLD; merge-skill.sh
# never sees a pre-open anchor). It parked until a human hand-dispatched the
# re-gate: four times inside one patrol on 2026-08-01.
#
# Fixtures, all with a NORMAL check_set (no healed mark) so every one of them
# would have been skipped outright before this fix:
#   RG-PRE   pre_open_gate, marker ABSENT, nothing in flight  -> DISPATCH (branch)
#   RG-POST  pull_request,  marker ABSENT, nothing in flight  -> DISPATCH (PR)
#   RG-BACK  pre_open_gate, marker ABSENT, rework child HANDED BACK (open,
#            unrouted, sitting on the anchor's branch)        -> DISPATCH
#   RG-WORK  pre_open_gate, marker ABSENT, rework child STILL BEING WORKED
#            (in_progress on the branch)                      -> NO dispatch
#   RG-POOL  pre_open_gate, marker ABSENT, rework child pool-ROUTED, unclaimed
#                                                             -> NO dispatch
#   RG-STALE pre_open_gate, green@OLD but the branch moved     -> DISPATCH
#   RG-FRESH pre_open_gate, green@<live head>                  -> NO dispatch
#   RG-PSTAL pull_request,  green@OLD, head moved -> NO dispatch (that is
#            reconcile-merged-prs.sh's stale-gate arm, which carries merge_hold
#            and one-re-review-per-head guards this pass does not)
#   RG-NOGH  pre_open_gate, green@OLD but the head will NOT resolve -> NO
#            dispatch (fail soft: a marker stays satisfiable without a head)
#   RG-HOLD  pre_open_gate, marker ABSENT, but merge_hold set -> NO dispatch
#            (operator gate; a re-gate is work toward landing, so it honours the
#            same hold reconcile-merged-prs.sh's stale-gate arm honours)
cat > "$TMP/anchors" <<'A'
RG-PRE|pre_open_gate|codex||polecat/rg-pre|main||
RG-POST|pull_request|codex|420|polecat/rg-post|main||
RG-BACK|pre_open_gate|codex||polecat/rg-back|main||
RG-CONV|pre_open_gate|codex||polecat/rg-conv|main||
RG-CBACK|pre_open_gate|codex||polecat/rg-cback|main||
RG-WORK|pre_open_gate|codex||polecat/rg-work|main||
RG-POOL|pre_open_gate|codex||polecat/rg-pool|main||
RG-STALE|pre_open_gate|codex||polecat/rg-stale|main|green@a11a11a|
RG-FRESH|pre_open_gate|codex||polecat/rg-fresh|main|green@c33c33c|
RG-PSTAL|pull_request|codex|421|polecat/rg-pstal|main|green@a11a11a|
RG-NOGH|pre_open_gate|codex||polecat/rg-nogh|main|green@a11a11a|
RG-HOLD|pre_open_gate|codex||polecat/rg-hold|main|||1
RG-HEALHOLD|pre_open_gate|EMPTY||polecat/rg-healhold|main|||1
A
# The branch-resident beads. RG-BACK's child is the exact hand-back shape the
# refinery leaves behind: still OPEN, gc.routed_to cleared, and ASSIGNED BACK to the
# refinery — inert, because the only thing that would re-raise the gate is the
# dispatch this pass is deciding whether to make. The assignee is spelled out rather
# than left blank: it is the field most likely to be mistaken for liveness later, and
# a blank one would let that mistake pass this suite (see the branch probe above).
#
# RG-CONV and RG-CBACK are the two halves of the CONVOY-FIRST dispatch (tk-79zn6),
# and they exist as a PAIR on purpose — either one alone is passable by a wrong fix:
#   rework-conv   a rework being worked RIGHT NOW by a live polecat. Under graph.v2
#                 the work bead itself is never claimed (the polecat claims its STEP
#                 beads), so it sits plain `open`, unassigned, with gc.routed_to
#                 RETIRED at pour and the live route in gc.execution_routed_to. Every
#                 field the old predicate read is empty, which is exactly why it was
#                 dispatched a twin over an unchanged head. MUST suppress.
#   rework-cback  the SAME child after its hand-back: identical execution route, still
#                 open, now assigned to the refinery. MUST NOT suppress — this is
#                 tk-t46nq, and the modelled shape is live bead tk-b5iaq, which carries
#                 gc.execution_routed_to to this day with the refinery as its assignee.
# Together they pin the discriminator to the assignee and nothing else: read the route
# key alone and RG-CBACK parks; keep ignoring it and RG-CONV twins.
cat > "$TMP/branchbeads" <<'B'
rework-back|polecat/rg-back|open|||gc-toolkit/gc-toolkit.refinery|
rework-conv|polecat/rg-conv|open||||gc-toolkit/gc-toolkit.polecat
rework-cback|polecat/rg-cback|open|||gc-toolkit/gc-toolkit.refinery|gc-toolkit/gc-toolkit.polecat
rework-work|polecat/rg-work|in_progress|||gc-toolkit__polecat-lx-88888|
rework-pool|polecat/rg-pool|open||gc-toolkit/gc-toolkit.polecat||
B
# Live heads. RG-STALE/RG-PSTAL moved past a11a11a; RG-FRESH is still at its
# reviewed commit; RG-NOGH is deliberately absent so the stub exits non-zero.
printf 'polecat/rg-stale\tb22b22b\npolecat/rg-fresh\tc33c33c\npolecat/rg-pstal\tb22b22b\n' > "$TMP/heads"
: > "$TMP/reviews"; : > "$TMP/revmeta"; : > "$TMP/stamped"; : > "$TMP/healed"
: > "$TMP/flagged"; : > "$TMP/deps"; : > "$TMP/stampfail"; rm -f "$TMP"/bodies/*
OUT7="$(bash "$SCRIPT" \
  --default 'codex' \
  --review-pool 'gc-toolkit/gc-toolkit.polecat-codex' \
  --fix-pool 'gc-toolkit/gc-toolkit.polecat')"

dispatched_for() { grep -q "	anchor_bead	$1\$" "$TMP/revmeta"; }

dispatched_for RG-PRE \
  && ok "(REGATE) already-normalized PRE-OPEN anchor with no marker re-dispatches the signoff" \
  || bad "(REGATE) pre-open anchor with an absent marker must re-dispatch (got: $(cat "$TMP/revmeta"))"
dispatched_for RG-POST \
  && ok "(REGATE) already-normalized POST-OPEN anchor with no marker re-dispatches the signoff" \
  || bad "(REGATE) post-open anchor with an absent marker must re-dispatch"
# The core regression: a handed-back rework child must NOT suppress the dispatch.
dispatched_for RG-BACK \
  && ok "(HANDBACK) a rework child already handed back does NOT count as in-flight — re-gate dispatched" \
  || bad "(HANDBACK) handed-back rework child wrongly suppressed the re-gate — the tk-t46nq park"
dispatched_for RG-WORK \
  && bad "(INFLIGHT) a rework still in_progress must suppress the dispatch (its branch is about to move)" \
  || ok "(INFLIGHT) rework still being worked -> no dispatch"
dispatched_for RG-POOL \
  && bad "(INFLIGHT) a pool-routed unclaimed rework must suppress the dispatch" \
  || ok "(INFLIGHT) pool-routed rework awaiting a claim -> no dispatch"
# The convoy-first pair (tk-79zn6). RG-CONV is the twin-minting bug: a rework a live
# polecat is working reads inert to the un-widened predicate, because its route moved
# to gc.execution_routed_to. RG-CBACK is the guard that keeps the obvious fix honest.
dispatched_for RG-CONV \
  && bad "(INFLIGHT-CONV) a convoy-dispatched rework (route in gc.execution_routed_to) must suppress the dispatch — this is the twin signoff over an unchanged head" \
  || ok "(INFLIGHT-CONV) convoy-first rework in flight -> no twin dispatch"
dispatched_for RG-CBACK \
  && ok "(HANDBACK-CONV) a convoy-first rework already handed back does NOT count as in-flight — re-gate dispatched" \
  || bad "(HANDBACK-CONV) gc.execution_routed_to survives the hand-back; reading it without the assignee re-parks the gate (tk-t46nq)"
# Marker-vs-live-head, and the ownership split with reconcile-merged-prs.sh.
dispatched_for RG-STALE \
  && ok "(STALE) pre-open marker green at a head that MOVED re-dispatches (no other pass can see it)" \
  || bad "(STALE) stale pre-open marker must re-dispatch"
dispatched_for RG-FRESH \
  && bad "(FRESH) a marker green at the LIVE head must NOT dispatch" \
  || ok "(FRESH) marker green at the live head -> gate satisfiable, no dispatch"
dispatched_for RG-PSTAL \
  && bad "(SPLIT) a stale POST-OPEN marker belongs to reconcile-merged-prs.sh — dispatching here twins it" \
  || ok "(SPLIT) stale post-open marker left to reconcile's stale-gate arm (no twin)"
dispatched_for RG-NOGH \
  && bad "(HEADFAIL) an unresolvable head must fail SOFT — a present marker stays satisfiable" \
  || ok "(HEADFAIL) unresolvable branch head -> present marker treated as satisfiable (no dispatch)"
# THE HOST PIN, asserted on the ARGV of the head read itself (review tk-w9ttd
# finding #1). The behavioural consequence is already covered — the gh stub refuses a
# read that arrives without `--hostname github.com`, so a dropped pin also fails
# (STALE) — but that failure reads as "the stale marker did not re-gate" and points at
# the wrong code. This names the defect directly. It is a REGRESSION, not a
# refinement: `live_head_for` resolved the repo through a command substitution, so
# ORIGIN_HOST was set in a subshell, read back empty in the parent, and
# `${ORIGIN_HOST:+--hostname "$ORIGIN_HOST"}` expanded to NOTHING — the read fell back
# to gh's default host (GH_HOST, or github.com) with no error anywhere.
# `|| true`: this file runs under `set -euo pipefail`, so a grep that matches NOTHING
# fails the pipeline (pipefail) and the assignment aborts the WHOLE suite — turning
# "this assertion failed" into "the remaining assertions never ran", which is the one
# failure mode a regression suite must not have. No match is a legitimate outcome here;
# it is exactly what a regression looks like, and it must be REPORTED.
GH_HEAD_READ=$(grep 'commits/polecat/rg-stale' "$TMP/ghlog" 2>/dev/null | head -1 || true)
[ -n "$GH_HEAD_READ" ] \
  && ok "(PINNED) the marker-vs-head test actually read the branch head through gh" \
  || bad "(PINNED) no gh head read was recorded for RG-STALE"
hasin "$GH_HEAD_READ" '--hostname github.com' \
  && ok "(PINNED) the head read carries the origin HOST pin, not just the o/r path" \
  || bad "(PINNED) live_head_for must pass --hostname from the ORIGIN it resolved; a hostless read answers on whatever host GH_HOST names (got: '$GH_HEAD_READ')"
hasin "$GH_HEAD_READ" 'repos/o/r/commits/' \
  && ok "(PINNED) the head read is pinned to the origin-derived repository" \
  || bad "(PINNED) head read must name repos/o/r (got: '$GH_HEAD_READ')"
# The operator hold, and the deliberate asymmetry between the two paths.
dispatched_for RG-HOLD \
  && bad "(HOLD) a re-gate must honour merge_hold (a review on a held PR is spent quota)" \
  || ok "(HOLD) merge_hold suppresses the re-gate (operator gate)"
dispatched_for RG-HEALHOLD \
  && ok "(HOLD) merge_hold does NOT suppress the HEAL path — an ungated anchor must be armed regardless" \
  || bad "(HOLD) a held-but-UNGATED anchor must still heal+dispatch: it would merge un-reviewed once the hold lifts"
grep -q '^RG-HEALHOLD	codex$' "$TMP/stamped" \
  && ok "(HOLD) the held ungated anchor is still stamped (fail-closed beats the hold)" \
  || bad "(HOLD) held ungated anchor must still be stamped"
# The re-gate path never stamps check_set. RG-HEALHOLD is the only anchor here
# with an un-normalized check_set, so it is the only heal — every other fixture
# arrives already normalized and must leave with its check_set untouched.
hasin "$OUT7" '1 healed' \
  && ok "(REGATE) only the un-normalized anchor heals; re-gates stamp no check_set" \
  || bad "(REGATE) exactly 1 heal expected on the re-gate pass (got: $OUT7)"
STAMPED7=$(cut -f1 "$TMP/stamped" | sort -u | tr '\n' ' ')
eq "$STAMPED7" "RG-HEALHOLD " "(REGATE) no already-normalized anchor was re-stamped"
# The counters separate a re-gate from a heal-path dispatch.
# 6 dispatches, 5 of them re-gates: RG-PRE, RG-POST, RG-BACK, RG-CBACK and RG-STALE
# re-gate; RG-HEALHOLD is the one heal-path dispatch. RG-CONV contributes NOTHING to
# either count — a convoy-first rework in flight is the dispatch that must not happen,
# so this line doubles as the arithmetic proof of (INFLIGHT-CONV): read the route key
# without the assignee and RG-CBACK drops out, making it 5 and 4 again.
hasin "$OUT7" '6 signoffs dispatched (5 of them re-gated)' \
  && ok "(REGATE) the summary counts 5 re-gates distinctly from heals" \
  || bad "(REGATE) summary must report 5 of 6 dispatches re-gated (got: $OUT7)"
# The reviewer is told WHY it was woken — without it a re-gate reads as a
# duplicate of the signoff that already ran. Asserted PER RE-GATED REVIEW and on
# the note's CONTENT: an unscoped `grep review_note` over the whole fixture set
# proves nothing, because it passes as long as ANY one dispatch wrote the key —
# every true re-gate could have lost its reason and the assertion would still be
# green. Scope to a known re-gate (RG-PRE, the absent-marker case; RG-STALE, the
# moved-head case) and require the reason itself.
note_for() { # <anchor> -> the review_note recorded on the review dispatched for it
  local rev
  rev=$(awk -F'\t' -v a="$1" '$2=="anchor_bead" && $3==a{print $1; exit}' "$TMP/revmeta")
  [ -n "$rev" ] || return 0
  awk -F'\t' -v r="$rev" '$1==r && $2=="review_note"{print $3; exit}' "$TMP/revmeta"
}
RGPRE_NOTE="$(note_for RG-PRE)"
RGSTALE_NOTE="$(note_for RG-STALE)"
[ -n "$RGPRE_NOTE" ] \
  && ok "(NOTE) the absent-marker re-gate records a NON-EMPTY review_note" \
  || bad "(NOTE) RG-PRE's re-gate must record a non-empty review_note"
hasin "$RGPRE_NOTE" 'absent' \
  && ok "(NOTE) the absent-marker re-gate's note states the marker was absent" \
  || bad "(NOTE) RG-PRE note must say the marker was absent (got: '$RGPRE_NOTE')"
[ -n "$RGSTALE_NOTE" ] \
  && ok "(NOTE) the stale-marker re-gate records a NON-EMPTY review_note" \
  || bad "(NOTE) RG-STALE's re-gate must record a non-empty review_note"
hasin "$RGSTALE_NOTE" 'a11a11a' && hasin "$RGSTALE_NOTE" 'b22b22b' \
  && ok "(NOTE) the stale-marker re-gate's note names the reviewed OID and the live head" \
  || bad "(NOTE) RG-STALE note must name both shas (got: '$RGSTALE_NOTE')"
# ...and the same reason reaches the bead BODY, not only its metadata. The body is
# what a reviewer actually reads; a reason parked in metadata alone leaves the
# re-gate looking like a duplicate of the signoff that already ran.
RGSTALE_REV=$(awk -F'\t' '$2=="anchor_bead" && $3=="RG-STALE"{print $1; exit}' "$TMP/revmeta")
if [ -n "$RGSTALE_REV" ] && [ -f "$TMP/bodies/$RGSTALE_REV" ]; then
  grep -qF 'Context from the dispatch' "$TMP/bodies/$RGSTALE_REV" \
    && grep -qF 'b22b22b' "$TMP/bodies/$RGSTALE_REV" \
    && ok "(NOTE) the re-gate reason is carried in the review BODY as well as metadata" \
    || bad "(NOTE) the re-gate body must carry the dispatch reason"
else
  bad "(NOTE) no body captured for the RG-STALE re-gate"
fi
# A re-gate is still a real signoff: pre-open reviews the BRANCH, post-open the PR.
grep -q '	review_branch	polecat/rg-pre$' "$TMP/revmeta" \
  && ok "(REGATE) the pre-open re-gate reviews the BRANCH compare-range" \
  || bad "(REGATE) pre-open re-gate must carry review_branch"
RGPOST_REV=$(awk -F'\t' '$2=="anchor_bead" && $3=="RG-POST"{print $1; exit}' "$TMP/revmeta")
grep -q "^$RGPOST_REV	pr_number	420\$" "$TMP/revmeta" \
  && ok "(REGATE) the post-open re-gate reviews the PR" \
  || bad "(REGATE) post-open re-gate must carry pr_number"

# --- Run 8: the re-gate converges. The review dispatched in run 7 is now in
#     flight, so a second pass must not twin it — the same convergence run 2
#     proves for the heal path.
cp "$TMP/revmeta" "$TMP/revmeta.r7"
bash "$SCRIPT" \
  --default 'codex' \
  --review-pool 'gc-toolkit/gc-toolkit.polecat-codex' \
  --fix-pool 'gc-toolkit/gc-toolkit.polecat' >/dev/null
NEW_REGATE=$(comm -13 <(sort -u "$TMP/revmeta.r7") <(sort -u "$TMP/revmeta") | grep -c 'anchor_bead' || true)
eq "$NEW_REGATE" "0" "(REGATE-CONV) the dispatched re-gate is in flight -> no twin on the next pass"

# --- Run 9: LIVE BRANCH OWNERS. ----------------------------------------------
# `closed` is the only status that releases a branch. A child an operator PARKED
# (blocked/deferred), one sitting on an agent's hook, or a pinned one still OWNS
# the branch — reconcile-merged-prs.sh enumerates exactly that set (LIVE_STATUSES)
# before it force-pushes, for the same reason. The re-gate sweep's in-flight probe
# asked only for open,in_progress, so every one of these owners was INVISIBLE to
# it: the pass would dispatch a codex signoff against a branch that is frozen, on
# a hook, or otherwise owned by unresolved rework — reviewing a commit that is not
# final and spending codex quota to do it.
#
# LO-FREE is the control: the handed-back rework shape (status exactly `open`,
# unrouted, not a review) is the ONE live-status bead that is genuinely inert, and
# it must STILL dispatch. Widening the status set must not re-break tk-t46nq.
cat > "$TMP/anchors" <<'A'
LO-BLOCK|pre_open_gate|codex||polecat/lo-block|main||
LO-DEFER|pre_open_gate|codex||polecat/lo-defer|main||
LO-HOOK|pre_open_gate|codex||polecat/lo-hook|main||
LO-PIN|pre_open_gate|codex||polecat/lo-pin|main||
LO-FREE|pre_open_gate|codex||polecat/lo-free|main||
A
# LO-FREE's child carries the refinery assignee for the same reason RG-BACK's does:
# it is the hand-back control, and a blank assignee would make it agree with the
# suppressed cases by accident rather than by rule.
cat > "$TMP/branchbeads" <<'B'
rework-block|polecat/lo-block|blocked|||
rework-defer|polecat/lo-defer|deferred|||
rework-hook|polecat/lo-hook|hooked|||
rework-pin|polecat/lo-pin|pinned|||
rework-free|polecat/lo-free|open|||gc-toolkit/gc-toolkit.refinery
B
: > "$TMP/reviews"; : > "$TMP/revmeta"; : > "$TMP/stamped"; : > "$TMP/healed"
: > "$TMP/flagged"; : > "$TMP/deps"; : > "$TMP/stampfail"; : > "$TMP/heads"
rm -f "$TMP"/bodies/*
bash "$SCRIPT" \
  --default 'codex' \
  --review-pool 'gc-toolkit/gc-toolkit.polecat-codex' \
  --fix-pool 'gc-toolkit/gc-toolkit.polecat' >/dev/null
for owner in BLOCK:blocked DEFER:deferred HOOK:hooked PIN:pinned; do
  a="LO-${owner%%:*}"; st="${owner##*:}"
  dispatched_for "$a" \
    && bad "(LIVEOWN) a $st rework child still owns the branch — no signoff may be dispatched over it" \
    || ok "(LIVEOWN) $st branch owner suppresses the re-gate (branch is not free)"
done
dispatched_for LO-FREE \
  && ok "(LIVEOWN) an OPEN unrouted non-review child is still inert — the re-gate dispatches (tk-t46nq intact)" \
  || bad "(LIVEOWN) widening the status set must NOT re-suppress the handed-back rework case"

# --- Run 10: ROUTE PERSISTENCE + REPAIR. -------------------------------------
# gc.routed_to is what makes a review claimable. Writing it best-effort — without
# reading it back — is the one failure that strands the gate FOREVER: the review is
# created (so the in-flight probe counts it, being a task_kind=review) but no pool
# can claim it, so every later pass suppresses its own dispatch and waits on a bead
# nothing can action. Nothing else owns the pre-open re-gate, so nothing recovers
# it. This is the tk-3xy37 finding, whose repair contract reconcile-merged-prs.sh
# already carries (arm_stale_gate + the unrouted-review repair arm).
#
# 10a: the route write is DROPPED. The dispatch must NOT be reported, and the bead
#      must be left unrouted rather than counted as sent.
cat > "$TMP/anchors" <<'A'
RT-PRE|pre_open_gate|codex||polecat/rt-pre|main||
A
: > "$TMP/reviews"; : > "$TMP/revmeta"; : > "$TMP/stamped"; : > "$TMP/healed"
: > "$TMP/flagged"; : > "$TMP/deps"; : > "$TMP/stampfail"; : > "$TMP/branchbeads"
rm -f "$TMP"/bodies/*
echo 'ALL' > "$TMP/routefail"
RT_ERR="$TMP/rt.err"; RC10=0
OUT10="$(bash "$SCRIPT" \
  --default 'codex' \
  --review-pool 'gc-toolkit/gc-toolkit.polecat-codex' \
  --fix-pool 'gc-toolkit/gc-toolkit.polecat' 2>"$RT_ERR")" || RC10=$?
eq "$RC10" "0" "(ROUTEFAIL) a failed route is best-effort (rc=0): the anchor is gated, not ungated"
dispatched_for RT-PRE \
  && ok "(ROUTEFAIL) the review bead itself was still created and anchored" \
  || bad "(ROUTEFAIL) the review should exist (only its route failed)"
grep -q '	gc.routed_to	' "$TMP/revmeta" \
  && bad "(ROUTEFAIL) the route did not persist — nothing may record it as routed" \
  || ok "(ROUTEFAIL) no route recorded (the write was dropped)"
hasin "$OUT10" '0 signoffs dispatched' \
  && ok "(ROUTEFAIL) an unrouted review is NOT counted as dispatched" \
  || bad "(ROUTEFAIL) must report 0 dispatched (got: $OUT10)"
grep -q "did not durably route" "$RT_ERR" \
  && ok "(ROUTEFAIL) WARNs that the route did not persist" \
  || bad "(ROUTEFAIL) must WARN on a dropped route (got: $(cat "$RT_ERR"))"

# 10b: the next pass REPAIRS it — re-routes the SAME bead, never a twin. Without
#      the repair arm the in-flight probe would find this inert review and skip
#      forever, which is precisely the silent hold.
: > "$TMP/routefail"
cp "$TMP/revmeta" "$TMP/revmeta.r10a"
OUT10B="$(bash "$SCRIPT" \
  --default 'codex' \
  --review-pool 'gc-toolkit/gc-toolkit.polecat-codex' \
  --fix-pool 'gc-toolkit/gc-toolkit.polecat')"
grep -q '	gc.routed_to	gc-toolkit/gc-toolkit.polecat-codex$' "$TMP/revmeta" \
  && ok "(REPAIR) the unrouted signoff is re-routed on the next pass" \
  || bad "(REPAIR) an unrouted signoff must be repaired (got: $(cat "$TMP/revmeta"))"
RT_REVS=$(awk -F'\t' '$2=="anchor_bead" && $3=="RT-PRE"{print $1}' "$TMP/revmeta" | sort -u | wc -l | tr -d ' ')
eq "$RT_REVS" "1" "(REPAIR) the repair re-routes the SAME review — no twin dispatched"
# A repair IS a dispatch: the signoff reaches the pool on this pass, having been
# created on the last one. It is reported as such, and named STRANDED so the log
# says which of the two it was.
hasin "$OUT10B" 'had a STRANDED signoff .* re-routed to' \
  && ok "(REPAIR) the pass names the re-route as a repair of a stranded signoff" \
  || bad "(REPAIR) must report the stranded re-route (got: $OUT10B)"
hasin "$OUT10B" '1 signoffs dispatched' \
  && ok "(REPAIR) the repaired signoff counts as dispatched — it is claimable now" \
  || bad "(REPAIR) must count the repair as 1 dispatched (got: $OUT10B)"

# --- Run 11: MALFORMED MARKERS, re-partitioned by WS4 verb (tk-s8zx3 finding #2,
#     re-derived against WS4 tk-zgse0). ---------------------------------------------
# A non-empty check.codex was treated as "present, therefore satisfiable" unless a
# live-head comparison said otherwise, and that comparison only ran on a `green@<oid>`
# value. So `green`, `red`, `green@` and `green@<not-an-oid>` fell through to the
# satisfiable exit and PARKED — gate armed, no dispatch, no escalation, no merge.
# tk-lzjpd re-gated all four. WS4 then split that set by VERB, and this pass follows the
# split rather than re-gating blindly:
#
#   green / red        NO VERB -> unmappable. reconcile-gate-verdicts.sh records the
#                      terminal exception (R12a) for these LATER in the same wake, so this
#                      pass must NOT dispatch — a review here would be claimed later and
#                      stamp green@ over that exception. reconcile-gate-verdicts.sh's own
#                      header names this pass as the one that must skip it.
#   green@ / green@bad GREEN VERB, malformed oid. It can never equal green@<live head>,
#                      so on a PRE-OPEN anchor it re-gates WITHOUT a head read (tk-lzjpd's
#                      insight, kept inside the green verb). -> DISPATCH.
#   green@bad (POST)   a post-open malformed green@ is reconcile-merged-prs.sh's stale-gate
#                      arm's (it matches green@<non-empty oid>). -> NO dispatch here.
#   green@<live head>  well-formed and current. -> NO dispatch (control).
#
#   MAL-BARE  pre_open_gate, check.codex=green      -> NO dispatch (unmappable)
#   MAL-RED   pull_request,  check.codex=red        -> NO dispatch (unmappable)
#   MAL-AT    pre_open_gate, check.codex=green@     -> DISPATCH (malformed oid, no head)
#   MAL-JUNK  pull_request,  check.codex=green@nope -> NO dispatch (reconcile's stale-gate)
#   MAL-OK    pre_open_gate, green@<live head>      -> NO dispatch (control)
cat > "$TMP/anchors" <<'A'
MAL-BARE|pre_open_gate|codex||polecat/mal-bare|main|green|
MAL-RED|pull_request|codex|430|polecat/mal-red|main|red|
MAL-AT|pre_open_gate|codex||polecat/mal-at|main|green@|
MAL-JUNK|pull_request|codex|431|polecat/mal-junk|main|green@nope|
MAL-OK|pre_open_gate|codex||polecat/mal-ok|main|green@d44d44d|
A
printf 'polecat/mal-ok\td44d44d\n' > "$TMP/heads"
: > "$TMP/reviews"; : > "$TMP/revmeta"; : > "$TMP/stamped"; : > "$TMP/healed"
: > "$TMP/flagged"; : > "$TMP/deps"; : > "$TMP/branchbeads"; : > "$TMP/ghlog"
rm -f "$TMP"/bodies/*
OUT11="$(bash "$SCRIPT" \
  --default 'codex' \
  --review-pool 'gc-toolkit/gc-toolkit.polecat-codex' \
  --fix-pool 'gc-toolkit/gc-toolkit.polecat')"
# No-verb markers are unmappable: this pass leaves them for reconcile-gate-verdicts.sh.
for m in MAL-BARE MAL-RED; do
  dispatched_for "$m" \
    && bad "(MALFORMED) $m names no verb — it is unmappable and must NOT be re-gated here (reconcile-gate-verdicts.sh records its exception)" \
    || ok "(MALFORMED) $m (no verb) -> unmappable, no dispatch (WS4 exception arm owns it)"
done
hasin "$OUT11" "UNMAPPABLE check.codex='green'" \
  && ok "(MALFORMED) the unmappable marker is named and reconcile-gate-verdicts.sh cited as its owner" \
  || bad "(MALFORMED) an unmappable marker must be logged as such (got: $OUT11)"
# A malformed OID under the green verb re-gates on a pre-open anchor, without a head read.
dispatched_for MAL-AT \
  && ok "(MALFORMED) a pre-open green@ with a malformed oid re-gates — it can never equal the head" \
  || bad "(MALFORMED) MAL-AT must re-gate: green@<empty oid> is unmeetable for every head"
# ...and it consulted NO head to decide it: MAL-AT has no entry in $TMP/heads, so a rule
# that needed one would have fallen soft into satisfiable and dispatched nothing.
grep -q 'commits/polecat/mal-at' "$TMP/ghlog" 2>/dev/null \
  && bad "(MALFORMED) the malformed-oid arm must not read the head (it can never match)" \
  || ok "(MALFORMED) MAL-AT re-gated without a head read"
# A post-open malformed green@ belongs to reconcile-merged-prs.sh's stale-gate arm.
dispatched_for MAL-JUNK \
  && bad "(MALFORMED) a POST-OPEN green@<non-oid> is reconcile-merged-prs.sh's stale-gate arm — dispatching here twins it" \
  || ok "(MALFORMED) post-open malformed green@ left to reconcile's stale-gate arm (no twin)"
dispatched_for MAL-OK \
  && bad "(MALFORMED) a WELL-FORMED marker at the live head must still be satisfiable" \
  || ok "(MALFORMED) control: green@<live head> is untouched"
# The reviewer is told which value was rejected — "re-gated" with no reason reads
# as a duplicate of the signoff that already ran.
MALAT_NOTE="$(note_for MAL-AT)"
hasin "$MALAT_NOTE" "hexadecimal form" \
  && ok "(MALFORMED) the re-gate reason names the form the merge gate requires" \
  || bad "(MALFORMED) note must explain the malformed marker (got: '$MALAT_NOTE')"
hasin "$OUT11" '1 of them re-gated' \
  && ok "(MALFORMED) exactly the one pre-open malformed-oid marker re-gates" \
  || bad "(MALFORMED) expected 1 re-gate (got: $OUT11)"

# --- Run 12: a review that cannot raise THIS gate must not suppress it. -------
# (review tk-s8zx3 finding #3.) The in-flight probes key on pr_number and branch,
# which are not this anchor's identity — a review surfaced by them may be about
# something else entirely, and suppressing on one is not a delay but a permanent
# hold, because nothing re-examines the decision. Two mechanically reachable
# shapes, both of which used to park the anchor:
#
#   DEAD-DROP  a review carrying this anchor's pr_number and task_kind=review, but
#              whose anchor_bead write was LOST — it is unrouted and unclaimed, so
#              no polecat can claim it and `repair_review_routing` will not touch
#              it (it cannot be attributed to any anchor). It can never stamp any
#              gate. -> DISPATCH.
#   DEAD-OTHER a review that names ANOTHER anchor while carrying this PR's number.
#              It will stamp that anchor's gate, never this one. -> DISPATCH.
#   DEAD-LIVE  the control: a review that names THIS anchor. -> NO dispatch.
cat > "$TMP/anchors" <<'A'
DEAD-DROP|pull_request|codex|440|polecat/dead-drop|main||
DEAD-OTHER|pull_request|codex|441|polecat/dead-other|main||
DEAD-LIVE|pull_request|codex|442|polecat/dead-live|main||
A
# id|anchor_bead|pr_number|status|assignee — the blank anchor_bead IS the fixture.
cat > "$TMP/reviews" <<'R'
rev-dropped||440|open|
rev-foreign|SOMEONE-ELSE|441|open|
rev-live|DEAD-LIVE|442|open|
R
: > "$TMP/revmeta"; : > "$TMP/stamped"; : > "$TMP/healed"; : > "$TMP/flagged"
: > "$TMP/deps"; : > "$TMP/heads"; : > "$TMP/branchbeads"; rm -f "$TMP"/bodies/*
OUT12="$(bash "$SCRIPT" \
  --default 'codex' \
  --review-pool 'gc-toolkit/gc-toolkit.polecat-codex' \
  --fix-pool 'gc-toolkit/gc-toolkit.polecat')"
dispatched_for DEAD-DROP \
  && ok "(DEADREV) a review whose anchor_bead was lost is inert — it does not suppress the re-gate" \
  || bad "(DEADREV) DEAD-DROP must re-gate: nothing can route, claim or attribute that review"
dispatched_for DEAD-OTHER \
  && ok "(DEADREV) a review naming ANOTHER anchor does not hold this one's gate" \
  || bad "(DEADREV) DEAD-OTHER must re-gate: that review stamps somebody else's anchor"
dispatched_for DEAD-LIVE \
  && bad "(DEADREV) a review that names THIS anchor must still suppress the dispatch (no twins)" \
  || ok "(DEADREV) control: a review naming this anchor is in flight — no twin dispatched"
hasin "$OUT12" '2 of them re-gated' \
  && ok "(DEADREV) exactly the two unactionable reviews are re-gated past" \
  || bad "(DEADREV) expected 2 re-gates (got: $OUT12)"

# --- Run 13: TERMINAL PRs are not re-gated (review tk-w9ttd finding #2). ------
# This pass runs BEFORE reconcile-merged-prs.sh in the same patrol, and the widened
# satisfiability sweep reaches post-open anchors it never used to examine. An ABSENT
# marker is the NORMAL shape behind a MERGED PR — the signoff that cleared it has
# nothing left to re-stamp — so without a state check the sweep dispatches a codex
# review, in real quota, for a pull request nobody can merge, and routes an inert
# review child into the codex pool ahead of the observer that was about to close the
# anchor. Same for a PR an operator CLOSED out of band, which needs an escalation,
# not a reviewer.
#
#   TP-MERGED  pull_request, marker ABSENT, PR MERGED   -> NO dispatch
#   TP-CLOSED  pull_request, marker ABSENT, PR CLOSED   -> NO dispatch
#   TP-MALF    pull_request, marker green@ (malformed oid), PR MERGED -> NO dispatch.
#              A post-open malformed green@ never reaches the terminal guard: it exits at
#              the post-open satisfiable path (reconcile-merged-prs.sh's stale-gate arm
#              owns green@<non-oid> post-open), so it is not re-gated regardless of PR
#              state. Kept here as the cross-check that no post-open green@ is dispatched.
#   TP-OPEN    pull_request, marker ABSENT, PR OPEN     -> DISPATCH (the control:
#              the guard must not suppress the case tk-t46nq exists to fix)
#   TP-UNREAD  pull_request, marker ABSENT, PR state UNREADABLE -> DISPATCH. The
#              guard fails SOFT in the dispatch direction on purpose: one wasted
#              review that reconcile disposes of the same pass is cheaper than
#              re-creating the park, and a gh-less rig must behave exactly as it did
#              before the guard existed.
#   TP-PRE     pre_open_gate, marker ABSENT             -> DISPATCH (no PR to be
#              terminal; the guard must not touch the pre-open path at all)
cat > "$TMP/anchors" <<'A'
TP-MERGED|pull_request|codex|450|polecat/tp-merged|main||
TP-CLOSED|pull_request|codex|451|polecat/tp-closed|main||
TP-MALF|pull_request|codex|452|polecat/tp-malf|main|green@|
TP-OPEN|pull_request|codex|453|polecat/tp-open|main||
TP-UNREAD|pull_request|codex|454|polecat/tp-unread|main||
TP-PRE|pre_open_gate|codex||polecat/tp-pre|main||
A
# number<TAB>state<TAB>headRefName. TP-UNREAD is deliberately ABSENT so the view
# fails — the unreadable-state fixture. The head refs match each anchor's branch
# because certify_pr_identity refuses a PR opened from another branch, and a
# certification that failed for THAT reason would take the fail-soft arm and prove
# nothing about the states below.
printf '450\tMERGED\tpolecat/tp-merged\n451\tCLOSED\tpolecat/tp-closed\n452\tMERGED\tpolecat/tp-malf\n453\tOPEN\tpolecat/tp-open\n' > "$TMP/prs"
: > "$TMP/reviews"; : > "$TMP/revmeta"; : > "$TMP/stamped"; : > "$TMP/healed"
: > "$TMP/flagged"; : > "$TMP/deps"; : > "$TMP/heads"; : > "$TMP/branchbeads"
: > "$TMP/ghlog"; rm -f "$TMP"/bodies/*
OUT13="$(bash "$SCRIPT" \
  --default 'codex' \
  --review-pool 'gc-toolkit/gc-toolkit.polecat-codex' \
  --fix-pool 'gc-toolkit/gc-toolkit.polecat' 2>"$TMP/err13")"
dispatched_for TP-MERGED \
  && bad "(TERMINAL) a MERGED PR must not be re-gated — the review lands on work nobody can merge, ahead of the observer that closes the anchor" \
  || ok "(TERMINAL) merged PR -> no signoff dispatched (reconcile-merged-prs.sh disposes of it)"
dispatched_for TP-CLOSED \
  && bad "(TERMINAL) a CLOSED PR must not be re-gated — it needs an escalation, not a reviewer" \
  || ok "(TERMINAL) closed PR -> no signoff dispatched"
dispatched_for TP-MALF \
  && bad "(TERMINAL) a post-open green@<non-oid> must not be re-gated here — it is reconcile-merged-prs.sh's stale-gate arm's" \
  || ok "(TERMINAL) post-open malformed green@ on a merged PR -> still no dispatch"
dispatched_for TP-OPEN \
  && ok "(TERMINAL) control: an OPEN PR with an absent marker still re-gates" \
  || bad "(TERMINAL) the guard must NOT suppress an open PR — that is the tk-t46nq park"
dispatched_for TP-UNREAD \
  && ok "(TERMINAL) an unreadable PR state fails SOFT — the signoff is dispatched anyway" \
  || bad "(TERMINAL) suppressing on an unreadable state re-creates the park this sweep ends"
dispatched_for TP-PRE \
  && ok "(TERMINAL) a pre-open anchor has no PR to be terminal — re-gate unaffected" \
  || bad "(TERMINAL) the terminal-PR guard must not touch the pre-open path"
hasin "$OUT13" '3 of them re-gated' \
  && ok "(TERMINAL) exactly the three non-terminal anchors re-gate" \
  || bad "(TERMINAL) expected 3 re-gates (got: $OUT13)"
# The operator is TOLD why the anchor was passed over, and who owns it now — a
# silent skip on a gating anchor is indistinguishable from the park.
hasin "$OUT13" 'TP-MERGED (PR#450) needs a re-gate.*MERGED' \
  && ok "(TERMINAL) the skip names the anchor, the PR and its terminal state" \
  || bad "(TERMINAL) the skip must be logged with the PR state (got: $OUT13)"
hasin "$OUT13" 'reconcile-merged-prs.sh' \
  && ok "(TERMINAL) the skip names the pass that owns the disposition" \
  || bad "(TERMINAL) the skip must say which pass disposes of the anchor"
grep -q 'TP-UNREAD.*dispatching the signoff anyway' "$TMP/err13" \
  && ok "(TERMINAL) the fail-soft dispatch says what it did about the unreadable state" \
  || bad "(TERMINAL) an unreadable state must warn AND say the signoff went out anyway (got: $(cat "$TMP/err13"))"
# The state read is PINNED, exactly as the head read is: `gh pr view <n> --repo
# <host>/<owner>/<repo>`. Unpinned, the number answers in whatever repository gh
# considers current, and a FOREIGN closed PR would suppress a signoff this anchor
# genuinely needs — a park caused by the very guard meant to prevent waste.
GH_PR_READ=$(grep '^pr view 450' "$TMP/ghlog" 2>/dev/null | head -1 || true)   # see (PINNED)
hasin "$GH_PR_READ" '--repo github.com/o/r' \
  && ok "(TERMINAL) the PR state read is pinned host-qualified to this checkout's origin" \
  || bad "(TERMINAL) certify_pr_identity must pin the state read (got: '$GH_PR_READ')"
# A pre-open anchor must not cost a PR read at all — it has no PR.
grep -q 'pr view.*polecat/tp-pre' "$TMP/ghlog" 2>/dev/null \
  && bad "(TERMINAL) a pre-open anchor must not trigger a PR state read" \
  || ok "(TERMINAL) no PR read is made for the pre-open anchor"

# --- Run 5c: REUSING an in-flight signoff is a claim about REACHABILITY, and it
#     has to be checked (review tk-tbacg P2). ------------------------------------
# `inflight_for` answers "a review for this anchor already exists", and the pass
# then skips the dispatch on that answer alone. `repair_review_routing` covers ONE
# unreachable shape — open + unclaimed + `gc.routed_to` empty + task_kind=review +
# anchor_bead — and everything outside it fell through to "already in flight, no
# dispatch" and was believed forever.
#
# That is exactly what the route read-back leaves behind on its unreadable arm: the
# route write is lost AND the verification read fails, so the dispatch declines to
# close the bead (closing a possibly-claimed review is the worse error) and leaves
# it open. Every later pass finds it, counts the gate as covered by a review nobody
# can claim, and never mints a replacement — the armed gate holds the merge forever
# while the dispatch counter says a signoff went out.
reuse_run() { # <reviews-fixture> <revmeta-fixture> [revshowfail] [dropkey] -> OUT
  cat > "$TMP/anchors" <<'A'
bead-REUSE|pull_request|EMPTY|431|polecat/feat-reuse|main||
A
  : > "$TMP/stamped"; : > "$TMP/healed"; : > "$TMP/flagged"; : > "$TMP/deps"
  : > "$TMP/stampfail"; : > "$TMP/closed"
  printf '%s' "$1" > "$TMP/reviews"
  printf '%s' "$2" > "$TMP/revmeta"
  # [dropkey] is the same one-key write-drop $FAKE_DROPKEY models for the dispatch
  # (route_run): the repair paths write the route in one update whose halves persist
  # independently, so a repair that reports success without reading BOTH back is the
  # same unverified write, one arm further along.
  FAKE_REVSHOWFAIL="${3:-}" FAKE_DROPKEY="${4:-}" bash "$SCRIPT" \
    --default 'codex' \
    --review-pool 'gc-toolkit/gc-toolkit.polecat-codex' \
    --fix-pool 'gc-toolkit/gc-toolkit.polecat' 2>&1
}
POOL_C='gc-toolkit/gc-toolkit.polecat-codex'
# Did the run record this exact <id, key, value> in the review ledger? Field-split on
# the recorded TSV rather than matching a line, so a value that itself contains
# whitespace cannot be read as a match on a shorter one.
revmeta_is() { # <review-id> <key> <value>
  awk -F'\t' -v i="$1" -v k="$2" -v v="$3" \
    '$1==i && $2==k && $3==v {found=1} END {exit !found}' "$TMP/revmeta" 2>/dev/null
}

# (REUSE-INERT) the review exists, is open, and is offered to NOBODY: no
# gc.routed_to, no assignee, no durable copy. Believing it holds the gate forever.
OUT5H="$(reuse_run 'rev-inert|bead-REUSE|431
' '')"
hasin "$OUT5H" 'INERT in-flight signoff rev-inert' \
  && ok "(REUSE-INERT) an unreachable in-flight signoff is DETECTED, not believed" \
  || bad "(REUSE-INERT) reusing a signoff nobody can claim must be caught (got: $OUT5H)"
grep -q "^rev-inert	gc.routed_to	$POOL_C$" "$TMP/revmeta" \
  && ok "(REUSE-INERT) it is re-routed to the review pool rather than left inert" \
  || bad "(REUSE-INERT) the reused review must be re-offered to a pool (revmeta: $(cat "$TMP/revmeta"))"
grep -q "^rev-inert	review_pool	$POOL_C$" "$TMP/revmeta" \
  && ok "(REUSE-INERT) and its DURABLE route copy is written with it" \
  || bad "(REUSE-INERT) the durable copy must be restored alongside the live route"
[ -s "$TMP/closed" ] \
  && bad "(REUSE-INERT) an existing review must be repaired, never closed out from under its anchor" \
  || ok "(REUSE-INERT) the review is repaired in place, not closed"

# (REUSE-INERT-OPERATOR) the same inert review, but its durable copy names a
# DIFFERENT pool — an operator's deliberate re-route. The repair must re-offer it
# through THAT pool, not silently drag it back to this pass's default. Reachability
# is what reuse needs; which pool is the operator's call.
OUT5I="$(reuse_run 'rev-elsewhere|bead-REUSE|431
' 'rev-elsewhere	review_pool	other-rig/other.polecat-codex
')"
grep -q '^rev-elsewhere	gc.routed_to	other-rig/other.polecat-codex$' "$TMP/revmeta" \
  && ok "(REUSE-INERT-OPERATOR) an inert review is re-offered through the pool its durable copy names" \
  || bad "(REUSE-INERT-OPERATOR) the operator's pool must win over this pass's default (got: $OUT5I)"

# (REUSE-CLAIMED-DURABLE) the review is CLAIMED — reachable, and none of this
# pass's business to re-offer — but its durable copy is missing. It is fine now and
# strands later: a signoff that ends without stamping the gate has to put the review
# back in a pool, and review_pool is the only field left that says which one. Repair
# the durable half; never touch the live half of a claimed bead.
OUT5J="$(reuse_run 'rev-claimed|bead-REUSE|431
' 'rev-claimed	gc.routed_to	'"$POOL_C"'
rev-claimed	assignee	gc-toolkit__polecat-codex-lx-1
')"
grep -q "^rev-claimed	review_pool	$POOL_C$" "$TMP/revmeta" \
  && ok "(REUSE-CLAIMED-DURABLE) a claimed review's missing durable route copy is restored" \
  || bad "(REUSE-CLAIMED-DURABLE) the durable copy must be repaired (revmeta: $(cat "$TMP/revmeta"))"
hasin "$OUT5J" '0 signoffs dispatched' \
  && ok "(REUSE-CLAIMED-DURABLE) a claimed review still counts as in flight — no twin is minted" \
  || bad "(REUSE-CLAIMED-DURABLE) repairing the durable copy must not mint a second review (got: $OUT5J)"
[ -s "$TMP/closed" ] \
  && bad "(REUSE-CLAIMED-DURABLE) a CLAIMED review must never be closed" \
  || ok "(REUSE-CLAIMED-DURABLE) the claimed review is left with its reviewer"

# (REUSE-UNREADABLE) the reused review cannot be READ at all. Unverified is not
# verified: it must not be counted as covering the gate, and it must not be replaced
# either — a twin for an anchor that may already have a live signoff is the
# duplicate dispatch the dedup exists to prevent. Hold, warn, retry next pass.
OUT5K="$(reuse_run 'rev-dark|bead-REUSE|431
' '' 'rev-dark')"
hasin "$OUT5K" 'route could not be VERIFIED' \
  && ok "(REUSE-UNREADABLE) an unreadable in-flight signoff is reported, not believed" \
  || bad "(REUSE-UNREADABLE) an unreadable reuse must warn (got: $OUT5K)"
hasin "$OUT5K" '0 signoffs dispatched' \
  && ok "(REUSE-UNREADABLE) and no twin signoff is minted for it" \
  || bad "(REUSE-UNREADABLE) an unreadable reuse must not mint a replacement (got: $OUT5K)"
[ -s "$TMP/closed" ] \
  && bad "(REUSE-UNREADABLE) an unreadable review must never be closed" \
  || ok "(REUSE-UNREADABLE) the unreadable review is left exactly as it was"

# --- Run 5d: the STRANDED-signoff fast path writes BOTH halves of the route
#     (review tk-8x7mv P1). --------------------------------------------------------
# `repair_review_routing` runs BEFORE the reuse validation above and `continue`s on
# success, so nothing downstream ever sees what it leaves behind. It wrote
# `gc.routed_to` alone — the only write site in this script that wrote one half of
# the pair — and that reads as harmless, because the review IS claimable when the
# pass ends.
#
# It strands on the NEXT step. A claim consumes `gc.routed_to`, so the repair
# predicate (open + unclaimed + unrouted) stops matching and no later pass looks at
# the bead again; `review_pool` is the only field left that says which pool the
# review came from, and it is absent. The first signoff that ends with the gate
# UNRECORDED then releases the review open, unassigned and in NO pool — offered to
# nobody, gate armed, owed by nobody. The repair rebuilds the exact silent hold the
# repair exists to end, which is why the cases below assert the PAIR and not just
# reachability.
#
# (STRANDED-PAIR) both halves absent on a bead `bd show` reads as a review for THIS
# anchor: the one shape the fast path claims.
OUT5L="$(reuse_run 'rev-stranded|bead-REUSE|431
' $'rev-stranded\ttask_kind\treview\nrev-stranded\tanchor_bead\tbead-REUSE\n')"
hasin "$OUT5L" 'had a STRANDED signoff rev-stranded' \
  && ok "(STRANDED-PAIR) a stranded signoff is answered by the fast path, not by the reuse arm" \
  || bad "(STRANDED-PAIR) the fast path must repair the stranded review (got: $OUT5L)"
revmeta_is 'rev-stranded' 'gc.routed_to' "$POOL_C" \
  && ok "(STRANDED-PAIR) the live offer is restored" \
  || bad "(STRANDED-PAIR) the repair must re-offer the review (revmeta: $(cat "$TMP/revmeta"))"
revmeta_is 'rev-stranded' 'review_pool' "$POOL_C" \
  && ok "(STRANDED-PAIR) and the DURABLE copy is written with it — the claim eats the live half, and this is the only field a signoff can restore the route from" \
  || bad "(STRANDED-PAIR) review_pool must be written alongside gc.routed_to (revmeta: $(cat "$TMP/revmeta"))"
hasin "$OUT5L" '1 signoffs dispatched' \
  && ok "(STRANDED-PAIR) a verified repair counts as the dispatch it is" \
  || bad "(STRANDED-PAIR) the repaired signoff must count as dispatched (got: $OUT5L)"
[ -s "$TMP/closed" ] \
  && bad "(STRANDED-PAIR) a stranded review is repaired in place, never closed" \
  || ok "(STRANDED-PAIR) the review is repaired in place, not closed"

# (STRANDED-PAIR-OPERATOR) the same stranded shape, except the durable copy names a
# DIFFERENT pool. `review_pool` is never consumed, so a non-empty value is somebody's
# deliberate route — an operator's re-route, or the pool an earlier pass dispatched
# to — while `--review-pool` is only what this invocation was handed. Stamping the
# default over it SPLITS the route (durable copy A, live offer B), which is the shape
# `route_ok` rejects as unverified: pool A is woken with nothing to claim while pool B
# is offered a review minted for A. Same precedence, same reason, as the INERT
# re-offer's `${REUSE_POOL:-$REVIEW_POOL}` above.
POOL_OP='other-rig/other.polecat-codex'
OUT5M="$(reuse_run 'rev-stranded-op|bead-REUSE|431
' $'rev-stranded-op\ttask_kind\treview\nrev-stranded-op\tanchor_bead\tbead-REUSE\nrev-stranded-op\treview_pool\t'"$POOL_OP"$'\n')"
revmeta_is 'rev-stranded-op' 'gc.routed_to' "$POOL_OP" \
  && ok "(STRANDED-PAIR-OPERATOR) a stranded review is re-offered through the pool its durable copy names" \
  || bad "(STRANDED-PAIR-OPERATOR) the operator's pool must win over this pass's default (revmeta: $(cat "$TMP/revmeta"))"
revmeta_is 'rev-stranded-op' 'gc.routed_to' "$POOL_C" \
  && bad "(STRANDED-PAIR-OPERATOR) the live offer must not be split away from the durable copy" \
  || ok "(STRANDED-PAIR-OPERATOR) the route is not split — nothing is offered to this pass's default pool"
hasin "$OUT5M" "re-routed to $POOL_OP" \
  && ok "(STRANDED-PAIR-OPERATOR) and the pass names the pool that now holds the offer" \
  || bad "(STRANDED-PAIR-OPERATOR) the log (and the wake) must name the pool actually routed to (got: $OUT5M)"

# (STRANDED-PAIR-UNVERIFIED) the pair goes out in ONE update whose halves persist
# independently — the same transient the dispatch's read-back exists to catch. Here
# the DURABLE half is dropped. Reporting success on it would `continue` past the only
# block that can still restore that half, leaving the missing-review_pool strand
# behind while the counter says a signoff went out. So the repair must fail its
# read-back, fall through, and let the reuse arm say what is wrong.
OUT5N="$(reuse_run 'rev-halfwrite|bead-REUSE|431
' $'rev-halfwrite\ttask_kind\treview\nrev-halfwrite\tanchor_bead\tbead-REUSE\n' '' 'review_pool')"
hasin "$OUT5N" 'had a STRANDED signoff rev-halfwrite' \
  && bad "(STRANDED-PAIR-UNVERIFIED) a half-landed repair must not be reported as a re-route" \
  || ok "(STRANDED-PAIR-UNVERIFIED) the repair reads both halves back and does not claim success on one"
hasin "$OUT5N" 'DURABLE route copy (review_pool) is missing' \
  && ok "(STRANDED-PAIR-UNVERIFIED) it falls through to the reuse arm, which reports the missing durable copy" \
  || bad "(STRANDED-PAIR-UNVERIFIED) the unrestorable durable copy must be WARNed about (got: $OUT5N)"
hasin "$OUT5N" '0 signoffs dispatched' \
  && ok "(STRANDED-PAIR-UNVERIFIED) an unverified repair is not counted as a dispatch" \
  || bad "(STRANDED-PAIR-UNVERIFIED) must not count a repair whose route did not verify (got: $OUT5N)"

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
