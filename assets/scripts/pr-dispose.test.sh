#!/usr/bin/env bash
# Hermetic test for assets/scripts/pr-dispose.sh — the sanctioned path that
# records a deliberate PR-close disposition on the open anchor and closes the
# PR, so the PR's closer consummates the terminal close through bead-rehome.sh.
# Covers: the marker stamped on an OPEN pull_request anchor; the marker stamped
# and the PR closed on an anchor on the pending record, pending or at a changed
# head, with the landing order named as its closer, and a closed anchor or an
# exception of that record refused;
# --no-close-pr stamping only; the PR closed through gh when the anchor is open,
# after a closing comment posted through pr-post.sh with the city's mark, which
# gates the close; gh view, comment and close pinned to the anchor's own pr_url
# repo, never the checkout origin; a --pr that contradicts the pr_url refused; the live PR identity
# certified against the anchor before closing; idempotent no-op on an
# already-disposed anchor; refusal on an anchor past the pull_request state
# (named bead-rehome as the direct verb); refusal on an anchor with no parseable
# pr_url; a marker the store refuses, which closes no PR; the successor store carried
# through when given and cleared when omitted; the close-mode failures that
# record the marker but exit non-zero (gh missing, an unreadable state, a
# failed closing comment or gh close); dry-run writing nothing; and the usage refusals (bad kind, missing
# args).
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

# gh: pr-dispose reads the PR (state, url and comments) and closes it, both
# pinned to the --repo it derives from the anchor's pr_url. The harness gh stub
# cats a whole fixture and has no `close`, so override it with a minimal one that
# serves a canned state (per PR, default OPEN), a url built from the pinned
# --repo and a canned conversation, and logs the closing comment and the close,
# honouring the refusal knobs. Written after harness_init so it wins on PATH.
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$BIN/gh" <<'GH'
set -u
printf '%s\n' "$*" >> "${STUB_GH_LOG:?}"
[ "${1:-}" = "pr" ] || { echo "gh stub: only 'pr' supported" >&2; exit 2; }
v="${2:-}"; shift 2 || true
num=""; repo=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) repo="${2:-}"; shift 2 ;;
    --*)    shift ;;
    *)      [ -z "$num" ] && num="$1"; shift ;;
  esac
done
# STUB_LOCK_PROBE names the record lock: each call then records whether the lock
# was free while GitHub was reached.
if [ -n "${STUB_LOCK_PROBE:-}" ]; then
  if flock -n "$STUB_LOCK_PROBE" true; then s=free; else s=held; fi
  printf 'pr %s: lock %s\n' "$v" "$s" >> "$STUB_LOCK_PROBE.probe"
fi
case "$v" in
  view)  [ -n "${STUB_PR_VIEW_RC:-}" ] && { echo "gh (stub): simulated pr view failure" >&2; exit "$STUB_PR_VIEW_RC"; }
         f="$STUB_GH_DIR/pr_state_$num"; st="OPEN"; [ -s "$f" ] && st="$(cat "$f")"
         # The url reflects the repo the SUT pinned (--repo, from the anchor's
         # pr_url), so its identity check certifies the live PR against the
         # anchor. STUB_PR_URL forces a mismatch to exercise that refusal.
         url="${STUB_PR_URL:-https://$repo/pull/$num}"
         # STUB_PR_COMMENTS is the PR's conversation, as a JSON array.
         printf '{"state":"%s","url":"%s","comments":%s}\n' "$st" "$url" "${STUB_PR_COMMENTS:-[]}" ;;
  comment) exit "${STUB_PR_COMMENT_RC:-0}" ;;
  close) exit "${STUB_PR_CLOSE_RC:-0}" ;;
  *)     echo "gh pr stub: unsupported '$v'" >&2; exit 2 ;;
esac
GH
chmod +x "$BIN/gh"

# bead-store.sh: pr-dispose takes the record lock of the store that holds the
# anchor, which it asks bead-store.sh --db to name. The stub names a store
# directory of the suite's own for every id, refuses while STUB_BS_RC is set,
# and logs each call.
DB="$TMP/rig/.beads"; mkdir -p "$DB"
LOCK="$DB/pr-record.lock"
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$SD/bead-store.sh" <<'BS'
printf '%s\n' "$*" >> "${STUB_BS_LOG:?}"
[ -z "${STUB_BS_RC:-}" ] || { echo "bead-store: (stub) no rig carries the prefix" >&2; exit "$STUB_BS_RC"; }
[ "${1:-}" = --db ] || { echo "bead-store stub: only --db" >&2; exit 2; }
printf '%s\n' "${STUB_BS_DB:?}"
BS
chmod +x "$SD/bead-store.sh"
export STUB_BS_LOG="$TMP/bead-store.log" STUB_BS_DB="$DB" STUB_BS_RC=""
: > "$STUB_BS_LOG"

