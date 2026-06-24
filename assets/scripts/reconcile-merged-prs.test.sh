#!/usr/bin/env bash
# Hermetic test for reconcile-merged-prs.sh (close-on-land close pass).
#
# Stubs `gh` (PR state + auto-merge) and `gc` (bead-ledger list/close/update +
# mail) on PATH. No live city, Dolt, network, or real pull requests. Covers the
# PR dispositions plus the signoff-head merge gate and convergence:
#   (1) PR merged              -> anchor CLOSED "Merged to <target> at <sha>"
#   (2) PR closed, unmerged    -> anchor flagged (merge_result=abandoned,
#                                 routed to human) + mayor escalated once
#   (3) PR open, ready, head signoff-validated -> `gh pr merge --auto` queued
#   (4) PR open, draft          -> skipped (left to reconcile-draft-prs.sh)
#   (3b) PR open, ready, signoff_head STALE  -> auto-merge HELD
#   (3c) PR open, ready, signoff_head MISSING -> auto-merge HELD
#   (5) convergence: a closed anchor + a flagged anchor leave the gating set,
#       so a second pass does not re-close or re-escalate them.
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

# Gating anchors (gc bd list source): id|pr_number|merged_target|signoff_head
#   bead-C carries signoff_head == PR 203's live head  -> auto-merge ALLOWED
#   bead-E carries a STALE signoff_head (!= PR 205 head) -> auto-merge HELD
#   bead-F carries NO signoff_head                       -> auto-merge HELD
cat > "$TMP/anchors" <<'A'
bead-A|201|main|
bead-B|202|main|
bead-C|203|main|HEADC0000000
bead-D|204|main|
bead-E|205|main|STALE0000000
bead-F|206|main|
A

# PR states (gh pr view source): pr|state|mergedAt|isDraft|mergeOid|baseRefName|headRefOid
#   201 merged           -> close anchor bead-A   (mergedAt set = authoritative merge)
#   202 closed, unmerged -> flag anchor bead-B + escalate
#   203 open, ready, head==signoff -> queue auto-merge
#   204 open, draft      -> skip
#   205 open, ready, head!=signoff (stale) -> hold auto-merge
#   206 open, ready, no signoff on anchor  -> hold auto-merge
cat > "$TMP/prs" <<'P'
201|MERGED|2026-06-23T01:00:00Z|false|abc12345def67890|main|HEAD20100000
202|CLOSED||false||main|HEAD20200000
203|OPEN||false||main|HEADC0000000
204|OPEN||true||main|HEAD20400000
205|OPEN||false||main|HEAD20500000
206|OPEN||false||main|HEAD20600000
P

: > "$TMP/closed"; : > "$TMP/abandoned"; : > "$TMP/automerge"; : > "$TMP/mail"; : > "$TMP/closelog"

# --- gh stub: pr view (emit state JSON), pr merge (record auto-merge). --------
# The `pr view` arm VALIDATES the requested `--json` fields against the set a
# supported gh actually exposes for a PR, and errors (exit 1, like real gh) on
# any unknown field. This is the regression guard for the field-shape bug:
# `merged` is NOT a pr-view field (`mergedAt` is), so a buggy
# `--json ...merged...` empties PR_JSON and the disposition matrix below fails —
# exactly the real-world failure where close-on-land silently closes nothing.
cat > "$TMP/bin/gh" <<'GH'
#!/usr/bin/env bash
case "$1 $2" in
  "pr view")
    num="$3"; shift 3
    fields=""
    while [ $# -gt 0 ]; do case "$1" in --json) fields="$2"; shift 2 ;; *) shift ;; esac; done
    # Supported `gh pr view --json` fields (subset; notably NOT `merged`).
    SUPPORTED=" number state mergedAt mergeCommit isDraft baseRefName headRefName headRefOid url title body author additions deletions mergeable "
    OIFS="$IFS"; IFS=','
    for f in $fields; do
      case "$SUPPORTED" in
        *" $f "*) : ;;
        *) IFS="$OIFS"; echo "Unknown JSON field: \"$f\"" >&2; exit 1 ;;
      esac
    done
    IFS="$OIFS"
    while IFS='|' read -r pr state mergedat isdraft oid base headoid; do
      [ "$pr" = "$num" ] || continue
      jq -n --arg s "$state" --arg ma "$mergedat" --argjson d "$isdraft" \
            --arg o "$oid" --arg b "$base" --arg h "$headoid" \
        '{state:$s, mergedAt:(if $ma=="" then null else $ma end), isDraft:$d, mergeCommit:(if $o=="" then null else {oid:$o} end), baseRefName:$b, headRefOid:$h}'
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
# bd list reflects state: a closed or flagged anchor leaves the gating set,
# which is what makes the convergence assertion meaningful.
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
if [ "$1" = "mail" ]; then printf 'escalation\n' >> "$FAKE_MAIL"; exit 0; fi
[ "$1" = "bd" ] || exit 0
case "$2" in
  list)
    out=""
    while IFS='|' read -r id pr target signoff; do
      [ -n "$id" ] || continue
      grep -qx "$id" "$FAKE_CLOSED" 2>/dev/null && continue
      grep -qx "$id" "$FAKE_ABANDONED" 2>/dev/null && continue
      obj=$(printf '{"id":"%s","metadata":{"pr_number":"%s","merged_target":"%s","signoff_head":"%s"}}' "$id" "$pr" "$target" "$signoff")
      if [ -z "$out" ]; then out="$obj"; else out="$out,$obj"; fi
    done < "$FAKE_ANCHORS"
    printf '[%s]\n' "$out" ;;
  close)
    id="$3"; shift 3
    reason=""
    while [ $# -gt 0 ]; do case "$1" in --reason) reason="$2"; shift 2 ;; *) shift ;; esac; done
    printf '%s\n' "$id" >> "$FAKE_CLOSED"
    printf '%s\t%s\n' "$id" "$reason" >> "$FAKE_CLOSELOG" ;;
  update)
    id="$3"
    case "$*" in *merge_result=abandoned*) printf '%s\n' "$id" >> "$FAKE_ABANDONED" ;; esac ;;
