#!/usr/bin/env bash
# Hermetic test for reconcile-merged-prs.sh (close-on-land DETECT-ONLY observer).
#
# Stubs `gh` (PR state) and `gc` (bead-ledger list/close/update + mail) on PATH.
# No live city, Dolt, network, or real pull requests. The observer RECORDS merges
# it observes and ESCALATES discrepancies, but it has NO merge authority — the
# merge itself is the merge skill's job (merge-skill.sh, tested separately in
# merge-skill.test.sh). Covers the observer's dispositions + the no-merge
# invariant + convergence:
#   (1) PR merged              -> anchor CLOSED "Merged to <target> at <sha>"
#   (2) PR closed, unmerged    -> anchor flagged (merge_result=abandoned,
#                                 routed to human) + mayor escalated once
#   (3) PR open, ready          -> DETECT-ONLY: anchor left OPEN, the observer
#                                 never merges and never closes it
#   (4) PR open, draft          -> skipped (drafts retired; a stray draft is left alone)
#   (7) PR open, ready BUT live base != anchor target (retargeted after
#        publication) -> anchor flagged merge_result=retargeted + routed to
#        human + escalated once; never closed as landed
#   (8) PR merged BUT to a base != anchor target (retargeted) -> anchor NOT
#        closed as landed (would record a landing that never happened); flagged
#        retargeted + escalated once.
#   (INV) the observer NEVER runs `gh pr merge` for ANY anchor — no merge authority.
#   (5) convergence: closed / flagged / retargeted anchors leave the gating set,
#       so a second pass does not re-close, re-escalate, or re-flag them.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/reconcile-merged-prs.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }
has() { grep -q "$1" "$2" 2>/dev/null; }

mkdir -p "$TMP/bin"

# Gating anchors (gc bd list source): id|pr_number|merged_target
#   bead-A merged to main            -> closed (observed merge recorded)
#   bead-B closed unmerged           -> flagged abandoned + escalated
#   bead-C open, ready               -> left OPEN (the merge skill lands it, not us)
#   bead-D open, draft               -> skipped
#   bead-H open, ready, retargeted   -> flagged retargeted + escalated, never closed
#   bead-I merged to wrong base      -> NOT closed as landed; flagged retargeted
cat > "$TMP/anchors" <<'A'
bead-A|201|main
bead-B|202|main
bead-C|203|main
bead-D|204|main
bead-H|208|main
bead-I|209|main
A

# PR states (gh pr view source): pr|state|mergedAt|isDraft|mergeOid|baseRefName
#   201 merged to main            -> close anchor bead-A (mergedAt set = merge)
#   202 closed, unmerged          -> flag anchor bead-B + escalate
#   203 open, ready               -> observer leaves it (detect-only)
#   204 open, draft               -> skip
#   208 open, base=integration/foo != main -> retarget (flagged, never merged)
#   209 merged BUT to integration/foo != main -> retarget (NOT closed as landed)
cat > "$TMP/prs" <<'P'
201|MERGED|2026-06-23T01:00:00Z|false|abc12345def67890|main
202|CLOSED||false||main
203|OPEN||false||main
204|OPEN||true||main
208|OPEN||false||integration/foo
209|MERGED|2026-06-23T02:00:00Z|false|cafe1234abcd5678|integration/foo
P

: > "$TMP/closed"; : > "$TMP/abandoned"; : > "$TMP/retargeted"
: > "$TMP/automerge"; : > "$TMP/mail"; : > "$TMP/closelog"

