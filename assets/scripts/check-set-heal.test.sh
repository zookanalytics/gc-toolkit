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
#   (GATE)   the REAL formula wiring (heal-gates-merge, extracted from
#            mol-refinery-patrol.toml): a stamp-failing heal (rc=UNSAFE_RC) HOLDS
#            the merge-skill stub (no merge attempted); a clean heal lets it run.
#            This is the review tk-z4u2e finding #1 regression — a failed stamp used
#            to fall through to merge-skill in the SAME pass and merge un-reviewed.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/check-set-heal.sh"
ROOT="$(cd "$HERE/../.." && pwd)"
TOML="$ROOT/formulas/mol-refinery-patrol.toml"
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
# helper, same reasoning, as merge-skill.test.sh's.
hasin() { grep -q "$2" <<< "$1"; }

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
bead-NORMAL|pull_request|codex|406|polecat/feat-normal|main|green@HEAD406|
bead-GREEN|pull_request|EMPTY|407|polecat/feat-green|main|green@HEAD407|
bead-INFLGT|pull_request|EMPTY|408|polecat/feat-inflgt|main||
bead-PREOPEN|pre_open_gate|EMPTY||polecat/feat-preopen|main||
A

# An open review already referencing bead-INFLGT (so the heal must NOT dispatch a
# twin). Format: review_id|anchor_bead|pr_number. The inflight lookup finds it via
# the pr_number and anchor_bead branches of inflight_for.
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

