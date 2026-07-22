#!/usr/bin/env bash
# Hermetic test for merge-skill.sh (close-on-land merge skill — the single writer
# of merged-truth). Stubs `gh` (PR state + the real merge) and `gc` (bead-ledger
# list/close/update) on PATH. No live city, Dolt, network, or real pull requests.
#
# The skill is the LANDING path that replaces GitHub auto-merge: for each OPEN
# gating anchor it runs validate -> merge -> record. Covered:
#   (1) ready (base==target, every check_set gate green@head, no child,
#        mergeStateStatus=CLEAN) -> MERGED (gh pr merge --squash) + anchor closed
#        "Merged to <target> at <sha>" + merge_result=merged recorded
#   (1b) NO-GATE: empty check_set + CLEAN -> MERGED (the bug fix — a missing gate
#        marker no longer holds a human-approved CLEAN PR forever)
#   (2) check.codex STALE (green@<old-head>) -> merge HELD (not green at live head)
#   (3) check.codex MISSING but codex in check_set -> merge HELD
#   (4) mergeStateStatus=BLOCKED -> merge HELD (CI/approval not green)
#   (5) mergeStateStatus=BEHIND  -> merge HELD (base moved)
#   (6) open rework child references the PR -> merge HELD (a child holds the land)
#   (7) live base != anchor target (retargeted) -> merge HELD (would land wrong)
#   (8) draft PR  -> skipped (drafts retired)
#   (9) already MERGED -> skipped (the observer records it, not the skill)
#   (10) open rework child PAST the former --limit cap -> merge HELD (the
#        referencing-bead scan is unbounded, --limit=0)
#   (11) metadata.merge_hold=true on the anchor -> merge HELD even when the PR is
#        fully CLEAN and every gate is green (operator gate; before the fix such a
#        CLEAN held PR squash-merged with no operator signal)
#   (12) TWO open anchors claim the same PR (a rework bead leaked into the anchor
#        class, tk-ynz4b): one carries the codex gate (red), the duplicate has an
#        EMPTY check_set + CLEAN PR -> before the fix the gateless duplicate
#        merged the PR, bypassing codex; now EVERY anchor of a multi-anchor PR is
#        HELD until the duplicate is closed/demoted
#   (INV) `gh pr merge` is reached for EXACTLY the fully-validated PRs — no
#         other anchor is merged.
#   (5c) convergence: a merged+closed anchor leaves the gating set, so a second
#        pass does not re-merge it.
#   (FS) field-shape guard: the skill requests only gh-supported --json fields.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/merge-skill.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }
has() { grep -q "$1" "$2" 2>/dev/null; }

mkdir -p "$TMP/bin"

# Gating anchors (gc bd list source):
#   id|pr_number|merged_target|check_set|check.codex|merge_hold
# The 5th column is the anchor's per-gate marker value for check.codex; a
# "green@<oid>" value means "the codex gate passed at commit <oid>". bead-NOGATE
# has an empty check_set (declares no gates) and no marker. The 6th column is
# metadata.merge_hold (an operator gate); rows that omit it read as "" (no hold),
# so only bead-HOLD carries it.
cat > "$TMP/anchors" <<'A'
bead-CLEAN|301|main|codex|green@HEAD301
bead-STALE|302|main|codex|green@STALE302
bead-NOSIGN|303|main|codex|
bead-BLOCKED|304|main|codex|green@HEAD304
bead-CHILD|305|main|codex|green@HEAD305
bead-RETARGET|306|main|codex|green@HEAD306
bead-DRAFT|307|main|codex|green@HEAD307
bead-MERGED|308|main|codex|green@HEAD308
bead-BEHIND|309|main|codex|green@HEAD309
bead-CAPCHILD|310|main|codex|green@HEAD310
bead-NOGATE|311|main||
bead-HOLD|312|main|codex|green@HEAD312|true
bead-DUPGATED|313|main|codex|
bead-DUPFREE|313|main||
bead-OPTOUT|314|main|none|
A