# --- gh stub: pr view (emit state JSON), pr merge (record any merge attempt). --
# The `pr view` arm VALIDATES the requested `--json` fields against the set a
# supported gh actually exposes for a PR, and errors (exit 1, like real gh) on
# any unknown field. This is the regression guard for the field-shape bug:
# `merged` is NOT a pr-view field (`mergedAt` is), so a buggy
# `--json ...merged...` empties PR_JSON and the disposition matrix below fails —
# exactly the real-world failure where close-on-land silently closes nothing.
#
# The `pr merge` arm records to $FAKE_AUTOMERGE. The observer must NEVER reach it
# (it has no merge authority): the INV assertion below proves that file stays
# empty across the whole run. The merge skill's own test exercises real merges.
cat > "$TMP/bin/gh" <<'GH'
#!/usr/bin/env bash
case "$1 $2" in
  "pr view")
    num="$3"; shift 3
    fields=""
    while [ $# -gt 0 ]; do case "$1" in --json) fields="$2"; shift 2 ;; *) shift ;; esac; done
    # Supported `gh pr view --json` fields (subset; notably NOT `merged`).
    SUPPORTED=" number state mergedAt mergeCommit isDraft baseRefName headRefName headRefOid url title body author additions deletions mergeable mergeStateStatus "
    OIFS="$IFS"; IFS=','
    for f in $fields; do
      case "$SUPPORTED" in
        *" $f "*) : ;;
        *) IFS="$OIFS"; echo "Unknown JSON field: \"$f\"" >&2; exit 1 ;;
      esac
    done
    IFS="$OIFS"
    while IFS='|' read -r pr state mergedat isdraft oid base; do
      [ "$pr" = "$num" ] || continue
      jq -n --arg s "$state" --arg ma "$mergedat" --argjson d "$isdraft" \
            --arg o "$oid" --arg b "$base" \
        '{state:$s, mergedAt:(if $ma=="" then null else $ma end), isDraft:$d, mergeCommit:(if $o=="" then null else {oid:$o} end), baseRefName:$b}'
      exit 0
    done < "$FAKE_PRS"
    exit 0 ;;
  "pr merge")
    printf '%s\n' "$3" >> "$FAKE_AUTOMERGE" ;;
esac
exit 0
GH
chmod +x "$TMP/bin/gh"

# --- gc stub: bd list / bd close / bd update + mail. --------------------------
# bd list reflects state: a closed, flagged (abandoned), or retargeted anchor
# leaves the gating set, which is what makes the convergence assertion
# meaningful. Only the gating-anchor scan is modeled —
# `--metadata-field merge_result=pull_request` — because the detect-only observer
# does NOT scan referencing children (that hold moved to the merge skill).
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
if [ "$1" = "mail" ]; then
  shift; subj=""
  while [ $# -gt 0 ]; do case "$1" in -s) subj="$2"; shift 2 ;; *) shift ;; esac; done
  printf '%s\n' "$subj" >> "$FAKE_MAIL"; exit 0
fi
[ "$1" = "bd" ] || exit 0
case "$2" in
  list)
    case "$*" in
      *"merge_result=pull_request"*)
        out=""
        while IFS='|' read -r id pr target; do
          [ -n "$id" ] || continue
          grep -qx "$id" "$FAKE_CLOSED" 2>/dev/null && continue
          grep -qx "$id" "$FAKE_ABANDONED" 2>/dev/null && continue
          grep -qx "$id" "$FAKE_RETARGETED" 2>/dev/null && continue
          obj=$(printf '{"id":"%s","metadata":{"pr_number":"%s","merged_target":"%s"}}' "$id" "$pr" "$target")
          if [ -z "$out" ]; then out="$obj"; else out="$out,$obj"; fi
        done < "$FAKE_ANCHORS"
        printf '[%s]\n' "$out" ;;
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
      *merge_result=abandoned*)  printf '%s\n' "$id" >> "$FAKE_ABANDONED" ;;
      *merge_result=retargeted*) printf '%s\n' "$id" >> "$FAKE_RETARGETED" ;;
    esac ;;
esac
exit 0
GC
chmod +x "$TMP/bin/gc"

export PATH="$TMP/bin:$PATH"
export FAKE_ANCHORS="$TMP/anchors" FAKE_PRS="$TMP/prs" \
       FAKE_CLOSED="$TMP/closed" FAKE_ABANDONED="$TMP/abandoned" \
       FAKE_RETARGETED="$TMP/retargeted" \
       FAKE_AUTOMERGE="$TMP/automerge" FAKE_MAIL="$TMP/mail" FAKE_CLOSELOG="$TMP/closelog"

# --- Run 1: the disposition matrix. ------------------------------------------
OUT1="$(bash "$SCRIPT")"

has '^bead-A$' "$TMP/closed" && ok "(1) merged PR -> anchor closed" \
                             || bad "(1) merged PR -> anchor closed"
grep -q 'Merged to main at abc12345' "$TMP/closelog" \
  && ok "(1) close reason names target + short merge sha" \
  || bad "(1) close reason names target + short merge sha (got: $(cat "$TMP/closelog"))"
