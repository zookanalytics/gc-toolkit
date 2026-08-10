#!/usr/bin/env bash
# Hermetic test for the close-on-land FAIL-CLOSED gating transition (PR#163
# signoff finding, fix #2 — the companion to the durable anchor_bead fallback
# tested by signoff-anchor-resolution.test.sh).
#
# Durable anchor_bead (fix #1) lets the signoff REDISCOVER its anchor when the
# BLOCKS edge is dropped. But the anchor is still detached into gating
# unconditionally, so if the anchor_bead write itself does NOT persist (a
# transient Dolt failure, or a reused review the dispatch never stamped), the
# anchor is detached with no recoverable link: the check.codex marker is never
# stamped and the merge skill holds the merge forever = stranded PR.
#
# Fix #2 (formulas/mol-refinery-patrol.toml, `signoff-anchor-failclosed`
# markers): before detaching, heal anchor_bead on the review bead and VERIFY it
# persisted; if it did not, leave $WORK assigned to the refinery (drain-ack +
# exit 1) so the next patrol retries instead of stranding.
#
# Fix #3 (same markers): the heal+verify above only runs when REVIEW_FOR_GATE is
# non-empty. In codex mode an empty REVIEW_FOR_GATE means review create/lookup
# failed (gc bd create returned no id; jq on empty input exits 0, block not under
# set -e), and the old no-op path then detached the anchor with no review bead —
# the same stranded PR. The gate now fails closed when codex review is the
# REQUIRED gate but no review id exists (codex in CHECK_SET && empty
# REVIEW_FOR_GATE).
#
# Fix #4 (tk-tmefn, same markers): a recorded anchor_bead is only half the link.
# The dispatch also writes the review's ROUTE — gc.routed_to (the live offer,
# which a claim consumes) and review_pool (the durable copy a signoff restores
# the route from) — best-effort, and nothing read it back. A dispatch counted
# without a route is a permanent strand: the review is open, so the next
# patrol's dedup reuses it rather than minting a replacement, while no pool can
# claim it. The gate now reads the route back, repairs once, and defers if it
# still will not stick — cases (M)-(Q).
#
# Fix #5 (tk-tmefn): codex membership is decided IN-SHELL at both formula sites.
# The old `... | grep -qxF codex` pipeline reports 141 on a long check_set under
# pipefail, reading a declared codex gate as absent — cases (I2)/(I3) and the
# static guard (D3).
#
# Fix #6 (tk-5niup, same markers): reading the route back is not enough while the
# predicate only asks whether the LIVE half is non-EMPTY. review_pool naming the
# codex pool while gc.routed_to names a DIFFERENT one, with nobody claiming, is a
# SPLIT route: the anchor is detached into gating while the review sits offered to
# a pool that will never stamp check.codex — the same unclaimable strand as (N),
# wearing a populated field. The live half must MATCH the pool (or the bead be
# claimed), identical to arm_stale_gate (reconcile-merged-prs.sh) and
# check-set-heal.sh's route_ok — cases (R)-(R3).
#
# This EXECUTES the real gate snippet extracted verbatim from the formula
# (between the markers) against a fake `gc`, so it cannot drift from the shipped
# instruction. No live city, Dolt, network, or PRs.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TOML="$ROOT/formulas/mol-refinery-patrol.toml"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }

mkdir -p "$TMP/bin"