# hold_lock [<jq filter>] — another writer of the record, such as a run of the
# landing order, holds the lock until release_lock. Given a filter, it applies
# it to the store as its last write, while it still holds the lock.
hold_lock() {
  rm -f "$TMP/held" "$TMP/go"; mkfifo "$TMP/go"
  flock "$LOCK" bash -c '
    : > "$1/held"; read -r _ < "$1/go"
    [ -z "$2" ] || { jq -c "$2" "$3" > "$3.tmp" && mv "$3.tmp" "$3"; }' _ "$TMP" "${1:-}" "$STUB_STORE" &
  HOLDER=$!
  for _ in $(seq 50); do [ -e "$TMP/held" ] && break; sleep 0.1; done
}
release_lock() { echo go > "$TMP/go"; wait "$HOLDER" 2>/dev/null || true; }

# An OPEN anchor gating a PR, plus the successor it points to. The pr_url
# defaults to the checkout's own repo but can be overridden (arg 4) to prove the
# gh calls follow the anchor's pr_url, not the checkout origin.
anchor() { # id num [extra-metadata] [pr_url-override]
  prurl="${4:-https://github.com/zook/gc-toolkit/pull/$2}"
  printf '{"id":"%s","status":"open","assignee":"rig/refinery","notes":"","title":"t","metadata":{"merge_result":"pull_request","pr_number":"%s","pr_url":"%s","branch":"polecat/%s"%s}}' \
    "$1" "$2" "$prurl" "$1" "${3:-}"
}
succ() { printf '{"id":"%s","status":"open","title":"successor","notes":"","metadata":{}}' "$1"; }

echo "# an OPEN pull_request anchor: the marker is stamped (--no-close-pr)"
store "[$(anchor A1 70), $(succ S1)]"
out=$("$SUT" --anchor A1 --successor S1 --kind duplicate --no-close-pr 2>&1); rc=$?
eq "$rc" 0 "exits 0"
eq "$(meta A1 'gc.pr_close_disposition_kind')" "duplicate" "kind stamped"
eq "$(meta A1 'gc.pr_close_disposition_successor')" "S1" "successor stamped"
eq "$(meta A1 'gc.pr_close_disposition_successor_store')" "<absent>" "no store key when none given"
eq "$(bstatus A1)" "open" "the anchor is NOT closed — that terminal close is pr-facts's"
eq "$(cat "$STUB_DEPS")" "" "…and no edge is written here (bead-rehome is its sole writer)"
hasnt "$(cat "$STUB_GH_LOG")" "pr close" "--no-close-pr closes no PR"

echo "# the PR is closed through gh when the anchor is open"
store "[$(anchor A2 71), $(succ S2)]"
: > "$STUB_GH_LOG"
out=$("$SUT" --anchor A2 --successor S2 --kind re-homed --note "ruled out" 2>&1); rc=$?
eq "$rc" 0 "exits 0"
eq "$(meta A2 'gc.pr_close_disposition_kind')" "re-homed" "kind stamped"
has "$(cat "$STUB_GH_LOG")" "pr close 71" "gh pr close was called for the PR"
has "$out" "closed PR#71" "reports the close"
has "$(cat "$STUB_GH_LOG")" "pr comment 71 --repo github.com/zook/gc-toolkit --body Closing as re-homed: disposition recorded on anchor A2 (successor S2)." \
  "the closing comment is posted on the PR"
has "$(cat "$STUB_GH_LOG")" "ruled out" "…carrying the note"
has "$(cat "$STUB_GH_LOG")" "<!-- gc:city -->" "…and the city's mark, so pr-facts never reads it back as feedback"
eq "$(grep -E '^pr (comment|close) ' "$STUB_GH_LOG" | cut -d' ' -f2 | tr '\n' ' ')" "comment close " \
  "the comment is posted before the close"
hasnt "$(grep '^pr close ' "$STUB_GH_LOG")" "--comment" "the close posts no comment of its own"