# PR states (gh pr view source):
#   pr|state|isDraft|baseRefName|headRefOid|mergeStateStatus|mergeable|mergeOid
#   301 OPEN, base==target, check.codex green@head, CLEAN -> MERGED + recorded
#   302 OPEN, check.codex green@old-head (stale)  -> HELD
#   303 OPEN, codex in check_set but no marker    -> HELD
#   304 OPEN, check green@head BUT mergeState BLOCKED -> HELD
#   305 OPEN, check green@head, CLEAN, open child -> HELD
#   306 OPEN, base=integration/foo != main        -> HELD (retargeted)
#   307 OPEN, draft                               -> skipped
#   308 MERGED already                            -> skipped (observer's job)
#   309 OPEN, check green@head BUT mergeState BEHIND -> HELD
#   310 OPEN, check green@head, CLEAN, open child past former cap -> HELD
#   311 OPEN, empty check_set (no gate), CLEAN    -> MERGED (the bug fix)
#   312 OPEN, check green@head, CLEAN BUT merge_hold=true -> HELD (operator gate)
#   313 OPEN, CLEAN, claimed by TWO anchors (bead-DUPGATED codex-red +
#       bead-DUPFREE gateless) -> HELD via both (one-anchor-per-PR, tk-ynz4b);
#       pre-fix the gateless duplicate merged it, bypassing the codex gate
#   314 OPEN, CLEAN, check_set="none" (the EXPLICIT opt-out sentinel, tk-i48ca)
#       -> MERGED. The sentinel is now STAMPED on the anchor instead of being
#       collapsed to "", so it arrives here as a gate NAME; if the gate-splitting
#       did not drop it, a gateless rig would hold forever on `check.none` — a
#       marker no reviewer can stamp.
cat > "$TMP/prs" <<'P'
301|OPEN|false|main|HEAD301|CLEAN|MERGEABLE|a301c0ffee123456
302|OPEN|false|main|HEAD302|CLEAN|MERGEABLE|
303|OPEN|false|main|HEAD303|CLEAN|MERGEABLE|
304|OPEN|false|main|HEAD304|BLOCKED|MERGEABLE|
305|OPEN|false|main|HEAD305|CLEAN|MERGEABLE|
306|OPEN|false|integration/foo|HEAD306|CLEAN|MERGEABLE|
307|OPEN|true|main|HEAD307|CLEAN|MERGEABLE|
308|MERGED|false|main|HEAD308|CLEAN|MERGEABLE|d308dead00beef11
309|OPEN|false|main|HEAD309|BEHIND|MERGEABLE|
310|OPEN|false|main|HEAD310|CLEAN|MERGEABLE|
311|OPEN|false|main|HEAD311|CLEAN|MERGEABLE|b311c0ffee654321
312|OPEN|false|main|HEAD312|CLEAN|MERGEABLE|
313|OPEN|false|main|HEAD313|CLEAN|MERGEABLE|
314|OPEN|false|main|HEAD314|CLEAN|MERGEABLE|e314f00d5add1e00
P

# Open rework/review children referencing a PR (gc bd list pr_number= source):
# pr_number|child_id|merge_result. PR 305 has an open rework child (no
# merge_result -> the skill must count it and HOLD). PR 310's real child sits
# PAST the former --limit cap behind 24 jq-excluded decoys.
cat > "$TMP/children" <<'C'
305|child-305|
C
for i in $(seq -w 1 24); do
  printf '310|decoy-%s|pull_request\n' "$i" >> "$TMP/children"
done
printf '310|child-310|\n' >> "$TMP/children"

: > "$TMP/closed"; : > "$TMP/merged"; : > "$TMP/mergedrec"; : > "$TMP/closelog"