# --- gc stub: the metadata writes/reads the gate snippet performs. ------------
#   gc runtime drain-ack                                  -> no-op (exit 0)
#   gc bd update <id> --set-metadata anchor_bead=<v>      -> persist to a store,
#       UNLESS FAIL_ANCHOR_WRITE is set (models a write that returns success-ish
#       but does not persist — the exact transient the read-back must catch).
#   gc bd show <id> --json                                -> emit the stored
#       metadata.anchor_bead (empty when the write was dropped).
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
[ "$1" = "runtime" ] && exit 0
[ "$1" = "bd" ] || exit 0
case "$2" in
  update)
    id="$3"; shift 3
    while [ $# -gt 0 ]; do
      case "$1" in
        --set-metadata)
          key="${2%%=*}"; val="${2#*=}"; shift 2
          if [ "$key" = "anchor_bead" ] && [ -n "${FAIL_ANCHOR_WRITE:-}" ]; then
            : # simulate a write that does not persist
          elif [ "$key" = "${FAIL_META_KEY:-}" ]; then
            : # same, for any single named key — used to drop a ROUTE field so
              # even the gate's own repair write cannot land it
          else
            printf '%s|%s|%s\n' "$id" "$key" "$val" >> "$FAKE_META"
          fi ;;
        *) shift ;;
      esac
    done ;;
  show)
    id="$3"
    meta_get() { awk -F'|' -v id="$id" -v k="$1" '$1==id && $2==k {v=$3} END{print v}' "$FAKE_META" 2>/dev/null; }
    ab=$(meta_get anchor_bead)
    rp=$(meta_get review_pool)
    rt=$(meta_get gc.routed_to)
    as=""
    # $FAKE_CLAIMED models a codex polecat claiming the review the INSTANT it was
    # routed: the claim CONSUMES gc.routed_to and takes the assignee. The gate
    # must read that as reachable, not as a lost route.
    if [ -n "${FAKE_CLAIMED:-}" ] && [ -n "$rt" ]; then as="$rt"; rt=""; fi
    jq -n --arg ab "$ab" --arg rp "$rp" --arg rt "$rt" --arg as "$as" \
      '[{assignee: (if $as=="" then null else $as end),
         metadata: ({} + (if $ab=="" then {} else {anchor_bead:$ab} end)
                       + (if $rp=="" then {} else {review_pool:$rp} end)
                       + (if $rt=="" then {} else {"gc.routed_to":$rt} end))}]' ;;
esac
exit 0
GC
chmod +x "$TMP/bin/gc"

export PATH="$TMP/bin:$PATH"
export FAKE_META="$TMP/meta"

# --- Extract the REAL gate snippet from the formula. -------------------------
# Lines between the markers (exclusive). Missing/renamed markers => empty
# extraction => the guard below fails loudly: the gate cannot silently vanish.
SNIPPET="$(awk '
  /# >>> signoff-anchor-failclosed/ {f=1; next}
  /# <<< signoff-anchor-failclosed/ {f=0}
  f' "$TOML")"

[ -n "$SNIPPET" ] \
  && ok "gate snippet extracted between signoff-anchor-failclosed markers" \
  || bad "gate snippet extraction EMPTY — markers missing from $TOML"

# Run WITHOUT set -e (as the polecat runs the step); the snippet's own `exit 1`
# is the fail-closed signal we assert on.
printf '%s\n' "$SNIPPET" > "$TMP/run.sh"

# gate <review_for_gate> <work> <fail?> [check_set] -> echo the snippet's exit
# code. exit 0 == transition PROCEEDS; non-zero == fail-closed defer. The 4th arg
# is the rendered check-set (default empty == no codex gate); it drives the
# codex-gate-id fail-closed check (finding fix #3).
gate() {
  : > "$FAKE_META"
  if CHECK_SET="${4:-}" REVIEW_FOR_GATE="$1" WORK="$2" FAIL_ANCHOR_WRITE="$3" bash "$TMP/run.sh" >/dev/null 2>&1; then
    echo 0
  else
    echo "$?"
  fi
}

# (A) anchor_bead heals + persists -> gate passes, transition proceeds.
eq "$(gate rb-1 work-1 '')" "0" \
   "(A) anchor_bead recorded -> gating transition proceeds"
# (B) THE FIX: anchor_bead write does NOT persist -> fail-closed defer (exit 1),
#     so the anchor is NOT detached into an unrecoverable gating state.
eq "$(gate rb-1 work-1 1)" "1" \
   "(B) anchor_bead not durably recorded -> transition deferred (fail-closed, exit 1)"
# (C) no review bead (non-codex gate) -> snippet is a no-op, transition proceeds.
eq "$(gate '' work-1 '')" "0" \
   "(C) no review bead -> gate skipped, transition proceeds"