has '^bead-B$' "$TMP/abandoned" && ok "(2) closed-unmerged PR -> anchor flagged" \
                                || bad "(2) closed-unmerged PR -> anchor flagged"
eq "$(grep -c 'out-of-band close of PR#202' "$TMP/mail")" "1" \
   "(2) out-of-band close escalates to mayor once"
has '^bead-C$' "$TMP/closed" && bad "(3) ready anchor must NOT be closed by the observer" \
                             || ok "(3) ready PR -> anchor left OPEN (detect-only; merge skill lands it)"
has '^bead-D$' "$TMP/closed" && bad "(4) draft anchor must NOT be closed" \
                             || ok "(4) draft PR -> anchor not closed"
# (7) retargeted open PR: flagged + escalated, never closed.
has '^bead-H$' "$TMP/retargeted" && ok "(7) retargeted open anchor flagged merge_result=retargeted" \
                                 || bad "(7) retargeted open anchor flagged merge_result=retargeted"
has '^bead-H$' "$TMP/closed" && bad "(7) retargeted open anchor must NOT be closed" \
                             || ok "(7) retargeted open anchor not closed as landed"
eq "$(grep -c 'PR#208 retargeted' "$TMP/mail")" "1" "(7) retarget escalates to mayor once"
# (8) merged-to-wrong-base: NOT closed as landed, flagged retargeted.
has '^bead-I$' "$TMP/closed" && bad "(8) merged-to-wrong-base anchor must NOT be closed" \
                             || ok "(8) merged-to-wrong-base anchor not closed as landed"
has '^bead-I$' "$TMP/retargeted" && ok "(8) merged-to-wrong-base anchor flagged retargeted" \
                                 || bad "(8) merged-to-wrong-base anchor flagged retargeted"
eq "$(grep -c 'PR#209 retargeted' "$TMP/mail")" "1" "(8) merged-to-wrong-base escalates once"

# (INV) NO MERGE AUTHORITY: the observer must never call `gh pr merge` for ANY
# anchor — the seam that the auto-merge retirement turns on. $FAKE_AUTOMERGE
# stays empty across the entire run (ready, draft, retargeted, merged alike).
eq "$(wc -l < "$TMP/automerge" | tr -d ' ')" "0" \
   "(INV) observer never runs 'gh pr merge' (detect-only, no merge authority)"

# Summary counters + the absence of any auto-merge wording.
printf '%s\n' "$OUT1" | grep -q "1 closed, 1 abandoned" \
  && ok "run 1 summary reports 1 closed, 1 abandoned" \
  || bad "run 1 summary (got: $OUT1)"
printf '%s\n' "$OUT1" | grep -q "2 retargeted" \
  && ok "run 1 summary reports 2 retargeted" \
  || bad "run 1 summary retargeted count (got: $OUT1)"
printf '%s\n' "$OUT1" | grep -qi "auto-merge" \
  && bad "run 1 summary must not mention auto-merge (it was retired)" \
  || ok "run 1 summary makes no mention of auto-merge"

# --- Regression guard (field shape): only gh-supported --json fields. ---------
# The stub models real gh: it REJECTS `merged` (the field the original bug
# requested) and ACCEPTS the script's real field set. The disposition matrix
# above already exercises this end-to-end (the script would skip every anchor on
# a rejected field); these direct probes document the contract so a reintroduced
# `merged` fails loudly with an obvious message.
gh pr view 201 --json merged >/dev/null 2>&1 \
  && bad "(6) gh stub must REJECT unsupported field 'merged' (models real gh)" \
  || ok "(6) unsupported --json field 'merged' rejected (guards the field-shape bug)"
gh pr view 201 --json state,mergedAt,mergeCommit,isDraft,baseRefName >/dev/null 2>&1 \
  && ok "(6) the script's --json field set is accepted by the gh stub" \
  || bad "(6) the script's --json field set must be accepted"

# --- Run 2: convergence. Closed / flagged / retargeted anchors leave the set. -
MAIL_BEFORE=$(wc -l < "$TMP/mail" | tr -d ' ')
bash "$SCRIPT" >/dev/null
eq "$(grep -c '^bead-A$' "$TMP/closed")" "1" "(5) merged anchor not re-closed on second pass"
eq "$(wc -l < "$TMP/mail" | tr -d ' ')" "$MAIL_BEFORE" "(5) flagged + retargeted anchors not re-escalated on second pass"

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