echo "# a recorded --successor-store is carried onto the marker"
store "[$(anchor A3 72), $(succ S3)]"
out=$("$SUT" --anchor A3 --successor bt-xyz --kind duplicate --successor-store rig:beta --no-close-pr 2>&1)
eq "$(meta A3 'gc.pr_close_disposition_successor_store')" "rig:beta" "store key stamped"

echo "# already disposed (closed naming a successor): no-op, nothing stamped, no close"
# The edge rides the row as `gc bd list` prints it, the row bd_disposed_to reads.
store "[$(anchor A4 73 | jq -c '.status = "closed" | .dependencies = [{issue_id: "A4", depends_on_id: "S9", type: "supersedes"}]'), $(succ S4)]"
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

echo "# an anchor on the pending record: the marker is stamped and the PR closed, for the landing order"
store "[$(anchor A30 100 | jq -c '.status = "blocked" | .metadata.merge_result = "pull_request_pending"'), $(succ S30)]"
: > "$STUB_GH_LOG"
out=$("$SUT" --anchor A30 --successor S30 --kind not-needed 2>&1); rc=$?
eq "$rc" 0 "exits 0"
eq "$(meta A30 'gc.pr_close_disposition_kind')" "not-needed" "kind stamped"
eq "$(meta A30 'gc.pr_close_disposition_successor')" "S30" "successor stamped"
eq "$(bstatus A30)" "blocked" "the anchor is left as it stands: its close is the landing order's"
has "$(cat "$STUB_GH_LOG")" "pr close 100" "the PR is closed"
has "$out" "the landing order disposes A30" "names the landing order as the closer"

echo "# …and one at a head the refinery has not validated yet"
store "[$(anchor A31 101 | jq -c '.metadata.merge_result = "pull_request_head_changed"'), $(succ S31)]"
: > "$STUB_GH_LOG"
out=$("$SUT" --anchor A31 --successor S31 --kind re-homed 2>&1); rc=$?
eq "$rc" 0 "exits 0"
eq "$(meta A31 'gc.pr_close_disposition_kind')" "re-homed" "kind stamped"
eq "$(bstatus A31)" "open" "the anchor is left open"
has "$(cat "$STUB_GH_LOG")" "pr close 101" "the PR is closed"

echo "# a closed anchor, or an exception of the pending record, is refused, naming bead-rehome"
for c in "A32 closed pull_request_pending" "A33 blocked pull_request_closed_unmerged"; do
  set -- $c
  store "[$(anchor "$1" 102 | jq -c --arg s "$2" --arg m "$3" '.status = $s | .metadata.merge_result = $m'), $(succ S32)]"
  : > "$STUB_GH_LOG"
  out=$("$SUT" --anchor "$1" --successor S32 --kind not-needed 2>&1); rc=$?
  eq "$rc" 1 "$2 at $3 exits 1"
  has "$out" "bead-rehome.sh --origin $1" "…naming the direct disposition verb"
  eq "$(meta "$1" 'gc.pr_close_disposition_kind')" "<absent>" "…with no marker stamped"
  hasnt "$(cat "$STUB_GH_LOG")" "pr " "…and no gh call"
done

pending() { anchor "$1" "$2" | jq -c '.status = "blocked" | .metadata.merge_result = "pull_request_pending"'; }

echo "# the read of the anchor and the stamp wait while another writer holds the record lock"
store "[$(pending A40 110), $(succ S40)]"
: > "$STUB_GH_LOG"; : > "$STUB_BS_LOG"
hold_lock
"$SUT" --anchor A40 --successor S40 --kind not-needed >"$TMP/out" 2>&1 &
RULING=$!
sleep 1
eq "$(meta A40 'gc.pr_close_disposition_kind')" "<absent>" "no marker is stamped while the lock is held"
hasnt "$(cat "$STUB_GH_LOG")" "pr " "…and GitHub is not reached"
release_lock
rc=0; wait "$RULING" || rc=$?
eq "$rc" 0 "the ruling goes ahead once the lock is free"
eq "$(meta A40 'gc.pr_close_disposition_kind')" "not-needed" "…the marker is stamped"
has "$(cat "$STUB_GH_LOG")" "pr close 110" "…and the PR is closed"
eq "$(cat "$STUB_BS_LOG")" "--db A40" "the lock is the one in the store that holds the anchor"

