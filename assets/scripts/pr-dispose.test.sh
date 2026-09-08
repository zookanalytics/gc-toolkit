#!/usr/bin/env bash
# Hermetic test for assets/scripts/pr-dispose.sh — the sanctioned path that
# records a deliberate PR-close disposition on the open anchor and closes the
# PR, so pr-facts.sh consummates the terminal close through bead-rehome.sh.
# Covers: the marker stamped and read back on an OPEN pull_request anchor;
# --no-close-pr stamping only; the PR closed through gh when the anchor is open;
# idempotent no-op on an already-disposed anchor; refusal on an anchor past the
# pull_request state (named bead-rehome as the direct verb); refusal on a
# missing PR number; the marker read-back gate refusing to close the PR when the
# stamp did not land; the optional successor store carried through; dry-run
# writing nothing; and the usage refusals (bad kind, missing args).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-pr-dispose-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"
harness_init

SD="$TMP/scripts"
mk_sut_dir "$SD" "$HERE/pr-dispose.sh"
SUT="$SD/pr-dispose.sh"

# gh: pr-dispose reads the PR state and closes it. The harness gh stub cats a
# whole fixture and has no `close`, so override it with a minimal one that
# serves a canned state (per PR, default OPEN) and logs the close, honouring a
# refusal knob. Written after harness_init so it wins on PATH.
cat > "$BIN/gh" <<'GH'
#!/usr/bin/env bash
set -u
printf '%s\n' "$*" >> "${STUB_GH_LOG:?}"
[ "${1:-}" = "pr" ] || { echo "gh stub: only 'pr' supported" >&2; exit 2; }
v="${2:-}"; shift 2 || true
num=""; for a in "$@"; do case "$a" in ''|--*|github.com/*) : ;; *) [ -z "$num" ] && num="$a" ;; esac; done
case "$v" in
  view)  [ -n "${STUB_PR_VIEW_RC:-}" ] && { echo "gh (stub): simulated pr view failure" >&2; exit "$STUB_PR_VIEW_RC"; }
         f="$STUB_GH_DIR/pr_state_$num"; [ -s "$f" ] && cat "$f" || echo "OPEN" ;;
  close) exit "${STUB_PR_CLOSE_RC:-0}" ;;
  *)     echo "gh pr stub: unsupported '$v'" >&2; exit 2 ;;
esac
GH
chmod +x "$BIN/gh"

# An OPEN anchor gating a PR, plus the successor it points to.
anchor() { # id num [extra-metadata]
  printf '{"id":"%s","status":"open","assignee":"rig/refinery","notes":"","title":"t","metadata":{"merge_result":"pull_request","pr_number":"%s","pr_url":"https://github.com/zook/gc-toolkit/pull/%s","branch":"polecat/%s"%s}}' \
    "$1" "$2" "$2" "$1" "${3:-}"
}
succ() { printf '{"id":"%s","status":"open","title":"successor","notes":"","metadata":{}}' "$1"; }

echo "# an OPEN pull_request anchor: the marker is stamped and read back (--no-close-pr)"
store "[$(anchor A1 70), $(succ S1)]"
out=$("$SUT" --anchor A1 --successor S1 --kind duplicate --no-close-pr 2>&1); rc=$?
eq "$rc" 0 "exits 0"
eq "$(meta A1 'gc.pr_close_disposition_kind')" "duplicate" "kind stamped"
eq "$(meta A1 'gc.pr_close_disposition_successor')" "S1" "successor stamped"
eq "$(meta A1 'gc.pr_close_disposition_successor_store')" "<absent>" "no store key when none given"
eq "$(bstatus A1)" "open" "the anchor is NOT closed — that terminal close is pr-facts's"
eq "$(meta A1 'gc.superseded_by')" "<absent>" "…and no gc.superseded_by is written here (bead-rehome is its sole writer)"
hasnt "$(cat "$STUB_GH_LOG")" "pr close" "--no-close-pr closes no PR"

echo "# the PR is closed through gh when the anchor is open"
store "[$(anchor A2 71), $(succ S2)]"
: > "$STUB_GH_LOG"
out=$("$SUT" --anchor A2 --successor S2 --kind re-homed --note "ruled out" 2>&1); rc=$?
eq "$rc" 0 "exits 0"
eq "$(meta A2 'gc.pr_close_disposition_kind')" "re-homed" "kind stamped"
has "$(cat "$STUB_GH_LOG")" "pr close 71" "gh pr close was called for the PR"
has "$out" "closed PR#71" "reports the close"

echo "# a recorded --successor-store is carried onto the marker"
store "[$(anchor A3 72), $(succ S3)]"
out=$("$SUT" --anchor A3 --successor bt-xyz --kind duplicate --successor-store rig:beta --no-close-pr 2>&1)
eq "$(meta A3 'gc.pr_close_disposition_successor_store')" "rig:beta" "store key stamped"

echo "# already disposed (gc.superseded_by set): no-op, nothing stamped, no close"
store "[$(anchor A4 73 ',"gc.superseded_by":"S9"'), $(succ S4)]"
: > "$STUB_GH_LOG"
out=$("$SUT" --anchor A4 --successor S4 --kind duplicate 2>&1); rc=$?
eq "$rc" 0 "exits 0 (idempotent)"
has "$out" "already disposed" "says it is already disposed"
eq "$(meta A4 'gc.pr_close_disposition_kind')" "<absent>" "no marker written over a disposed anchor"
hasnt "$(cat "$STUB_GH_LOG")" "pr close" "no PR close on an already-disposed anchor"

echo "# an anchor past the pull_request state is refused, naming bead-rehome"
store "[{\"id\":\"A5\",\"status\":\"open\",\"title\":\"t\",\"notes\":\"\",\"metadata\":{\"merge_result\":\"abandoned\",\"pr_number\":\"74\"}}, $(succ S5)]"
out=$("$SUT" --anchor A5 --successor S5 --kind not-needed 2>&1); rc=$?
eq "$rc" 1 "exits 1"
has "$out" "bead-rehome.sh --origin A5" "names the direct disposition verb for a non-pull_request anchor"
eq "$(meta A5 'gc.pr_close_disposition_kind')" "<absent>" "no marker stamped on the refused anchor"

echo "# a pull_request anchor with no PR number and no --pr is refused"
store "[{\"id\":\"A6\",\"status\":\"open\",\"metadata\":{\"merge_result\":\"pull_request\"}}, $(succ S6)]"
out=$("$SUT" --anchor A6 --successor S6 --kind duplicate 2>&1); rc=$?
eq "$rc" 1 "exits 1"
has "$out" "no numeric PR number" "explains the missing PR number"

echo "# the read-back gate: a marker that does not stick refuses to close the PR"
store "[$(anchor A7 75), $(succ S7)]"
: > "$STUB_GH_LOG"
out=$(STUB_DROP_KEYS="A7:gc.pr_close_disposition_kind,gc.pr_close_disposition_successor" "$SUT" --anchor A7 --successor S7 --kind duplicate 2>&1); rc=$?
eq "$rc" 1 "exits 1"
has "$out" "did NOT stick" "reports the failed read-back"
hasnt "$(cat "$STUB_GH_LOG")" "pr close" "the PR is NOT closed when the marker did not land"

echo "# the PR is already closed: marker stamped, no close attempted"
store "[$(anchor A8 76), $(succ S8)]"
printf 'CLOSED\n' > "$GH_DIR/pr_state_76"
: > "$STUB_GH_LOG"
out=$("$SUT" --anchor A8 --successor S8 --kind folded 2>&1); rc=$?
eq "$rc" 0 "exits 0"
eq "$(meta A8 'gc.pr_close_disposition_kind')" "folded" "marker stamped"
hasnt "$(cat "$STUB_GH_LOG")" "pr close" "no re-close of an already-closed PR"
has "$out" "already CLOSED" "notes the PR was already closed"

echo "# an unreadable PR state is not mistaken for a closed PR (false success)"
store "[$(anchor A10 78), $(succ S10)]"
: > "$STUB_GH_LOG"
out=$(STUB_PR_VIEW_RC=1 "$SUT" --anchor A10 --successor S10 --kind duplicate 2>&1); rc=$?
eq "$rc" 1 "exits non-zero — an unreadable PR state is not a success"
eq "$(meta A10 'gc.pr_close_disposition_kind')" "duplicate" "the marker is still recorded (it is durable)"
has "$out" "could not be read" "reports the PR state was unreadable"
hasnt "$out" "already" "does NOT claim the PR is already closed/not open"
hasnt "$(cat "$STUB_GH_LOG")" "pr close" "and does not blind-close on a state it could not read"

echo "# gh pr close failing on an OPEN PR is an error, not a false success"
store "[$(anchor A11 79), $(succ S11)]"
: > "$STUB_GH_LOG"
out=$(STUB_PR_CLOSE_RC=1 "$SUT" --anchor A11 --successor S11 --kind duplicate 2>&1); rc=$?
eq "$rc" 1 "exits non-zero — the PR was not closed"
eq "$(meta A11 'gc.pr_close_disposition_kind')" "duplicate" "the marker is recorded"
has "$(cat "$STUB_GH_LOG")" "pr close 79" "the close was attempted"
has "$out" "still OPEN" "reports the PR is still open and needs closing"

echo "# dry-run writes nothing"
store "[$(anchor A9 77), $(succ S9)]"
: > "$STUB_GH_LOG"
out=$("$SUT" --anchor A9 --successor S9 --kind duplicate --dry-run 2>&1); rc=$?
eq "$rc" 0 "exits 0"
has "$out" "dry run" "announces the dry run"
eq "$(meta A9 'gc.pr_close_disposition_kind')" "<absent>" "no marker stamped under --dry-run"
hasnt "$(cat "$STUB_GH_LOG")" "pr close" "no PR close under --dry-run"

echo "# usage refusals"
"$SUT" --anchor A --successor B --kind bogus >/dev/null 2>&1; eq "$?" 2 "an out-of-set kind is refused (exit 2)"
"$SUT" --anchor A --successor B >/dev/null 2>&1;              eq "$?" 2 "a missing --kind is refused (exit 2)"
"$SUT" --successor B --kind duplicate >/dev/null 2>&1;        eq "$?" 2 "a missing --anchor is refused (exit 2)"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
