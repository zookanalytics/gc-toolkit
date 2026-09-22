#!/usr/bin/env bash
# pr-visit-comment-wiring.test.sh — proves the converse close paths produce the
# right PR-reminder update. The moot/benign silent close (converse-close-out.sh)
# closes the visit itself, so it reaches pr-visit-comment.sh directly, resolved
# off a candidate root — a recorder planted at
# $GC_RIG_ROOT/assets/scripts/pr-visit-comment.sh stands in and records the call.
# The normal sign-off (converse-signoff.sh) runs BEFORE the visit closes, so it
# must not post yet: it stashes the close text (gc.pr_visit_summary /
# gc.pr_visit_actions) on the visit, and converse-settle's close step or
# converse-claim.sh's stranded-finish recovery posts it after the close. The
# engage, dismiss and finish sites are covered by gc-helm.test.sh /
# gc-helm-engage.test.sh / converse-claim.test.sh, which own those harnesses.
#
# Hermetic: stubs gc and the takeaway writer; no city, no network, no gh.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SIGNOFF="$HERE/converse-signoff.sh"
CLOSEOUT="$HERE/converse-close-out.sh"
for f in "$SIGNOFF" "$CLOSEOUT"; do [ -r "$f" ] || { echo "not found: $f" >&2; exit 2; }; done
command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 2; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n        %s\n' "$1" "${2:-}"; }
has() { if grep -qF -- "$2" "$3"; then ok "$1"; else bad "$1" "missing '$2' in: $(cat "$3")"; fi; }

TMPD="$(mktemp -d "${TMPDIR:-/tmp}/pr-visit-comment-wiring.XXXXXX")"
trap 'rm -rf "$TMPD"' EXIT
BIN="$TMPD/bin"; mkdir -p "$BIN"

# A stub rig root the candidate loop finds first (GC_RIG_ROOT), carrying the
# recorder in place of pr-visit-comment.sh and a no-op gc-helm.sh for the
# sign-off's takeaway write.
SR="$TMPD/rig"; mkdir -p "$SR/assets/scripts"
cat >"$SR/assets/scripts/pr-visit-comment.sh" <<'REC'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${PVC_LOG:?}"
REC
chmod +x "$SR/assets/scripts/pr-visit-comment.sh"
cat >"$SR/assets/scripts/gc-helm.sh" <<'HELM'
#!/usr/bin/env bash
exit 0
HELM
chmod +x "$SR/assets/scripts/gc-helm.sh"

# gc stub: the visit names its subject via stall_root; the subject reads back a
# takeaway (so the sign-off's readback passes); every list is empty (no demand);
# `bd update` (the sign-off's PR-reminder stash) is logged to $GC_UPDATE_LOG;
# every other write succeeds.
cat >"$BIN/gc" <<'STUB'
#!/usr/bin/env bash
[ "${1:-}" = "bd" ] || exit 0
case "${2:-}" in
  show)
    id="${3:-}"
    case "$id" in
      tk-vis) jq -nc '[{id:"tk-vis",metadata:{stall_root:"tk-subj"}}]' ;;
      *)      jq -nc '[{id:"tk-subj",metadata:{"gc.takeaway":"we shipped it","gc.outcome":"moot"}}]' ;;
    esac ;;
  list)   printf '[]' ;;
  update) printf '%s\n' "$*" >> "${GC_UPDATE_LOG:-/dev/null}" ;;
  *) : ;;
esac
STUB
chmod +x "$BIN/gc"

echo "── converse-signoff.sh stashes the PR-reminder close text on the visit (posted only after the close) ──"
PVC_LOG="$TMPD/signoff.pvc"; : >"$PVC_LOG"
GC_UPDATE_LOG="$TMPD/signoff.upd"; : >"$GC_UPDATE_LOG"
( PATH="$BIN:$PATH" GC_RIG_ROOT="$SR" PVC_LOG="$PVC_LOG" GC_UPDATE_LOG="$GC_UPDATE_LOG" \
  bash "$SIGNOFF" --visit tk-vis --outcome "we shipped it" --ruled no --still-owed "await deploy" ) >/dev/null 2>&1
has "the stash lands on the visit" 'update tk-vis' "$GC_UPDATE_LOG"
has "the takeaway is stashed as the summary" 'gc.pr_visit_summary=we shipped it' "$GC_UPDATE_LOG"
has "what is still owed is stashed as the actions" 'gc.pr_visit_actions=still owed: await deploy' "$GC_UPDATE_LOG"
# The reminder is posted only AFTER the visit closes (converse-settle's close
# step, or the stranded-finish recovery), so the pre-close sign-off must not
# reach the tool — that ordering is the whole point of the fix.
if [ ! -s "$PVC_LOG" ]; then ok "the sign-off does not post the reminder before the close"
else bad "the sign-off does not post the reminder before the close" "PVC_LOG not empty: $(cat "$PVC_LOG")"; fi

echo "── converse-close-out.sh updates the reminder on a moot/benign close ──"
PVC_LOG="$TMPD/closeout.pvc"; : >"$PVC_LOG"
( PATH="$BIN:$PATH" GC_RIG_ROOT="$SR" PVC_LOG="$PVC_LOG" \
  VISIT=tk-vis SUBJECT=tk-subj bash "$CLOSEOUT" moot "the premise died before anyone claimed it" ) >/dev/null 2>&1
has "the reminder is closed for the visit, on its subject" \
    'close --visit tk-vis --subject tk-subj' "$PVC_LOG"
has "the outcome word is carried" '--outcome moot' "$PVC_LOG"
has "the reading is passed as the summary" '--summary the premise died before anyone claimed it' "$PVC_LOG"

echo
echo "pr-visit-comment-wiring: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