# --- gh stub: pr view (emit state JSON), pr merge (record the merge). ---------
# `pr view` validates requested --json fields against a supported set (NOT
# `merged`) and emits a full object; the skill reads the subset it asked for.
# `pr merge` records the merged PR number — this is the seam: it must be reached
# for EXACTLY the one fully-validated anchor.
cat > "$TMP/bin/gh" <<'GH'
#!/usr/bin/env bash
case "$1 $2" in
  "pr view")
    num="$3"; shift 3
    fields=""
    while [ $# -gt 0 ]; do case "$1" in --json) fields="$2"; shift 2 ;; *) shift ;; esac; done
    SUPPORTED=" number state mergedAt mergeCommit isDraft baseRefName headRefName headRefOid url title body author additions deletions mergeable mergeStateStatus "
    OIFS="$IFS"; IFS=','
    for f in $fields; do
      case "$SUPPORTED" in
        *" $f "*) : ;;
        *) IFS="$OIFS"; echo "Unknown JSON field: \"$f\"" >&2; exit 1 ;;
      esac
    done
    IFS="$OIFS"
    while IFS='|' read -r pr state isdraft base headoid mss mergeable oid; do
      [ "$pr" = "$num" ] || continue
      jq -n --arg s "$state" --argjson d "$isdraft" --arg b "$base" \
            --arg h "$headoid" --arg m "$mss" --arg mg "$mergeable" --arg o "$oid" \
        '{state:$s, isDraft:$d, baseRefName:$b, headRefOid:$h, mergeStateStatus:$m, mergeable:$mg, mergeCommit:(if $o=="" then null else {oid:$o} end)}'
      exit 0
    done < "$FAKE_PRS"
    exit 0 ;;
  "pr merge")
    printf '%s\n' "$3" >> "$FAKE_MERGED" ;;
esac
exit 0
GH
chmod +x "$TMP/bin/gh"

# --- gc stub: bd list / bd close / bd update. --------------------------------
# Two list shapes: the gating-anchor scan (merge_result=pull_request, excluding
# already-closed anchors so convergence holds) and the referencing-bead scan
# (pr_number=N, --status open,in_progress) that returns the anchor (which the
# skill EXCLUDES) plus any open rework/review children (which HOLD the merge).
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
emit_rows() {
  raw="[$1]"; n="$2"
  if [ -n "$n" ] && [ "$n" -gt 0 ] 2>/dev/null; then
    printf '%s' "$raw" | jq -c ".[:$n]"
  else
    printf '%s\n' "$raw"
  fi
}
[ "$1" = "bd" ] || exit 0
case "$2" in
  list)
    lim=$(printf '%s' "$*" | sed -n 's/.*--limit=\([0-9][0-9]*\).*/\1/p')
    case "$*" in
      *"merge_result=pull_request"*)
        out=""
        while IFS='|' read -r id pr target checkset checkcodex merge_hold; do
          [ -n "$id" ] || continue
          grep -qx "$id" "$FAKE_CLOSED" 2>/dev/null && continue
          obj=$(printf '{"id":"%s","metadata":{"pr_number":"%s","merged_target":"%s","check_set":"%s","check.codex":"%s","merge_hold":"%s"}}' "$id" "$pr" "$target" "$checkset" "$checkcodex" "$merge_hold")
          if [ -z "$out" ]; then out="$obj"; else out="$out,$obj"; fi
        done < "$FAKE_ANCHORS"
        emit_rows "$out" "$lim" ;;
      *"pr_number="*)
        prnum=$(printf '%s' "$*" | sed -n 's/.*pr_number=\([0-9][0-9]*\).*/\1/p')
        out=""
        while IFS='|' read -r id pr target checkset checkcodex merge_hold; do
          [ -n "$id" ] || continue
          [ "$pr" = "$prnum" ] || continue
          grep -qx "$id" "$FAKE_CLOSED" 2>/dev/null && continue
          obj=$(printf '{"id":"%s","metadata":{"pr_number":"%s","merge_result":"pull_request"}}' "$id" "$pr")
          if [ -z "$out" ]; then out="$obj"; else out="$out,$obj"; fi
        done < "$FAKE_ANCHORS"
        if [ -f "$FAKE_CHILDREN" ]; then
          while IFS='|' read -r cpr cid cmr; do
            [ -n "$cpr" ] || continue
            [ "$cpr" = "$prnum" ] || continue
            grep -qx "$cid" "$FAKE_CLOSED" 2>/dev/null && continue
            obj=$(printf '{"id":"%s","metadata":{"pr_number":"%s","merge_result":"%s"}}' "$cid" "$cpr" "$cmr")
            if [ -z "$out" ]; then out="$obj"; else out="$out,$obj"; fi
          done < "$FAKE_CHILDREN"
        fi
        emit_rows "$out" "$lim" ;;
      *) printf '[]\n' ;;
    esac ;;
  close)
    id="$3"; shift 3
    reason=""
    while [ $# -gt 0 ]; do case "$1" in --reason) reason="$2"; shift 2 ;; *) shift ;; esac; done
    printf '%s\n' "$id" >> "$FAKE_CLOSED"
    printf '%s\t%s\n' "$id" "$reason" >> "$FAKE_CLOSELOG" ;;
  update)
    id="$3"
    case "$*" in
      *merge_result=merged*) printf '%s\n' "$id" >> "$FAKE_MERGEDREC" ;;
    esac ;;