echo "# a run's last write before the lock frees is what the ruling reads"
# The run that held the lock read the PR closed with no ruling on the anchor and
# recorded the record's exception, so the ruling that waited finds an anchor
# past the pending record and stamps nothing.
store "[$(pending A41 111), $(succ S41)]"
: > "$STUB_GH_LOG"
hold_lock '(.[] | select(.id == "A41") | .metadata.merge_result) = "pull_request_closed_unmerged"'
"$SUT" --anchor A41 --successor S41 --kind not-needed >"$TMP/out" 2>&1 &
RULING=$!
sleep 1
release_lock
rc=0; wait "$RULING" || rc=$?
eq "$rc" 1 "the ruling reads the anchor the run left and refuses it"
has "$(cat "$TMP/out")" "bead-rehome.sh --origin A41" "…naming the direct disposition verb"
eq "$(meta A41 'gc.pr_close_disposition_kind')" "<absent>" "…with no marker stamped"
hasnt "$(cat "$STUB_GH_LOG")" "pr " "…and no gh call"

echo "# a lock that does not come within the wait writes nothing and closes no PR"
store "[$(pending A42 112), $(succ S42)]"
: > "$STUB_GH_LOG"
hold_lock
out=$(PR_RECORD_LOCK_WAIT_SECS=1 "$SUT" --anchor A42 --successor S42 --kind not-needed 2>&1); rc=$?
eq "$rc" 1 "exits 1"
has "$out" "record lock" "…naming the lock"
eq "$(meta A42 'gc.pr_close_disposition_kind')" "<absent>" "…with no marker stamped"
hasnt "$(cat "$STUB_GH_LOG")" "pr " "…and no gh call"

echo "# --dry-run takes no lock"
rc=0; out=$(timeout 10 "$SUT" --anchor A42 --successor S42 --kind not-needed --dry-run 2>&1) || rc=$?
eq "$rc" 0 "a dry run answers while the lock is held"
release_lock

echo "# a store that does not resolve writes nothing"
store "[$(pending A43 113), $(succ S43)]"
: > "$STUB_GH_LOG"
out=$(STUB_BS_RC=1 "$SUT" --anchor A43 --successor S43 --kind not-needed 2>&1); rc=$?
eq "$rc" 1 "exits 1"
has "$out" "did not resolve" "…saying the store did not resolve"
eq "$(meta A43 'gc.pr_close_disposition_kind')" "<absent>" "…with no marker stamped"
hasnt "$(cat "$STUB_GH_LOG")" "pr " "…and no gh call"

echo "# a gc call made under the lock runs without its descriptor, and GitHub is reached with the lock free"
store "[$(pending A44 114), $(succ S44)]"
: > "$STUB_GH_LOG"; rm -f "$LOCK.probe"
mv "$BIN/gc" "$BIN/gc.stub"
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$BIN/gc" <<'GC'
if { : >&9; } 2>/dev/null; then printf 'gc %s: fd 9 open\n' "$*" >> "${STUB_FD_LOG:?}"; fi
exec "$0.stub" "$@"
GC
chmod +x "$BIN/gc"
export STUB_FD_LOG="$TMP/fd9.log"; : > "$STUB_FD_LOG"
out=$(STUB_LOCK_PROBE="$LOCK" "$SUT" --anchor A44 --successor S44 --kind not-needed 2>&1); rc=$?
mv "$BIN/gc.stub" "$BIN/gc"
eq "$rc" 0 "exits 0"
eq "$(meta A44 'gc.pr_close_disposition_kind')" "not-needed" "…with the marker stamped"
eq "$(cat "$STUB_FD_LOG")" "" "no gc call holds the lock's descriptor"
has "$(cat "$LOCK.probe" 2>/dev/null)" "pr close: lock free" "the PR is closed with the lock free"
hasnt "$(cat "$LOCK.probe" 2>/dev/null)" "held" "…and every gh call finds it free"

echo "# a pull_request anchor with no parseable pr_url is refused before stamping"
store "[{\"id\":\"A6\",\"status\":\"open\",\"metadata\":{\"merge_result\":\"pull_request\",\"pr_number\":\"80\"}}, $(succ S6)]"
: > "$STUB_GH_LOG"
out=$("$SUT" --anchor A6 --successor S6 --kind duplicate 2>&1); rc=$?
eq "$rc" 1 "exits 1"
has "$out" "no parseable pr_url" "explains the missing pr_url — a bare number cannot pin the repo"
eq "$(meta A6 'gc.pr_close_disposition_kind')" "<absent>" "no marker stamped when the PR cannot be identified"
hasnt "$(cat "$STUB_GH_LOG")" "pr " "no gh call when the pr_url is unparseable"

