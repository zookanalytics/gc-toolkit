#!/usr/bin/env bash
# measure.sh — the line counts of gc-toolkit's tree, by kind and subsystem.
#
#   measure.sh [REF]           the lines of the tree at REF (default HEAD)
#   measure.sh BASE HEAD       the lines HEAD adds over BASE, less the lines it removes
#   measure.sh --pr BASE HEAD  the size section gc-toolkit's CI posts on a PR,
#                              from the merge base of BASE and HEAD to HEAD
#
# Run it from inside a gc-toolkit checkout. A line is a physical line of a
# tracked text file, as `git diff --numstat` counts it, so it reads only git
# objects and never the working tree. A symlink or a binary file counts nothing.
# Each end of a change is counted on its own, so a file that a symlink or a
# binary replaces takes all its lines out, and a file that replaces one brings
# all its lines in.
#
# Each path gets the first kind in RULES whose pattern it matches. The pack
# kinds are code, flow (formulas, orders and other config), text (agent
# prompts, fragments and skills) and test, and a path of a pack kind also gets a
# subsystem: the first `pre` rule it matches, else its own row in section 4 of
# docs/component-model.md at the measured commit, which a test takes from the
# script it is named for, else the first `post` rule. A path none of them
# places is counted as unplaced.
#
# --pr prints markdown: the net runtime and test lines by subsystem, the other
# kinds beside them, and the lines the change adds to each file the deletion
# plan retires, with the bead that retires it. The plan is
# tools/deletion-plan.tsv at the merge base. A merge base that carries no
# tools/measure.sh prints nothing, since these rules describe only gc-toolkit's
# tree.
set -euo pipefail

