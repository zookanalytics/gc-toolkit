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
#   (13) DEPENDENCY-LINKED rework child with NO pr_number of its own -> merge HELD
#        (tk-lgjvg: the gate resolved children by pr_number alone, so a child that
#        carries only branch/source_review_bead was invisible and the gate PASSED)
#   (14) dependency-linked child in status `blocked` -> merge HELD (the live
#        tk-h9pq5/PR#233 shape: the child was blocked + routed to human. The
#        invariant is "all children CLOSED", so every non-closed status holds)
#   (15) pr_number-carrying child in status `blocked` -> merge HELD (the probe asks
#        for every LIVE_STATUSES value, not just open,in_progress)
#   (16) open REVIEW bead attached as a `blocks` dependency OF the anchor (how a
#        signoff gate attaches) -> merge HELD
#   (17) open DOWNSTREAM dependent (up/blocks) + open EPIC PARENT (down/parent-
#        child) -> MERGED. Both are the wrong end of their edge; holding on either
#        deadlocks a healthy anchor forever, which is why both dep probes are
#        direction- AND type-filtered.
#   (18) CLOSED dependency-linked child -> MERGED (a closed child holds nothing)
#   (19) the child probe ERRORS -> merge HELD (fail closed: an empty result from a
#        broken query is indistinguishable from "no children", and reading it as
#        "no children" merges past open rework)
#   (20) a live `blocks` blocker that CARRIES merge_result=pull_request — an
#        upstream PR anchor filed as an explicit merge-ordering block -> merge
#        HELD (tk-je0rk: the merge_result exclusion was applied to the whole
#        holder set, so the one holder shape that carries merge_result BY
#        DEFINITION was deleted and the downstream PR merged past its blocker)
#   (21) a live parent-child CHILD carrying merge_result=pre_open_gate (a child
#        that reached its own PR/pre-open gate) -> merge HELD too. Same rule:
#        provenance decides, and a dependency edge holds regardless of
#        merge_result — only pr_number-swept duplicates are excludable.
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
bead-DEPCHILD|315|main|codex|green@HEAD315
bead-BLOCKEDKID|316|main|codex|green@HEAD316
bead-PRBLOCKED|317|main|codex|green@HEAD317
bead-BLOCKGATE|318|main|codex|green@HEAD318
bead-DOWNSTREAM|319|main|codex|green@HEAD319
bead-CLOSEDCHILD|320|main|codex|green@HEAD320
bead-PROBEFAIL|321|main|codex|green@HEAD321
bead-BLOCKEDBYPR|322|main|codex|green@HEAD322
bead-KIDANCHOR|323|main|codex|green@HEAD323
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
#   315 OPEN, CLEAN, gate green — open dep-linked child, NO pr_number  -> HELD
#   316 OPEN, CLEAN, gate green — dep-linked child in status `blocked` -> HELD
#   317 OPEN, CLEAN, gate green — pr_number child in status `blocked`  -> HELD
#   318 OPEN, CLEAN, gate green — open review bead BLOCKING the anchor -> HELD
#   319 OPEN, CLEAN, gate green — only wrong-end edges (downstream dependent,
#       epic parent)                                                   -> MERGED
#   320 OPEN, CLEAN, gate green — dep-linked child already CLOSED      -> MERGED
#   321 OPEN, CLEAN, gate green — the child probe errors               -> HELD
#   322 OPEN, CLEAN, gate green — `blocks` blocker carrying
#       merge_result=pull_request (an upstream PR ordered ahead)       -> HELD
#   323 OPEN, CLEAN, gate green — parent-child child carrying
#       merge_result=pre_open_gate                                     -> HELD
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
315|OPEN|false|main|HEAD315|CLEAN|MERGEABLE|
316|OPEN|false|main|HEAD316|CLEAN|MERGEABLE|
317|OPEN|false|main|HEAD317|CLEAN|MERGEABLE|
318|OPEN|false|main|HEAD318|CLEAN|MERGEABLE|
319|OPEN|false|main|HEAD319|CLEAN|MERGEABLE|f319c0ffee333333
320|OPEN|false|main|HEAD320|CLEAN|MERGEABLE|a320c0ffee444444
321|OPEN|false|main|HEAD321|CLEAN|MERGEABLE|
322|OPEN|false|main|HEAD322|CLEAN|MERGEABLE|
323|OPEN|false|main|HEAD323|CLEAN|MERGEABLE|
P