esac
exit 0
GC
chmod +x "$TMP/bin/gc"

export PATH="$TMP/bin:$PATH"
export FAKE_ANCHORS="$TMP/anchors" FAKE_PRS="$TMP/prs" FAKE_CHILDREN="$TMP/children" \
       FAKE_CLOSED="$TMP/closed" FAKE_MERGED="$TMP/merged" \
       FAKE_MERGEDREC="$TMP/mergedrec" FAKE_CLOSELOG="$TMP/closelog"

# --- Run 1: validate -> merge -> record for the one ready PR, hold the rest. --
OUT1="$(bash "$SCRIPT")"

# (1) ready PR -> merged + recorded + closed.
has '^301$' "$TMP/merged" && ok "(1) ready PR -> 'gh pr merge --squash' performed" \
                          || bad "(1) ready PR -> merge performed"
has '^bead-CLEAN$' "$TMP/closed" && ok "(1) ready anchor closed (record)" \
                                 || bad "(1) ready anchor closed"
grep -q 'Merged to main at a301c0ff' "$TMP/closelog" \
  && ok "(1) close reason names target + short merge sha" \
  || bad "(1) close reason (got: $(cat "$TMP/closelog"))"
has '^bead-CLEAN$' "$TMP/mergedrec" && ok "(1) merge_result=merged recorded on anchor" \
                                    || bad "(1) merge_result=merged recorded"

# (1b) THE BUG FIX: an anchor with an empty check_set (no required gate) merges
# once CLEAN, instead of the former unconditional hold on a missing signoff_head.
has '^311$' "$TMP/merged" && ok "(1b) no-gate PR (empty check_set) -> merged (missing gate no longer holds forever)" \
                          || bad "(1b) no-gate PR -> merged"
has '^bead-NOGATE$' "$TMP/closed" && ok "(1b) no-gate anchor closed (record)" \
                                  || bad "(1b) no-gate anchor closed"
has '^bead-NOGATE$' "$TMP/mergedrec" && ok "(1b) merge_result=merged recorded on no-gate anchor" \
                                     || bad "(1b) no-gate merge_result recorded"

# (1c) THE OPT-OUT SENTINEL (tk-i48ca): check_set="none" is a gateless rig saying
# so EXPLICITLY. It reaches this script as a gate NAME (the formula now stamps the
# sentinel instead of collapsing it to ""), so the gate-splitting must DROP it —
# otherwise the anchor holds forever on `check.none`, a marker no reviewer can
# stamp. Stamping the sentinel is what lets an EMPTY check_set stay a reliable
# "this bead never ran normalization" signal for check-set-heal.sh.
has '^314$' "$TMP/merged" && ok "(1c) opt-out PR (check_set='none') -> merged (sentinel read as no-gates)" \
                          || bad "(1c) opt-out sentinel must merge, not hold on a 'check.none' marker"
has '^bead-OPTOUT$' "$TMP/closed" && ok "(1c) opt-out anchor closed (record)" \
                                  || bad "(1c) opt-out anchor closed"

# (2)-(12) every other anchor is HELD or skipped — NOT merged. 313 is the
# multi-anchor PR: its gateless duplicate anchor (bead-DUPFREE) is CLEAN and
# would have merged pre-fix.
for n in 302 303 304 305 306 307 308 309 310 312 313; do
  has "^$n$" "$TMP/merged" && bad "($n) anchor must NOT be merged" \
                          || ok "($n) anchor not merged"
done

# Hold reasons name the specific gate that blocked each PR.
printf '%s\n' "$OUT1" | grep -q "PR#302 check 'codex' not green at live head" \
  && ok "(2) stale check.codex (green@old-head) -> held, reason names the gate" \
  || bad "(2) stale check hold reason (got: $OUT1)"
printf '%s\n' "$OUT1" | grep -q "PR#303 check 'codex' not green at live head" \
  && ok "(3) missing check.codex (codex in check_set) -> held" || bad "(3) missing check hold (got: $OUT1)"
