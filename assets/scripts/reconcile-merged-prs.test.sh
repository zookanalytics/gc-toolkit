#!/usr/bin/env bash
# Hermetic test for reconcile-merged-prs.sh (close-on-merge close pass).
#
# Stubs `gh` (PR state + auto-merge) and `gc` (bead-ledger list/close/update +
# mail) on PATH. No live city, Dolt, network, or real pull requests. Covers the
# four PR dispositions plus convergence:
#   (1) PR merged           -> anchor CLOSED "Merged to <target> at <sha>"
#   (2) PR closed, unmerged -> anchor ABANDONED (merge_result=abandoned,
#                              routed to human) + mayor escalated once
#   (3) PR open, ready       -> `gh pr merge --auto` queued
#   (4) PR open, draft       -> skipped (left to reconcile-draft-prs.sh)
#   (5) convergence: a closed anchor + an abandoned anchor leave the gating set,
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

# Gating anchors (gc bd list source): id|pr_number|merged_target
cat > "$TMP/anchors" <<'A'
bead-A|201|main
bead-B|202|main
bead-C|203|main
bead-D|204|main
A

# PR states (gh pr view source): pr|state|merged|isDraft|mergeOid|baseRefName
#   201 merged          -> close anchor bead-A
#   202 closed, unmerged -> abandon anchor bead-B + escalate
#   203 open, ready      -> queue auto-merge
#   204 open, draft      -> skip
cat > "$TMP/prs" <<'P'
201|MERGED|true|false|abc12345def67890|main
202|CLOSED|false|false||main
203|OPEN|false|false||main
204|OPEN|false|true||main
P

: > "$TMP/closed"; : > "$TMP/abandoned"; : > "$TMP/automerge"; : > "$TMP/mail"; : > "$TMP/closelog"

# --- gh stub: pr view (emit state JSON), pr merge (record auto-merge). --------
cat > "$TMP/bin/gh" <<'GH'
#!/usr/bin/env bash
case "$1 $2" in
  "pr view")
    num="$3"
    while IFS='|' read -r pr state merged isdraft oid base; do
      [ "$pr" = "$num" ] || continue
      jq -n --arg s "$state" --argjson m "$merged" --argjson d "$isdraft" \
            --arg o "$oid" --arg b "$base" \
        '{state:$s, merged:$m, isDraft:$d, mergeCommit:(if $o=="" then null else {oid:$o} end), baseRefName:$b}'
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
# bd list reflects state: a closed or abandoned anchor leaves the gating set,
# which is what makes the convergence assertion meaningful.
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
if [ "$1" = "mail" ]; then printf 'escalation\n' >> "$FAKE_MAIL"; exit 0; fi
[ "$1" = "bd" ] || exit 0
case "$2" in
  list)
    out=""
    while IFS='|' read -r id pr target; do
      [ -n "$id" ] || continue
      grep -qx "$id" "$FAKE_CLOSED" 2>/dev/null && continue
      grep -qx "$id" "$FAKE_ABANDONED" 2>/dev/null && continue
      obj=$(printf '{"id":"%s","metadata":{"pr_number":"%s","merged_target":"%s"}}' "$id" "$pr" "$target")
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
has '^bead-B$' "$TMP/abandoned" && ok "(2) closed-unmerged PR -> anchor abandoned" \
                                || bad "(2) closed-unmerged PR -> anchor abandoned"
eq "$(wc -l < "$TMP/mail" | tr -d ' ')" "1" "(2) abandoned PR escalates to mayor once"
has '^203$' "$TMP/automerge" && ok "(3) open ready PR -> auto-merge queued" \
                             || bad "(3) open ready PR -> auto-merge queued"
has '^bead-C$' "$TMP/closed" && bad "(3) ready anchor must NOT be closed" \
                             || ok "(3) ready anchor not closed"
has '^204$' "$TMP/automerge" && bad "(4) draft PR must NOT auto-merge" \
                             || ok "(4) draft PR not auto-merged"
has '^bead-D$' "$TMP/closed" && bad "(4) draft anchor must NOT be closed" \
                             || ok "(4) draft anchor not closed"
printf '%s\n' "$OUT1" | grep -q "1 closed, 1 abandoned" \
  && ok "run 1 summary reports 1 closed, 1 abandoned" \
  || bad "run 1 summary (got: $OUT1)"

# --- Run 2: convergence. bead-A (closed) + bead-B (abandoned) leave the set. --
MAIL_BEFORE=$(wc -l < "$TMP/mail" | tr -d ' ')
bash "$SCRIPT" >/dev/null
eq "$(grep -c '^bead-A$' "$TMP/closed")" "1" "(5) merged anchor not re-closed on second pass"
eq "$(wc -l < "$TMP/mail" | tr -d ' ')" "$MAIL_BEFORE" "(5) abandoned anchor not re-escalated on second pass"

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