case "$2" in
  list)
    case "$*" in
      *"merge_result=pull_request"*|*"merge_result=pre_open_gate"*)
        want=$(printf '%s' "$*" | sed -n 's/.*merge_result=\([a-z_]*\).*/\1/p')
        out=""
        while IFS='|' read -r id mr cs pr branch target codex healed; do
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
          prfield=""; [ -n "$pr" ] && prfield=$(printf ',"pr_number":"%s","pr_url":"https://x/pull/%s"' "$pr" "$pr")
          obj=$(printf '{"id":"%s","title":"impl %s","metadata":{"merge_result":"%s","branch":"%s","merged_target":"%s"%s%s%s%s%s}}' \
            "$id" "$id" "$mr" "$branch" "$target" "$csfield" "$cxfield" "$hfield" "$flfield" "$prfield")
          if [ -z "$out" ]; then out="$obj"; else out="$out,$obj"; fi
        done < "$FAKE_ANCHORS"
        printf '[%s]\n' "$out" ;;
      *"pr_number="*)
        pnum=$(printf '%s' "$*" | sed -n 's/.*pr_number=\([0-9][0-9]*\).*/\1/p')
        rid=$(awk -F'|' -v p="$pnum" '$3==p{print $1; exit}' "$FAKE_REVIEWS" 2>/dev/null)
        if [ -n "$rid" ]; then printf '[{"id":"%s"}]\n' "$rid"; else printf '[]\n'; fi ;;
      *"anchor_bead="*)
        aid=$(printf '%s' "$*" | sed -n 's/.*anchor_bead=\([^ ]*\).*/\1/p')
        rid=$(awk -F'|' -v a="$aid" '$2==a{print $1; exit}' "$FAKE_REVIEWS" 2>/dev/null)
        # Also honour a review minted THIS run (recorded in FAKE_REVMETA).
        [ -n "$rid" ] || rid=$(awk -F'\t' -v a="$aid" '$2=="anchor_bead" && $3==a{print $1; exit}' "$FAKE_REVMETA" 2>/dev/null)
        if [ -n "$rid" ]; then printf '[{"id":"%s"}]\n' "$rid"; else printf '[]\n'; fi ;;
      *"branch="*)
        br=$(printf '%s' "$*" | sed -n 's/.*branch=\([^ ]*\).*/\1/p')
        # No standalone branch-keyed reviews in fixtures; return empty.
        printf '[]\n' ;;
      *) printf '[]\n' ;;
    esac ;;
  show)
    id="$3"
    # A bead whose `gc bd show` answers NOTHING — the unreadable read, as distinct
    # from a bead that reads cleanly and says something bad. The route read-back and
    # the REUSE validation both have to tell those apart: unreadable is not proof of
    # a broken route, and acting on it (closing the bead, re-routing it, or counting
    # it as sufficient) is how a live signoff gets erased or duplicated.
    case " ${FAKE_REVSHOWFAIL:-} " in *" $id "*) exit 0 ;; esac
    cs=$(cs_for "$id"); [ "$cs" = "EMPTY" ] || [ "$cs" = "__ABSENT__" ] && cs=""
    # check_set_healed as the STAMP READ-BACK sees it. Modelled separately from
    # check_set because the two persist independently: the script writes them in one
    # call and verifies each, so the half-landed write (gate armed, retry mark lost)
    # has to be representable here or the regression cannot stage it.
    hl=$(healed_for "$id")
    [ -n "$hl" ] || hl=$(awk -F'|' -v i="$id" '$1==i{print $8; exit}' "$FAKE_ANCHORS" 2>/dev/null)
    # The FALLBACK retry mark, as the read-back sees it. Modelled here for the same
    # reason check_set_healed is: the script now re-reads it after writing it, so a
    # dropped flag write has to be representable or the regression cannot stage the
    # both-marks-lost case.
    fl=""
    grep -qx "$id" "$FAKE_FLAGGED" 2>/dev/null && fl="1"
    # anchor_bead recorded on a review this run?
    ab=$(awk -F'\t' -v i="$id" '$1==i && $2=="anchor_bead"{print $3; exit}' "$FAKE_REVMETA" 2>/dev/null)
    # The ROUTE the dispatch wrote, as the read-back sees it. LAST write wins, so
    # the script's one repair attempt is visible here.
    rp=$(awk -F'\t' -v i="$id" '$1==i && $2=="review_pool"{v=$3} END{print v}' "$FAKE_REVMETA" 2>/dev/null)
    rt=$(awk -F'\t' -v i="$id" '$1==i && $2=="gc.routed_to"{v=$3} END{print v}' "$FAKE_REVMETA" 2>/dev/null)
    as=""
    # $FAKE_CLAIMED models a pool polecat claiming the review the INSTANT it was
    # routed: gc.routed_to is CONSUMED (a claim eats it) and an assignee appears.
    # The read-back must read that as reachable, not as a lost route — re-routing
    # a claimed review would offer it to a second pool.
    if [ -n "${FAKE_CLAIMED:-}" ] && [ -n "$rt" ]; then as="$rt"; rt=""; fi
    # A review that arrived at this pass ALREADY claimed (staged directly in
    # $FAKE_REVMETA rather than claimed mid-run), for the reuse cases: the pass finds
    # an in-flight review a polecat is holding and must never re-offer it.
    [ -n "$as" ] || as=$(awk -F'\t' -v i="$id" '$1==i && $2=="assignee"{v=$3} END{print v}' "$FAKE_REVMETA" 2>/dev/null)
    jq -n --arg cs "$cs" --arg hl "$hl" --arg ab "$ab" --arg rp "$rp" --arg rt "$rt" --arg as "$as" \
          --arg fl "$fl" \
      '[{assignee: (if $as=="" then null else $as end),
         metadata: ({} + (if $cs=="" then {} else {check_set:$cs} end)
                       + (if $hl=="" then {} else {check_set_healed:$hl} end)
                       + (if $fl=="" then {} else {check_set_heal_flagged:$fl} end)
                       + (if $ab=="" then {} else {anchor_bead:$ab} end)
                       + (if $rp=="" then {} else {review_pool:$rp} end)
                       + (if $rt=="" then {} else {"gc.routed_to":$rt} end))}]' ;;
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
    # Record review metadata (anchor_bead, routing, task_kind, review_branch).
    # $FAKE_DROPKEY names ONE key whose write is silently DISCARDED — the
    # "update returned success but nothing landed" transient that the route
    # read-back exists to catch. Dropping `gc.routed_to` and `review_pool`
    # separately is what distinguishes an unclaimable review from one whose
    # signoff can no longer restore its route.
    for k in anchor_bead gc.routed_to review_pool task_kind review_branch pr_number fix_target_pool; do
      [ "$k" = "${FAKE_DROPKEY:-}" ] && continue
      if grep -q -- "--set-metadata $k=" <<< "$*"; then
        v=$(printf '%s' "$*" | sed -n "s/.*--set-metadata $k=\\([^ ]*\\).*/\\1/p")
        # $FAKE_STALE_ROUTE models a SPLIT route: the batched update persists
        # review_pool for THIS pool while gc.routed_to keeps an OLDER pool's
        # value. Not a dropped write — a write whose live half never took — so
        # the read-back sees a perfectly non-empty gc.routed_to that offers the
        # review to somebody else entirely.
        if [ "$k" = "gc.routed_to" ] && [ -n "${FAKE_STALE_ROUTE:-}" ]; then
          v="$FAKE_STALE_ROUTE"
        fi
        printf '%s\t%s\t%s\n' "$id" "$k" "$v" >> "$FAKE_REVMETA"
      fi
    done ;;
  dep)
    # gc bd dep <review> --blocks <anchor>
    rev="$3"; anchor=$(printf '%s' "$*" | sed -n 's/.*--blocks \([^ ]*\).*/\1/p')
    printf '%s\t%s\n' "$rev" "$anchor" >> "$FAKE_DEPS" ;;
