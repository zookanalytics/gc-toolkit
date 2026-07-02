#!/usr/bin/env bash
# Hermetic test for pre-open-resolve.sh (the pre-open codex gate's PR-create pass,
# tk-6d0vb.1.8). Stubs `gh` (branch head, existing-PR lookup, the real pr create)
# and `gc` (bead-ledger list/show/update) on PATH. No live city, Dolt, network, or
# real pull requests.
#
# The pass opens the PR for each pre_open_gate anchor once codex is green at the
# branch head, then flips it to pull_request → the unchanged merge gate. Covered:
#   (GREEN)  no PR yet + check.codex green@<live head> -> `gh pr create` (non-draft)
#            at that head + flip to pull_request with the new pr_url/pr_number.
#   (STALE)  no PR + check.codex green@<OLD head> != live head -> HELD (no create,
#            no flip): a rework advanced the head, the marker must re-earn it.
#   (MISS)   no PR + no check.codex marker -> HELD (codex not done).
#   (HASPR)  branch already has an open PR (a sibling anchor opened it) -> flipped
#            to pull_request (record the existing pr), NEVER a second `gh pr create`
#            — this is the orphan-convoy convergence.
#   (INV)    `gh pr create` is reached for EXACTLY the one green no-PR anchor.
#   (CONV)   convergence: a flipped anchor leaves the pre_open_gate set, so a
#            second pass neither re-creates nor re-flips it.
#   (FS)     the pass gates codex-only (the branch may carry other pending checks);
#            a green codex marker alone opens the PR.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/pre-open-resolve.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }
has() { grep -q "$1" "$2" 2>/dev/null; }

mkdir -p "$TMP/bin"

# Pre-open-gated anchors (gc bd list source): id|branch|merged_target|check.codex
#   bead-GREEN : green at the live head            -> open PR + flip
#   bead-STALE : green at an OLD head (rework moved it) -> held
#   bead-MISS  : no marker (codex not done)        -> held
#   bead-HASPR : branch already has an open PR      -> flip (no second create)
cat > "$TMP/anchors" <<'A'
bead-GREEN|polecat/feat-a|main|green@HEADA
bead-STALE|polecat/feat-b|main|green@OLDB
bead-MISS|polecat/feat-c|main|
bead-HASPR|polecat/feat-d|main|green@HEADD
A

# Live branch heads (gh api .../commits/<branch> -> .sha):
cat > "$TMP/heads" <<'H'
polecat/feat-a|HEADA
polecat/feat-b|HEADB
polecat/feat-c|HEADC
polecat/feat-d|HEADD
H

# Existing OPEN PRs by branch (gh pr list --head <branch>): only feat-d has one.
cat > "$TMP/existpr" <<'E'
polecat/feat-d|404|https://github.com/o/r/pull/404
E

# What `gh pr create --head <branch>` produces (branch|number|url): only feat-a
# reaches create (it is the sole green, no-PR anchor).
cat > "$TMP/newpr" <<'N'
polecat/feat-a|501|https://github.com/o/r/pull/501
N

# Review beads carrying the codex verdict (anchor_id|review_id) + notes.
cat > "$TMP/reviews" <<'R'
bead-GREEN|rev-green
R
cat > "$TMP/notes" <<'NT'
rev-green|Codex signoff: LGTM (pre-open).
NT

: > "$TMP/created"; : > "$TMP/fliplog"; : > "$TMP/flipped"; : > "$TMP/comments"

# --- gh stub: api (branch head), pr list/create/view/comment. -----------------
cat > "$TMP/bin/gh" <<'GH'
#!/usr/bin/env bash
cmd="$1"; sub="${2:-}"
if [ "$cmd" = "api" ]; then
  # gh api "repos/{owner}/{repo}/commits/<branch>" --jq .sha  -> emit the head oid
  path="$2"
  branch=$(printf '%s' "$path" | sed 's#^repos/[^/]*/[^/]*/commits/##')
  awk -F'|' -v b="$branch" '$1==b{print $2; exit}' "$FAKE_HEADS"
  exit 0