# Rework/review children referencing a PR by their OWN pr_number metadata
# (gc bd list pr_number= source):
#   pr_number|child_id|merge_result|status     (empty status reads as `open`)
# PR 305 has an open rework child (no merge_result -> the skill must count it and
# HOLD). PR 310's real child sits PAST the former --limit cap behind 24
# jq-excluded decoys. PR 317's child is `blocked`, NOT open — the stub honours the
# requested --status list, so it is returned only because the skill now asks for
# every live status instead of open,in_progress.
cat > "$TMP/children" <<'C'
305|child-305||
317|prblocked-317||blocked
C
for i in $(seq -w 1 24); do
  printf '310|decoy-%s|pull_request|\n' "$i" >> "$TMP/children"
done
printf '310|child-310||\n' >> "$TMP/children"

# Dependency edges (gc bd dep list source), the resolution path tk-lgjvg adds:
#   anchor|direction|type|bead_id|status|merge_result
# `direction` is the flag the skill passes (up = dependents of the anchor,
# down = what the anchor depends on), so a row is returned ONLY to the exact
# direction+type walk that asks for it. The two wrong-end rows on bead-DOWNSTREAM
# are the deadlock guards: an `up|blocks` dependent WAITS for this merge and a
# `down|parent-child` parent stays open until the anchor closes, so a gate that
# held on either would never land a healthy anchor.
#
# The last two rows carry a NON-EMPTY merge_result (tk-je0rk). They are the holder
# shapes the merge_result exclusion used to delete: an upstream PR anchor ordered
# ahead of this one by an explicit `blocks` edge carries merge_result=pull_request
# BY DEFINITION, and a child that reached its own pre-open gate carries
# pre_open_gate. Reached by a dependency edge, both hold — the exclusion is scoped
# to pr_number-swept duplicate anchors only.
cat > "$TMP/deps" <<'D'
bead-DEPCHILD|up|parent-child|depchild-315|open|
bead-BLOCKEDKID|up|parent-child|blockedkid-316|blocked|
bead-BLOCKGATE|down|blocks|review-318|open|
bead-DOWNSTREAM|up|blocks|downstream-319|open|
bead-DOWNSTREAM|down|parent-child|epic-319|open|
bead-CLOSEDCHILD|up|parent-child|closedchild-320|closed|
bead-BLOCKEDBYPR|down|blocks|upstream-322|open|pull_request
bead-KIDANCHOR|up|parent-child|kidanchor-323|open|pre_open_gate
D

# Anchors whose dep probe ERRORS (exit 1) — the fail-closed case.
printf 'bead-PROBEFAIL\n' > "$TMP/depfail"

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

