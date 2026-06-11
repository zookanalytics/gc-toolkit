#!/usr/bin/env bash
# Hermetic test for reconcile-draft-prs.sh.
#
# Stubs `gh` (draft-PR enumeration + `pr ready`) and `gc` (bead-ledger
# queries) on PATH. No live city, Dolt, network, or real pull requests.
# Covers the guard matrix the reconciler must enforce:
#   (1) draft + CLOSED review bead + no open beads          -> un-drafted
#   (2) draft + CLOSED review bead + OPEN fix bead (pr_number) -> NOT un-drafted
#   (3) draft + NO review bead (e.g. a human's manual draft)  -> NOT un-drafted
#   (4) draft + IN_PROGRESS review bead (review still running) -> NOT un-drafted
#   (5) idempotent: a readied PR leaves the --draft set, so a second pass is
#       a no-op (convergence — the whole point of the reconciler).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/reconcile-draft-prs.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }
# Was PR number $1 handed to `gh pr ready`?
readied() { grep -qx "$1" "$TMP/readied" 2>/dev/null; }

mkdir -p "$TMP/bin"

# Draft PRs the bot owns (gh pr list output, before any are readied).
cat > "$TMP/drafts.json" <<'JSON'
[
  {"number":101,"headRefName":"polecat/tk-aaa"},
  {"number":102,"headRefName":"polecat/tk-bbb"},
  {"number":103,"headRefName":"polecat/tk-ccc"},
  {"number":104,"headRefName":"polecat/tk-ddd"}
]
JSON

# Fake bead ledger, one row per bead: pr_number|task_kind|status
#   101: review concluded (closed), nothing else open      -> reconcile
#   102: review concluded (closed) BUT an open fix bead     -> keep draft
#        (the REQUEST_CHANGES arm files a fix bead carrying pr_number, no task_kind)
#   103: (no rows) a human's manual draft, no review bead   -> keep draft
#   104: review still in_progress                           -> keep draft
cat > "$TMP/beads" <<'LEDGER'
101|review|closed
102|review|closed
102||open
104|review|in_progress
LEDGER

: > "$TMP/readied"

# --- gh stub: enumerate drafts (minus already-readied), record `pr ready`. ---
# Modeling "a readied PR is no longer a draft" is what makes the idempotency
# assertion meaningful: run 2 never re-sees PR 101.
cat > "$TMP/bin/gh" <<'GH'
#!/usr/bin/env bash
case "$1 $2" in
  "pr list")
    jq -c '.[]' "$FAKE_DRAFTS" | while read -r obj; do
      n=$(printf '%s' "$obj" | jq -r '.number')
      grep -qx "$n" "$FAKE_READIED" 2>/dev/null && continue
      printf '%s\n' "$obj"
    done | jq -s '.'
    ;;
  "pr ready")
    printf '%s\n' "$3" >> "$FAKE_READIED"
    ;;
esac
exit 0
GH
chmod +x "$TMP/bin/gh"

# --- gc stub: gc bd list --metadata-field K=V ... --status S --json. ----------
# Returns the first ledger row matching ALL metadata filters and the status
# set, shaped as `[{"id":...}]` (only .[0].id is consumed), else `[]`.
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
[ "$1" = "bd" ] && [ "$2" = "list" ] || exit 0
shift 2
want_pr=""; want_kind=""; statuses=""
while [ $# -gt 0 ]; do
  case "$1" in
    --metadata-field)
      case "$2" in
        pr_number=*) want_pr="${2#pr_number=}" ;;
        task_kind=*) want_kind="${2#task_kind=}" ;;
      esac
      shift 2 ;;
    --status) statuses="$2"; shift 2 ;;
    *) shift ;;
  esac
done
match=""
while IFS='|' read -r pr kind status; do
  [ -n "$pr" ] || continue
  [ -n "$want_pr" ] && [ "$pr" != "$want_pr" ] && continue
  [ -n "$want_kind" ] && [ "$kind" != "$want_kind" ] && continue
  if [ -n "$statuses" ]; then
    case ",$statuses," in *",$status,"*) : ;; *) continue ;; esac
  fi
  match="bead-${pr}"
  break
done < "$FAKE_BEADS"
[ -n "$match" ] && printf '[{"id":"%s"}]\n' "$match" || printf '[]\n'
exit 0
GC
chmod +x "$TMP/bin/gc"

export PATH="$TMP/bin:$PATH"
export FAKE_DRAFTS="$TMP/drafts.json" FAKE_READIED="$TMP/readied" FAKE_BEADS="$TMP/beads"

# --- Run 1: the guard matrix. ------------------------------------------------
OUT1="$(bash "$SCRIPT")"
readied 101 && ok "(1) closed review + no open beads -> un-drafted" \
            || bad "(1) closed review + no open beads -> un-drafted"
readied 102 && bad "(2) open fix bead -> must NOT un-draft" \
            || ok "(2) closed review + open fix bead -> NOT un-drafted"
readied 103 && bad "(3) no review bead -> must NOT un-draft" \
            || ok "(3) no review bead (human draft) -> NOT un-drafted"
readied 104 && bad "(4) in_progress review -> must NOT un-draft" \
            || ok "(4) review still in_progress -> NOT un-drafted"
eq "$(wc -l < "$TMP/readied" | tr -d ' ')" "1" "exactly one PR reconciled in run 1"
printf '%s\n' "$OUT1" | grep -q "1 reconciled" \
  && ok "run 1 summary reports 1 reconciled" \
  || bad "run 1 summary reports 1 reconciled (got: $OUT1)"

# --- Run 2: idempotent. PR 101 is no longer a draft; nothing new is readied. --
bash "$SCRIPT" >/dev/null
eq "$(wc -l < "$TMP/readied" | tr -d ' ')" "1" "second pass is a no-op (convergent/idempotent)"

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
