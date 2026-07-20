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
          else
            printf '%s|%s|%s\n' "$id" "$key" "$val" >> "$FAKE_META"
          fi ;;
        *) shift ;;
      esac
    done ;;
  show)
    id="$3"
    ab=$(awk -F'|' -v id="$id" '$1==id && $2=="anchor_bead" {v=$3} END{print v}' "$FAKE_META" 2>/dev/null)
    if [ -n "$ab" ]; then printf '[{"metadata":{"anchor_bead":"%s"}}]\n' "$ab"
    else printf '[{"metadata":{}}]\n'; fi ;;
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
# --- Gate must leave the anchor for retry (drain-ack) on the fail path. -------
printf '%s' "$SNIPPET" | grep -q 'gc runtime drain-ack' \
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