# --- gc stub: bd list / bd dep list / bd close / bd update. ------------------
# Two list shapes: the gating-anchor scan (merge_result=pull_request, excluding
# already-closed anchors so convergence holds) and the referencing-bead scan
# (pr_number=N, honouring the requested --status list) that returns the anchor
# (which the skill EXCLUDES) plus any live rework/review children (which HOLD the
# merge). `bd dep list` serves the two dependency walks, each answering ONLY the
# direction+type it was asked for — a stub that ignored the flags could not tell
# a rework child from the epic parent or the downstream dependent.
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
        # The status filter the caller asked for. A child whose status is not in
        # the list is invisible, exactly as the real `gc bd list --status` behaves.
        want=$(printf '%s' "$*" | sed -n 's/.*--status[= ]\([a-z_,]*\).*/\1/p')
        [ -n "$want" ] || want="open"
        out=""
        while IFS='|' read -r id pr target checkset checkcodex merge_hold; do
          [ -n "$id" ] || continue
          [ "$pr" = "$prnum" ] || continue
          grep -qx "$id" "$FAKE_CLOSED" 2>/dev/null && continue
          obj=$(printf '{"id":"%s","status":"open","metadata":{"pr_number":"%s","merge_result":"pull_request"}}' "$id" "$pr")
          if [ -z "$out" ]; then out="$obj"; else out="$out,$obj"; fi
        done < "$FAKE_ANCHORS"
        if [ -f "$FAKE_CHILDREN" ]; then
          while IFS='|' read -r cpr cid cmr cstatus; do
            [ -n "$cpr" ] || continue
            [ "$cpr" = "$prnum" ] || continue
            grep -qx "$cid" "$FAKE_CLOSED" 2>/dev/null && continue
            [ -n "$cstatus" ] || cstatus="open"
            printf '%s' ",$want," | grep -q ",$cstatus," || continue
            obj=$(printf '{"id":"%s","status":"%s","metadata":{"pr_number":"%s","merge_result":"%s"}}' "$cid" "$cstatus" "$cpr" "$cmr")
            if [ -z "$out" ]; then out="$obj"; else out="$out,$obj"; fi
          done < "$FAKE_CHILDREN"
        fi
        emit_rows "$out" "$lim" ;;
      *) printf '[]\n' ;;
    esac ;;
  dep)
    [ "$3" = "list" ] || { printf '[]\n'; exit 0; }
    aid="$4"; shift 4
    dir="down"; typ=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --direction=*) dir="${1#--direction=}"; shift ;;
        --direction) dir="$2"; shift 2 ;;
        -t|--type) typ="$2"; shift 2 ;;
        --type=*) typ="${1#--type=}"; shift ;;
        *) shift ;;
      esac
    done
    # A wedged/unreadable probe: non-zero exit with no usable payload.
    if grep -qx "$aid" "$FAKE_DEPFAIL" 2>/dev/null; then
      echo "gc: dep list failed for $aid" >&2; exit 1
    fi
    out=""
    if [ -f "$FAKE_DEPS" ]; then
      while IFS='|' read -r danchor ddir dtype did dstatus dmr; do
        [ -n "$danchor" ] || continue
        [ "$danchor" = "$aid" ] || continue
        [ "$ddir" = "$dir" ] || continue
        [ -z "$typ" ] || [ "$dtype" = "$typ" ] || continue
        grep -qx "$did" "$FAKE_CLOSED" 2>/dev/null && continue
        obj=$(printf '{"id":"%s","status":"%s","dependency_type":"%s","metadata":{"merge_result":"%s"}}' "$did" "$dstatus" "$dtype" "$dmr")
        if [ -z "$out" ]; then out="$obj"; else out="$out,$obj"; fi
      done < "$FAKE_DEPS"
    fi
    printf '[%s]\n' "$out" ;;
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
       FAKE_DEPS="$TMP/deps" FAKE_DEPFAIL="$TMP/depfail" \
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

# (17) THE ANTI-DEADLOCK GUARD: bead-DOWNSTREAM's only edges point the WRONG way
# — an `up|blocks` dependent waiting for this merge, and a `down|parent-child`
# epic parent that stays open until the anchor closes. Neither is a child. A gate
# that walked those directions would hold a healthy anchor forever.
has '^319$' "$TMP/merged" && ok "(17) wrong-end edges (downstream dependent + epic parent) -> merged, not deadlocked" \
                          || bad "(17) wrong-end edges must NOT hold the merge"
# (18) a CLOSED dependency-linked child holds nothing — the invariant is "all
# children CLOSED", and this one is.
has '^320$' "$TMP/merged" && ok "(18) closed dep-linked child -> merged" \
                          || bad "(18) closed dep-linked child must not hold"

# (2)-(19) every other anchor is HELD or skipped — NOT merged. 313 is the
# multi-anchor PR: its gateless duplicate anchor (bead-DUPFREE) is CLEAN and
# would have merged pre-fix. 315-318 and 321 are the tk-lgjvg child-resolution
# cases: every one is CLEAN with its codex gate green at the live head, so the
# ONLY thing standing between them and a merge is the child gate.
for n in 302 303 304 305 306 307 308 309 310 312 313 315 316 317 318 321 322 323; do
  has "^$n$" "$TMP/merged" && bad "($n) anchor must NOT be merged" \
                          || ok "($n) anchor not merged"
