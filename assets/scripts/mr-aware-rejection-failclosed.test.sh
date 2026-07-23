#!/usr/bin/env bash
# Hermetic test for the mr-aware Rejection Flow FAIL-CLOSED bead read
# (PR#204 signoff finding, review tk-h51jg).
#
# Both rejection arms of mol-refinery-patrol.toml — the `rebase` step (conflict)
# and the `handle-failures` step (test regression) — repool a rejected gating
# anchor AND must clear its `merge_result` so it drops out of merge-skill.sh's
# `merge_result=pull_request` scan. Left set on a repooled anchor with no rework
# child, the skill lands the un-gated rework — the exact hole this migration
# exists to close.
#
# The pre-fix code repooled UNCONDITIONALLY, then read merge_result in a SEPARATE
# `gc bd show ... 2>/dev/null | jq` that FAILS OPEN: `gc bd` writes errors to
# stderr and leaves stdout empty, so a read that failed AFTER the repool made
# `MR_STATE` empty, the `--unset-metadata merge_result` was silently skipped, and
# the anchor was left routed-to-polecat WITH merge_result still set.
#
# The fix (both `# >>> mr-aware-rejection` … `# <<< mr-aware-rejection` blocks):
# read + SHAPE-validate the bead ONCE before repooling, fold the merge_result
# clear (and pr_url→existing_pr) into the SAME repool update, and if the bead is
# unreadable, FAIL CLOSED — do not repool at all (drain-ack + exit 1), leaving the
# anchor with the refinery to retry rather than pooling it with merge_result set.
#
# This EXECUTES the real snippets extracted verbatim from the formula (between the
# markers) against a fake `gc`, so the test cannot drift from the shipped
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

# --- gc stub: models the reads/writes the rejection snippet performs. ----------
#   gc runtime drain-ack               -> no-op (exit 0)
#   gc bd show <id> --json             -> emit bead JSON per SHOW_SCENARIO:
#       mr         -> mr-shaped anchor (merge_result + pr_url set)
#       nonmr      -> plain bead (no merge_result)
#       unreadable -> EMPTY stdout, exit 0 — the exact bd fails-open behavior the
#                     fix must treat as "cannot determine mr-shape", NOT "non-mr".
#   gc bd update <id> ...              -> record UPDATE_RAN + each set/unset op so
#       the assertions can prove the repool ran (or, when unreadable, did NOT).
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
[ "$1" = "runtime" ] && exit 0
[ "$1" = "bd" ] || exit 0
case "$2" in
  show)
    case "${SHOW_SCENARIO:-mr}" in
      mr)         printf '[{"metadata":{"merge_result":"pull_request","pr_url":"https://example.test/pr/1","pr_number":"1"}}]\n' ;;
      nonmr)      printf '[{"metadata":{}}]\n' ;;
      unreadable) : ;;  # empty stdout — bd fails open (error to stderr, nothing on stdout)
    esac ;;
  update)
    id="$3"; shift 3
    echo "UPDATE_RAN" >> "$FAKE_META"
    while [ $# -gt 0 ]; do
      case "$1" in
        --set-metadata)   printf 'set|%s|%s\n' "${2%%=*}" "${2#*=}" >> "$FAKE_META"; shift 2 ;;
        --unset-metadata) printf 'unset|%s\n' "$2" >> "$FAKE_META"; shift 2 ;;
        *) shift ;;
      esac
    done ;;
esac
exit 0
GC
chmod +x "$TMP/bin/gc"

# git stub: only `git rev-parse origin/<t>` inside the rebase-arm rejection_reason
# string. Fixed sha keeps the test hermetic (no repo dependency).
cat > "$TMP/bin/git" <<'GIT'
#!/usr/bin/env bash
echo "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
exit 0
GIT
chmod +x "$TMP/bin/git"

export PATH="$TMP/bin:$PATH"
export FAKE_META="$TMP/meta"