# (F) THE FIX (#3): codex gate REQUIRED but no review id (create/lookup failed)
#     -> fail-closed defer (exit 1), so the anchor is NOT detached with no review
#     bead left to ever stamp check.codex.
eq "$(gate '' work-1 '' codex)" "1" \
   "(F) codex gate + missing review id -> transition deferred (fail-closed, exit 1)"
# (G) codex gate + review id present + anchor records -> transition proceeds.
eq "$(gate rb-1 work-1 '' codex)" "0" \
   "(G) codex gate + review id present + recorded -> gating transition proceeds"
# (H) codex gate + review id present but anchor write dropped -> fail-closed defer
#     (fix #2 still applies under codex mode).
eq "$(gate rb-1 work-1 1 codex)" "1" \
   "(H) codex gate + anchor not recorded -> transition deferred (fail-closed, exit 1)"
# (I) THE tk-aj4ua FIX: a natural-form spaced check-set "lint, codex" must parse
#     identically to "lint,codex" — codex IS a member, so the missing-review-id
#     gate fails closed (exit 1). The old literal ",codex," grep saw the space and
#     treated codex as ABSENT, skipping the gate (exit 0) while merge-skill.sh
#     still trimmed to `codex` and enforced it -> stranded PR. This case fails on
#     the pre-fix grep and passes only with the normalized (trim) membership test.
eq "$(gate '' work-1 '' 'lint, codex')" "1" \
   "(I) spaced check-set 'lint, codex' + missing review id -> fail-closed (exit 1)"
# (J) spaced check-set + review id present + anchor records -> proceeds (parity
#     with (G): normalization must not over-fire and block a valid transition).
eq "$(gate rb-1 work-1 '' 'lint, codex')" "0" \
   "(J) spaced check-set 'lint, codex' + review id present + recorded -> proceeds"
# (I2)/(I3) THE tk-tmefn FIX: a LONG check_set, run UNDER `set -o pipefail`.
#
# The membership test used to pipe printf|tr|sed into `grep -qxF codex`.
# `grep -q` exits at its FIRST match, closing the pipe under sed while sed still
# has the ~10k gates AFTER `codex` to write; sed takes SIGPIPE and the pipeline
# reports 141. WITH pipefail that 141 is the `if` condition's status, so the
# condition reads FALSE for a check_set that plainly names codex: the fail-closed
# guard is SKIPPED and the anchor is detached with no review bead — the exact
# strand this gate exists to prevent, decided by nothing but how many gates
# happen to follow `codex`. Measured 10/10 misses at this width.
#
# Why a SEPARATE runner: the step's own bash block sets `-e`, NOT `-o pipefail`,
# so the trap is LATENT in production today rather than live — the pipeline's
# status is grep's 0 and the membership reads correctly. Run under the shell
# options the step actually uses, this case would pass against the broken
# pipeline and pin nothing. It is asserted under pipefail on purpose: that is the
# condition the in-shell match makes irrelevant, and one `set -o pipefail` added
# to the step preamble later is all it would take to turn the latent trap live.
printf 'set -o pipefail\n%s\n' "$SNIPPET" > "$TMP/run-pf.sh"
gate_pf() {
  : > "$FAKE_META"
  if CHECK_SET="${4:-}" REVIEW_FOR_GATE="$1" WORK="$2" FAIL_ANCHOR_WRITE="$3" \
       bash "$TMP/run-pf.sh" >/dev/null 2>&1; then
    echo 0
  else
    echo "$?"
  fi
}
LONGSET="codex"
for _i in $(seq 1 10000); do LONGSET="$LONGSET,gate$_i"; done
eq "$(gate_pf '' work-1 '' "$LONGSET")" "1" \
   "(I2) long check_set naming codex + missing review id -> fail-closed under pipefail (exit 1)"