fi
case "$cmd $sub" in
  "pr list")   # --head <branch> --state open --json number,url --limit 1
    head=""; shift 2
    while [ $# -gt 0 ]; do case "$1" in --head) head="$2"; shift 2 ;; *) shift ;; esac; done
    row=$(awk -F'|' -v b="$head" '$1==b{print; exit}' "$FAKE_EXISTPR")
    if [ -n "$row" ]; then
      num=$(printf '%s' "$row" | cut -d'|' -f2); url=$(printf '%s' "$row" | cut -d'|' -f3)
      jq -n --arg n "$num" --arg u "$url" '[{number:($n|tonumber), url:$u}]'
    else printf '[]\n'; fi ;;
  "pr create") # --base X --head <branch> --title T --body-file F
    head=""; shift 2
    while [ $# -gt 0 ]; do case "$1" in --head) head="$2"; shift 2 ;; *) shift ;; esac; done
    row=$(awk -F'|' -v b="$head" '$1==b{print; exit}' "$FAKE_NEWPR")
    if [ -n "$row" ]; then
      printf '%s\n' "$head" >> "$FAKE_CREATED"
      printf '%s\n' "$(printf '%s' "$row" | cut -d'|' -f3)"   # the new PR url
    fi ;;
  "pr view")   # <arg> --json <field> -q <expr>   (arg = branch for url, url for number)
    arg="$3"; shift 3
    field=""
    while [ $# -gt 0 ]; do case "$1" in --json) field="$2"; shift 2 ;; *) shift ;; esac; done
    case "$field" in
      url)    awk -F'|' -v b="$arg" '$1==b{print $3; exit}' "$FAKE_NEWPR" "$FAKE_EXISTPR" ;;
      number) awk -F'|' -v u="$arg" '$3==u{print $2; exit}' "$FAKE_NEWPR" "$FAKE_EXISTPR" ;;
    esac ;;
  "pr comment") # <num> --body ...
    printf '%s\n' "$3" >> "$FAKE_COMMENTS" ;;
esac
exit 0
GH
chmod +x "$TMP/bin/gh"

# --- gc stub: bd list (anchors + review lookup), bd show (notes), bd update. ---
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
[ "$1" = "bd" ] || exit 0
case "$2" in
  list)
    case "$*" in
      *"merge_result=pre_open_gate"*)
        out=""
        while IFS='|' read -r id branch target codexmark; do
          [ -n "$id" ] || continue
          grep -qx "$id" "$FAKE_FLIPPED" 2>/dev/null && continue   # convergence
          obj=$(printf '{"id":"%s","title":"impl %s","description":"desc %s","metadata":{"branch":"%s","merged_target":"%s","check.codex":"%s","merge_result":"pre_open_gate"}}' \
            "$id" "$id" "$id" "$branch" "$target" "$codexmark")
          if [ -z "$out" ]; then out="$obj"; else out="$out,$obj"; fi
        done < "$FAKE_ANCHORS"
        printf '[%s]\n' "$out" ;;
      *"task_kind=review"*)
        aid=$(printf '%s' "$*" | sed -n 's/.*anchor_bead=\([^ ]*\).*/\1/p')
        rid=$(awk -F'|' -v a="$aid" '$1==a{print $2; exit}' "$FAKE_REVIEWS" 2>/dev/null)
        if [ -n "$rid" ]; then printf '[{"id":"%s","updated_at":"1"}]\n' "$rid"; else printf '[]\n'; fi ;;
      *) printf '[]\n' ;;
    esac ;;
  show)
    rid="$3"
    notes=$(awk -F'|' -v r="$rid" '$1==r{print $2; exit}' "$FAKE_NOTES" 2>/dev/null)
    jq -n --arg n "$notes" '[{notes:$n}]' ;;
  update)
    id="$3"
    case "$*" in
      *merge_result=pull_request*)
        prnum=$(printf '%s' "$*" | sed -n 's/.*pr_number=\([0-9][0-9]*\).*/\1/p')
        printf '%s\t%s\n' "$id" "$prnum" >> "$FAKE_FLIPLOG"
        printf '%s\n' "$id" >> "$FAKE_FLIPPED" ;;
    esac ;;
esac
exit 0
GC
chmod +x "$TMP/bin/gc"

export PATH="$TMP/bin:$PATH"
export FAKE_ANCHORS="$TMP/anchors" FAKE_HEADS="$TMP/heads" FAKE_EXISTPR="$TMP/existpr" \
       FAKE_NEWPR="$TMP/newpr" FAKE_REVIEWS="$TMP/reviews" FAKE_NOTES="$TMP/notes" \
       FAKE_CREATED="$TMP/created" FAKE_FLIPLOG="$TMP/fliplog" FAKE_FLIPPED="$TMP/flipped" \
       FAKE_COMMENTS="$TMP/comments"