esac
exit 0
GC
chmod +x "$TMP/bin/gc"

: > "$TMP/stamped"; : > "$TMP/healed"; : > "$TMP/flagged"; : > "$TMP/revmeta"
: > "$TMP/deps"; : > "$TMP/stampfail"; : > "$TMP/healfail"; : > "$TMP/closed"
: > "$TMP/flagfail"; : > "$TMP/flagtries"; echo 0 > "$TMP/seq"
mkdir -p "$TMP/bodies"

export PATH="$TMP/bin:$PATH"
export FAKE_ANCHORS="$TMP/anchors" FAKE_REVIEWS="$TMP/reviews" \
       FAKE_STAMPED="$TMP/stamped" FAKE_HEALED="$TMP/healed" \
       FAKE_FLAGGED="$TMP/flagged" FAKE_REVMETA="$TMP/revmeta" FAKE_DEPS="$TMP/deps" \
       FAKE_STAMPFAIL="$TMP/stampfail" FAKE_HEALFAIL="$TMP/healfail" \
       FAKE_FLAGFAIL="$TMP/flagfail" FAKE_FLAGTRIES="$TMP/flagtries" \
       FAKE_SEQ="$TMP/seq" FAKE_CLOSED="$TMP/closed" FAKE_BODIES="$TMP/bodies"

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

# Summary: 6 healed (EMPTY, ABSENT, SEP, GREEN, INFLGT, PREOPEN), and the opt-outs
# / normal untouched.
hasin "$OUT1" '6 healed' \
  && ok "run 1 summary reports 6 healed" || bad "run 1 summary healed count (got: $OUT1)"
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

# --- Run 4c: HEALDEFER. The state a deferred partial write leaves behind —
#     check_set normalized, check_set_healed absent — proving the deferral this
#     script must not do. Nothing here is broken-looking: the anchor reads
#     "already normalized" and is skipped, while its codex gate has no marker and
#     no review. This is why 4b dispatches in-pass instead of trusting "next pass".
cat > "$TMP/anchors" <<'A'
bead-DEFER|pull_request|codex|413|polecat/feat-defer|main||
A
: > "$TMP/reviews"; : > "$TMP/revmeta"; : > "$TMP/stamped"; : > "$TMP/healed"
: > "$TMP/flagged"; : > "$TMP/deps"; : > "$TMP/stampfail"; : > "$TMP/healfail"
OUT4C="$(bash "$SCRIPT" \
  --default 'codex' \
  --review-pool 'gc-toolkit/gc-toolkit.polecat-codex' \
  --fix-pool 'gc-toolkit/gc-toolkit.polecat' 2>&1)"