USAGE="usage: measure.sh [REF] | measure.sh BASE HEAD | measure.sh --pr BASE HEAD"
PR=""
if [ "${1:-}" = --pr ]; then
  PR=1; shift
  [ $# -eq 2 ] || { echo "$USAGE" >&2; exit 2; }
fi
[ $# -le 2 ] || { echo "$USAGE" >&2; exit 2; }
EMPTY=$(git hash-object -t tree /dev/null)
if [ $# -eq 2 ]; then
  BASE=$1 HEAD_REF=$2
else
  BASE=$EMPTY HEAD_REF=${1:-HEAD}
fi
git rev-parse --verify --quiet "$HEAD_REF^{commit}" >/dev/null || { echo "measure.sh: $HEAD_REF is not a commit" >&2; exit 2; }
git rev-parse --verify --quiet "$BASE^{tree}" >/dev/null || { echo "measure.sh: $BASE is not a commit" >&2; exit 2; }
if [ -n "$PR" ]; then
  BASE=$(git merge-base "$BASE" "$HEAD_REF") || { echo "measure.sh: $1 and $2 share no merge base" >&2; exit 2; }
  git cat-file -e "$BASE:tools/measure.sh" 2>/dev/null || exit 0
fi

RULES=$(cat <<'RULES'
kind	generated	^generated/|/dist/|/gen/|(^|/)package-lock\.json$|(^|/)go\.sum$
kind	record	^specs/
kind	tooling	^tools/|^\.github/|^\.[^/]*$|(^|/)\.gitkeep$
kind	test	\.test\.(sh|ts|tsx)$|_test\.go$|/testdata/|/fixture/|\.fixture\.json$|\.stub\.sh$|^assets/scripts/test-harness\.sh$|(^|/)vitest\.config\.ts$
kind	docs	^docs/|(^|/)README\.md$|(^|/)PROVENANCE\.md$|^LICENSE$|^(AGENTS|CLAUDE)\.md$
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

# Each section's lines, then @path last: every path that differs between the
# ends, which is counted from what the sections before it hold. @base and @head
# are each end's own line counts, and git prints "-" for a binary file. @pair is
# the lines git adds between the ends, and @plan the deletion plan's rows; --pr
# reads both.
{
  echo "@rule"; printf '%s\n' "$RULES"
  echo "@place"; placements "$HEAD_REF"
  git rev-parse --verify --quiet "$BASE^{commit}" >/dev/null 2>&1 && placements "$BASE"
  if [ -n "$PR" ]; then
    echo "@plan"; git show "$BASE:tools/deletion-plan.tsv" 2>/dev/null || true
    echo "@pair"; git diff --numstat --no-renames "$BASE" "$HEAD_REF"
  fi
  echo "@base"; git diff --numstat "$EMPTY" "$BASE"
  echo "@head"; git diff --numstat "$EMPTY" "$HEAD_REF"
  echo "@path"; git diff --raw --no-renames "$BASE" "$HEAD_REF"
} | awk -F'\t' -v head="$(git rev-parse --short "$HEAD_REF")" -v base="$(git rev-parse --short "$BASE")" -v two=$# -v pr="$PR" '
  /^@/ { sec = $0; next }
  sec == "@rule" && $1 == "kind" { nk++; KN[nk] = $2; KR[nk] = $3; next }
  sec == "@rule" { nr++; RPHASE[nr] = $1; RSUB[nr] = $2; RRE[nr] = $3; next }
  sec == "@place" { if (!($1 in PLACE)) PLACE[$1] = $2; next }
  sec == "@plan" { if ($1 != "" && $1 !~ /^#/) PLAN[$1] = $2; next }
  sec == "@pair" { ADDED[$3] = $1; next }
  sec == "@base" { LB[$3] = $1; next }
  sec == "@head" { LH[$3] = $1; next }
  # ":<mode> <mode> <blob> <blob> <status>", then the path. An end counts only
  # when it is a regular file that git counts as text, since a symlink or a
  # gitlink has no lines.
  sec == "@path" {
    split($1, m, " "); p = $2
    tb = (substr(m[1], 2) ~ /^100/) && (p in LB) && LB[p] != "-"
    th = (m[2] ~ /^100/) && (p in LH) && LH[p] != "-"
    if (!tb && !th) next
    net = (th ? LH[p] : 0) - (tb ? LB[p] : 0)
    for (i = 1; i <= nk; i++) if (p ~ KR[i]) { k = KN[i]; break }
    KIND[k] += net
    # A file with text at both ends gains what git adds between them, and one
    # with text only at the head gains all of it.
    if (th && (p in PLAN)) { a = (tb ? ADDED[p] : LH[p]) + 0; if (a > 0) GAIN[p] = a }
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
  function signed(n) { n += 0; return n > 0 ? "+" n : n "" }
  function abs(n) { return n < 0 ? -n : n }
  # The size section: a sentence of totals, a row per subsystem the change
  # touches with the most changed first, the kinds beside the pack, and each
  # file the deletion plan retires that the change adds lines to.
  function size_section(    rt, n, s, r, t, cmd, order, k, i, nb, item, list, p) {
    rt = KIND["code"] + KIND["flow"] + KIND["text"]
    n = 0; for (s in SEEN) n++
    if (n) printf "Net lines from the merge base `%s`: runtime %s and tests %s.\n", base, signed(rt), signed(KIND["test"])
    else printf "No runtime or test lines change from the merge base `%s`.\n", base
    if (n) {
      printf "\n| Subsystem | Runtime | Tests |\n|---|---:|---:|\n"
      fflush()
      cmd = "LC_ALL=C sort -t \"\t\" -k1,1nr -k2,2 | cut -f3-"
      for (s in SEEN) {
        r = CELL[s, "code"] + CELL[s, "flow"] + CELL[s, "text"]; t = CELL[s, "test"]
        printf "%d\t%s\t| %s | %s | %s |\n", abs(r) + abs(t), s, s, signed(r), signed(t) | cmd
      }
      close(cmd)
    }
    k = split("docs tooling record generated", order, " ")
    nb = 0
    for (i = 1; i <= k; i++) if (KIND[order[i]]) item[++nb] = order[i] " " signed(KIND[order[i]])
    if (nb) {
      list = item[1]
      for (i = 2; i <= nb; i++) list = list (i == nb ? " and " : ", ") item[i]
      printf "\nBeside the pack: %s.\n", list
    }
    n = 0; for (p in GAIN) n++
    if (n) {
      printf "\nThe change adds lines to files the deletion plan retires:\n\n"
      fflush()
      cmd = "LC_ALL=C sort"
      for (p in GAIN) printf "- `%s` gains %d line%s, and %s retires it.\n", p, GAIN[p], (GAIN[p] == 1 ? "" : "s"), PLAN[p] | cmd
      close(cmd)
    }
  }
  END {
    if (pr) { size_section(); exit }
    if (two == 2) printf "net lines from %s to %s\n\n", base, head
    else printf "lines at %s\n\n", head
    printf "%-10s %8s\n", "kind", "lines"
    n = split("code flow text test docs tooling record generated", order, " ")
    for (i = 1; i <= n; i++) printf "%-10s %8d\n", order[i], KIND[order[i]]
    printf "\n%-10s %8s %8s %8s %8s %8s\n", "subsystem", "code", "flow", "text", "test", "total"
    fflush()
    for (s in SEEN) printf "%-10s %8d %8d %8d %8d %8d\n", s, CELL[s, "code"], CELL[s, "flow"], CELL[s, "text"], CELL[s, "test"], SUB[s] | "sort -k6,6nr"
  }'