esac
exit 0
GC
chmod +x "$TMP/bin/gc"

export PATH="$TMP/bin:$PATH"
export FAKE_ANCHORS="$TMP/anchors" FAKE_PRS="$TMP/prs" \
       FAKE_CLOSED="$TMP/closed" FAKE_ABANDONED="$TMP/abandoned" \
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
eq "$(wc -l < "$TMP/mail" | tr -d ' ')" "1" "(2) out-of-band close escalates to mayor once"
has '^203$' "$TMP/automerge" && ok "(3) ready PR, head signoff-validated -> auto-merge queued" \
                             || bad "(3) ready PR, head signoff-validated -> auto-merge queued"
has '^bead-C$' "$TMP/closed" && bad "(3) ready anchor must NOT be closed" \
                             || ok "(3) ready anchor not closed"
has '^204$' "$TMP/automerge" && bad "(4) draft PR must NOT auto-merge" \
                             || ok "(4) draft PR not auto-merged"
has '^bead-D$' "$TMP/closed" && bad "(4) draft anchor must NOT be closed" \
                             || ok "(4) draft anchor not closed"
# The signoff-head gate: a stale or missing signoff_head holds auto-merge.
has '^205$' "$TMP/automerge" && bad "(3b) stale signoff_head must HOLD auto-merge" \
                             || ok "(3b) ready PR with stale signoff_head -> auto-merge held"
has '^206$' "$TMP/automerge" && bad "(3c) missing signoff_head must HOLD auto-merge" \
                             || ok "(3c) ready PR with no signoff_head -> auto-merge held"
printf '%s\n' "$OUT1" | grep -q "1 closed, 1 abandoned" \
  && ok "run 1 summary reports 1 closed, 1 abandoned" \
  || bad "run 1 summary (got: $OUT1)"
printf '%s\n' "$OUT1" | grep -q "1 auto-merge queued" \
  && ok "run 1 summary reports exactly 1 auto-merge queued (only the validated head)" \
  || bad "run 1 summary auto-merge count (got: $OUT1)"

# --- Regression guard (field shape): only gh-supported --json fields. ---------
# The stub models real gh: it REJECTS `merged` (the field the original bug
# requested) and ACCEPTS `mergedAt`/`headRefOid`. The disposition matrix above
# already exercises this end-to-end (the script would skip every anchor on a
# rejected field); these direct probes document the contract so a reintroduced
# `merged` fails loudly with an obvious message.
gh pr view 201 --json merged >/dev/null 2>&1 \
  && bad "(6) gh stub must REJECT unsupported field 'merged' (models real gh)" \
  || ok "(6) unsupported --json field 'merged' rejected (guards the field-shape bug)"
gh pr view 201 --json state,mergedAt,mergeCommit,isDraft,baseRefName,headRefOid >/dev/null 2>&1 \
  && ok "(6) the script's --json field set is accepted by the gh stub" \
  || bad "(6) the script's --json field set must be accepted"

# --- Run 2: convergence. bead-A (closed) + bead-B (flagged) leave the set. ----
MAIL_BEFORE=$(wc -l < "$TMP/mail" | tr -d ' ')
bash "$SCRIPT" >/dev/null
eq "$(grep -c '^bead-A$' "$TMP/closed")" "1" "(5) merged anchor not re-closed on second pass"
eq "$(wc -l < "$TMP/mail" | tr -d ' ')" "$MAIL_BEFORE" "(5) flagged anchor not re-escalated on second pass"

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