# (I3) parity: the same long check_set must not over-fire when the review id IS
#      present — the fix must not turn every long-check_set rig into a permanent
#      defer.
eq "$(gate_pf rb-1 work-1 '' "$LONGSET")" "0" \
   "(I3) long check_set + review id present + recorded -> proceeds under pipefail"
# (L) one-anchor-per-PR (tk-ynz4b): on a rework hand-back the resolved gating
#     anchor (GATING_ANCHOR) differs from $WORK — the heal must record THAT
#     anchor on the review, never the rework bead, or the signoff would stamp
#     check.<name> on a bead the merge skill does not gate on. Cases (A)-(J)
#     leave GATING_ANCHOR unset and exercise the ${GATING_ANCHOR:-$WORK}
#     first-handoff fallback.
: > "$FAKE_META"
if CHECK_SET=codex REVIEW_FOR_GATE=rb-2 WORK=rework-1 GATING_ANCHOR=anchor-1 \
     FAIL_ANCHOR_WRITE='' bash "$TMP/run.sh" >/dev/null 2>&1; then
  rec=$(awk -F'|' '$1=="rb-2" && $2=="anchor_bead" {v=$3} END{print v}' "$FAKE_META" 2>/dev/null)
  eq "$rec" "anchor-1" \
     "(L) rework hand-back: anchor_bead records the resolved gating anchor, not \$WORK"
else
  bad "(L) rework hand-back gate must proceed when the anchor write persists"
fi

# --- (M)-(Q) THE ROUTE READ-BACK (tk-tmefn). ---------------------------------
# A recorded anchor_bead is only half the link. The dispatch also writes the
# review's ROUTE — gc.routed_to (the live offer) and review_pool (the durable
# copy) — best-effort, status discarded, and nothing read it back. If either
# write is dropped the review bead still exists and is still OPEN, so the next
# patrol's EXISTING_REVIEW dedup REUSES it instead of minting a replacement,
# while no pool can ever claim it: the gate stays armed and unmet, the PR (or
# the pre-open branch) is held, and nothing retries. The gate now verifies the
# route the same way it verifies the anchor link, repairs once, and defers if it
# still will not stick.
#
# route_gate <seed_review_pool> <seed_routed_to> <claimed?> [persistently_dropped_key]
# Seeds the route as the DISPATCH would have left it, then runs the real gate.
route_gate() {
  : > "$FAKE_META"
  printf 'rb-r|anchor_bead|anchor-r\n' >> "$FAKE_META"
  if [ -n "$1" ]; then printf 'rb-r|review_pool|%s\n' "$1" >> "$FAKE_META"; fi
  if [ -n "$2" ]; then printf 'rb-r|gc.routed_to|%s\n' "$2" >> "$FAKE_META"; fi
  if CHECK_SET=codex REVIEW_FOR_GATE=rb-r WORK=work-r GATING_ANCHOR=anchor-r \
     CODEX_POOL='rig/pool-codex' FAIL_ANCHOR_WRITE='' FAKE_CLAIMED="$3" \
     FAIL_META_KEY="${4:-}" bash "$TMP/run.sh" >/dev/null 2>&1; then
    echo 0
  else
    echo "$?"
  fi
}

# (M) both route fields recorded -> gate passes, transition proceeds.
eq "$(route_gate 'rig/pool-codex' 'rig/pool-codex' '')" "0" \
   "(M) durably-routed review -> gating transition proceeds"
# (N) THE FIX: gc.routed_to never persists (the repair write is dropped too) ->
#     fail-closed defer. Nobody is offered the review, so nothing can ever stamp
#     the gate; detaching here would strand the anchor behind a dedup that keeps
#     reusing an unclaimable bead.
eq "$(route_gate 'rig/pool-codex' '' '' 'gc.routed_to')" "1" \
   "(N) route (gc.routed_to) not durably recorded -> transition deferred (fail-closed, exit 1)"
# (N2) the SAME missing route, but the repair write lands -> proceeds. The gate
#      heals a transient miss rather than deferring on it; deferring on every
#      dropped write would stall the patrol on noise.
eq "$(route_gate 'rig/pool-codex' '' '')" "0" \
   "(N2) a transiently missing route is REPAIRED in place -> transition proceeds"