done

# Hold reasons name the specific gate that blocked each PR.
#
# These assert with `grep -q PATTERN <<< "$OUT1"`, NOT `printf … | grep -q …`.
# Do not "tidy" them back into a pipe. Under this file's `set -o pipefail`, the
# piped form reports a FALSE FAILURE on a string that is genuinely present:
# `grep -q` exits 0 the instant it matches, closing the pipe while `printf` is
# still writing, so printf dies of SIGPIPE (141) and pipefail promotes that to
# the pipeline's status — the `&&`/`||` then takes the `bad` branch even though
# the match succeeded. It is a RACE on how much printf flushed before grep quit,
# so it hides while the payload is small and widens as the payload grows.
#
# Measured on this suite's real $OUT1 (2552 B): the piped form produced 14 false
# failures in 3000 tries (~0.5%), the here-string form 0 in 3000. At 18 piped
# assertions per run that is roughly a 1-in-12 chance of a spurious FAIL per
# execution — which is exactly the "ANOMALY" recorded in tk-lgjvg's notes: a lone
# "(14) blocked dep-linked child must hold" failure whose own diagnostic dump
# CONTAINED the asserted substring, written off as unreproducible after 16 clean
# reruns. It was never a flaky assertion; it was this. (Anchors 322/323 lengthen
# $OUT1 slightly and so nudge the odds up, but the defect predates them.)
#
# A here-string is not a pipeline, so there is no SIGPIPE and no pipefail
# interaction. The same pattern is still live in ~10 other pack test files and in
# reconcile-graduated-convoys.sh:209 (shipped, where it can silently skip a
# convoy) — tracked as tk-zfjg9, deliberately not swept here.
grep -q "PR#302 check 'codex' not green at live head" <<< "$OUT1" \
  && ok "(2) stale check.codex (green@old-head) -> held, reason names the gate" \
  || bad "(2) stale check hold reason (got: $OUT1)"
grep -q "PR#303 check 'codex' not green at live head" <<< "$OUT1" \
  && ok "(3) missing check.codex (codex in check_set) -> held" || bad "(3) missing check hold (got: $OUT1)"
grep -q "PR#304 not mergeable yet (mergeStateStatus='BLOCKED'" <<< "$OUT1" \
  && ok "(4) BLOCKED -> held, reason names mergeStateStatus" || bad "(4) BLOCKED hold (got: $OUT1)"
grep -q "PR#309 not mergeable yet (mergeStateStatus='BEHIND'" <<< "$OUT1" \
  && ok "(5) BEHIND -> held" || bad "(5) BEHIND hold (got: $OUT1)"
grep -q "PR#305 has unclosed rework/review bead child-305 (open)" <<< "$OUT1" \
  && ok "(6) open rework child -> held, reason names the child" || bad "(6) child hold (got: $OUT1)"
grep -q "PR#306 base 'integration/foo' != target 'main' (retargeted)" <<< "$OUT1" \
  && ok "(7) retargeted -> held, reason names the base mismatch" || bad "(7) retarget hold (got: $OUT1)"
grep -q "PR#310 has unclosed rework/review bead child-310 (open)" <<< "$OUT1" \
  && ok "(10) open child past former cap -> held (unbounded scan found it)" \
  || bad "(10) past-cap child hold (got: $OUT1)"
grep -q "PR#312 merge_hold set (operator gate)" <<< "$OUT1" \
  && ok "(11) merge_hold=true -> held, reason names the operator gate" \
  || bad "(11) merge_hold hold reason (got: $OUT1)"
grep -q "PR#313 has multiple open gating anchors (one-anchor-per-PR violated); merge held (anchor bead-DUPGATED)" <<< "$OUT1" \
  && ok "(12) multi-anchor PR -> gated anchor held with the one-anchor-per-PR reason" \
  || bad "(12) multi-anchor gated-anchor hold (got: $OUT1)"