echo "# a marker the store refuses closes nothing"
store "[$(anchor A7 75), $(succ S7)]"
: > "$STUB_GH_LOG"
out=$(STUB_UPDATE_FAIL=A7 "$SUT" --anchor A7 --successor S7 --kind duplicate 2>&1); rc=$?
eq "$rc" 1 "exits 1"
has "$out" "the store refused the disposition marker on A7" "reports the refused stamp"
hasnt "$(cat "$STUB_GH_LOG")" "pr close" "the PR is NOT closed when the marker did not land"

echo "# omitting --successor-store clears a stale store a prior attempt left"
store "[$(anchor A21 91 ',"gc.pr_close_disposition_successor_store":"rig:stale"'), $(succ S21)]"
: > "$STUB_GH_LOG"
out=$("$SUT" --anchor A21 --successor S21 --kind duplicate 2>&1); rc=$?
eq "$rc" 0 "exits 0 — the stale store was cleared and the marker is consistent"
eq "$(meta A21 'gc.pr_close_disposition_successor_store')" "<absent>" "the stale store is cleared when none is given"
eq "$(meta A21 'gc.pr_close_disposition_kind')" "duplicate" "the new marker is stamped"
has "$(cat "$STUB_GH_LOG")" "pr close 91" "the PR is closed after the marker is made consistent"

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

echo "# a closing comment that cannot be posted leaves the PR open, an error"
store "[$(anchor A12 81), $(succ S12)]"
: > "$STUB_GH_LOG"
out=$(STUB_PR_COMMENT_RC=1 "$SUT" --anchor A12 --successor S12 --kind duplicate 2>&1); rc=$?
eq "$rc" 1 "exits non-zero — the PR was not closed"
eq "$(meta A12 'gc.pr_close_disposition_kind')" "duplicate" "the marker is recorded"
has "$(cat "$STUB_GH_LOG")" "pr comment 81" "the comment was attempted"
hasnt "$(cat "$STUB_GH_LOG")" "pr close" "the PR is NOT closed without its closing comment"
has "$out" "still OPEN" "reports the PR is still open and needs closing"

echo "# a re-run after a failed close leaves one closing comment, not two"
# The first run posts the notice and dies on the close. The re-run finds that
# notice on the PR, posts nothing, and closes.
store "[$(anchor A27 97), $(succ S27)]"
: > "$STUB_GH_LOG"
out=$(STUB_PR_CLOSE_RC=1 "$SUT" --anchor A27 --successor S27 --kind duplicate 2>&1); rc=$?
eq "$rc" 1 "the first run dies on the failed close"
eq "$(grep -c '^pr comment 97 ' "$STUB_GH_LOG")" "1" "…after posting the closing comment"
POSTED_BODY=$(printf 'Closing as duplicate: disposition recorded on anchor A27 (successor S27). The refinery disposes the anchor from this close; no rework-or-close decision is owed.\n\n<!-- gc:city -->')
: > "$STUB_GH_LOG"
out=$(STUB_PR_COMMENTS="$(jq -cn --arg b "$POSTED_BODY" '[{author:{login:"gc-city-bot"},body:$b}]')" \
      "$SUT" --anchor A27 --successor S27 --kind duplicate 2>&1); rc=$?
eq "$rc" 0 "the re-run closes the PR"
hasnt "$(cat "$STUB_GH_LOG")" "pr comment" "…without posting the closing comment again"
has "$(cat "$STUB_GH_LOG")" "pr close 97" "…and the close is made"
has "$out" "already carries this disposition's closing comment" "…and says why it posted nothing"

echo "# …but a notice that is not this disposition's, or carries no mark, posts a fresh one"
store "[$(anchor A28 98), $(succ S28)]"
: > "$STUB_GH_LOG"
OTHER=$(jq -cn '[{body:"Closing as duplicate: disposition recorded on anchor A280 (successor S28).\n\n<!-- gc:city -->"},
                 {body:"Closing as re-homed: disposition recorded on anchor A28 (successor S28).\n\n<!-- gc:city -->"},
                 {body:"Closing as duplicate: disposition recorded on anchor A28 (successor S28). quoted by hand"}]')