# (O) THE OTHER HALF: review_pool never persists, gc.routed_to is fine. The
#     review IS claimable right now, so it looks healthy — but the durable copy
#     is the only thing a signoff can restore the route from when it has to
#     re-offer the review, and the claim that would need it is exactly what
#     consumes gc.routed_to. Fail closed.
eq "$(route_gate '' 'rig/pool-codex' '' 'review_pool')" "1" \
   "(O) durable route copy (review_pool) not recorded -> transition deferred (fail-closed, exit 1)"
# (P) NOT over-firing: a review claimed the instant it routed has an EMPTY
#     gc.routed_to (the claim ate it) and an assignee. That is a healthy
#     dispatch; deferring on it would stall every fast-claimed review.
eq "$(route_gate 'rig/pool-codex' 'rig/pool-codex' '1')" "0" \
   "(P) review claimed the instant it routed (routed_to consumed, assignee set) -> proceeds"
# (R)/(R2) THE SPLIT ROUTE (tk-5niup): review_pool names the codex pool while the
#     LIVE gc.routed_to names a DIFFERENT pool, and nobody has claimed the bead.
#     The old predicate only asked whether the live half was non-EMPTY, so this
#     passed: the anchor was detached into gating while the review sat offered to
#     a pool that will never stamp check.codex. Unclaimable by the pool that owes
#     the gate = the same permanent strand (N) covers, wearing a populated field.
# (R) the repair write lands -> the gate HEALS the live half and proceeds. The
#     exit code alone cannot pin this (the pre-fix gate also proceeded), so assert
#     the repair actually rewrote gc.routed_to to the codex pool — pre-fix the
#     predicate passed on the first read and no repair was ever attempted.
: > "$FAKE_META"
printf 'rb-r|anchor_bead|anchor-r\n'          >> "$FAKE_META"
printf 'rb-r|review_pool|rig/pool-codex\n'    >> "$FAKE_META"
printf 'rb-r|gc.routed_to|rig/pool-other\n'   >> "$FAKE_META"
if CHECK_SET=codex REVIEW_FOR_GATE=rb-r WORK=work-r GATING_ANCHOR=anchor-r \
   CODEX_POOL='rig/pool-codex' FAIL_ANCHOR_WRITE='' bash "$TMP/run.sh" >/dev/null 2>&1; then
  R_ROUTE=$(awk -F'|' '$1=="rb-r" && $2=="gc.routed_to" {v=$3} END{print v}' "$FAKE_META" 2>/dev/null)
  eq "$R_ROUTE" "rig/pool-codex" \
     "(R) split route (durable=codex, live=other pool, unclaimed) -> repaired to the codex pool"
else
  bad "(R) a split route whose repair write lands must HEAL and proceed, not defer"
fi
# (R2) THE FIX, pinned: the same split route, and the repair write is dropped too
#      -> fail-closed defer. Pre-fix the gate returned 0 on the FIRST read (live
#      half non-empty) and detached the anchor with the review routed to the wrong
#      pool; nothing would ever have re-offered it to codex.
eq "$(route_gate 'rig/pool-codex' 'rig/pool-other' '' 'gc.routed_to')" "1" \
   "(R2) split route that will not repair -> transition deferred (fail-closed, exit 1)"
# (R3) NOT over-firing on a split route that is already CLAIMED: an assignee means
#      a polecat holds the review, so the live offer is spent and its value is
#      history. Deferring here would stall a perfectly healthy dispatch — the same
#      over-fire (P) guards against, reached through a stale live route.
eq "$(route_gate 'rig/pool-codex' 'rig/pool-other' '1')" "0" \
   "(R3) split route but the review is CLAIMED -> proceeds (the claim spent the offer)"