# --- Extract EACH real rejection snippet from the formula. --------------------
# One file per `# >>> mr-aware-rejection` … `# <<< mr-aware-rejection` pair, so
# BOTH arms (rebase + handle-failures) are exercised, not just the first. Missing
# or renamed markers => zero blocks => the guard below fails loudly.
awk -v tmp="$TMP" '
  /# >>> mr-aware-rejection/ { n++; f=1; next }
  /# <<< mr-aware-rejection/ { f=0; next }
  f { print > (tmp "/block" n ".sh") }
' "$TOML"

NBLOCKS=$(ls "$TMP"/block*.sh 2>/dev/null | wc -l | tr -d ' ')
eq "$NBLOCKS" "2" "both rejection arms extracted between mr-aware-rejection markers"

# run <blockfile> <scenario> -> echo the snippet's exit code; leaves $FAKE_META
# populated. exit 0 == repool proceeded; non-zero == fail-closed defer.
run() {
  : > "$FAKE_META"
  if SHOW_SCENARIO="$2" WORK=work-1 TARGET=main GC_RIG=rig bash "$1" >/dev/null 2>&1; then
    echo 0
  else
    echo "$?"
  fi
}

# Exercise every extracted arm identically — the fail-closed contract is the same
# for both, so neither can regress silently.
for BLK in "$TMP"/block*.sh; do
  L="$(basename "$BLK" .sh)"

  # (A) mr-shaped + readable -> repool proceeds; merge_result cleared and
  #     pr_url→existing_pr carried IN THE SAME update.
  eq "$(run "$BLK" mr)" "0" "[$L](A) mr-shaped readable bead -> repool proceeds (exit 0)"
  grep -q '^UPDATE_RAN$' "$FAKE_META" \
    && ok "[$L](A) repool update ran" || bad "[$L](A) repool update did not run"
  grep -q '^unset|merge_result$' "$FAKE_META" \
    && ok "[$L](A) merge_result cleared in the SAME repool update" \
    || bad "[$L](A) merge_result NOT cleared"
  grep -q '^set|existing_pr|https://example.test/pr/1$' "$FAKE_META" \
    && ok "[$L](A) pr_url carried to existing_pr" || bad "[$L](A) existing_pr not carried"
  grep -q '^set|rejection_reason|' "$FAKE_META" \
    && ok "[$L](A) rejection_reason set" || bad "[$L](A) rejection_reason missing"
  grep -q '^set|gc.routed_to|' "$FAKE_META" \
    && ok "[$L](A) routed back to the polecat pool" || bad "[$L](A) gc.routed_to missing"

  # (B) non-mr + readable -> plain repool; NO merge_result clear, NO existing_pr.
  eq "$(run "$BLK" nonmr)" "0" "[$L](B) non-mr readable bead -> plain repool (exit 0)"
  grep -q '^UPDATE_RAN$' "$FAKE_META" \
    && ok "[$L](B) repool update ran" || bad "[$L](B) repool update did not run"
  if grep -q '^unset|merge_result$' "$FAKE_META"; then
    bad "[$L](B) merge_result cleared on a NON-mr bead (spurious unset)"
  else
    ok "[$L](B) no spurious merge_result clear on a non-mr bead"
  fi
  if grep -q '^set|existing_pr|' "$FAKE_META"; then
    bad "[$L](B) existing_pr set on a non-mr bead"
  else
    ok "[$L](B) no existing_pr on a non-mr bead"
  fi

  # (C) THE FIX: unreadable bead (empty stdout) -> FAIL CLOSED. exit 1, and NO
  #     repool ran, so the anchor is left with the refinery (merge_result intact)
  #     rather than pooled to a polecat with merge_result still set.
  eq "$(run "$BLK" unreadable)" "1" "[$L](C) unreadable bead -> fail-closed defer (exit 1)"
  if grep -q '^UPDATE_RAN$' "$FAKE_META"; then
    bad "[$L](C) repool RAN on an unreadable bead — the exact bug this fix prevents"
  else
    ok "[$L](C) unreadable bead -> NO repool ran (anchor left with the refinery)"
  fi
done

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