out=$(STUB_PR_COMMENTS="$OTHER" "$SUT" --anchor A28 --successor S28 --kind duplicate 2>&1); rc=$?
eq "$rc" 0 "exits 0"
eq "$(grep -c '^pr comment 98 ' "$STUB_GH_LOG")" "1" "another anchor's notice, another kind's, or an unmarked copy does not count as posted"
has "$(cat "$STUB_GH_LOG")" "pr close 98" "…and the PR is closed"

echo "# gh calls follow the anchor's pr_url repo, NOT the checkout origin"
# The reviewed bug: #NUM was aimed at the checkout's origin, so an anchor read
# cross-rig could close a same-numbered PR in the wrong repository. Here the
# anchor's pr_url names a different repo than the checkout origin; the view and
# the close must both target the pr_url's repo.
store "[$(anchor A23 93 '' 'https://github.com/other/proj/pull/93'), $(succ S23)]"
: > "$STUB_GH_LOG"
out=$(STUB_ORIGIN_URL="https://github.com/zook/gc-toolkit" "$SUT" --anchor A23 --successor S23 --kind duplicate 2>&1); rc=$?
eq "$rc" 0 "closes against the pr_url's repo"
has "$(cat "$STUB_GH_LOG")" "pr view 93 --repo github.com/other/proj" "reads the PR in the anchor's own repo"
has "$(cat "$STUB_GH_LOG")" "pr comment 93 --repo github.com/other/proj" "comments on the PR in the anchor's own repo"
has "$(cat "$STUB_GH_LOG")" "pr close 93 --repo github.com/other/proj" "closes the PR in the anchor's own repo"
hasnt "$(cat "$STUB_GH_LOG")" "github.com/zook/gc-toolkit" "never aims a gh call at the checkout origin repo"

echo "# a --pr that contradicts the anchor's pr_url is refused before any gh call"
store "[$(anchor A25 95), $(succ S25)]"
: > "$STUB_GH_LOG"
out=$("$SUT" --anchor A25 --successor S25 --kind duplicate --pr 999 2>&1); rc=$?
eq "$rc" 1 "a mismatched --pr is refused"
has "$out" "does not match the anchor's pr_url" "explains the mismatch"
eq "$(meta A25 'gc.pr_close_disposition_kind')" "<absent>" "no marker stamped on a mismatched --pr"
hasnt "$(cat "$STUB_GH_LOG")" "pr " "no gh call on a mismatched --pr"

echo "# the live PR identity is certified against the anchor before closing"
store "[$(anchor A26 96), $(succ S26)]"
: > "$STUB_GH_LOG"
# gh returns a PR whose url is a different repo than the anchor's pr_url, as a
# transferred or renamed repo would redirect: refuse rather than close it.
out=$(STUB_PR_URL="https://github.com/moved/elsewhere/pull/96" "$SUT" --anchor A26 --successor S26 --kind duplicate 2>&1); rc=$?
eq "$rc" 1 "a live PR whose url does not match the anchor is refused"
has "$out" "not the anchor's pr_url" "reports the identity mismatch"
eq "$(meta A26 'gc.pr_close_disposition_kind')" "duplicate" "the marker is recorded (identity is checked in the close path)"
hasnt "$(cat "$STUB_GH_LOG")" "pr close" "the PR is NOT closed on an identity mismatch"

echo "# in close mode with gh missing, the marker is recorded but the exit is non-zero"
store "[$(anchor A24 94), $(succ S24)]"
: > "$STUB_GH_LOG"
# gh is on the system PATH, so simulate its absence with a curated PATH: the two
# stubs plus the real tools the SUT and the gc stub need, flock among them, and
# no gh.
NOGH="$TMP/nogh"; mkdir -p "$NOGH"
for s in gc git; do ln -sf "$BIN/$s" "$NOGH/$s"; done
for t in bash env jq tr awk cat cp mv rm mktemp sed grep dirname flock; do
  p="$(command -v "$t" 2>/dev/null)" && ln -sf "$p" "$NOGH/$t"
done
out=$(PATH="$NOGH" "$SUT" --anchor A24 --successor S24 --kind duplicate 2>&1); rc=$?
eq "$rc" 1 "gh missing in close mode exits non-zero (no false success)"
eq "$(meta A24 'gc.pr_close_disposition_kind')" "duplicate" "the marker is still recorded (it is durable)"
has "$out" "gh is not available" "reports gh was unavailable"
hasnt "$out" "already" "does NOT claim the PR is closed or disposed"
hasnt "$(cat "$STUB_GH_LOG")" "pr close" "no PR close attempted when gh is missing"

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