hasin "$OUT4C" '0 signoffs dispatched' \
  && ok "(HEALDEFER) an anchor whose healed mark was lost is never re-dispatched by a later pass" \
  || bad "(HEALDEFER) fixture must show the deferral is a dead end (got: $OUT4C)"
hasin "$OUT4C" '1 already normalized' \
  && ok "(HEALDEFER) it is classified 'already normalized' — invisible to the retry" \
  || bad "(HEALDEFER) lost-mark anchor must classify as normalized (got: $OUT4C)"

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

# --- Run 6: FORMULA GATING (heal-gates-merge). The finding this rework closes
#     (review tk-z4u2e #1): a stamp that did not persist used to exit 0, so the
#     formula ran merge-skill.sh in the SAME pass and the still-ungated anchor
#     merged un-reviewed. Extract the REAL gating snippet from the formula and
#     drive the REAL check-set-heal.sh into it with a merge-skill STUB — a
#     stamp-failing heal must HOLD the merge; a clean heal must let it run.
GATE="$(awk '
  /# >>> heal-gates-merge/ {f=1; next}
  /# <<< heal-gates-merge/ {f=0}
  f' "$TOML")"
[ -n "$GATE" ] \
  && ok "(GATE) heal-gates-merge snippet extracted from the formula" \
  || bad "(GATE) heal-gates-merge markers missing or renamed in the formula"
# Template-free so it executes directly (the {{...}} args are hoisted ABOVE the
# markers in the formula).
hasin "$GATE" '{{' \
  && bad "(GATE) extracted snippet still contains a {{template}} — hoist the args above the markers" \
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
  printf "CHECK_SET_HEAL_ARGS=( --default codex --review-pool 'gc-toolkit/gc-toolkit.polecat-codex' --fix-pool 'gc-toolkit/gc-toolkit.polecat' )\n"
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
  && ok "(GATE-FAIL) the formula recorded MERGE_SKILL_HELD=1" \
  || bad "(GATE-FAIL) the formula did not set MERGE_SKILL_HELD (got: $GATEOUT)"

# 6b: stamp SUCCEEDS -> real heal exits 0 -> merge-skill RUNS.
: > "$TMP/reviews"; : > "$TMP/revmeta"; : > "$TMP/stamped"; : > "$TMP/healed"
: > "$TMP/flagged"; : > "$TMP/deps"; : > "$TMP/stampfail"
: > "$MERGE_SENTINEL"
GATEOUT2="$(bash "$TMP/gaterun.sh" 2>/dev/null)"
[ -s "$MERGE_SENTINEL" ] && ok "(GATE-OK) a clean heal lets merge-skill run" \
                         || bad "(GATE-OK) merge-skill did NOT run after a clean heal (got: $GATEOUT2)"
hasin "$GATEOUT2" 'MERGE_SKILL_HELD=0' \
  && ok "(GATE-OK) the formula recorded MERGE_SKILL_HELD=0" \
  || bad "(GATE-OK) the formula MERGE_SKILL_HELD should be 0 (got: $GATEOUT2)"

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
reuse_run() { # <reviews-fixture> <revmeta-fixture> [revshowfail] -> OUT
  cat > "$TMP/anchors" <<'A'
bead-REUSE|pull_request|EMPTY|431|polecat/feat-reuse|main||
A
  : > "$TMP/stamped"; : > "$TMP/healed"; : > "$TMP/flagged"; : > "$TMP/deps"
  : > "$TMP/stampfail"; : > "$TMP/closed"
  printf '%s' "$1" > "$TMP/reviews"
  printf '%s' "$2" > "$TMP/revmeta"
  FAKE_REVSHOWFAIL="${3:-}" bash "$SCRIPT" \
    --default 'codex' \
    --review-pool 'gc-toolkit/gc-toolkit.polecat-codex' \
    --fix-pool 'gc-toolkit/gc-toolkit.polecat' 2>&1
}
POOL_C='gc-toolkit/gc-toolkit.polecat-codex'

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

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
