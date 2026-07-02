#!/usr/bin/env bash
# Hermetic test for the signoff-anchor resolution contract (close-on-land).
#
# The codex signoff gate has two halves that must agree on how to find the
# gating anchor from a review bead:
#   - DISPATCH (formulas/mol-refinery-patrol.toml) creates the review bead,
#     stamps metadata.anchor_bead = the anchor, and attaches a BLOCKS edge
#     review->anchor *best-effort* (a failed edge only warns; it must not
#     strand the PR).
#   - COMPLETION (template-fragments/polecat-non-impl-done.template.md) resolves
#     the anchor to stamp check.<gate>=green@<head> (COMMENT signoff pass) or
#     clear it + file a rework child (REQUEST_CHANGES).
#
# The bug this guards (PR#163 signoff finding): if completion resolves the
# anchor ONLY by the best-effort BLOCKS edge and that edge was dropped, ANCHOR
# is empty, the check.<gate> marker is never stamped, and the merge skill holds
# the merge forever ("no signoff yet") with nothing to re-dispatch the review.
# The fix is a durable metadata.anchor_bead fallback, resolved when the edge is
# missing.
#
# This test EXECUTES the real resolution snippet extracted verbatim from the
# template (between the `signoff-anchor-resolve` markers) against a fake `gc`,
# so it cannot drift from the shipped instruction. It also asserts the dispatch
# stamps anchor_bead atomically with the review's routing fields. No live city,
# Dolt, network, or PRs.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TEMPLATE="$ROOT/template-fragments/polecat-non-impl-done.template.md"
TOML="$ROOT/formulas/mol-refinery-patrol.toml"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }

mkdir -p "$TMP/bin"

# --- gc stub: only the two reads the resolution snippet performs. ------------
#   gc bd dep list <id> --direction=up -t blocks --json  -> the BLOCKS edge;
#       FAKE_EDGE set      => one upward blocks neighbor (the anchor)
#       FAKE_EDGE empty    => [] (edge dropped / never attached)
#   gc bd show <id> --json -> the review bead's metadata;
#       FAKE_ANCHORBEAD set => metadata.anchor_bead present (durable fallback)
#       FAKE_ANCHORBEAD empty => metadata without anchor_bead
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
[ "$1" = "bd" ] || exit 0
case "$2" in
  dep)   # bd dep list <id> --direction=up -t blocks --json
    if [ -n "${FAKE_EDGE:-}" ]; then printf '[{"id":"%s"}]\n' "$FAKE_EDGE"; else printf '[]\n'; fi ;;
  show)  # bd show <id> --json
    if [ -n "${FAKE_ANCHORBEAD:-}" ]; then
      printf '[{"metadata":{"anchor_bead":"%s"}}]\n' "$FAKE_ANCHORBEAD"
    else
      printf '[{"metadata":{}}]\n'
    fi ;;
  *) printf '[]\n' ;;
esac
exit 0
GC
chmod +x "$TMP/bin/gc"

# --- Extract the REAL resolution snippet from the template. -------------------
# Pulls the lines between the markers (exclusive). If the markers or the snippet
# are removed/renamed, extraction yields nothing and the guard below fails
# loudly — the contract cannot silently disappear.
SNIPPET="$(awk '
  /# >>> signoff-anchor-resolve/ {f=1; next}
  /# <<< signoff-anchor-resolve/ {f=0}
  f' "$TEMPLATE")"

[ -n "$SNIPPET" ] \
  && ok "snippet extracted between signoff-anchor-resolve markers" \
  || bad "snippet extraction EMPTY — markers missing from $TEMPLATE"

# The template uses the <work-bead> placeholder (the polecat substitutes its own
# review-bead id at runtime). The fake gc keys off env, not the id, so any
# concrete value works.
SNIPPET="${SNIPPET//<work-bead>/rb-1}"

# Wrap WITHOUT set -e: the snippet's `[ -z "$ANCHOR" ] && ANCHOR=...` short-
# circuits to a non-zero compound when ANCHOR is already set, which is correct
# (and exactly how the polecat done-sequence runs it — not under set -e).
{ printf '%s\n' "$SNIPPET"; printf 'printf "%%s" "${ANCHOR:-}"\n'; } > "$TMP/run.sh"

resolve() { PATH="$TMP/bin:$PATH" FAKE_EDGE="$1" FAKE_ANCHORBEAD="$2" bash "$TMP/run.sh"; }

# --- Behavioral matrix. ------------------------------------------------------
# (A) edge present, no anchor_bead -> edge wins (primary, dep-graph path).
eq "$(resolve 'anchor-edge' '')"           'anchor-edge' \
   "(A) blocks edge present -> anchor resolved from edge"