# --- Run 1. -------------------------------------------------------------------
OUT1="$(bash "$SCRIPT")"

# (GREEN) the sole green no-PR anchor: PR created at its branch + flipped.
has '^polecat/feat-a$' "$TMP/created" \
  && ok "(GREEN) green no-PR anchor -> 'gh pr create' at its branch" \
  || bad "(GREEN) green anchor -> PR created"
grep -q '^bead-GREEN	501$' "$TMP/fliplog" \
  && ok "(GREEN) flipped to pull_request with the NEW pr_number (501)" \
  || bad "(GREEN) flip records new pr_number (got: $(cat "$TMP/fliplog"))"
printf '%s\n' "$OUT1" | grep -q "bead-GREEN opened PR#501" \
  && ok "(GREEN) summary names the opened PR" || bad "(GREEN) open summary (got: $OUT1)"

# (STALE) marker at an old head -> held, NOT created, NOT flipped.
has '^polecat/feat-b$' "$TMP/created" && bad "(STALE) must NOT create a PR" \
                                      || ok "(STALE) no PR created"
grep -q '^bead-STALE	' "$TMP/fliplog" && bad "(STALE) must NOT flip" || ok "(STALE) not flipped"
printf '%s\n' "$OUT1" | grep -q "bead-STALE .* codex not green at live head" \
  && ok "(STALE) held, reason names the stale marker" || bad "(STALE) hold reason (got: $OUT1)"

# (MISS) no marker -> held.
has '^polecat/feat-c$' "$TMP/created" && bad "(MISS) must NOT create a PR" \
                                      || ok "(MISS) no PR created"
grep -q '^bead-MISS	' "$TMP/fliplog" && bad "(MISS) must NOT flip" || ok "(MISS) not flipped"

# (HASPR) branch already has a PR -> flipped to that PR, NO second create.
grep -q '^bead-HASPR	404$' "$TMP/fliplog" \
  && ok "(HASPR) existing-PR branch -> flipped to pull_request with the existing pr_number (404)" \
  || bad "(HASPR) flip records existing pr_number (got: $(cat "$TMP/fliplog"))"
has '^polecat/feat-d$' "$TMP/created" && bad "(HASPR) must NOT open a second PR" \
                                      || ok "(HASPR) no second PR created (orphan-convoy convergence)"

# (STATE) the existing-PR lookup must query --state all, not --state open: a
# parent stranded in pre_open_gate after a pre-open rework, whose sibling PR has
# already MERGED, must still flip onto the pull_request scan the merged-close
# observer watches (reconcile-merged-prs.sh scans only pull_request). A --state
# open lookup would miss the merged sibling and strand the parent open forever.
grep -qF 'gh pr list --head "$branch" --state all' "$SCRIPT" \
  && ok "(STATE) existing-PR lookup uses --state all (a merged/closed sibling PR still flips the orphan → observable)" \
  || bad "(STATE) existing-PR lookup must use --state all so a merged sibling PR flips the orphan (observer-blindness fix)"

# (INV) exactly one `gh pr create` this pass — only the green no-PR anchor.
eq "$(wc -l < "$TMP/created" | tr -d ' ')" "1" "(INV) exactly one PR created (the green no-PR anchor)"

# Summary counters: 1 opened, 1 flipped, 2 held.
printf '%s\n' "$OUT1" | grep -q "1 opened, 1 flipped, 2 held" \
  && ok "run 1 summary reports 1 opened, 1 flipped, 2 held" || bad "run 1 summary (got: $OUT1)"

# --- Run 2: convergence. Flipped anchors left the pre_open_gate set. -----------
OUT2="$(bash "$SCRIPT")"
eq "$(wc -l < "$TMP/created" | tr -d ' ')" "1" "(CONV) green anchor not re-created on second pass"
eq "$(grep -c '^bead-GREEN	' "$TMP/fliplog")" "1" "(CONV) green anchor not re-flipped on second pass"
eq "$(grep -c '^bead-HASPR	' "$TMP/fliplog")" "1" "(CONV) has-PR anchor not re-flipped on second pass"

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
