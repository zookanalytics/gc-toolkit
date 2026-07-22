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
#            dispatch — the anchor stays ungated and is retried, flagged once.
#   (CONV)   a healed anchor (check_set_healed recorded, gate now satisfiable via
#            the dispatched review) is not re-stamped and not re-dispatched.
#   (RETRY)  a healed anchor whose dispatch FAILED last pass (healed recorded, gate
#            still unsatisfiable, nothing in flight) re-dispatches — the stamp did
#            not hide it from the satisfiability retry.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/check-set-heal.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }
has() { grep -q "$1" "$2" 2>/dev/null; }

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
  awk -F'\t' -v i="$1" '$1==i{print $2; exit}' "$FAKE_HEALED" 2>/dev/null
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
          cxfield=""; [ -n "$codex" ] && cxfield=$(printf ',"check.codex":"%s"' "$codex")
          prfield=""; [ -n "$pr" ] && prfield=$(printf ',"pr_number":"%s","pr_url":"https://x/pull/%s"' "$pr" "$pr")
          obj=$(printf '{"id":"%s","title":"impl %s","metadata":{"merge_result":"%s","branch":"%s","merged_target":"%s"%s%s%s%s}}' \
            "$id" "$id" "$mr" "$branch" "$target" "$csfield" "$cxfield" "$hfield" "$prfield")
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
    cs=$(cs_for "$id"); [ "$cs" = "EMPTY" ] || [ "$cs" = "__ABSENT__" ] && cs=""
    # anchor_bead recorded on a review this run?
    ab=$(awk -F'\t' -v i="$id" '$1==i && $2=="anchor_bead"{print $3; exit}' "$FAKE_REVMETA" 2>/dev/null)
    jq -n --arg cs "$cs" --arg ab "$ab" \
      '[{metadata: ({} + (if $cs=="" then {} else {check_set:$cs} end) + (if $ab=="" then {} else {anchor_bead:$ab} end))}]' ;;
  create)
    # gc bd create "<title>" -t task --json
    n=$(cat "$FAKE_SEQ" 2>/dev/null || echo 0); n=$((n + 1)); printf '%s' "$n" > "$FAKE_SEQ"
    printf '{"id":"rev-new-%s"}\n' "$n" ;;
  update)
    id="$3"
    # Record a check_set stamp so the NEXT list/show reflects it (convergence).
    if printf '%s' "$*" | grep -q 'check_set='; then
      val=$(printf '%s' "$*" | sed -n 's/.*--set-metadata check_set=\([^ ]*\).*/\1/p')
      # Honour a deliberate stamp-fail injection: if this id is in FAKE_STAMPFAIL,
      # do NOT persist the check_set (simulate a lost ledger write).
      if ! grep -qx "$id" "$FAKE_STAMPFAIL" 2>/dev/null; then
        printf '%s\t%s\n' "$id" "$val" >> "$FAKE_STAMPED"
      fi
    fi
    if printf '%s' "$*" | grep -q 'check_set_healed='; then
      val=$(printf '%s' "$*" | sed -n 's/.*--set-metadata check_set_healed=\([^ ]*\).*/\1/p')
      printf '%s\t%s\n' "$id" "$val" >> "$FAKE_HEALED"
    fi
    if printf '%s' "$*" | grep -q 'check_set_heal_flagged='; then
      printf '%s\n' "$id" >> "$FAKE_FLAGGED"
    fi
    # Record review metadata (anchor_bead, routing, task_kind, review_branch).
    for k in anchor_bead gc.routed_to task_kind review_branch pr_number fix_target_pool; do
      if printf '%s' "$*" | grep -q -- "--set-metadata $k="; then
        v=$(printf '%s' "$*" | sed -n "s/.*--set-metadata $k=\\([^ ]*\\).*/\\1/p")
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
: > "$TMP/deps"; : > "$TMP/stampfail"; echo 0 > "$TMP/seq"

export PATH="$TMP/bin:$PATH"
export FAKE_ANCHORS="$TMP/anchors" FAKE_REVIEWS="$TMP/reviews" \
       FAKE_STAMPED="$TMP/stamped" FAKE_HEALED="$TMP/healed" \
       FAKE_FLAGGED="$TMP/flagged" FAKE_REVMETA="$TMP/revmeta" FAKE_DEPS="$TMP/deps" \
       FAKE_STAMPFAIL="$TMP/stampfail" FAKE_SEQ="$TMP/seq"

# --- Run 1. -------------------------------------------------------------------
OUT1="$(bash "$SCRIPT" \
  --default 'codex' \
  --review-pool 'gc-toolkit/gc-toolkit.polecat-codex' \
  --fix-pool 'gc-toolkit/gc-toolkit.polecat')"

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
awk -F'\t' '$2=="anchor_bead" && $3=="bead-PREOPEN"{print $1}' "$TMP/revmeta" | while read -r rid; do
  grep -q "^$rid	pr_number	" "$TMP/revmeta" && echo "PREOPEN_HAS_PR" || true
done | grep -q PREOPEN_HAS_PR && bad "(PREOPEN) pre-open review must NOT carry pr_number" \
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

# Summary: 6 healed (EMPTY, ABSENT, SEP, GREEN, INFLGT, PREOPEN), and the opt-outs
# / normal untouched.
printf '%s\n' "$OUT1" | grep -q '6 healed' \
  && ok "run 1 summary reports 6 healed" || bad "run 1 summary healed count (got: $OUT1)"
printf '%s\n' "$OUT1" | grep -q '2 explicit opt-out' \
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
printf '%s\n' "$OUT2" | grep -q '0 healed' \
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
OUT4="$(bash "$SCRIPT" \
  --default 'codex' \
  --review-pool 'gc-toolkit/gc-toolkit.polecat-codex' \
  --fix-pool 'gc-toolkit/gc-toolkit.polecat')"
grep -q '	anchor_bead	bead-FAIL$' "$TMP/revmeta" && bad "(STAMPFAIL) a failed stamp must NOT dispatch a signoff" \
                                                    || ok "(STAMPFAIL) failed stamp -> no signoff dispatched (fail-closed)"
has '^bead-FAIL$' "$TMP/flagged" && ok "(STAMPFAIL) failed stamp flags the anchor once" \
                                 || bad "(STAMPFAIL) failed stamp must flag the anchor"
printf '%s\n' "$OUT4" | grep -q '0 healed' \
  && ok "(STAMPFAIL) a non-persisting stamp is NOT counted healed" || bad "(STAMPFAIL) must report 0 healed (got: $OUT4)"

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

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