printf '%s\n' "$OUT1" | grep -q "PR#304 not mergeable yet (mergeStateStatus='BLOCKED'" \
  && ok "(4) BLOCKED -> held, reason names mergeStateStatus" || bad "(4) BLOCKED hold (got: $OUT1)"
printf '%s\n' "$OUT1" | grep -q "PR#309 not mergeable yet (mergeStateStatus='BEHIND'" \
  && ok "(5) BEHIND -> held" || bad "(5) BEHIND hold (got: $OUT1)"
printf '%s\n' "$OUT1" | grep -q "PR#305 has open rework/review bead child-305" \
  && ok "(6) open rework child -> held, reason names the child" || bad "(6) child hold (got: $OUT1)"
printf '%s\n' "$OUT1" | grep -q "PR#306 base 'integration/foo' != target 'main' (retargeted)" \
  && ok "(7) retargeted -> held, reason names the base mismatch" || bad "(7) retarget hold (got: $OUT1)"
printf '%s\n' "$OUT1" | grep -q "PR#310 has open rework/review bead child-310" \
  && ok "(10) open child past former cap -> held (unbounded scan found it)" \
  || bad "(10) past-cap child hold (got: $OUT1)"
printf '%s\n' "$OUT1" | grep -q "PR#312 merge_hold set (operator gate)" \
  && ok "(11) merge_hold=true -> held, reason names the operator gate" \
  || bad "(11) merge_hold hold reason (got: $OUT1)"
printf '%s\n' "$OUT1" | grep -q "PR#313 has multiple open gating anchors (one-anchor-per-PR violated); merge held (anchor bead-DUPGATED)" \
  && ok "(12) multi-anchor PR -> gated anchor held with the one-anchor-per-PR reason" \
  || bad "(12) multi-anchor gated-anchor hold (got: $OUT1)"
printf '%s\n' "$OUT1" | grep -q "PR#313 has multiple open gating anchors (one-anchor-per-PR violated); merge held (anchor bead-DUPFREE)" \
  && ok "(12) multi-anchor PR -> gateless duplicate ALSO held (pre-fix it merged, bypassing codex)" \
  || bad "(12) multi-anchor gateless-duplicate hold (got: $OUT1)"

# (9) already-merged anchor is NOT closed by the skill (the observer records it).
has '^bead-MERGED$' "$TMP/closed" && bad "(9) already-merged anchor must NOT be closed by the skill" \
                                  || ok "(9) already-merged anchor left for the observer"

# (INV) exactly three PRs were merged: the fully-validated gated head (301), the
# no-gate PR (311), and the explicit opt-out (314). No held/skipped anchor leaked.
eq "$(wc -l < "$TMP/merged" | tr -d ' ')" "3" "(INV) exactly three PRs merged (gated head 301 + no-gate 311 + opt-out 314)"

# Summary counters.
printf '%s\n' "$OUT1" | grep -q "3 merged" \
  && ok "run 1 summary reports 3 merged" || bad "run 1 summary merged count (got: $OUT1)"

# --- Field-shape guard: only gh-supported --json fields. ----------------------
gh pr view 301 --json merged >/dev/null 2>&1 \
  && bad "(FS) gh stub must REJECT unsupported field 'merged'" \
  || ok "(FS) unsupported --json field 'merged' rejected (guards the field-shape bug)"
gh pr view 301 --json state,isDraft,baseRefName,headRefOid,mergeStateStatus,mergeable >/dev/null 2>&1 \
  && ok "(FS) the skill's validate --json field set is accepted" \
  || bad "(FS) the skill's --json field set must be accepted"
gh pr view 301 --json mergeCommit >/dev/null 2>&1 \
  && ok "(FS) the skill's record --json mergeCommit is accepted" \
  || bad "(FS) mergeCommit field must be accepted"

# --- Run 2: convergence. The merged+closed anchor leaves the gating set. -------
bash "$SCRIPT" >/dev/null
eq "$(grep -c '^301$' "$TMP/merged")" "1" "(5c) merged gated anchor not re-merged on second pass"
eq "$(grep -c '^311$' "$TMP/merged")" "1" "(5c) merged no-gate anchor not re-merged on second pass"

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
