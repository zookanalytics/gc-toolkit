#!/usr/bin/env bash
# measure.sh — derives the line counts docs/built-once-target.md states.
#
#   measure.sh [REF]        the lines of the tree at REF (default HEAD)
#   measure.sh BASE HEAD    the lines HEAD adds over BASE, less the lines it removes
#
# Run it from inside a gc-toolkit checkout. A line is a physical line of a
# tracked text file, as `git diff --numstat` counts it, so it reads only git
# objects and never the working tree. A symlink or a binary file counts nothing.
#
# Each path gets the first kind in RULES whose pattern it matches. The pack
# kinds are code, flow (formulas, orders and other config), text (agent
# prompts, fragments and skills) and test, and a path of a pack kind also gets a
# subsystem: the first `pre` rule it matches, else its own row in section 4 of
# docs/component-model.md at the measured commit, which a test takes from the
# script it is named for, else the first `post` rule. A path none of them
# places is counted as unplaced.
set -euo pipefail

[ $# -le 2 ] || { echo "usage: measure.sh [REF] | measure.sh BASE HEAD" >&2; exit 2; }
if [ $# -eq 2 ]; then
  BASE=$1 HEAD_REF=$2
else
  BASE=$(git hash-object -t tree /dev/null) HEAD_REF=${1:-HEAD}
fi
git rev-parse --verify --quiet "$HEAD_REF^{commit}" >/dev/null || { echo "measure.sh: $HEAD_REF is not a commit" >&2; exit 2; }
git rev-parse --verify --quiet "$BASE^{tree}" >/dev/null || { echo "measure.sh: $BASE is not a commit" >&2; exit 2; }

RULES=$(cat <<'RULES'
kind	generated	^generated/|/dist/|/gen/|(^|/)package-lock\.json$|(^|/)go\.sum$
kind	record	^specs/
kind	tooling	^tools/|^\.github/|^\.[^/]*$|(^|/)\.gitkeep$
kind	test	\.test\.(sh|ts|tsx)$|_test\.go$|/testdata/|/fixture/|\.fixture\.json$|\.stub\.sh$|^assets/scripts/test-harness\.sh$|(^|/)vitest\.config\.ts$
kind	docs	^docs/|(^|/)README\.md$|(^|/)PROVENANCE\.md$|^LICENSE$
kind	text	prompt\.template\.md$|(^|/)template-fragments/|^skills/
kind	flow	\.toml$|\.json$|^overlays/|namepool\.txt$
kind	code	.
pre	keeper	^packs/
pre	board	^services/helm/
pre	gctk	^services/gctk/
pre	doctor	^doctor/
pre	doctrine	^template-fragments/
pre	config	^(pack\.toml|review-checks\.toml|lifecycle/|commands/|overlays/|assets/hooks/|\.beads/)
pre	work	^agents/polecat/
pre	review	^agents/(polecat-codex|demo)/
pre	merge	^agents/refinery/
pre	patrol	^agents/(witness|deacon|dog)/
pre	visit	^agents/
pre	visit	^skills/(converse-|session-title/)
pre	review	^skills/(review-|specialist-stance/|demo-capture/|gc-demo-script/)
pre	feedback	^skills/learning-distill/
pre	doctrine	^skills/
post	review	^formulas/(mol-review-quorum-signoff|mol-rig-demo)\.toml$
post	work	^formulas/mol-design-convoy\.toml$
post	visit	^orders/(gate-visit-sweep|proactive-scan-sling)\.toml$
post	shared	^orders/gctk-build\.toml$
post	visit	^assets/scripts/(converse-|gc-helm|gate-visit|visit-|pr-visit-|tmux-|bead-context|proactive-scan|human-route|takeaway-)
post	work	^assets/scripts/(self-review-check|convoy-seed|submit-branch-gate|load-context-|workspace-setup-|rejected-branch-|salvage-scope|husk-guard|recovery-stamp|work-context|decline-wiring|polecat-escalation|agent-worktree|mol-design-convoy|pool-(nudge|cap|demand)-wiring)
post	merge	^assets/scripts/(merge-tail|pr-status-label|pr-summary-region|one-anchor-per-pr|refinery-|mr-aware|find-work|unrecorded-direct|downstream-court)
post	review	^assets/scripts/(review-|demo-deliver|rig-demo-capture|migrate-approval|signoff-gate|check-set-normalize|mol-validate-refuse|mol-rig-demo)
post	feedback	^assets/scripts/(learning-recurrence|distiller-)
post	patrol	^assets/scripts/(branch-context|file-warrant|orphan-dispose|dolt-backup|deacon-|witness-|patrol-|crash-loop|doctor-|notice-finding|host-bead|topology-root|liveness-lookup|candidate-pipeline|owning-store|dog-escalation|cycle-recycle|worktree-cleanup)
post	shared	^assets/scripts/
RULES
)

# Section 4's rows, as `<path> <workflow>`, at the measured commit. A commit
# from before the index existed places nothing, and the rules place its paths.
placements() {
  git show "$1:docs/component-model.md" 2>/dev/null | awk -F'|' '
    /^## 4\./ { on = 1; next }
    /^### / { on = 0 }
    on && $2 ~ /^ `[^`]+`/ {
      p = $2; sub(/^ `/, "", p); sub(/`.*/, "", p)
      w = $3; gsub(/^ +| +$/, "", w); sub(/ primitive$/, "", w)
      print p "\t" w
    }' || true
}

{
  echo "@rule"; printf '%s\n' "$RULES"
  echo "@place"; placements "$HEAD_REF"
  git rev-parse --verify --quiet "$BASE^{commit}" >/dev/null 2>&1 && placements "$BASE"
  echo "@link"
  for r in "$BASE" "$HEAD_REF"; do git ls-tree -r "$r" | awk '$1 == "120000" { print $4 }'; done
  echo "@stat"; git diff --numstat --no-renames "$BASE" "$HEAD_REF"
} | awk -F'\t' -v head="$(git rev-parse --short "$HEAD_REF")" -v base="$(git rev-parse --short "$BASE")" -v two=$# '
  /^@/ { sec = $0; next }
  sec == "@rule" && $1 == "kind" { nk++; KN[nk] = $2; KR[nk] = $3; next }
  sec == "@rule" { nr++; RPHASE[nr] = $1; RSUB[nr] = $2; RRE[nr] = $3; next }
  sec == "@place" { if (!($1 in PLACE)) PLACE[$1] = $2; next }
  sec == "@link" { LINK[$1] = 1; next }
  sec == "@stat" && !($3 in LINK) && $1 != "-" {
    p = $3; net = $1 - $2
    for (i = 1; i <= nk; i++) if (p ~ KR[i]) { k = KN[i]; break }
    KIND[k] += net
    if (k !~ /^(code|flow|text|test)$/) next
    s = place(p); SUB[s] += net; CELL[s, k] += net; SEEN[s] = 1
  }
  function place(p,    i, subj) {
    for (i = 1; i <= nr; i++) if (RPHASE[i] == "pre" && p ~ RRE[i]) return RSUB[i]
    subj = p; sub(/\.test\.sh$/, ".sh", subj)
    if (subj in PLACE) return PLACE[subj]
    for (i = 1; i <= nr; i++) if (RPHASE[i] == "post" && p ~ RRE[i]) return RSUB[i]
    return "unplaced"
  }
  END {
    if (two == 2) printf "net lines from %s to %s\n\n", base, head
    else printf "lines at %s\n\n", head
    printf "%-10s %8s\n", "kind", "lines"
    n = split("code flow text test docs tooling record generated", order, " ")
    for (i = 1; i <= n; i++) printf "%-10s %8d\n", order[i], KIND[order[i]]
    printf "\n%-10s %8s %8s %8s %8s %8s\n", "subsystem", "code", "flow", "text", "test", "total"
    fflush()
    for (s in SEEN) printf "%-10s %8d %8d %8d %8d %8d\n", s, CELL[s, "code"], CELL[s, "flow"], CELL[s, "text"], CELL[s, "test"], SUB[s] | "sort -k6,6nr"
  }'