# (B) edge DROPPED but anchor_bead present -> fallback resolves it. THE FIX:
#     without the fallback this returns '' and strands the PR forever.
eq "$(resolve '' 'anchor-meta')"           'anchor-meta' \
   "(B) blocks edge dropped -> anchor resolved from durable metadata.anchor_bead"
# (C) both present -> edge takes precedence; fallback only fires when empty.
eq "$(resolve 'anchor-edge' 'anchor-meta')" 'anchor-edge' \
   "(C) edge present takes precedence over anchor_bead fallback"
# (D) both missing -> empty (degrades to the documented warn path, no crash).
eq "$(resolve '' '')"                       '' \
   "(D) edge and anchor_bead both missing -> ANCHOR empty (warn path)"

# --- Dispatch wiring: anchor_bead must be stamped on the review bead, in the
#     SAME `gc bd update "$REVIEW_BEAD"` batch as its routing fields (so it is
#     as durable as the review's own dispatch — not a separable best-effort
#     write like the edge). -----------------------------------------------------
REVIEW_UPDATE="$(awk '
  /gc bd update "\$REVIEW_BEAD"/ {f=1}
  f {print}
  f && !/\\[[:space:]]*$/ {exit}' "$TOML")"
printf '%s' "$REVIEW_UPDATE" | grep -q -- '--set-metadata anchor_bead="\$WORK"' \
  && ok "(E) dispatch stamps anchor_bead=\$WORK atomically in the review-bead update batch" \
  || bad "(E) dispatch must stamp --set-metadata anchor_bead=\"\$WORK\" in the review-bead update batch"

# --- Pre-open dispatch wiring (tk-6d0vb.1.8): the PRE-OPEN review bead carries
#     review_branch/review_base (the compare-range the reviewer diffs, and the
#     template's pre-open discriminator) AND anchor_bead, in one update batch —
#     since the awk above grabs the FIRST review-bead update (the pre-open one),
#     REVIEW_UPDATE is that batch. The completion path (resolution snippet tested
#     above) and the fail-closed gate both depend on anchor_bead being here too. -
printf '%s' "$REVIEW_UPDATE" | grep -qF -- '--set-metadata review_branch="$BRANCH"' \
  && ok "(E2) pre-open dispatch stamps review_branch=\$BRANCH (reviewer compare-range + template discriminator)" \
  || bad "(E2) pre-open dispatch must stamp --set-metadata review_branch=\"\$BRANCH\""
printf '%s' "$REVIEW_UPDATE" | grep -qF -- '--set-metadata review_base="$TARGET"' \
  && ok "(E3) pre-open dispatch stamps review_base=\$TARGET" \
  || bad "(E3) pre-open dispatch must stamp --set-metadata review_base=\"\$TARGET\""

# --- Template pre-open arm (tk-6d0vb.1.8): the fix-target dispatch discriminates
#     pre-open by review_branch and reads the reviewed oid from the BRANCH head
#     (git rev-parse origin/<branch>) — NOT the reviews API, since no PR/review
#     exists yet — so the stamped check.<gate> matches the head the resolver opens
#     the PR at. --------------------------------------------------------------
grep -qF 'REVIEW_BRANCH=$(gc bd show <work-bead> --json' "$TEMPLATE" \
  && ok "(H) template reads metadata.review_branch (pre-open discriminator)" \
  || bad "(H) template must read metadata.review_branch to discriminate pre-open"
grep -qF 'git rev-parse "origin/$REVIEW_BRANCH"' "$TEMPLATE" \
  && ok "(I) template pre-open pass stamps the gate from the branch head (git rev-parse origin/<branch>)" \
  || bad "(I) template pre-open pass must read the reviewed oid via git rev-parse origin/<branch>"

# --- check_set membership normalization (tk-aj4ua): BOTH codex-membership sites
#     must normalize check_set — trim a spaced list — the SAME way merge-skill.sh
#     enforces it, so a natural-form "lint, codex" cannot make one path skip codex
#     while the other enforces it (the stranded-PR class). Since tk-6d0vb.1.8 the
#     dispatch keys off a precomputed CODEX_GATE, so the two normalizing sites are
#     the step-2 gate DECISION and the fail-closed site. Static guards on the raw
#     formula so a regression to the brittle literal grep is caught. -------------
grep -qF ',codex,' "$TOML" \
  && bad "(F) brittle literal ',codex,' membership grep still present -> a spaced 'lint, codex' would strand the PR" \
  || ok "(F) no brittle literal ',codex,' membership grep in the formula"
NORM_COUNT=$(grep -cF "grep -qxF codex" "$TOML" || true)
eq "$NORM_COUNT" "2" \
   "(G) both codex-membership sites (step-2 gate decision + fail-closed) use the normalized whole-line match"

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