grep -q "PR#313 has multiple open gating anchors (one-anchor-per-PR violated); merge held (anchor bead-DUPFREE)" <<< "$OUT1" \
  && ok "(12) multi-anchor PR -> gateless duplicate ALSO held (pre-fix it merged, bypassing codex)" \
  || bad "(12) multi-anchor gateless-duplicate hold (got: $OUT1)"

# (13)-(16),(19) tk-lgjvg: the child gate resolves holders by DEPENDENCY as well
# as by pr_number, over every live status, and fails CLOSED when it cannot look.
grep -q "PR#315 has unclosed rework/review bead depchild-315 (open)" <<< "$OUT1" \
  && ok "(13) dep-linked child with NO pr_number -> held (the fail-open defect)" \
  || bad "(13) dep-linked child must hold the merge (got: $OUT1)"
grep -q "PR#316 has unclosed rework/review bead blockedkid-316 (blocked)" <<< "$OUT1" \
  && ok "(14) dep-linked child in status 'blocked' -> held (all children CLOSED, not just open)" \
  || bad "(14) blocked dep-linked child must hold (got: $OUT1)"
grep -q "PR#317 has unclosed rework/review bead prblocked-317 (blocked)" <<< "$OUT1" \
  && ok "(15) pr_number child in status 'blocked' -> held (probe asks for every live status)" \
  || bad "(15) blocked pr_number child must hold (got: $OUT1)"
grep -q "PR#318 has unclosed rework/review bead review-318 (open)" <<< "$OUT1" \
  && ok "(16) review bead attached as a 'blocks' dep of the anchor -> held" \
  || bad "(16) blocking review bead must hold (got: $OUT1)"
grep -q "PR#321 in-flight rework/review probe failed; merge held" <<< "$OUT1" \
  && ok "(19) unreadable child probe -> held (fail closed, not merged past)" \
  || bad "(19) probe failure must fail CLOSED (got: $OUT1)"

# (20)-(21) tk-je0rk: a holder reached by a DEPENDENCY EDGE holds regardless of
# merge_result. The exclusion is for duplicate anchors the pr_number probe swept
# up — applied to the whole holder set it deleted the one holder shape that
# carries merge_result by definition (an upstream PR / pre-open anchor filed as
# an explicit merge-ordering block), and the downstream PR merged past it.
grep -q "PR#322 has unclosed rework/review bead upstream-322 (open, merge_result=pull_request)" <<< "$OUT1" \
  && ok "(20) live merge_result=pull_request blocker -> held (dep-edge holder survives the exclusion)" \
  || bad "(20) an upstream PR blocker must hold the merge (got: $OUT1)"
grep -q "PR#323 has unclosed rework/review bead kidanchor-323 (open, merge_result=pre_open_gate)" <<< "$OUT1" \
  && ok "(21) live merge_result=pre_open_gate dep child -> held, reason names the marker" \
  || bad "(21) a gating dep-linked child must hold the merge (got: $OUT1)"

# (9) already-merged anchor is NOT closed by the skill (the observer records it).
has '^bead-MERGED$' "$TMP/closed" && bad "(9) already-merged anchor must NOT be closed by the skill" \
                                  || ok "(9) already-merged anchor left for the observer"

# (INV) exactly five PRs were merged: the fully-validated gated head (301), the
# no-gate PR (311), the explicit opt-out (314), and the two whose only children
# cannot hold — wrong-end edges (319) and an already-closed child (320). No
# held/skipped anchor leaked.
eq "$(wc -l < "$TMP/merged" | tr -d ' ')" "5" "(INV) exactly five PRs merged (301 + 311 + 314 + 319 + 320)"

# Summary counters.
grep -q "5 merged" <<< "$OUT1" \
  && ok "run 1 summary reports 5 merged" || bad "run 1 summary merged count (got: $OUT1)"

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
eq "$(grep -c '^319$' "$TMP/merged")" "1" "(5c) wrong-end-edge anchor not re-merged on second pass"

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