# (Q) no pool in scope (a non-codex gate dispatches no review) -> the route check
#     is skipped entirely, not failed on an absent route.
: > "$FAKE_META"; printf 'rb-r|anchor_bead|anchor-r\n' >> "$FAKE_META"
if CHECK_SET=lint REVIEW_FOR_GATE=rb-r WORK=work-r GATING_ANCHOR=anchor-r \
   FAIL_ANCHOR_WRITE='' bash "$TMP/run.sh" >/dev/null 2>&1; then
  ok "(Q) no CODEX_POOL in scope -> route check skipped, transition proceeds"
else
  bad "(Q) an absent pool must skip the route check, not defer the transition"
fi

# --- Gate wiring: the formula must feed REVIEW_FOR_GATE from the dispatched or
#     reused review bead, else the gate never runs. ----------------------------
grep -q 'REVIEW_FOR_GATE="${REVIEW_BEAD:-$EXISTING_REVIEW}"' "$TOML" \
  && ok "(D) gate is fed REVIEW_FOR_GATE from the new-or-reused review bead" \
  || bad "(D) formula must set REVIEW_FOR_GATE from \${REVIEW_BEAD:-\$EXISTING_REVIEW}"
# The codex-id check (fix #3) reads CHECK_SET, which the snippet keeps
# template-free; the live formula must wire it from the rendered {{check_set}}
# OUTSIDE the markers, else the check-set is invisible and the check never
# fires. Static guard (the extracted snippet cannot assert its own wiring).
grep -q 'CHECK_SET="{{check_set}}"' "$TOML" \
  && ok "(D2) check-set CHECK_SET is wired from the rendered {{check_set}}" \
  || bad "(D2) formula must set CHECK_SET=\"{{check_set}}\" for the codex-id check"
# (D3) No codex-membership PIPELINE may come back to the formula, at EITHER site
# (the CODEX_GATE/PRE_OPEN decision in the merge-push step, and the fail-closed
# guard above). (I2) executes the guard, but the CODEX_GATE site sits outside any
# extraction markers, so a static guard is what covers it: under pipefail a long
# check_set makes `... | grep -qxF codex` report 141, and there the miss silently
# drops PRE_OPEN — the PR opens BEFORE codex has reviewed it. Comment lines are
# stripped first: the fix is DESCRIBED in prose right next to both sites.
grep -vE '^[[:space:]]*#' "$TOML" > "$TMP/toml-nocomment"
grep -q 'grep -q[a-zA-Z]* codex' "$TMP/toml-nocomment" \
  && bad "(D3) a codex-membership grep pipeline is back in the formula — under pipefail a long check_set reads it as ABSENT" \
  || ok "(D3) codex membership is decided in-shell at every formula site (no pipefail-prone pipeline)"
# --- Gate must leave the anchor for retry (drain-ack) on the fail path. -------
grep -q 'gc runtime drain-ack' <<< "$SNIPPET" \
  && ok "(E) fail path drain-acks so the next patrol retries" \
  || bad "(E) fail path must gc runtime drain-ack before exiting"

# --- Pre-open transition is ALSO fail-closed (tk-6d0vb.1.8). The gate snippet is
#     SHARED: both the post-open (merge_result=pull_request) and the pre-open
#     (merge_result=pre_open_gate) transitions run AFTER it, so an anchor with no
#     recoverable review->anchor link is never detached into EITHER gating state.
#     Guard that the pre_open_gate transition sits downstream of the fail-closed
#     markers in the formula. -----------------------------------------------------
FC_END=$(grep -n '# <<< signoff-anchor-failclosed' "$TOML" | head -1 | cut -d: -f1)
PREOPEN_LINE=$(grep -n -- '--set-metadata merge_result=pre_open_gate' "$TOML" | head -1 | cut -d: -f1)
{ [ -n "$FC_END" ] && [ -n "$PREOPEN_LINE" ] && [ "$PREOPEN_LINE" -gt "$FC_END" ]; } \
  && ok "(K) pre_open_gate transition is downstream of the fail-closed gate (shared gate protects the pre-open path)" \
  || bad "(K) pre_open_gate transition must follow the fail-closed markers (got FC_END=$FC_END pre_open=$PREOPEN_LINE)"

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
