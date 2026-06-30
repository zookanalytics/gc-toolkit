#!/usr/bin/env bash
# Hermetic test for merge-skill.sh (close-on-land merge skill — the single writer
# of merged-truth). Stubs `gh` (PR state + the real merge) and `gc` (bead-ledger
# list/close/update) on PATH. No live city, Dolt, network, or real pull requests.
#
# The skill is the LANDING path that replaces GitHub auto-merge: for each OPEN
# gating anchor it runs validate -> merge -> record. Covered:
#   (1) ready (base==target, head==signoff, no child, mergeStateStatus=CLEAN)
#        -> MERGED (gh pr merge --squash) + anchor closed "Merged to <target> at
#           <sha>" + merge_result=merged recorded
#   (2) signoff_head STALE  -> merge HELD (head not signoff-validated)
#   (3) signoff_head MISSING -> merge HELD
#   (4) mergeStateStatus=BLOCKED -> merge HELD (CI/approval not green)
#   (5) mergeStateStatus=BEHIND  -> merge HELD (base moved)
#   (6) open rework child references the PR -> merge HELD (a child holds the land)
#   (7) live base != anchor target (retargeted) -> merge HELD (would land wrong)
#   (8) draft PR  -> skipped (drafts retired)
#   (9) already MERGED -> skipped (the observer records it, not the skill)
#   (10) open rework child PAST the former --limit cap -> merge HELD (the
#        referencing-bead scan is unbounded, --limit=0)
#   (INV) `gh pr merge` is reached for EXACTLY the one fully-validated PR — no
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

# Gating anchors (gc bd list source): id|pr_number|merged_target|signoff_head
cat > "$TMP/anchors" <<'A'
bead-CLEAN|301|main|HEAD301
bead-STALE|302|main|STALE302
bead-NOSIGN|303|main|
bead-BLOCKED|304|main|HEAD304
bead-CHILD|305|main|HEAD305
bead-RETARGET|306|main|HEAD306
bead-DRAFT|307|main|HEAD307
bead-MERGED|308|main|HEAD308
bead-BEHIND|309|main|HEAD309
bead-CAPCHILD|310|main|HEAD310
A

# PR states (gh pr view source):
#   pr|state|isDraft|baseRefName|headRefOid|mergeStateStatus|mergeable|mergeOid
#   301 OPEN, base==target, head==signoff, CLEAN -> MERGED + recorded
#   302 OPEN, head != signoff (stale)            -> HELD
#   303 OPEN, anchor has no signoff              -> HELD
#   304 OPEN, head==signoff BUT mergeState BLOCKED -> HELD
#   305 OPEN, head==signoff, CLEAN, open child   -> HELD
#   306 OPEN, base=integration/foo != main       -> HELD (retargeted)
#   307 OPEN, draft                              -> skipped
#   308 MERGED already                           -> skipped (observer's job)
#   309 OPEN, head==signoff BUT mergeState BEHIND  -> HELD
#   310 OPEN, head==signoff, CLEAN, open child past former cap -> HELD
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
        while IFS='|' read -r id pr target signoff; do
          [ -n "$id" ] || continue
          grep -qx "$id" "$FAKE_CLOSED" 2>/dev/null && continue
          obj=$(printf '{"id":"%s","metadata":{"pr_number":"%s","merged_target":"%s","signoff_head":"%s"}}' "$id" "$pr" "$target" "$signoff")
          if [ -z "$out" ]; then out="$obj"; else out="$out,$obj"; fi
        done < "$FAKE_ANCHORS"
        emit_rows "$out" "$lim" ;;
      *"pr_number="*)
        prnum=$(printf '%s' "$*" | sed -n 's/.*pr_number=\([0-9][0-9]*\).*/\1/p')
        out=""
        while IFS='|' read -r id pr target signoff; do
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

# (2)-(10) every other anchor is HELD or skipped — NOT merged.
for n in 302 303 304 305 306 307 308 309 310; do
  has "^$n$" "$TMP/merged" && bad "($n) anchor must NOT be merged" \
                          || ok "($n) anchor not merged"
done

# Hold reasons name the specific gate that blocked each PR.
printf '%s\n' "$OUT1" | grep -q "PR#302 head not signoff-validated" \
  && ok "(2) stale signoff_head -> held, reason names the signoff gate" \
  || bad "(2) stale signoff hold reason (got: $OUT1)"
printf '%s\n' "$OUT1" | grep -q "PR#303 head not signoff-validated" \
  && ok "(3) missing signoff_head -> held" || bad "(3) missing signoff hold (got: $OUT1)"
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

# (9) already-merged anchor is NOT closed by the skill (the observer records it).
has '^bead-MERGED$' "$TMP/closed" && bad "(9) already-merged anchor must NOT be closed by the skill" \
                                  || ok "(9) already-merged anchor left for the observer"

# (INV) exactly one PR was merged.
eq "$(wc -l < "$TMP/merged" | tr -d ' ')" "1" "(INV) exactly one PR merged (the fully-validated head)"

# Summary counters.
printf '%s\n' "$OUT1" | grep -q "1 merged" \
  && ok "run 1 summary reports 1 merged" || bad "run 1 summary merged count (got: $OUT1)"

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
eq "$(grep -c '^301$' "$TMP/merged")" "1" "(5c) merged anchor not re-merged on second pass"

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
