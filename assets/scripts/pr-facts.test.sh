#!/usr/bin/env bash
# Hermetic test for assets/scripts/pr-facts.sh — external PR facts, no merge
# authority. Covers: recording an out-of-band merge (never with an empty
# merged_sha); abandoned (+ escalate); retargeted (+ escalate, check markers
# cleared, human-routed); BLOCKED -> escalate only an unresolved-thread block
# (merge-blocked-threads, read from reviewThreads because reviewDecision is
# masked while threads are open; no guess when the read fails, and an operator
# merge_hold left alone) while a pending required approving review files no visit
# and any stale merge-blocked-approval visit is retired; CONFLICTING -> one rework child per head (dedup on
# branch+head, holds and a live demand veto, unstamped orphans adopted),
# stamped prepare_mode=merge (every branch brought current by merge, never rebase),
# counted as dispatched only once that stamp AND the route read back, with a
# child stranded by a lost route stamp re-routed rather than buried by the
# dedup; stale-gate -> one re-review child per head, carrying mol-review via
# gc sling --on (dedup, pour read-back, fix_target_pool stamped);
# and dismissing our OWN superseded CHANGES_REQUESTED (marker recorded first;
# auto-merge armed skips; a human's review is never dismissed).
# Also covers --posture-only (the pre-merge arm: records posture, dispatches
# nothing, leaves MERGED/CLOSED reconciliation to the full pass, and reports an
# anchor it could not make current in its EXIT CODE, which is what holds
# merge.sh for that pass);
# Also covers the status: label moving in the arm that records a review: each
# early arm re-derives it for an anchor whose posture value it changes or
# whose feedback batch it routes, a merge state moving alone is left to the full
# pass, and the full pass's own re-derive reads the labels its sweep just wrote;
# Also covers the POSTURE record and the comment watermark: the declared
# vocabulary, posture pinned to the live head and written only on change, an
# unanswered comment routing to a fix-pool child or (under a human hold) to a
# visit, the watermark advancing only after both that child's mode and its route
# read back, a comment above the mark re-firing while one below it stays
# answered, and the reads that record nothing rather than clear a standing
# `commented`.
# Also covers the validation pass such a batch ensures: a live check_name=human
# task_kind=validation bead anchored to the PR (the lane the validator rules,
# never the whole check_set — a multi-lane anchor still gets one human-lane pass)
# pinned to the head, blocking the anchor so an already-green PR cannot merge
# until the validator closes it, left unrouted for gate-ensure to dispatch,
# deduped by the live human-lane pass so a later batch reuses the open one rather
# than opening another (a correctness pass on the anchor does not stand in for it) and
# adopted by title when a prior stamp dropped. Opening it
# fails closed: a pass that did not record the shape the validator consumes
# (anchor_bead, check_name=human, the head pin) or an unattachable blocks edge
# holds the batch unwatermarked to retry. A capped anchor
# keeps its park (retired on signoff.sh's side, not here) and its feedback goes to
# the person; a verdict the city posted itself and a rework hand-back are not
# feedback and open no pass.
# Write-back: EYES on a routed comment; a question-mark answer naming the visit
# while a comment's batch waits on an open one, or its finding on a needs-you
# ruling; once the batch's bead closes and the comment's finding has closed, one
# check-mark answer naming what resolved it and EYES traded for THUMBS_UP, in the
# thread (resolved behind it) for an inline comment and on the Conversation tab,
# linking to the comment, for a review body or a Conversation comment; each
# space's batch read from its own ledger, which the routing transition writes;
# idempotent across passes; nothing for a comment no batch places, for our own
# comments, or for a thread a human answered after us; and the answers bounded
# to the batch each comment belongs to, so an earlier batch's comment is never
# told a later bead answered it; and the answers held back whenever a pass
# cannot finish the batch's pickup reactions, whether the cap or a failed write
# left them owing, or a comment in the thread sits above the mark with no batch
# covering it yet.
#
# The sections run in the parts declared below, each wrapped in an `if part`
# block. tools/run-tests.sh runs each part as its own run under its own
# timeout; run directly, the file runs every part in order.
# run-tests-parts: reconcile posture feedback writeback checks pacing
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-pr-facts-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"
# pr-facts.sh records what it observes through lifecycle.sh, which execs gctk.
harness_build_gctk
harness_init

# The value@oid half of a dated key. pr_posture carries a third @<since>
# component, stamped by lifecycle.sh under compare-and-preserve: an unmet
# approval requirement is one of the causes that start the owed clock the helm
# board ranks its queue by, so the recorded posture has to date its own turn.
# Assertions about WHAT was recorded and at which head read through this; the
# instant has its own coverage at the end of the posture section.
meta_pinned() { local v; v="$(meta "$1" "$2")"; case "$v" in *@*@*) printf '%s' "${v%@*}" ;; *) printf '%s' "$v" ;; esac; }
# The id of the (single) live validation pass on an anchor, or <none>. A human
# feedback batch opens one; assertions read its shape through this.
vpass_id() { jq -r --arg a "$1" '[ .[] | select((.metadata.task_kind // "") == "validation") | select((.metadata.anchor_bead // "") == $a) | select((.status // "open") != "closed") | .id ] | .[0] // "<none>"' "$STUB_STORE"; }

SD="$TMP/scripts"
mk_sut_dir "$SD" "$HERE/pr-facts.sh" "$HERE/lifecycle.sh" "$HERE/record-failure-cap.sh" "$HERE/finding.sh" "$HERE/review-checks.sh" "$HERE/visit-close.sh" "$HERE/finalize-gate.sh"
# escalate.sh's contract, not just its call log: ONE visit per subject+key,
# stamped so the caller can find it again. pr-facts reads the visit back to
# block the anchor on it, so a stub that only logged would test nothing.
# --retract is the counterpart: it closes every OPEN visit for the situation
# that nobody is engaged in as moot, leaves an engaged one (claimed, or bound by
# assignee or session) to its holder, and is a no-op success when none matches.
# STUB_RETRACT_FAIL makes a retract fail having closed nothing.
cat > "$SD/escalate.sh" <<'ESC'
#!/usr/bin/env bash
set -u
printf '%s\n' "$*" >> "${STUB_ESC_LOG:?}"
subj=""; key=""; msg=""; retract=0
while [ $# -gt 0 ]; do
  case "$1" in
    --subject) shift; subj="${1:-}" ;;
    --key)     shift; key="${1:-}" ;;
    --message) shift; msg="${1:-}" ;;
    --retract) retract=1 ;;
  esac
  shift || true
done
[ -n "$subj" ] && [ -n "$key" ] || exit 2
if [ "$retract" = 1 ]; then
  [ -z "${STUB_RETRACT_FAIL:-}" ] || exit 1
  open=$(jq -r --arg s "$subj" --arg k "$key" '
    .[] | select((.status // "open") == "open")
      | select(((.metadata["gc.continuation_group"] // "") | tostring) == $s)
      | select(((.metadata.escalation_key // "") | tostring) == $k)
      | select(((.assignee // "") | tostring) == "" and ((.metadata["gc.session_name"] // "") | tostring) == "")
      | .id' "${STUB_STORE:?}")
  rrc=0
  for v in $open; do
    gc bd update "$v" --status=closed --set-metadata gc.outcome=moot \
      --set-metadata "gc.outcome_reason=$msg" >/dev/null || rrc=1
  done
  exit "$rrc"
fi
have=$(jq -r --arg s "$subj" --arg k "$key" '
  [ .[] | select((.status // "open") != "closed")
    | select(((.metadata["gc.continuation_group"] // "") | tostring) == $s)
    | select(((.metadata.escalation_key // "") | tostring) == $k) | .id ] | .[0] // empty' "${STUB_STORE:?}")
[ -n "$have" ] && exit 0
vid=$(gc bd create "visit: $subj — $key" -t task --json | jq -r '.id // empty')
[ -n "$vid" ] || exit 1
gc bd update "$vid" --set-metadata "escalation_key=$key" \
  --set-metadata "gc.continuation_group=$subj" --set-metadata "task_kind=visit" >/dev/null
gc bd dep add "$vid" "$subj" --type=tracks >/dev/null 2>&1 || true
ESC
printf '#!/usr/bin/env bash\necho "METHOD${2:+ note: $2}"\n' > "$SD/review-dispatch-body.sh"
# validate-dispatch-body.sh's real output is prose the validator reads; the test
# only needs a non-empty note so the validation-pass open takes its body path.
printf '#!/usr/bin/env bash\necho "VALIDATE-METHOD${2:+ note: $2}"\n' > "$SD/validate-dispatch-body.sh"
chmod +x "$SD/escalate.sh" "$SD/review-dispatch-body.sh" "$SD/validate-dispatch-body.sh"
export STUB_ESC_LOG="$TMP/esc.log"; : > "$STUB_ESC_LOG"
# bead-rehome.sh, the sanctioned terminal close pr-facts consummates a
# pre-recorded disposition through. The contract that matters here: on success
# it stamps gc.superseded_by and CLOSES the origin; STUB_REHOME_RC models the
# refusals it reports without closing (4 transient, 5/6 a human is needed).
# It also models the two real holds on that close, each exit 5, in the real
# order. The finalize gate runs first, and it is the real finalize-gate.sh: an
# OPEN visit on the origin holds the close, except a visit filed under the key
# --except-key names that nobody is engaged in. Without it, a stub that ignored
# visits would pass an anchor its own escalation holds forever. Then the close is
# NOT --force, so an OPEN bead that still `blocks` the origin refuses it. Without
# that, a stub that closed straight through a blocking rework child would
# green-light the strand pr-facts's dispose-children-first order exists to
# prevent — an anchor stranded open behind a rework child it cannot close.
cat > "$SD/bead-rehome.sh" <<'REHOME'
#!/usr/bin/env bash
set -u
printf '%s\n' "$*" >> "${STUB_REHOME_LOG:?}"
origin=""; succ=""; store=""; except=""
while [ $# -gt 0 ]; do
  case "$1" in
    --origin)          shift; origin="${1:-}" ;;
    --successor)       shift; succ="${1:-}" ;;
    --successor-store) shift; store="${1:-}" ;;
    --except-key)      shift; except="${1:-}" ;;
  esac
  shift || true
done
rc="${STUB_REHOME_RC:-0}"
if [ "$rc" != "0" ]; then echo "bead-rehome (stub): refusing rc=$rc" >&2; exit "$rc"; fi
fg=(check "$origin"); [ -n "$except" ] && fg+=(--except-key "$except")
if ! why=$("$(dirname "$0")/finalize-gate.sh" "${fg[@]}" 2>/dev/null); then
  echo "bead-rehome (stub): the close is held: $why (exit 5)" >&2
  exit 5
fi
# Real close: drop ONLY the origin->successor wait edge, then close WITHOUT
# --force. Any OTHER open blocker (a rework child that blocks this anchor) refuses
# the close, leaving the bead OPEN and pointed — exit 5, the shape pr-facts reads
# as "a human is needed" and never as a clean dispose.
gc bd dep remove "$origin" "$succ" >/dev/null 2>&1 || true
if [ "$(gc bd dep list "$origin" --direction=down -t blocks --json 2>/dev/null \
        | jq '[ .[] | select((.status // "open") != "closed") ] | length' 2>/dev/null || echo 0)" != "0" ]; then
  echo "bead-rehome (stub): $origin has an OPEN blocker; non-force close refused (exit 5)" >&2
  exit 5
fi
if [ -n "$store" ]; then
  gc bd update "$origin" --status=closed --set-metadata "gc.superseded_by=$succ" --set-metadata "gc.superseded_by_store=$store" >/dev/null 2>&1 || exit 5
else
  gc bd update "$origin" --status=closed --set-metadata "gc.superseded_by=$succ" >/dev/null 2>&1 || exit 5
fi
exit 0
REHOME
chmod +x "$SD/bead-rehome.sh"
export STUB_REHOME_LOG="$TMP/rehome.log"; : > "$STUB_REHOME_LOG"
SUT="$SD/pr-facts.sh"
FIX="rig/gc-toolkit.polecat"; REV="rig/gc-toolkit.polecat-codex"
run() { "$SUT" --fix-pool "$FIX" --review-pool "$REV" 2>&1; }
run_posture() { "$SUT" --posture-only 2>&1; }

anchor() { # id num extra [branch]
  printf '{"id":"%s","status":"open","assignee":"rig/refinery","notes":"","title":"t","metadata":{"merge_result":"pull_request","pr_number":"%s","pr_url":"https://github.com/zook/gc-toolkit/pull/%s","branch":"%s","merged_target":"main","check_set":"correctness","check.correctness":"green"%s}}' \
    "$1" "$2" "$2" "${4:-polecat/x$2}" "${3:-}"
}
prview() { # num state mergeState mergeable extra [headRefName]
  printf '{"state":"%s","isDraft":false,"baseRefName":"main","headRefName":"%s","headRefOid":"sha-%s","headRepository":{"name":"gc-toolkit"},"headRepositoryOwner":{"login":"zook"},"isCrossRepository":false,"mergeStateStatus":"%s","mergeable":"%s","reviewDecision":"","url":"https://github.com/zook/gc-toolkit/pull/%s","mergeCommit":{"oid":"merged-sha-%s"},"autoMergeRequest":null%s}' \
    "$2" "${6:-polecat/x$1}" "$1" "$3" "$4" "$1" "$1" "${5:-}"
}
# A standing approval on PR <num> from an account other than the city's: what
# the conflict arm's merge-in waits for (review-verdict.sh). Its id sits far
# above every review-id watermark the fixtures use, and an APPROVED review is
# never feedback, so it moves no watermark.
approve() { # num [login]
  printf '[{"id":%s,"user":{"login":"%s"},"state":"APPROVED","body":"","commit_id":"sha-%s","submitted_at":"2026-08-20T01:00:00Z"}]' \
    "$((880000 + $1))" "${2:-human1}" "$1" > "$GH_DIR/reviews_$1.json"
}

# What `gc-helm.sh demand` files when a sitting holds an anchor: the bead the
# person owes, gating the anchor. Its liveness — never the gc.takeaway headline
# beside it — is what says a sitting is still waiting on somebody.
demand() { # <anchor-id> [status]
  printf '{"id":"dm-%s","status":"%s","assignee":"","title":"Rule on %s","notes":"","metadata":{"gc.demand_for":"%s","gc.routed_to":"human"}}' \
    "$1" "${2:-open}" "$1" "$1"
}

# A parked rework child: shares the anchor's branch, carries a merge-in resume
# (prepare_mode=merge), routed to the fix pool, and — like every child — no
# merge_result of its own. `extra` appends metadata (a rebase_hold freeze);
# status/assignee default to the parked shape (open, unclaimed).
child() { # id branch [extra-metadata] [status] [assignee]
  printf '{"id":"%s","status":"%s","assignee":"%s","notes":"","title":"Merge main into %s:","metadata":{"branch":"%s","target":"main","prepare_mode":"merge","gc.routed_to":"rig/gc-toolkit.polecat"%s}}' \
    "$1" "${4:-open}" "${5:-}" "$2" "$2" "${3:-}"
}

ROOT="$(cd "$HERE/../.." && pwd)"

# ==== part reconcile: merged, closed, retargeted and conflicting PRs ====
if part reconcile; then

echo "# every section sits inside a part"
# A run executes only its own part's block, so a section outside every block
# would run once per part. Blocks open with `if part <name>; then` and close
# with `fi # part <name>`, both at the start of a line.
OUTSIDE=$(awk '/^if part [A-Za-z0-9_-]+; then$/ { inside = 1; next }
               /^fi # part [A-Za-z0-9_-]+$/ { inside = 0; next }
               /^echo "# / && !inside { print NR ": " $0 }' "$HERE/pr-facts.test.sh")
eq "$OUTSIDE" "" "no section header sits outside a part"

echo "# posture vocabulary drift against lifecycle.toml"
BLOCK="$(awk '/# >>> pr-posture-vocabulary/{f=1;next} /# <<< pr-posture-vocabulary/{f=0} f' "$HERE/pr-facts.sh")"
[ -n "$BLOCK" ] && ok "posture-vocabulary block extracted" || bad "posture-vocabulary markers missing"
eval "$BLOCK"
TOML_POSTURES=$(sed -n 's/^postures = \[\(.*\)\]/\1/p' "$ROOT/lifecycle/lifecycle.toml" | tr -d '",' | sed 's/^ *//;s/ *$//' | tr -s ' ')
eq "$PR_POSTURES" "$TOML_POSTURES" "postures match lifecycle.toml [posture]"

echo "# metadata-key drift against lifecycle.toml"
# A metadata key is state, and the registry is the exhaustive declaration
# downstream audits read (docs/component-model.md). A key these scripts write
# but nothing registers is state no audit can account for. pr-dispose.sh and
# demo-deliver.sh are covered alongside pr-facts.sh: each WRITES a key pr-facts
# only reads — the PR-close disposition marker and artifact_url — so a drift
# check scanning pr-facts alone would never see those writes.
REGISTERED=$(sed -n '/^# The metadata-key registry/,$p' "$ROOT/lifecycle/lifecycle.toml" \
  | sed 's/#.*//' | grep -oE '"[^"]+"' | tr -d '"' | sort -u)
# pr-facts.sh writes anchor metadata through three flags: bd's --set-metadata,
# and lifecycle.sh transition's --set and --set-dated. All three are state the
# registry must declare, so the extraction reads every one — a key written only
# through lifecycle would otherwise drift unseen.
WRITTEN=$(grep -hoE -- '--set(-metadata|-dated)? "?[A-Za-z_][A-Za-z0-9_.]*=' "$HERE/pr-facts.sh" "$HERE/pr-dispose.sh" "$HERE/demo-deliver.sh" \
  | sed -E 's/^--set(-metadata|-dated)? "?//; s/=$//' | sort -u)
[ -n "$WRITTEN" ] && ok "metadata-key writes extracted" || bad "no metadata-key writes found in pr-facts.sh/pr-dispose.sh/demo-deliver.sh"
UNREGISTERED=$(printf '%s\n' "$WRITTEN" \
  | grep -Fxv -f <(printf '%s\n' "$REGISTERED") | tr '\n' ' ' | sed 's/ *$//') || true
eq "$UNREGISTERED" "" "every metadata key pr-facts.sh, pr-dispose.sh and demo-deliver.sh write is registered in lifecycle.toml"

echo "# out-of-band merge is recorded"
store "[$(anchor F1 10)]"
printf '%s' "$(prview 10 MERGED CLEAN MERGEABLE)" > "$GH_DIR/pr_view_10.json"
out=$(run); rc=$?
eq "$rc" 0 "record pass exits 0"
has "$out" "recorded F1 — PR#10 is MERGED" "the merged fact is recorded"
eq "$(bstatus F1)" "closed" "anchor closed"
eq "$(meta F1 merge_result)" "merged" "merge_result=merged"
eq "$(meta F1 merged_sha)" "merged-sha-10" "merged_sha recorded"
hasnt "$(cat "$STUB_GH_LOG")" "pr merge" "pr-facts never merges"
hasnt "$(cat "$STUB_GC_LOG")" "bd close" "the record never uses the \`bd close\` verb, whose ownership check refuses a bead assigned to another principal"

# This arm and merge.sh's two record arms perform the same repair on the same
# anchor, so their failures count against ONE budget: a backstop keeping its own
# tally would let each writer sit forever at two-of-three while the anchor is
# refused on every pass by both. record-failure-cap.sh is the shared counter, and
# STUB_CLOSE_FAIL is what makes this the real shape rather than a total outage —
# the close is refused and the counter beside it still writes, which is bd's own
# asymmetry.
echo "# the out-of-band record shares the retry budget"
store "[$(anchor F1b 12)]"
printf '%s' "$(prview 12 MERGED CLEAN MERGEABLE)" > "$GH_DIR/pr_view_12.json"
: > "$STUB_ESC_LOG"
out=$(STUB_CLOSE_FAIL="F1b" run 2>&1)
has "$out" "record failed for F1b" "a refused record is still reported"
eq "$(meta F1b merge_record_failures)" "1" "…and counted on the anchor, in the same key merge.sh counts in"
eq "$(cat "$STUB_ESC_LOG")" "" "…escalating nothing under the cap"

# A count merge.sh already carried is what this arm's failure lands on top of,
# which is the whole point of one budget: the third failure escalates whichever
# writer reaches it.
store "[$(anchor F1c 13 ',"merge_record_failures":"2"')]"
printf '%s' "$(prview 13 MERGED CLEAN MERGEABLE)" > "$GH_DIR/pr_view_13.json"
: > "$STUB_ESC_LOG"
out=$(STUB_CLOSE_FAIL="F1c" run 2>&1)
eq "$(meta F1c merge_record_failures)" "3" "a failure here counts on top of merge.sh's"
has "$(cat "$STUB_ESC_LOG")" "--key merge-record-failed.13" "…and reaching the cap escalates from this arm too"

# The record that lands clears the shared count.
store "[$(anchor F1d 14 ',"merge_record_failures":"2"')]"
printf '%s' "$(prview 14 MERGED CLEAN MERGEABLE)" > "$GH_DIR/pr_view_14.json"
out=$(run)
eq "$(bstatus F1d)" "closed" "the record lands"
eq "$(meta F1d merge_record_failures)" "<absent>" "…and clears the count it inherited"

echo "# closed-unmerged -> abandoned + escalate"
store "[$(anchor F2 11)]"
printf '%s' "$(prview 11 CLOSED CLEAN MERGEABLE)" > "$GH_DIR/pr_view_11.json"
: > "$STUB_ESC_LOG"
out=$(run)
has "$out" "closed out-of-band; abandoned" "the abandonment is recorded"
eq "$(meta F2 merge_result)" "abandoned" "merge_result=abandoned"
eq "$(bstatus F2)" "open" "the anchor stays OPEN (work did not land)"
eq "$(meta F2 'gc.routed_to')" "human" "routed to human"
eq "$(bassignee F2)" "" "assignee cleared"
has "$(cat "$STUB_ESC_LOG")" "--subject F2 --key pr-abandoned.11" "escalate.sh got the situation key"

# The default above is preserved: an out-of-band close with no recorded
# disposition still abandons and files the visit. The cases below cover a close
# whose disposition WAS pre-recorded (assets/scripts/pr-dispose.sh) — pr-facts
# consummates it through bead-rehome.sh instead of re-asking the decision.
echo "# closed-unmerged + pre-recorded disposition -> auto-dispose, no visit"
store "[$(anchor F2a 21 ',"gc.pr_close_disposition_kind":"duplicate","gc.pr_close_disposition_successor":"tk-succ"')]"
printf '%s' "$(prview 21 CLOSED CLEAN MERGEABLE)" > "$GH_DIR/pr_view_21.json"
: > "$STUB_ESC_LOG"; : > "$STUB_REHOME_LOG"
out=$(run)
has "$out" "auto-disposed (duplicate -> tk-succ)" "the disposition is consummated, not abandoned"
has "$(cat "$STUB_REHOME_LOG")" "--origin F2a --successor tk-succ --kind duplicate" "bead-rehome got the recorded disposition"
eq "$(bstatus F2a)" "closed" "the anchor is closed via the sanctioned terminal path"
eq "$(meta F2a 'gc.superseded_by')" "tk-succ" "gc.superseded_by is stamped (the terminal state I5 accepts)"
eq "$(meta F2a merge_result)" "pull_request" "merge_result is NOT flipped to abandoned"
eq "$(cat "$STUB_ESC_LOG")" "" "…and NO rework-or-close visit is filed"

echo "# a pre-recorded disposition retires a stale rework-or-close visit"
store "[$(anchor F2b 22 ',"gc.pr_close_disposition_kind":"not-needed","gc.pr_close_disposition_successor":"tk-vis"'), {\"id\":\"V22\",\"status\":\"open\",\"title\":\"visit\",\"notes\":\"\",\"metadata\":{\"escalation_key\":\"pr-abandoned.22\",\"gc.continuation_group\":\"F2b\",\"task_kind\":\"visit\",\"gc.routed_to\":\"human\"}}]"
printf '%s' "$(prview 22 CLOSED CLEAN MERGEABLE)" > "$GH_DIR/pr_view_22.json"
: > "$STUB_ESC_LOG"
out=$(run)
eq "$(bstatus F2b)" "closed" "the anchor is disposed"
eq "$(bstatus V22)" "closed" "the stale visit is retired"
eq "$(meta V22 'gc.outcome')" "moot" "…closed moot — the question it asked is answered"
has "$(meta V22 'gc.outcome_reason')" "F2b disposed (not-needed -> tk-vis)" "…with a reason, which the board shows as the sitting's headline"
has "$out" "retired stale visit V22" "the retirement is reported"

# The sitting that recorded the disposition can still hold the visit. bd's close
# verb refuses a bead assigned to another actor, and pr-facts holds no visit, so
# the retire passes --force. STUB_ENFORCE_CLOSE_OWNER makes the stub refuse a
# plain close the way bd does, so this case fails if the --force is dropped.
echo "# a pre-recorded disposition retires the rework-or-close visit a sitting still holds"
store "[$(anchor F2n 39 ',"gc.pr_close_disposition_kind":"not-needed","gc.pr_close_disposition_successor":"tk-vn"'), {\"id\":\"VN\",\"status\":\"in_progress\",\"assignee\":\"lx-sitting\",\"title\":\"visit\",\"notes\":\"\",\"metadata\":{\"escalation_key\":\"pr-abandoned.39\",\"gc.continuation_group\":\"F2n\",\"task_kind\":\"visit\",\"gc.routed_to\":\"human\"}}]"
printf '%s' "$(prview 39 CLOSED CLEAN MERGEABLE)" > "$GH_DIR/pr_view_39.json"
: > "$STUB_ESC_LOG"
out=$(STUB_ENFORCE_CLOSE_OWNER=1 run)
eq "$(bstatus VN)" "closed" "the held visit is retired over the sitting's claim"
eq "$(meta VN 'gc.outcome')" "moot" "…closed moot"
has "$(meta VN 'gc.outcome_reason')" "F2n disposed (not-needed -> tk-vn)" "…with its reason"
eq "$(bstatus F2n)" "closed" "the anchor is disposed in the same pass"

echo "# a disposition bead-rehome refused (human needed) -> distinct escalation, anchor left open"
store "[$(anchor F2c 23 ',"gc.pr_close_disposition_kind":"duplicate","gc.pr_close_disposition_successor":"tk-c"')]"
printf '%s' "$(prview 23 CLOSED CLEAN MERGEABLE)" > "$GH_DIR/pr_view_23.json"
: > "$STUB_ESC_LOG"
out=$(STUB_REHOME_RC=5 run)
eq "$(bstatus F2c)" "open" "the anchor is left OPEN for repair"
eq "$(meta F2c merge_result)" "pull_request" "…still enumerable, so the next pass retries"
eq "$(meta F2c 'gc.superseded_by')" "<absent>" "nothing was disposed"
has "$(cat "$STUB_ESC_LOG")" "--subject F2c --key pr-dispose-failed.23" "escalated under a DISTINCT key"
hasnt "$(cat "$STUB_ESC_LOG")" "pr-abandoned.23" "…never the generic rework-or-close visit"

echo "# a disposition whose pointer would not stick (transient) -> skip, retry, no escalation"
store "[$(anchor F2d 24 ',"gc.pr_close_disposition_kind":"duplicate","gc.pr_close_disposition_successor":"tk-d"')]"
printf '%s' "$(prview 24 CLOSED CLEAN MERGEABLE)" > "$GH_DIR/pr_view_24.json"
: > "$STUB_ESC_LOG"
out=$(STUB_REHOME_RC=4 run)
eq "$(bstatus F2d)" "open" "the anchor is left OPEN"
eq "$(meta F2d merge_result)" "pull_request" "…still enumerable for the retry"
eq "$(cat "$STUB_ESC_LOG")" "" "a transient failure escalates nothing"
has "$out" "retry next pass" "the transient skip is reported"

echo "# a malformed disposition (kind set, successor missing) falls through to the default"
store "[$(anchor F2e 25 ',"gc.pr_close_disposition_kind":"duplicate"')]"
printf '%s' "$(prview 25 CLOSED CLEAN MERGEABLE)" > "$GH_DIR/pr_view_25.json"
: > "$STUB_ESC_LOG"; : > "$STUB_REHOME_LOG"
out=$(run)
eq "$(cat "$STUB_REHOME_LOG")" "" "bead-rehome is not called on a malformed marker"
eq "$(meta F2e merge_result)" "abandoned" "the default abandon still runs"
has "$(cat "$STUB_ESC_LOG")" "--subject F2e --key pr-abandoned.25" "…and the rework-or-close visit is filed"

# The marker is read from a FRESH anchor read, not from the row captured at
# enumeration: pr-dispose.sh stamps it just before it closes the PR, which can
# fall AFTER this pass enumerated the anchor. Reading the stale row would abandon
# a deliberately-disposed anchor.
echo "# a marker set after enumeration but before the CLOSED re-read is honored (race)"
cat > "$TMP/stamp-hook.sh" <<'HOOK'
#!/usr/bin/env bash
# Models pr-dispose.sh landing the marker between enumeration and the re-read:
# stamp it on a show of the raced anchor, so the enumerated row never had it.
[ "$1" = "F2f" ] || exit 0
tmp=$(mktemp)
jq -c --arg id "$1" 'map(if .id == $id then
    .metadata["gc.pr_close_disposition_kind"] = "duplicate"
    | .metadata["gc.pr_close_disposition_successor"] = "tk-race" else . end)' \
  "${STUB_STORE:?}" > "$tmp" && mv "$tmp" "${STUB_STORE:?}"
HOOK
chmod +x "$TMP/stamp-hook.sh"
store "[$(anchor F2f 26)]"   # stored WITHOUT the marker; the hook adds it on the re-read
printf '%s' "$(prview 26 CLOSED CLEAN MERGEABLE)" > "$GH_DIR/pr_view_26.json"
: > "$STUB_ESC_LOG"; : > "$STUB_REHOME_LOG"
out=$(STUB_SHOW_HOOK="$TMP/stamp-hook.sh" run)
has "$out" "auto-disposed (duplicate -> tk-race)" "a marker set after enumeration is read fresh and consummated"
has "$(cat "$STUB_REHOME_LOG")" "--origin F2f --successor tk-race --kind duplicate" "bead-rehome got the freshly-read disposition"
eq "$(bstatus F2f)" "closed" "the anchor is disposed, not abandoned"
eq "$(cat "$STUB_ESC_LOG")" "" "…and NO rework-or-close visit is filed"

echo "# a failed CLOSED re-read skips and retries, never abandons from stale absence"
store "[$(anchor F2g 27 ',"gc.pr_close_disposition_kind":"duplicate","gc.pr_close_disposition_successor":"tk-g"')]"
printf '%s' "$(prview 27 CLOSED CLEAN MERGEABLE)" > "$GH_DIR/pr_view_27.json"
: > "$STUB_ESC_LOG"; : > "$STUB_REHOME_LOG"
out=$(STUB_SHOW_FAIL=1 run)
eq "$(bstatus F2g)" "open" "the anchor is left OPEN"
eq "$(meta F2g merge_result)" "pull_request" "…still enumerable, so the next pass retries"
eq "$(cat "$STUB_ESC_LOG")" "" "nothing is escalated on a read that did not land"
eq "$(cat "$STUB_REHOME_LOG")" "" "…and bead-rehome is not called"
has "$out" "re-reading the anchor failed" "the skip names the failed re-read"

# The auto-dispose closes the anchor; the rework children parked on its
# branch are moot once the PR is gone and re-offer to the fix pool if left open,
# so the dispose drops them the same sanctioned way — bead-rehome.sh, pointed at
# the anchor's own successor.
echo "# an auto-dispose drops the closed PR's parked rework children"
store "[$(anchor F2h 28 ',"gc.pr_close_disposition_kind":"duplicate","gc.pr_close_disposition_successor":"tk-h"'), $(child K1 polecat/x28), $(child K2 polecat/x28)]"
printf '%s' "$(prview 28 CLOSED CLEAN MERGEABLE)" > "$GH_DIR/pr_view_28.json"
: > "$STUB_ESC_LOG"; : > "$STUB_REHOME_LOG"
out=$(run)
has "$out" "auto-disposed (duplicate -> tk-h)" "the anchor is disposed"
eq "$(bstatus F2h)" "closed" "the anchor is closed"
eq "$(bstatus K1)" "closed" "the parked child K1 is dropped"
eq "$(meta K1 'gc.superseded_by')" "tk-h" "…superseded by the anchor's successor, the sanctioned terminal close"
eq "$(bstatus K2)" "closed" "the parked child K2 is dropped too"
has "$(cat "$STUB_REHOME_LOG")" "--origin K1 --successor tk-h --kind not-needed" "bead-rehome drops K1 as not-needed -> the successor"
has "$(cat "$STUB_REHOME_LOG")" "--origin K2 --successor tk-h --kind not-needed" "…and K2 the same way"
has "$out" "dropped parked child K1" "the drop is reported"
eq "$(cat "$STUB_ESC_LOG")" "" "…and still no rework-or-close visit is filed"

# Only a PARKED child is dropped. A child a worker holds (in_progress), a review
# bead on the branch (no prepare_mode, signoff's to close), and a child the
# operator froze (rebase_hold) are each left alone.
echo "# the child drop leaves in-flight children, review beads, and frozen children alone"
store "[$(anchor F2i 29 ',"gc.pr_close_disposition_kind":"duplicate","gc.pr_close_disposition_successor":"tk-i"'), {\"id\":\"RV\",\"status\":\"open\",\"assignee\":\"\",\"notes\":\"\",\"title\":\"Review PR#29\",\"metadata\":{\"branch\":\"polecat/x29\",\"gc.routed_to\":\"rig/gc-toolkit.polecat-codex\"}}, $(child LV polecat/x29 '' in_progress rig/gc-toolkit.polecat), $(child FZ polecat/x29 ',"rebase_hold":"operator is reviewing this branch"')]"
printf '%s' "$(prview 29 CLOSED CLEAN MERGEABLE)" > "$GH_DIR/pr_view_29.json"
: > "$STUB_REHOME_LOG"
out=$(run)
eq "$(bstatus F2i)" "closed" "the anchor is disposed"
eq "$(bstatus RV)" "open" "a review bead on the branch (no prepare_mode) is NOT dropped"
eq "$(bstatus LV)" "in_progress" "a child a worker holds (in_progress) is left alone"
eq "$(bstatus FZ)" "open" "a frozen child (rebase_hold) is NOT closed out from under the operator"
hasnt "$(cat "$STUB_REHOME_LOG")" "--origin RV" "bead-rehome never touched the review bead"
hasnt "$(cat "$STUB_REHOME_LOG")" "--origin LV" "…nor the in-flight child"
hasnt "$(cat "$STUB_REHOME_LOG")" "--origin FZ" "…nor the frozen child"
has "$out" "child FZ on 'polecat/x29' is frozen (rebase_hold)" "the skipped freeze is reported for the operator"

echo "# the successor store, when the disposition records one, rides the child drop too"
store "[$(anchor F2k 31 ',"gc.pr_close_disposition_kind":"re-homed","gc.pr_close_disposition_successor":"ot-k","gc.pr_close_disposition_successor_store":"rig:other"'), $(child K3 polecat/x31)]"
printf '%s' "$(prview 31 CLOSED CLEAN MERGEABLE)" > "$GH_DIR/pr_view_31.json"
: > "$STUB_REHOME_LOG"
out=$(run)
eq "$(bstatus K3)" "closed" "the child is dropped"
has "$(cat "$STUB_REHOME_LOG")" "--origin K3 --successor ot-k --kind not-needed --successor-store rig:other" "the child drop carries the same successor store as the anchor"

# A rework child holds a `blocks` edge on its anchor, so the anchor's own
# non-force close is REFUSED while the child is open. The child must be dropped
# FIRST, in this same pass — drop it after the anchor close and the anchor can
# never close (its blocker is what fails the close), so it strands OPEN with its
# pointer stamped and a human has to finish it by hand. The bead-rehome stub
# models that open-blocker refusal, so this case fails against a dispose that
# closes the anchor before its children.
echo "# a blocking rework child is dropped BEFORE the anchor close, so the anchor is not stranded"
: > "$STUB_DEPS"
store "[$(anchor F2j 30 ',"gc.pr_close_disposition_kind":"folded","gc.pr_close_disposition_successor":"tk-j"'), $(child RC polecat/x30 ',"task_kind":"rework","anchor_bead":"F2j"'), {\"id\":\"VJ\",\"status\":\"open\",\"title\":\"visit\",\"notes\":\"\",\"metadata\":{\"escalation_key\":\"pr-abandoned.30\",\"gc.continuation_group\":\"F2j\",\"task_kind\":\"visit\",\"gc.routed_to\":\"human\"}}]"
gc bd dep RC --blocks F2j >/dev/null 2>&1   # the edge that refuses the anchor's close while RC is open
printf '%s' "$(prview 30 CLOSED CLEAN MERGEABLE)" > "$GH_DIR/pr_view_30.json"
: > "$STUB_ESC_LOG"; : > "$STUB_REHOME_LOG"
out=$(run)
eq "$(bstatus RC)" "closed" "the blocking rework child is dropped"
eq "$(bstatus F2j)" "closed" "…so the anchor's own close is no longer refused — disposed, not stranded"
eq "$(meta F2j 'gc.superseded_by')" "tk-j" "the anchor carries its terminal pointer"
eq "$(meta RC 'gc.superseded_by')" "tk-j" "…and the child is superseded by the anchor's successor"
has "$(cat "$STUB_REHOME_LOG")" "--origin RC --successor tk-j --kind not-needed" "the child is dropped as not-needed -> the anchor's successor"
rc_ln=$(grep -n -- "--origin RC " "$STUB_REHOME_LOG" | head -1 | cut -d: -f1)
an_ln=$(grep -n -- "--origin F2j " "$STUB_REHOME_LOG" | head -1 | cut -d: -f1)
{ [ -n "$rc_ln" ] && [ -n "$an_ln" ] && [ "$rc_ln" -lt "$an_ln" ]; } \
  && ok "the child close precedes the anchor close (completeness by construction, not a next-pass retry)" \
  || bad "the child must be disposed before the anchor close (rc_ln='$rc_ln' an_ln='$an_ln')"
eq "$(bstatus VJ)" "closed" "the stale rework-or-close visit is retired in the same consummation"
eq "$(meta VJ 'gc.outcome')" "moot" "…closed moot, the decision it asked for is made"
eq "$(cat "$STUB_ESC_LOG")" "" "nothing is escalated — the disposition consummated completely"

# The children are dropped BEFORE the anchor close, to clear their hold. When the
# close is then refused for a reason dropping them does not clear — a separate
# open blocker, a foreign disposition — the children are already gone. The
# pr-dispose-failed escalation must NAME them, or an operator who reverses the
# disposition finds them disposed with nothing saying so.
echo "# a refused anchor close names the children already disposed in the escalation"
: > "$STUB_DEPS"
store "[$(anchor F2m 33 ',"gc.pr_close_disposition_kind":"duplicate","gc.pr_close_disposition_successor":"tk-m"'), $(child K5 polecat/x33), {\"id\":\"BLK\",\"status\":\"open\",\"title\":\"unrelated blocker\",\"notes\":\"\",\"metadata\":{}}]"
gc bd dep BLK --blocks F2m >/dev/null 2>&1   # a blocker that is NOT a parked child, so dropping the children never clears it
printf '%s' "$(prview 33 CLOSED CLEAN MERGEABLE)" > "$GH_DIR/pr_view_33.json"
: > "$STUB_ESC_LOG"; : > "$STUB_REHOME_LOG"
out=$(run)
eq "$(bstatus K5)" "closed" "the parked child is dropped before the anchor close"
eq "$(bstatus F2m)" "open" "…but the anchor close is still refused (another blocker), so it is left OPEN"
has "$(cat "$STUB_ESC_LOG")" "--subject F2m --key pr-dispose-failed.33" "escalated under the dispose-failed key"
has "$(cat "$STUB_ESC_LOG")" "K5" "…the escalation names the child that was already disposed"
has "$(cat "$STUB_ESC_LOG")" "restore them by hand" "…and says to restore it if the disposition is wrong"

# A refused close escalates under pr-dispose-failed.<num>, and that visit tracks
# the anchor. It reports this arm's own failed close and asks for the next pass's
# retry, so the retry names its key to the finalize gate, which excepts the visit
# while nobody is engaged in it, and retracts it moot once the close lands. Held
# by it instead, the anchor could not close even after the obstruction it
# reported cleared. dvisit seeds the visit escalate.sh files: stamped with its key
# and its subject's group, and tracked onto the subject by the edge each case
# seeds beside it. An assignee seeds a visit someone has engaged.
dvisit() { # id subject key [status] [assignee]
  printf '{"id":"%s","status":"%s","assignee":"%s","title":"visit","notes":"","metadata":{"escalation_key":"%s","gc.continuation_group":"%s","task_kind":"visit","gc.routed_to":"human"}}' \
    "$1" "${4:-open}" "${5:-}" "$3" "$2"
}
# How many visits in the store carry a situation key, whatever their status.
nvisits() { jq --arg k "$1" '[ .[] | select((.metadata.escalation_key // "") == $k) ] | length' "$STUB_STORE"; }
# Filings of a situation, apart from its retraction: a filing's argv begins
# with --subject, a retraction's with --retract.
filings() { grep -c -- "^--subject $1 --key $2 " "$STUB_ESC_LOG"; }

echo "# the arm's own pr-dispose-failed visit does not hold the retry it asks for"
: > "$STUB_DEPS"
store "[$(anchor F2n 120 ',"gc.pr_close_disposition_kind":"re-homed","gc.pr_close_disposition_successor":"tk-n"'), $(dvisit VN F2n pr-dispose-failed.120), {\"id\":\"OB\",\"status\":\"closed\",\"title\":\"former blocker\",\"notes\":\"\",\"metadata\":{}}]"
printf 'VN|tracks|F2n\nOB|blocks|F2n\n' > "$STUB_DEPS"   # the visit's edge, and the obstruction it reported, since closed
printf '%s' "$(prview 120 CLOSED CLEAN MERGEABLE)" > "$GH_DIR/pr_view_120.json"
: > "$STUB_ESC_LOG"; : > "$STUB_REHOME_LOG"
out=$(run)
eq "$(bstatus F2n)" "closed" "the anchor closes once the obstruction its escalation reported has cleared"
eq "$(meta F2n 'gc.superseded_by')" "tk-n" "…through the sanctioned terminal close"
has "$(cat "$STUB_REHOME_LOG")" "--origin F2n --successor tk-n --kind re-homed --except-key pr-dispose-failed.120" "bead-rehome is told the arm's own visits do not hold this retry"
eq "$(bstatus VN)" "closed" "the arm's own visit is retracted once the close lands"
eq "$(meta VN 'gc.outcome')" "moot" "…closed moot: the obstruction it reported is gone"
has "$(cat "$STUB_ESC_LOG")" "--retract --subject F2n --key pr-dispose-failed.120" "…through escalate.sh's retract verb"
eq "$(filings F2n pr-dispose-failed.120)" "0" "…and nothing is re-filed"
has "$out" "retracted its own pr-dispose-failed visit VN" "the retraction is reported"

echo "# a pr-dispose-failed visit a person has claimed still holds the close"
: > "$STUB_DEPS"
store "[$(anchor F2o 121 ',"gc.pr_close_disposition_kind":"duplicate","gc.pr_close_disposition_successor":"tk-o"'), $(dvisit VC F2o pr-dispose-failed.121 in_progress)]"
printf 'VC|tracks|F2o\n' > "$STUB_DEPS"
printf '%s' "$(prview 121 CLOSED CLEAN MERGEABLE)" > "$GH_DIR/pr_view_121.json"
: > "$STUB_ESC_LOG"; : > "$STUB_REHOME_LOG"
out=$(run)
eq "$(bstatus F2o)" "open" "the anchor is left OPEN while a person holds the visit"
has "$out" "held by open visit VC" "…held by the claimed visit"
eq "$(bstatus VC)" "in_progress" "the claimed visit is its holder's to conclude"
hasnt "$(cat "$STUB_ESC_LOG")" "--retract" "…so nothing retracts it"
eq "$(nvisits pr-dispose-failed.121)" "1" "…and no second visit is filed beside it"

echo "# a pr-dispose-failed visit bound by assignee (engaged, not yet claimed) still holds the close"
# Engage binds the visit's assignee while it is still open, before the sitting's
# claim promotes it. The board reads that as engaged, and so does the gate.
: > "$STUB_DEPS"
store "[$(anchor F2oa 124 ',"gc.pr_close_disposition_kind":"duplicate","gc.pr_close_disposition_successor":"tk-oa"'), $(dvisit VE F2oa pr-dispose-failed.124 open lx-sitting)]"
printf 'VE|tracks|F2oa\n' > "$STUB_DEPS"
printf '%s' "$(prview 124 CLOSED CLEAN MERGEABLE)" > "$GH_DIR/pr_view_124.json"
: > "$STUB_ESC_LOG"; : > "$STUB_REHOME_LOG"
out=$(run)
eq "$(bstatus F2oa)" "open" "the anchor is left OPEN while a person is engaging the visit"
has "$out" "held by open visit VE" "…held by the engaged visit"
eq "$(bstatus VE)" "open" "the engaged visit is untouched"
eq "$(meta VE 'gc.outcome')" "<absent>" "…with no outcome stamped on it"

echo "# twin pr-dispose-failed visits on the anchor are both excepted"
# escalate.sh files a second visit when its dedup listing is unreadable. Both
# carry the arm's key and the anchor's stamp, so neither holds the retry.
: > "$STUB_DEPS"
store "[$(anchor F2t 125 ',"gc.pr_close_disposition_kind":"folded","gc.pr_close_disposition_successor":"tk-t"'), $(dvisit VT1 F2t pr-dispose-failed.125), $(dvisit VT2 F2t pr-dispose-failed.125)]"
printf 'VT1|tracks|F2t\nVT2|tracks|F2t\n' > "$STUB_DEPS"
printf '%s' "$(prview 125 CLOSED CLEAN MERGEABLE)" > "$GH_DIR/pr_view_125.json"
: > "$STUB_ESC_LOG"; : > "$STUB_REHOME_LOG"
out=$(run)
eq "$(bstatus F2t)" "closed" "the anchor closes with twin visits of the arm's own situation open"
hasnt "$out" "held by open visit VT" "…neither twin holds it"
eq "$(bstatus VT1)" "closed" "…and once it lands the first twin is retracted"
eq "$(bstatus VT2)" "closed" "…and the second as well"
has "$out" "retracted its own pr-dispose-failed visit VT2" "…each one reported"

echo "# a standing obstruction keeps its one visit; the pass after it clears closes the anchor"
: > "$STUB_DEPS"
store "[$(anchor F2p 122 ',"gc.pr_close_disposition_kind":"not-needed","gc.pr_close_disposition_successor":"tk-p"'), $(dvisit VS F2p pr-dispose-failed.122), {\"id\":\"BS\",\"status\":\"open\",\"title\":\"open must-fix finding\",\"notes\":\"\",\"metadata\":{}}]"
printf 'VS|tracks|F2p\nBS|blocks|F2p\n' > "$STUB_DEPS"
printf '%s' "$(prview 122 CLOSED CLEAN MERGEABLE)" > "$GH_DIR/pr_view_122.json"
: > "$STUB_ESC_LOG"; : > "$STUB_REHOME_LOG"
out=$(run)
eq "$(bstatus F2p)" "open" "an anchor still blocked stays OPEN"
has "$out" "has an OPEN blocker" "…refused for the obstruction itself, not for its own visit"
eq "$(bstatus VS)" "open" "the visit stays open while the obstruction stands"
hasnt "$(cat "$STUB_ESC_LOG")" "--retract" "…nothing retracts it"
eq "$(nvisits pr-dispose-failed.122)" "1" "…and the escalation dedups onto it rather than filing a second"
# The obstruction clears (arm 10 retires a disposed anchor's findings), and the
# next pass retries the close the visit asked for.
jq -c 'map(if .id == "BS" then .status = "closed" else . end)' "$STUB_STORE" > "$TMP/store.next" && mv "$TMP/store.next" "$STUB_STORE"
: > "$STUB_ESC_LOG"
out=$(run)
eq "$(bstatus F2p)" "closed" "the next pass after the obstruction clears closes the anchor"
eq "$(bstatus VS)" "closed" "…and retracts the visit that reported it"
eq "$(meta VS 'gc.outcome')" "moot" "…as moot"

echo "# another open visit on the anchor still holds the close; only the arm's own is excepted"
: > "$STUB_DEPS"
store "[$(anchor F2q 123 ',"gc.pr_close_disposition_kind":"folded","gc.pr_close_disposition_successor":"tk-q"'), $(dvisit VQ F2q pr-dispose-failed.123), $(dvisit VR F2q an-unrelated-question)]"
printf 'VQ|tracks|F2q\nVR|tracks|F2q\n' > "$STUB_DEPS"
printf '%s' "$(prview 123 CLOSED CLEAN MERGEABLE)" > "$GH_DIR/pr_view_123.json"
: > "$STUB_ESC_LOG"; : > "$STUB_REHOME_LOG"
out=$(run)
eq "$(bstatus F2q)" "open" "the anchor is left OPEN"
has "$out" "held by open visit VR" "…held by the visit the arm does not own"
eq "$(bstatus VQ)" "open" "the arm's own visit stays open: the close it asks for has not landed"
eq "$(bstatus VR)" "open" "…and the other visit is untouched"

# A visit's description: the report a person reads when they open or engage it.
vdesc() { jq -r --arg id "$1" '(.[] | select(.id == $id) | .description) // "<absent>"' "$STUB_STORE"; }
# The arm's own visit as an earlier pass filed it: its description names the
# obstruction that pass hit, and the parked children it disposed, if any.
dvisit_desc() { # id subject key description [assignee]
  jq -nc --arg id "$1" --arg s "$2" --arg k "$3" --arg d "$4" --arg a "${5:-}" \
    '{id: $id, status: "open", assignee: $a, title: "visit", description: $d, notes: "",
      metadata: {escalation_key: $k, "gc.continuation_group": $s, task_kind: "visit", "gc.routed_to": "human"}}'
}

echo "# a close refused for a new reason refreshes the visit's description"
# escalate.sh dedups every later refusal onto the visit it filed first, so the
# arm rewrites that visit's description when this pass's refusal differs. The
# note naming the children an earlier pass disposed is carried forward.
: > "$STUB_DEPS"
OLD_REPORT="PR#131 was closed with a pre-recorded disposition, but bead-rehome.sh could not consummate it (rc=5): has an OPEN blocker BOLD. The anchor is left OPEN carrying the marker. The branch's parked rework/rebase children (K9) were ALREADY disposed (closed not-needed -> tk-x) before this close, to clear their blocks-hold on the anchor; if the disposition is wrong, restore them by hand."
store "[$(anchor F2x 131 ',"gc.pr_close_disposition_kind":"folded","gc.pr_close_disposition_successor":"tk-x"'), $(dvisit_desc VX F2x pr-dispose-failed.131 "$OLD_REPORT"), $(dvisit VR2 F2x an-unrelated-question)]"
printf 'VX|tracks|F2x\nVR2|tracks|F2x\n' > "$STUB_DEPS"
printf '%s' "$(prview 131 CLOSED CLEAN MERGEABLE)" > "$GH_DIR/pr_view_131.json"
: > "$STUB_ESC_LOG"; : > "$STUB_REHOME_LOG"
out=$(run)
eq "$(bstatus F2x)" "open" "the close is refused, now by another open visit"
has "$(vdesc VX)" "held by open visit VR2" "the visit's description names this pass's obstruction"
hasnt "$(vdesc VX)" "BOLD" "…and no longer the blocker an earlier pass hit"
has "$(vdesc VX)" "The branch's parked rework/rebase children (K9) were ALREADY disposed" "…while the children an earlier pass disposed stay named"
has "$out" "refreshed its pr-dispose-failed visit VX" "the refresh is reported"
eq "$(nvisits pr-dispose-failed.131)" "1" "…on the one visit, with nothing re-filed"
REFRESHED="$(vdesc VX)"
out=$(run)
eq "$(vdesc VX)" "$REFRESHED" "a pass refused for the same reason leaves the description as it is"
hasnt "$out" "refreshed its pr-dispose-failed visit VX" "…and writes nothing"

echo "# a visit someone is engaged in keeps its description"
: > "$STUB_DEPS"
store "[$(anchor F2y 132 ',"gc.pr_close_disposition_kind":"folded","gc.pr_close_disposition_successor":"tk-y"'), $(dvisit_desc VY F2y pr-dispose-failed.132 "an earlier report" lx-sitting)]"
printf 'VY|tracks|F2y\n' > "$STUB_DEPS"
printf '%s' "$(prview 132 CLOSED CLEAN MERGEABLE)" > "$GH_DIR/pr_view_132.json"
: > "$STUB_ESC_LOG"; : > "$STUB_REHOME_LOG"
out=$(run)
eq "$(bstatus F2y)" "open" "the engaged visit holds the close"
eq "$(vdesc VY)" "an earlier report" "…and its description is left to the person in it"

echo "# a retract that does not land after the close is retried by the next full pass"
# The closed anchor leaves the enumeration, so the arm never reaches it again.
# The sweep ahead of the anchor loop reads the open visit, finds its subject
# closed with the disposition pointer recorded, and retracts it.
: > "$STUB_DEPS"
store "[$(anchor F2r 126 ',"gc.pr_close_disposition_kind":"re-homed","gc.pr_close_disposition_successor":"tk-r"'), $(dvisit VF F2r pr-dispose-failed.126)]"
printf 'VF|tracks|F2r\n' > "$STUB_DEPS"
printf '%s' "$(prview 126 CLOSED CLEAN MERGEABLE)" > "$GH_DIR/pr_view_126.json"
: > "$STUB_ESC_LOG"; : > "$STUB_REHOME_LOG"
out=$(STUB_RETRACT_FAIL=1 run)
eq "$(bstatus F2r)" "closed" "the anchor closes"
eq "$(bstatus VF)" "open" "…but the retract did not land, so its visit is still open"
has "$out" "visit VF is still open; a full pass retracts it" "…and the pass says a full pass retries it"
out=$(run_posture)
eq "$(bstatus VF)" "open" "a posture-only pass leaves it"
: > "$STUB_ESC_LOG"
out=$(run)
eq "$(bstatus VF)" "closed" "the next full pass retracts it"
eq "$(meta VF 'gc.outcome')" "moot" "…as moot"
has "$(cat "$STUB_ESC_LOG")" "--retract --subject F2r --key pr-dispose-failed.126" "…through the same retract verb"
has "$out" "retracted its own pr-dispose-failed visit VF" "…and reports it"

echo "# the sweep retracts only a visit whose subject closed with its pointer, and nobody engaged"
# A subject closed with no gc.superseded_by has no disposition on record, a
# visit someone is engaged in is theirs to conclude, and a subject that does
# not read this pass is left for the next.
: > "$STUB_DEPS"
store "[$(anchor F2u 128 '' | jq -c '.status = "closed"'), $(dvisit VU F2u pr-dispose-failed.128), $(anchor F2v 129 ',"gc.superseded_by":"tk-v"' | jq -c '.status = "closed"'), $(dvisit VV F2v pr-dispose-failed.129 open lx-sitting), $(dvisit VG GHOST pr-dispose-failed.130)]"
printf 'VU|tracks|F2u\nVV|tracks|F2v\n' > "$STUB_DEPS"
: > "$STUB_ESC_LOG"
out=$(run)
eq "$(bstatus VU)" "open" "a visit whose subject closed with no disposition pointer is left"
eq "$(bstatus VV)" "open" "a visit someone is engaged in is left"
eq "$(bstatus VG)" "open" "a visit whose subject does not read is left"
has "$out" "subject GHOST unreadable this pass" "…and the unreadable subject is reported"
hasnt "$(cat "$STUB_ESC_LOG")" "--retract" "…and none of them is retracted"

echo "# the sweep's retract runs through the real escalate.sh and visit-close.sh"
# Every other case drives escalate.sh's contract through the stub above. This
# one runs the real verb against a subject already closed, the shape the sweep
# meets: escalate.sh reads the open visits for the situation, and visit-close.sh
# folds the reading onto the subject, stamps the outcome, and closes the visit.
# GC_RIG names the store, since no rig set is served here to derive it from.
SD2="$TMP/scripts-real-escalate"
mk_sut_dir "$SD2" "$HERE/pr-facts.sh" "$HERE/lifecycle.sh" "$HERE/record-failure-cap.sh" "$HERE/finding.sh" "$HERE/review-checks.sh" "$HERE/visit-close.sh" "$HERE/finalize-gate.sh" "$HERE/escalate.sh"
cp "$SD/bead-rehome.sh" "$SD/review-dispatch-body.sh" "$SD/validate-dispatch-body.sh" "$SD2/"
: > "$STUB_DEPS"
store "[$(anchor F2w 127 ',"gc.superseded_by":"tk-w"' | jq -c '.status = "closed"'), $(dvisit VW F2w pr-dispose-failed.127)]"
printf 'VW|tracks|F2w\n' > "$STUB_DEPS"
out=$(GC_RIG=gc-toolkit "$SD2/pr-facts.sh" --fix-pool "$FIX" --review-pool "$REV" 2>&1)
eq "$(bstatus VW)" "closed" "the real retract closes the visit on the closed anchor"
eq "$(meta VW 'gc.outcome')" "moot" "…moot, stamped by visit-close.sh"
has "$(meta VW 'gc.outcome_reason')" "PR#127's pre-recorded disposition is consummated" "…with the sweep's reading as its reason"
has "$(notes F2w)" "visit VW closed moot" "…and the reading folded onto the closed subject's notes"
has "$out" "retracted its own pr-dispose-failed visit VW" "the retraction is reported"

echo "# a pre-recorded disposition retires the PR's other merge-path visits before the close"
# Each was filed to hold the PR's merge until a person answered it. The PR is
# closed with its disposition recorded, so there is no merge left to hold, and
# none of them may keep the anchor from closing.
mpvisit() { # id subject key [status] [assignee]
  printf '{"id":"%s","status":"%s","assignee":"%s","title":"visit","notes":"","metadata":{"escalation_key":"%s","gc.continuation_group":"%s","task_kind":"visit","gc.routed_to":"human"}}' \
    "$1" "${4:-open}" "${5:-}" "$3" "$2"
}
: > "$STUB_DEPS"
store "[$(anchor F2z 133 ',"gc.pr_close_disposition_kind":"folded","gc.pr_close_disposition_successor":"tk-z"'), $(mpvisit VC1 F2z pr-comments.133.5.7), $(mpvisit VU1 F2z pr-unengaged-threads.133.sha-133), $(mpvisit VB1 F2z merge-blocked-threads), $(mpvisit VT3 F2z pr-retargeted.133), $(mpvisit VN3 F2z pr-fix-noncode.133 deferred), $(mpvisit VK3 F2z pr-fix-capped.133)]"
printf 'VC1|tracks|F2z\nVU1|tracks|F2z\nVB1|tracks|F2z\nVT3|tracks|F2z\nVN3|tracks|F2z\nVK3|tracks|F2z\n' > "$STUB_DEPS"
printf '%s' "$(prview 133 CLOSED CLEAN MERGEABLE)" > "$GH_DIR/pr_view_133.json"
: > "$STUB_ESC_LOG"; : > "$STUB_REHOME_LOG"
out=$(run)
eq "$(bstatus F2z)" "closed" "the anchor closes in the same pass"
for v in VC1 VU1 VB1 VT3 VN3 VK3; do
  eq "$(bstatus "$v")" "closed" "merge-path visit $v is retired"
done
eq "$(meta VC1 'gc.outcome')" "moot" "…closed moot"
has "$(meta VC1 'gc.outcome_reason')" "F2z disposed (folded -> tk-z)" "…naming the disposition"
has "$(meta VC1 'gc.outcome_reason')" "the merge this visit held is gone" "…and why its question is moot"
has "$out" "retired stale visit VC1 (pr-comments.133.5.7" "each retirement is reported with its key"
eq "$(filings F2z pr-dispose-failed.133)" "0" "…and no dispose-failed visit is filed"

echo "# an engaged merge-path visit keeps holding the close"
# A person in that conversation concludes it. Only the rework-or-close visit is
# retired over a claim, because the disposition answers its question.
: > "$STUB_DEPS"
store "[$(anchor F2za 134 ',"gc.pr_close_disposition_kind":"duplicate","gc.pr_close_disposition_successor":"tk-za"'), $(mpvisit VCE F2za pr-comments.134.1.2 open lx-sitting)]"
printf 'VCE|tracks|F2za\n' > "$STUB_DEPS"
printf '%s' "$(prview 134 CLOSED CLEAN MERGEABLE)" > "$GH_DIR/pr_view_134.json"
: > "$STUB_ESC_LOG"; : > "$STUB_REHOME_LOG"
out=$(run)
eq "$(bstatus VCE)" "open" "the engaged feedback visit is left to its holder"
eq "$(bstatus F2za)" "open" "…and it holds the anchor's close"
has "$out" "VCE (pr-comments.134.1.2) is engaged (lx-sitting)" "…which the pass reports"
has "$out" "held by open visit VCE" "…and names as the hold"

echo "# a visit for another PR, or under a key this script does not file, is not retired"
: > "$STUB_DEPS"
store "[$(anchor F2zb 135 ',"gc.pr_close_disposition_kind":"not-needed","gc.pr_close_disposition_successor":"tk-zb"'), $(mpvisit VO F2zb pr-comments.999.1.2), $(mpvisit VQ2 F2zb an-unrelated-question)]"
printf 'VO|tracks|F2zb\nVQ2|tracks|F2zb\n' > "$STUB_DEPS"
printf '%s' "$(prview 135 CLOSED CLEAN MERGEABLE)" > "$GH_DIR/pr_view_135.json"
: > "$STUB_ESC_LOG"; : > "$STUB_REHOME_LOG"
out=$(run)
eq "$(bstatus VO)" "open" "another PR's feedback visit is left"
eq "$(bstatus VQ2)" "open" "a visit under another key is left"
eq "$(bstatus F2zb)" "open" "…and they still hold the anchor's close"

echo "# base moved -> retargeted + markers cleared"
store "[$(anchor F3 12)]"
printf '%s' "$(prview 12 OPEN CLEAN MERGEABLE)" | jq -c '.baseRefName = "release"' > "$GH_DIR/pr_view_12.json"
: > "$STUB_ESC_LOG"
out=$(run)
has "$out" "retargeted (base 'release'" "the retarget is recorded"
eq "$(meta F3 merge_result)" "retargeted" "merge_result=retargeted"
eq "$(meta F3 'gc.routed_to')" "human" "routed to human"
eq "$(meta F3 'check.correctness')" "<absent>" "the pre-retarget check marker is cleared"
has "$(cat "$STUB_ESC_LOG")" "--key pr-retargeted.12" "escalated once per situation key"

echo "# CONFLICTING -> one rework child per head"
store "[$(anchor F4 13)]"
printf '%s' "$(prview 13 OPEN DIRTY CONFLICTING)" > "$GH_DIR/pr_view_13.json"
approve 13
out=$(run)
has "$out" "filed merge-mode rework new-2 routed to $FIX" "a rework child was filed, classified, and routed"
eq "$(meta new-2 task_kind)" "rework" "child carries the rework role marker"
eq "$(meta new-2 anchor_bead)" "F4" "child names the anchor it belongs to"
eq "$(meta F4 task_kind)" "<absent>" "…and the anchor carries none, so the marker discriminates"
eq "$(meta new-2 branch)" "polecat/x13" "child carries the branch"
eq "$(meta new-2 target)" "main" "child carries the target"
eq "$(meta new-2 merge_strategy)" "mr" "child is mr-mode"
eq "$(meta new-2 existing_pr)" "https://github.com/zook/gc-toolkit/pull/13" "child reworks THIS PR"
eq "$(meta new-2 'gc.routed_to')" "$FIX" "child routed to the fix pool"
has "$(meta new-2 rejection_reason)" "head sha-13" "the rejection reason names the head (the dedup key)"
eq "$(meta new-2 prepare_mode)" "merge" "every branch shape is brought current by merge, polecat/* included"
hasnt "$(meta new-2 rejection_reason)" "force-push with --force-with-lease" "a merge-in work order never names a force-push"
has "$(meta new-2 rejection_reason)" "Do NOT rebase it and do NOT force-push it" "…and forbids the rewrite in words"
grep -qxF "new-2|blocks|F4" "$STUB_DEPS" && ok "child blocks the anchor" || bad "blocks edge missing"
eq "$(meta F4 merge_result)" "pull_request" "the anchor keeps gating (no state flip)"

echo "# …dedup: second pass files nothing"
out=$(run)
has "$out" "already covers branch" "an existing child suppresses a twin"
eq "$(jq '[.[] | select(.id | startswith("new-")) | select((.metadata.task_kind // "") == "rework")] | length' "$STUB_STORE")" "1" "still exactly one child"

echo "# …an UNAPPROVED conflicting PR files no merge-in: its posture is recorded, and one line says why"
# A bring-current costs a polecat round and a CI run, and goes stale whenever
# main moves, while a PR nobody approved cannot land however current it is. So
# the merge-in waits for an approval, by the rule merge.sh lands on.
store "[$(anchor NA1 230)]"
printf '%s' "$(prview 230 OPEN DIRTY CONFLICTING)" > "$GH_DIR/pr_view_230.json"
echo '[]' > "$GH_DIR/reviews_230.json"
: > "$STUB_SESSION_LOG"
out=$(run)
has "$out" "PR#230 conflicts but no external approval stands; no merge-in filed" "the unapproved conflict files no merge-in"
eq "$(printf '%s\n' "$out" | grep -c 'PR#230 conflicts')" "1" "…and says so in exactly one line"
eq "$(jq '[.[] | select(.id | startswith("new-"))] | length' "$STUB_STORE")" "0" "…no child of any kind is minted"
eq "$(meta_pinned NA1 pr_posture)" "none@sha-230" "…while its posture is recorded at the live head"
eq "$(meta NA1 pr_merge_state)" "DIRTY@sha-230" "…beside the merge state that says it conflicts"
hasnt "$(cat "$STUB_SESSION_LOG")" "wake $FIX" "…the fix pool is not woken"
eq "$(meta NA1 merge_result)" "pull_request" "…and the anchor keeps gating, untouched"

echo "# …the same PR, once approved, gets its merge-in: the approval is what released it"
approve 230
out=$(run)
has "$out" "filed merge-mode rework" "an approval releases the bring-current"
eq "$(jq '[.[] | select((.metadata.task_kind // "") == "rework") | select((.metadata.anchor_bead // "") == "NA1")] | length' "$STUB_STORE")" "1" "…exactly one merge-in child"

echo "# …a standing CHANGES_REQUESTED vetoes the approval beside it, as it vetoes the merge"
# An empty-bodied CHANGES_REQUESTED carries no feedback to route, so the anchor
# reaches this arm rather than the feedback arm.
store "[$(anchor NA2 231)]"
printf '%s' "$(prview 231 OPEN DIRTY CONFLICTING)" | jq -c '.reviewDecision = "CHANGES_REQUESTED"' > "$GH_DIR/pr_view_231.json"
printf '[{"id":880301,"user":{"login":"human1"},"state":"APPROVED","body":"","commit_id":"sha-231","submitted_at":"2026-08-20T01:00:00Z"},{"id":880302,"user":{"login":"human2"},"state":"CHANGES_REQUESTED","body":"","commit_id":"sha-231","submitted_at":"2026-08-21T01:00:00Z"}]' > "$GH_DIR/reviews_231.json"
out=$(run)
has "$out" "PR#231 conflicts but 'human2' has a standing CHANGES_REQUESTED; no merge-in filed" "a standing veto holds the merge-in"
eq "$(jq '[.[] | select(.id | startswith("new-"))] | length' "$STUB_STORE")" "0" "…and no child is minted"

echo "# …neither a dismissed approval nor one under the city's own login counts"
store "[$(anchor NA3 232), $(anchor NA4 233)]"
printf '%s' "$(prview 232 OPEN DIRTY CONFLICTING)" > "$GH_DIR/pr_view_232.json"
printf '%s' "$(prview 233 OPEN DIRTY CONFLICTING)" > "$GH_DIR/pr_view_233.json"
printf '[{"id":880401,"user":{"login":"human1"},"state":"DISMISSED","body":"","commit_id":"sha-232","submitted_at":"2026-08-20T01:00:00Z"}]' > "$GH_DIR/reviews_232.json"
approve 233 gc-city-bot
out=$(run)
has "$out" "PR#232 conflicts but no external approval stands" "a dismissed approval releases nothing"
has "$out" "PR#233 conflicts but no external approval stands" "…nor does the city's own approval"
eq "$(jq '[.[] | select(.id | startswith("new-"))] | length' "$STUB_STORE")" "0" "…and no child is minted for either"

echo "# …reviews that do not read, or an unresolved acting login, prove no approval: nothing is filed until a pass reads one"
store "[$(anchor NA5 234)]"
printf '%s' "$(prview 234 OPEN DIRTY CONFLICTING)" > "$GH_DIR/pr_view_234.json"
approve 234
out=$(STUB_GH_LIST_RC=1 run)
has "$out" "PR#234 conflicts but its reviews could not be read to prove an approval; no merge-in filed (retry next pass)" "an unreadable review list fails closed"
out=$(STUB_SELF_LOGIN="" run)
has "$out" "PR#234 conflicts but its reviews could not be read to prove an approval" "…and so does an unresolved acting login, which cannot tell an outside approval from the city's own"
eq "$(jq '[.[] | select(.id | startswith("new-"))] | length' "$STUB_STORE")" "0" "…neither files a child"
out=$(run)
has "$out" "filed merge-mode rework" "…and the next pass that reads the approval files the merge-in"

echo "# …a merge-in child already on an UNAPPROVED PR's branch is left as it is"
# The gate stops new merge-ins, not the ones in flight: a routed child drains
# through its polecat as before, and an unrouted strand is re-routed only once
# the PR is approved.
liv=$(child LV1 polecat/x235 ',"task_kind":"rework","anchor_bead":"NA6","rejection_reason":"stale base at head sha-235: ..."')
str=$(child ST1 polecat/x236 ',"task_kind":"rework","anchor_bead":"NA7","rejection_reason":"stale base at head sha-236: ...","gc.routed_to":""')
store "[$(anchor NA6 235), $liv, $(anchor NA7 236), $str]"
gc bd dep LV1 --blocks NA6 >/dev/null 2>&1
gc bd dep ST1 --blocks NA7 >/dev/null 2>&1
printf '%s' "$(prview 235 OPEN DIRTY CONFLICTING)" > "$GH_DIR/pr_view_235.json"
printf '%s' "$(prview 236 OPEN DIRTY CONFLICTING)" > "$GH_DIR/pr_view_236.json"
out=$(run)
has "$out" "PR#235 conflicts but no external approval stands" "an unapproved PR with a merge-in in flight files nothing new"
eq "$(bstatus LV1)" "open" "…its routed child is left open"
eq "$(meta LV1 'gc.routed_to')" "rig/gc-toolkit.polecat" "…and routed, to drain through its polecat"
eq "$(meta ST1 'gc.routed_to')" "" "…while an unrouted strand stays unrouted"
hasnt "$out" "re-routing stranded rework ST1" "…and is not reported re-routed"
eq "$(jq '[.[] | select(.id | startswith("new-"))] | length' "$STUB_STORE")" "0" "…and nothing is minted"
approve 236
out=$(run)
has "$out" "re-routing stranded rework ST1" "once the PR is approved, the strand is re-routed as before"

echo "# …a hold vetoes the dispatch"
store "[$(anchor F5 14 ',"rebase_hold":"true"')]"
printf '%s' "$(prview 14 OPEN DIRTY CONFLICTING)" > "$GH_DIR/pr_view_14.json"
out=$(run)
has "$out" "a hold is set (operator gate); no rework dispatched" "rebase_hold vetoes the dispatch"

echo "# …and so does a live demand: rebasing is one horn of what it asks"
# The anchor carries no human route of its own. That route sits on the demand
# bead, so the demand is the only signal that a person is mid-decision here.
store "[$(anchor F5b 16),$(demand F5b)]"
printf '%s' "$(prview 16 OPEN DIRTY CONFLICTING)" > "$GH_DIR/pr_view_16.json"
: > "$STUB_SESSION_LOG"
out=$(run)
eq "$(meta F5b 'gc.routed_to')" "" "the anchor itself is not human-routed"
has "$out" "an open demand holds it for a person's decision; no rework dispatched" "the demand vetoes the dispatch"
eq "$(jq '[.[] | select(.id | startswith("new-")) | select((.metadata.task_kind // "") == "rework")] | length' "$STUB_STORE")" "0" "…and no rework child is minted"
hasnt "$(cat "$STUB_SESSION_LOG")" "wake $FIX" "…and the fix pool is not woken"
eq "$(meta F5b merge_result)" "pull_request" "…while the anchor keeps gating, so the merge still waits"

echo "# …while a CLOSED demand is a decision already made: the rework is dispatched"
store "[$(anchor F5c 17),$(demand F5c closed)]"
printf '%s' "$(prview 17 OPEN DIRTY CONFLICTING)" > "$GH_DIR/pr_view_17.json"
approve 17
out=$(run)
has "$out" "filed merge-mode rework new-3 routed to $FIX" "a closed demand holds nothing"

echo "# …but a closed demand is not the only hold: any OTHER live blocker on the anchor freezes the dispatch too (tk-nak6pb)"
# takeaway_is_holding reads only the demand channel. A closed demand is a
# decision made, yet the anchor can still be blocked on an ordinary
# prerequisite — here PB1, a bead it depends on carrying no demand marker at all.
# Rebasing blind would run ahead of a merge already held on it. The
# foreign-blocker guard reads every live blocker merge.sh holds the merge on.
store "[$(anchor FBK1 96),{\"id\":\"PB1\",\"status\":\"open\",\"assignee\":\"\",\"notes\":\"\",\"title\":\"prerequisite the anchor depends on\",\"metadata\":{}}]"
gc bd dep PB1 --blocks FBK1 >/dev/null 2>&1
printf '%s' "$(prview 96 OPEN DIRTY CONFLICTING)" > "$GH_DIR/pr_view_96.json"
: > "$STUB_SESSION_LOG"
out=$(run)
has "$out" "the anchor is held by PB1 (a merge is held on it); no rework dispatched" "a plain depends-on blocker vetoes the stale-base dispatch"
eq "$(jq '[.[] | select(.id | startswith("new-"))] | length' "$STUB_STORE")" "0" "…and no rework child is minted"
hasnt "$(cat "$STUB_SESSION_LOG")" "wake $FIX" "…and the fix pool is not woken"

echo "# …but the arm's OWN rework child is the mechanism, not a hold: it blocks the anchor yet the dedup still runs (tk-nak6pb)"
# A live rework child of THIS anchor blocks it — that is how the merge waits for
# the fix. Excluding it by task_kind+anchor_bead is what lets a stranded child be
# re-routed and a covering one dedup, rather than the guard burying both.
store "[$(anchor FBK2 97),$(child CW1 polecat/x97 ',"task_kind":"rework","anchor_bead":"FBK2"')]"
gc bd dep CW1 --blocks FBK2 >/dev/null 2>&1
printf '%s' "$(prview 97 OPEN DIRTY CONFLICTING)" > "$GH_DIR/pr_view_97.json"
approve 97
out=$(run)
has "$out" "rework CW1 already covers branch 'polecat/x97' at this head, no new child" "the anchor's own rework child is excluded from the guard, so the dedup runs"

echo "# …and that own rework child, parked for a person in the held lifecycle state, still covers — the merge_result stamp does not drop it"
# converse-hold transitions an unanchored child to `held`, stamping
# merge_result=held; the child still owns the branch, so dropping it on the
# merge_result test alone would re-mint a merge-current twin every pass.
store "[$(anchor FBK3 98),$(child HW1 polecat/x98 ',"task_kind":"rework","anchor_bead":"FBK3","merge_result":"held"' blocked)]"
gc bd dep HW1 --blocks FBK3 >/dev/null 2>&1
printf '%s' "$(prview 98 OPEN DIRTY CONFLICTING)" > "$GH_DIR/pr_view_98.json"
approve 98
out=$(run)
has "$out" "rework HW1 already covers branch 'polecat/x98' at this head, no new child" "a rework child parked in the held lifecycle state (merge_result=held) still covers the branch"
eq "$(jq '[.[] | select(.id | startswith("new-")) | select((.metadata.task_kind // "") == "rework")] | length' "$STUB_STORE")" "0" "…and no twin is minted"

echo "# …but that own rework child, ITSELF held by a live decision demand, DOES veto: the demand gates the branch both share"
# A base-supersession or reconcile decision is filed on the in-flight rework
# (gc.demand_for=<child>), not the anchor. The child is on the anchor's own
# branch, so anchor_foreign_blocker excludes it as the arm's own mechanism and
# takeaway_is_holding on the anchor reads clear — both blind. anchor_decision_held
# reads the demand ledger for the child too, because a decision on it holds the
# one branch the anchor and child share.
store "[$(anchor FDK1 110),$(child KID1 polecat/x110 ',"task_kind":"rework","anchor_bead":"FDK1"'),$(demand KID1)]"
gc bd dep KID1 --blocks FDK1 >/dev/null 2>&1
printf '%s' "$(prview 110 OPEN DIRTY CONFLICTING)" > "$GH_DIR/pr_view_110.json"
: > "$STUB_SESSION_LOG"
out=$(run)
eq "$(meta FDK1 'gc.routed_to')" "" "the anchor itself is not human-routed"
eq "$(jq -r '.[] | select(.id=="dm-KID1") | .metadata["gc.demand_for"] // "<none>"' "$STUB_STORE")" "KID1" "the demand names the rework child, not the anchor"
has "$out" "an open demand holds it for a person's decision; no rework dispatched" "a decision demand on the rework child vetoes the dispatch"
eq "$(jq '[.[] | select(.id | startswith("new-")) | select((.metadata.task_kind // "") != "validation")] | length' "$STUB_STORE")" "0" "…and no new rework child is minted"
hasnt "$(cat "$STUB_SESSION_LOG")" "wake $FIX" "…and the fix pool is not woken"

echo "# …control: with that child's demand CLOSED the hold lifts, and the own child dedups as the mechanism it is — so the LIVE demand, not the child, was the veto"
store "[$(anchor FDK2 111),$(child KID2 polecat/x111 ',"task_kind":"rework","anchor_bead":"FDK2"'),$(demand KID2 closed)]"
gc bd dep KID2 --blocks FDK2 >/dev/null 2>&1
printf '%s' "$(prview 111 OPEN DIRTY CONFLICTING)" > "$GH_DIR/pr_view_111.json"
approve 111
out=$(run)
has "$out" "rework KID2 already covers branch 'polecat/x111' at this head, no new child" "a closed demand holds nothing; the own child dedups"
eq "$(jq '[.[] | select(.id | startswith("new-"))] | length' "$STUB_STORE")" "0" "…and no new rework child is minted"

echo "# …and an unreadable blocker list holds the dispatch, the safe side for a rewrite (tk-nak6pb)"
store "[$(anchor FBK3 98)]"
printf '%s' "$(prview 98 OPEN DIRTY CONFLICTING)" > "$GH_DIR/pr_view_98.json"
STUB_DEP_GARBAGE=1
out=$(run)
STUB_DEP_GARBAGE=""
has "$out" "the anchor is held by an unreadable blocker (a merge is held on it); no rework dispatched" "an unreadable edge list fails closed"
eq "$(jq '[.[] | select(.id | startswith("new-"))] | length' "$STUB_STORE")" "0" "…and no rework child is minted"

echo "# …and so does an operator's own merge_hold=true — a plain hold vetoes the dispatch"
store "[$(anchor F5d 90 ',"merge_hold":"true"')]"
printf '%s' "$(prview 90 OPEN DIRTY CONFLICTING)" > "$GH_DIR/pr_view_90.json"
out=$(run)
has "$out" "a hold is set (operator gate); no rework dispatched" "an operator's own hold still vetoes the dispatch"
eq "$(jq '[.[] | select(.id | startswith("new-")) | select((.metadata.task_kind // "") == "rework")] | length' "$STUB_STORE")" "0" "…and no rework child is minted"

echo "# …and a held + CONFLICTING anchor DEFERS fresh operator comments — the cap-park carve-out is gone (F5e successor)"
# The merge_hold skip above continues past the whole loop body, so the feedback
# arm never runs: a fresh operator comment on a held+conflicting PR is left
# unwatermarked and unrouted until the hold lifts. The retired cap park
# (merge_hold=signoff_cap) had a carve-out that still routed it to the person
# holding the anchor; every truthy merge_hold now defers it, and the five
# migrated parks are exactly merge_hold=true.
store "[$(anchor F5e 91 ',"merge_hold":"true"')]"
printf '%s' "$(prview 91 OPEN DIRTY CONFLICTING)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_91.json"
echo '[]' > "$GH_DIR/reviews_91.json"
printf '[{"id":9101,"user":{"login":"human1"},"body":"please rebase and address this"}]' > "$GH_DIR/comments_91.json"
out=$(run)
has "$out" "a hold is set (operator gate); no rework dispatched" "the held+conflicting anchor dispatches no rework"
eq "$(meta F5e pr_comment_disposition)" "<absent>" "…the fresh operator comment gets no disposition"
eq "$(meta F5e pr_comment_watermark)" "<absent>" "…the comment stays unwatermarked, deferred until the hold lifts"
eq "$(vpass_id F5e)" "<none>" "…and no validation pass is opened for it"
eq "$(meta F5e merge_hold)" "true" "…the operator's hold is left standing"
eq "$(jq '[.[] | select(.id | startswith("new-"))] | length' "$STUB_STORE")" "0" "…and no child of any kind is minted"

echo "# …and so does an armed re-dispatch: the anchor is parked, waiting to re-offer when ready (tk-79ffoh)"
# gc.dispatch_when_ready is deferred-dispatch's arm marker. While it is set the
# anchor is deliberately parked and this branch is superseded by a pending
# re-pour, so a rework minted here would be non-hand-offable: a polecat can only
# refuse it, and the pool re-offers the refusal until a human clears it.
store "[$(anchor FA1 95 ',"gc.dispatch_when_ready":"rig/gc-toolkit.polecat"')]"
printf '%s' "$(prview 95 OPEN DIRTY CONFLICTING)" > "$GH_DIR/pr_view_95.json"
: > "$STUB_SESSION_LOG"
out=$(run)
has "$out" "the anchor is armed to re-dispatch when ready (gc.dispatch_when_ready=rig/gc-toolkit.polecat); no rework dispatched" "an armed anchor vetoes the stale-base dispatch"
eq "$(jq '[.[] | select(.id | startswith("new-"))] | length' "$STUB_STORE")" "0" "…and no rework child is minted"
hasnt "$(cat "$STUB_SESSION_LOG")" "wake $FIX" "…and the fix pool is not woken"
eq "$(meta FA1 merge_result)" "pull_request" "…while the anchor keeps gating, so the merge still waits"

echo "# …and the SAME anchor without the arm dispatches a rework — the arm is the only thing holding it"
store "[$(anchor FA1 95)]"
approve 95
: > "$STUB_SESSION_LOG"
out=$(run)
has "$out" "filed merge-mode rework" "with no arm, the conflict dispatches a rework"
eq "$(jq '[.[] | select(.id | startswith("new-"))] | length' "$STUB_STORE")" "1" "…exactly one child, now that nothing holds it"

echo "# …a non-held CONFLICTING anchor with unanswered feedback routes it, files no merge-in child (tk-f9x2nb)"
# The mirror of F5e above: past the skip guards, a conflicting anchor that owes
# feedback falls through to the feedback arm rather than filing a merge-in child.
# Its prepare_mode=merge child brings the branch current as it answers, so one
# child does both and the review loop runs while the branch conflicts — which is
# what feeds the CHANGES_REQUESTED findings/validation/write-back sweep (#843).
store "[$(anchor CF1 160)]"
printf '%s' "$(prview 160 OPEN DIRTY CONFLICTING)" | jq -c '.reviewDecision = "CHANGES_REQUESTED"' > "$GH_DIR/pr_view_160.json"
echo '[]' > "$GH_DIR/reviews_160.json"
printf '[{"id":16000,"user":{"login":"human1"},"body":"please address this"}]' > "$GH_DIR/comments_160.json"
: > "$STUB_SESSION_LOG"
out=$(run)
DISP="$(meta CF1 pr_comment_disposition)"
has "$DISP" "rework:" "the conflicting anchor's feedback routes to a fix-pool rework child"
CFIX="${DISP#rework:}"
eq "$(meta "$CFIX" task_kind)" "rework" "…the fix unit carries the rework role marker"
eq "$(meta "$CFIX" anchor_bead)" "CF1" "…named to the anchor it holds"
eq "$(meta "$CFIX" prepare_mode)" "merge" "…brought current by merge, so it resolves the conflict as it answers"
eq "$(meta "$CFIX" branch)" "polecat/x160" "…on the PR's own branch"
eq "$(jq '[.[] | select((.metadata.rejection_reason // "") | test("stale base"))] | length' "$STUB_STORE")" "0" \
  "…and NO merge-in (stale-base) child is filed — a second one would twin it on the branch"
VP=$(vpass_id CF1)
hasnt "$VP" "<none>" "…a human-lane validation pass is opened on the anchor"
eq "$(meta "$VP" check_name)" "human" "…on the lane the validator's finding query selects"
FID=$(jq -r '[ .[] | select((.metadata.task_kind // "") == "finding") | select((.metadata.anchor_bead // "") == "CF1") | .id ] | .[0] // "<none>"' "$STUB_STORE")
hasnt "$FID" "<none>" "…the comment becomes a finding on the anchor, so the write-back has an input"
eq "$(meta "$FID" 'finding.lane')" "human" "…on the human lane the validator rules"
eq "$(meta CF1 pr_comment_watermark)" "16000" "…the comment is watermarked now, not deferred behind the conflict (contrast F5e)"
eq "$(meta CF1 merge_result)" "pull_request" "…and the anchor keeps gating (no state flip)"
has "$(cat "$STUB_SESSION_LOG")" "wake $FIX" "…and the fix pool is woken"

echo "# …and with NO fix pool it STILL routes that feedback — to a visit, not the void (tk-ixiuy4)"
# The branch/fix-pool guard is merge-in-only: it must not skip an anchor that owes
# feedback, because the feedback arm's own fallback dispositions a missing pool (or
# an unresolved head branch) as a human visit. Skipping it left operator feedback
# on a conflicting PR with no visit, no finding, and no validation pass — the very
# starvation this fix was supposed to end.
store "[$(anchor CF2 161)]"
printf '%s' "$(prview 161 OPEN DIRTY CONFLICTING)" | jq -c '.reviewDecision = "CHANGES_REQUESTED"' > "$GH_DIR/pr_view_161.json"
echo '[]' > "$GH_DIR/reviews_161.json"
printf '[{"id":16100,"user":{"login":"human1"},"body":"please address this"}]' > "$GH_DIR/comments_161.json"
: > "$STUB_ESC_LOG"
out=$("$SUT" --review-pool "$REV" 2>&1)   # no --fix-pool: the "no configured fix pool" case
hasnt "$out" "branch/fix-pool unavailable" "the no-pool conflict is NOT skipped at the merge-in guard"
DISP="$(meta CF2 pr_comment_disposition)"
has "$DISP" "visit:" "…its feedback routes to a human visit, the no-fix-pool fallback"
has "$(cat "$STUB_ESC_LOG")" "--subject CF2 --key pr-comments.161.0.16100" "…filed under the batch's comment key"
has "$(cat "$STUB_ESC_LOG")" "no fix pool is configured" "…naming why the city cannot route the work itself"
eq "$(jq '[.[] | select((.metadata.task_kind // "") == "rework") | select((.metadata.anchor_bead // "") == "CF2")] | length' "$STUB_STORE")" "0" "…and no rework child is minted with no pool to route it to"
hasnt "$(vpass_id CF2)" "<none>" "…a human-lane validation pass is still opened on the anchor"
FID2=$(jq -r '[ .[] | select((.metadata.task_kind // "") == "finding") | select((.metadata.anchor_bead // "") == "CF2") | .id ] | .[0] // "<none>"' "$STUB_STORE")
hasnt "$FID2" "<none>" "…and the comment still becomes a finding on the anchor"
eq "$(meta CF2 pr_comment_watermark)" "16100" "…the comment is watermarked now, not stranded behind the missing pool"
eq "$(meta CF2 merge_result)" "pull_request" "…while the anchor keeps gating"

echo "# …but a no-pool conflict with NOTHING to route still parks at that guard — the fix is scoped to feedback"
# The control for the case above: without unanswered feedback there is no feedback
# arm to fall through to, so the merge-in guard still holds the anchor for repair
# exactly as before. This is what proves the fix widened nothing but the feedback path.
store "[$(anchor CF3 162)]"
printf '%s' "$(prview 162 OPEN DIRTY CONFLICTING)" > "$GH_DIR/pr_view_162.json"
: > "$STUB_ESC_LOG"
out=$("$SUT" --review-pool "$REV" 2>&1)   # no --fix-pool, no feedback owed
has "$out" "branch/fix-pool unavailable; merge stays held" "with nothing to route, the guard still parks it for an operator to repair"
eq "$(meta CF3 pr_comment_disposition)" "<absent>" "…nothing is dispositioned"
eq "$(vpass_id CF3)" "<none>" "…and no validation pass is opened"

echo "# …a CLOSED rework at the current head is a finished round, NOT a cover: an approved PR gone CONFLICTING after its round, head unchanged, re-dispatches instead of wedging on the closed child"
store "[$(anchor F6 15), {\"id\":\"old-rw\",\"status\":\"closed\",\"assignee\":\"\",\"notes\":\"\",\"metadata\":{\"branch\":\"polecat/x15\",\"task_kind\":\"rework\",\"anchor_bead\":\"F6\",\"rejection_reason\":\"stale base at head sha-15: ...\"}}]"
printf '%s' "$(prview 15 OPEN DIRTY CONFLICTING)" > "$GH_DIR/pr_view_15.json"
approve 15
out=$(run)
has "$out" "filed merge-mode rework" "a closed child no longer suppresses the re-file; the still-dirty branch is re-dispatched"
eq "$(jq '[.[] | select(.id | startswith("new-")) | select((.metadata.task_kind // "") == "rework")] | length' "$STUB_STORE")" "1" "exactly one fresh merge-in child is minted"
out=$(run)
has "$out" "already covers branch" "…and the fresh OPEN child then dedups the next pass: the live-child guard still prevents a re-dispatch loop"
eq "$(jq '[.[] | select(.id | startswith("new-")) | select((.metadata.task_kind // "") == "rework")] | length' "$STUB_STORE")" "1" "still exactly one child — no loop"

echo "# …a created-but-unstamped rework orphan is ADOPTED, never twinned"
store "[$(anchor F4b 19)]"
printf '%s' "$(prview 19 OPEN DIRTY CONFLICTING)" > "$GH_DIR/pr_view_19.json"
approve 19
out=$(STUB_DROP_KEYS="new-2:branch,target,rejection_reason,merge_strategy,existing_pr,pr_url,pr_number,gc.routed_to" run)
eq "$(meta new-2 branch)" "<absent>" "first pass left an unstamped orphan (stamp dropped)"
out=$(run)
has "$out" "adopting unstamped rework orphan new-2" "the next pass adopts the orphan by its deterministic title"
eq "$(jq '[.[] | select(.id | startswith("new-")) | select((.metadata.task_kind // "") == "rework")] | length' "$STUB_STORE")" "1" "STILL exactly one rework child — no twin minted"
eq "$(meta new-2 branch)" "polecat/x19" "the adopted orphan is now fully stamped"
eq "$(meta new-2 'gc.routed_to')" "$FIX" "…and routed to the fix pool"
# The adoption re-stamps the identity with --set-metadata, which stores
# pr_number as a number, and the read-back still verifies the child.
eq "$(jq -r '.[] | select(.id == "new-2") | .metadata.pr_number | type' "$STUB_STORE")" "number" \
  "…its re-stamped pr_number reads back as the number bd stores, and the identity still verifies"

echo "# …atomic birth: a stamp that keeps the branch but drops rejection_reason is UNMADE, never a husk"
# The defect this bead fixes: a child left able to veto (branch + open) but not
# rescued (the stranded re-route keys on rejection_reason). Such a child must
# never exist — form it fully or unmake it.
store "[$(anchor AB1 70)]"
printf '%s' "$(prview 70 OPEN DIRTY CONFLICTING)" > "$GH_DIR/pr_view_70.json"
approve 70
out=$(STUB_DROP_KEYS="new-2:rejection_reason" run)
has "$out" "could not form the rework child for PR#70" "the arm refuses to route a child it could not fully form"
eq "$(bstatus new-2)" "closed" "the veto-capable-but-unrescuable newborn is unmade"
eq "$(meta new-2 gc.outcome)" "abandoned" "…and marked abandoned"
eq "$(jq '[.[] | select((.metadata.task_kind // "") == "rework") | select(.status == "open") | select((.metadata.rejection_reason // "") == "")] | length' "$STUB_STORE")" "0" "no OPEN rework child survives able to veto but missing rejection_reason"
hasnt "$out" "filed merge-mode rework new-2 routed" "the husk is never reported as dispatched"

echo "# …a SHARED head branch is classified merge, never rebase"
store "[$(anchor SB 28 '' 'integration/refinery-fixes')]"
printf '%s' "$(prview 28 OPEN DIRTY CONFLICTING '' 'integration/refinery-fixes')" > "$GH_DIR/pr_view_28.json"
approve 28
out=$(run)
has "$out" "filed merge-mode rework new-2" "the dispatch names the mode it classified"
eq "$(meta new-2 prepare_mode)" "merge" "an integration/* head is classified merge"
eq "$(bstatus new-2)" "open" "the child was filed"
has "$(jq -r '.[] | select(.id == "new-2") | .title' "$STUB_STORE")" "Merge main into PR#28 (branch integration/refinery-fixes)" "the TITLE names the mode an operator would act on by hand"
hasnt "$(meta new-2 rejection_reason)" "force-push with --force-with-lease" "the merge-mode work order must NOT instruct a force-push"
hasnt "$(meta new-2 rejection_reason)" "rebase 'integration" "…nor a rebase"
has "$(meta new-2 rejection_reason)" "MERGING origin/main IN" "…it names the non-destructive remedy instead"
has "$(meta new-2 rejection_reason)" "Do NOT rebase it and do NOT force-push it" "…and forbids the rewrite in words too"
eq "$(meta new-2 'gc.routed_to')" "$FIX" "the merge-mode child is still dispatched, not stalled on a human"

echo "# …a graduation on a polecat-shaped branch is brought current by merge, like every shape"
store "[$(anchor GD 29 ',"graduation":"true"')]"
printf '%s' "$(prview 29 OPEN DIRTY CONFLICTING)" > "$GH_DIR/pr_view_29.json"
approve 29
out=$(run)
eq "$(meta new-2 prepare_mode)" "merge" "a graduation is brought current by merge, like every branch shape"
hasnt "$(meta new-2 rejection_reason)" "force-push with --force-with-lease" "…and the work order names no force-push"

echo "# …a prepare_mode stamp that does not persist leaves the child UNROUTED"
store "[$(anchor DM 31)]"
printf '%s' "$(prview 31 OPEN DIRTY CONFLICTING)" > "$GH_DIR/pr_view_31.json"
approve 31
: > "$STUB_SESSION_LOG"
out=$(STUB_DROP_KEYS="new-2:prepare_mode" run)
has "$out" "could not form the rework child for PR#31" "the lost stamp is caught by the full-identity read-back"
eq "$(meta new-2 prepare_mode)" "<absent>" "the stamp really was dropped"
eq "$(meta new-2 'gc.routed_to')" "<absent>" "an unstamped child is inert, never routed with incomplete metadata"
hasnt "$(cat "$STUB_SESSION_LOG")" "wake $FIX" "…and the fix pool is not woken"

echo "# …a route stamp that does not persist leaves the rework UNDISPATCHED"
store "[$(anchor RT 32)]"
printf '%s' "$(prview 32 OPEN DIRTY CONFLICTING)" > "$GH_DIR/pr_view_32.json"
approve 32
: > "$STUB_SESSION_LOG"
out=$(STUB_DROP_KEYS="new-2:gc.routed_to" run)
eq "$(meta new-2 'gc.routed_to')" "<absent>" "the route stamp really was dropped"
has "$out" "formed but not routed to $FIX; left unrouted" "the lost route stamp is caught by a read-back"
hasnt "$out" "filed merge-mode rework new-2 routed to" "an unreachable rework is never reported as dispatched"
hasnt "$(cat "$STUB_SESSION_LOG")" "wake $FIX" "…and the fix pool is not woken"

echo "# …and the NEXT pass re-routes it, past the branch dedup that would bury it"
out=$(run)
has "$out" "re-routing stranded rework new-2" "the stranded child is adopted, not suppressed as a dup"
eq "$(meta new-2 'gc.routed_to')" "$FIX" "…and the route lands on the retry"
eq "$(jq '[.[] | select(.id | startswith("new-")) | select((.metadata.task_kind // "") == "rework")] | length' "$STUB_STORE")" "1" "…with no twin minted"
has "$out" "filed merge-mode rework new-2 routed to $FIX" "…and only now is the dispatch reported"

echo "# …once routed, the child dedups normally again"
out=$(run)
has "$out" "already covers branch" "a routed child suppresses a twin as before"

echo "# …a role-marker stamp that does not persist leaves the child UNROUTED, like the mode"
# task_kind=rework + anchor_bead sit in the same write as prepare_mode. A child
# routed with the marker dropped is a live rework on the anchor's OWN branch that
# a metadata read cannot tell from the anchor — the defect this bead prevents.
store "[$(anchor RM 35)]"
printf '%s' "$(prview 35 OPEN DIRTY CONFLICTING)" > "$GH_DIR/pr_view_35.json"
approve 35
: > "$STUB_SESSION_LOG"
out=$(STUB_DROP_KEYS="new-2:task_kind,anchor_bead" run)
has "$out" "could not form the rework child for PR#35" "a dropped role marker is caught by the full-identity read-back, before the route"
eq "$(meta new-2 task_kind)" "<absent>" "the marker stamp really was dropped"
eq "$(meta new-2 anchor_bead)" "<absent>" "…both halves of it"
eq "$(meta new-2 'gc.routed_to')" "<absent>" "…so the unmarked child is never routed"
hasnt "$(cat "$STUB_SESSION_LOG")" "wake $FIX" "…and the fix pool is not woken"
hasnt "$out" "filed merge-mode rework new-2 routed to" "…nor is it reported as dispatched"

echo "# …and the NEXT pass re-stamps it through the stranded arm, then routes"
out=$(run)
has "$out" "re-routing stranded rework new-2" "the unrouted child is adopted by the stranded arm, not buried"
eq "$(meta new-2 task_kind)" "rework" "…which re-stamps the role marker"
eq "$(meta new-2 anchor_bead)" "RM" "…and the anchor it belongs to"
eq "$(meta new-2 'gc.routed_to')" "$FIX" "…and only now is it routed"
eq "$(jq '[.[] | select(.id | startswith("new-"))] | length' "$STUB_STORE")" "1" "…with no twin minted"

echo "# …a merge_strategy stamp that does not persist leaves the child UNROUTED"
# merge_strategy=mr is part of the child's full identity; the read-back verifies it
# so a write that reports success but drops it never routes a child carrying no
# declared strategy. (existing_pr would still force mr on its own here — the
# read-back holds the whole identity, it does not lean on that recovery.)
store "[$(anchor MS 101)]"
printf '%s' "$(prview 101 OPEN DIRTY CONFLICTING)" > "$GH_DIR/pr_view_101.json"
approve 101
: > "$STUB_SESSION_LOG"
out=$(STUB_DROP_KEYS="new-2:merge_strategy" run)
has "$out" "could not form the rework child for PR#101" "a dropped merge_strategy is caught by the full-identity read-back, before the route"
eq "$(meta new-2 merge_strategy)" "<absent>" "the merge_strategy stamp really was dropped"
eq "$(meta new-2 'gc.routed_to')" "<absent>" "…so a child carrying no declared strategy is never routed"
hasnt "$(cat "$STUB_SESSION_LOG")" "wake $FIX" "…and the fix pool is not woken"
hasnt "$out" "filed merge-mode rework new-2 routed to" "…nor is it reported as dispatched"

echo "# …and the NEXT pass re-stamps merge_strategy through the stranded arm, then routes"
out=$(run)
has "$out" "re-routing stranded rework new-2" "the unrouted child is adopted by the stranded arm, not buried"
eq "$(meta new-2 merge_strategy)" "mr" "…which re-stamps the handoff-critical merge_strategy"
eq "$(meta new-2 'gc.routed_to')" "$FIX" "…and only now is it routed"
eq "$(jq '[.[] | select(.id | startswith("new-")) | select((.metadata.task_kind // "") == "rework")] | length' "$STUB_STORE")" "1" "…with no twin minted"

echo "# …the PR identity (existing_pr/pr_url/pr_number) is verified too, or a rework of a PR routes as a PR-less direct candidate"
# With the PR identity dropped AND merge_strategy absent, mol-refinery-patrol
# resolves an unset merge_strategy to direct and forces mr back only when
# existing_pr is present — so a child that loses both is pushed straight to the
# target branch instead of held as an mr-mode hand-back. The read-back verifies
# the whole PR identity so that shape is never routed.
store "[$(anchor PI 102)]"
printf '%s' "$(prview 102 OPEN DIRTY CONFLICTING)" > "$GH_DIR/pr_view_102.json"
approve 102
: > "$STUB_SESSION_LOG"
out=$(STUB_DROP_KEYS="new-2:existing_pr,pr_url,pr_number" run)
has "$out" "could not form the rework child for PR#102" "a dropped PR identity is caught by the full-identity read-back, before the route"
eq "$(meta new-2 existing_pr)" "<absent>" "the existing_pr stamp really was dropped"
eq "$(meta new-2 pr_number)" "<absent>" "…and the pr_number with it"
eq "$(meta new-2 'gc.routed_to')" "<absent>" "…so a rework of an existing PR is never routed as a PR-less direct candidate"
hasnt "$(cat "$STUB_SESSION_LOG")" "wake $FIX" "…and the fix pool is not woken"

echo "# …and the NEXT pass re-stamps the PR identity through the stranded arm, then routes"
out=$(run)
has "$out" "re-routing stranded rework new-2" "the unrouted child is adopted by the stranded arm"
eq "$(meta new-2 pr_number)" "102" "…which re-stamps the PR identity"
eq "$(meta new-2 'gc.routed_to')" "$FIX" "…and only now is it routed"
eq "$(jq '[.[] | select(.id | startswith("new-")) | select((.metadata.task_kind // "") == "rework")] | length' "$STUB_STORE")" "1" "…with no twin minted"

echo "# …a covering rework that lacks the role marker is re-stamped, never left as its anchor's twin"
# A routed-but-unclaimed child from a pass before this marker existed (or one
# whose stamp half-landed) is treated as already covering the conflict, so it
# never flows through the creation stamp. Re-stamp it in place rather than leave
# a live rework on the anchor's own branch a metadata read cannot tell apart.
cov='{"id":"cov-rw","status":"open","assignee":"","notes":"",'
cov="$cov"'"title":"Rebase PR#36 onto main: base rewritten, PR conflicts",'
cov="$cov"'"metadata":{"branch":"polecat/x36","gc.routed_to":"'"$FIX"'","rejection_reason":"stale base at head sha-36: x"}}'
store "[$(anchor CV 36), $cov]"
printf '%s' "$(prview 36 OPEN DIRTY CONFLICTING)" > "$GH_DIR/pr_view_36.json"
approve 36
eq "$(meta cov-rw task_kind)" "<absent>" "the covering child starts with no role marker"
out=$(run)
has "$out" "re-stamped role marker on covering rework cov-rw" "the dedup re-stamps the marker instead of only vetoing"
has "$out" "already covers branch 'polecat/x36' at this head, no new child" "…and still mints no twin"
eq "$(meta cov-rw task_kind)" "rework" "the covering child now carries task_kind=rework"
eq "$(meta cov-rw anchor_bead)" "CV" "…and names the anchor it reworks"
eq "$(jq '[.[] | select(.id | startswith("new-"))] | length' "$STUB_STORE")" "0" "no child was minted"

echo "# …a covering-child restamp that does not persist is reported UNMARKED (retry next pass), never done"
# The covering-child restamp shares gc bd update's return-0-without-writing
# failure with the create path: a marker that silently drops must leave the
# child reported unmarked so the next pass retries, never claimed re-stamped — a
# live rework left unmarked on the anchor's own branch is the misread the marker
# exists to stop.
covd='{"id":"cov-drop","status":"open","assignee":"","notes":"",'
covd="$covd"'"title":"Rebase PR#38 onto main: base rewritten, PR conflicts",'
covd="$covd"'"metadata":{"branch":"polecat/x38","gc.routed_to":"'"$FIX"'","rejection_reason":"stale base at head sha-38: x"}}'
store "[$(anchor CX 38), $covd]"
printf '%s' "$(prview 38 OPEN DIRTY CONFLICTING)" > "$GH_DIR/pr_view_38.json"
approve 38
eq "$(meta cov-drop task_kind)" "<absent>" "the covering child starts with no role marker"
out=$(STUB_DROP_KEYS="cov-drop:task_kind,anchor_bead" run)
hasnt "$out" "re-stamped role marker on covering rework cov-drop" "a restamp that half-lands is not reported as done"
has "$out" "could not re-stamp role marker on covering rework cov-drop (retry next pass)" "…the read-back catches the dropped marker and defers to the next pass"
eq "$(meta cov-drop task_kind)" "<absent>" "the marker really was dropped"
eq "$(meta cov-drop anchor_bead)" "<absent>" "…both halves of it"
has "$out" "already covers branch 'polecat/x38' at this head, no new child" "…while it still dedups the conflict"
eq "$(jq '[.[] | select(.id | startswith("new-"))] | length' "$STUB_STORE")" "0" "no child was minted"

echo "# …a CLOSED covering child blocks nothing: its round is over, so it is neither re-stamped nor read as covering, and the still-conflicting branch re-dispatches"
cov2='{"id":"cov-closed","status":"closed","assignee":"","notes":"",'
cov2="$cov2"'"title":"Rebase PR#37 onto main: base rewritten, PR conflicts",'
cov2="$cov2"'"metadata":{"branch":"polecat/x37","rejection_reason":"stale base at head sha-37: x"}}'
store "[$(anchor CW 37), $cov2]"
printf '%s' "$(prview 37 OPEN DIRTY CONFLICTING)" > "$GH_DIR/pr_view_37.json"
approve 37
out=$(run)
hasnt "$out" "re-stamped role marker" "a closed child is read by no live gate, so it is not re-stamped"
eq "$(meta cov-closed task_kind)" "<absent>" "…and its marker stays absent"
has "$out" "filed merge-mode rework" "…and it no longer dedups: the still-conflicting branch re-dispatches"

echo "# …a stranded rework a polecat has since claimed is never re-stamped under them"
held='{"id":"held-rw","status":"in_progress","assignee":"rig/gc-toolkit.polecat-2","notes":"",'
held="$held"'"title":"Rebase PR#33 onto main: base rewritten, PR conflicts",'
held="$held"'"metadata":{"branch":"polecat/x33","rejection_reason":"stale base at head sha-33: x"}}'
store "[$(anchor RT2 33), $held]"
printf '%s' "$(prview 33 OPEN DIRTY CONFLICTING)" > "$GH_DIR/pr_view_33.json"
approve 33
out=$(run)
has "$out" "already covers branch" "a claimed child still suppresses the arm"
eq "$(meta held-rw 'gc.routed_to')" "<absent>" "…and nothing is written under the holder"
eq "$(meta held-rw task_kind)" "<absent>" "…not even the role marker: the route read-back refuses to route an unmarked child, so a claimed one predates the stamp and is backfilled out of band, never written under its holder"

echo "# …a strand never overrides a LIVE sibling's claim on the force-push"
strand='{"id":"strand-rw","status":"open","assignee":"","notes":"",'
strand="$strand"'"title":"Rebase PR#34 onto main: base rewritten, PR conflicts",'
strand="$strand"'"metadata":{"branch":"polecat/x34","rejection_reason":"stale base at head sha-34: x"}}'
livesib='{"id":"live-rw","status":"in_progress","assignee":"rig/gc-toolkit.polecat-3","notes":"",'
livesib="$livesib"'"title":"Rebase PR#34 onto main: base rewritten, PR conflicts",'
livesib="$livesib"'"metadata":{"branch":"polecat/x34","rejection_reason":"stale base at head sha-old: x"}}'
# The strand is listed FIRST: it is open, so it matches the dedup's live arm and
# would be the one picked as the dup — the veto must not depend on that order.
store "[$strand, $livesib, $(anchor RT3 34)]"
printf '%s' "$(prview 34 OPEN DIRTY CONFLICTING)" > "$GH_DIR/pr_view_34.json"
approve 34
out=$(run)
has "$out" "rework live-rw already covers branch" "the live sibling still vetoes, strand or no strand"
has "$out" "unrouted sibling strand-rw is redundant" "…and the unreachable strand is named, not silently left"
eq "$(meta strand-rw 'gc.routed_to')" "<absent>" "…the strand is NOT routed into a race with it"
eq "$(jq '[.[] | select(.id | startswith("new-")) | select((.metadata.task_kind // "") == "rework")] | length' "$STUB_STORE")" "0" "…and no twin is minted"

echo "# an empty mergeCommit read never records an empty merged_sha"
store "[$(anchor F1b 24)]"
printf '%s' "$(prview 24 MERGED CLEAN MERGEABLE)" | jq -c 'del(.mergeCommit)' > "$GH_DIR/pr_view_24.json"
out=$(run)
has "$out" "recording merged_sha=unverified:PR#24" "the degraded record is loud"
eq "$(meta F1b merged_sha)" "unverified:PR#24" "merged_sha is never empty"
eq "$(bstatus F1b)" "closed" "the anchor still closed"

# A commit landing on the branch stales nothing: green is a state of the lane.
# The arm that filed a re-review child per head retired with the pin, and this
# is the anchor shape that used to trigger it.
echo "# a green lane at a head no verdict named files no re-review"
store "[$(anchor F9 18)]"
printf '%s' "$(prview 18 OPEN BLOCKED MERGEABLE)" > "$GH_DIR/pr_view_18.json"
: > "$STUB_GC_LOG"
out=$(run)
hasnt "$out" "filed re-review" "no re-review child is filed"
hasnt "$out" "is stale" "…and nothing here calls a moved head stale"
hasnt "$(cat "$STUB_GC_LOG")" "--on mol-review" "…and no review formula is poured from this arm"

fi # part reconcile

# ==== part posture: BLOCKED, dismissals, the posture record, the comment
# watermark, --posture-only and a sitting's hold ====
if part posture; then

echo "# BLOCKED on unresolved threads (thread resolution required): merge-blocked-threads"
store "[$(anchor B1 35)]"
printf '%s' "$(prview 35 OPEN BLOCKED MERGEABLE)" > "$GH_DIR/pr_view_35.json"
echo '{"threads":[{"id":"tb1a","isResolved":false},{"id":"tb1b","isResolved":true}]}' > "$GH_DIR/threads_35.json"
printf '[{"type":"pull_request","parameters":{"required_review_thread_resolution":true,"required_approving_review_count":1}}]' > "$GH_DIR/rules_main.json"
: > "$STUB_ESC_LOG"
out=$(run)
has "$out" "PR#35 BLOCKED on 1 unresolved review thread(s)" "the arm names the unresolved-thread cause and counts only the open ones"
has "$(cat "$STUB_ESC_LOG")" "--subject B1 --key merge-blocked-threads" "escalated under the thread-cause key"

echo "# BLOCKED with thread resolution OFF escalates nothing — the open thread is not the gate, and a pending approval is state"
store "[$(anchor B5 41)]"
printf '%s' "$(prview 41 OPEN BLOCKED MERGEABLE)" > "$GH_DIR/pr_view_41.json"
echo '{"threads":[{"id":"tb5","isResolved":false}]}' > "$GH_DIR/threads_41.json"
printf '[{"type":"pull_request","parameters":{"required_review_thread_resolution":false,"required_approving_review_count":1}}]' > "$GH_DIR/rules_main.json"
: > "$STUB_ESC_LOG"
out=$(run)
eq "$(cat "$STUB_ESC_LOG")" "" "an open thread with thread-resolution off is not the gate, and a required approving review is state, not a visit"

echo "# BLOCKED solely on a required approving review files NO visit (the operator's review queue is state)"
store "[$(anchor B2 36)]"
printf '%s' "$(prview 36 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_36.json"
echo '{"threads":[{"id":"tb2","isResolved":true}]}' > "$GH_DIR/threads_36.json"
printf '[{"type":"pull_request","parameters":{"required_review_thread_resolution":true,"required_approving_review_count":1}}]' > "$GH_DIR/rules_main.json"
: > "$STUB_ESC_LOG"
out=$(run)
eq "$(cat "$STUB_ESC_LOG")" "" "a PR blocked only on a required approving review escalates nothing"
hasnt "$out" "BLOCKED awaiting approval" "…and the removed approval arm no longer names the cause"

echo "# BLOCKED that neither a required thread nor a required approval explains escalates nothing"
store "[$(anchor B6 43)]"
printf '%s' "$(prview 43 OPEN BLOCKED MERGEABLE)" > "$GH_DIR/pr_view_43.json"
printf '[{"type":"pull_request","parameters":{"required_review_thread_resolution":false,"required_approving_review_count":0}}]' > "$GH_DIR/rules_main.json"
: > "$STUB_ESC_LOG"
out=$(run)
eq "$(cat "$STUB_ESC_LOG")" "" "an unmodeled cause is not escalated as a guess"

echo "# BLOCKED whose reviewThreads cannot be read (thread resolution required) escalates no guessed cause"
store "[$(anchor B3 37)]"
printf '%s' "$(prview 37 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_37.json"
echo '{"threads":[{"id":"tb3","isResolved":false}]}' > "$GH_DIR/threads_37.json"
printf '[{"type":"pull_request","parameters":{"required_review_thread_resolution":true,"required_approving_review_count":1}}]' > "$GH_DIR/rules_main.json"
: > "$STUB_ESC_LOG"
out=$(STUB_GQL_READ_FAIL=1 run)
eq "$(cat "$STUB_ESC_LOG")" "" "an unreadable connection escalates nothing — never a guessed cause"

echo "# BLOCKED whose branch rules cannot be read escalates no guessed cause"
store "[$(anchor B7 44)]"
printf '%s' "$(prview 44 OPEN BLOCKED MERGEABLE)" > "$GH_DIR/pr_view_44.json"
printf '{"message":"Not Found"}' > "$GH_DIR/rules_main.json"
: > "$STUB_ESC_LOG"
out=$(run)
eq "$(cat "$STUB_ESC_LOG")" "" "unreadable branch rules escalate nothing, not a guess"

echo "# a BLOCKED PR under an operator merge_hold is their gate, left unescalated"
store "[$(anchor B4 38 ',"merge_hold":"true"')]"
printf '%s' "$(prview 38 OPEN BLOCKED MERGEABLE)" > "$GH_DIR/pr_view_38.json"
echo '{"threads":[{"id":"tb4","isResolved":false}]}' > "$GH_DIR/threads_38.json"
printf '[{"type":"pull_request","parameters":{"required_review_thread_resolution":true,"required_approving_review_count":1}}]' > "$GH_DIR/rules_main.json"
: > "$STUB_ESC_LOG"
out=$(run)
eq "$(cat "$STUB_ESC_LOG")" "" "an operator merge_hold leaves the BLOCKED escalation unsent"
rm -f "$GH_DIR/rules_main.json"

echo "# the merge-blocked-approval visit category is retired: every open one is swept, even with no live anchors"
# A store whose PRs have all merged (no open pull_request anchor) is exactly
# where the no-anchors early-exit would skip a tail sweep, so the retirement runs
# before it. MC1's anchor is closed (its PR merged); MO1's is a live PR the board
# still surfaces as state; MX1 is unreadable this pass; ATV is a genuine
# unresolved-thread block under a different key.
store "[{\"id\":\"MC1\",\"status\":\"closed\",\"title\":\"t\",\"notes\":\"\",\"metadata\":{\"merge_result\":\"merged\"}}, {\"id\":\"MO1\",\"status\":\"open\",\"title\":\"t\",\"notes\":\"\",\"metadata\":{\"pr_posture\":\"review_required@sha-9@2026-09-18T00:00:00Z\"}}, {\"id\":\"AV1\",\"status\":\"open\",\"title\":\"visit\",\"notes\":\"\",\"metadata\":{\"escalation_key\":\"merge-blocked-approval\",\"gc.continuation_group\":\"MC1\",\"task_kind\":\"visit\",\"gc.routed_to\":\"human\"}}, {\"id\":\"AV2\",\"status\":\"open\",\"title\":\"visit\",\"notes\":\"\",\"metadata\":{\"escalation_key\":\"merge-blocked-approval\",\"gc.continuation_group\":\"MO1\",\"task_kind\":\"visit\",\"gc.routed_to\":\"human\"}}, {\"id\":\"AV3\",\"status\":\"open\",\"title\":\"visit\",\"notes\":\"\",\"metadata\":{\"escalation_key\":\"merge-blocked-approval\",\"gc.continuation_group\":\"MX1\",\"task_kind\":\"visit\",\"gc.routed_to\":\"human\"}}, {\"id\":\"ATV\",\"status\":\"open\",\"title\":\"visit\",\"notes\":\"\",\"metadata\":{\"escalation_key\":\"merge-blocked-threads\",\"gc.continuation_group\":\"MO1\",\"task_kind\":\"visit\",\"gc.routed_to\":\"human\"}}]"
: > "$STUB_ESC_LOG"
out=$(run); rc=$?
eq "$rc" 0 "the pass still exits 0"
has "$out" "no gating anchors" "the sweep ran ahead of the no-anchors early-exit"
eq "$(bstatus AV1)" "closed" "a visit whose PR merged (anchor closed) is retired"
eq "$(meta AV1 'gc.outcome')" "moot" "…closed moot — the premise it asked about is dead"
has "$(meta AV1 'gc.outcome_reason')" "a required approving review is state" "…with a reason, which the board shows as the sitting's headline"
has "$out" "retired stale merge-blocked-approval visit AV1" "the retirement is reported"
eq "$(bstatus AV2)" "closed" "a visit for a still-open PR is retired too — a required approving review is state, not a visit"
eq "$(meta AV2 'gc.outcome')" "moot" "…closed moot"
has "$(meta AV2 'gc.outcome_reason')" "Subject MO1 is open" "…with a reason naming its own subject's state"
eq "$(bstatus AV3)" "open" "a visit whose subject is unreadable this pass is left, never retired on a read that did not land"
eq "$(meta AV3 'gc.outcome')" "<absent>" "…and nothing is stamped on it"
has "$out" "subject MX1 unreadable" "…and the fail-closed skip is reported"
eq "$(bstatus ATV)" "open" "a genuine unresolved-thread visit (different key) is untouched by the approval sweep"
eq "$(cat "$STUB_ESC_LOG")" "" "the sweep files nothing — it only retires"

# pr-facts holds none of the visits it retires, so this retire passes --force as
# well: an open visit still assigned to a sitting closes like an unassigned one.
# STUB_ENFORCE_CLOSE_OWNER makes the stub refuse a plain close the way bd does.
# A close that does not land leaves its visit open and reported, and the sweep
# goes on to the next visit.
echo "# the approval retire closes an assigned visit, and a refused close leaves it for the next pass"
store "[{\"id\":\"MC2\",\"status\":\"closed\",\"title\":\"t\",\"notes\":\"\",\"metadata\":{\"merge_result\":\"merged\"}}, {\"id\":\"AV4\",\"status\":\"open\",\"assignee\":\"lx-sitting\",\"title\":\"visit\",\"notes\":\"\",\"metadata\":{\"escalation_key\":\"merge-blocked-approval\",\"gc.continuation_group\":\"MC2\",\"task_kind\":\"visit\",\"gc.routed_to\":\"human\"}}, {\"id\":\"AV5\",\"status\":\"open\",\"title\":\"visit\",\"notes\":\"\",\"metadata\":{\"escalation_key\":\"merge-blocked-approval\",\"gc.continuation_group\":\"MC2\",\"task_kind\":\"visit\",\"gc.routed_to\":\"human\"}}, {\"id\":\"AV6\",\"status\":\"open\",\"title\":\"visit\",\"notes\":\"\",\"metadata\":{\"escalation_key\":\"merge-blocked-approval\",\"gc.continuation_group\":\"MC2\",\"task_kind\":\"visit\",\"gc.routed_to\":\"human\"}}]"
out=$(STUB_ENFORCE_CLOSE_OWNER=1 STUB_CLOSE_FAIL="AV5" run); rc=$?
eq "$rc" 0 "a refused retire does not fail the pass"
eq "$(bstatus AV4)" "closed" "an approval visit still assigned to a sitting is retired over the claim"
has "$(meta AV4 'gc.outcome_reason')" "Subject MC2 is closed" "…with its reason"
eq "$(bstatus AV5)" "open" "a visit whose close is refused stays open for the next pass"
has "$out" "could not retire stale merge-blocked-approval visit AV5" "…and the refusal is reported"
eq "$(bstatus AV6)" "closed" "…while the sweep goes on to retire the next visit"

echo "# dismissal of our OWN superseded CHANGES_REQUESTED"
store "[$(anchor D1 20)]"
printf '%s' "$(prview 20 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "CHANGES_REQUESTED"' > "$GH_DIR/pr_view_20.json"
printf '[{"id":901,"user":{"login":"gc-city-bot"},"state":"CHANGES_REQUESTED","commit_id":"sha-OLD","submitted_at":"2026-08-19T00:00:00Z"}]' > "$GH_DIR/reviews_20.json"
: > "$STUB_GH_LOG"
out=$(run)
has "$out" "dismissed our own superseded CHANGES_REQUESTED (review 901)" "the stale own block is dismissed"
eq "$(meta D1 signoff_dismissed)" "901@sha-20" "signoff_dismissed recorded (and read back) first"
has "$(cat "$STUB_GH_LOG")" "DISMISS repos/zook/gc-toolkit/pulls/20/reviews/901/dismissals" "the dismissal hit the pinned endpoint"

echo "# …a human's CHANGES_REQUESTED is never dismissed"
store "[$(anchor D2 21)]"
printf '%s' "$(prview 21 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "CHANGES_REQUESTED"' > "$GH_DIR/pr_view_21.json"
printf '[{"id":902,"user":{"login":"human1"},"state":"CHANGES_REQUESTED","commit_id":"sha-OLD","submitted_at":"2026-08-19T00:00:00Z"}]' > "$GH_DIR/reviews_21.json"
: > "$STUB_GH_LOG"
out=$(run)
hasnt "$(cat "$STUB_GH_LOG")" "DISMISS" "a human's block is left standing"
eq "$(meta D2 signoff_dismissed)" "<absent>" "…and no marker is recorded"

echo "# …native auto-merge armed skips the dismissal"
store "[$(anchor D3 22)]"
printf '%s' "$(prview 22 OPEN BLOCKED MERGEABLE)" \
  | jq -c '.reviewDecision = "CHANGES_REQUESTED" | .autoMergeRequest = {"enabledAt":"x"}' > "$GH_DIR/pr_view_22.json"
printf '[{"id":903,"user":{"login":"gc-city-bot"},"state":"CHANGES_REQUESTED","commit_id":"sha-OLD","submitted_at":"2026-08-19T00:00:00Z"}]' > "$GH_DIR/reviews_22.json"
: > "$STUB_GH_LOG"
out=$(run)
has "$out" "auto-merge is armed" "the armed auto-merge is named"
hasnt "$(cat "$STUB_GH_LOG")" "DISMISS" "…and nothing is dismissed"

echo "# …marker that does not persist blocks the dismissal"
store "[$(anchor D4 23)]"
printf '%s' "$(prview 23 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "CHANGES_REQUESTED"' > "$GH_DIR/pr_view_23.json"
printf '[{"id":904,"user":{"login":"gc-city-bot"},"state":"CHANGES_REQUESTED","commit_id":"sha-OLD","submitted_at":"2026-08-19T00:00:00Z"}]' > "$GH_DIR/reviews_23.json"
: > "$STUB_GH_LOG"
out=$(STUB_DROP_KEYS="D4:signoff_dismissed" run)
has "$out" "marker did not persist; NOT dismissing" "an unrecorded marker fails closed"
hasnt "$(cat "$STUB_GH_LOG")" "DISMISS" "…and the dismissal is withheld"

echo "# …past the cutover, an unmarked CHANGES_REQUESTED under our login is feedback: never dismissed"
store "[$(anchor D5 164 ',"pr_provenance_since":"2026-10-07T00:00:00Z"')]"
printf '%s' "$(prview 164 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "CHANGES_REQUESTED"' > "$GH_DIR/pr_view_164.json"
printf '[{"id":905,"user":{"login":"gc-city-bot"},"state":"CHANGES_REQUESTED","commit_id":"sha-OLD","submitted_at":"2026-10-07T02:00:00Z"}]' > "$GH_DIR/reviews_164.json"
: > "$STUB_GH_LOG"
out=$(run)
hasnt "$(cat "$STUB_GH_LOG")" "DISMISS" "a model review's block is left standing"
eq "$(meta D5 signoff_dismissed)" "<absent>" "…and no marker is recorded"

echo "# …and a marked CHANGES_REQUESTED past the cutover is ours: dismissed"
store "[$(anchor D6 165 ',"pr_provenance_since":"2026-10-07T00:00:00Z"')]"
printf '%s' "$(prview 165 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "CHANGES_REQUESTED"' > "$GH_DIR/pr_view_165.json"
printf '[{"id":906,"user":{"login":"gc-city-bot"},"state":"CHANGES_REQUESTED","body":"\\n\\n<!-- gc:city -->","commit_id":"sha-OLD","submitted_at":"2026-10-07T02:00:00Z"}]' > "$GH_DIR/reviews_165.json"
: > "$STUB_GH_LOG"
out=$(run)
has "$(cat "$STUB_GH_LOG")" "DISMISS repos/zook/gc-toolkit/pulls/165/reviews/906/dismissals" "the city's own marked block is dismissed"

echo "# posture: an anchor blocked on a human approval says so"
# The sl-bgmuy/PR#552 fixture: check green at the live head, nothing in flight,
# and by the pack's old accounting indistinguishable from an anchor progressing.
store "[$(anchor S1 50)]"
printf '%s' "$(prview 50 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_50.json"
echo '[]' > "$GH_DIR/reviews_50.json"; echo '[]' > "$GH_DIR/comments_50.json"
out=$(run)
has "$out" "posture review_required@sha-50" "the pass names what it recorded"
eq "$(meta_pinned S1 pr_posture)" "review_required@sha-50" "the anchor carries the posture, pinned to the head"
eq "$(meta S1 pr_merge_state)" "BLOCKED@sha-50" "…and GitHub's mergeStateStatus verbatim beside it"
eq "$(meta S1 merge_result)" "pull_request" "recording a posture is not a state change"

echo "# …an unchanged posture is not re-written"
: > "$STUB_GC_LOG"
out=$(run)
eq "$(grep -c '^bd update S1' "$STUB_GC_LOG" || true)" "0" "no ledger churn when nothing moved"
hasnt "$out" "posture review_required" "…and the pass says nothing about it"

echo "# …a moved head re-pins it"
printf '%s' "$(prview 50 OPEN CLEAN MERGEABLE)" \
  | jq -c '.reviewDecision = "APPROVED" | .headRefOid = "sha-NEW"' > "$GH_DIR/pr_view_50.json"
out=$(run)
eq "$(meta_pinned S1 pr_posture)" "approved@sha-NEW" "the posture follows the head it was read at"
eq "$(meta S1 pr_merge_state)" "CLEAN@sha-NEW" "…so does the merge state"

echo "# COMMENTED is representable, and it routes to work"
# The fixture: inline comments that were neither approval nor
# veto, so nothing in the pack could name them.
store "[$(anchor P1 40)]"
printf '%s' "$(prview 40 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_40.json"
echo '[]' > "$GH_DIR/reviews_40.json"
printf '[{"id":5001,"user":{"login":"human1"},"body":"this path never runs","path":"docs/gate-calibration.md"}]' \
  > "$GH_DIR/comments_40.json"
: > "$STUB_SESSION_LOG"
out=$(run)
eq "$(meta_pinned P1 pr_posture)" "commented@sha-40" "COMMENTED is a recorded posture, not an unrepresentable one"
has "$out" "routed to rework:new-2" "the comment routed to something"
eq "$(meta P1 pr_comment_disposition)" "rework:new-2" "…and the choice is recorded on the anchor"
eq "$(meta P1 pr_comment_watermark)" "5001" "the watermark advanced to the routed comment"
eq "$(meta P1 pr_review_watermark)" "0" "…and the review id space stayed put (two spaces, never merged)"
eq "$(meta new-2 anchor_bead)" "P1" "the child names the anchor — this arm's dedup key"
eq "$(meta new-2 task_kind)" "rework" "…and its role, so a metadata read can tell it from the anchor"
eq "$(meta new-2 pr_number)" "40" "…and the PR, so merge.sh counts it in flight"
eq "$(meta new-2 branch)" "polecat/x40" "the child resumes the PR's own branch"
eq "$(meta new-2 prepare_mode)" "merge" "every branch shape is brought current by merge, polecat/* included"
eq "$(meta new-2 'gc.routed_to')" "$FIX" "the child is routed to the fix pool"
has "$(meta new-2 rejection_reason)" "Do NOT open a new PR" "the work order reworks THIS PR"
grep -qxF "new-2|blocks|P1" "$STUB_DEPS" && ok "the child blocks the anchor" || bad "blocks edge missing"
has "$(cat "$STUB_SESSION_LOG")" "wake $FIX" "the fix pool is woken"

echo "# …a comment below the watermark is answered; the batch never re-fires"
: > "$STUB_SESSION_LOG"
out=$(run)
eq "$(jq '[.[] | select(.id | startswith("new-")) | select((.metadata.task_kind // "") == "rework")] | length' "$STUB_STORE")" "1" "no twin child"
eq "$(meta_pinned P1 pr_posture)" "review_required@sha-40" "the answered comment falls back to the standing posture"
hasnt "$out" "routed to rework" "…and nothing re-routes"
hasnt "$(cat "$STUB_SESSION_LOG")" "wake $FIX" "…nor re-wakes the pool"

echo "# …a comment ABOVE the watermark is new, and gets its own batch"
printf '[{"id":5001,"user":{"login":"human1"},"body":"a"},{"id":5009,"user":{"login":"human1"},"body":"and another"}]' \
  > "$GH_DIR/comments_40.json"
out=$(run)
eq "$(meta_pinned P1 pr_posture)" "commented@sha-40" "a comment above the mark is outstanding by construction"
eq "$(meta P1 pr_comment_watermark)" "5009" "the watermark advanced past it"
eq "$(meta P1 pr_comment_disposition)" "rework:new-5" "the new batch got its own child (the first batch took new-2, its pass new-3, its finding new-4)"
eq "$(jq '[.[] | select(.id | startswith("new-")) | select((.metadata.task_kind // "") == "rework")] | length' "$STUB_STORE")" "2" "…and the first child was not reused"

echo "# a comment answered elsewhere (its thread resolved) is NOT unanswered — no false merge hold (tk-91ftmj)"
# The watermark advances only when THIS script routes, so a comment a sitting
# answered in-thread and resolved never moves it; without a path-independent read
# it reads unanswered forever and files a visit carrying pr_number that holds the
# merge. A resolved review thread is that path-independent "answered" signal.
store "[$(anchor AE1 470)]"
printf '%s' "$(prview 470 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_470.json"
echo '[]' > "$GH_DIR/reviews_470.json"
printf '[{"id":5001,"user":{"login":"human1"},"body":"please fix","path":"a.sh","line":3},{"id":5002,"user":{"login":"gc-city-bot"},"body":"fixed\\n\\n<!-- gc:city -->","path":"a.sh","line":3,"in_reply_to_id":5001}]' > "$GH_DIR/comments_470.json"
printf '%s\n' '{"reviews":[],"threads":[{"id":"T-470","isResolved":true,"viewerCanResolve":true,"comments":{"nodes":[{"id":"NC-470","databaseId":5001,"fullDatabaseId":"5001","author":{"login":"human1"},"body":"please fix","reactionGroups":[]},{"id":"NC-470b","databaseId":5002,"fullDatabaseId":"5002","author":{"login":"gc-city-bot"},"body":"fixed\n\n<!-- gc:city -->","reactionGroups":[]}]}}]}' > "$GH_DIR/threads_470.json"
: > "$STUB_SESSION_LOG"
out=$(run)
eq "$(meta_pinned AE1 pr_posture)" "review_required@sha-470" "a resolved-thread comment falls back to the standing posture, not commented"
hasnt "$out" "routed to rework" "the answered comment routes nothing"
eq "$(meta AE1 pr_comment_disposition)" "<absent>" "…and no disposition is recorded"
eq "$(meta AE1 pr_comment_watermark)" "<absent>" "…and the watermark does not advance"
hasnt "$(cat "$STUB_SESSION_LOG")" "wake $FIX" "…nor is the fix pool woken"

echo "# a resolved comment is dropped even when a higher-id unresolved one remains (tk-91ftmj)"
# The filter is per-comment, not all-or-nothing: the resolved comment (higher id)
# is dropped while the unresolved one still routes, so the watermark stops at the
# unresolved id — proof the higher resolved id was not counted.
store "[$(anchor AE2 471)]"
printf '%s' "$(prview 471 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_471.json"
echo '[]' > "$GH_DIR/reviews_471.json"
printf '[{"id":5101,"user":{"login":"human1"},"body":"still open","path":"a.sh","line":1},{"id":5109,"user":{"login":"human1"},"body":"answered","path":"b.sh","line":2},{"id":5110,"user":{"login":"gc-city-bot"},"body":"fixed\\n\\n<!-- gc:city -->","path":"b.sh","line":2,"in_reply_to_id":5109}]' > "$GH_DIR/comments_471.json"
printf '%s\n' '{"reviews":[],"threads":[{"id":"T-471a","isResolved":false,"viewerCanResolve":true,"comments":{"nodes":[{"id":"NC-471a","databaseId":5101,"fullDatabaseId":"5101","author":{"login":"human1"},"body":"still open","reactionGroups":[]}]}},{"id":"T-471b","isResolved":true,"viewerCanResolve":true,"comments":{"nodes":[{"id":"NC-471b","databaseId":5109,"fullDatabaseId":"5109","author":{"login":"human1"},"body":"answered","reactionGroups":[]},{"id":"NC-471c","databaseId":5110,"fullDatabaseId":"5110","author":{"login":"gc-city-bot"},"body":"fixed\n\n<!-- gc:city -->","reactionGroups":[]}]}}]}' > "$GH_DIR/threads_471.json"
out=$(run)
eq "$(meta_pinned AE2 pr_posture)" "commented@sha-471" "the unresolved comment still makes the PR commented"
has "$out" "routed to rework" "…and it routes"
eq "$(meta AE2 pr_comment_watermark)" "5101" "the watermark stops at the unresolved comment; the higher resolved id was dropped"

echo "# a thread read that fails counts the batch unfiltered — a failed read never drops an objection (tk-91ftmj)"
# The thread IS resolved, so a successful read would drop the comment; the forced
# read failure must fall back to counting it, never to silently answering it.
store "[$(anchor AE3 472)]"
printf '%s' "$(prview 472 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_472.json"
echo '[]' > "$GH_DIR/reviews_472.json"
printf '[{"id":5201,"user":{"login":"human1"},"body":"please fix","path":"a.sh","line":1},{"id":5202,"user":{"login":"gc-city-bot"},"body":"fixed\\n\\n<!-- gc:city -->","path":"a.sh","line":1,"in_reply_to_id":5201}]' > "$GH_DIR/comments_472.json"
printf '%s\n' '{"reviews":[],"threads":[{"id":"T-472","isResolved":true,"viewerCanResolve":true,"comments":{"nodes":[{"id":"NC-472","databaseId":5201,"fullDatabaseId":"5201","author":{"login":"human1"},"body":"please fix","reactionGroups":[]},{"id":"NC-472b","databaseId":5202,"fullDatabaseId":"5202","author":{"login":"gc-city-bot"},"body":"fixed\n\n<!-- gc:city -->","reactionGroups":[]}]}}]}' > "$GH_DIR/threads_472.json"
out=$(STUB_GQL_READ_FAIL=1 run)
has "$out" "review-thread resolution unreadable" "the failed read is reported"
has "$out" "routed to rework" "…and the comment is counted unfiltered and routes — never dropped on a failed read"
eq "$(meta AE3 pr_comment_watermark)" "5201" "…and the watermark advances"

echo "# the write-back's awaiting answer in a resolved thread answers nothing, so the comment before it routes"
# An awaiting answer says the comments before it wait on a person. A comment the
# routing arm had not reached when it was posted sits before it, and a thread
# someone then resolved must not read that comment as answered.
store "[$(anchor AEA 486)]"
printf '%s' "$(prview 486 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_486.json"
echo '[]' > "$GH_DIR/reviews_486.json"
printf '[{"id":5751,"user":{"login":"human1"},"body":"please fix","path":"a.sh","line":3},{"id":5752,"user":{"login":"gc-city-bot"},"body":"❓ Awaiting a person — visit V1.\\n<!-- gc-writeback -->\\n<!-- gc-writeback-mark:awaiting:V1 -->\\n\\n<!-- gc:city -->","path":"a.sh","line":3,"in_reply_to_id":5751}]' > "$GH_DIR/comments_486.json"
printf '%s\n' '{"reviews":[],"threads":[{"id":"T-486","isResolved":true,"viewerCanResolve":true,"comments":{"nodes":[{"id":"NC-486","databaseId":5751,"fullDatabaseId":"5751","author":{"login":"human1"},"body":"please fix","reactionGroups":[]},{"id":"NC-486b","databaseId":5752,"fullDatabaseId":"5752","author":{"login":"gc-city-bot"},"body":"❓ Awaiting a person — visit V1.\n<!-- gc-writeback -->\n<!-- gc-writeback-mark:awaiting:V1 -->\n\n<!-- gc:city -->","reactionGroups":[]}]}}]}' > "$GH_DIR/threads_486.json"
out=$(run)
has "$out" "routed to rework" "the comment before the awaiting answer routes"
eq "$(meta AEA pr_comment_watermark)" "5751" "…and the watermark advances to it"

echo "# a comment id past 2^31 is matched by fullDatabaseId, not the 32-bit databaseId"
# Review-comment ids already exceed a GraphQL Int. The thread here carries the id
# only as fullDatabaseId (a BigInt string) with databaseId null, the shape GitHub
# leaves once it retires the deprecated field, so a reader of databaseId matches
# nothing and routes the answered comment.
store "[$(anchor AE4 473)]"
printf '%s' "$(prview 473 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_473.json"
echo '[]' > "$GH_DIR/reviews_473.json"
printf '[{"id":4203522112,"user":{"login":"human1"},"body":"please fix","path":"a.sh","line":1},{"id":4203522150,"user":{"login":"gc-city-bot"},"body":"fixed\\n\\n<!-- gc:city -->","path":"a.sh","line":1,"in_reply_to_id":4203522112}]' > "$GH_DIR/comments_473.json"
printf '%s\n' '{"reviews":[],"threads":[{"id":"T-473","isResolved":true,"viewerCanResolve":true,"comments":{"nodes":[{"id":"NC-473","databaseId":null,"fullDatabaseId":"4203522112","author":{"login":"human1"},"body":"please fix","reactionGroups":[]},{"id":"NC-473b","databaseId":null,"fullDatabaseId":"4203522150","author":{"login":"gc-city-bot"},"body":"fixed\n\n<!-- gc:city -->","reactionGroups":[]}]}}]}' > "$GH_DIR/threads_473.json"
out=$(run)
eq "$(meta_pinned AE4 pr_posture)" "review_required@sha-473" "the answered comment past 2^31 is dropped: not commented"
hasnt "$out" "routed to rework" "…and it routes nothing"

echo "# one thread read serves every reader on an anchor visit"
# The incident's shape: the city replied unmarked, before the PR's provenance
# cutover, so the reply is the city's own and answers the human comment. The
# answered-comment read drops that comment, which leaves the unmarked reply for
# the unengaged-thread count to ask about. Both read this PR's threads in one
# posture pass, and the second reuses the first's nodes rather than reading the
# connection again.
store "[$(anchor AE5 474 ',"pr_provenance_since":"2026-10-07T00:00:00Z"')]"
printf '%s' "$(prview 474 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_474.json"
echo '[]' > "$GH_DIR/reviews_474.json"
printf '[{"id":5401,"user":{"login":"human1"},"body":"please fix","path":"a.sh","line":1,"created_at":"2026-10-06T10:00:00Z"},{"id":5402,"user":{"login":"gc-city-bot"},"body":"fixed","path":"a.sh","line":1,"in_reply_to_id":5401,"created_at":"2026-10-06T11:00:00Z"}]' > "$GH_DIR/comments_474.json"
printf '%s\n' '{"reviews":[],"threads":[{"id":"T-474","isResolved":true,"viewerCanResolve":true,"comments":{"nodes":[{"id":"NC-474a","databaseId":5401,"fullDatabaseId":"5401","author":{"login":"human1"},"body":"please fix","reactionGroups":[]},{"id":"NC-474b","databaseId":5402,"fullDatabaseId":"5402","author":{"login":"gc-city-bot"},"body":"fixed","createdAt":"2026-10-06T11:00:00Z","reactionGroups":[]}]}}]}' > "$GH_DIR/threads_474.json"
: > "$STUB_GH_LOG"
out=$(run_posture)
eq "$(meta_pinned AE5 pr_posture)" "review_required@sha-474" "the answered comment and the resolved thread hold nothing"
eq "$(grep -c 'reviewThreads(first:100' "$STUB_GH_LOG")" "1" "…and the two readers took one thread read between them"

echo "# a comment written after our last reply in a resolved thread is still outstanding"
# A reply does not reopen a resolved thread. The reviewer's "no, still broken"
# (5503) came after the city's reply (5502), so it is not answered, while the
# comment that reply answered (5501) is. The batch routes, and its mark stops at
# the outstanding comment.
store "[$(anchor AE6 475)]"
printf '%s' "$(prview 475 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_475.json"
echo '[]' > "$GH_DIR/reviews_475.json"
printf '[{"id":5501,"user":{"login":"human1"},"body":"please fix","path":"a.sh","line":1},{"id":5502,"user":{"login":"gc-city-bot"},"body":"fixed\\n\\n<!-- gc:city -->","path":"a.sh","line":1,"in_reply_to_id":5501},{"id":5503,"user":{"login":"human1"},"body":"no, this is still broken","path":"a.sh","line":1,"in_reply_to_id":5501}]' > "$GH_DIR/comments_475.json"
printf '%s\n' '{"reviews":[],"threads":[{"id":"T-475","isResolved":true,"viewerCanResolve":true,"comments":{"nodes":[{"id":"NC-475a","databaseId":5501,"fullDatabaseId":"5501","author":{"login":"human1"},"body":"please fix","reactionGroups":[]},{"id":"NC-475b","databaseId":5502,"fullDatabaseId":"5502","author":{"login":"gc-city-bot"},"body":"fixed\n\n<!-- gc:city -->","reactionGroups":[]},{"id":"NC-475c","databaseId":5503,"fullDatabaseId":"5503","author":{"login":"human1"},"body":"no, this is still broken","reactionGroups":[]}]}}]}' > "$GH_DIR/threads_475.json"
out=$(run)
eq "$(meta_pinned AE6 pr_posture)" "commented@sha-475" "the comment after our reply makes the PR commented"
has "$out" "routed to rework" "…and it routes"
eq "$(meta AE6 pr_comment_watermark)" "5503" "…through the outstanding comment"
CB=$(jq -r '[ .[] | select((.metadata.anchor_bead // "") == "AE6") | select((.metadata.task_kind // "") == "rework") | .description ] | .[0] // ""' "$STUB_STORE")
has "$CB" "no, this is still broken" "the work order carries the outstanding comment"
hasnt "$CB" "(comment 5501)" "…and not the one our reply answered"

echo "# a thread resolved with no reply of ours answers nothing"
# Resolution alone does not say the city answered: the comment routes as it would
# have with no thread read at all.
store "[$(anchor AE7 476)]"
printf '%s' "$(prview 476 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_476.json"
echo '[]' > "$GH_DIR/reviews_476.json"
printf '[{"id":5601,"user":{"login":"human1"},"body":"please fix","path":"a.sh","line":1}]' > "$GH_DIR/comments_476.json"
printf '%s\n' '{"reviews":[],"threads":[{"id":"T-476","isResolved":true,"viewerCanResolve":true,"comments":{"nodes":[{"id":"NC-476","databaseId":5601,"fullDatabaseId":"5601","author":{"login":"human1"},"body":"please fix","reactionGroups":[]}]}}]}' > "$GH_DIR/threads_476.json"
out=$(run)
eq "$(meta_pinned AE7 pr_posture)" "commented@sha-476" "a resolved thread with no reply of ours stays commented"
eq "$(meta AE7 pr_comment_watermark)" "5601" "…and its comment routes"

echo "# an unmarked reply under our login after the provenance cutover answers nothing"
# A reply of ours is a post that is the city's own. An unmarked one under our own
# login after the cutover is feedback, an operator's or a model's run on the
# city's account, so it answers nothing in the thread it sits in: both comments
# route.
store "[$(anchor AE10 485 ',"pr_provenance_since":"2026-10-07T00:00:00Z"')]"
printf '%s' "$(prview 485 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_485.json"
echo '[]' > "$GH_DIR/reviews_485.json"
printf '[{"id":5901,"user":{"login":"human1"},"body":"please fix","path":"a.sh","line":1,"created_at":"2026-10-07T01:00:00Z"},{"id":5902,"user":{"login":"gc-city-bot"},"body":"this is still broken","path":"a.sh","line":1,"in_reply_to_id":5901,"created_at":"2026-10-07T02:00:00Z"}]' > "$GH_DIR/comments_485.json"
printf '%s\n' '{"reviews":[],"threads":[{"id":"T-485","isResolved":true,"viewerCanResolve":true,"comments":{"nodes":[{"id":"NC-485a","databaseId":5901,"fullDatabaseId":"5901","author":{"login":"human1"},"body":"please fix","createdAt":"2026-10-07T01:00:00Z","reactionGroups":[]},{"id":"NC-485b","databaseId":5902,"fullDatabaseId":"5902","author":{"login":"gc-city-bot"},"body":"this is still broken","createdAt":"2026-10-07T02:00:00Z","reactionGroups":[]}]}}]}' > "$GH_DIR/threads_485.json"
out=$(run)
eq "$(meta_pinned AE10 pr_posture)" "commented@sha-485" "the unmarked post after the cutover answers nothing: commented"
eq "$(meta AE10 pr_comment_watermark)" "5902" "…and both comments route, the unmarked post as feedback"
CB=$(jq -r '[ .[] | select((.metadata.anchor_bead // "") == "AE10") | select((.metadata.task_kind // "") == "rework") | .description ] | .[0] // ""' "$STUB_STORE")
has "$CB" "please fix" "the work order carries the comment the unmarked post did not answer"
has "$CB" "this is still broken" "…and the unmarked post itself"

echo "# a batch routed by another space never lowers the comment watermark"
# 5701 was routed (mark 5701); 5702 arrived and both threads were answered, so
# the threads drop every comment and the filtered count is 0. A Conversation
# comment then routes the batch, and the transition writes the comment mark
# back: it has to stay at 5701, or every answered comment under it would route
# again the moment its thread lost the answer.
store "[$(anchor AE8 477 ',"pr_comment_watermark":5701')]"
printf '%s' "$(prview 477 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_477.json"
echo '[]' > "$GH_DIR/reviews_477.json"
printf '[{"id":5701,"user":{"login":"human1"},"body":"one","path":"a.sh","line":1},{"id":5702,"user":{"login":"human1"},"body":"two","path":"b.sh","line":1},{"id":5703,"user":{"login":"gc-city-bot"},"body":"fixed\\n\\n<!-- gc:city -->","path":"a.sh","line":1,"in_reply_to_id":5701},{"id":5704,"user":{"login":"gc-city-bot"},"body":"fixed\\n\\n<!-- gc:city -->","path":"b.sh","line":1,"in_reply_to_id":5702}]' > "$GH_DIR/comments_477.json"
printf '%s\n' '{"reviews":[],"threads":[{"id":"T-477a","isResolved":true,"viewerCanResolve":true,"comments":{"nodes":[{"id":"NC-477a","databaseId":5701,"fullDatabaseId":"5701","author":{"login":"human1"},"body":"one","reactionGroups":[]},{"id":"NC-477c","databaseId":5703,"fullDatabaseId":"5703","author":{"login":"gc-city-bot"},"body":"fixed\n\n<!-- gc:city -->","reactionGroups":[]}]}},{"id":"T-477b","isResolved":true,"viewerCanResolve":true,"comments":{"nodes":[{"id":"NC-477b","databaseId":5702,"fullDatabaseId":"5702","author":{"login":"human1"},"body":"two","reactionGroups":[]},{"id":"NC-477d","databaseId":5704,"fullDatabaseId":"5704","author":{"login":"gc-city-bot"},"body":"fixed\n\n<!-- gc:city -->","reactionGroups":[]}]}}]}' > "$GH_DIR/threads_477.json"
printf '[{"id":7701,"user":{"login":"human1"},"body":"one more thing"}]' > "$GH_DIR/issue_comments_477.json"
out=$(run)
has "$out" "routed to rework" "the Conversation comment routes the batch"
eq "$(meta AE8 pr_comment_watermark)" "5701" "…and the comment mark stays where it was, never 0"
eq "$(meta AE8 pr_issue_comment_watermark)" "7701" "…while the Conversation mark advances"

echo "# a dismissal never lowers the review watermark"
# Review 900 was routed (mark 900) and then dismissed, so the highest counted
# review is the older 800. A Conversation comment routing the batch writes the
# review mark back, and it stays at 900.
store "[$(anchor AE9 478 ',"pr_review_watermark":900')]"
printf '%s' "$(prview 478 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_478.json"
printf '[{"id":800,"user":{"login":"human1"},"state":"COMMENTED","body":"older"},{"id":900,"user":{"login":"human1"},"state":"DISMISSED","body":"retired"}]' > "$GH_DIR/reviews_478.json"
echo '[]' > "$GH_DIR/comments_478.json"
printf '[{"id":7801,"user":{"login":"human1"},"body":"one more thing"}]' > "$GH_DIR/issue_comments_478.json"
out=$(run)
has "$out" "routed to rework" "the Conversation comment routes the batch"
eq "$(meta AE9 pr_review_watermark)" "900" "…and the review mark stays at the dismissed review's id, never the older 800"

echo "# a review whose every inline comment its thread answered is answered, body and all"
# The incident's shape: a COMMENTED review with a summary body over its inline
# comments, each answered by the city in-thread and resolved. Dropping only the
# comments left the review id above its mark, so the batch still fired and the
# false hold stood.
store "[$(anchor AF1 479)]"
printf '%s' "$(prview 479 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_479.json"
printf '[{"id":9100,"user":{"login":"human1"},"state":"COMMENTED","body":"Sticking with comments on the docs change."}]' > "$GH_DIR/reviews_479.json"
printf '[{"id":9101,"user":{"login":"human1"},"body":"one","path":"a.md","line":1,"pull_request_review_id":9100},{"id":9102,"user":{"login":"human1"},"body":"two","path":"b.md","line":1,"pull_request_review_id":9100},{"id":9103,"user":{"login":"gc-city-bot"},"body":"fixed\\n\\n<!-- gc:city -->","path":"a.md","line":1,"in_reply_to_id":9101,"pull_request_review_id":9110},{"id":9104,"user":{"login":"gc-city-bot"},"body":"fixed\\n\\n<!-- gc:city -->","path":"b.md","line":1,"in_reply_to_id":9102,"pull_request_review_id":9111}]' > "$GH_DIR/comments_479.json"
printf '%s\n' '{"reviews":[],"threads":[{"id":"T-479a","isResolved":true,"viewerCanResolve":true,"comments":{"nodes":[{"id":"NC-479a","databaseId":9101,"fullDatabaseId":"9101","author":{"login":"human1"},"body":"one","reactionGroups":[]},{"id":"NC-479c","databaseId":9103,"fullDatabaseId":"9103","author":{"login":"gc-city-bot"},"body":"fixed\n\n<!-- gc:city -->","reactionGroups":[]}]}},{"id":"T-479b","isResolved":true,"viewerCanResolve":true,"comments":{"nodes":[{"id":"NC-479b","databaseId":9102,"fullDatabaseId":"9102","author":{"login":"human1"},"body":"two","reactionGroups":[]},{"id":"NC-479d","databaseId":9104,"fullDatabaseId":"9104","author":{"login":"gc-city-bot"},"body":"fixed\n\n<!-- gc:city -->","reactionGroups":[]}]}}]}' > "$GH_DIR/threads_479.json"
out=$(run)
eq "$(meta_pinned AF1 pr_posture)" "review_required@sha-479" "the answered review holds nothing: not commented"
hasnt "$out" "routed to" "…and routes nothing, neither a rework nor a visit"
eq "$(meta AF1 pr_review_watermark)" "<absent>" "…and no batch moved the review mark"

echo "# a review with one inline comment still outstanding keeps its body in the batch"
# Comment 9201 was answered and 9202 was not, so the review is not answered: its
# body and 9202 route, and 9201 does not.
store "[$(anchor AF2 480)]"
printf '%s' "$(prview 480 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_480.json"
printf '[{"id":9200,"user":{"login":"human1"},"state":"COMMENTED","body":"Two things below."}]' > "$GH_DIR/reviews_480.json"
printf '[{"id":9201,"user":{"login":"human1"},"body":"first thing","path":"a.md","line":1,"pull_request_review_id":9200},{"id":9202,"user":{"login":"human1"},"body":"second thing","path":"b.md","line":1,"pull_request_review_id":9200},{"id":9203,"user":{"login":"gc-city-bot"},"body":"fixed\\n\\n<!-- gc:city -->","path":"a.md","line":1,"in_reply_to_id":9201,"pull_request_review_id":9210}]' > "$GH_DIR/comments_480.json"
printf '%s\n' '{"reviews":[],"threads":[{"id":"T-480a","isResolved":true,"viewerCanResolve":true,"comments":{"nodes":[{"id":"NC-480a","databaseId":9201,"fullDatabaseId":"9201","author":{"login":"human1"},"body":"first thing","reactionGroups":[]},{"id":"NC-480c","databaseId":9203,"fullDatabaseId":"9203","author":{"login":"gc-city-bot"},"body":"fixed\n\n<!-- gc:city -->","reactionGroups":[]}]}},{"id":"T-480b","isResolved":false,"viewerCanResolve":true,"comments":{"nodes":[{"id":"NC-480b","databaseId":9202,"fullDatabaseId":"9202","author":{"login":"human1"},"body":"second thing","reactionGroups":[]}]}}]}' > "$GH_DIR/threads_480.json"
out=$(run)
eq "$(meta_pinned AF2 pr_posture)" "commented@sha-480" "the review with an outstanding comment keeps the PR commented"
eq "$(meta AF2 pr_review_watermark)" "9200" "…its body routes"
eq "$(meta AF2 pr_comment_watermark)" "9202" "…with the outstanding comment"
CB=$(jq -r '[ .[] | select((.metadata.anchor_bead // "") == "AF2") | select((.metadata.task_kind // "") == "rework") | .description ] | .[0] // ""' "$STUB_STORE")
has "$CB" "Two things below." "the work order carries the review body"
has "$CB" "second thing" "…and the outstanding comment"
hasnt "$CB" "first thing" "…and not the comment its thread answered"

echo "# a review submitted late over comments the mark already passed still routes"
# The mark passed 9301 before review 9300 (opened earlier, submitted later) became
# visible. The review is answered only on the threads' word, never the mark's:
# 9301's thread is open, so the body routes.
store "[$(anchor AF3 481 ',"pr_comment_watermark":9305')]"
printf '%s' "$(prview 481 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_481.json"
printf '[{"id":9300,"user":{"login":"human1"},"state":"COMMENTED","body":"Late review body."}]' > "$GH_DIR/reviews_481.json"
printf '[{"id":9301,"user":{"login":"human1"},"body":"late comment","path":"a.md","line":1,"pull_request_review_id":9300}]' > "$GH_DIR/comments_481.json"
printf '%s\n' '{"reviews":[],"threads":[{"id":"T-481","isResolved":false,"viewerCanResolve":true,"comments":{"nodes":[{"id":"NC-481","databaseId":9301,"fullDatabaseId":"9301","author":{"login":"human1"},"body":"late comment","reactionGroups":[]}]}}]}' > "$GH_DIR/threads_481.json"
out=$(run)
eq "$(meta_pinned AF3 pr_posture)" "commented@sha-481" "the late review is outstanding"
eq "$(meta AF3 pr_review_watermark)" "9300" "…and its body routes"

echo "# answered feedback is read once: the answered marks let later passes skip the threads"
# Nothing routes answered feedback, so no watermark moves past it. The first read
# records how far the threads answered past each watermark, and a pass whose newest
# feedback sits at or below those marks reads no threads at all. The city's reply
# carries the write-back marker, as its replies do, so the unengaged-thread
# backstop (which reads the threads for an unmarked comment of ours) asks nothing.
store "[$(anchor AG1 482)]"
printf '%s' "$(prview 482 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_482.json"
printf '[{"id":9400,"user":{"login":"human1"},"state":"COMMENTED","body":"Summary of the review."}]' > "$GH_DIR/reviews_482.json"
printf '[{"id":9401,"user":{"login":"human1"},"body":"answered comment","path":"a.md","line":1,"pull_request_review_id":9400},{"id":9402,"user":{"login":"gc-city-bot"},"body":"fixed <!-- gc-writeback -->","path":"a.md","line":1,"in_reply_to_id":9401,"pull_request_review_id":9410}]' > "$GH_DIR/comments_482.json"
printf '%s\n' '{"reviews":[],"threads":[{"id":"T-482a","isResolved":true,"viewerCanResolve":true,"comments":{"nodes":[{"id":"NC-482a","databaseId":9401,"fullDatabaseId":"9401","author":{"login":"human1"},"body":"answered comment","reactionGroups":[]},{"id":"NC-482b","databaseId":9402,"fullDatabaseId":"9402","author":{"login":"gc-city-bot"},"body":"fixed <!-- gc-writeback -->","reactionGroups":[]}]}}]}' > "$GH_DIR/threads_482.json"
: > "$STUB_GH_LOG"
out=$(run_posture)
eq "$(meta_pinned AG1 pr_posture)" "review_required@sha-482" "the answered review and comment hold nothing"
eq "$(grep -c 'reviewThreads(first:100' "$STUB_GH_LOG")" "1" "…the first pass reads the threads once"
eq "$(meta AG1 pr_comment_answered)" "9401" "…and records how far they answered the comments"
eq "$(meta AG1 pr_review_answered)" "9400" "…and the reviews"
: > "$STUB_GH_LOG"
out=$(run_posture)
eq "$(meta_pinned AG1 pr_posture)" "review_required@sha-482" "the next pass still drops the answered feedback"
eq "$(grep -c 'reviewThreads(first:100' "$STUB_GH_LOG")" "0" "…without reading the threads"
# A new comment above the mark brings the read back, and it routes alone.
printf '[{"id":9401,"user":{"login":"human1"},"body":"answered comment","path":"a.md","line":1,"pull_request_review_id":9400},{"id":9402,"user":{"login":"gc-city-bot"},"body":"fixed <!-- gc-writeback -->","path":"a.md","line":1,"in_reply_to_id":9401,"pull_request_review_id":9410},{"id":9405,"user":{"login":"human1"},"body":"a new comment","path":"b.md","line":1,"pull_request_review_id":9420}]' > "$GH_DIR/comments_482.json"
printf '%s\n' '{"reviews":[],"threads":[{"id":"T-482a","isResolved":true,"viewerCanResolve":true,"comments":{"nodes":[{"id":"NC-482a","databaseId":9401,"fullDatabaseId":"9401","author":{"login":"human1"},"body":"answered comment","reactionGroups":[]},{"id":"NC-482b","databaseId":9402,"fullDatabaseId":"9402","author":{"login":"gc-city-bot"},"body":"fixed <!-- gc-writeback -->","reactionGroups":[]}]}},{"id":"T-482c","isResolved":false,"viewerCanResolve":true,"comments":{"nodes":[{"id":"NC-482c","databaseId":9405,"fullDatabaseId":"9405","author":{"login":"human1"},"body":"a new comment","reactionGroups":[]}]}}]}' > "$GH_DIR/threads_482.json"
: > "$STUB_GH_LOG"
out=$(run)
has "$(cat "$STUB_GH_LOG")" "reviewThreads(first:100" "a comment above the mark brings the thread read back"
eq "$(meta_pinned AG1 pr_posture)" "commented@sha-482" "…the new comment makes the PR commented"
eq "$(meta AG1 pr_comment_watermark)" "9405" "…and routes"
CB=$(jq -r '[ .[] | select((.metadata.anchor_bead // "") == "AG1") | select((.metadata.task_kind // "") == "rework") | .description ] | .[0] // ""' "$STUB_STORE")
has "$CB" "a new comment" "the work order carries the new comment"
hasnt "$CB" "answered comment" "…and not the answered one"
hasnt "$CB" "Summary of the review." "…nor the answered review body"

echo "# a read brought back by a new comment re-reads what the mark covered"
# The mark passed 9501 when its thread was answered. The thread has since been
# unresolved; that alone routes nothing, but the new comment 9505 brings the read
# back, which finds 9501 outstanding too, so both route.
store "[$(anchor AG2 483 ',"pr_comment_answered":9501')]"
printf '%s' "$(prview 483 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_483.json"
echo '[]' > "$GH_DIR/reviews_483.json"
printf '[{"id":9501,"user":{"login":"human1"},"body":"reopened comment","path":"a.md","line":1},{"id":9502,"user":{"login":"gc-city-bot"},"body":"fixed\\n\\n<!-- gc:city -->","path":"a.md","line":1,"in_reply_to_id":9501},{"id":9505,"user":{"login":"human1"},"body":"a new comment","path":"b.md","line":1}]' > "$GH_DIR/comments_483.json"
printf '%s\n' '{"reviews":[],"threads":[{"id":"T-483a","isResolved":false,"viewerCanResolve":true,"comments":{"nodes":[{"id":"NC-483a","databaseId":9501,"fullDatabaseId":"9501","author":{"login":"human1"},"body":"reopened comment","reactionGroups":[]},{"id":"NC-483b","databaseId":9502,"fullDatabaseId":"9502","author":{"login":"gc-city-bot"},"body":"fixed\n\n<!-- gc:city -->","reactionGroups":[]}]}},{"id":"T-483c","isResolved":false,"viewerCanResolve":true,"comments":{"nodes":[{"id":"NC-483c","databaseId":9505,"fullDatabaseId":"9505","author":{"login":"human1"},"body":"a new comment","reactionGroups":[]}]}}]}' > "$GH_DIR/threads_483.json"
out=$(run)
eq "$(meta AG2 pr_comment_watermark)" "9505" "the batch routes"
CB=$(jq -r '[ .[] | select((.metadata.anchor_bead // "") == "AG2") | select((.metadata.task_kind // "") == "rework") | .description ] | .[0] // ""' "$STUB_STORE")
has "$CB" "reopened comment" "the work order carries the comment whose thread was unresolved"
has "$CB" "a new comment" "…beside the new one"

echo "# a thread read that fails drops only what the answered mark covers"
# 9601 was confirmed answered (mark 9601) before the read began to fail. The new
# comment 9605 routes, unfiltered, and the confirmed 9601 stays out of the batch.
store "[$(anchor AG3 484 ',"pr_comment_answered":9601')]"
printf '%s' "$(prview 484 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_484.json"
echo '[]' > "$GH_DIR/reviews_484.json"
printf '[{"id":9601,"user":{"login":"human1"},"body":"confirmed comment","path":"a.md","line":1},{"id":9602,"user":{"login":"gc-city-bot"},"body":"fixed\\n\\n<!-- gc:city -->","path":"a.md","line":1,"in_reply_to_id":9601},{"id":9605,"user":{"login":"human1"},"body":"a new comment","path":"b.md","line":1}]' > "$GH_DIR/comments_484.json"
printf '%s\n' '{"reviews":[],"threads":[]}' > "$GH_DIR/threads_484.json"
out=$(STUB_GQL_READ_FAIL=1 run)
has "$out" "review-thread resolution unreadable" "the failed read is reported"
eq "$(meta AG3 pr_comment_watermark)" "9605" "…the new comment routes"
CB=$(jq -r '[ .[] | select((.metadata.anchor_bead // "") == "AG3") | select((.metadata.task_kind // "") == "rework") | .description ] | .[0] // ""' "$STUB_STORE")
has "$CB" "a new comment" "the work order carries the new comment"
hasnt "$CB" "confirmed comment" "…and not the one the mark confirmed"

echo "# a feedback batch past the OS per-argument limit still renders"
# A busy PR's inline-comment list grew past Linux's
# per-argument cap (MAX_ARG_STRLEN, 128 KiB), so the jq that took the list as
# --argjson could not exec — the batch never rendered, never watermarked, and
# the merge held on a forever-retry commented posture. The lists ride stdin now,
# so the fixture is built past the cap: the old --argjson form fails to exec here.
store "[$(anchor BIG 70)]"
printf '%s' "$(prview 70 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_70.json"
echo '[]' > "$GH_DIR/reviews_70.json"
jq -nc '[ range(7000;7010) | {id: ., user:{login:"human1"}, body:("y"*14000), path:"docs/big.md", line:(.-7000)} ]' > "$GH_DIR/comments_70.json"
[ "$(wc -c < "$GH_DIR/comments_70.json")" -gt 131072 ] && ok "the fixture exceeds MAX_ARG_STRLEN, so the old --argjson form could not exec here" || bad "fixture too small to exercise the argv limit"
out=$(run)
hasnt "$out" "could not render the feedback findings" "the render survives a comment list past the argv limit"
hasnt "$out" "could not filter retired reviews" "…and so does the dismissal filter that shares the argv"
has "$out" "routed to rework:new-2" "the oversized batch routes like any other"
eq "$(meta BIG pr_comment_watermark)" "7009" "the watermark advances to the last comment in the oversized batch"
eq "$(meta BIG pr_comment_disposition)" "rework:new-2" "…and the disposition records on the anchor"

echo "# each batch's range is recorded by the transition that routes it"
store "[$(anchor P9 62)]"
printf '%s' "$(prview 62 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_62.json"
echo '[]' > "$GH_DIR/reviews_62.json"
printf '[{"id":6201,"user":{"login":"human1"},"body":"x"}]' > "$GH_DIR/comments_62.json"
out=$(run)
eq "$(meta P9 pr_comment_batch | sed 's/rework:[^|]*/rework:CHILD/g')" "rework:CHILD|0|6201" \
  "the routed batch carries its range from the first pass"
printf '[{"id":6201,"user":{"login":"human1"},"body":"x"},{"id":6209,"user":{"login":"human1"},"body":"y"}]' \
  > "$GH_DIR/comments_62.json"
out=$(run)
eq "$(meta P9 pr_comment_batch | sed 's/rework:[^|]*/rework:CHILD/g')" "rework:CHILD|0|6201;rework:CHILD|6201|6209" \
  "…and a second batch starts where the first one's mark stands"

echo "# a batch routed over a mark with NO recorded range starts at that mark"
# The state a pass leaves when it exits between routing a batch and recording
# its range: a disposition and a mark, no history. Derived after the fact, the
# next batch reads a single range running back to zero and answers comments the
# earlier bead owns. Written by the routing transition, it begins where the mark
# it replaces stands.
store "[$(anchor PA 66 ',"pr_comment_disposition":"rework:KOLD","pr_comment_watermark":"6601","pr_review_watermark":"0"')]"
printf '%s' "$(prview 66 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_66.json"
echo '[]' > "$GH_DIR/reviews_66.json"
printf '[{"id":6601,"user":{"login":"human1"},"body":"x"},{"id":6609,"user":{"login":"human1"},"body":"y"}]' \
  > "$GH_DIR/comments_66.json"
out=$(run)
eq "$(meta PA pr_comment_batch | sed 's/rework:[^|]*/rework:CHILD/g')" "rework:CHILD|6601|6609" \
  "the new batch begins at the standing mark, never back at zero"

echo "# a batch's review bodies and Conversation comments are recorded in ledgers of their own"
# Their ids are spaces unrelated to the inline comments', so the routing
# transition records each space's range in that space's ledger. The write-back
# finds a review body's or a Conversation comment's batch there, and a space a
# batch carried nothing in gains no record.
store "[$(anchor PRB 301)]"
printf '%s' "$(prview 301 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_301.json"
printf '[{"id":8801,"user":{"login":"human1"},"state":"COMMENTED","body":"rethink this"}]' > "$GH_DIR/reviews_301.json"
echo '[]' > "$GH_DIR/comments_301.json"
printf '[{"id":770301,"user":{"login":"human1"},"body":"and rename it"}]' > "$GH_DIR/issue_comments_301.json"
out=$(run)
eq "$(meta PRB pr_review_batch | sed 's/rework:[^|]*/rework:CHILD/g')" "rework:CHILD|0|8801" \
  "the review ledger carries the batch's review range"
eq "$(meta PRB pr_issue_comment_batch | sed 's/rework:[^|]*/rework:CHILD/g')" "rework:CHILD|0|770301" \
  "…and the Conversation ledger its issue-comment range, in the same transition"
eq "$(meta PRB pr_comment_batch | sed 's/rework:[^|]*/rework:CHILD/g')" "rework:CHILD|0|0" \
  "…while the inline ledger records the batch over an empty inline range"
printf '[{"id":770301,"user":{"login":"human1"},"body":"and rename it"},{"id":770309,"user":{"login":"human1"},"body":"one more"}]' \
  > "$GH_DIR/issue_comments_301.json"
out=$(run)
eq "$(meta PRB pr_issue_comment_batch | sed 's/rework:[^|]*/rework:CHILD/g')" "rework:CHILD|0|770301;rework:CHILD|770301|770309" \
  "a second batch starts where the first one's mark stands"
eq "$(meta PRB pr_review_batch | sed 's/rework:[^|]*/rework:CHILD/g')" "rework:CHILD|0|8801" \
  "…and a ledger whose space the batch carried nothing in gains no record"

echo "# a review ledger that cannot be parsed holds the batch unwatermarked"
store "[$(anchor PRC 302 ',"pr_review_batch":"rework:KX|y|1"')]"
printf '%s' "$(prview 302 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_302.json"
echo '[]' > "$GH_DIR/reviews_302.json"
printf '[{"id":9301,"user":{"login":"human1"},"body":"x"}]' > "$GH_DIR/comments_302.json"
out=$(run)
has "$out" "review or Conversation batch history is unreadable; NOT watermarking" "the unparsable ledger is reported"
eq "$(meta PRC pr_comment_watermark)" "<absent>" "…and the batch is not watermarked past it"

echo "# …a routing that lands but does not read back re-dispatches onto the SAME child"
store "[$(anchor W1 45)]"
printf '%s' "$(prview 45 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_45.json"
echo '[]' > "$GH_DIR/reviews_45.json"
printf '[{"id":9001,"user":{"login":"human1"},"body":"x"}]' > "$GH_DIR/comments_45.json"
out=$(STUB_DROP_KEYS="W1:pr_comment_watermark" run)
has "$out" "watermark did NOT record" "the lost watermark is caught by the read-back"
eq "$(meta W1 pr_comment_watermark)" "<absent>" "…the mark really did not move"
out=$(run)
has "$out" "already covers this batch; re-checking its route" "the next pass finds its own child"
eq "$(jq '[.[] | select(.id | startswith("new-")) | select((.metadata.task_kind // "") == "rework")] | length' "$STUB_STORE")" "1" "STILL one child — an unanswered comment never mints a twin"
eq "$(meta W1 pr_comment_watermark)" "9001" "…and the mark lands on the retry"

echo "# …an unstamped comment-rework orphan is ADOPTED, never twinned"
store "[$(anchor W2 46)]"
printf '%s' "$(prview 46 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_46.json"
echo '[]' > "$GH_DIR/reviews_46.json"
printf '[{"id":9100,"user":{"login":"human1"},"body":"x"}]' > "$GH_DIR/comments_46.json"
out=$(STUB_DROP_KEYS="new-2:anchor_bead" run)
has "$out" "did not record anchor_bead=W2; left unrouted" "an unstamped child is inert, never routed"
eq "$(meta new-2 'gc.routed_to')" "<absent>" "…and cannot be claimed"
out=$(run)
has "$out" "adopting unstamped comment-rework orphan new-2" "the next pass adopts it by its deterministic title"
eq "$(jq '[.[] | select(.id | startswith("new-")) | select((.metadata.task_kind // "") == "rework")] | length' "$STUB_STORE")" "1" "STILL exactly one child"
eq "$(meta new-2 'gc.routed_to')" "$FIX" "…now routed"

echo "# …but a CLOSED orphan is never adopted: it holds nothing and still moves the mark"
store "[$(anchor W3 47)]"
printf '%s' "$(prview 47 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_47.json"
echo '[]' > "$GH_DIR/reviews_47.json"
printf '[{"id":9200,"user":{"login":"human1"},"body":"x"}]' > "$GH_DIR/comments_47.json"
out=$(STUB_DROP_KEYS="new-2:anchor_bead" run)
has "$out" "did not record anchor_bead=W3; left unrouted" "the dropped stamp leaves an orphan again"
ctmp=$(mktemp "${TMPDIR:-/tmp}/gctk-pr-facts-test.XXXXXX"); jq -c 'map(if .id == "new-2" then .status = "closed" else . end)' "$STUB_STORE" > "$ctmp" && mv "$ctmp" "$STUB_STORE"
out=$(run)
hasnt "$out" "adopting unstamped comment-rework orphan" "a closed orphan is passed over"
eq "$(jq '[.[] | select(.id | startswith("new-")) | select((.metadata.task_kind // "") == "rework")] | length' "$STUB_STORE")" "2" "a live child is minted in its place"
eq "$(meta new-3 'gc.routed_to')" "$FIX" "…and that one is routed"
eq "$(meta W3 pr_comment_disposition)" "rework:new-3" "the disposition names the live child"
grep -qxF "new-3|blocks|W3" "$STUB_DEPS" && ok "…and it is what holds the merge" || bad "blocks edge missing"

echo "# …a child whose ROUTE stamp drops is never watermarked past"
# The blocks edge holds the merge either way, so the failure is not a silent
# merge — it is an unclaimable child plus a mark retired past the only comments
# that could re-file it.
store "[$(anchor W4 48)]"
printf '%s' "$(prview 48 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_48.json"
echo '[]' > "$GH_DIR/reviews_48.json"
printf '[{"id":9300,"user":{"login":"human1"},"body":"x"}]' > "$GH_DIR/comments_48.json"
out=$(STUB_DROP_KEYS="new-2:gc.routed_to" run)
has "$out" "is NOT routed to $FIX; NOT watermarking" "a dropped route stamp refuses the watermark"
eq "$(meta new-2 'gc.routed_to')" "<absent>" "…the child really is unclaimable"
eq "$(meta W4 pr_comment_watermark)" "<absent>" "…and the comment stays above the mark"
eq "$(meta W4 pr_comment_disposition)" "<absent>" "…with nothing recorded as its disposition"
out=$(run)
has "$out" "already covers this batch; re-checking its route" "the next pass re-checks the route it left behind"
eq "$(meta new-2 'gc.routed_to')" "$FIX" "…repairs it in place"
eq "$(jq '[.[] | select(.id | startswith("new-")) | select((.metadata.task_kind // "") == "rework")] | length' "$STUB_STORE")" "1" "…without minting a twin"
eq "$(meta W4 pr_comment_watermark)" "9300" "…and only then does the mark move"

echo "# …a child whose prepare_mode stamp drops is never routed, nor watermarked past"
# mol-polecat-work now resumes an absent mode as MERGE, so a dropped stamp no
# longer risks a rewrite; the read-back still refuses to route the child until the
# mode it was classified with is confirmed on the bead.
store "[$(anchor W6 50 '' 'integration/convoy-77')]"
printf '%s' "$(prview 50 OPEN BLOCKED MERGEABLE '' 'integration/convoy-77')" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_50.json"
echo '[]' > "$GH_DIR/reviews_50.json"
printf '[{"id":9600,"user":{"login":"human1"},"body":"x"}]' > "$GH_DIR/comments_50.json"
: > "$STUB_SESSION_LOG"
out=$(STUB_DROP_KEYS="new-2:prepare_mode" run)
has "$out" "did not record prepare_mode=merge; left unrouted and NOT watermarking" "the lost mode stamp is caught BEFORE the route"
eq "$(meta new-2 prepare_mode)" "<absent>" "the stamp really was dropped"
eq "$(meta new-2 'gc.routed_to')" "<absent>" "…so the child is never routed with incomplete metadata"
eq "$(meta W6 pr_comment_watermark)" "<absent>" "…and the comment stays above the mark"
eq "$(meta W6 pr_comment_disposition)" "<absent>" "…with nothing recorded as its disposition"
hasnt "$(cat "$STUB_SESSION_LOG")" "wake $FIX" "…and the fix pool is not woken"
out=$(run)
has "$out" "already covers this batch; re-checking its route" "the next pass finds its own child"
eq "$(meta new-2 prepare_mode)" "merge" "…re-stamps the mode it classified"
eq "$(meta new-2 'gc.routed_to')" "$FIX" "…and only then routes it"
eq "$(jq '[.[] | select(.id | startswith("new-")) | select((.metadata.task_kind // "") == "rework")] | length' "$STUB_STORE")" "1" "…without minting a twin"
eq "$(meta W6 pr_comment_watermark)" "9600" "…and only then does the mark move"

echo "# …a CLOSED child is dispositioned, so an unrouted one still converges"
store "[$(anchor W5 49)]"
printf '%s' "$(prview 49 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_49.json"
echo '[]' > "$GH_DIR/reviews_49.json"
printf '[{"id":9400,"user":{"login":"human1"},"body":"x"}]' > "$GH_DIR/comments_49.json"
out=$(STUB_DROP_KEYS="new-2:gc.routed_to" run)
has "$out" "NOT watermarking" "the unrouted child holds the mark"
ctmp=$(mktemp "${TMPDIR:-/tmp}/gctk-pr-facts-test.XXXXXX"); jq -c 'map(if .id == "new-2" then .status = "closed" else . end)' "$STUB_STORE" > "$ctmp" && mv "$ctmp" "$STUB_STORE"
out=$(run)
eq "$(meta W5 pr_comment_watermark)" "9400" "a closed child answers the batch even unrouted — refusing forever could not converge"

echo "# …a child whose task_kind stamp drops is never routed nor watermarked past, then re-stamped"
# anchor_bead is the dedup key and lands, so the create-path read-back passes;
# task_kind is the role marker, and a dropped one would leave a routed comment
# rework on the anchor's own branch that a metadata read cannot tell apart.
store "[$(anchor W7 51)]"
printf '%s' "$(prview 51 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_51.json"
echo '[]' > "$GH_DIR/reviews_51.json"
printf '[{"id":9700,"user":{"login":"human1"},"body":"x"}]' > "$GH_DIR/comments_51.json"
: > "$STUB_SESSION_LOG"
out=$(STUB_DROP_KEYS="new-2:task_kind" run)
has "$out" "did not record task_kind=rework; left unmarked and NOT watermarking" "a dropped role marker refuses the watermark"
eq "$(meta new-2 task_kind)" "<absent>" "the marker really was dropped"
eq "$(meta new-2 anchor_bead)" "W7" "…while the dedup key (anchor_bead) still landed"
eq "$(meta new-2 'gc.routed_to')" "<absent>" "…so the unmarked child is never routed"
eq "$(meta W7 pr_comment_watermark)" "<absent>" "…and the comment stays above the mark"
hasnt "$(cat "$STUB_SESSION_LOG")" "wake $FIX" "…and the fix pool is not woken"
out=$(run)
has "$out" "already covers this batch; re-checking its route" "the next pass finds its own child by anchor_bead"
eq "$(meta new-2 task_kind)" "rework" "…re-stamps the role marker on the recheck"
eq "$(meta new-2 'gc.routed_to')" "$FIX" "…and only then routes it"
eq "$(jq '[.[] | select(.id | startswith("new-")) | select((.metadata.task_kind // "") == "rework")] | length' "$STUB_STORE")" "1" "…without minting a twin rework child (the batch's own validation pass is a separate bead)"
eq "$(meta W7 pr_comment_watermark)" "9700" "…and only then does the mark move"

echo "# --posture-only: the record merge.sh reads, written before merge.sh runs"
# merge.sh reads pr_posture off the bead and never asks GitHub. The full arm
# runs AFTER merge, so a comment that arrived since the last pass would be
# invisible to the merge it should have held. This mode closes that window: it
# records, and dispatches nothing.
store "[$(anchor PO1 60)]"
printf '%s' "$(prview 60 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_60.json"
echo '[]' > "$GH_DIR/reviews_60.json"
printf '[{"id":9500,"user":{"login":"human1"},"body":"x"}]' > "$GH_DIR/comments_60.json"
: > "$STUB_SESSION_LOG"
out=$(run_posture); rc=$?
eq "$rc" 0 "a posture-only pass exits 0"
eq "$(meta_pinned PO1 pr_posture)" "commented@sha-60" "the posture is recorded"
eq "$(meta PO1 pr_merge_state)" "BLOCKED@sha-60" "…and the merge state beside it"
has "$out" "posture-only" "the summary names the mode"
eq "$(jq '[.[] | select(.id | startswith("new-")) | select((.metadata.task_kind // "") == "rework")] | length' "$STUB_STORE")" "0" "NOTHING was dispatched"
eq "$(meta PO1 pr_comment_watermark)" "<absent>" "…and no watermark moved: routing is the full pass's"
hasnt "$(cat "$STUB_SESSION_LOG")" "wake" "…no pool was woken"

echo "# …the full pass that follows still routes the same batch"
out=$(run)
eq "$(meta PO1 pr_comment_disposition)" "rework:new-2" "the comment is routed once the full arm runs"
eq "$(meta PO1 pr_comment_watermark)" "9500" "…and only then is it marked answered"

echo "# …a CONFLICTING anchor is recorded, never reworked, by this mode"
store "[$(anchor PO2 61)]"
printf '%s' "$(prview 61 OPEN DIRTY CONFLICTING)" > "$GH_DIR/pr_view_61.json"
echo '[]' > "$GH_DIR/reviews_61.json"
echo '[]' > "$GH_DIR/comments_61.json"
out=$(run_posture)
eq "$(meta_pinned PO2 pr_posture)" "none@sha-61" "the posture is still recorded"
hasnt "$out" "filed merge-mode rework" "…but no rework child is filed"
eq "$(jq '[.[] | select(.id | startswith("new-")) | select((.metadata.task_kind // "") == "rework")] | length' "$STUB_STORE")" "0" "…none at all"

echo "# …and MERGED/CLOSED reconciliation is left to the full pass"
store "[$(anchor PO3 62)]"
printf '%s' "$(prview 62 MERGED CLEAN MERGEABLE)" > "$GH_DIR/pr_view_62.json"
out=$(run_posture)
hasnt "$out" "is MERGED" "a merged PR is not reconciled by the posture pass"
eq "$(bstatus PO3)" "open" "…the anchor is left exactly as it was"
eq "$(meta PO3 merge_result)" "pull_request" "…with its state untouched"
out=$(run)
has "$out" "PR#62 is MERGED" "the full pass still records it"
eq "$(bstatus PO3)" "closed" "…and closes the anchor"

echo "# --posture-only: an anchor it could not make current holds the merge arm"
# merge.sh validates the posture recorded here and never asks GitHub. The only
# signal that a posture is NOT current is this arm's exit code, which
# refinery-reconcile reads to hold merge.sh for the pass.
store "[$(anchor PO4 63)]"
printf '%s' "$(prview 63 OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_63.json"
echo '[]' > "$GH_DIR/reviews_63.json"
printf '[{"id":9600,"user":{"login":"human1"},"body":"x"}]' > "$GH_DIR/comments_63.json"
out=$(STUB_UPDATE_FAIL="PO4" run_posture); rc=$?
eq "$rc" 1 "an unpersisted posture exits non-zero"
has "$out" "posture is not current" "…naming the anchor merge must not read"
has "$out" "1 not current" "…and counting it in the summary"
eq "$(meta PO4 pr_posture)" "<absent>" "…with nothing recorded"

echo "# …a posture it could not even determine holds the merge arm too"
# Nothing distinguishes our own comment from a human's without the acting login,
# so this pass cannot tell "no new comment" from "a comment it cannot see".
store "[$(anchor PO4 63)]"
out=$(STUB_SELF_LOGIN="" run_posture); rc=$?
eq "$rc" 1 "an undeterminable posture exits non-zero"
has "$out" "the acting login is unresolved" "…naming the read that failed"

echo "# …but a standing commented@ is already holding, so it is not the gap"
store "[$(anchor PO5 64 ',"pr_posture":"commented@sha-64"')]"
printf '%s' "$(prview 64 OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_64.json"
echo '[]' > "$GH_DIR/reviews_64.json"
echo '[]' > "$GH_DIR/comments_64.json"
out=$(STUB_SELF_LOGIN="" run_posture); rc=$?
eq "$rc" 0 "the arm does not hold the whole queue over an anchor already held"
eq "$(meta PO5 pr_posture)" "commented@sha-64" "…and the standing posture is untouched"

echo "# …the FULL pass never gates on the same condition (it runs after merge)"
store "[$(anchor PO6 65)]"
printf '%s' "$(prview 65 OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_65.json"
echo '[]' > "$GH_DIR/reviews_65.json"
echo '[]' > "$GH_DIR/comments_65.json"
out=$(STUB_SELF_LOGIN="" run); rc=$?
eq "$rc" 0 "the full pass exits 0"
has "$out" "not current" "…while still reporting the count"

echo "# a sitting still waiting on a person gets the comments, not the fix pool"
store "[$(anchor H1 44 ',"gc.takeaway":"holding — needs a ruling"'),$(demand H1)]"
printf '%s' "$(prview 44 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_44.json"
echo '[]' > "$GH_DIR/reviews_44.json"
printf '[{"id":8001,"user":{"login":"human1"},"body":"this is wrong"}]' > "$GH_DIR/comments_44.json"
: > "$STUB_ESC_LOG"; : > "$STUB_SESSION_LOG"
out=$(run)
has "$(cat "$STUB_ESC_LOG")" "--key pr-comments.44.0.8001" "the visit key names the exact batch"
has "$(cat "$STUB_ESC_LOG")" "a sitting is holding it for an operator ruling" "…and why no work could be routed"
eq "$(meta H1 pr_comment_disposition)" "visit:new-3" "the choice is recorded, and it is the visit"
eq "$(meta H1 pr_comment_watermark)" "8001" "the comment IS dispositioned — it went to a named party"
eq "$(meta new-3 task_kind)" "visit" "the visit was really filed"
eq "$(meta new-3 pr_number)" "44" "the visit carries the PR, which is what holds the merge"
hasnt "$(grep -F '|blocks|H1' "$STUB_DEPS" || true)" "new-3" "…and NOT a blocks edge: escalate.sh already files the visit depending on its subject"
hasnt "$(cat "$STUB_SESSION_LOG")" "wake $FIX" "no work was routed under the human's decision"

echo "# …while a takeaway whose sitting ENDED holds nothing: the comments become work"
store "[$(anchor H2 45 ',"gc.takeaway":"routed — nothing further needed here"'),$(demand H2 closed)]"
printf '%s' "$(prview 45 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_45.json"
echo '[]' > "$GH_DIR/reviews_45.json"
printf '[{"id":8002,"user":{"login":"human1"},"body":"this is wrong"}]' > "$GH_DIR/comments_45.json"
: > "$STUB_ESC_LOG"
out=$(run)
eq "$(meta H2 pr_comment_disposition)" "rework:new-3" "a closed demand is a sitting that ended, so the fix pool gets them"
eq "$(cat "$STUB_ESC_LOG")" "" "…and no visit is filed"
eq "$(meta H2 'gc.takeaway')" "routed — nothing further needed here" "…while the sitting's record is left alone"

echo "# …and so does rebase_hold: a child told to answer comments may rewrite the branch"
store "[$(anchor H5 54 ',"rebase_hold":"true"')]"
printf '%s' "$(prview 54 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_54.json"
echo '[]' > "$GH_DIR/reviews_54.json"
printf '[{"id":8400,"user":{"login":"human1"},"body":"x"}]' > "$GH_DIR/comments_54.json"
: > "$STUB_ESC_LOG"; : > "$STUB_SESSION_LOG"
out=$(run)
has "$(cat "$STUB_ESC_LOG")" "rebase_hold freezes the branch" "an operator branch freeze routes to the human, not the pool"
eq "$(meta H5 pr_comment_disposition)" "visit:new-2" "…and the visit is what is recorded"
hasnt "$(cat "$STUB_SESSION_LOG")" "wake $FIX" "…no work dispatched against the frozen branch"

echo "# …and so does an armed re-dispatch: feedback goes to a visit, never a rework on a superseded branch (tk-79ffoh)"
store "[$(anchor FA2 76 ',"gc.dispatch_when_ready":"rig/gc-toolkit.polecat"')]"
printf '%s' "$(prview 76 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_76.json"
echo '[]' > "$GH_DIR/reviews_76.json"
printf '[{"id":8600,"user":{"login":"human1"},"body":"x"}]' > "$GH_DIR/comments_76.json"
: > "$STUB_ESC_LOG"; : > "$STUB_SESSION_LOG"
out=$(run)
has "$(cat "$STUB_ESC_LOG")" "the anchor is armed to re-dispatch when ready" "an armed anchor routes feedback to the human, not the pool"
has "$(meta FA2 pr_comment_disposition)" "visit:" "…and the visit is what is recorded, not a rework"
hasnt "$(cat "$STUB_SESSION_LOG")" "wake $FIX" "…no rework dispatched against the superseded branch"

echo "# …a visit that did not take the stamp is NOT watermarked past"
store "[$(anchor H4 53 ',"gc.routed_to":"human"')]"
printf '%s' "$(prview 53 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_53.json"
echo '[]' > "$GH_DIR/reviews_53.json"
printf '[{"id":8300,"user":{"login":"human1"},"body":"x"}]' > "$GH_DIR/comments_53.json"
out=$(STUB_DROP_KEYS="new-2:pr_number" run)
has "$out" "did not record pr_number=53; NOT watermarking" "an unheld visit fails closed"
eq "$(meta H4 pr_comment_watermark)" "<absent>" "…the mark never moved past an unheld comment"
eq "$(meta_pinned H4 pr_posture)" "commented@sha-53" "…and the posture still holds the merge"

echo "# …so does an anchor already routed to a human, and one with no fix pool"
store "[$(anchor H2 47 ',"gc.routed_to":"human"')]"
printf '%s' "$(prview 47 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_47.json"
echo '[]' > "$GH_DIR/reviews_47.json"
printf '[{"id":8100,"user":{"login":"human1"},"body":"x"}]' > "$GH_DIR/comments_47.json"
: > "$STUB_ESC_LOG"
out=$(run)
has "$(cat "$STUB_ESC_LOG")" "already routed to a human" "a human-routed anchor gets a visit"
eq "$(meta H2 pr_comment_disposition)" "visit:new-2" "…and the visit is what is recorded"
store "[$(anchor H3 48)]"
printf '%s' "$(prview 48 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_48.json"
echo '[]' > "$GH_DIR/reviews_48.json"
printf '[{"id":8200,"user":{"login":"human1"},"body":"x"}]' > "$GH_DIR/comments_48.json"
: > "$STUB_ESC_LOG"
out=$("$SUT" --review-pool "$REV" 2>&1)
has "$(cat "$STUB_ESC_LOG")" "no fix pool is configured" "with nowhere to route work, the human is asked"
eq "$(meta H3 pr_comment_disposition)" "visit:new-2" "silence is never the answer"

fi # part posture

# ==== part feedback: validation passes, review bodies, CHANGES_REQUESTED and
# the reads that record nothing ====
if part feedback; then

# --- operator feedback opens a validation pass on the anchor --------------------
# A human feedback batch is review the branch has never been answered against, so
# it enters the graph the way a reviewer's findings do: a live check_name=human
# validation pass on the anchor — a task_kind=validation bead gate-ensure's
# quiescence reads to hold a fresh whole-diff review off the anchor while the
# validator rules the batch. This arm does not touch an operator's own hold. See
# specs/tk-ztapg/review-cycle-architecture.md, "What moves a lane backwards".
HELD_STATE=',"merge_hold":"true","gc.routed_to":"human","blocked_reason":"held for the operator to review"'

echo "# a human feedback batch opens one validation pass on the anchor, left unrouted"
store "[$(anchor V1 70)]"
printf '%s' "$(prview 70 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_70.json"
echo '[]' > "$GH_DIR/reviews_70.json"
printf '[{"id":8500,"user":{"login":"human1"},"body":"this is not what I asked for"}]' > "$GH_DIR/comments_70.json"
: > "$STUB_ESC_LOG"; : > "$STUB_SESSION_LOG"
out=$(run)
VP=$(vpass_id V1)
hasnt "$VP" "<none>" "the batch opens a validation pass on the anchor"
eq "$(meta "$VP" anchor_bead)" "V1" "…anchored to the gating anchor — the shape open_validation_pass reads"
eq "$(meta "$VP" check_name)" "human" "…naming lane human, which the validator's finding query consumes — never the whole check_set"
eq "$(meta "$VP" reviewed_oid)" "sha-70" "…pinned to the head the batch was produced at"
eq "$(meta "$VP" 'gc.routed_to')" "<absent>" "…and unrouted: gate-ensure dispatches mol-validate onto a validating lane"
grep -qxF "$VP|blocks|V1" "$STUB_DEPS" && ok "…and blocks the anchor: merge.sh holds the merge until the validator closes the pass" || bad "validation-pass blocks edge missing"
eq "$(meta V1 signoff_rounds_reset)" "<absent>" "the batch writes no signoff_rounds_reset"
eq "$(meta V1 'check.correctness')" "green" "…and no check.<lane>=validating marker is written; the lane derives that"
eq "$(meta V1 pr_comment_disposition)" "rework:new-2" "the comments still route to work (the pass is opened after, as new-3)"
has "$(cat "$STUB_SESSION_LOG")" "wake $FIX" "…and the fix pool is woken"
# …and the comment becomes a finding the validator rules, the shape a machine
# review's finding has (specs/tk-ztapg/review-cycle-architecture.md, "Findings").
FID1=$(jq -r '[ .[] | select((.metadata.task_kind // "") == "finding") | select((.metadata.anchor_bead // "") == "V1") | .id ] | .[0] // "<none>"' "$STUB_STORE")
hasnt "$FID1" "<none>" "the comment becomes a task_kind=finding bead on the anchor"
eq "$(meta "$FID1" 'finding.lane')" "human" "…on the human lane the validator's finding query selects (finding.lane == check_name)"
eq "$(meta "$FID1" 'finding.source')" "human:human1" "…sourced to the login that raised it, whose thread a decline's owed reply is posted back into"
eq "$(meta "$FID1" 'finding.disposition')" "unvalidated" "…unruled until the validator rules it"
grep -qxF "new-2|blocks|$FID1" "$STUB_DEPS" && bad "the rework child must NOT block the unvalidated finding at dispatch — a fix unit that blocked one the validator later declines would refuse its close" || ok "the rework child does not block the unvalidated finding; the validator hangs that edge only as it rules the finding must-fix"
grep -qxF "new-2|blocks|V1" "$STUB_DEPS" && ok "…the rework child still blocks the anchor, so the merge is held" || bad "rework child does not block the anchor (the merge hold is gone)"
eq "$(jq '[.[] | select((.metadata.task_kind // "") == "finding") | select((.metadata.anchor_bead // "") == "V1")] | length' "$STUB_STORE")" "1" "…one comment, one finding — no twin"

echo "# the batch watermarks once findings are filed and the pass is opened — no fix-unit-to-finding wire gates it"
# The fix-unit -> finding edges are no longer hung at dispatch, so a dep write
# that would have failed them cannot hold the batch: the findings are filed, the
# validation pass is opened, and the disposition is watermarked. The validator
# hangs the close-ordering edge as it rules each finding must-fix.
store "[$(anchor Vw 87)]"
printf '%s' "$(prview 87 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_87.json"
echo '[]' > "$GH_DIR/reviews_87.json"
printf '[{"id":8870,"user":{"login":"human1"},"body":"still not what I asked for"}]' > "$GH_DIR/comments_87.json"
out=$(run)
hasnt "$out" "wire rework child" "no fix-unit-to-finding wire is attempted at dispatch"
FIDW=$(jq -r '[ .[] | select((.metadata.task_kind // "") == "finding") | select((.metadata.anchor_bead // "") == "Vw") | .id ] | .[0] // "<none>"' "$STUB_STORE")
hasnt "$FIDW" "<none>" "the comment is filed as a finding"
grep -qxF "new-2|blocks|$FIDW" "$STUB_DEPS" && bad "the rework child must not block the unvalidated finding" || ok "…which the rework child does not block at dispatch"
eq "$(meta Vw pr_comment_disposition)" "rework:new-2" "…and the batch watermarks its rework disposition"

echo "# a multi-lane anchor opens ONE human-lane pass, not a synthetic correctness,arch lane"
# check_name is the lane the validator rules; mol-validate matches findings by
# finding.lane == check_name and a human batch's findings are finding.lane=human,
# so the pass names human whatever the anchor's lanes are. The whole check_set
# (correctness,arch) is one synthetic lane no finding carries — the multi-lane bug.
store "[$(anchor Vm 75 ',"check_set":"correctness,arch","check.arch":"green"')]"
printf '%s' "$(prview 75 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_75.json"
echo '[]' > "$GH_DIR/reviews_75.json"
printf '[{"id":8750,"user":{"login":"human1"},"body":"this misreads the arch lane"}]' > "$GH_DIR/comments_75.json"
out=$(run)
VPM=$(vpass_id Vm)
hasnt "$VPM" "<none>" "the multi-lane anchor opens a validation pass"
eq "$(meta "$VPM" check_name)" "human" "…named human, never the synthetic correctness,arch that matches no finding and backs no real lane"
grep -qxF "$VPM|blocks|Vm" "$STUB_DEPS" && ok "…and it blocks the multi-lane anchor, both lanes green or not" || bad "validation-pass blocks edge missing"

echo "# a validation-pass blocks edge that will not attach warns, holds the batch, and does not watermark"
# The pass and its blocks edge are separate writes; an edge that cannot be
# attached and read back is a pass that holds nothing, so the batch is not
# watermarked and retries. The rework child is already filed, so the retry is free.
store "[$(anchor Vb 76)]"
printf '%s' "$(prview 76 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_76.json"
echo '[]' > "$GH_DIR/reviews_76.json"
printf '[{"id":8760,"user":{"login":"human1"},"body":"x"}]' > "$GH_DIR/comments_76.json"
out=$(STUB_DEP_FAIL="new-3" run)
has "$out" "did not record a blocks edge" "the unattached edge is reported, not swallowed"
hasnt "$(grep -F '|blocks|Vb' "$STUB_DEPS" || true)" "new-3" "…and no pass blocks edge stands on the anchor"
eq "$(meta Vb pr_comment_disposition)" "<absent>" "…the batch is not watermarked until the pass holds, so it retries"
eq "$(meta new-2 'gc.routed_to')" "$FIX" "…while the rework child is already filed and routed"

echo "# a batch whose watermark write dropped opens no second human-lane pass"
# The pass and the watermark are separate writes, so a pass that opened but whose
# mark did not record sees the same comment again. The live human-lane pass, not
# the mark, is what stops the twin.
EXIST_VP='{"id":"vp-71","status":"open","assignee":"","title":"Validate PR#71 feedback (through review 0, comment 8510)","notes":"","metadata":{"task_kind":"validation","anchor_bead":"Ve","check_name":"human","reviewed_oid":"sha-71"}}'
store "[$(anchor Ve 71),$EXIST_VP]"
printf '%s' "$(prview 71 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_71.json"
echo '[]' > "$GH_DIR/reviews_71.json"
printf '[{"id":8510,"user":{"login":"human1"},"body":"x"}]' > "$GH_DIR/comments_71.json"
out=$(run)
eq "$(jq '[.[] | select((.metadata.task_kind // "") == "validation") | select((.metadata.anchor_bead // "") == "Ve")] | length' "$STUB_STORE")" "1" "the human-lane pass already open rules the batch, so no second one opens"
has "$out" "already carries a human-lane validation pass vp-71" "…and the pass names the one already open"

echo "# a correctness validation pass on the anchor does NOT stand in for the human batch"
# gate-ensure's quiescence reads any validation pass, so a correctness pass holds the
# merge — but mol-validate rules a pass by check_name, and a correctness pass never rules
# the human findings (finding.lane=human). The dedup is the human LANE, so the
# batch opens its own human-lane pass beside the correctness one rather than watermarking
# behind a pass that leaves its findings unruled.
CODEX_VP='{"id":"cvp-77","status":"open","assignee":"","title":"Validate correctness lane on Vx","notes":"","metadata":{"task_kind":"validation","anchor_bead":"Vx","check_name":"correctness","reviewed_oid":"sha-77"}}'
store "[$(anchor Vx 77),$CODEX_VP]"
printf '%s' "$(prview 77 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_77.json"
echo '[]' > "$GH_DIR/reviews_77.json"
printf '[{"id":8770,"user":{"login":"human1"},"body":"the correctness pass never sees this"}]' > "$GH_DIR/comments_77.json"
out=$(run)
HP=$(jq -r '[ .[] | select((.metadata.task_kind // "") == "validation") | select((.metadata.anchor_bead // "") == "Vx") | select((.metadata.check_name // "") == "human") | .id ] | .[0] // "<none>"' "$STUB_STORE")
hasnt "$HP" "<none>" "the human batch opens its own human-lane pass, not reusing the correctness one"
eq "$(meta "$HP" check_name)" "human" "…named human, the lane the validator rules the batch by"
eq "$(meta "$HP" reviewed_oid)" "sha-77" "…pinned to the head the batch was produced at"
grep -qxF "$HP|blocks|Vx" "$STUB_DEPS" && ok "…and it blocks the anchor, beside the correctness pass" || bad "human-lane validation-pass blocks edge missing"

echo "# an unstamped validation-pass orphan from a dropped stamp is adopted, not twinned"
# A prior pass created the bead but its stamp dropped, so it carries no
# check_name and the human-lane probe cannot see it; the title probe adopts it
# rather than mint a twin.
ORPH='{"id":"orph-72","status":"open","assignee":"","title":"Validate PR#72 feedback (through review 0, comment 8720)","notes":"","metadata":{}}'
store "[$(anchor Vo 72),$ORPH]"
printf '%s' "$(prview 72 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_72.json"
echo '[]' > "$GH_DIR/reviews_72.json"
printf '[{"id":8720,"user":{"login":"human1"},"body":"one more thing"}]' > "$GH_DIR/comments_72.json"
out=$(run)
has "$out" "adopting unstamped validation-pass orphan orph-72" "the orphan is adopted"
eq "$(vpass_id Vo)" "orph-72" "…and stamped into the pass, no twin minted"
eq "$(meta orph-72 anchor_bead)" "Vo" "…now carrying the anchor open_validation_pass reads"

echo "# a held anchor: the batch opens a pass but does NOT lift the operator's hold"
# An operator's own hold is theirs to lift, so this arm never touches it; it
# stays, and the comments go to the person holding it.
store "[$(anchor Vc 73 "$HELD_STATE")]"
printf '%s' "$(prview 73 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_73.json"
echo '[]' > "$GH_DIR/reviews_73.json"
printf '[{"id":8730,"user":{"login":"human1"},"body":"still not right"}]' > "$GH_DIR/comments_73.json"
out=$(run)
hasnt "$(vpass_id Vc)" "<none>" "the batch still opens a validation pass"
eq "$(meta Vc merge_hold)" "true" "…but the operator's hold is left standing — this arm does not touch it"
eq "$(meta Vc 'gc.routed_to')" "human" "…nor the human route"
eq "$(meta Vc signoff_rounds_reset)" "<absent>" "…and no signoff_rounds_reset is written"
eq "$(meta Vc pr_comment_disposition)" "visit:new-2" "…so the comments go to the person holding it, not to work"

echo "# a verdict the city posted itself is not feedback, and opens no pass"
# Provenance, not shape: signoff.sh posts its verdicts through pr-post.sh, which
# marks them as the city's own, and a rework hand-back posts nothing at all, so
# neither reaches this arm.
store "[$(anchor R3 57 ',"merge_hold":"true","gc.routed_to":"human"')]"
printf '%s' "$(prview 57 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_57.json"
printf '[{"id":7500,"user":{"login":"gc-city-bot"},"state":"COMMENTED","body":"Signoff verdict: request-changes\\n\\n<!-- gc:city -->","commit_id":"sha-57"}]' \
  > "$GH_DIR/reviews_57.json"
printf '[{"id":8700,"user":{"login":"gc-city-bot"},"body":"P2: nit at foo.sh:3\\n\\n<!-- gc:city -->"}]' > "$GH_DIR/comments_57.json"
# The city's own inline nit sits in a RESOLVED thread. The unengaged backstop (a
# separate arm) counts only unresolved threads holding an unmarked comment, so it
# finds nothing here and the posture is review_required.
printf '%s\n' '{"reviews":[],"threads":[{"id":"T-57","isResolved":true,"viewerCanResolve":true,"comments":{"nodes":[{"id":"NC-57","databaseId":100,"author":{"login":"gc-city-bot"},"body":"P2: nit at foo.sh:3\n\n<!-- gc:city -->","reactionGroups":[]}]}}]}' > "$GH_DIR/threads_57.json"
out=$(run)
eq "$(meta_pinned R3 pr_posture)" "review_required@sha-57" "the city's own verdict is not an outstanding comment"
eq "$(vpass_id R3)" "<none>" "…so no validation pass opens"
eq "$(meta R3 merge_hold)" "true" "…the operator's hold stands, untouched"
eq "$(meta R3 'gc.routed_to')" "human" "…and the anchor stays parked for the person it was given to"

echo "# …and a rework hand-back, which posts nothing at all, is not feedback either"
KID52='{"id":"kid-52","status":"open","assignee":"","title":"Rework PR#52","notes":"","metadata":{"anchor_bead":"R7","source_review_bead":"rv-52"}}'
store "[$(anchor R7 52 ',"merge_hold":"true","gc.routed_to":"human"'),$KID52]"
printf '%s' "$(prview 52 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_52.json"
echo '[]' > "$GH_DIR/reviews_52.json"
echo '[]' > "$GH_DIR/comments_52.json"
out=$(run)
eq "$(meta_pinned R7 pr_posture)" "review_required@sha-52" "a hand-back leaves the PR with nothing outstanding on it"
eq "$(vpass_id R7)" "<none>" "…so no validation pass opens"
eq "$(meta R7 merge_hold)" "true" "…and the operator's hold stands"
eq "$(meta R7 'gc.routed_to')" "human" "…with the hold it belongs to"

echo "# a validation-pass stamp that drops warns, holds the batch, and does not twin"
# The pass and its anchor_bead stamp are separate writes; a stamp that does not
# record fails closed — the batch is not watermarked, so it retries and the next
# pass adopts the unstamped bead by title rather than minting a twin. The rework
# child is already filed and routed, so the retry costs nothing.
store "[$(anchor Vf 74)]"
printf '%s' "$(prview 74 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_74.json"
echo '[]' > "$GH_DIR/reviews_74.json"
printf '[{"id":8740,"user":{"login":"human1"},"body":"x"}]' > "$GH_DIR/comments_74.json"
out=$(STUB_UPDATE_FAIL="new-3" run)
has "$out" "did not record the batch shape" "the dropped stamp is reported, not swallowed"
eq "$(vpass_id Vf)" "<none>" "…and no stamped validation pass stands on the anchor"
eq "$(meta Vf pr_comment_disposition)" "<absent>" "…the batch is not watermarked until the pass opens, so it retries"
eq "$(meta new-2 'gc.routed_to')" "$FIX" "…while the rework child is already filed and routed"

echo "# a pass whose check_name write half-lands warns, holds the batch, does not watermark"
# The validator selects findings by check_name and defaults a missing one to correctness,
# so a pass carrying anchor_bead but no check_name would rule correctness findings and
# leave the human batch unruled. Reading only anchor_bead back would pass it; the
# read-back checks the lane the validator consumes and skips the watermark.
store "[$(anchor Vk 78)]"
printf '%s' "$(prview 78 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_78.json"
echo '[]' > "$GH_DIR/reviews_78.json"
printf '[{"id":8780,"user":{"login":"human1"},"body":"x"}]' > "$GH_DIR/comments_78.json"
out=$(STUB_DROP_KEYS="new-3:check_name" run)
has "$out" "did not record the batch shape" "the dropped lane is reported, not swallowed"
has "$out" "check_name=<absent>" "…naming the field that did not land"
eq "$(meta Vk pr_comment_disposition)" "<absent>" "…the batch is not watermarked, so it retries"

echo "# a pass whose reviewed_oid write half-lands warns, holds the batch, does not watermark"
# reviewed_oid is the pin mol-validate needs to back the lane, so a pass missing it
# cannot rule the batch. The read-back checks the pin against the live head and
# skips the mark.
store "[$(anchor Vp 79)]"
printf '%s' "$(prview 79 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_79.json"
echo '[]' > "$GH_DIR/reviews_79.json"
printf '[{"id":8790,"user":{"login":"human1"},"body":"x"}]' > "$GH_DIR/comments_79.json"
out=$(STUB_DROP_KEYS="new-3:reviewed_oid" run)
has "$out" "did not record the batch shape" "the dropped head pin is reported, not swallowed"
has "$out" "reviewed_oid=<absent>" "…naming the field that did not land"
eq "$(meta Vp pr_comment_disposition)" "<absent>" "…the batch is not watermarked, so it retries"

echo "# an existing human-lane pass whose reviewed_oid dropped is repaired, not trusted on the probe's word"
# The dedup probe matches a pass on (task_kind=validation, anchor_bead, check_name=human)
# alone, so a prior pass whose reviewed_oid write dropped matches it on the next
# reconcile. Trusting the probe would watermark the batch behind a pass mol-validate
# cannot pin (its back-lane needs reviewed_oid). The shape is re-read for the existing
# pass too: a missing pin is repaired to the live head, and only then does the mark go.
NOPIN_VP='{"id":"vp-82","status":"open","assignee":"","title":"Validate PR#82 feedback (through review 0, comment 8820)","notes":"","metadata":{"task_kind":"validation","anchor_bead":"Vn","check_name":"human"}}'
store "[$(anchor Vn 82),$NOPIN_VP]"
printf '%s' "$(prview 82 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_82.json"
echo '[]' > "$GH_DIR/reviews_82.json"
printf '[{"id":8820,"user":{"login":"human1"},"body":"x"}]' > "$GH_DIR/comments_82.json"
out=$(run)
has "$out" "already carries a human-lane validation pass vp-82" "the existing pass is the dedup target, no twin minted"
eq "$(jq '[.[] | select((.metadata.task_kind // "") == "validation") | select((.metadata.anchor_bead // "") == "Vn")] | length' "$STUB_STORE")" "1" "…and exactly one pass stands on the anchor"
eq "$(meta vp-82 reviewed_oid)" "sha-82" "…its dropped head pin is repaired to the live head before the mark"
has "$(meta Vn pr_comment_disposition)" "rework:" "…and only then does the batch watermark"

echo "# an existing human-lane pass keeps the head it was opened at; a later batch does not re-pin it"
# head_oid is the live PR head, not a per-batch constant. One live human-lane pass rules
# every open human finding on the anchor, so a batch arriving after the head moved rides
# the open pass — but re-pinning it to the new head would move the commit a validator is
# ruling against out from under it. A present reviewed_oid is preserved; only a missing
# one is filled.
OLDPIN_VP='{"id":"vp-83","status":"open","assignee":"","title":"Validate PR#83 feedback (through review 0, comment 8830)","notes":"","metadata":{"task_kind":"validation","anchor_bead":"Vh","check_name":"human","reviewed_oid":"sha-OLD"}}'
store "[$(anchor Vh 83),$OLDPIN_VP]"
printf '%s' "$(prview 83 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_83.json"
echo '[]' > "$GH_DIR/reviews_83.json"
printf '[{"id":8830,"user":{"login":"human1"},"body":"x"}]' > "$GH_DIR/comments_83.json"
out=$(run)
eq "$(meta vp-83 reviewed_oid)" "sha-OLD" "the in-flight pass keeps its head; the batch does not move the validator's pin"
has "$(meta Vh pr_comment_disposition)" "rework:" "…and the batch still watermarks behind the open pass"

echo "# a pass whose task_kind write half-lands is invisible to the validator path, so the shape gate holds it"
# task_kind=validation is the key gate-ensure's open_validation_pass selects a
# pass by; a bead carrying anchor_bead and check_name but no task_kind still
# blocks the anchor by its edge, yet no validator-path selector can see it.
# Reading back only anchor_bead/check_name/reviewed_oid would pass it; the gate
# reads task_kind too and skips the watermark so the batch retries.
store "[$(anchor Vg 84)]"
printf '%s' "$(prview 84 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_84.json"
echo '[]' > "$GH_DIR/reviews_84.json"
printf '[{"id":8840,"user":{"login":"human1"},"body":"x"}]' > "$GH_DIR/comments_84.json"
out=$(STUB_DROP_KEYS="new-3:task_kind" run)
has "$out" "did not record the batch shape" "the dropped task_kind is reported, not swallowed"
has "$out" "task_kind=<absent>" "…naming the field that did not land"
eq "$(meta Vg pr_comment_disposition)" "<absent>" "…the batch is not watermarked, so it retries"

echo "# a same-anchor half-stamped pass (its task_kind dropped) is reclaimed and repaired, not twinned"
# A prior pass created THIS anchor's human pass and had the task_kind half of its
# shaping write drop, so the bead carries anchor_bead and check_name=human but no
# task_kind. The human-lane probe (task_kind==validation) cannot see it and the
# orphan-by-title probe (anchor_bead=="") skips it, so a naive arm would mint a
# twin that double-blocks the anchor. The reclaim finds it by title on this anchor
# and the shape gate restores its task_kind.
HALF_VP='{"id":"half-85","status":"open","assignee":"","title":"Validate PR#85 feedback (through review 0, comment 8850)","notes":"","metadata":{"anchor_bead":"Vz","check_name":"human","reviewed_oid":"sha-85"}}'
store "[$(anchor Vz 85),$HALF_VP]"
printf '%s' "$(prview 85 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_85.json"
echo '[]' > "$GH_DIR/reviews_85.json"
printf '[{"id":8850,"user":{"login":"human1"},"body":"x"}]' > "$GH_DIR/comments_85.json"
out=$(run)
has "$out" "reclaiming half-stamped validation pass half-85" "the half-stamped pass is reclaimed by title on its anchor"
eq "$(vpass_id Vz)" "half-85" "…and repaired into the human-lane pass — no twin minted"
eq "$(meta half-85 task_kind)" "validation" "…its dropped task_kind is restored"
eq "$(jq '[.[] | select(.id | startswith("new-")) | select((.metadata.task_kind // "") == "validation")] | length' "$STUB_STORE")" "0" "no second validation pass is minted"

echo "# a COMMENTED review body with no inline comment is still a human waiting"
store "[$(anchor P3 42)]"
printf '%s' "$(prview 42 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_42.json"
printf '[{"id":7001,"user":{"login":"human1"},"state":"COMMENTED","body":"why this way?","commit_id":"sha-42"}]' \
  > "$GH_DIR/reviews_42.json"
echo '[]' > "$GH_DIR/comments_42.json"
out=$(run)
eq "$(meta_pinned P3 pr_posture)" "commented@sha-42" "a review body with no inline comment still counts"
eq "$(meta P3 pr_review_watermark)" "7001" "the review id space carries it"
eq "$(meta P3 pr_comment_watermark)" "0" "…and the comment id space stays at zero"
FID3=$(jq -r '[ .[] | select((.metadata.task_kind // "") == "finding") | select((.metadata.anchor_bead // "") == "P3") | .id ] | .[0] // "<none>"' "$STUB_STORE")
hasnt "$FID3" "<none>" "a review body with no inline comment becomes a finding too, not only inline comments"
eq "$(meta "$FID3" 'finding.source')" "human:human1" "…sourced to the review's author"

echo "# …an EMPTY-bodied COMMENTED review is not a posture no id can answer"
store "[$(anchor P4 43)]"
printf '%s' "$(prview 43 OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_43.json"
printf '[{"id":7002,"user":{"login":"human1"},"state":"COMMENTED","body":"","commit_id":"sha-43"}]' > "$GH_DIR/reviews_43.json"
echo '[]' > "$GH_DIR/comments_43.json"
out=$(run)
eq "$(meta_pinned P4 pr_posture)" "none@sha-43" "its inline comments are what the comment read already sees"

echo "# the city's own comment is not a human waiting"
store "[$(anchor P2 41)]"
printf '%s' "$(prview 41 OPEN CLEAN MERGEABLE)" | jq -c '.reviewDecision = "APPROVED"' > "$GH_DIR/pr_view_41.json"
printf '[{"id":6002,"user":{"login":"gc-city-bot"},"state":"COMMENTED","body":"replayed verdict\\n\\n<!-- gc:city -->"}]' > "$GH_DIR/reviews_41.json"
printf '[{"id":6001,"user":{"login":"gc-city-bot"},"body":"replayed verdict\\n\\n<!-- gc:city -->"}]' > "$GH_DIR/comments_41.json"
# The replayed verdict sits in a RESOLVED thread. The unengaged backstop counts
# only unresolved threads holding an unmarked comment, so it finds nothing here
# and the posture is the approval this test asserts.
printf '%s\n' '{"reviews":[],"threads":[{"id":"T-41","isResolved":true,"viewerCanResolve":true,"comments":{"nodes":[{"id":"NC-41","databaseId":100,"author":{"login":"gc-city-bot"},"body":"replayed verdict\n\n<!-- gc:city -->","reactionGroups":[]}]}}]}' > "$GH_DIR/threads_41.json"
out=$(run)
eq "$(meta_pinned P2 pr_posture)" "approved@sha-41" "our own replayed verdict is not an outstanding comment"
eq "$(meta P2 pr_comment_watermark)" "<absent>" "…and nothing was watermarked"

echo "# an unanswered comment outranks an approval"
store "[$(anchor P5 49)]"
printf '%s' "$(prview 49 OPEN CLEAN MERGEABLE)" | jq -c '.reviewDecision = "APPROVED"' > "$GH_DIR/pr_view_49.json"
echo '[]' > "$GH_DIR/reviews_49.json"
printf '[{"id":9500,"user":{"login":"human2"},"body":"but what about this?"}]' > "$GH_DIR/comments_49.json"
out=$(run)
eq "$(meta_pinned P5 pr_posture)" "commented@sha-49" "one reviewer's approval does not answer another's question"

echo "# a human CHANGES_REQUESTED is a veto AND a batch to answer"
# The fixture: objections that converged to correctness-green
# untouched, because nothing read the feedback under a standing
# CHANGES_REQUESTED. The veto is the posture; what sits under it routes like
# any other feedback. The review body is empty on purpose — an operator whose
# whole objection is inline leaves it that way.
desc() { jq -r --arg id "$1" '(.[] | select(.id == $id) | .description) // "<absent>"' "$STUB_STORE"; }
store "[$(anchor P6 51)]"
printf '%s' "$(prview 51 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "CHANGES_REQUESTED"' > "$GH_DIR/pr_view_51.json"
printf '[{"id":9600,"user":{"login":"human1"},"state":"CHANGES_REQUESTED","body":"","commit_id":"sha-51","submitted_at":"2026-08-19T00:00:00Z"}]' \
  > "$GH_DIR/reviews_51.json"
printf '[{"id":9601,"user":{"login":"human1"},"body":"WHY IS THIS HERE?","path":"docs/file-structure.md","line":12,"pull_request_review_id":9600}]' > "$GH_DIR/comments_51.json"
: > "$STUB_SESSION_LOG"
out=$(run)
eq "$(meta_pinned P6 pr_posture)" "changes_requested@sha-51" "the veto is still the posture"
has "$out" "routed to rework:new-2" "…and the feedback under it routed to work"
eq "$(meta P6 pr_comment_watermark)" "9601" "the watermark advanced to the routed comment"
eq "$(meta new-2 anchor_bead)" "P6" "the child hangs off the same anchor"
eq "$(meta new-2 source_review)" "9600" "…and names the review it came from"
eq "$(meta new-2 branch)" "polecat/x51" "…resuming the PR's own branch"
has "$(desc new-2)" "WHY IS THIS HERE?" "the child carries the comment verbatim"
has "$(desc new-2)" "docs/file-structure.md:12" "…and where it was left"
hasnt "$(desc new-2)" "## Review bodies" "an empty review body renders no section"
grep -qxF "new-2|blocks|P6" "$STUB_DEPS" && ok "…and the child holds the merge" || bad "blocks edge missing"
FID6=$(jq -r '[ .[] | select((.metadata.task_kind // "") == "finding") | select((.metadata.anchor_bead // "") == "P6") | .id ] | .[0] // "<none>"' "$STUB_STORE")
hasnt "$FID6" "<none>" "an operator's CHANGES_REQUESTED produces a finding — the tk-zina89 gap closed"
eq "$(meta "$FID6" 'finding.source')" "human:human1" "…sourced to the operator who raised it, so it reaches the validator like any finding"
grep -qxF "new-2|blocks|$FID6" "$STUB_DEPS" && bad "the child must not block the still-unvalidated CHANGES_REQUESTED finding at dispatch" || ok "…and the child does not block the unvalidated finding; a must-fix ruling is what hangs the fix unit's edge onto it (the merge is held by the child's anchor edge above)"
has "$(cat "$STUB_SESSION_LOG")" "wake $FIX" "…and the fix pool is woken"

echo "# …the same standing review is not filed twice"
: > "$STUB_SESSION_LOG"
out=$(run)
eq "$(jq '[.[] | select(.id | startswith("new-")) | select((.metadata.task_kind // "") == "rework")] | length' "$STUB_STORE")" "1" "no twin child"
hasnt "$out" "routed to rework" "…nothing re-routes"
eq "$(meta_pinned P6 pr_posture)" "changes_requested@sha-51" "…and the veto stands on its own, answered or not"

echo "# …and a CHANGES_REQUESTED veto opens a validation pass like any other feedback"
# A veto is review the branch has never been answered against, the same as a
# comment batch, so it opens a pass. It does not touch an operator's own hold,
# so a held anchor keeps its hold and the veto goes to the person holding it.
HELDCR=',"merge_hold":"true","gc.routed_to":"human","blocked_reason":"held for the operator to review"'
store "[$(anchor PB 56 "$HELDCR")]"
printf '%s' "$(prview 56 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "CHANGES_REQUESTED"' > "$GH_DIR/pr_view_56.json"
printf '[{"id":9660,"user":{"login":"human1"},"state":"CHANGES_REQUESTED","body":"not what I asked for","commit_id":"sha-56"}]' > "$GH_DIR/reviews_56.json"
echo '[]' > "$GH_DIR/comments_56.json"
out=$(run)
hasnt "$(vpass_id PB)" "<none>" "the veto opens a validation pass"
eq "$(meta PB signoff_rounds_reset)" "<absent>" "…and no signoff_rounds_reset is written"
eq "$(meta PB merge_hold)" "true" "…the operator's hold is left standing"
eq "$(meta PB 'gc.routed_to')" "human" "…with the human route"
eq "$(meta PB pr_comment_disposition)" "visit:new-2" "…so the objection goes to the person holding it (the pass is opened after, as new-3)"

echo "# …a review DISMISSED before it routed is never filed"
# A dismissal moves the review out of COMMENTED and CHANGES_REQUESTED both, so
# it leaves the batch by the same read that would have counted it.
store "[$(anchor P7 52)]"
printf '%s' "$(prview 52 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_52.json"
printf '[{"id":9700,"user":{"login":"human1"},"state":"DISMISSED","body":"never mind"}]' > "$GH_DIR/reviews_52.json"
echo '[]' > "$GH_DIR/comments_52.json"
out=$(run)
eq "$(meta_pinned P7 pr_posture)" "review_required@sha-52" "a dismissed review is not a human waiting"
hasnt "$out" "routed to rework" "…so nothing is filed for it"
eq "$(meta P7 pr_review_watermark)" "<absent>" "…and nothing is watermarked"

echo "# …nor the inline comments that dismissal left behind"
# The comment rows outlive the review that carried them: GitHub still serves
# them under /pulls/N/comments. Counting one without asking what carried it
# re-raises the feedback the dismissal retired, and steps the watermark past it
# so no later pass can notice.
store "[$(anchor PC 57)]"
printf '%s' "$(prview 57 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_57.json"
printf '[{"id":9710,"user":{"login":"human1"},"state":"DISMISSED","body":"never mind"}]' > "$GH_DIR/reviews_57.json"
printf '[{"id":9711,"user":{"login":"human1"},"body":"WHY IS THIS HERE?","path":"docs/file-structure.md","line":12,"pull_request_review_id":9710}]' > "$GH_DIR/comments_57.json"
out=$(run)
eq "$(meta_pinned PC pr_posture)" "review_required@sha-57" "what a dismissal left behind is not a human waiting"
hasnt "$out" "routed to rework" "…so nothing is filed for it"
eq "$(meta PC pr_comment_watermark)" "<absent>" "…and the watermark does not step past it"

echo "# …while a comment no dismissal covers still routes"
# The filter asks what carried each comment, not whether a dismissal exists on
# the PR. A comment standing on its own is feedback nobody retired, and it has
# to keep routing beside one that was.
printf '[{"id":9711,"user":{"login":"human1"},"body":"WHY IS THIS HERE?","path":"docs/file-structure.md","line":12,"pull_request_review_id":9710},{"id":9712,"user":{"login":"human1"},"body":"this one stands alone","path":"docs/state-machine.md","line":3}]' > "$GH_DIR/comments_57.json"
out=$(run)
has "$out" "routed to rework:new-2" "the standalone comment routes"
eq "$(meta PC pr_comment_watermark)" "9712" "the watermark follows the comment that routed"
has "$(desc new-2)" "this one stands alone" "the child carries it"
hasnt "$(desc new-2)" "WHY IS THIS HERE?" "…and not the retired comment beside it"

echo "# …and an APPROVED review retires nothing it carried"
# Only a dismissal retires a comment. An approval is a live review, and an
# inline comment under it is feedback nobody has answered; dropping it would let
# a PR green everywhere else merge over the objection.
store "[$(anchor PD 66)]"
printf '%s' "$(prview 66 OPEN CLEAN MERGEABLE)" | jq -c '.reviewDecision = "APPROVED"' > "$GH_DIR/pr_view_66.json"
printf '[{"id":9720,"user":{"login":"human1"},"state":"APPROVED","body":"","commit_id":"sha-66"}]' > "$GH_DIR/reviews_66.json"
printf '[{"id":9721,"user":{"login":"human1"},"body":"one more thing","path":"docs/state-machine.md","line":7,"pull_request_review_id":9720}]' > "$GH_DIR/comments_66.json"
out=$(run)
eq "$(meta_pinned PD pr_posture)" "commented@sha-66" "an approval does not retire the comment it carried"
has "$out" "routed to rework:new-2" "…so the comment under it routes"
eq "$(meta PD pr_comment_watermark)" "9721" "…and the watermark follows it"
has "$(desc new-2)" "one more thing" "the child carries the comment"

echo "# …a review BODY with no inline comment is carried too"
# An objection stated in the review body alone has nothing on the /files page,
# so a work order that names only that page hands the child an empty read.
store "[$(anchor P8 53)]"
printf '%s' "$(prview 53 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "CHANGES_REQUESTED"' > "$GH_DIR/pr_view_53.json"
printf '[{"id":9800,"user":{"login":"human1"},"state":"CHANGES_REQUESTED","body":"This is still 30 lines of workflow descriptions.","commit_id":"sha-53"}]' > "$GH_DIR/reviews_53.json"
echo '[]' > "$GH_DIR/comments_53.json"
out=$(run)
has "$out" "routed to rework:new-2" "a body-only objection routes"
eq "$(meta P8 pr_review_watermark)" "9800" "the review id space carries it"
eq "$(meta P8 pr_comment_watermark)" "0" "…and the comment id space stays put"
has "$(desc new-2)" "This is still 30 lines of workflow descriptions." "the child carries the review body"
eq "$(meta new-2 source_review)" "9800" "…and names the review"

echo "# …the city's OWN CHANGES_REQUESTED files nothing: that is signoff's loop"
store "[$(anchor P9 54)]"
printf '%s' "$(prview 54 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "CHANGES_REQUESTED"' > "$GH_DIR/pr_view_54.json"
printf '[{"id":9900,"user":{"login":"gc-city-bot"},"state":"CHANGES_REQUESTED","body":"finding\\n\\n<!-- gc:city -->","commit_id":"sha-54"}]' > "$GH_DIR/reviews_54.json"
printf '[{"id":9901,"user":{"login":"gc-city-bot"},"body":"finding\\n\\n<!-- gc:city -->"}]' > "$GH_DIR/comments_54.json"
out=$(run)
eq "$(meta_pinned P9 pr_posture)" "changes_requested@sha-54" "the veto is recorded"
hasnt "$out" "feedback history unreadable" "…off review lists that read cleanly"
hasnt "$out" "routed to rework" "…and this arm files nothing against the city's own verdict"
eq "$(meta P9 pr_comment_watermark)" "<absent>" "…nor watermarks it"

echo "# provenance: an unmarked review under the city's own login after the cutover is feedback"
# The operator runs model reviews (/code-review, codex, gemini) under the city's
# GitHub account. Past the anchor's pr_provenance_since an unmarked review there
# routes like a person's: its body and its inline comments go to a rework child,
# and each becomes a finding sourced to the account that posted it.
CUT=',"pr_provenance_since":"2026-10-07T00:00:00Z"'
store "[$(anchor PV1 156 "$CUT")]"
printf '%s' "$(prview 156 OPEN CLEAN MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_156.json"
printf '[{"id":9700,"user":{"login":"gc-city-bot"},"state":"COMMENTED","body":"Automated code review: two findings below.","commit_id":"sha-156","submitted_at":"2026-10-07T01:00:00Z"}]' > "$GH_DIR/reviews_156.json"
printf '[{"id":9701,"user":{"login":"gc-city-bot"},"body":"Bound the re-read per pass.","path":"assets/scripts/merge.sh","line":12,"pull_request_review_id":9700,"created_at":"2026-10-07T01:00:00Z"}]' > "$GH_DIR/comments_156.json"
out=$(run)
has "$out" "routed to rework:" "the model review routes like a person's"
eq "$(meta PV1 pr_review_watermark)" "9700" "…its body advances the review mark"
eq "$(meta PV1 pr_comment_watermark)" "9701" "…its inline comment advances the comment mark"
eq "$(meta_pinned PV1 pr_posture)" "commented@sha-156" "…and the posture holds the merge as commented"
PV1C=$(jq -r '[ .[] | select((.metadata.task_kind // "") == "rework") | select((.metadata.anchor_bead // "") == "PV1") | .id ] | .[0] // ""' "$STUB_STORE")
has "$(desc "$PV1C")" "Bound the re-read per pass." "the child carries the inline comment verbatim"
# The fixer works in its own rig's checkout, so the helper is named by the
# absolute path pr-facts resolved, never a pack-relative one that names nothing
# there.
has "$(desc "$PV1C")" "reply through $SD/pr-post.sh" "…and tells the fixer to reply through pr-post.sh, by its resolved path"
has "$(meta "$PV1C" rejection_reason)" "posted through $SD/pr-post.sh" "…as its rejection_reason does"
hasnt "$(desc "$PV1C")" "through assets/scripts/pr-post.sh" "…never by a pack-relative path"
eq "$(jq '[ .[] | select((.metadata.task_kind // "") == "finding") | select((.metadata.anchor_bead // "") == "PV1")
           | select((.metadata["finding.source"] // "") == "human:gc-city-bot") ] | length' "$STUB_STORE")" "2" "…and each item is a finding sourced to the account it came from"
eq "$(jq '[ .[] | select(((.metadata.escalation_key // "") | tostring) | startswith("pr-unengaged-threads")) ] | length' "$STUB_STORE")" "0" "…so the unengaged-thread backstop has nothing to file"

echo "# provenance: the mark under any other login claims nothing — a quoting human is feedback"
store "[$(anchor PV2 157 "$CUT")]"
printf '%s' "$(prview 157 OPEN CLEAN MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_157.json"
echo '[]' > "$GH_DIR/reviews_157.json"
echo '[]' > "$GH_DIR/comments_157.json"
printf '[{"id":881001,"user":{"login":"human1"},"body":"> quoting the bot\\n\\n<!-- gc:city -->\\n\\nthis is still wrong","created_at":"2026-10-07T02:00:00Z"}]' > "$GH_DIR/issue_comments_157.json"
out=$(run)
has "$out" "issue 881001" "the human's comment routes though it carries the mark"
eq "$(meta PV2 pr_issue_comment_watermark)" "881001" "…and advances the conversation mark"

echo "# provenance: an unmarked post under our login from BEFORE the cutover is still the city's own"
# The notices a PR already carried when the city began marking stay the city's,
# so they do not all turn into feedback at once.
store "[$(anchor PV3 158 "$CUT")]"
printf '%s' "$(prview 158 OPEN CLEAN MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_158.json"
printf '[{"id":9800,"user":{"login":"gc-city-bot"},"state":"COMMENTED","body":"Signoff verdict: approve","commit_id":"sha-158","submitted_at":"2026-10-05T00:00:00Z"}]' > "$GH_DIR/reviews_158.json"
echo '[]' > "$GH_DIR/comments_158.json"
printf '[{"id":881002,"user":{"login":"gc-city-bot"},"body":"Pre-open signoff (comment-only — not an approval)","created_at":"2026-10-05T00:00:00Z"}]' > "$GH_DIR/issue_comments_158.json"
out=$(run)
hasnt "$out" "routed to rework" "the older unmarked notices route nothing"
eq "$(meta_pinned PV3 pr_posture)" "review_required@sha-158" "…and hold no posture"
eq "$(meta PV3 pr_review_watermark)" "<absent>" "…nor move a mark"

echo "# provenance: the first read of an open PR stamps its cutover, once — drafts included"
store "[$(anchor PV4 159), $(anchor PV6 167)]"
printf '%s' "$(prview 159 OPEN CLEAN MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_159.json"
printf '%s' "$(prview 167 OPEN CLEAN MERGEABLE)" | jq -c '.isDraft = true' > "$GH_DIR/pr_view_167.json"
for n in 159 167; do echo '[]' > "$GH_DIR/reviews_$n.json"; echo '[]' > "$GH_DIR/comments_$n.json"; done
out=$(run_posture)
PV4S=$(meta PV4 pr_provenance_since)
case "$PV4S" in
  [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z) ok "the posture pass stamps a UTC instant on a first read" ;;
  *) bad "the posture pass stamps a UTC instant on a first read" "got '$PV4S'" ;;
esac
case "$(meta PV6 pr_provenance_since)" in
  [0-9][0-9][0-9][0-9]-*Z) ok "…a draft PR is stamped too, before anyone can review it unmarked" ;;
  *) bad "…a draft PR is stamped too, before anyone can review it unmarked" "got '$(meta PV6 pr_provenance_since)'" ;;
esac
# A stamp from an earlier pass, so a rewrite would show as a changed value.
jq -c '[ .[] | if .id == "PV4" then .metadata.pr_provenance_since = "2026-10-07T00:00:00Z" else . end ]' "$STUB_STORE" > "$TMP/pv4.json" \
  && mv "$TMP/pv4.json" "$STUB_STORE"
out=$(run)
eq "$(meta PV4 pr_provenance_since)" "2026-10-07T00:00:00Z" "a recorded instant is never rewritten"

echo "# provenance: a malformed cutover reads every post under our login as the city's own"
store "[$(anchor PV5 163 ',"pr_provenance_since":"last tuesday"')]"
printf '%s' "$(prview 163 OPEN CLEAN MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_163.json"
echo '[]' > "$GH_DIR/reviews_163.json"
echo '[]' > "$GH_DIR/comments_163.json"
printf '[{"id":881003,"user":{"login":"gc-city-bot"},"body":"landed abc123"}]' > "$GH_DIR/issue_comments_163.json"
out=$(run)
has "$out" "is not a UTC instant" "the malformed stamp is named"
hasnt "$out" "feedback history unreadable" "…the lists read cleanly"
hasnt "$out" "routed to rework" "…and the unmarked post under our login routes nothing"
eq "$(meta PV5 pr_provenance_since)" "last tuesday" "…and the stamp is left for a person to read"

echo "# provenance: a review drafted before the cutover and submitted after it is feedback whole"
# An inline comment is drafted inside a pending review and published with it.
# Dated by its own creation it would read as the city's while the review body
# routed as feedback, and the child would carry the summary without the findings.
store "[$(anchor PV7 169 "$CUT")]"
printf '%s' "$(prview 169 OPEN CLEAN MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_169.json"
printf '[{"id":9710,"user":{"login":"gc-city-bot"},"state":"COMMENTED","body":"Automated review: one finding below.","commit_id":"sha-169","submitted_at":"2026-10-07T00:10:00Z"}]' > "$GH_DIR/reviews_169.json"
printf '[{"id":9711,"user":{"login":"gc-city-bot"},"body":"Guard the empty read.","path":"assets/scripts/merge.sh","line":7,"pull_request_review_id":9710,"created_at":"2026-10-06T23:50:00Z"}]' > "$GH_DIR/comments_169.json"
echo '[]' > "$GH_DIR/issue_comments_169.json"
out=$(run)
has "$out" "routed to rework:" "the straddling review routes"
eq "$(meta PV7 pr_review_watermark)" "9710" "…its body advances the review mark"
eq "$(meta PV7 pr_comment_watermark)" "9711" "…and its inline comment, drafted before the cutover, advances the comment mark with it"
PV7C=$(jq -r '[ .[] | select((.metadata.task_kind // "") == "rework") | select((.metadata.anchor_bead // "") == "PV7") | .id ] | .[0] // ""' "$STUB_STORE")
has "$(desc "$PV7C")" "Guard the empty read." "the child carries the inline finding, not only the summary"
eq "$(jq '[ .[] | select(((.metadata.escalation_key // "") | tostring) | startswith("pr-unengaged-threads")) | select((.metadata.anchor_bead // "") == "PV7") ] | length' "$STUB_STORE")" "0" "…so the unengaged-thread backstop has nothing of it to file"

echo "# …an unreadable review list still records the veto, and routes nothing"
store "[$(anchor PA 55)]"
printf '%s' "$(prview 55 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "CHANGES_REQUESTED"' > "$GH_DIR/pr_view_55.json"
printf '[{"id":9950,"user":{"login":"human1"},"state":"CHANGES_REQUESTED","body":"unread","commit_id":"sha-55"}]' > "$GH_DIR/reviews_55.json"
printf '[{"id":9951,"user":{"login":"human1"},"body":"unread"}]' > "$GH_DIR/comments_55.json"
out=$(STUB_GH_LIST_RC=1 run)
eq "$(meta_pinned PA pr_posture)" "changes_requested@sha-55" "reviewDecision alone settles the posture merge.sh reads"
has "$out" "the feedback under it not routed" "…and the pass says the batch is deferred"
hasnt "$out" "routed to rework" "…having routed nothing on a read it could not make"

echo "# a read that cannot tell records NOTHING rather than clear a standing hold"
store "[$(anchor P7 52 ',"pr_posture":"commented@sha-52","pr_comment_watermark":"1"')]"
printf '%s' "$(prview 52 OPEN CLEAN MERGEABLE)" | jq -c '.reviewDecision = "APPROVED"' > "$GH_DIR/pr_view_52.json"
out=$(STUB_SELF_LOGIN="" run)
has "$out" "the acting login is unresolved" "an unresolved login is named"
eq "$(meta P7 pr_posture)" "commented@sha-52" "the standing posture is left holding, never downgraded blind"

echo "# identity mismatch records nothing"
store "[$(anchor I1 30)]"
printf '%s' "$(prview 30 MERGED CLEAN MERGEABLE)" | jq -c '.headRepositoryOwner.login = "stranger" | .isCrossRepository = true' > "$GH_DIR/pr_view_30.json"
out=$(run)
has "$out" "identity did not certify" "the foreign head is refused"
eq "$(meta I1 merge_result)" "pull_request" "…and NOTHING was recorded"

echo "# unreadable enumeration fails loudly"
out=$(STUB_LIST_FAIL=1 run); rc=$?
eq "$rc" 1 "an unreadable enumeration exits non-zero"

fi # part feedback

# These helpers sit outside every part: parts writeback and checks both use
# them, and child() here replaces the rework-child helper above for the rest of
# the file, in every run.
# ---- PR write-back: acknowledge on pickup, reply and resolve on landing -------
# STUB_SELF_LOGIN is gc-city-bot, so "johnzook" is the operator throughout.
# A write-back fixture states the WHOLE PR, not just its review threads. The
# posture arm reads the REST review and comment lists first and would route a
# batch of its own over anything it finds there, replacing the disposition these
# tests are asserting about — and these PR numbers are shared with the dispatch
# tests above, whose fixtures outlive them.
threads() {
  printf '%s' "$2" > "$GH_DIR/threads_$1.json"
  printf '[]' > "$GH_DIR/reviews_$1.json"
  printf '[]' > "$GH_DIR/comments_$1.json"
}
tfile()   { cat "$GH_DIR/threads_$1.json"; }
reacted() { # num node-id [content] -> true/false; EYES unless named
  jq -r --arg id "$2" --arg c "${3:-EYES}" '[ (.reviews[]?, (.threads[]? | .comments.nodes[]?), .issue_comments[]?)
    | select(.id == $id) | (.reactionGroups // [])[]
    | select(.content == $c and .viewerHasReacted) ] | length > 0' "$GH_DIR/threads_$1.json"
}
# A resolved comment trades EYES for THUMBS_UP.
thumbed() { reacted "$1" "$2" THUMBS_UP; }
tresolved() { jq -r --arg t "$2" '[ .threads[]? | select(.id == $t) | .isResolved ] | first' "$GH_DIR/threads_$1.json"; }
treply()    { jq -r --arg t "$2" '[ .threads[]? | select(.id == $t) | .comments.nodes[]?
                | select((.body // "") | contains("<!-- gc-writeback -->")) | .body ] | join(" ")' "$GH_DIR/threads_$1.json"; }
# one operator thread at comment id 100, plus a child bead the disposition names
one_thread() {
  printf '{"reviews":[],"threads":[{"id":"T-%s","isResolved":false,"viewerCanResolve":true,"comments":{"nodes":[{"id":"NC-%s","databaseId":100,"author":{"login":"johnzook"},"body":"%s","reactionGroups":[]}]}}]}' \
    "$1" "$1" "${2:-please fix}"
}
wb_meta() { printf ',"pr_comment_disposition":"%s","pr_comment_watermark":"%s","pr_review_watermark":"0"' "$1" "${2:-100}"; }
wb_batch() { printf ',"pr_comment_batch":"%s"' "$1"; }
wb_rmeta() { printf ',"pr_comment_disposition":"%s","pr_comment_watermark":"0","pr_review_watermark":"%s"' "$1" "$2"; }
# the Conversation-tab variant: dispositioned, with only the issue-comment watermark raised
wb_imeta() { printf ',"pr_comment_disposition":"%s","pr_comment_watermark":"0","pr_review_watermark":"0","pr_issue_comment_watermark":"%s"' "$1" "${2:-50}"; }
child()   { printf '{"id":"%s","status":"%s","assignee":"","notes":"","title":"c","metadata":{}}' "$1" "$2"; }
# an artifact fix unit: closed by demo-deliver on attach, carrying the attached
# comment's URL as artifact_url (what the write-back cites in place of a commit).
child_artifact() { printf '{"id":"%s","status":"%s","assignee":"","notes":"","title":"c","metadata":{"artifact_url":"%s"}}' "$1" "$2" "$3"; }
gh_since() { tail -n +"$1" "$STUB_GH_LOG"; }
# The provenance cutover the unengaged-thread sections stamp on their anchors.
# Those sections sit in the writeback and checks parts, and each part runs alone,
# so the stamp is defined here, outside both.
UTCUT=',"pr_provenance_since":"2026-10-07T00:00:00Z"'
# advance one bead between passes, the way a later pass of the city would
bmut() { # <id> <jq-expression over that bead>
  local t="$TMP/bmut.json"
  jq -c --arg id "$1" "[ .[] | if .id == \$id then $2 else . end ]" "$STUB_STORE" > "$t" && mv "$t" "$STUB_STORE"
}

# ==== part writeback: acknowledge, reply and resolve on the PR ====
if part writeback; then

echo "# a comment that produced a rework bead is acknowledged in the same pass"
store "[$(anchor W1 40 "$(wb_meta rework:K1)"), $(child K1 open)]"
printf '%s' "$(prview 40 OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_40.json"
threads 40 "$(one_thread 40)"
out=$(run)
eq "$(reacted 40 NC-40)" "true" "the routed comment got its EYES reaction"
has "$out" "1 comments acknowledged" "the pass reports the acknowledgement"
eq "$(treply 40 T-40)" "" "no reply while the rework bead is still open"
eq "$(tresolved 40 T-40)" "false" "…and the thread is NOT resolved on filing"

echo "# a routed top-level (Conversation) comment gets the same EYES acknowledgement"
# Issue comments are their own id space, watermarked by pr_issue_comment_watermark;
# the write-back reads that mark, not the inline-comment one. They carry no thread,
# so a routed one earns the pickup reaction and nothing else.
store "[$(anchor WI 88 "$(wb_imeta rework:KI)"), $(child KI open)]"
printf '%s' "$(prview 88 OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_88.json"
threads 88 '{"reviews":[],"threads":[],"issue_comments":[
  {"id":"IC-88","databaseId":50,"author":{"login":"johnzook"},"reactionGroups":[]},
  {"id":"IC-88-hi","databaseId":80,"author":{"login":"johnzook"},"reactionGroups":[]},
  {"id":"IC-88-self","databaseId":40,"author":{"login":"gc-city-bot"},"body":"landed\n\n<!-- gc:city -->","reactionGroups":[]}]}'
out=$(run)
eq "$(reacted 88 IC-88)" "true" "the routed Conversation comment got its EYES reaction"
eq "$(reacted 88 IC-88-hi)" "false" "a Conversation comment above the mark earns none"
eq "$(reacted 88 IC-88-self)" "false" "our own Conversation comment earns none"
has "$out" "1 comments acknowledged" "the pass reports the one acknowledgement"

echo "# …and running it again writes no second reaction (idempotent off viewerHasReacted)"
mark=$(( $(wc -l < "$STUB_GH_LOG") + 1 ))
out=$(run)
hasnt "$(gh_since "$mark")" "REACT" "no second reaction to the Conversation comment"

echo "# a landed fix replies once naming the commit, then resolves the thread"
store "[$(anchor W2 41 "$(wb_meta rework:K2)"), $(child K2 closed)]"
printf '%s' "$(prview 41 OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_41.json"
threads 41 "$(one_thread 41)"
out=$(run)
has "$(treply 41 T-41)" "✅ Resolved in sha-41" "the reply leads with the check mark and names the landing commit"
has "$(treply 41 T-41)" "K2" "…and the bead that carried the work"
has "$(treply 41 T-41)" "<!-- gc-writeback-mark:resolved -->" "…carrying the resolved mark line a later pass reads"
has "$(treply 41 T-41)" "<!-- gc:city -->" "…carrying the city's mark, posted through pr-post.sh"
eq "$(tresolved 41 T-41)" "true" "the thread is resolved behind the reply"
eq "$(thumbed 41 NC-41)" "true" "the resolved comment carries THUMBS_UP"
eq "$(reacted 41 NC-41)" "false" "…in place of its pickup EYES, so it no longer reads as merely looked at"
has "$out" "1 threads replied, 1 threads resolved" "the pass reports both writes"
has "$out" "1 comments marked resolved" "…and the reaction it traded"

echo "# running the same pass twice writes nothing the second time"
mark=$(( $(wc -l < "$STUB_GH_LOG") + 1 ))
out=$(run)
hasnt "$(gh_since "$mark")" "REACT" "no second reaction"
hasnt "$(gh_since "$mark")" "REPLY" "no second reply"
hasnt "$(gh_since "$mark")" "RESOLVE" "no second resolve"
has "$out" "0 comments acknowledged, 0 threads replied, 0 threads resolved" "the repeat pass reports no writes"
eq "$(jq -r '[ .threads[].comments.nodes[] ] | length' "$GH_DIR/threads_41.json")" "2" "the thread still carries exactly one reply"

echo "# an artifact fix unit cites the delivered artifact, not a commit, then resolves"
# demo-deliver closed this fix unit on attach and recorded the attached comment's
# URL as artifact_url. The write-back cites that URL and never a head commit the
# artifact did not make, and still resolves the thread behind the reply.
store "[$(anchor WART 47 "$(wb_meta rework:KART)"), $(child_artifact KART closed https://github.com/zook/gc-toolkit/pull/47#issuecomment-900)]"
printf '%s' "$(prview 47 OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_47.json"
threads 47 "$(one_thread 47)"
out=$(run)
eq "$(thumbed 47 NC-47)" "true" "the comment is marked resolved"
has "$(treply 47 T-47)" "issuecomment-900" "the reply cites the delivered artifact's URL"
hasnt "$(treply 47 T-47)" "Resolved in sha-47" "…and never claims a commit the artifact did not make"
has "$(treply 47 T-47)" "KART" "the reply names the fix unit that carried the work"
eq "$(tresolved 47 T-47)" "true" "the thread is resolved behind the artifact reply"
has "$out" "1 threads replied, 1 threads resolved" "the pass reports both writes"

echo "# a comment nothing acted on is never touched"
store "[$(anchor W3 42)]"
printf '%s' "$(prview 42 OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_42.json"
threads 42 "$(one_thread 42)"
mark=$(( $(wc -l < "$STUB_GH_LOG") + 1 ))
out=$(run)
eq "$(reacted 42 NC-42)" "false" "no disposition means no reaction"
hasnt "$(gh_since "$mark")" "graphql" "…and the threads are not even read"

echo "# a comment ABOVE the watermark was never routed and earns nothing"
store "[$(anchor W4 43 "$(wb_meta rework:K4)"), $(child K4 closed)]"
printf '%s' "$(prview 43 OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_43.json"
threads 43 "$(printf '%s' "$(one_thread 43)" | jq -c '.threads[0].comments.nodes[0].databaseId = 999')"
out=$(run)
eq "$(reacted 43 NC-43)" "false" "an unrouted comment gets no reaction"
eq "$(tresolved 43 T-43)" "false" "…and its thread is not resolved"

echo "# a thread also holding a comment above the mark is not resolved behind its landed batch"
# The older batch landed and would answer the thread on its own. Both beads are
# closed, so what holds the thread is the newer comment: no batch covers it, so
# nothing has addressed it, and a resolve here would close the thread before it
# is answered and put it past every later pass.
store "[$(anchor WQ 73 "$(wb_meta rework:KQ1)"), $(child KQ1 closed), $(child KQ2 closed)]"
printf '%s' "$(prview 73 OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_73.json"
threads 73 "$(printf '%s' "$(one_thread 73)" | jq -c '.threads[0].comments.nodes += [
  {"id":"NC-73b","databaseId":200,"author":{"login":"johnzook"},"body":"and this","reactionGroups":[]}]')"
out=$(run)
eq "$(reacted 73 NC-73)" "true" "the routed comment still earns its acknowledgement"
eq "$(reacted 73 NC-73b)" "false" "the comment above the mark earns none"
eq "$(treply 73 T-73)" "" "the landed batch never answers a thread with a request outstanding"
eq "$(tresolved 73 T-73)" "false" "…and the thread is left open for it"
eq "$(meta WQ pr_comment_batch)" "rework:KQ1|0|100" "the batch owing that thread is kept"

echo "# …and the pass that routes and lands it answers the thread for both"
bmut WQ '.metadata += {"pr_comment_disposition":"rework:KQ2","pr_comment_watermark":"200"}'
mark=$(( $(wc -l < "$STUB_GH_LOG") + 1 ))
out=$(run)
eq "$(thumbed 73 NC-73b)" "true" "the newly routed comment is answered and marked resolved"
has "$(treply 73 T-73)" "KQ1" "the reply names the first batch's bead"
has "$(treply 73 T-73)" "KQ2" "…and the second's"
eq "$(tresolved 73 T-73)" "true" "…and the thread is resolved behind it"
eq "$(gh_since "$mark" | grep -c REPLY)" "1" "the thread still gets exactly one reply"

echo "# an operator reply after ours leaves the thread open"
store "[$(anchor W5 44 "$(wb_meta rework:K5)"), $(child K5 closed)]"
printf '%s' "$(prview 44 OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_44.json"
threads 44 "$(printf '%s' "$(one_thread 44)" | jq -c '
  .threads[0].comments.nodes += [
    {"id":"NC-44b","databaseId":0,"author":{"login":"gc-city-bot"},"body":"Addressed in sha-44 (K5).\n<!-- gc-writeback -->","reactionGroups":[]},
    {"id":"NC-44c","databaseId":101,"author":{"login":"johnzook"},"body":"not quite","reactionGroups":[]}]')"
mark=$(( $(wc -l < "$STUB_GH_LOG") + 1 ))
out=$(run)
has "$out" "has a reply after ours; left unresolved" "the live conversation is reported"
eq "$(tresolved 44 T-44)" "false" "…and the thread stays open"
hasnt "$(gh_since "$mark")" "REPLY" "no second reply is posted into it"

# A thread longer than one GraphQL page. The stub cuts its reads at 100 the way
# the API does, so everything past that is visible only to a caller that pages.
long_thread() { # <num> <trailing comment objects, jq array>
  jq -cn --arg n "$1" --argjson tail "$2" '{reviews: [], threads: [{
    id: ("T-" + $n), isResolved: false, viewerCanResolve: true,
    comments: {nodes: ([ range(1;100)
      | {id: ("NC-" + $n + "-" + tostring), databaseId: ., author: {login: "johnzook"},
         body: "please fix", reactionGroups: [{content: "EYES", viewerHasReacted: true}]} ] + $tail)}}]}'
}

echo "# a thread longer than one page is read to its end before it is resolved"
# The first page ends on the city's own reply, so a caller that stops there sees
# a finished conversation. The operator answered on the next page.
store "[$(anchor WN 70 "$(wb_meta rework:KN 100)"), $(child KN closed)]"
printf '%s' "$(prview 70 OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_70.json"
threads 70 "$(long_thread 70 '[
  {"id":"NC-70-mine","databaseId":0,"author":{"login":"gc-city-bot"},
   "body":"Addressed in sha-70 (KN).\n<!-- gc-writeback -->","reactionGroups":[]},
  {"id":"NC-70-late","databaseId":101,"author":{"login":"johnzook"},
   "body":"not quite","reactionGroups":[]}]')"
mark=$(( $(wc -l < "$STUB_GH_LOG") + 1 ))
out=$(run)
has "$out" "has a reply after ours; left unresolved" "the answer past the page boundary is seen"
eq "$(tresolved 70 T-70)" "false" "…and the thread is NOT resolved over it"
hasnt "$(gh_since "$mark")" "REPLY" "…nor answered a second time"

echo "# a routed comment past the first page still gets its acknowledgement"
store "[$(anchor WO 71 "$(wb_meta rework:KO 101)"), $(child KO open)]"
printf '%s' "$(prview 71 OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_71.json"
threads 71 "$(long_thread 71 '[
  {"id":"NC-71-100","databaseId":100,"author":{"login":"johnzook"},
   "body":"please fix","reactionGroups":[{"content":"EYES","viewerHasReacted":true}]},
  {"id":"NC-71-past","databaseId":101,"author":{"login":"johnzook"},
   "body":"one more","reactionGroups":[]}]')"
out=$(run)
eq "$(reacted 71 NC-71-past)" "true" "the comment on the second page is acknowledged"
has "$out" "1 comments acknowledged" "…and it was the only write the pass owed"

echo "# a thread that cannot be read to its end writes NOTHING"
store "[$(anchor WP 72 "$(wb_meta rework:KP 101)"), $(child KP closed)]"
printf '%s' "$(prview 72 OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_72.json"
threads 72 "$(long_thread 72 '[
  {"id":"NC-72-100","databaseId":100,"author":{"login":"johnzook"},
   "body":"please fix","reactionGroups":[{"content":"EYES","viewerHasReacted":true}]},
  {"id":"NC-72-past","databaseId":101,"author":{"login":"johnzook"},
   "body":"one more","reactionGroups":[]}]')"
mark=$(( $(wc -l < "$STUB_GH_LOG") + 1 ))
out=$(STUB_GQL_THREAD_FAIL=1 run)
has "$out" "could not be read to its end" "the half-read thread is reported"
hasnt "$(gh_since "$mark")" "REACT" "…and nothing is acknowledged over it"
eq "$(tresolved 72 T-72)" "false" "…nor is it resolved"
out=$(run)
eq "$(thumbed 72 NC-72-past)" "true" "the pass that CAN read it does the work the refusal deferred"
eq "$(tresolved 72 T-72)" "true" "…and resolves the thread behind it"

echo "# a comment routed to an open visit is marked awaiting a person, and its thread left open"
# The visit is a person's to answer, so the city never claims it resolved while
# the visit is open. The question mark tells the operator which comments wait on
# them, as against the ones a rework is fixing.
store "[$(anchor W6 45 "$(wb_meta visit:V6)"), $(child V6 open)]"
printf '%s' "$(prview 45 OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_45.json"
threads 45 "$(one_thread 45)"
out=$(run)
eq "$(reacted 45 NC-45)" "true" "the comment keeps its pickup EYES"
has "$(treply 45 T-45)" "❓ Awaiting a person — visit V6." "its thread gets the question-mark answer naming the visit"
has "$(treply 45 T-45)" "<!-- gc-writeback-mark:awaiting:V6 -->" "…carrying the awaiting mark line"
eq "$(tresolved 45 T-45)" "false" "…and the thread stays open: the person still owes the ruling"
eq "$(thumbed 45 NC-45)" "false" "…and the comment is not marked resolved"
mark=$(( $(wc -l < "$STUB_GH_LOG") + 1 ))
out=$(run)
hasnt "$(gh_since "$mark")" "REPLY" "a second pass posts the awaiting answer nothing more"
eq "$(meta W6 pr_comment_batch)" "visit:V6|0|100" "…and the visit's batch is kept while it waits"

echo "# …once the person closes the visit, the comment is resolved"
bmut V6 '.status = "closed" | .metadata += {"gc.outcome":"done"}'
mark=$(( $(wc -l < "$STUB_GH_LOG") + 1 ))
out=$(run)
has "$(treply 45 T-45)" "✅ Resolved: visit V6 closed (done)." "the check-mark answer names the closed visit and its outcome"
eq "$(tresolved 45 T-45)" "true" "…the thread is resolved behind it"
eq "$(thumbed 45 NC-45),$(reacted 45 NC-45)" "true,false" "…and the comment trades EYES for THUMBS_UP"
eq "$(gh_since "$mark" | grep -c '^REPLY')" "1" "one answer, the awaiting one left as it was"
mark=$(( $(wc -l < "$STUB_GH_LOG") + 1 ))
out=$(run)
hasnt "$(gh_since "$mark")" "REPLY" "a later pass writes nothing more into the thread"
hasnt "$(gh_since "$mark")" "REACT" "…and no reaction"

# ---- the peer model: a declined human objection is answered, never silenced ----
# The validator may overrule a human on the merits (finding declined), but it
# owes them the reason on their PR: it stamps the answer (finding.reply) and the
# row it answers (finding.comment_id), and the write-back posts that answer into
# the thread and resolves it. A closed declined human finding carrying both.
dfind() { # id anchor comment_id [reply]
  printf '{"id":"%s","status":"closed","assignee":"","notes":"declined: not an objection","title":"finding[human]: x","metadata":{"task_kind":"finding","anchor_bead":"%s","finding.lane":"human","finding.disposition":"declined","finding.source":"human:johnzook","finding.comment_id":"%s"%s}}' \
    "$1" "$2" "$3" "${4:+,\"finding.reply\":\"$4\"}"
}

echo "# a declined human objection is answered on its thread and the thread resolved"
store "[$(anchor WD1 47 "$(wb_meta visit:VD1)"), $(dfind DF1 WD1 100 'The diff already asserts X in helper; no change needed.')]"
printf '%s' "$(prview 47 OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_47.json"
threads 47 "$(one_thread 47)"
out=$(run)
has "$(treply 47 T-47)" "no change needed" "the validator's decline reason is posted into the raiser's thread"
has "$(treply 47 T-47)" "<!-- gc-writeback -->" "…carrying the write-back marker"
eq "$(tresolved 47 T-47)" "true" "…and the answered thread is resolved, so it no longer holds the merge"
eq "$(meta DF1 finding.reply_posted)" "1" "…and the finding is marked answered"
echo "# …and a second pass answers the same thread nothing"
mark=$(( $(wc -l < "$STUB_GH_LOG") + 1 ))
out=$(run)
hasnt "$(gh_since "$mark")" "addPullRequestReviewThreadReply" "the answered decline is never replied to twice"

echo "# the no-objection carve-out declines silently — no owed reply, no thread write"
# A comment that raises no objection (a question the diff answers, praise) is
# declined like a machine finding, with no --reply, so finding.reply is unset and
# the write-back owes nothing: the thread is neither replied to nor resolved.
store "[$(anchor WD3 48 "$(wb_meta visit:VD3)"), $(dfind DF3 WD3 100)]"
printf '%s' "$(prview 48 OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_48.json"
threads 48 "$(one_thread 48)"
out=$(run)
eq "$(treply 48 T-48)" "" "a no-objection decline owes no reply, so none is posted"
eq "$(tresolved 48 T-48)" "false" "…and the thread is left untouched"
eq "$(meta DF3 finding.reply_posted)" "<absent>" "…and the finding is not marked answered"

# ---- a deferred or needs-you human finding owes its raiser an answer too -------
# The write-back answers every human ruling that owes a reply, not only declines:
# a deferred finding posts its follow-up id and resolves the thread (the deferral
# is settled on this PR), a needs-you finding posts its visit id and leaves the
# thread UNRESOLVED (the operator still owes a ruling). A finding carrying the
# disposition, its comment_id, and the owed reply.
xfind() { # id anchor comment_id disposition status reply
  printf '{"id":"%s","status":"%s","assignee":"","notes":"","title":"finding[human]: x","metadata":{"task_kind":"finding","anchor_bead":"%s","finding.lane":"human","finding.disposition":"%s","finding.source":"human:johnzook","finding.comment_id":"%s","finding.reply":"%s"}}' \
    "$1" "$5" "$2" "$4" "$3" "$6"
}

echo "# a deferred human objection posts its follow-up id into the thread and resolves it"
store "[$(anchor WDF1 51 "$(wb_meta visit:VDF1)"), $(xfind DFF1 WDF1 100 deferred closed 'Deferred — tracked as follow-up tk-fup1. It will be picked up after this merges.')]"
printf '%s' "$(prview 51 OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_51.json"
threads 51 "$(one_thread 51)"
out=$(run)
has "$(treply 51 T-51)" "tracked as follow-up tk-fup1" "the deferred finding's follow-up id is posted into the raiser's thread"
has "$(treply 51 T-51)" "<!-- gc-writeback -->" "…carrying the write-back marker"
eq "$(tresolved 51 T-51)" "true" "…and the thread is resolved: a deferral is settled on this PR"
eq "$(meta DFF1 finding.reply_posted)" "1" "…and the finding is marked answered"

echo "# a needs-you objection posts its visit id into the thread but leaves it UNRESOLVED"
store "[$(anchor WNU1 52 "$(wb_meta visit:VNU1)"), $(xfind NUF1 WNU1 100 needs-you open 'This comment needs your decision — opened visit tk-vis1. The review stays changes-requested until you rule it.')]"
printf '%s' "$(prview 52 OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_52.json"
threads 52 "$(one_thread 52)"
out=$(run)
has "$(treply 52 T-52)" "opened visit tk-vis1" "the needs-you finding's visit id is posted into the raiser's thread"
eq "$(tresolved 52 T-52)" "false" "…but the thread is NOT resolved: the operator still owes a ruling"
eq "$(meta NUF1 finding.reply_posted)" "1" "…and the finding is marked answered so the reply is not doubled"

echo "# a re-raise re-blocks: a re-review after a decline re-opens the human validation pass"
# Declining closes the finding, so a still-standing objection re-adopts as a
# FRESH finding on re-review (find_open_by_key reads open findings only), and
# pr-facts re-opens the human validation pass whose blocks edge re-holds the
# anchor. The prior decline forecloses nothing.
store "[$(anchor WR 49 ',"pr_comment_watermark":"100"'), $(dfind DFR WR 100 'declined last round')]"
printf '%s' "$(prview 49 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_49.json"
echo '[]' > "$GH_DIR/reviews_49.json"
printf '[{"id":200,"user":{"login":"johnzook"},"body":"i still think this is wrong"}]' > "$GH_DIR/comments_49.json"
out=$(run)
VPR=$(vpass_id WR)
hasnt "$VPR" "<none>" "the re-review re-opens a human validation pass on the anchor"
grep -qxF "$VPR|blocks|WR" "$STUB_DEPS" && ok "…whose blocks edge re-holds the anchor" || bad "re-opened validation pass does not block the anchor"
FRESHR=$(jq -r '[ .[] | select((.metadata.task_kind // "") == "finding") | select((.metadata.anchor_bead // "") == "WR") | select((.status // "open") != "closed") | .id ] | .[0] // "<none>"' "$STUB_STORE")
hasnt "$FRESHR" "<none>" "…and a fresh OPEN finding is filed, the closed decline not re-adopted in its place"
eq "$(bstatus DFR)" "closed" "…while the prior declined finding stays closed"

echo "# a later batch answers its own comments and never the ones before them"
# The watermark is cumulative and the disposition is overwritten per batch, so
# an earlier batch's unresolved thread still sits below the mark. It keeps the
# reaction it earned, and it must never be told a later commit addressed it.
store "[$(anchor WF 52 "$(wb_meta visit:VF)"), $(child VF open), $(child KF closed)]"
printf '%s' "$(prview 52 OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_52.json"
threads 52 "$(one_thread 52)"
out=$(run)
eq "$(meta WF pr_comment_batch)" "visit:VF|0|100" "the first batch is bounded by the mark alone"
eq "$(tresolved 52 T-52)" "false" "the open visit's thread is left for the human"
bmut WF '.metadata += {"pr_comment_disposition":"rework:KF","pr_comment_watermark":"200"}'
threads 52 "$(tfile 52 | jq -c '.threads += [{"id":"T-52b","isResolved":false,"viewerCanResolve":true,
  "comments":{"nodes":[{"id":"NC-52b","databaseId":200,"author":{"login":"johnzook"},"body":"and this","reactionGroups":[]}]}}]')"
mark=$(( $(wc -l < "$STUB_GH_LOG") + 1 ))
out=$(run)
eq "$(meta WF pr_comment_batch)" "visit:VF|0|100;rework:KF|100|200" \
  "the new disposition inherits the old mark as its floor, beside the open visit's batch it still owes"
eq "$(thumbed 52 NC-52b)" "true" "the new comment is answered and marked resolved"
has "$(treply 52 T-52b)" "✅ Resolved in sha-52" "its thread gets the reply"
eq "$(tresolved 52 T-52b)" "true" "…and is resolved behind it"
hasnt "$(treply 52 T-52)" "Resolved" "the earlier batch's thread is never answered by this one"
eq "$(tresolved 52 T-52)" "false" "…and is never resolved by it"
eq "$(gh_since "$mark" | grep -c RESOLVE)" "1" "exactly one thread was resolved"

echo "# an earlier batch is answered by its own bead, after a later one moved the mark"
# The disposition holds one batch at a time, so what an unanswered batch covered
# has to outlive it: a comment routed under KJ1 is owed its reply whenever KJ1
# lands, and KJ2 taking the disposition first must not swallow it.
store "[$(anchor WJ 56 "$(wb_meta rework:KJ1)"), $(child KJ1 open), $(child KJ2 open)]"
printf '%s' "$(prview 56 OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_56.json"
threads 56 "$(one_thread 56)"
out=$(run)
eq "$(reacted 56 NC-56)" "true" "the first batch's comment is acknowledged"
eq "$(treply 56 T-56)" "" "…and nothing is answered while its bead is open"
bmut WJ '.metadata += {"pr_comment_disposition":"rework:KJ2","pr_comment_watermark":"200"}'
threads 56 "$(tfile 56 | jq -c '.threads += [{"id":"T-56b","isResolved":false,"viewerCanResolve":true,
  "comments":{"nodes":[{"id":"NC-56b","databaseId":200,"author":{"login":"johnzook"},"body":"and this","reactionGroups":[]}]}}]')"
out=$(run)
eq "$(reacted 56 NC-56b)" "true" "the second batch's comment is acknowledged"
eq "$(treply 56 T-56)" "" "the first batch is still unanswered, its bead still open"
bmut KJ1 '.status = "closed"'
out=$(run)
has "$(treply 56 T-56)" "KJ1" "the earlier batch's thread is answered by ITS bead once that lands"
eq "$(tresolved 56 T-56)" "true" "…and resolved behind that reply"
eq "$(treply 56 T-56b)" "" "the later batch's thread waits for its own bead"
bmut KJ2 '.status = "closed"'
mark=$(( $(wc -l < "$STUB_GH_LOG") + 1 ))
out=$(run)
has "$(treply 56 T-56b)" "KJ2" "the later batch's thread is answered by its own bead"
eq "$(tresolved 56 T-56b)" "true" "…and resolved behind it"
eq "$(gh_since "$mark" | grep -c REPLY)" "1" "the answered batch is never replied to twice"
eq "$(meta WJ pr_comment_batch)" "rework:KJ2|100|200" \
  "the earlier batch, its comment answered and marked, is retired from the inline ledger"

echo "# a thread two batches touched waits for both, and names both"
# A landed later batch never answers over an earlier one still unbuilt: the
# thread still carries a request nothing has addressed.
store "[$(anchor WM 59 "$(wb_meta rework:KM1)"), $(child KM1 open), $(child KM2 open)]"
printf '%s' "$(prview 59 OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_59.json"
threads 59 "$(one_thread 59)"
out=$(run)
bmut WM '.metadata += {"pr_comment_disposition":"rework:KM2","pr_comment_watermark":"200"}'
threads 59 "$(tfile 59 | jq -c '.threads[0].comments.nodes += [
  {"id":"NC-59b","databaseId":200,"author":{"login":"johnzook"},"body":"and this","reactionGroups":[]}]')"
out=$(run)
bmut KM2 '.status = "closed"'
out=$(run)
eq "$(treply 59 T-59)" "" "the later batch never answers over the earlier one still open"
eq "$(tresolved 59 T-59)" "false" "…and never resolves the thread under it"
bmut KM1 '.status = "closed"'
mark=$(( $(wc -l < "$STUB_GH_LOG") + 1 ))
out=$(run)
has "$(treply 59 T-59)" "KM1" "the reply names the earlier batch's bead"
has "$(treply 59 T-59)" "KM2" "…and the later one"
eq "$(tresolved 59 T-59)" "true" "…and the thread is resolved behind it"
eq "$(gh_since "$mark" | grep -c REPLY)" "1" "the thread still gets exactly one reply"

echo "# a thread two MIXED-form batches touched names each by its own landing form"
# One batch's fix unit lands a commit; the other's lands an artifact (a demo
# closed on attach, carrying artifact_url). The single reply must cite the commit
# for the commit unit and the delivered URL for the artifact unit — never a commit
# the demo never made, nor a demo the commit never was. Collapsing both to the
# last record's form (the pre-fix bug) would claim one for the other.
store "[$(anchor WX 60 "$(wb_meta rework:KC1)"), $(child KC1 open), $(child KA2 open)]"
printf '%s' "$(prview 60 OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_60.json"
threads 60 "$(one_thread 60)"
out=$(run)
bmut WX '.metadata += {"pr_comment_disposition":"rework:KA2","pr_comment_watermark":"200"}'
threads 60 "$(tfile 60 | jq -c '.threads[0].comments.nodes += [
  {"id":"NC-60b","databaseId":200,"author":{"login":"johnzook"},"body":"and this","reactionGroups":[]}]')"
out=$(run)
bmut KC1 '.status = "closed"'
out=$(run)
eq "$(treply 60 T-60)" "" "the thread waits while the artifact unit is still open"
bmut KA2 '.status = "closed" | .metadata += {"artifact_url":"https://github.com/zook/gc-toolkit/pull/60#issuecomment-600"}'
mark=$(( $(wc -l < "$STUB_GH_LOG") + 1 ))
out=$(run)
has "$(treply 60 T-60)" "✅ Resolved in sha-60 on this PR (KC1)" "the commit unit is cited by its landing commit"
has "$(treply 60 T-60)" "issuecomment-600 (KA2)" "the artifact unit is cited by its delivered URL, not a commit"
eq "$(tresolved 60 T-60)" "true" "the thread is resolved behind the one mixed-form reply"
eq "$(gh_since "$mark" | grep -c REPLY)" "1" "the thread still gets exactly one reply"

echo "# a thread a visit batch and a rework batch both touched waits for the person too"
# The first comment was routed to a human and the second filed a rework child.
# The landed rework answers its own comment, but the thread still holds one a
# person owes a ruling on, so it is answered only once the visit closes, by one
# reply naming both.
store "[$(anchor WL 58 "$(wb_meta visit:VL)"), $(child VL open), $(child KL closed)]"
printf '%s' "$(prview 58 OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_58.json"
threads 58 "$(one_thread 58)"
out=$(run)
has "$(treply 58 T-58)" "❓ Awaiting a person — visit VL." "the visit's comment is marked awaiting a person"
bmut WL '.metadata += {"pr_comment_disposition":"rework:KL","pr_comment_watermark":"200"}'
threads 58 "$(tfile 58 | jq -c '.threads[0].comments.nodes += [
  {"id":"NC-58b","databaseId":200,"author":{"login":"johnzook"},"body":"and this","reactionGroups":[]}]')"
out=$(run)
hasnt "$(treply 58 T-58)" "Resolved" "the landed rework never answers over a comment still awaiting a person"
eq "$(tresolved 58 T-58)" "false" "…and never resolves the thread under it"
bmut VL '.status = "closed"'
out=$(run)
has "$(treply 58 T-58)" "Resolved in sha-58 on this PR (KL)." "once the visit closes, the reply names the rework"
has "$(treply 58 T-58)" "Resolved: visit VL closed." "…and the closed visit"
eq "$(tresolved 58 T-58)" "true" "…and the thread is resolved behind it"
eq "$(thumbed 58 NC-58),$(thumbed 58 NC-58b)" "true,true" "…with both comments marked resolved"

echo "# a batch history it cannot parse acknowledges and answers nothing"
store "[$(anchor WK 57 "$(wb_meta rework:KK)$(wb_batch 'rework:KK|x|200')"), $(child KK closed)]"
printf '%s' "$(prview 57 OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_57.json"
threads 57 "$(one_thread 57)"
out=$(run)
has "$out" "comment batch history is unreadable" "the unparsable history is reported"
eq "$(reacted 57 NC-57)" "true" "the acknowledgement still lands"
eq "$(treply 57 T-57)" "" "…but nothing is answered"
eq "$(tresolved 57 T-57)" "false" "…and nothing is resolved"
eq "$(meta WK pr_comment_batch)" "rework:KK|x|200" "…and the record it could not read is left as it found it"

echo "# a batch range that did not record acknowledges and answers nothing"
store "[$(anchor WG 53 "$(wb_meta rework:KG)"), $(child KG closed)]"
printf '%s' "$(prview 53 OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_53.json"
threads 53 "$(one_thread 53)"
out=$(STUB_DROP_KEYS="WG:pr_comment_batch" run)
has "$out" "comment batch range did not record" "the unrecorded range is reported"
eq "$(reacted 53 NC-53)" "true" "the acknowledgement still lands"
eq "$(treply 53 T-53)" "" "…but nothing is answered"
eq "$(tresolved 53 T-53)" "false" "…and nothing is resolved"

echo "# a thread we replied to is still resolved once the batch has moved past it"
store "[$(anchor WH 54 "$(wb_meta rework:KH 200)$(wb_batch 'rework:KH|150|200')"), $(child KH closed)]"
printf '%s' "$(prview 54 OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_54.json"
threads 54 "$(printf '%s' "$(one_thread 54)" | jq -c '
  .threads[0].comments.nodes += [
    {"id":"NC-54b","databaseId":0,"author":{"login":"gc-city-bot"},"body":"Addressed in sha-54 (KH).\n<!-- gc-writeback -->","reactionGroups":[]}]')"
mark=$(( $(wc -l < "$STUB_GH_LOG") + 1 ))
out=$(run)
eq "$(tresolved 54 T-54)" "true" "our own unfinished claim is finished"
hasnt "$(gh_since "$mark")" "REPLY" "…without a second reply"

echo "# an unreadable mark never lowers the floor"
store "[$(anchor WI 55 "$(wb_meta rework:KI 0)$(wb_batch 'rework:KI|100|200')"), $(child KI closed)]"
printf '%s' "$(prview 55 OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_55.json"
threads 55 "$(one_thread 55)"
mark=$(( $(wc -l < "$STUB_GH_LOG") + 1 ))
out=$(run)
eq "$(meta WI pr_comment_batch)" "rework:KI|100|200" "the recorded range survives a mark it cannot read"
hasnt "$(gh_since "$mark")" "RESOLVE" "…and nothing is resolved under it"

echo "# our own comments are never acknowledged"
store "[$(anchor W7 46 "$(wb_meta rework:K7)"), $(child K7 open)]"
printf '%s' "$(prview 46 OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_46.json"
threads 46 "$(printf '%s' "$(one_thread 46)" | jq -c '.threads[0].comments.nodes[0].author.login = "gc-city-bot"
  | .threads[0].comments.nodes[0].body = "a city notice\n\n<!-- gc:city -->"')"
out=$(run)
eq "$(reacted 46 NC-46)" "false" "the city does not react to itself"

echo "# …but an unmarked comment under our login past the cutover was feedback, so it is acknowledged"
store "[$(anchor W7B 166 "$(wb_meta rework:K7B)"',"pr_provenance_since":"2026-10-07T00:00:00Z"'), $(child K7B open)]"
printf '%s' "$(prview 166 OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_166.json"
threads 166 "$(printf '%s' "$(one_thread 166)" | jq -c '.threads[0].comments.nodes[0].author.login = "gc-city-bot"
  | .threads[0].comments.nodes[0].createdAt = "2026-10-07T01:00:00Z"')"
out=$(run)
eq "$(reacted 166 NC-166)" "true" "the routed model-review comment gets its EYES reaction"

echo "# …and a comment drafted before the cutover in a review submitted after it is acknowledged too"
# The write-back reads the same provenance the routing arm routed by: a thread
# comment is dated by its review's submission, so the comment the child carries
# is the comment the write-back acknowledges.
store "[$(anchor W7C 174 "$(wb_meta rework:K7C)"',"pr_provenance_since":"2026-10-07T00:00:00Z"'), $(child K7C open)]"
printf '%s' "$(prview 174 OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_174.json"
threads 174 "$(printf '%s' "$(one_thread 174)" | jq -c '.threads[0].comments.nodes[0].author.login = "gc-city-bot"
  | .threads[0].comments.nodes[0].createdAt = "2026-10-06T23:50:00Z"
  | .threads[0].comments.nodes[0].pullRequestReview = {submittedAt: "2026-10-07T00:10:00Z"}')"
out=$(run)
eq "$(reacted 174 NC-174)" "true" "the straddling review's comment gets its EYES reaction"

echo "# a review body that produced the bead is acknowledged too"
store "[$(anchor W8 47 "$(wb_rmeta rework:K8 55)"), $(child K8 open)]"
printf '%s' "$(prview 47 OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_47.json"
threads 47 '{"reviews":[{"id":"RV-47","databaseId":55,"state":"COMMENTED","body":"a real note","author":{"login":"johnzook"},"reactionGroups":[]},{"id":"RV-47e","databaseId":54,"state":"COMMENTED","body":"   ","author":{"login":"johnzook"},"reactionGroups":[]}],"threads":[]}'
out=$(run)
eq "$(reacted 47 RV-47)" "true" "the review body is acknowledged"
eq "$(reacted 47 RV-47e)" "false" "an empty-bodied review carries no comment to acknowledge"

echo "# …and a CHANGES_REQUESTED review body is acknowledged the same way"
# max_r counts a veto's body beside a COMMENTED one, so the write-back reacts to
# the states it can advance the mark past. A body-only veto routed to a child,
# its review left unreacted, would tell the operator the city acted on nothing.
store "[$(anchor W8c 74 "$(wb_rmeta rework:K8c 55)"), $(child K8c open)]"
printf '%s' "$(prview 74 OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_74.json"
threads 74 '{"reviews":[{"id":"RV-74","databaseId":55,"state":"CHANGES_REQUESTED","body":"not what I asked for","author":{"login":"johnzook"},"reactionGroups":[]}],"threads":[]}'
out=$(run)
eq "$(reacted 74 RV-74)" "true" "a veto's review body earns the same acknowledgement a COMMENTED one does"

echo "# a thread the identity cannot resolve is left alone"
store "[$(anchor W9 48 "$(wb_meta rework:K9)"), $(child K9 closed)]"
printf '%s' "$(prview 48 OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_48.json"
threads 48 "$(printf '%s' "$(one_thread 48)" | jq -c '.threads[0].viewerCanResolve = false')"
out=$(run)
eq "$(tresolved 48 T-48)" "false" "an unresolvable thread is not resolved"
has "$(treply 48 T-48)" "✅ Resolved in sha-48" "…but the reply still lands, since the operator still wants it"
has "$out" "not resolvable by this identity" "the missing right is reported"

echo "# an unreadable thread read writes nothing"
store "[$(anchor WA 49 "$(wb_meta rework:KA)"), $(child KA closed)]"
printf '%s' "$(prview 49 OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_49.json"
threads 49 "$(one_thread 49)"
out=$(STUB_GQL_READ_FAIL=1 run)
has "$out" "review threads unreadable" "the unreadable read is reported"
eq "$(reacted 49 NC-49)" "false" "…and nothing was written"

echo "# a failed reply never resolves the thread behind it"
store "[$(anchor WB 50 "$(wb_meta rework:KB)"), $(child KB closed)]"
printf '%s' "$(prview 50 OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_50.json"
threads 50 "$(one_thread 50)"
out=$(STUB_REPLY_RC=1 run)
has "$out" "could not reply on thread" "the failed reply is reported"
eq "$(tresolved 50 T-50)" "false" "…and the thread is left unresolved"

echo "# over the reaction cap, the batch's answers wait for the acknowledgements"
# The pickup reaction is what tells the operator their comment was seen. A
# thread replied to and resolved while the cap left its comment unacknowledged
# answers a comment the city never showed it picked up. PR_FACTS_REACT_CAP sets
# the cap low, so six threads cross it.
store "[$(anchor WJ 56 "$(wb_meta rework:KJ)"), $(child KJ closed)]"
printf '%s' "$(prview 56 OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_56.json"
threads 56 "$(jq -cn '{reviews: [], threads: [ range(6) | {
  id: ("T-56-" + tostring), isResolved: false, viewerCanResolve: true,
  comments: {nodes: [{id: ("NC-56-" + tostring), databaseId: 100,
    author: {login: "johnzook"}, body: "please fix", reactionGroups: []}]}} ]}')"
mark=$(( $(wc -l < "$STUB_GH_LOG") + 1 ))
out=$(PR_FACTS_REACT_CAP=5 run)
has "$out" "has 6 comments awaiting a pickup reaction; acknowledging 5 this pass" "the cap is reported"
eq "$(gh_since "$mark" | grep -c '^REACT .* EYES$')" "5" "exactly the capped 5 acknowledgements land"
has "$out" "nothing replied or resolved this pass" "the answers are deferred with them"
hasnt "$(gh_since "$mark")" "REPLY" "no thread is answered over an unacknowledged comment"
hasnt "$(gh_since "$mark")" "RESOLVE" "…and none is resolved"

echo "# …and the pass that finishes the acknowledgements answers every thread"
mark=$(( $(wc -l < "$STUB_GH_LOG") + 1 ))
out=$(PR_FACTS_REACT_CAP=5 run)
eq "$(gh_since "$mark" | grep -c '^REACT .* EYES$')" "1" "the comment the cap held over is acknowledged"
eq "$(gh_since "$mark" | grep -c '^REPLY')" "6" "every thread in the batch gets its reply"
eq "$(gh_since "$mark" | grep -c '^RESOLVE')" "6" "…and is resolved behind it"
eq "$(gh_since "$mark" | grep -c '^REACT .* THUMBS_UP$'),$(gh_since "$mark" | grep -c '^UNREACT .* EYES$')" "6,6" \
  "…and every answered comment trades its EYES for THUMBS_UP"

echo "# swaps owed on comments answered earlier draw on the same reaction cap"
# Six threads a reply of ours already answered and resolved, each comment
# still carrying EYES: a swap each, and no more of them than the cap per pass.
store "[$(anchor WSW 322 "$(wb_meta rework:KSW)"), $(child KSW closed)]"
printf '%s' "$(prview 322 OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_322.json"
threads 322 "$(jq -cn '{reviews: [], threads: [ range(6) | {
  id: ("T-322-" + tostring), isResolved: true, viewerCanResolve: true,
  comments: {nodes: [
    {id: ("NC-322-" + tostring), databaseId: 100, author: {login: "johnzook"}, body: "please fix",
     reactionGroups: [{content: "EYES", viewerHasReacted: true}]},
    {id: ("NC-322-" + tostring + "-r"), databaseId: 0, author: {login: "gc-city-bot"},
     body: "Addressed in sha-322 on this PR (KSW).\n<!-- gc-writeback -->", reactionGroups: []}]}} ]}')"
mark=$(( $(wc -l < "$STUB_GH_LOG") + 1 ))
out=$(PR_FACTS_REACT_CAP=5 run)
eq "$(gh_since "$mark" | grep -c '^REACT .* THUMBS_UP$')" "5" "the first pass swaps the capped 5"
hasnt "$(gh_since "$mark")" "REPLY" "…posting no answer over the replies already there"
mark=$(( $(wc -l < "$STUB_GH_LOG") + 1 ))
out=$(PR_FACTS_REACT_CAP=5 run)
eq "$(gh_since "$mark" | grep -c '^REACT .* THUMBS_UP$'),$(gh_since "$mark" | grep -c '^UNREACT .* EYES$')" "1,1" \
  "…and the next pass swaps the one it deferred"

echo "# a reaction cap override that is not a positive integer keeps the default cap"
# A cap of 0 would hold every batch's answers forever, so an override that is
# not a positive integer falls back to the default, and one comment is
# acknowledged and answered in a single pass. The answer trades the pickup EYES
# for THUMBS_UP, so the acknowledgement is read off the pass's writes.
store "[$(anchor WJ0 80 "$(wb_meta rework:KJ0)"), $(child KJ0 closed)]"
printf '%s' "$(prview 80 OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_80.json"
threads 80 "$(one_thread 80)"
mark=$(( $(wc -l < "$STUB_GH_LOG") + 1 ))
out=$(PR_FACTS_REACT_CAP=0 run)
eq "$(gh_since "$mark" | grep -c '^REACT NC-80 EYES$')" "1" "a zero override still acknowledges the comment"
eq "$(tresolved 80 T-80)" "true" "…and the thread is answered behind it"
store "[$(anchor WJ1 81 "$(wb_meta rework:KJ1)"), $(child KJ1 closed)]"
printf '%s' "$(prview 81 OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_81.json"
threads 81 "$(one_thread 81)"
mark=$(( $(wc -l < "$STUB_GH_LOG") + 1 ))
out=$(PR_FACTS_REACT_CAP=five run)
eq "$(gh_since "$mark" | grep -c '^REACT NC-81 EYES$')" "1" "a non-numeric override still acknowledges the comment"
eq "$(tresolved 81 T-81)" "true" "…and the thread is answered behind it"

echo "# a pickup reaction that failed to land holds the answer back too"
store "[$(anchor WK 57 "$(wb_meta rework:KK)"), $(child KK closed)]"
printf '%s' "$(prview 57 OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_57.json"
threads 57 "$(one_thread 57)"
mark=$(( $(wc -l < "$STUB_GH_LOG") + 1 ))
out=$(STUB_REACT_RC=1 run)
has "$out" "could not react to NC-57" "the failed acknowledgement is reported"
has "$out" "still has comments awaiting their pickup reaction" "the answers are held with it"
hasnt "$(gh_since "$mark")" "REPLY" "the thread is not answered"
eq "$(tresolved 57 T-57)" "false" "…and not resolved"

echo "# …and the pass whose acknowledgement lands answers it"
out=$(run)
eq "$(thumbed 57 NC-57)" "true" "the retried acknowledgement lands, and the answer behind it marks the comment resolved"
has "$(treply 57 T-57)" "✅ Resolved in sha-57" "the reply follows it"
eq "$(tresolved 57 T-57)" "true" "…and the thread is resolved behind it"

echo "# a disposition written DURING the pass is acknowledged in that same pass"
# The sweep re-reads the anchors instead of reusing the top-of-pass enumeration,
# which is the whole reason an arm can route a comment and see it acknowledged
# without waiting for the next reconcile. A hook stamps WD2 while the dispatch
# loop is still working WD1, so only a re-read can see it.
store "[$(anchor WD1 60), $(anchor WD2 61)]"
printf '%s' "$(prview 60 OPEN DIRTY CONFLICTING)" > "$GH_DIR/pr_view_60.json"
printf '%s' "$(prview 61 OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_61.json"
threads 61 "$(one_thread 61)"
cat > "$TMP/stamp-hook" <<HOOK
#!/usr/bin/env bash
t=\$(mktemp "${TMPDIR:-/tmp}/gctk-pr-facts-test.XXXXXX")
jq '[ .[] | if .id == "WD2" then .metadata += {"pr_comment_disposition":"rework:KD","pr_comment_watermark":"100","pr_review_watermark":"0"} else . end ]' "\${STUB_STORE:?}" > "\$t" && mv "\$t" "\${STUB_STORE:?}"
HOOK
chmod +x "$TMP/stamp-hook"
out=$(STUB_SHOW_HOOK="$TMP/stamp-hook" run)
eq "$(meta WD2 pr_comment_disposition)" "rework:KD" "the hook stamped WD2 mid-pass"
eq "$(reacted 61 NC-61)" "true" "the sweep saw the mid-pass disposition and acknowledged in the same pass"

echo "# a write-back never touches a PR this anchor does not own"
store "[$(anchor WC 51 "$(wb_meta rework:KC)"), $(child KC closed)]"
printf '%s' "$(prview 51 OPEN CLEAN MERGEABLE)" | jq -c '.headRepositoryOwner.login = "stranger" | .isCrossRepository = true' > "$GH_DIR/pr_view_51.json"
threads 51 "$(one_thread 51)"
out=$(run)
has "$out" "identity did not certify for the write-back" "the foreign PR is refused"
eq "$(reacted 51 NC-51)" "false" "…and NOTHING was written back"

# ---- the state marks: looked at, awaiting a person, resolved ------------------
# A review body or a Conversation comment has no thread, so its answer is a PR
# comment of ours linking to it, found again by the mark line naming its token.
# Its batch is read from its own space's ledger, so these fixtures carry them.
wb_tmeta() { # disposition review-mark issue-mark review-ledger issue-ledger
  printf ',"pr_comment_disposition":"%s","pr_comment_watermark":"0","pr_review_watermark":"%s","pr_issue_comment_watermark":"%s","pr_review_batch":"%s","pr_issue_comment_batch":"%s"' \
    "$1" "$2" "$3" "$4" "$5"
}
# the bodies of our own Conversation comments on the PR
pcomments() { jq -r '[ .issue_comments[]? | select(.author.login == "gc-city-bot") | .body ] | join(" ")' "$GH_DIR/threads_$1.json"; }
# a human finding that names the comment it was raised on and that comment's review
hfind() { # id anchor comment_id review_id disposition status [reply]
  printf '{"id":"%s","status":"%s","assignee":"","notes":"","title":"finding[human]: x","metadata":{"task_kind":"finding","anchor_bead":"%s","finding.lane":"human","finding.disposition":"%s","finding.source":"human:johnzook","finding.comment_id":"%s","finding.review_id":"%s"%s}}' \
    "$1" "$6" "$2" "$5" "$3" "$4" "${7:+,\"finding.reply\":\"$7\"}"
}
top_fixture() { # num — one routed review body (55) and one routed Conversation comment (50)
  printf '{"reviews":[{"id":"RV-%s","databaseId":55,"state":"COMMENTED","body":"rethink the cap","url":"https://github.com/zook/gc-toolkit/pull/%s#pullrequestreview-55","author":{"login":"johnzook"},"reactionGroups":[]}],"threads":[],"issue_comments":[{"id":"IC-%s","databaseId":50,"body":"and rename it","url":"https://github.com/zook/gc-toolkit/pull/%s#issuecomment-50","author":{"login":"johnzook"},"reactionGroups":[]}]}' \
    "$1" "$1" "$1" "$1"
}

echo "# a landed batch resolves its review body and Conversation comment with one linking answer"
store "[$(anchor WT1 310 "$(wb_tmeta rework:KT1 55 50 'rework:KT1|0|55' 'rework:KT1|0|50')"), $(child KT1 closed)]"
printf '%s' "$(prview 310 OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_310.json"
threads 310 "$(top_fixture 310)"
mark=$(( $(wc -l < "$STUB_GH_LOG") + 1 ))
out=$(run)
has "$(pcomments 310)" "✅ Resolved in sha-310 on this PR (KT1)." "a check-mark answer names the landing commit and the bead"
has "$(pcomments 310)" "In reply to https://github.com/zook/gc-toolkit/pull/310#pullrequestreview-55, https://github.com/zook/gc-toolkit/pull/310#issuecomment-50." \
  "…and links to the review body and the Conversation comment it answers"
has "$(pcomments 310)" "<!-- gc-writeback-mark:resolved r55 i50 -->" "…carrying the mark line that names both"
eq "$(gh_since "$mark" | grep -c '^PRCOMMENT')" "1" "one Conversation answer covers the whole batch"
eq "$(thumbed 310 RV-310),$(reacted 310 RV-310)" "true,false" "the review body trades EYES for THUMBS_UP"
eq "$(thumbed 310 IC-310),$(reacted 310 IC-310)" "true,false" "…and so does the Conversation comment"
has "$out" "1 conversation answers posted, 2 comments marked resolved" "the pass reports the answer and both swaps"
echo "# …and a second pass finds its own answer and writes nothing"
mark=$(( $(wc -l < "$STUB_GH_LOG") + 1 ))
out=$(run)
hasnt "$(gh_since "$mark")" "PRCOMMENT" "no second Conversation answer"
hasnt "$(gh_since "$mark")" "REACT" "…and no reaction"

echo "# a Conversation comment routed to an open visit is marked awaiting a person, then resolved"
store "[$(anchor WT2 311 "$(wb_tmeta visit:VT2 0 50 '' 'visit:VT2|0|50')"), $(child VT2 open)]"
printf '%s' "$(prview 311 OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_311.json"
threads 311 "$(top_fixture 311 | jq -c '.reviews = []')"
out=$(run)
has "$(pcomments 311)" "❓ Awaiting a person — visit VT2. In reply to https://github.com/zook/gc-toolkit/pull/311#issuecomment-50." \
  "a question-mark answer names the visit and links to the comment"
has "$(pcomments 311)" "<!-- gc-writeback-mark:awaiting:VT2 i50 -->" "…carrying the awaiting mark line"
eq "$(reacted 311 IC-311),$(thumbed 311 IC-311)" "true,false" "the comment keeps its pickup EYES"
mark=$(( $(wc -l < "$STUB_GH_LOG") + 1 ))
out=$(run)
hasnt "$(gh_since "$mark")" "PRCOMMENT" "the awaiting answer is posted once"
bmut VT2 '.status = "closed"'
mark=$(( $(wc -l < "$STUB_GH_LOG") + 1 ))
out=$(run)
has "$(pcomments 311)" "✅ Resolved: visit VT2 closed. In reply to https://github.com/zook/gc-toolkit/pull/311#issuecomment-50." \
  "once the visit closes, the check-mark answer follows"
eq "$(gh_since "$mark" | grep -c '^PRCOMMENT')" "1" "…as one more answer"
eq "$(thumbed 311 IC-311),$(reacted 311 IC-311)" "true,false" "…and the comment trades EYES for THUMBS_UP"

echo "# a Conversation comment no ledger places is acknowledged and never answered"
# An anchor routed before the review and Conversation ledgers existed carries
# its Conversation comments below the mark with no batch to read: the city
# cannot tell which bead answered them, so it claims none did.
store "[$(anchor WT3 312 "$(wb_imeta rework:KT3)"), $(child KT3 closed)]"
printf '%s' "$(prview 312 OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_312.json"
threads 312 "$(top_fixture 312 | jq -c '.reviews = []')"
mark=$(( $(wc -l < "$STUB_GH_LOG") + 1 ))
out=$(run)
eq "$(reacted 312 IC-312)" "true" "the comment is acknowledged"
hasnt "$(gh_since "$mark")" "PRCOMMENT" "…and nothing answers it"
eq "$(thumbed 312 IC-312)" "false" "…nor marks it resolved"

echo "# a landed batch waits for the comment's own finding to be validated"
# Resolved means validated as resolved: a finding still open is a ruling the
# validator has not given, so the batch's bead closing answers nothing yet.
store "[$(anchor WT4 313 "$(wb_meta rework:KT4)"), $(child KT4 closed), $(hfind FT4 WT4 100 900 unvalidated open)]"
printf '%s' "$(prview 313 OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_313.json"
threads 313 "$(one_thread 313)"
out=$(run)
eq "$(treply 313 T-313)" "" "no answer while the finding is open"
eq "$(tresolved 313 T-313)" "false" "…and the thread is left open"
eq "$(reacted 313 NC-313)" "true" "…the comment still acknowledged"
bmut FT4 '.status = "closed" | .metadata += {"finding.disposition":"must-fix"}'
out=$(run)
has "$(treply 313 T-313)" "✅ Resolved in sha-313 on this PR (KT4)." "once the finding closes, the batch answers the comment"
eq "$(tresolved 313 T-313)" "true" "…and resolves the thread"
eq "$(thumbed 313 NC-313)" "true" "…and marks the comment resolved"

echo "# a needs-you finding marks its comment awaiting a person, whatever its batch did"
store "[$(anchor WT5 314 "$(wb_meta rework:KT5)"), $(child KT5 closed), $(hfind FT5 WT5 100 900 needs-you open 'This comment needs your decision — opened visit tk-v314. The review stays changes-requested until you rule it.')]"
printf '%s' "$(prview 314 OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_314.json"
threads 314 "$(one_thread 314)"
out=$(run)
has "$(treply 314 T-314)" "❓ This comment needs your decision — opened visit tk-v314." "the owed reply leads with the question mark"
has "$(treply 314 T-314)" "<!-- gc-writeback-finding:FT5 -->" "…carrying the line naming its finding"
hasnt "$(treply 314 T-314)" "Resolved" "the landed batch never claims the comment resolved"
eq "$(tresolved 314 T-314)" "false" "…and the thread stays open for the ruling"
eq "$(thumbed 314 NC-314)" "false" "…with the comment not marked resolved"

echo "# a declined finding's answer leads with the check mark and marks the comment resolved"
store "[$(anchor WT6 315 "$(wb_meta rework:KT6)"), $(child KT6 open), $(hfind FT6 WT6 100 900 declined closed 'The helper already asserts it; no change needed.')]"
printf '%s' "$(prview 315 OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_315.json"
threads 315 "$(one_thread 315)"
out=$(run)
has "$(treply 315 T-315)" "✅ The helper already asserts it; no change needed." "the decline is answered with the check mark"
eq "$(tresolved 315 T-315)" "true" "…and its thread resolved"
mark=$(( $(wc -l < "$STUB_GH_LOG") + 1 ))
out=$(run)
eq "$(thumbed 315 NC-315),$(reacted 315 NC-315)" "true,false" "the next pass trades the comment's EYES for THUMBS_UP"
hasnt "$(gh_since "$mark")" "REPLY" "…without answering it twice"
mark=$(( $(wc -l < "$STUB_GH_LOG") + 1 ))
out=$(run)
hasnt "$(gh_since "$mark")" "REACT" "a third pass writes no reaction"

echo "# a declined review body is answered on the Conversation tab, linking to the review"
store "[$(anchor WT7 316 "$(wb_tmeta rework:KT7 55 0 'rework:KT7|0|55' '')"), $(child KT7 open), $(hfind FT7 WT7 55 55 declined closed 'Not an objection: the cap is a reaction budget.')]"
printf '%s' "$(prview 316 OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_316.json"
threads 316 "$(top_fixture 316 | jq -c '.issue_comments = []')"
out=$(STUB_DROP_KEYS="FT7:finding.reply_posted" run)
has "$(pcomments 316)" "✅ Not an objection: the cap is a reaction budget. In reply to https://github.com/zook/gc-toolkit/pull/316#pullrequestreview-55." \
  "the decline is posted with the check mark and a link to the review it answers"
eq "$(meta FT7 finding.reply_posted)" "<absent>" "the answered stamp was dropped, as a pass that died after posting leaves it"
mark=$(( $(wc -l < "$STUB_GH_LOG") + 1 ))
out=$(run)
hasnt "$(gh_since "$mark")" "PRCOMMENT" "the next pass finds the posted answer by its finding line and posts no second one"
eq "$(meta FT7 finding.reply_posted)" "1" "…and records the finding answered"
out=$(run)
eq "$(thumbed 316 RV-316),$(reacted 316 RV-316)" "true,false" "…and the review body trades EYES for THUMBS_UP"

echo "# a comment added to an answered, resolved thread is answered on its own"
store "[$(anchor WT8 317 "$(wb_meta rework:KT8b 200)$(wb_batch 'rework:KT8a|0|100;rework:KT8b|100|200')"), $(child KT8a closed), $(child KT8b closed)]"
printf '%s' "$(prview 317 OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_317.json"
threads 317 "$(printf '%s' "$(one_thread 317)" | jq -c '
  .threads[0].isResolved = true
  | .threads[0].comments.nodes[0].reactionGroups = [{"content":"THUMBS_UP","viewerHasReacted":true}]
  | .threads[0].comments.nodes += [
    {"id":"NC-317m","databaseId":0,"author":{"login":"gc-city-bot"},"body":"✅ Resolved in sha-317 on this PR (KT8a).\n<!-- gc-writeback -->\n<!-- gc-writeback-mark:resolved -->","reactionGroups":[]},
    {"id":"NC-317b","databaseId":200,"author":{"login":"johnzook"},"body":"one more","reactionGroups":[]}]')"
mark=$(( $(wc -l < "$STUB_GH_LOG") + 1 ))
out=$(run)
has "$(treply 317 T-317)" "✅ Resolved in sha-317 on this PR (KT8b)." "the later comment gets the answer naming its own bead"
eq "$(gh_since "$mark" | grep -c '^REPLY')" "1" "…in one reply"
hasnt "$(gh_since "$mark")" "RESOLVE" "…into the thread already resolved, which is left as it is"
eq "$(thumbed 317 NC-317b),$(reacted 317 NC-317b)" "true,false" "…and the later comment is marked resolved"

echo "# a reply of ours with no mark line still answers its thread, and its comment is marked"
# A thread answered and resolved by a reply that carries only the marker: that
# reply resolved the comment, so a later pass posts nothing over it and trades
# the comment's EYES for THUMBS_UP while its batch is still recorded.
store "[$(anchor WT9 318 "$(wb_meta rework:KT9)"), $(child KT9 closed)]"
printf '%s' "$(prview 318 OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_318.json"
threads 318 "$(printf '%s' "$(one_thread 318)" | jq -c '
  .threads[0].isResolved = true
  | .threads[0].comments.nodes[0].reactionGroups = [{"content":"EYES","viewerHasReacted":true}]
  | .threads[0].comments.nodes += [
    {"id":"NC-318m","databaseId":0,"author":{"login":"gc-city-bot"},"body":"Addressed in sha-318 on this PR (KT9).\n<!-- gc-writeback -->","reactionGroups":[]}]')"
mark=$(( $(wc -l < "$STUB_GH_LOG") + 1 ))
out=$(run)
hasnt "$(gh_since "$mark")" "REPLY" "no second answer over the old one"
eq "$(thumbed 318 NC-318),$(reacted 318 NC-318)" "true,false" "…and the answered comment is marked resolved"

echo "# a swap that fails is retried by the next pass"
store "[$(anchor WTA 319 "$(wb_meta rework:KTA)"), $(child KTA closed)]"
printf '%s' "$(prview 319 OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_319.json"
threads 319 "$(one_thread 319)"
out=$(STUB_UNREACT_RC=1 run)
has "$out" "could not retire the pickup reaction on NC-319" "the failed removal is reported"
eq "$(thumbed 319 NC-319),$(reacted 319 NC-319)" "true,true" "…leaving both reactions, never neither"
eq "$(tresolved 319 T-319)" "true" "…while the answer and the resolve stand"
mark=$(( $(wc -l < "$STUB_GH_LOG") + 1 ))
out=$(run)
eq "$(thumbed 319 NC-319),$(reacted 319 NC-319)" "true,false" "the next pass finishes the swap"
hasnt "$(gh_since "$mark")" "REPLY" "…without answering again"

echo "# findings that cannot be read mark nothing"
store "[$(anchor WTB 320 "$(wb_meta rework:KTB)"), $(child KTB closed)]"
printf '%s' "$(prview 320 OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_320.json"
threads 320 "$(one_thread 320)"
out=$(STUB_LIST_FAIL_ON="anchor_bead=WTB" run)
has "$out" "findings unreadable; acknowledging only" "the unreadable findings are reported"
eq "$(reacted 320 NC-320)" "true" "the comment is still acknowledged"
eq "$(treply 320 T-320)" "" "…but nothing is answered"
eq "$(tresolved 320 T-320)" "false" "…or resolved"

echo "# a resolved batch is retired from its ledger once its comments are marked, and an open visit's is kept"
store "[$(anchor WTC 321 "$(wb_tmeta rework:KTC2 55 50 'rework:KTC1|0|55' 'visit:VTC|0|50;rework:KTC2|50|50')"), $(child KTC1 closed), $(child KTC2 closed), $(child VTC open)]"
printf '%s' "$(prview 321 OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_321.json"
threads 321 "$(top_fixture 321)"
out=$(run)
out=$(run)
eq "$(meta WTC pr_review_batch)" "rework:KTC1|0|55" "the newest record is kept whatever it owes"
eq "$(meta WTC pr_issue_comment_batch)" "visit:VTC|0|50;rework:KTC2|50|50" "an open visit's batch is kept while its comment waits"
bmut VTC '.status = "closed"'
out=$(run)
out=$(run)
eq "$(meta WTC pr_issue_comment_batch)" "rework:KTC2|50|50" "…and retired once the comment it held is resolved and marked"

# ---- feedback the threads answered before routing is not the batch's ----------
# The routing arm leaves out of its batch what the review threads already
# answered: a comment in a resolved thread with a later post of the city's (a
# sitting's reply, say). The batch's range still holds it, but its bead never saw
# it, so it is acknowledged and never answered or marked by that bead.
# answered_thread <num> <suffix> <comment-id> <review-id> — a resolved thread: an
# operator comment, then the city's marked reply to it
answered_thread() {
  printf '{"id":"T-%s%s","isResolved":true,"viewerCanResolve":true,"comments":{"nodes":[{"id":"NC-%s%s","databaseId":%s,"author":{"login":"johnzook"},"body":"rename this","pullRequestReview":{"databaseId":%s},"reactionGroups":[]},{"id":"NC-%s%ss","databaseId":%s,"author":{"login":"gc-city-bot"},"body":"Renamed in the sitting.\\n\\n<!-- gc:city -->","pullRequestReview":{"databaseId":99},"reactionGroups":[]}]}}' \
    "$1" "$2" "$1" "$2" "$3" "$4" "$1" "$2" "$(( $3 + 1 ))"
}
open_thread() { # <num> <suffix> <comment-id> — an unresolved thread holding one operator comment
  printf '{"id":"T-%s%s","isResolved":false,"viewerCanResolve":true,"comments":{"nodes":[{"id":"NC-%s%s","databaseId":%s,"author":{"login":"johnzook"},"body":"please fix","reactionGroups":[]}]}}' \
    "$1" "$2" "$1" "$2" "$3"
}

echo "# a landed batch answers the comment it carried, never one a sitting answered before routing"
store "[$(anchor WTD 323 "$(wb_meta rework:KTD)"), $(child KTD closed)]"
printf '%s' "$(prview 323 OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_323.json"
threads 323 "{\"reviews\":[],\"threads\":[$(answered_thread 323 a 90 55),$(open_thread 323 b 100)]}"
mark=$(( $(wc -l < "$STUB_GH_LOG") + 1 ))
out=$(run)
has "$(treply 323 T-323b)" "✅ Resolved in sha-323 on this PR (KTD)." "the carried comment's thread is answered by the batch"
eq "$(treply 323 T-323a)" "" "the thread the sitting answered gets no answer naming the batch"
eq "$(gh_since "$mark" | grep -c '^REPLY')" "1" "…so the pass posts one reply"
eq "$(reacted 323 NC-323a),$(thumbed 323 NC-323a)" "true,false" "…and that comment is acknowledged, never marked resolved"
eq "$(thumbed 323 NC-323b)" "true" "the carried comment is marked resolved"

echo "# an open visit's awaiting answer skips the comment a sitting answered before routing"
store "[$(anchor WTE 324 "$(wb_meta visit:VTE)"), $(child VTE open)]"
printf '%s' "$(prview 324 OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_324.json"
threads 324 "{\"reviews\":[],\"threads\":[$(answered_thread 324 a 90 55),$(open_thread 324 b 100)]}"
out=$(run)
has "$(treply 324 T-324b)" "❓ Awaiting a person — visit VTE." "the carried comment waits on the visit"
eq "$(treply 324 T-324a)" "" "the comment a sitting answered is not marked awaiting"

echo "# a review body whose inline comments a sitting answered is left out of the batch's answer"
store "[$(anchor WTF 325 "$(wb_tmeta rework:KTF 56 0 'rework:KTF|0|56' '')"), $(child KTF closed)]"
printf '%s' "$(prview 325 OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_325.json"
threads 325 "$(printf '%s' "{\"reviews\":[],\"threads\":[$(answered_thread 325 a 90 55)],\"issue_comments\":[]}" | jq -c '.reviews = [
  {"id":"RV-325a","databaseId":55,"state":"COMMENTED","body":"two renames","url":"https://github.com/zook/gc-toolkit/pull/325#pullrequestreview-55","author":{"login":"johnzook"},"reactionGroups":[]},
  {"id":"RV-325b","databaseId":56,"state":"COMMENTED","body":"rethink the cap","url":"https://github.com/zook/gc-toolkit/pull/325#pullrequestreview-56","author":{"login":"johnzook"},"reactionGroups":[]}]')"
out=$(run)
has "$(pcomments 325)" "✅ Resolved in sha-325 on this PR (KTF). In reply to https://github.com/zook/gc-toolkit/pull/325#pullrequestreview-56." \
  "the batch answers the review it carried"
hasnt "$(pcomments 325)" "pullrequestreview-55" "…and not the review whose every inline comment a sitting answered"
eq "$(reacted 325 RV-325a),$(thumbed 325 RV-325a)" "true,false" "that review is acknowledged, never marked resolved"
eq "$(thumbed 325 RV-325b)" "true" "the carried review is marked resolved"

echo "# a finding still places its comment under the batch when the thread holds a later city post"
# The fixer answered in the thread and someone resolved it, but the comment was
# routed: its finding says so, and the batch's bead answers it.
store "[$(anchor WTG 326 "$(wb_meta rework:KTG)"), $(child KTG closed), $(hfind FTG WTG 90 55 must-fix closed)]"
printf '%s' "$(prview 326 OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_326.json"
threads 326 "{\"reviews\":[],\"threads\":[$(answered_thread 326 a 90 55)]}"
out=$(run)
has "$(treply 326 T-326a)" "✅ Resolved in sha-326 on this PR (KTG)." "the routed comment is answered by its batch"
eq "$(thumbed 326 NC-326a)" "true" "…and marked resolved"

echo "# an unmarked review under our OWN login from before the cutover leaves threads arm 7 never routes"
# The gap: an outside review agent (or an operator-run review) posted findings on
# a green PR under the automation's own login before the city marked its posts.
# arm 7 reads such a post as the city's own, so it routes nothing; the check
# stays green, and until this backstop nothing flagged it.
store "[$(anchor UT1 60 "$UTCUT")]"
printf '%s' "$(prview 60 OPEN CLEAN MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_60.json"
printf '%s\n' '[{"id":100,"user":{"login":"gc-city-bot"},"body":"**Review finding 1/1** fix this","pull_request_review_id":null,"created_at":"2026-10-06T12:00:00Z"}]' > "$GH_DIR/comments_60.json"
echo '[]' > "$GH_DIR/reviews_60.json"
printf '%s\n' '{"reviews":[],"threads":[{"id":"T-60","isResolved":false,"viewerCanResolve":true,"comments":{"nodes":[{"id":"NC-60","databaseId":100,"author":{"login":"gc-city-bot"},"body":"**Review finding 1/1** fix this","reactionGroups":[]}]}}]}' > "$GH_DIR/threads_60.json"
out=$(run)
has "$out" "unengaged review-thread finding" "the backstop flags the otherwise-clear PR"
hasnt "$out" "routed to rework:" "arm 7 routed nothing — the finding is the city's own by the cutover"
UTVID=$(jq -r '[ .[] | select(((.metadata.escalation_key // "") | tostring) | startswith("pr-unengaged-threads")) | .id ] | .[0] // empty' "$STUB_STORE")
[ -n "$UTVID" ] && ok "a visit was filed" || bad "no visit filed"
eq "$(meta "$UTVID" pr_number)" "60" "…stamped with the PR so merge.sh holds the merge"
eq "$(meta "$UTVID" anchor_bead)" "UT1" "…and anchored to the gating bead"
eq "$(meta UT1 pr_unengaged_threads)" "sha-60" "…and the anchor is head-watermarked against re-filing"

echo "# a RESOLVED thread is done — the finding exists but nothing is flagged"
store "[$(anchor UT2 61 "$UTCUT")]"
printf '%s' "$(prview 61 OPEN CLEAN MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_61.json"
printf '%s\n' '[{"id":100,"user":{"login":"gc-city-bot"},"body":"finding","pull_request_review_id":null,"created_at":"2026-10-06T12:00:00Z"}]' > "$GH_DIR/comments_61.json"
echo '[]' > "$GH_DIR/reviews_61.json"
printf '%s\n' '{"reviews":[],"threads":[{"id":"T-61","isResolved":true,"viewerCanResolve":true,"comments":{"nodes":[{"id":"NC-61","databaseId":100,"author":{"login":"gc-city-bot"},"body":"finding","reactionGroups":[]}]}}]}' > "$GH_DIR/threads_61.json"
out=$(run)
hasnt "$out" "unengaged review-thread finding" "a resolved thread raises nothing"
eq "$(meta UT2 pr_unengaged_threads)" "<absent>" "…and no head watermark is written"

echo "# a thread we already replied into is arm 7's or the write-back's to finish, not ours"
store "[$(anchor UT3 62 "$UTCUT")]"
printf '%s' "$(prview 62 OPEN CLEAN MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_62.json"
printf '%s\n' '[{"id":100,"user":{"login":"gc-city-bot"},"body":"finding","pull_request_review_id":null,"created_at":"2026-10-06T12:00:00Z"}]' > "$GH_DIR/comments_62.json"
echo '[]' > "$GH_DIR/reviews_62.json"
printf '%s\n' '{"reviews":[],"threads":[{"id":"T-62","isResolved":false,"viewerCanResolve":true,"comments":{"nodes":[{"id":"NC-62","databaseId":100,"author":{"login":"gc-city-bot"},"body":"finding","reactionGroups":[]},{"id":"NC-62b","databaseId":0,"author":{"login":"gc-city-bot"},"body":"noted <!-- gc-writeback -->","reactionGroups":[]}]}}]}' > "$GH_DIR/threads_62.json"
out=$(run)
hasnt "$out" "unengaged review-thread finding" "a thread carrying our own reply is left to the write-back"

echo "# …and so is a thread a fixer or a sitting answered through pr-post.sh"
# A pr-post.sh reply carries the city's mark and not the write-back's marker. It
# is the reply the rework work order asks for, so it engages the thread the same
# way a write-back reply does.
store "[$(anchor UT7 168 "$UTCUT")]"
printf '%s' "$(prview 168 OPEN CLEAN MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_168.json"
printf '%s\n' '[{"id":100,"user":{"login":"gc-city-bot"},"body":"finding","pull_request_review_id":null,"created_at":"2026-10-06T12:00:00Z"},{"id":101,"user":{"login":"gc-city-bot"},"body":"Fixed on the branch; it reaches this PR with its push.\n\n<!-- gc:city -->","pull_request_review_id":null,"created_at":"2026-10-07T12:00:00Z"}]' > "$GH_DIR/comments_168.json"
echo '[]' > "$GH_DIR/reviews_168.json"
printf '%s\n' '{"reviews":[],"threads":[{"id":"T-168","isResolved":false,"viewerCanResolve":true,"comments":{"nodes":[{"id":"NC-168","databaseId":100,"author":{"login":"gc-city-bot"},"body":"finding","reactionGroups":[]},{"id":"NC-168b","databaseId":101,"author":{"login":"gc-city-bot"},"body":"Fixed on the branch; it reaches this PR with its push.\n\n<!-- gc:city -->","reactionGroups":[]}]}}]}' > "$GH_DIR/threads_168.json"
out=$(run)
hasnt "$out" "unengaged review-thread finding" "a thread holding a pr-post.sh reply is engaged"
eq "$(meta UT7 pr_unengaged_threads)" "<absent>" "…and no head watermark is written"

echo "# a live child already on the anchor owns the follow-up — no second signal, no thread read"
store "[$(anchor UT4 63 "$UTCUT"), {\"id\":\"rw-63\",\"status\":\"open\",\"assignee\":\"\",\"notes\":\"\",\"title\":\"Address review comments on PR#63\",\"metadata\":{\"anchor_bead\":\"UT4\"}}]"
printf '%s' "$(prview 63 OPEN CLEAN MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_63.json"
printf '%s\n' '[{"id":100,"user":{"login":"gc-city-bot"},"body":"finding","pull_request_review_id":null,"created_at":"2026-10-06T12:00:00Z"}]' > "$GH_DIR/comments_63.json"
echo '[]' > "$GH_DIR/reviews_63.json"
printf '%s\n' '{"reviews":[],"threads":[{"id":"T-63","isResolved":false,"viewerCanResolve":true,"comments":{"nodes":[{"id":"NC-63","databaseId":100,"author":{"login":"gc-city-bot"},"body":"finding","reactionGroups":[]}]}}]}' > "$GH_DIR/threads_63.json"
mark=$(( $(wc -l < "$STUB_GH_LOG") + 1 ))
out=$(run)
hasnt "$out" "unengaged review-thread finding" "an in-flight child on the anchor suppresses the backstop"
hasnt "$(gh_since "$mark")" "graphql" "…and the threads are not even read"

echo "# a thread read that fails files nothing — the backstop fails closed"
store "[$(anchor UT5 64 "$UTCUT")]"
printf '%s' "$(prview 64 OPEN CLEAN MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_64.json"
printf '%s\n' '[{"id":100,"user":{"login":"gc-city-bot"},"body":"finding","pull_request_review_id":null,"created_at":"2026-10-06T12:00:00Z"}]' > "$GH_DIR/comments_64.json"
echo '[]' > "$GH_DIR/reviews_64.json"
printf '%s\n' '{"reviews":[],"threads":[{"id":"T-64","isResolved":false,"viewerCanResolve":true,"comments":{"nodes":[{"id":"NC-64","databaseId":100,"author":{"login":"gc-city-bot"},"body":"finding","reactionGroups":[]}]}}]}' > "$GH_DIR/threads_64.json"
out=$(STUB_GQL_READ_FAIL=1 run)
hasnt "$out" "unengaged review-thread finding" "an unreadable thread read flags nothing"
eq "$(meta UT5 pr_unengaged_threads)" "<absent>" "…and writes no head watermark"
# …and in the PRE-MERGE posture pass the same unreadable read holds the merge: a
# read that did not answer is not proof of zero threads, so the posture stays
# uncurrent (never review_required, which merge.sh would wave through) and
# --posture-only exits non-zero for refinery-reconcile to hold merge.sh.
out=$(STUB_GQL_READ_FAIL=1 run_posture); rc=$?
eq "$rc" 1 "…and the pre-merge posture pass holds the merge (posture uncurrent, exits non-zero)"
has "$out" "posture is not current" "…naming the anchor merge must not read this pass"
eq "$(meta UT5 pr_posture)" "<absent>" "…recording no review_required posture merge.sh would clear against"

fi # part writeback

# ==== part checks: merge-hold order, the Conversation tab, red required checks,
# self-heal, review re-requests, the route-comments-only pass, the status:
# label and pacing ====
if part checks; then

echo "# ORDER: the merge-hold is set in the PRE-MERGE posture pass, not after merge"
# refinery-reconcile runs pr-facts --posture-only, then merge.sh, then the full
# pr-facts. merge.sh reads posture off the bead and holds only on commented@; it
# never reads threads. So a clean green PR with an unresolved thread under a
# pre-cutover review of ours
# has to read `commented` after --posture-only ALONE — before merge.sh runs —
# and the posture pass must dispatch nothing. The full pass that follows files
# the one visit the hold stands for; a later posture pass holds off that standing
# visit without re-reading the threads.
store "[$(anchor UT6 66 "$UTCUT")]"
printf '%s' "$(prview 66 OPEN CLEAN MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_66.json"
printf '%s\n' '[{"id":100,"user":{"login":"gc-city-bot"},"body":"**Review finding 1/1** fix this","pull_request_review_id":null,"created_at":"2026-10-06T12:00:00Z"}]' > "$GH_DIR/comments_66.json"
echo '[]' > "$GH_DIR/reviews_66.json"
printf '%s\n' '{"reviews":[],"threads":[{"id":"T-66","isResolved":false,"viewerCanResolve":true,"comments":{"nodes":[{"id":"NC-66","databaseId":100,"author":{"login":"gc-city-bot"},"body":"**Review finding 1/1** fix this","reactionGroups":[]}]}}]}' > "$GH_DIR/threads_66.json"
out=$(run_posture)
eq "$(meta_pinned UT6 pr_posture)" "commented@sha-66" "the posture pass records the merge-hold before merge.sh runs"
eq "$(jq '[.[] | select(((.metadata.escalation_key // "") | tostring) | startswith("pr-unengaged-threads"))] | length' "$STUB_STORE")" "0" "…and dispatches no visit — that is a routing pass's"
eq "$(meta UT6 pr_unengaged_threads)" "<absent>" "…and writes no head watermark yet"
out=$(run)
has "$out" "unengaged review-thread finding" "the full pass that follows files the one visit"
eq "$(meta UT6 pr_unengaged_threads)" "sha-66" "…and watermarks the head"
mark=$(( $(wc -l < "$STUB_GH_LOG") + 1 ))
out=$(run_posture)
eq "$(meta_pinned UT6 pr_posture)" "commented@sha-66" "a standing visit keeps the merge held on the next posture pass"
hasnt "$(gh_since "$mark")" "graphql" "…without re-reading the threads"

# A conflicting anchor whose `commented` posture stands for unengaged review
# threads owes feedback exactly as one holding an unanswered batch does. The
# CONFLICTING arm ends every anchor's visit it acts on, and the unengaged visit
# is filed behind it, so an arm reading only the unanswered batch as owed either
# files a merge-in over the threads (approved) or waits for an approval
# (unapproved), and in both cases the threads are routed nowhere.
# ut_fixture <num>: one unresolved thread under an unmarked pre-cutover post of
# the city's login, the shape an operator-run review leaves.
ut_fixture() {
  printf '%s\n' '[{"id":100,"user":{"login":"gc-city-bot"},"body":"**Review finding 1/1** fix this","pull_request_review_id":null,"created_at":"2026-10-06T12:00:00Z"}]' > "$GH_DIR/comments_$1.json"
  printf '{"reviews":[],"threads":[{"id":"T-%s","isResolved":false,"viewerCanResolve":true,"comments":{"nodes":[{"id":"NC-%s","databaseId":100,"author":{"login":"gc-city-bot"},"body":"**Review finding 1/1** fix this","reactionGroups":[]}]}}]}\n' "$1" "$1" > "$GH_DIR/threads_$1.json"
}
ut_visits() { jq --arg a "$1" '[ .[] | select(((.metadata.escalation_key // "") | tostring) | startswith("pr-unengaged-threads")) | select(((.metadata["gc.continuation_group"] // "") | tostring) == $a) ] | length' "$STUB_STORE"; }
merge_ins() { jq --arg a "$1" '[ .[] | select((.metadata.anchor_bead // "") == $a) | select((.metadata.rejection_reason // "") | test("stale base")) ] | length' "$STUB_STORE"; }

echo "# an approved CONFLICTING PR with unengaged threads gets their visit first, not a merge-in"
store "[$(anchor UC1 175 "$UTCUT")]"
printf '%s' "$(prview 175 OPEN DIRTY CONFLICTING)" | jq -c '.reviewDecision = "APPROVED"' > "$GH_DIR/pr_view_175.json"
approve 175
ut_fixture 175
: > "$STUB_SESSION_LOG"
out=$(run)
has "$out" "PR#175 has 1 unengaged review-thread finding(s); filed visit" "the conflicting PR's threads are routed to their visit"
eq "$(ut_visits UC1)" "1" "…exactly one visit"
eq "$(meta UC1 pr_unengaged_threads)" "sha-175" "…and the head is watermarked"
eq "$(merge_ins UC1)" "0" "…and no merge-in child is filed over the threads it would not answer"
hasnt "$(cat "$STUB_SESSION_LOG")" "wake $FIX" "…and the fix pool is not woken"
eq "$(meta_pinned UC1 pr_posture)" "commented@sha-175" "…while the posture holds the merge"

echo "# …once the visit stands, the next pass brings the approved branch current"
# The visit covers the threads, so nothing is owed: the conflict is the merge-in's
# again. The open visit keeps the posture `commented` and the merge held, and no
# second visit is filed for the same head.
: > "$STUB_SESSION_LOG"
out=$(run)
has "$out" "PR#175 conflicts with 'main'; filed merge-mode rework" "the merge-in is filed once the threads are routed"
eq "$(merge_ins UC1)" "1" "…exactly one merge-in child"
eq "$(ut_visits UC1)" "1" "…and still exactly one visit"
eq "$(meta_pinned UC1 pr_posture)" "commented@sha-175" "…while the open visit keeps the merge held"

echo "# an unapproved CONFLICTING PR with unengaged threads gets their visit, not a wait for approval"
store "[$(anchor UC2 176 "$UTCUT")]"
printf '%s' "$(prview 176 OPEN DIRTY CONFLICTING)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_176.json"
echo '[]' > "$GH_DIR/reviews_176.json"
ut_fixture 176
out=$(run)
has "$out" "PR#176 has 1 unengaged review-thread finding(s); filed visit" "the threads are routed while the PR waits for an approval"
hasnt "$out" "PR#176 conflicts but no external approval stands" "…the approval gate does not end the anchor's visit first"
eq "$(meta UC2 pr_unengaged_threads)" "sha-176" "…and the head is watermarked"
eq "$(merge_ins UC2)" "0" "…and no merge-in child is filed for the unapproved PR"

echo "# the early routing pass files the unengaged visit of a CONFLICTING PR"
# --route-comments-only routes operator feedback ahead of the slow arms, and an
# operator-run review under the city's login is operator feedback.
store "[$(anchor UC3 177 "$UTCUT")]"
printf '%s' "$(prview 177 OPEN DIRTY CONFLICTING)" | jq -c '.reviewDecision = "APPROVED"' > "$GH_DIR/pr_view_177.json"
approve 177
ut_fixture 177
out=$("$SUT" --route-comments-only --fix-pool "$FIX" 2>&1)
has "$out" "PR#177 has 1 unengaged review-thread finding(s); filed visit" "the early routing pass files the visit"
eq "$(meta UC3 pr_unengaged_threads)" "sha-177" "…and watermarks the head"
eq "$(merge_ins UC3)" "0" "…and files no merge-in child"
has "$out" "route-comments-only — 1 postures recorded, 0 comment batches routed, 1 flagged-to-human" "…and its summary counts the visit"

echo "# Conversation tab: an operator issue comment files a rework child on its own watermark"
# The sweep read only reviews and inline comments, so operator direction posted
# as an ISSUE comment routed nowhere. Its ids are a separate space, so it earns
# its own watermark rather than sharing the inline mark's.
store "[$(anchor IC1 92)]"
printf '%s' "$(prview 92 OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_92.json"
echo '[]' > "$GH_DIR/reviews_92.json"
echo '[]' > "$GH_DIR/comments_92.json"
printf '[{"id":770001,"user":{"login":"human1"},"body":"Rework: split the sweep into its own function"}]' > "$GH_DIR/issue_comments_92.json"
out=$(run)
has "$out" "watermark: review 0, comment 0, issue 770001" "the issue comment routes and advances its own mark"
CID=$(jq -r '[.[] | select(.id | startswith("new-"))][0].id // ""' "$STUB_STORE")
eq "$(meta IC1 pr_issue_comment_watermark)" "770001" "the issue watermark advances to the comment"
eq "$(meta IC1 pr_comment_watermark)" "0" "…the inline mark is untouched"
eq "$(meta IC1 pr_review_watermark)" "0" "…and the review mark is untouched"
eq "$(meta_pinned IC1 pr_posture)" "commented@sha-92" "…the merge is held as commented, not left progressing"
eq "$(meta IC1 pr_comment_disposition)" "rework:$CID" "…the disposition names the child"
eq "$(meta "$CID" anchor_bead)" "IC1" "the child is stamped to its anchor"
eq "$(meta "$CID" 'gc.routed_to')" "$FIX" "…routed to the fix pool"
eq "$(meta "$CID" task_kind)" "rework" "…as a rework"
has "$(jq -r --arg c "$CID" '.[] | select(.id == $c) | .title' "$STUB_STORE")" "issue 770001" "the title carries the issue coordinate"
has "$(jq -r --arg c "$CID" '.[] | select(.id == $c) | .description' "$STUB_STORE")" "## Conversation comments" "the body renders the conversation section"
has "$(jq -r --arg c "$CID" '.[] | select(.id == $c) | .description' "$STUB_STORE")" "split the sweep into its own function" "…carrying the operator's words verbatim"
grep -qxF "$CID|blocks|IC1" "$STUB_DEPS" && ok "…and it holds the merge via a blocks edge" || bad "blocks edge missing"

echo "# …idempotent: the same conversation batch mints no twin and moves no mark"
out=$(run)
# The batch also opens a validation pass, a second new- bead, so count only the
# rework child — the twin this guards against — not every new- bead.
eq "$(jq '[.[] | select(.id | startswith("new-")) | select((.metadata.task_kind // "") == "rework")] | length' "$STUB_STORE")" "1" "still exactly one child (the validation pass is a separate bead)"
eq "$(meta IC1 pr_issue_comment_watermark)" "770001" "…and the mark holds"

echo "# …a newer conversation comment above the mark re-fires"
printf '[{"id":770001,"user":{"login":"human1"},"body":"old"},{"id":770002,"user":{"login":"human1"},"body":"and one more thing"}]' > "$GH_DIR/issue_comments_92.json"
out=$(run)
has "$out" "issue 770002" "the newer conversation comment routes"
eq "$(meta IC1 pr_issue_comment_watermark)" "770002" "…and the mark advances past it"

echo "# …our own conversation comment is not feedback and routes nothing"
store "[$(anchor IC2 93)]"
printf '%s' "$(prview 93 OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_93.json"
echo '[]' > "$GH_DIR/reviews_93.json"
echo '[]' > "$GH_DIR/comments_93.json"
printf '[{"id":880001,"user":{"login":"gc-city-bot"},"body":"landed abc123\\n\\n<!-- gc:city -->"}]' > "$GH_DIR/issue_comments_93.json"
out=$(run)
eq "$(jq '[.[] | select(.id | startswith("new-"))] | length' "$STUB_STORE")" "0" "our own conversation comment mints no child"
hasnt "$out" "feedback history unreadable" "…read off a Conversation list that read cleanly"
eq "$(meta IC2 pr_issue_comment_watermark)" "<absent>" "…and moves no mark"

echo "# …an unreadable Conversation read holds the posture rather than clearing it"
# Reviews and inline comments read clean; only the Conversation space breaks. A
# clean posture written here would let merge.sh through over an unread comment,
# which is the very failure the fix exists to stop, so the pass records nothing.
store "[$(anchor IC3 94)]"
printf '%s' "$(prview 94 OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_94.json"
echo '[]' > "$GH_DIR/reviews_94.json"
echo '[]' > "$GH_DIR/comments_94.json"
printf '[{"id":990001,"user":{"login":"human1"},"body":"decide X"}]' > "$GH_DIR/issue_comments_94.json"
out=$(STUB_ISSUE_LIST_RC=1 run)
has "$out" "feedback history unreadable" "the unreadable Conversation read defers the pass"
eq "$(meta IC3 pr_posture)" "<absent>" "…and records no clean posture over the unread comment"

echo "# required-contexts-for is one block, shared byte-for-byte with merge.sh"
# The red-check arm routes on the same gating set merge.sh holds a merge on, so
# the two carry one copy of the resolver between markers; drift would let the
# cadence route on a different set than the merge holds on.
rcf() { awk '/^[[:space:]]*# >>> required-contexts-for[[:space:]]*$/{inb=1;next} /^[[:space:]]*# <<< required-contexts-for[[:space:]]*$/{inb=0} inb' "$1"; }
[ -n "$(rcf "$HERE/pr-facts.sh")" ] && ok "block present here" || bad "block missing from pr-facts.sh"
eq "$(rcf "$HERE/pr-facts.sh")" "$(rcf "$HERE/merge.sh")" "…byte-identical to merge.sh's copy"

echo "# a red required check -> ONE rework child to the fix pool"
# When a required check has terminally failed on a PR that every other arm has
# waved through, this arm files one rework child. `test` is required by branch
# protection and has terminally FAILED at the head; no feedback is unanswered.
printf '[{"type":"required_status_checks","parameters":{"required_status_checks":[{"context":"test"}]}}]' > "$GH_DIR/rules_main.json"
store "[$(anchor RC1 50)]"
printf '%s' "$(prview 50 OPEN UNSTABLE MERGEABLE ',"statusCheckRollup":[{"name":"test","status":"COMPLETED","conclusion":"FAILURE","detailsUrl":"https://github.com/zook/gc-toolkit/actions/runs/999"}]')" > "$GH_DIR/pr_view_50.json"
out=$(run)
has "$out" "required check(s) failing (test); filed merge-mode rework new-2 routed to $FIX" "the red required check is turned into a routed rework child"
eq "$(meta new-2 task_kind)" "rework" "child carries the rework role marker"
eq "$(meta new-2 anchor_bead)" "RC1" "child names the anchor it belongs to"
eq "$(meta RC1 task_kind)" "<absent>" "…and the anchor carries none, so the marker discriminates"
eq "$(meta new-2 branch)" "polecat/x50" "child resumes the head branch"
eq "$(meta new-2 target)" "main" "child targets the base"
eq "$(meta new-2 merge_strategy)" "mr" "child is mr-mode"
eq "$(meta new-2 existing_pr)" "https://github.com/zook/gc-toolkit/pull/50" "child reworks THIS PR, opening no second one"
eq "$(meta new-2 prepare_mode)" "merge" "every branch shape is brought current by merge, polecat/* included"
eq "$(meta new-2 'gc.routed_to')" "$FIX" "child routed to the fix pool"
has "$(meta new-2 rejection_reason)" "head sha-50" "the rejection reason names the head (the dedup key)"
has "$(meta new-2 rejection_reason)" "test" "…names the failing check"
has "$(meta new-2 rejection_reason)" "actions/runs/999" "…and carries the run log url"
grep -qxF "new-2|blocks|RC1" "$STUB_DEPS" && ok "child blocks the anchor" || bad "blocks edge missing"
eq "$(meta RC1 merge_result)" "pull_request" "the anchor keeps gating (no state flip)"

echo "# …dedup: an open child at this head suppresses a twin (rework OR review)"
out=$(run)
has "$out" "already covers this head, no new child" "the second pass files nothing"
eq "$(jq '[.[] | select(.id | startswith("new-"))] | length' "$STUB_STORE")" "1" "still exactly one child"

echo "# …a live review child (keyed on anchor_bead, not this branch) also stands the arm down"
# Built inline, not via child(): a later block reuses that name for a 2-arg
# helper, and this dedup keys on anchor_bead, which that shape does not carry.
RCK_REVIEW='{"id":"RCK","status":"in_progress","assignee":"rig/gc-toolkit.polecat-codex","notes":"","title":"Review PR#51","metadata":{"anchor_bead":"RC2","task_kind":"review","branch":"polecat/x51","gc.routed_to":"rig/gc-toolkit.polecat-codex"}}'
store "[$(anchor RC2 51),$RCK_REVIEW]"
printf '%s' "$(prview 51 OPEN UNSTABLE MERGEABLE ',"statusCheckRollup":[{"name":"test","status":"COMPLETED","conclusion":"FAILURE"}]')" > "$GH_DIR/pr_view_51.json"
out=$(run)
has "$out" "child RCK already covers this head, no new child" "an in-flight review on the anchor suppresses the red-check dispatch"
eq "$(jq '[.[] | select(.id | startswith("new-"))] | length' "$STUB_STORE")" "0" "…and no rework child is minted"

echo "# …a PENDING required check has not failed — nothing is routed"
store "[$(anchor RC3 52)]"
printf '%s' "$(prview 52 OPEN UNSTABLE MERGEABLE ',"statusCheckRollup":[{"name":"test","status":"IN_PROGRESS","conclusion":null,"detailsUrl":"https://x/runs/2"}]')" > "$GH_DIR/pr_view_52.json"
out=$(run)
hasnt "$out" "required check(s) failing" "a still-running required check is left for a later pass"
eq "$(jq '[.[] | select(.id | startswith("new-"))] | length' "$STUB_STORE")" "0" "…and no rework child is minted"

echo "# …a MISSING required check is ambiguous with not-started — nothing is routed"
store "[$(anchor RC4 53)]"
printf '%s' "$(prview 53 OPEN UNSTABLE MERGEABLE ',"statusCheckRollup":[]')" > "$GH_DIR/pr_view_53.json"
out=$(run)
eq "$(jq '[.[] | select(.id | startswith("new-"))] | length' "$STUB_STORE")" "0" "a required context with no run files no rework"

echo "# …a GREEN required check files nothing, even with an advisory check red"
store "[$(anchor RC5 54)]"
printf '%s' "$(prview 54 OPEN UNSTABLE MERGEABLE ',"statusCheckRollup":[{"name":"test","status":"COMPLETED","conclusion":"SUCCESS"},{"name":"lint","status":"COMPLETED","conclusion":"FAILURE"}]')" > "$GH_DIR/pr_view_54.json"
out=$(run)
eq "$(jq '[.[] | select(.id | startswith("new-"))] | length' "$STUB_STORE")" "0" "only a failing REQUIRED check routes; the advisory one is left alone"

echo "# …an operator merge_hold files no red-check rework (the anchor is theirs)"
store "[$(anchor RC6 55 ',"merge_hold":"true"')]"
printf '%s' "$(prview 55 OPEN UNSTABLE MERGEABLE ',"statusCheckRollup":[{"name":"test","status":"COMPLETED","conclusion":"FAILURE"}]')" > "$GH_DIR/pr_view_55.json"
out=$(run)
eq "$(jq '[.[] | select(.id | startswith("new-"))] | length' "$STUB_STORE")" "0" "a held anchor dispatches nothing"

echo "# …and an armed re-dispatch files no red-check rework either — the branch is superseded (tk-79ffoh)"
# GH_DIR fixtures outlive the per-case store reset, so PR#75's feedback batch
# from upthread is still present; clear it so this case exercises the red-check
# arm alone. Feedback on an armed anchor is FA2's case, where it routes to a
# visit and opens a validation pass that this plain new- count would catch.
rm -f "$GH_DIR/comments_75.json" "$GH_DIR/reviews_75.json"
store "[$(anchor FA3 75 ',"gc.dispatch_when_ready":"rig/gc-toolkit.polecat"')]"
printf '%s' "$(prview 75 OPEN UNSTABLE MERGEABLE ',"statusCheckRollup":[{"name":"test","status":"COMPLETED","conclusion":"FAILURE"}]')" > "$GH_DIR/pr_view_75.json"
out=$(run)
eq "$(jq '[.[] | select(.id | startswith("new-"))] | length' "$STUB_STORE")" "0" "an armed anchor dispatches no red-check rework"

echo "# …and the SAME anchor without the arm files one — the arm is the only thing standing the red check down"
store "[$(anchor FA3 75)]"
out=$(run)
has "$out" "required check(s) failing (test); filed merge-mode rework" "with no arm, the red check dispatches a rework"
eq "$(jq '[.[] | select(.id | startswith("new-"))] | length' "$STUB_STORE")" "1" "…exactly one child, now that nothing holds it"

echo "# …a BLOCKED PR on a red required check routes too (the filed incident's state)"
store "[$(anchor RC8 57)]"
printf '%s' "$(prview 57 OPEN BLOCKED MERGEABLE ',"statusCheckRollup":[{"name":"test","status":"COMPLETED","conclusion":"FAILURE","detailsUrl":"https://x/runs/5"}]')" > "$GH_DIR/pr_view_57.json"
out=$(run)
has "$out" "required check(s) failing (test); filed" "a BLOCKED PR whose block is a red required check is routed, not left to idle"
eq "$(meta new-2 anchor_bead)" "RC8" "…as a rework child of the blocked anchor"
rm -f "$GH_DIR/rules_main.json"

echo "# …atomic birth: a red-check child that keeps its branch but drops rejection_reason is UNMADE"
printf '[{"type":"required_status_checks","parameters":{"required_status_checks":[{"context":"test"}]}}]' > "$GH_DIR/rules_main.json"
store "[$(anchor AB2 71)]"
printf '%s' "$(prview 71 OPEN UNSTABLE MERGEABLE ',"statusCheckRollup":[{"name":"test","status":"COMPLETED","conclusion":"FAILURE"}]')" > "$GH_DIR/pr_view_71.json"
out=$(STUB_DROP_KEYS="new-2:rejection_reason" run)
has "$out" "could not form the red-check rework for PR#71" "the red-check arm refuses to route a child it could not fully form"
eq "$(bstatus new-2)" "closed" "the veto-capable-but-unrescuable newborn is unmade"
eq "$(meta new-2 gc.outcome)" "abandoned" "…and marked abandoned"
eq "$(jq '[.[] | select((.metadata.task_kind // "") == "rework") | select(.status == "open") | select((.metadata.rejection_reason // "") == "")] | length' "$STUB_STORE")" "0" "no OPEN red-check rework child survives able to veto but missing rejection_reason"
rm -f "$GH_DIR/rules_main.json"

# ---- self-heal reap: a rework child the branch has outrun, now green, is moot ----
# The merge-lane analogue of the self-heal the reconcile lane already does. Reaps
# ONLY a provably-dead premise: head moved past the cited head AND the current
# head is mergeable with every required check green. Heads are full 40-hex,
# because the reap extracts a git SHA (the harness's sha-<num> is not hex).
RW_OLDHEAD=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
RW_NEWHEAD=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
rwchild() { # id anchor num citedhead [status] [assignee] [reason-override]
  local reason="Required check(s) failing on PR#$3 at head $4: test."
  [ -n "${7:-}" ] && reason="$7"
  printf '{"id":"%s","status":"%s","assignee":"%s","notes":"","issue_type":"task","title":"Fix failing required check(s) on PR#%s:","metadata":{"task_kind":"rework","anchor_bead":"%s","branch":"polecat/x%s","rejection_reason":"%s","prepare_mode":"merge","merge_strategy":"mr","pr_number":"%s","pr_url":"https://github.com/zook/gc-toolkit/pull/%s","gc.routed_to":"%s"}}' \
    "$1" "${5:-open}" "${6:-}" "$3" "$2" "$3" "$reason" "$3" "$3" "$FIX"
}
reapview() { # num — an OPEN, MERGEABLE PR, required check green, current head = RW_NEWHEAD
  printf '%s' "$(prview "$1" OPEN CLEAN MERGEABLE ',"statusCheckRollup":[{"name":"test","status":"COMPLETED","conclusion":"SUCCESS"}]')" \
    | jq -c --arg h "$RW_NEWHEAD" '.headRefOid = $h' > "$GH_DIR/pr_view_$1.json"
}
reap_req() { printf '[{"type":"required_status_checks","parameters":{"required_status_checks":[{"context":"test"}]}}]' > "$GH_DIR/rules_main.json"; }

echo "# self-heal: a rework child whose cited head the branch has outrun, now green + mergeable, is reaped as moot"
reap_req
store "[$(anchor RP1 60),$(rwchild RW1 RP1 60 "$RW_OLDHEAD")]"
reapview 60
out=$(run)
has "$out" "reaped moot rework child RW1" "the moot child is reaped"
eq "$(bstatus RW1)" "closed" "the reaped child is closed"
eq "$(meta RW1 gc.outcome)" "moot" "the reaped child is marked moot"
has "$out" "1 moot reworks reaped" "the run tally counts the reap"
echo "# …and a second pass is a no-op — a closed child is never re-reaped (idempotent)"
out=$(run)
hasnt "$out" "reaped moot rework child RW1" "a closed child is not re-reaped"
rm -f "$GH_DIR/rules_main.json"

echo "# self-heal: a child is NOT reaped while the required check is still red at the current head (fail closed)"
reap_req
store "[$(anchor RP2 61),$(rwchild RW2 RP2 61 "$RW_OLDHEAD")]"
printf '%s' "$(prview 61 OPEN UNSTABLE MERGEABLE ',"statusCheckRollup":[{"name":"test","status":"COMPLETED","conclusion":"FAILURE"}]')" \
  | jq -c --arg h "$RW_NEWHEAD" '.headRefOid = $h' > "$GH_DIR/pr_view_61.json"
out=$(run)
hasnt "$out" "reaped moot rework child RW2" "a red check at the current head is not a dead premise"
eq "$(bstatus RW2)" "open" "the child is left open"
rm -f "$GH_DIR/rules_main.json"

echo "# self-heal: a child still citing the LIVE head is left OPEN (premise not falsified)"
reap_req
store "[$(anchor RP3 62),$(rwchild RW3 RP3 62 "$RW_NEWHEAD")]"
reapview 62
out=$(run)
hasnt "$out" "reaped moot rework child RW3" "a child at the live head is not moot"
eq "$(bstatus RW3)" "open" "the child is left open"
rm -f "$GH_DIR/rules_main.json"

echo "# self-heal: an in_progress (worker-held) rework child is never auto-reaped (open-only)"
reap_req
store "[$(anchor RP4 63),$(rwchild RW4 RP4 63 "$RW_OLDHEAD" in_progress worker-sess)]"
reapview 63
out=$(run)
hasnt "$out" "reaped moot rework child RW4" "an in_progress child is left for its holder"
eq "$(bstatus RW4)" "in_progress" "the held child is untouched"
rm -f "$GH_DIR/rules_main.json"

echo "# self-heal: a child whose reason names no head is ambiguous -> left OPEN (fail closed)"
reap_req
store "[$(anchor RP5 64),$(rwchild RW5 RP5 64 "$RW_OLDHEAD" open "" "the base was rewritten and PR#64 conflicts with main but no head is recorded here")]"
reapview 64
out=$(run)
hasnt "$out" "reaped moot rework child RW5" "no cited head -> mootness unprovable -> left open"
eq "$(bstatus RW5)" "open" "the child is left open"
rm -f "$GH_DIR/rules_main.json"

echo "# self-heal: a comment-rework child is never reaped on head-moved+green (its premise is unanswered feedback, not the head)"
reap_req
store "[$(anchor RP7 66),$(rwchild RW7 RP7 66 "$RW_OLDHEAD" open "" "Review feedback on PR#66 is unanswered at head $RW_OLDHEAD. Answer every item.")]"
reapview 66
out=$(run)
hasnt "$out" "reaped moot rework child RW7" "a comment-rework premise is not settled by a green check"
eq "$(bstatus RW7)" "open" "the comment-rework child is left open"
rm -f "$GH_DIR/rules_main.json"

echo "# self-heal: a moved-past child is NOT reaped when no required contexts are configured (green unprovable -> fail closed)"
rm -f "$GH_DIR/rules_main.json"
store "[$(anchor RP6 65),$(rwchild RW6 RP6 65 "$RW_OLDHEAD")]"
reapview 65
out=$(run)
hasnt "$out" "reaped moot rework child RW6" "no required contexts -> green cannot be proven -> left open"
eq "$(bstatus RW6)" "open" "the child is left open"

# ---- non-code / infra exclusion: a failure no code change can fix parks -------
# The arm routes a fixer only at a GENUINE code failure. A required check that
# timed out, was cancelled, failed to start, or is a deploy-type platform is a
# non-code cause — a code-fix polecat would fix nothing — so the anchor is
# parked to a human (gc.routed_to=human, the stand-down the arm already honors,
# with the takeaway the board shows as what the person owes, both in one
# lifecycle.sh update) and a pr-fix-noncode visit is filed. A park whose write
# does not read back files no visit. no_rework counts only new REWORK children:
# the escalate stub mints the visit as a new- bead too, which is not a dispatch.
no_rework() { jq '[.[] | select(.id | startswith("new-")) | select((.metadata.task_kind // "") == "rework")] | length' "$STUB_STORE"; }

echo "# a TIMED_OUT required check parks to a human and dispatches no fixer"
printf '[{"type":"required_status_checks","parameters":{"required_status_checks":[{"context":"test"}]}}]' > "$GH_DIR/rules_main.json"
store "[$(anchor NC1 110)]"
printf '%s' "$(prview 110 OPEN UNSTABLE MERGEABLE ',"statusCheckRollup":[{"name":"test","status":"COMPLETED","conclusion":"TIMED_OUT"}]')" > "$GH_DIR/pr_view_110.json"
: > "$STUB_ESC_LOG"; : > "$STUB_GC_LOG"
out=$(run)
has "$out" "non-code cause; parked to human" "the timeout is named a non-code cause and parked"
eq "$(meta NC1 'gc.routed_to')" "human" "the anchor is parked to a human"
has "$(meta NC1 'gc.takeaway')" "PR#110 has a required check failing for a non-code cause" "…with a takeaway naming what the person owes"
eq "$(meta NC1 'gc.takeaway_settled')" "" "…left unsettled, because a person still owes it"
eq "$(grep '^bd update NC1 ' "$STUB_GC_LOG" | grep -F 'gc.routed_to=human' | grep -cF 'gc.takeaway=PR#110' || true)" "1" "…written in the same update as the route"
eq "$(no_rework)" "0" "no fixer is dispatched at a non-code failure"
has "$(cat "$STUB_ESC_LOG")" "--subject NC1 --key pr-fix-noncode.110" "a non-code park files its visit"
eq "$(meta NC1 merge_result)" "pull_request" "the anchor keeps gating (the merge still waits)"

echo "# …a park whose route does not read back files no visit and retries next pass"
store "[$(anchor NC6 115)]"
printf '%s' "$(prview 115 OPEN UNSTABLE MERGEABLE ',"statusCheckRollup":[{"name":"test","status":"COMPLETED","conclusion":"TIMED_OUT"}]')" > "$GH_DIR/pr_view_115.json"
: > "$STUB_ESC_LOG"
out=$(STUB_DROP_KEYS="NC6:gc.routed_to" run)
has "$out" "parking the anchor to human did not land (retry next pass)" "a write that reported success without landing the route is not a park"
hasnt "$(cat "$STUB_ESC_LOG")" "pr-fix-noncode.115" "…so no visit is filed for a park that did not happen"
eq "$(no_rework)" "0" "…and no fixer is dispatched either"

echo "# …CANCELLED and STARTUP_FAILURE park the same way"
store "[$(anchor NC2 111)]"
printf '%s' "$(prview 111 OPEN UNSTABLE MERGEABLE ',"statusCheckRollup":[{"name":"test","status":"COMPLETED","conclusion":"CANCELLED"}]')" > "$GH_DIR/pr_view_111.json"
out=$(run)
eq "$(meta NC2 'gc.routed_to')" "human" "a cancelled required check parks"
eq "$(no_rework)" "0" "…and dispatches no fixer"
store "[$(anchor NC3 112)]"
printf '%s' "$(prview 112 OPEN UNSTABLE MERGEABLE ',"statusCheckRollup":[{"name":"test","status":"COMPLETED","conclusion":"STARTUP_FAILURE"}]')" > "$GH_DIR/pr_view_112.json"
out=$(run)
eq "$(meta NC3 'gc.routed_to')" "human" "a startup-failure required check parks"
eq "$(no_rework)" "0" "…and dispatches no fixer"

echo "# …a deploy-type required check (Vercel) FAILURE parks — the name marks it non-code, FAILURE notwithstanding"
store "[$(anchor NC4 113)]"
printf '[{"type":"required_status_checks","parameters":{"required_status_checks":[{"context":"Vercel"}]}}]' > "$GH_DIR/rules_main.json"
printf '%s' "$(prview 113 OPEN UNSTABLE MERGEABLE ',"statusCheckRollup":[{"name":"Vercel","status":"COMPLETED","conclusion":"FAILURE"}]')" > "$GH_DIR/pr_view_113.json"
: > "$STUB_ESC_LOG"
out=$(run)
eq "$(meta NC4 'gc.routed_to')" "human" "a deploy-type FAILURE parks rather than routing a code-fixer"
eq "$(no_rework)" "0" "…and dispatches no fixer"
has "$(cat "$STUB_ESC_LOG")" "--key pr-fix-noncode.113" "…and files the non-code park visit"

echo "# …a genuine code FAILURE still dispatches, even alongside a non-code failure, naming only the code check"
store "[$(anchor NC5 114)]"
printf '[{"type":"required_status_checks","parameters":{"required_status_checks":[{"context":"test"},{"context":"Vercel"}]}}]' > "$GH_DIR/rules_main.json"
printf '%s' "$(prview 114 OPEN UNSTABLE MERGEABLE ',"statusCheckRollup":[{"name":"test","status":"COMPLETED","conclusion":"FAILURE"},{"name":"Vercel","status":"COMPLETED","conclusion":"FAILURE"}]')" > "$GH_DIR/pr_view_114.json"
out=$(run)
has "$out" "required check(s) failing (test); filed" "a code failure routes a fixer even when a deploy check is also red"
eq "$(meta NC5 'gc.routed_to')" "" "…and the anchor is NOT parked (a code fix is owed)"
RCFIX_NC5=$(jq -r '[.[] | select(.id | startswith("new-")) | select((.metadata.task_kind // "") == "rework") | .id][0] // empty' "$STUB_STORE")
has "$(meta "$RCFIX_NC5" rejection_reason)" "head sha-114" "the dispatched child names the head"
hasnt "$(meta "$RCFIX_NC5" rejection_reason)" "Vercel" "…and the rework reason names only the code check, not the deploy one"
rm -f "$GH_DIR/rules_main.json"

# ---- attempt cap: a stuck PR stops drawing fixers and parks to a human --------
# Each red-check child names "head <oid>" in its title and its rejection_reason,
# so the distinct prior hex heads across this anchor's children are the attempts
# made. Under the cap the arm keeps dispatching; at the cap it parks the anchor to a
# human rather than churn another fixer. Heads are full 40-hex because the count
# extracts a git SHA, the same reason the reap fixtures above use hex.
CAPH1=1111111111111111111111111111111111111111
CAPH2=2222222222222222222222222222222222222222
CAPH3=3333333333333333333333333333333333333333
CAPHX=4444444444444444444444444444444444444444
rcredview() { # num head — OPEN UNSTABLE, required "test" FAILURE at the given hex head
  printf '%s' "$(prview "$1" OPEN UNSTABLE MERGEABLE ',"statusCheckRollup":[{"name":"test","status":"COMPLETED","conclusion":"FAILURE"}]')" \
    | jq -c --arg h "$2" '.headRefOid = $h' > "$GH_DIR/pr_view_$1.json"
}

echo "# under the cap (2 prior red heads): the 3rd still-red head dispatches the 3rd fixer"
reap_req
store "[$(anchor CAP1 120),$(rwchild CK1 CAP1 120 "$CAPH1" closed),$(rwchild CK2 CAP1 120 "$CAPH2" closed)]"
rcredview 120 "$CAPHX"
out=$(run)
has "$out" "required check(s) failing (test); filed" "with 2 prior attempts, the 3rd red head still dispatches"
eq "$(meta CAP1 'gc.routed_to')" "" "…and the anchor is not parked under the cap"
eq "$(no_rework)" "1" "…exactly one new fixer"
rm -f "$GH_DIR/rules_main.json"

echo "# at the cap (3 prior red heads): the 4th still-red head parks to a human, dispatches nothing"
reap_req
store "[$(anchor CAP2 121),$(rwchild CK3 CAP2 121 "$CAPH1" closed),$(rwchild CK4 CAP2 121 "$CAPH2" closed),$(rwchild CK5 CAP2 121 "$CAPH3" closed)]"
rcredview 121 "$CAPHX"
: > "$STUB_ESC_LOG"; : > "$STUB_GC_LOG"
out=$(run)
has "$out" "reached the cap (3)" "the arm names the cap it hit"
eq "$(meta CAP2 'gc.routed_to')" "human" "the stuck anchor is parked to a human"
has "$(meta CAP2 'gc.takeaway')" "PR#121 is still red after 3 auto-fix attempts" "…with a takeaway naming the PR and the attempts it drew"
eq "$(grep '^bd update CAP2 ' "$STUB_GC_LOG" | grep -F 'gc.routed_to=human' | grep -cF 'gc.takeaway=PR#121' || true)" "1" "…written in the same update as the route"
eq "$(no_rework)" "0" "…and no fourth fixer is dispatched"
has "$(cat "$STUB_ESC_LOG")" "--subject CAP2 --key pr-fix-capped.121" "…and the cap park files its visit"
eq "$(meta CAP2 merge_result)" "pull_request" "…while the anchor keeps gating"

echo "# …nothing lowers the count: a person clearing the route on a still-red PR sees it parked again"
jq -c 'map(if .id == "CAP2" then .metadata["gc.routed_to"] = "" else . end)' "$STUB_STORE" > "$TMP/cap2.json" && mv "$TMP/cap2.json" "$STUB_STORE"
out=$(run)
eq "$(meta CAP2 'gc.routed_to')" "human" "the next red pass parks the anchor again"
eq "$(no_rework)" "0" "…and still dispatches no fixer"
rm -f "$GH_DIR/rules_main.json"

echo "# …the cap counts DISTINCT heads: three children at ONE prior head is one attempt, not three"
reap_req
store "[$(anchor CAP3 122),$(rwchild CK6 CAP3 122 "$CAPH1" closed),$(rwchild CK7 CAP3 122 "$CAPH1" closed),$(rwchild CK8 CAP3 122 "$CAPH1" closed)]"
rcredview 122 "$CAPHX"
out=$(run)
has "$out" "required check(s) failing (test); filed" "three children at one prior head count as a single attempt, so the arm still dispatches"
eq "$(meta CAP3 'gc.routed_to')" "" "…and does not park"
rm -f "$GH_DIR/rules_main.json"

# A worked child as the live flow leaves it. Resuming a rework (mol-polecat-work's
# rejected-branch-resume block) and the refinery's landed-on-branch close
# (mol-refinery-patrol's one-anchor-per-pr-terminal) both unset its
# rejection_reason, so the head it was sent to fix survives only in the title the
# arm minted it with.
rwchild_worked() { # id anchor num head
  printf '{"id":"%s","status":"closed","assignee":"rig/refinery","notes":"","issue_type":"task","title":"Fix failing required check(s) on PR#%s: required check red at head %s","metadata":{"task_kind":"rework","anchor_bead":"%s","branch":"polecat/x%s","prepare_mode":"merge","merge_strategy":"mr","pr_number":"%s","pr_url":"https://github.com/zook/gc-toolkit/pull/%s"}}' \
    "$1" "$3" "$4" "$2" "$3" "$3" "$3"
}

echo "# …the cap counts a worked child by the head in its title, since working it cleared its rejection_reason"
reap_req
store "[$(anchor CAP4 123),$(rwchild_worked CK9 CAP4 123 "$CAPH1"),$(rwchild_worked CK10 CAP4 123 "$CAPH2"),$(rwchild_worked CK11 CAP4 123 "$CAPH3")]"
rcredview 123 "$CAPHX"
: > "$STUB_ESC_LOG"
out=$(run)
has "$out" "reached the cap (3)" "three worked children with no rejection_reason are three attempts"
eq "$(meta CAP4 'gc.routed_to')" "human" "…so the anchor parks to a human"
eq "$(no_rework)" "0" "…and no fourth fixer is dispatched"
rm -f "$GH_DIR/rules_main.json"

echo "# …a worked child at the CURRENT head is not a prior attempt"
reap_req
store "[$(anchor CAP5 124),$(rwchild_worked CK12 CAP5 124 "$CAPH1"),$(rwchild_worked CK13 CAP5 124 "$CAPH2"),$(rwchild_worked CK14 CAP5 124 "$CAPHX")]"
rcredview 124 "$CAPHX"
out=$(run)
hasnt "$out" "reached the cap" "two prior heads plus one child at the current head stay under the cap"
eq "$(meta CAP5 'gc.routed_to')" "" "…and the anchor is not parked"
rm -f "$GH_DIR/rules_main.json"

# ---- per-review dismissal + re-request once a human review's findings clear ----
# The peer-model write-back above answers each finding; this closes the loop at
# the review level. A human CHANGES_REQUESTED is GitHub's own block and stands
# until cleared, so once every finding one review raised has closed — fixed and
# landed, or declined and answered — pr-facts dismisses THAT review (clearing the
# block) and re-requests its author, per-review via finding.review_id. The
# confidence is the validator's, carried by the closed findings; a dismissal is
# not an approval. wview.reviews is served from the .reviews of threads_<n>.json.
rfind() { # id anchor review_id disposition [status]
  printf '{"id":"%s","status":"%s","assignee":"","notes":"","title":"finding[human]: %s","metadata":{"task_kind":"finding","anchor_bead":"%s","finding.lane":"human","finding.disposition":"%s","finding.source":"human:johnzook","finding.review_id":"%s"}}' \
    "$1" "${5:-closed}" "$1" "$2" "$4" "$3"
}
hreview() { # num review-databaseId state — a threads fixture carrying one human review
  printf '{"reviews":[{"id":"R%s","databaseId":%s,"state":"%s","author":{"login":"johnzook"}}],"threads":[]}' "$2" "$2" "$3"
}

echo "# a human review is dismissed and its author re-requested once all its findings clear"
store "[$(anchor HR1 140 "$(wb_meta rework:HRC1)"), $(child HRC1 closed), $(rfind HF1 HR1 555 must-fix), $(rfind HF2 HR1 555 declined)]"
printf '%s' "$(prview 140 OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_140.json"
threads 140 "$(hreview 140 555 CHANGES_REQUESTED)"
: > "$STUB_GH_LOG"
out=$(run)
has "$(cat "$STUB_GH_LOG")" "DISMISS repos/zook/gc-toolkit/pulls/140/reviews/555/dismissals" "the human review is dismissed once all its findings clear"
has "$(cat "$STUB_GH_LOG")" "REREQUEST repos/zook/gc-toolkit/pulls/140/requested_reviewers" "…and a fresh review is requested"
has "$(cat "$STUB_GH_LOG")" "reviewers[]=johnzook" "…from the review's own author"
has "$(cat "$STUB_GH_LOG")" "addressed by a change" "the dismiss message names the comment resolved by a change"
has "$(cat "$STUB_GH_LOG")" "resolved by an accepted decline" "…and the one resolved by an accepted decline"
has "$out" "dismissed human review 555 and re-requested johnzook" "the pass reports the per-review dismissal"

echo "# …but not while one of that review's findings is still open"
store "[$(anchor HR2 141 "$(wb_meta rework:HRC2)"), $(child HRC2 closed), $(rfind HF3 HR2 556 must-fix), $(rfind HF4 HR2 556 must-fix open)]"
printf '%s' "$(prview 141 OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_141.json"
threads 141 "$(hreview 141 556 CHANGES_REQUESTED)"
: > "$STUB_GH_LOG"
out=$(run)
hasnt "$(cat "$STUB_GH_LOG")" "DISMISS" "an open finding (an unfixed must-fix) keeps the review standing"
hasnt "$(cat "$STUB_GH_LOG")" "REREQUEST" "…and the author is not re-requested"

echo "# …nor while a needs-you finding holds the review open for the operator's ruling"
store "[$(anchor HR2b 146 "$(wb_meta rework:HRC2b)"), $(child HRC2b closed), $(rfind HF3b HR2b 561 declined), $(rfind HF4b HR2b 561 needs-you open)]"
printf '%s' "$(prview 146 OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_146.json"
threads 146 "$(hreview 146 561 CHANGES_REQUESTED)"
: > "$STUB_GH_LOG"
out=$(run)
hasnt "$(cat "$STUB_GH_LOG")" "DISMISS" "a needs-you finding deliberately holds the review changes-requested"
hasnt "$(cat "$STUB_GH_LOG")" "REREQUEST" "…and the author is not re-requested until the operator rules the visit"

echo "# …a review already DISMISSED is left alone — its state is the idempotency"
store "[$(anchor HR3 142 "$(wb_meta rework:HRC3)"), $(child HRC3 closed), $(rfind HF5 HR3 557 declined)]"
printf '%s' "$(prview 142 OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_142.json"
threads 142 "$(hreview 142 557 DISMISSED)"
: > "$STUB_GH_LOG"
out=$(run)
hasnt "$(cat "$STUB_GH_LOG")" "DISMISS" "an already-dismissed review is not dismissed again"
hasnt "$(cat "$STUB_GH_LOG")" "REREQUEST" "…nor its author re-requested again"

echo "# …a re-request the API refuses holds the dismissal — both are in scope"
store "[$(anchor HR4 143 "$(wb_meta rework:HRC4)"), $(child HRC4 closed), $(rfind HF6 HR4 558 declined)]"
printf '%s' "$(prview 143 OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_143.json"
threads 143 "$(hreview 143 558 CHANGES_REQUESTED)"
: > "$STUB_GH_LOG"
out=$(STUB_REREQUEST_RC=1 run)
has "$(cat "$STUB_GH_LOG")" "REREQUEST repos/zook/gc-toolkit/pulls/143/requested_reviewers" "the re-request is attempted"
hasnt "$(cat "$STUB_GH_LOG")" "DISMISS" "…and a re-request that fails holds the dismissal"

echo "# a review under our own login that is feedback is dismissed with no re-request"
# A model review run on the city's account after the cutover is feedback, so its
# findings route and clear like a person's. Its author is the acting login, and
# GitHub refuses a re-request of the PR's author, so the refused re-request here
# would hold the dismissal on every pass if the arm made it.
store "[$(anchor HR9 149 "$(wb_meta rework:HRC9)"',"pr_provenance_since":"2026-10-07T00:00:00Z"'), $(child HRC9 closed), $(rfind HF11 HR9 564 must-fix)]"
printf '%s' "$(prview 149 OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_149.json"
threads 149 '{"reviews":[{"id":"R564","databaseId":564,"state":"CHANGES_REQUESTED","author":{"login":"gc-city-bot"},"body":"model review: fix the race","submittedAt":"2026-10-07T03:00:00Z"}],"threads":[]}'
: > "$STUB_GH_LOG"
out=$(STUB_REREQUEST_RC=1 run)
has "$(cat "$STUB_GH_LOG")" "DISMISS repos/zook/gc-toolkit/pulls/149/reviews/564/dismissals" "the city-account review is dismissed once its findings clear"
hasnt "$(cat "$STUB_GH_LOG")" "REREQUEST" "…with no re-request of our own login"
has "$(cat "$STUB_GH_LOG")" "no fresh review is requested" "…and the dismiss message says none is requested"
has "$out" "dismissed review 564, posted under our own login, with no re-request" "the pass reports the dismissal without a re-request"
hasnt "$out" "could not re-request" "…and never reports a refused re-request"

# ---- a declined finding's owed reply gates its review's dismissal ---------------
# A declined human finding closes when the validator stamps its answer
# (finding.reply), which is before the reply/resolve arm has delivered that answer
# and marked it finding.reply_posted=1. So closure alone must not make the review
# dismissable: dismissing then would clear CHANGES_REQUESTED before the decline
# reached the reviewer. This finding carries both its review id and its owed reply.
rfindreply() { # id anchor review_id comment_id [reply_posted]
  printf '{"id":"%s","status":"closed","assignee":"","notes":"","title":"finding[human]: %s","metadata":{"task_kind":"finding","anchor_bead":"%s","finding.lane":"human","finding.disposition":"declined","finding.source":"human:johnzook","finding.review_id":"%s","finding.comment_id":"%s","finding.reply":"declined on the merits"%s}}' \
    "$1" "$1" "$2" "$3" "$4" "${5:+,\"finding.reply_posted\":\"$5\"}"
}

echo "# a declined finding whose owed reply has not landed holds its review's dismissal"
store "[$(anchor HR5 144 "$(wb_meta rework:HRC5)"), $(child HRC5 closed), $(rfindreply HF7 HR5 559 100)]"
printf '%s' "$(prview 144 OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_144.json"
threads 144 "$(jq -cn --argjson r "$(hreview 144 559 CHANGES_REQUESTED)" --argjson t "$(one_thread 144)" '{reviews: $r.reviews, threads: $t.threads}')"
: > "$STUB_GH_LOG"
out=$(STUB_RESOLVE_RC=1 run)
eq "$(meta HF7 finding.reply_posted)" "<absent>" "the resolve failed, so the decline reply is not yet marked delivered"
hasnt "$(cat "$STUB_GH_LOG")" "DISMISS" "an undelivered decline reply holds the review's dismissal"
hasnt "$(cat "$STUB_GH_LOG")" "REREQUEST" "…and the author is not re-requested"

echo "# …and once that reply is delivered (finding.reply_posted=1) the review is dismissed"
store "[$(anchor HR6 145 "$(wb_meta rework:HRC6)"), $(child HRC6 closed), $(rfindreply HF8 HR6 560 101 1)]"
printf '%s' "$(prview 145 OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_145.json"
threads 145 "$(hreview 145 560 CHANGES_REQUESTED)"
: > "$STUB_GH_LOG"
out=$(run)
has "$(cat "$STUB_GH_LOG")" "DISMISS repos/zook/gc-toolkit/pulls/145/reviews/560/dismissals" "a delivered decline reply lets the review dismiss"
has "$(cat "$STUB_GH_LOG")" "REREQUEST repos/zook/gc-toolkit/pulls/145/requested_reviewers" "…and its author is re-requested"
has "$(cat "$STUB_GH_LOG")" "resolved by an accepted decline" "…the dismiss message names the accepted decline"

# ---- a deferred finding's owed reply gates its review's dismissal the same way --
# A deferred finding closes when the validator rules it, but it owes its raiser
# the follow-up id before the review is cleared — the same reply_posted gate the
# decline rides, extended to the deferral. Once delivered the review dismisses,
# and the dismiss message names the deferral, not a bare "resolved".
rfinddeferred() { # id anchor review_id comment_id [reply_posted]
  printf '{"id":"%s","status":"closed","assignee":"","notes":"","title":"finding[human]: y","metadata":{"task_kind":"finding","anchor_bead":"%s","finding.lane":"human","finding.disposition":"deferred","finding.source":"human:johnzook","finding.review_id":"%s","finding.comment_id":"%s","finding.reply":"Deferred — tracked as follow-up tk-fup9. It will be picked up after this merges."%s}}' \
    "$1" "$2" "$3" "$4" "${5:+,\"finding.reply_posted\":\"$5\"}"
}

echo "# a deferred finding whose follow-up reply has not landed holds its review's dismissal"
store "[$(anchor HR7 147 "$(wb_meta rework:HRC7)"), $(child HRC7 closed), $(rfinddeferred HF9 HR7 562 100)]"
printf '%s' "$(prview 147 OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_147.json"
threads 147 "$(jq -cn --argjson r "$(hreview 147 562 CHANGES_REQUESTED)" --argjson t "$(one_thread 147)" '{reviews: $r.reviews, threads: $t.threads}')"
: > "$STUB_GH_LOG"
out=$(STUB_RESOLVE_RC=1 run)
eq "$(meta HF9 finding.reply_posted)" "<absent>" "the resolve failed, so the deferral reply is not yet marked delivered"
hasnt "$(cat "$STUB_GH_LOG")" "DISMISS" "an undelivered deferral reply holds the review's dismissal"

echo "# …and once the deferral reply is delivered (finding.reply_posted=1) the review is dismissed"
store "[$(anchor HR8 148 "$(wb_meta rework:HRC8)"), $(child HRC8 closed), $(rfinddeferred HF10 HR8 563 101 1)]"
printf '%s' "$(prview 148 OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_148.json"
threads 148 "$(hreview 148 563 CHANGES_REQUESTED)"
: > "$STUB_GH_LOG"
out=$(run)
has "$(cat "$STUB_GH_LOG")" "DISMISS repos/zook/gc-toolkit/pulls/148/reviews/563/dismissals" "a delivered deferral reply lets the review dismiss"
has "$(cat "$STUB_GH_LOG")" "tracked as a follow-up for after the merge" "…the dismiss message names the deferral"

# ---- --route-comments-only: route operator feedback early in the pass ----------
# --posture-only stamps commented/changes_requested on the pre-merge tick, and
# the full arm routes only at the pass TAIL. A pass the timeout killed in between
# would leave the feedback stamped-as-seen yet unrouted. This mode routes early:
# it does the SAME routing the full arm does, then stops — no write-back sweep,
# no MERGED/CLOSED reconciliation, none of the non-feedback arms.
# The `new-N` bead counter is high this late in the run, so the child id is read
# back from the store rather than assumed.
run_route() { "$SUT" --route-comments-only --fix-pool "$FIX" 2>&1; }

echo "# --route-comments-only: an unanswered comment is routed to a fix-pool child"
store "[$(anchor RC1 66)]"
printf '%s' "$(prview 66 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_66.json"
echo '[]' > "$GH_DIR/reviews_66.json"
printf '[{"id":6601,"user":{"login":"human1"},"body":"please change this","path":"a.sh"}]' > "$GH_DIR/comments_66.json"
: > "$STUB_SESSION_LOG"
out=$(run_route); rc=$?
eq "$rc" 0 "a route-comments-only pass exits 0"
has "$out" "route-comments-only" "the summary names the mode"
eq "$(meta_pinned RC1 pr_posture)" "commented@sha-66" "posture is still recorded (the arm re-reads it to route)"
rc1_child=$(jq -r '[ .[] | select((.metadata.task_kind // "") == "rework") | .id ][0] // "<none>"' "$STUB_STORE")
eq "$(meta RC1 pr_comment_disposition)" "rework:$rc1_child" "the comment is routed on the early tick, disposition recorded"
eq "$(meta RC1 pr_comment_watermark)" "6601" "…and the watermark advanced to the routed comment"
eq "$(meta "$rc1_child" anchor_bead)" "RC1" "the child names the anchor"
eq "$(meta "$rc1_child" task_kind)" "rework" "…and carries its role marker"
eq "$(meta "$rc1_child" 'gc.routed_to')" "$FIX" "…and is routed to the fix pool"
has "$(cat "$STUB_SESSION_LOG")" "wake $FIX" "the fix pool is woken"
eq "$(vpass_id RC1)" "$(jq -r '[ .[] | select((.metadata.task_kind // "") == "validation") | .id ][0] // "<none>"' "$STUB_STORE")" \
  "the batch opens its validation pass here too, exactly as the full arm does"

echo "# …a human hold routes the same batch to a visit, early (the full arm's choice)"
store "[$(anchor RC2 67 ',"merge_hold":"true"')]"
printf '%s' "$(prview 67 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_67.json"
echo '[]' > "$GH_DIR/reviews_67.json"
printf '[{"id":6701,"user":{"login":"human1"},"body":"hmm"}]' > "$GH_DIR/comments_67.json"
: > "$STUB_ESC_LOG"; : > "$STUB_SESSION_LOG"
out=$(run_route)
eq "$(meta RC2 pr_comment_disposition | sed 's/visit:.*/visit/')" "visit" "a held anchor's feedback goes to a visit, on the early tick"
has "$(cat "$STUB_ESC_LOG")" "merge_hold is set" "…and the visit records why no work could be routed"
hasnt "$(cat "$STUB_SESSION_LOG")" "wake $FIX" "…no work routed under the hold"

echo "# …route-comments-only does NOT run the write-back sweep (the full pass owns it)"
store "[$(anchor RC3 68 "$(wb_meta rework:KX)"), $(child KX open)]"
printf '%s' "$(prview 68 OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_68.json"
threads 68 "$(one_thread 68)"
out=$(run_route)
eq "$(reacted 68 NC-68)" "false" "no EYES reaction: the write-back sweep did not run in route mode"
hasnt "$out" "comments acknowledged" "…and the route summary reports no write-back"
# Control: the full pass on the SAME fixture reacts, so the false above is the
# mode's doing, not a fixture that could never react.
out=$(run)
eq "$(reacted 68 NC-68)" "true" "the full pass reacts on the same fixture, proving it discriminates"

echo "# …and MERGED/CLOSED reconciliation is left to the full pass, like --posture-only"
store "[$(anchor RC4 69)]"
printf '%s' "$(prview 69 MERGED CLEAN MERGEABLE)" > "$GH_DIR/pr_view_69.json"
out=$(run_route)
hasnt "$out" "is MERGED" "a merged PR is not reconciled by the feedback arm"
eq "$(bstatus RC4)" "open" "…the anchor is left exactly as it was"
eq "$(meta RC4 merge_result)" "pull_request" "…with its state untouched"
out=$(run)
has "$out" "PR#69 is MERGED" "the full pass still records it"
eq "$(bstatus RC4)" "closed" "…and closes the anchor"

echo "# …a CONFLICTING anchor is deferred to the full pass — no conflict-rework early"
store "[$(anchor RC9 152)]"
printf '%s' "$(prview 152 OPEN DIRTY CONFLICTING)" > "$GH_DIR/pr_view_152.json"
approve 152
: > "$STUB_SESSION_LOG"
out=$(run_route)
eq "$(jq '[.[] | select(.id | startswith("new-")) | select((.metadata.task_kind // "") == "rework")] | length' "$STUB_STORE")" "0" \
  "route-comments-only files no conflict-rework (the full pass owns it)"
hasnt "$(cat "$STUB_SESSION_LOG")" "wake $FIX" "…and does not wake the fix pool"
eq "$(meta RC9 merge_result)" "pull_request" "…the anchor is left gating, untouched"
# Control: the full pass on the SAME fixture dispatches the rework, so the skip
# above is route mode's doing, not a fixture that could never dispatch.
out=$(run)
eq "$(jq '[.[] | select(.id | startswith("new-")) | select((.metadata.task_kind // "") == "rework")] | length' "$STUB_STORE")" "1" \
  "the full pass dispatches the conflict-rework on the same fixture"

echo "# …but a CONFLICTING anchor WITH feedback is routed early — not deferred while it conflicts (tk-f9x2nb, #861)"
# The complement of RC9: route-comments-only still files no merge-in child, but a
# conflicting anchor that owes feedback now falls through to the feedback arm and
# routes it, so operator feedback is picked up before the merge rather than
# starved until the branch stops conflicting.
store "[$(anchor CF2 161)]"
printf '%s' "$(prview 161 OPEN DIRTY CONFLICTING)" | jq -c '.reviewDecision = "CHANGES_REQUESTED"' > "$GH_DIR/pr_view_161.json"
echo '[]' > "$GH_DIR/reviews_161.json"
printf '[{"id":16100,"user":{"login":"human1"},"body":"one more thing"}]' > "$GH_DIR/comments_161.json"
: > "$STUB_SESSION_LOG"
out=$(run_route)
has "$(meta CF2 pr_comment_disposition)" "rework:" "route-comments-only routes the conflicting anchor's feedback early"
eq "$(jq '[.[] | select((.metadata.rejection_reason // "") | test("stale base"))] | length' "$STUB_STORE")" "0" \
  "…and files no merge-in child (the full pass owns that; the feedback child brings the branch current)"
VP2=$(vpass_id CF2)
hasnt "$VP2" "<none>" "…and opens the validation pass, exactly as the full arm does"
has "$(cat "$STUB_SESSION_LOG")" "wake $FIX" "…and wakes the fix pool"

echo "# …a retargeted anchor is deferred to the full pass — no early transition or escalation"
store "[$(anchor RC10 153)]"
printf '%s' "$(prview 153 OPEN CLEAN MERGEABLE)" | jq -c '.baseRefName = "release"' > "$GH_DIR/pr_view_153.json"
: > "$STUB_ESC_LOG"
out=$(run_route)
eq "$(meta RC10 merge_result)" "pull_request" \
  "route-comments-only does not transition a retargeted anchor (the full pass owns it)"
hasnt "$(cat "$STUB_ESC_LOG")" "pr-retargeted.153" "…and files no retarget escalation early"
# Control: the full pass on the SAME fixture retargets, proving the skip is route mode's doing.
out=$(run)
eq "$(meta RC10 merge_result)" "retargeted" "the full pass retargets on the same fixture"

# ---- the status: label moves in the arm that records a review ----------------
# A human's review changes the label's inputs in the early arms: --posture-only
# records the new posture value, and --route-comments-only routes the feedback
# into live work on the anchor. Each re-derives the label there, so the PR list
# shows the review without waiting for the full pass at the tail. These cases run
# the real writer over the real derivation (gctk pr-status, from the binary
# harness_build_gctk built), so the label read back off the PR fixture is what
# the shared code path decided. The scripts dir carries no label writer, so
# elsewhere in this file pr-facts.sh's best-effort label call finds nothing to
# run. A wrapper that execs the real writer is put there for these cases and
# removed after them.
echo "# the status: label moves in the arm that records a review"
printf '#!/usr/bin/env bash\nexec %q "$@"\n' "$HERE/pr-status-label.sh" > "$SD/pr-status-label.sh"
chmod +x "$SD/pr-status-label.sh"
# The labels on a PR view fixture, sorted and comma-joined.
pv_labels() { jq -r '[.labels[]?.name] | sort | join(",")' "$GH_DIR/pr_view_$1.json"; }

echo "# …an approval recorded by --posture-only moves the label in that arm"
store "[$(anchor LB1 170 ',"pr_posture":"review_required@sha-170@2026-10-01T00:00:00Z","pr_merge_state":"CLEAN@sha-170"')]"
prview 170 OPEN CLEAN MERGEABLE | jq -c '.reviewDecision = "APPROVED" | .labels = [{name: "status: needs-review"}]' > "$GH_DIR/pr_view_170.json"
printf '[{"id":17001,"user":{"login":"human1"},"state":"APPROVED","body":"ship it","commit_id":"sha-170"}]' > "$GH_DIR/reviews_170.json"
out=$(run_posture); rc=$?
eq "$rc" 0 "the posture-only pass exits 0"
eq "$(meta_pinned LB1 pr_posture)" "approved@sha-170" "the approval is recorded as the posture"
eq "$(pv_labels 170)" "status: working" "…and the label leaves needs-review in the same arm: an approved PR is the city's to merge"

echo "# …a merge state moving under an unchanged posture leaves the label to the full pass"
# The label is deliberately wrong for the anchor's state, so any derivation would
# rewrite it. GitHub reports UNKNOWN while it computes mergeability, so this move
# is the common posture write, and re-deriving on it would cost one per PR.
store "[$(anchor LB2 171 ',"pr_posture":"review_required@sha-171@2026-10-01T00:00:00Z","pr_merge_state":"UNKNOWN@sha-171"')]"
prview 171 OPEN BLOCKED MERGEABLE | jq -c '.reviewDecision = "REVIEW_REQUIRED" | .labels = [{name: "status: working"}]' > "$GH_DIR/pr_view_171.json"
: > "$STUB_GH_LOG"
out=$(run_posture)
eq "$(meta LB2 pr_merge_state)" "BLOCKED@sha-171" "the moved merge state is recorded"
eq "$(pv_labels 171)" "status: working" "…but the label is not re-derived for it"
hasnt "$(cat "$STUB_GH_LOG")" "pr edit 171" "…so nothing is written to the PR"
# Control: the full pass reconciles the same fixture, so the label above stood
# because the posture-only pass did not derive it, not because it was right.
out=$(run)
eq "$(pv_labels 171)" "status: needs-review" "the full pass's reconcile corrects it on the same fixture"

echo "# …a change request routed by --route-comments-only moves the label in that arm"
store "[$(anchor LB3 172)]"
prview 172 OPEN BLOCKED MERGEABLE | jq -c '.reviewDecision = "CHANGES_REQUESTED" | .labels = [{name: "status: needs-review"}]' > "$GH_DIR/pr_view_172.json"
printf '[{"id":17201,"user":{"login":"human1"},"state":"CHANGES_REQUESTED","body":"rename this flag","commit_id":"sha-172","submitted_at":"2026-10-05T00:00:00Z"}]' > "$GH_DIR/reviews_172.json"
out=$(run_posture)
eq "$(meta_pinned LB3 pr_posture)" "changes_requested@sha-172" "--posture-only records the change request"
eq "$(pv_labels 172)" "status: needs-review" "…and the label stays, because nothing is acting on the PR yet"
out=$(run_route)
has "$(meta LB3 pr_comment_disposition)" "rework:" "--route-comments-only routes the batch into a rework child"
eq "$(pv_labels 172)" "status: working" "…and the label moves to working in the same arm"

echo "# …the full pass re-derives after its own posture write, over the label its sweep just wrote"
# The sweep at the top of the anchor writes needs-review off the posture the bead
# still carries. The approval the same pass then records has to move the label
# again, and that works only if the second call reads the PR's labels afresh
# rather than the list the pass read before its sweep changed them.
store "[$(anchor LB4 173 ',"pr_posture":"review_required@sha-173@2026-10-01T00:00:00Z","pr_merge_state":"CLEAN@sha-173"')]"
prview 173 OPEN CLEAN MERGEABLE | jq -c '.reviewDecision = "APPROVED" | .labels = [{name: "status: working"}]' > "$GH_DIR/pr_view_173.json"
: > "$STUB_GH_LOG"
out=$(run)
has "$(cat "$STUB_GH_LOG")" "pr edit 173 --repo github.com/zook/gc-toolkit --add-label status: needs-review" "the sweep writes needs-review off the recorded posture first"
eq "$(meta_pinned LB4 pr_posture)" "approved@sha-173" "the same pass then records the approval"
eq "$(pv_labels 173)" "status: working" "…and the label follows the approval, not the value the sweep wrote"

rm -f "$SD/pr-status-label.sh"

echo "# with GC_RECONCILE_BD_CACHE set, a rework mint invalidates the dedup so a re-probe files no twin"
# A CONFLICTING anchor mints one rework child; mint_rework_child drops the
# per-pass bd_list cache at the create, so a later branch-dedup probe refetches
# and adopts the child instead of reading a stale "no child" and twinning it.
# Two runs over one cache (no between-run clear) isolate that one invalidation:
# the first mints and clears, the second's probe must see the child.
store "[$(anchor F9 19)]"
printf '%s' "$(prview 19 OPEN DIRTY CONFLICTING)" > "$GH_DIR/pr_view_19.json"
approve 19
export GC_RECONCILE_BD_CACHE="$TMP/pf-cache"; mkdir -p "$GC_RECONCILE_BD_CACHE"
run >/dev/null 2>&1          # mints the child, invalidates the cache at the create
run >/dev/null 2>&1          # the branch-dedup probe refetches (invalidated) and sees it
unset GC_RECONCILE_BD_CACHE
twins=$(jq '[ .[] | select(((.metadata.task_kind // "") == "rework") and ((.metadata.branch // "") == "polecat/x19")) ] | length' "$STUB_STORE")
eq "$twins" 1 "the mint invalidates the per-pass cache, so the second pass's dedup sees the child and files no twin"

fi # part checks

# ==== part pacing: the paced walks, their visit order, and the posture basis ====
if part pacing; then

# One node of the batched open-PR read, matching prview's PR for the same number.
open_node() { # num [mergeState] [reviewDecision] [jq-edit]
  printf '{"number":%s,"state":"OPEN","isDraft":false,"url":"https://github.com/zook/gc-toolkit/pull/%s","headRefName":"polecat/x%s","headRefOid":"sha-%s","baseRefName":"main","isCrossRepository":false,"headRepository":{"name":"gc-toolkit"},"headRepositoryOwner":{"login":"zook"},"reviewDecision":"%s","mergeStateStatus":"%s","updatedAt":"2026-10-01T00:00:00Z","reviews":{"totalCount":0,"nodes":[]},"comments":{"totalCount":0,"nodes":[]}}' \
    "$1" "$1" "$1" "$1" "${3:-}" "${2:-CLEAN}" | jq -c "${4:-.}"
}
open_prs() { local IFS=,; printf '[%s]' "$*" > "$GH_DIR/open_prs.json"; }
pf_views() { grep -o '^pr view [0-9]*' "$STUB_GH_LOG" | awk '{print $3}' | awk '!seen[$0]++' | paste -sd, -; }
FAR() { echo "$(( $(date +%s) + 600 ))"; }

echo "# pacing: --deadline stops the per-anchor walk after one anchor and --cursor resumes after it"
# Three clean OPEN PRs, enumerated out of id order. A deadline of epoch 1 has
# always passed, so a paced pass reads exactly one PR; the posture-only mode
# ignores the pacing pair, because merge.sh needs every posture current.
store "[$(anchor PP3 83), $(anchor PP1 81), $(anchor PP2 82)]"
for n in 81 82 83; do printf '%s' "$(prview "$n" OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_$n.json"; done
open_prs "$(open_node 81)" "$(open_node 82)" "$(open_node 83)"
PFCUR="$TMP/pr-facts.cursor"; rm -f "$PFCUR" "$PFCUR".*
: > "$STUB_GH_LOG"
out=$("$SUT" --route-comments-only --fix-pool "$FIX" --deadline 1 --cursor "$PFCUR" 2>&1)
eq "$(pf_views)" "81" "a passed deadline reads the lowest id's PR and no other"
has "$out" "visited 1 of 3 PR anchors (0 needing action first) before the deadline; the next pass resumes at PP2" "…and names where the next pass resumes"
eq "$(cat "$PFCUR" 2>/dev/null)" "PP1" "the cursor records the anchor finished"
: > "$STUB_GH_LOG"
out=$("$SUT" --fix-pool "$FIX" --deadline 1 --cursor "$PFCUR" 2>&1)
eq "$(pf_views)" "82" "the full mode resumes after the cursor the same way"
: > "$STUB_GH_LOG"
out=$("$SUT" --posture-only --deadline 1 --cursor "$PFCUR" 2>&1)
eq "$(pf_views)" "83,81,82" "the posture-only mode reads every PR, in the enumerated order, whatever pacing it is handed"
hasnt "$out" "visited " "…and reports no pacing"

echo "# pacing: an anchor the walk skips for free does not spend its one visit past the deadline"
# PQ1 names no PR number, so the walk passes it without a read. It leads the
# rotation and the deadline has passed, so the visit the walk is owed goes to
# PQ2.
store "[$(anchor PQ1 x), $(anchor PQ2 84)]"
printf '%s' "$(prview 84 OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_84.json"
open_prs "$(open_node 84)"
rm -f "$PFCUR" "$PFCUR".*
: > "$STUB_GH_LOG"
out=$("$SUT" --route-comments-only --fix-pool "$FIX" --deadline 1 --cursor "$PFCUR" 2>&1)
eq "$(pf_views)" "84" "the visit goes to the first anchor that costs a read"
has "$out" "visited 1 of 2 PR anchors" "…counted once"

echo "# pacing: the write-back sweep rotates on a cursor of its own under the same deadline"
# Three anchors carry a routed comment batch, enumerated out of id order. A
# deadline of epoch 1 has always passed, so the sweep acknowledges one anchor's
# comments per pass, on a rotation apart from the walk's. The PR numbers are
# ones no earlier section uses, and each PR's issue comments are emptied too,
# because the walk visits the same anchors and would route a comment an earlier
# section left behind, which changes what the sweep owes.
store "[$(anchor WP3 193 "$(wb_meta rework:KP3)"), $(anchor WP1 191 "$(wb_meta rework:KP1)"),
        $(anchor WP2 192 "$(wb_meta rework:KP2)"), $(child KP1 open), $(child KP2 open), $(child KP3 open)]"
for n in 191 192 193; do
  printf '%s' "$(prview "$n" OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_$n.json"
  threads "$n" "$(one_thread "$n")"
  printf '[]' > "$GH_DIR/issue_comments_$n.json"
done
open_prs "$(open_node 191)" "$(open_node 192)" "$(open_node 193)"
WBCUR="$TMP/pr-facts-wb.cursor"; rm -f "$WBCUR" "$WBCUR".*
out=$("$SUT" --fix-pool "$FIX" --deadline 1 --cursor "$WBCUR" 2>&1)
eq "$(reacted 191 NC-191),$(reacted 192 NC-192),$(reacted 193 NC-193)" "true,false,false" "past the deadline the sweep still acknowledges one anchor, the lowest id"
has "$out" "write-back visited 1 of 3 anchors with routed comments (0 with something new first) before the deadline; the next pass resumes at WP2" "…and names where the next pass resumes"
eq "$(cat "$WBCUR.writeback" 2>/dev/null)" "WP1" "the sweep records its progress on a cursor of its own"
out=$("$SUT" --fix-pool "$FIX" --deadline 1 --cursor "$WBCUR" 2>&1)
eq "$(reacted 192 NC-192),$(reacted 193 NC-193)" "true,false" "the next pass resumes the sweep after its cursor"
out=$("$SUT" --fix-pool "$FIX" --deadline "$(FAR)" --cursor "$WBCUR" 2>&1)
eq "$(reacted 193 NC-193)" "true" "a deadline that has not passed lets the sweep reach every anchor"
has "$out" "write-back visited 3 of 3 anchors with routed comments" "…and reports the whole sweep"
out=$("$SUT" --fix-pool "$FIX" 2>&1)
hasnt "$out" "write-back visited" "an unpaced pass reports no write-back pacing"

echo "# write-back: an anchor with something new to answer goes ahead of the rotation"
# Every anchor was seen by the sweep above. A watermark moving on WP3 is a
# batch routed since; its live child closing is work that answers one. Each
# puts WP3 ahead of WP1, which the rotation would reach first.
rm -f "$WBCUR" "$WBCUR.writeback" "$WBCUR.writeback.first"
bmut WP3 '.metadata.pr_comment_watermark = "150"'
out=$("$SUT" --fix-pool "$FIX" --deadline 1 --cursor "$WBCUR" 2>&1)
has "$out" "write-back visited 2 of 3 anchors with routed comments (1 with something new first)" "a moved watermark puts the anchor first, and the rest still get their visit"
out=$("$SUT" --fix-pool "$FIX" --deadline "$(FAR)" --cursor "$WBCUR" 2>&1)
has "$out" "(0 with something new first)" "once visited, it rotates with the rest"
bmut KP3 '.status = "closed"'
bmut KP3 '.metadata.anchor_bead = "WP3"'
bmut KP2 '.metadata.anchor_bead = "WP2"'
out=$("$SUT" --fix-pool "$FIX" --deadline "$(FAR)" --cursor "$WBCUR" 2>&1)
has "$out" "(1 with something new first)" "a live child appearing on WP2 moves its mark"
bmut KP2 '.status = "closed"'
out=$("$SUT" --fix-pool "$FIX" --deadline "$(FAR)" --cursor "$WBCUR" 2>&1)
has "$out" "(1 with something new first)" "…and that child closing moves it again"

echo "# posture basis: a PR nothing touched since its posture was derived costs no per-PR read"
store "[$(anchor PB1 301 "$UTCUT"), $(anchor PB2 302 "$UTCUT")]"
for n in 301 302; do printf '%s' "$(prview "$n" OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_$n.json"; done
open_prs "$(open_node 301)" "$(open_node 302)"
BASIS="$TMP/pr-posture.seen"; rm -f "$BASIS"
run_basis() { : > "$STUB_GH_LOG"; "$SUT" --posture-only --seen "$BASIS" 2>&1; }
out=$(run_basis)
eq "$(pf_views)" "301,302" "with no basis yet every posture is read per PR"
has "$out" "0 unchanged since the basis they were derived from, 2 read per PR" "…and the summary says so"
eq "$(meta_pinned PB1 pr_posture),$(meta_pinned PB2 pr_posture)" "none@sha-301,none@sha-302" "…and records each posture"
out=$(run_basis)
eq "$(pf_views)" "301,302" "the next pass derives each posture again, to confirm the basis the first derivation recorded"
has "$out" "0 unchanged since the basis they were derived from, 2 read per PR" "…so it keeps none yet"
out=$(run_basis)
eq "$(pf_views)" "" "the pass after reads no PR whose confirmed basis has not moved"
hasnt "$(cat "$STUB_GH_LOG")" "/pulls/301/" "…and none of its feedback lists"
has "$out" "2 unchanged since the basis they were derived from, 0 read per PR" "…and counts them kept"
eq "$(meta_pinned PB1 pr_posture)" "none@sha-301" "…while the posture stands"

echo "# posture basis: the merge state follows the batched read with no per-PR read"
open_prs "$(open_node 301)" "$(open_node 302 DIRTY)"
out=$(run_basis)
eq "$(pf_views)" "" "a merge state that moved reads no PR"
eq "$(meta PB2 pr_merge_state)" "DIRTY@sha-302" "…and is recorded from the batched read"
eq "$(meta_pinned PB2 pr_posture)" "none@sha-302" "…beside the posture it kept"

echo "# posture basis: a new review, a new comment, a push or a new review decision reads the PR again"
# A PR read for a change is read once more on the pass after, which confirms its
# new basis, so each step settles before the next one moves the other PR.
open_prs "$(open_node 301 CLEAN '' '.reviews = {totalCount: 1, nodes: [{databaseId: 9001}]}')" "$(open_node 302 DIRTY)"
out=$(run_basis)
eq "$(pf_views)" "301" "a review the count shows reads that PR whole; the untouched one is kept"
out=$(run_basis)
eq "$(pf_views)" "301" "…and the pass after reads it once more, to confirm its new basis"
open_prs "$(open_node 301 CLEAN '' '.reviews = {totalCount: 1, nodes: [{databaseId: 9001}]}')" "$(open_node 302 DIRTY '' '.comments = {totalCount: 1, nodes: [{databaseId: 7001}]}')"
out=$(run_basis)
eq "$(pf_views)" "302" "a Conversation comment reads its PR again"
run_basis >/dev/null
open_prs "$(open_node 301 CLEAN '' '.reviews = {totalCount: 1, nodes: [{databaseId: 9001}]} | .updatedAt = "2026-10-02T00:00:00Z"')" "$(open_node 302 DIRTY '' '.comments = {totalCount: 1, nodes: [{databaseId: 7001}]}')"
out=$(run_basis)
eq "$(pf_views)" "301" "an updatedAt that moved reads its PR again"
run_basis >/dev/null
open_prs "$(open_node 301 CLEAN '' '.reviews = {totalCount: 1, nodes: [{databaseId: 9001}]} | .updatedAt = "2026-10-02T00:00:00Z"')" "$(open_node 302 DIRTY APPROVED '.comments = {totalCount: 1, nodes: [{databaseId: 7001}]}')"
out=$(run_basis)
eq "$(pf_views)" "302" "a review decision that moved reads its PR again"
run_basis >/dev/null
printf '%s' "$(prview 301 OPEN CLEAN MERGEABLE | jq -c '.headRefOid = "sha-301b"')" > "$GH_DIR/pr_view_301.json"
open_prs "$(open_node 301 CLEAN '' '.reviews = {totalCount: 1, nodes: [{databaseId: 9001}]} | .updatedAt = "2026-10-02T00:00:00Z" | .headRefOid = "sha-301b"')" "$(open_node 302 DIRTY APPROVED '.comments = {totalCount: 1, nodes: [{databaseId: 7001}]}')"
out=$(run_basis)
eq "$(pf_views)" "301" "a push reads its PR again"
eq "$(meta_pinned PB1 pr_posture)" "none@sha-301b" "…and pins the posture to the new head"
run_basis >/dev/null
out=$(run_basis)
eq "$(pf_views)" "" "with nothing moved, both are kept again"

echo "# posture basis: a watermark or a posture another arm moved reads the PR again"
bmut PB2 '.metadata.pr_issue_comment_watermark = "7001"'
out=$(run_basis)
eq "$(pf_views)" "302" "a watermark the routing advanced reads the PR again"
run_basis >/dev/null
bmut PB1 '.metadata.pr_posture = "commented@sha-301b@2026-10-01T00:00:00Z"'
out=$(run_basis)
eq "$(pf_views)" "301" "a posture the bead no longer carries is derived again, never restored from the basis"
eq "$(meta_pinned PB1 pr_posture)" "none@sha-301b" "…and the derivation records what the PR says"
out=$(run_basis)
eq "$(pf_views)" "301" "…as a candidate the next pass confirms, since another arm read the PR otherwise"
out=$(run_basis)
eq "$(pf_views)" "" "…after which it is kept again"

echo "# posture basis: a derivation is kept only once the next pass derives it again"
# The batched read shows a review on PB6 that the review list does not return
# yet: GitHub answered the two requests from different moments. The first
# derivation reads none and records it only as a candidate, which keeps
# nothing. The next pass derives again, now reads the review, and records it.
store "[$(anchor PB6 306 "$UTCUT")]"
printf '%s' "$(prview 306 OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_306.json"
open_prs "$(open_node 306 CLEAN '' '.reviews = {totalCount: 1, nodes: [{databaseId: 9306}]}')"
rm -f "$BASIS"
out=$(run_basis)
eq "$(meta_pinned PB6 pr_posture)" "none@sha-306" "a review list behind the batched read derives none"
printf '%s\n' '[{"id":9306,"user":{"login":"alice"},"state":"COMMENTED","body":"rename this","submitted_at":"2026-10-07T12:00:00Z"}]' > "$GH_DIR/reviews_306.json"
out=$(run_basis)
eq "$(pf_views)" "306" "the next pass derives the posture again rather than keep the first derivation's"
eq "$(meta_pinned PB6 pr_posture)" "commented@sha-306" "…and records the review it now reads"
rm -f "$GH_DIR/reviews_306.json"

echo "# posture basis: a commented posture, or one an unengaged-thread candidate decided, keeps none"
# PB3 holds an unanswered Conversation comment, so its posture is commented. PB4
# holds a pre-cutover unmarked comment under our own login in a resolved thread:
# no hold, but the answer turned on bead state the PR does not show.
store "[$(anchor PB3 303 "$UTCUT"), $(anchor PB4 304 "$UTCUT")]"
printf '%s' "$(prview 303 OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_303.json"
printf '%s\n' '[{"id":5003,"user":{"login":"alice"},"body":"please rename this","created_at":"2026-10-07T12:00:00Z"}]' > "$GH_DIR/issue_comments_303.json"
printf '%s' "$(prview 304 OPEN CLEAN MERGEABLE)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_304.json"
printf '%s\n' '[{"id":104,"user":{"login":"gc-city-bot"},"body":"**Review finding 1/1** fix this","pull_request_review_id":null,"created_at":"2026-10-06T12:00:00Z"}]' > "$GH_DIR/comments_304.json"
echo '[]' > "$GH_DIR/reviews_304.json"
printf '%s\n' '{"reviews":[],"threads":[{"id":"T-304","isResolved":true,"viewerCanResolve":true,"comments":{"nodes":[{"id":"NC-304","databaseId":104,"author":{"login":"gc-city-bot"},"body":"**Review finding 1/1** fix this","reactionGroups":[]}]}}]}' > "$GH_DIR/threads_304.json"
open_prs "$(open_node 303)" "$(open_node 304 CLEAN REVIEW_REQUIRED)"
rm -f "$BASIS"
out=$(run_basis)
eq "$(meta_pinned PB3 pr_posture),$(meta_pinned PB4 pr_posture)" "commented@sha-303,review_required@sha-304" "the postures are recorded"
out=$(run_basis)
eq "$(pf_views)" "303,304" "…and both are read whole again on the next pass"

echo "# posture basis: a derivation whose answered marks did not record keeps none, so the threads are read again"
# PB7's only inline comment is answered in its resolved thread, so its posture is
# none. The answered marks are what let the next derivation drop that comment
# without reading the threads. While they fail to record, each derivation reads
# the threads again, and a basis kept on two such derivations would skip the read.
store "[$(anchor PB7 307 "$UTCUT")]"
printf '%s' "$(prview 307 OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_307.json"
echo '[]' > "$GH_DIR/reviews_307.json"; echo '[]' > "$GH_DIR/issue_comments_307.json"
printf '[{"id":9701,"user":{"login":"human1"},"body":"answered comment","path":"a.md","line":1},{"id":9702,"user":{"login":"gc-city-bot"},"body":"fixed <!-- gc-writeback -->","path":"a.md","line":1,"in_reply_to_id":9701}]' > "$GH_DIR/comments_307.json"
printf '%s\n' '{"reviews":[],"threads":[{"id":"T-307a","isResolved":true,"viewerCanResolve":true,"comments":{"nodes":[{"id":"NC-307a","databaseId":9701,"fullDatabaseId":"9701","author":{"login":"human1"},"body":"answered comment","reactionGroups":[]},{"id":"NC-307b","databaseId":9702,"fullDatabaseId":"9702","author":{"login":"gc-city-bot"},"body":"fixed <!-- gc-writeback -->","reactionGroups":[]}]}}]}' > "$GH_DIR/threads_307.json"
open_prs "$(open_node 307)"
# A lifecycle.sh that refuses only the answered-marks write and passes every
# other transition, the posture record included, to the real one.
mv "$SD/lifecycle.sh" "$SD/lifecycle.real.sh"
cat > "$SD/lifecycle.sh" <<'LCW'
#!/usr/bin/env bash
case " $* " in *" pr_comment_answered="*) echo "lifecycle (stub): answered marks refused" >&2; exit 1 ;; esac
exec "$(dirname "$0")/lifecycle.real.sh" "$@"
LCW
chmod +x "$SD/lifecycle.sh"
rm -f "$BASIS"
out=$(run_basis)
eq "$(meta_pinned PB7 pr_posture)" "none@sha-307" "the answered comment holds nothing"
has "$out" "answered marks did not record" "…and the marks that did not record are named"
run_basis >/dev/null
out=$(run_basis)
eq "$(pf_views)" "307" "the pass after two derivations whose marks did not record derives the posture again"
eq "$(grep -c 'reviewThreads(first:100' "$STUB_GH_LOG")" "1" "…and reads the threads again"
mv "$SD/lifecycle.real.sh" "$SD/lifecycle.sh"
out=$(run_basis)
eq "$(meta PB7 pr_comment_answered)" "9701" "once the marks record"
out=$(run_basis)
eq "$(pf_views)" "307" "…the next pass derives the posture again to confirm the basis"
eq "$(grep -c 'reviewThreads(first:100' "$STUB_GH_LOG")" "0" "…dropping the answered comment by its mark, with no thread read"
out=$(run_basis)
eq "$(pf_views)" "" "…and the pass after keeps the posture on its confirmed basis"

echo "# posture basis: a changes_requested posture keeps its basis"
store "[$(anchor PB5 305 "$UTCUT")]"
printf '%s' "$(prview 305 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "CHANGES_REQUESTED"' > "$GH_DIR/pr_view_305.json"
open_prs "$(open_node 305 BLOCKED CHANGES_REQUESTED)"
rm -f "$BASIS"
out=$(run_basis)
eq "$(meta_pinned PB5 pr_posture)" "changes_requested@sha-305" "the review decision decides the posture"
out=$(run_basis)
eq "$(pf_views)" "305" "…the next pass derives it again to confirm the basis"
out=$(run_basis)
eq "$(pf_views)" "" "…and nothing else can move it, so the pass after reads no PR"

echo "# posture basis: a batched read that fails reads every PR per PR"
out=$(STUB_OPEN_PRS_FAIL=1 run_basis)
eq "$(pf_views)" "305" "the PR is read per PR"
has "$out" "the batched open-PR read did not answer" "…and the failed read is named"

echo "# done when: an approved PR gone DIRTY files its merge-in in the first pass, however far the rotation is from it"
# Four approved PRs, the last of them conflicting, and a deadline that has
# passed: the rotation reaches only the lowest id this pass. The merge-in owed
# goes ahead of it.
store "[$(anchor DW1 331 ',"pr_posture":"approved@sha-331@2026-10-01T00:00:00Z","pr_merge_state":"BLOCKED@sha-331"'),
        $(anchor DW2 332 ',"pr_posture":"approved@sha-332@2026-10-01T00:00:00Z","pr_merge_state":"BLOCKED@sha-332"'),
        $(anchor DW3 333 ',"pr_posture":"approved@sha-333@2026-10-01T00:00:00Z","pr_merge_state":"BLOCKED@sha-333"'),
        $(anchor DW4 334 ',"pr_posture":"approved@sha-334@2026-10-01T00:00:00Z","pr_merge_state":"DIRTY@sha-334"')]"
for n in 331 332 333; do printf '%s' "$(prview "$n" OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "APPROVED"' > "$GH_DIR/pr_view_$n.json"; done
printf '%s' "$(prview 334 OPEN DIRTY CONFLICTING)" | jq -c '.reviewDecision = "APPROVED"' > "$GH_DIR/pr_view_334.json"
open_prs "$(open_node 331 BLOCKED APPROVED)" "$(open_node 332 BLOCKED APPROVED)" "$(open_node 333 BLOCKED APPROVED)" "$(open_node 334 DIRTY APPROVED)"
DWCUR="$TMP/pr-facts-dw.cursor"; rm -f "$DWCUR" "$DWCUR".*
: > "$STUB_GH_LOG"
out=$("$SUT" --fix-pool "$FIX" --deadline 1 --cursor "$DWCUR" 2>&1)
eq "$(pf_views)" "334,331" "the conflicting approved PR is read first, and the rotation still gets its visit"
has "$out" "PR#334 conflicts with 'main'; filed merge-mode rework" "…and its merge-in is filed in this pass"
has "$out" "(1 needing action first)" "…counted as needing action"
: > "$STUB_GH_LOG"
out=$("$SUT" --fix-pool "$FIX" --deadline 1 --cursor "$DWCUR" 2>&1)
has "$out" "(0 needing action first)" "with the merge-in in flight it owes nothing and rotates"
eq "$(pf_views)" "332" "…so the rotation goes on after the cursor"

echo "# done when: new review feedback is routed in the first pass, however far the rotation is from it"
# The posture arm recorded commented for DF3, the highest id. The feedback arm
# reaches it first, past a deadline that leaves the rotation one visit.
store "[$(anchor DF1 341), $(anchor DF2 342), $(anchor DF3 343 ',"pr_posture":"commented@sha-343@2026-10-01T00:00:00Z"')]"
for n in 341 342 343; do printf '%s' "$(prview "$n" OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_$n.json"; done
printf '%s\n' '[{"id":5343,"user":{"login":"alice"},"body":"this name is misleading","created_at":"2026-10-07T12:00:00Z"}]' > "$GH_DIR/issue_comments_343.json"
open_prs "$(open_node 341)" "$(open_node 342)" "$(open_node 343)"
DFCUR="$TMP/pr-feedback-dw.cursor"; rm -f "$DFCUR" "$DFCUR".*
: > "$STUB_GH_LOG"
out=$("$SUT" --route-comments-only --fix-pool "$FIX" --deadline 1 --cursor "$DFCUR" 2>&1)
eq "$(pf_views)" "343,341" "the PR with unrouted feedback is read first"
has "$(meta DF3 pr_comment_disposition)" "rework:" "…and its feedback is routed in this pass"

echo "# feedback arm: changes_requested goes first only when its PR changed since the arm's last visit"
store "[$(anchor FC1 351), $(anchor FC2 352 ',"pr_posture":"changes_requested@sha-352@2026-10-01T00:00:00Z"')]"
printf '%s' "$(prview 351 OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_351.json"
printf '%s' "$(prview 352 OPEN BLOCKED MERGEABLE)" | jq -c '.reviewDecision = "CHANGES_REQUESTED"' > "$GH_DIR/pr_view_352.json"
open_prs "$(open_node 351)" "$(open_node 352 BLOCKED CHANGES_REQUESTED)"
FCCUR="$TMP/pr-feedback-cr.cursor"; rm -f "$FCCUR" "$FCCUR".*
out=$("$SUT" --route-comments-only --fix-pool "$FIX" --deadline "$(FAR)" --cursor "$FCCUR" 2>&1)
has "$out" "(0 needing action first)" "a standing change request the arm has no last visit to compare with rotates"
open_prs "$(open_node 351)" "$(open_node 352 BLOCKED CHANGES_REQUESTED '.reviews = {totalCount: 2, nodes: [{databaseId: 9352}]}')"
out=$("$SUT" --route-comments-only --fix-pool "$FIX" --deadline "$(FAR)" --cursor "$FCCUR" 2>&1)
has "$out" "(1 needing action first)" "a review since the arm's last visit puts it first"
out=$("$SUT" --route-comments-only --fix-pool "$FIX" --deadline "$(FAR)" --cursor "$FCCUR" 2>&1)
has "$out" "(0 needing action first)" "…and once visited it rotates again"

echo "# full walk: a PR that left the open list or changed since the last visit goes first; one with a rework in flight does not"
store "[$(anchor FW1 361), $(anchor FW2 362),
        $(anchor FW3 363 ',"pr_posture":"approved@sha-363@2026-10-01T00:00:00Z","pr_merge_state":"DIRTY@sha-363"'),
        {\"id\":\"FW3-rw\",\"status\":\"open\",\"assignee\":\"\",\"notes\":\"\",\"title\":\"Merge main into PR#363\",\"metadata\":{\"task_kind\":\"rework\",\"anchor_bead\":\"FW3\",\"branch\":\"polecat/x363\"}}]"
for n in 361 362; do printf '%s' "$(prview "$n" OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_$n.json"; done
printf '%s' "$(prview 363 OPEN DIRTY CONFLICTING)" | jq -c '.reviewDecision = "APPROVED"' > "$GH_DIR/pr_view_363.json"
open_prs "$(open_node 361)" "$(open_node 362)" "$(open_node 363 DIRTY APPROVED)"
FWCUR="$TMP/pr-facts-fw.cursor"; rm -f "$FWCUR" "$FWCUR".*
out=$("$SUT" --fix-pool "$FIX" --deadline "$(FAR)" --cursor "$FWCUR" 2>&1)
has "$out" "(0 needing action first)" "a walk with no marks yet puts nothing first for a change, and a merge-in in flight owes nothing"
eq "$(cut -f1 "$FWCUR.seen" | sort -u | paste -sd, -)" "FW1,FW2,FW3" "…and records a mark for every anchor"
printf '%s' "$(prview 362 MERGED CLEAN MERGEABLE)" > "$GH_DIR/pr_view_362.json"
open_prs "$(open_node 361 CLEAN '' '.headRefOid = "sha-361b"')" "$(open_node 363 DIRTY APPROVED)"
: > "$STUB_GH_LOG"
out=$("$SUT" --fix-pool "$FIX" --deadline 1 --cursor "$FWCUR" 2>&1)
has "$out" "(2 needing action first)" "a PR gone from the open list and a push since the last visit both go first"
eq "$(pf_views)" "361,363" "…the lower id ahead of the rotation, which still gets its visit"
has "$out" "1 needing action wait for the next pass" "…and the merged one the deadline left is named for the next pass"
out=$("$SUT" --fix-pool "$FIX" --deadline "$(FAR)" --cursor "$FWCUR" 2>&1)
has "$out" "recorded FW2 — PR#362 is MERGED" "the next pass records the merge it was owed"

echo "# full walk: an approved conflicting PR the conflict arm stands down on rotates, and goes first once released"
# HD2 is under a merge_hold, HD3 a rebase_hold, and HD4 is armed to re-dispatch:
# the conflict arm files no merge-in for any of them, so none takes a first visit
# every pass. Releasing HD2's hold makes it owe the merge-in again.
HD_APPROVED_DIRTY() { printf ',"pr_posture":"approved@sha-%s@2026-10-01T00:00:00Z","pr_merge_state":"DIRTY@sha-%s"%s' "$1" "$1" "$2"; }
store "[$(anchor HD1 381),
        $(anchor HD2 382 "$(HD_APPROVED_DIRTY 382 ',"merge_hold":"true"')"),
        $(anchor HD3 383 "$(HD_APPROVED_DIRTY 383 ',"rebase_hold":"true"')"),
        $(anchor HD4 384 "$(HD_APPROVED_DIRTY 384 ',"gc.dispatch_when_ready":"gc-toolkit/gc-toolkit.polecat"')")]"
printf '%s' "$(prview 381 OPEN CLEAN MERGEABLE)" > "$GH_DIR/pr_view_381.json"
for n in 382 383 384; do printf '%s' "$(prview "$n" OPEN DIRTY CONFLICTING)" | jq -c '.reviewDecision = "APPROVED"' > "$GH_DIR/pr_view_$n.json"; done
open_prs "$(open_node 381)" "$(open_node 382 DIRTY APPROVED)" "$(open_node 383 DIRTY APPROVED)" "$(open_node 384 DIRTY APPROVED)"
HDCUR="$TMP/pr-facts-hd.cursor"; rm -f "$HDCUR" "$HDCUR".*
out=$("$SUT" --fix-pool "$FIX" --deadline "$(FAR)" --cursor "$HDCUR" 2>&1)
has "$out" "(0 needing action first)" "a held, rebase-held or armed approved conflicting PR is not put first"
has "$out" "PR#382 conflicts but a hold is set" "…and the conflict arm stands down on it when the rotation reaches it"
bmut HD2 'del(.metadata.merge_hold)'
out=$("$SUT" --fix-pool "$FIX" --deadline "$(FAR)" --cursor "$HDCUR" 2>&1)
has "$out" "(1 needing action first)" "with its hold released it goes first"
has "$out" "PR#382 conflicts with 'main'; filed merge-mode rework" "…and its merge-in is filed"
rm -f "$GH_DIR/open_prs.json"

fi # part pacing

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
