#!/usr/bin/env bash
# Hermetic test for the two mol-polecat-work `submit-and-exit` mirror deltas.
#
# THE GUARDRAIL: `{{base_branch}}` answers "what did I branch FROM", never
# "where does this land". Base's submit-and-exit spends it on the second
# question and separately rebuilds the branch name from a template, and on a
# rework child both misread the same way:
#
#   1. BRANCH GATE — a rework child filed by a REQUEST_CHANGES signoff carries
#      metadata.branch = the reviewed branch, which workspace-setup step 3
#      calls AUTHORITATIVE and checks out. Base's gate then demands
#      `polecat/<bead-id>` and refuses to hand off the branch it just told the
#      polecat to use. Obeying it forks the reviewed branch, orphans the
#      pre-open review bead's review_branch pin, and offers the refinery a
#      second branch to land independently of the first. The invariant that
#      actually protects the handoff is CURRENT_BRANCH == metadata.branch;
#      `polecat/<bead-id>` is only how FRESH work satisfies it.
#
#   2. TARGET RESOLVE — the signoff dispatch slings the rework child with
#      `--var base_branch=<reviewed branch>` on purpose, so the worktree has
#      the PR-only files (tk-qqgeo), while the child's metadata.target already
#      names the real landing branch (REVIEW_BASE, normally main). Base writes
#      base_branch over it, rendering target=<the branch being pushed> — a
#      self-merge, and a strand indistinguishable from a missing merge target.
#
# Both defects shipped live: su-l74p, su-g805 and su-5l0q all stepped over the
# gate and all kept target=main by hand, three rounds running (tk-3yj8g).
#
# This EXECUTES the real snippets extracted verbatim from the formula (between
# the markers) against a fake `git`/`gc`, so the test cannot drift from the
# shipped instruction. No live city, Dolt, network, or worktrees.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TOML="$ROOT/formulas/mol-polecat-work.toml"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }

command -v jq >/dev/null 2>&1 || { echo "jq is required for this test" >&2; exit 1; }
[ -f "$TOML" ] || { echo "formula not found: $TOML" >&2; exit 1; }

# --- Extract the REAL snippets from the formula. ------------------------------
# Pulls the lines between the markers (exclusive). If the markers or the
# snippets are removed/renamed — the exact thing a wholesale reconciliation
# against base does — extraction yields nothing and the checks below fail
# loudly. The guardrails cannot silently disappear.
extract() {
  awk -v m="$1" '
    $0 ~ ("# >>> " m "$") {f=1; next}
    $0 ~ ("# <<< " m "$") {f=0}
    f' "$TOML"
}

GATE="$(extract submit-branch-gate)"
RESOLVE="$(extract submit-target-resolve)"
CONSUME="$(extract submit-target-consume)"

[ -n "$CONSUME" ] \
  && ok "consumer extracted between submit-target-consume markers" \
  || bad "consumer extraction EMPTY — markers missing from $TOML"

[ -n "$GATE" ] \
  && ok "gate extracted between submit-branch-gate markers" \
  || bad "gate extraction EMPTY — markers missing from $TOML"
[ -n "$RESOLVE" ] \
  && ok "resolver extracted between submit-target-resolve markers" \
  || bad "resolver extraction EMPTY — markers missing from $TOML"

# TOML `"""` strings treat a trailing backslash as a line-ending escape and eat
# the newline plus the following indentation. A shell line-continuation written
# inside one therefore silently joins lines. Both snippets are written
# backslash-free so what the polecat reads is what this test runs; assert it,
# because reintroducing a continuation is an easy and invisible edit.
case "$GATE$RESOLVE$CONSUME" in
  *\\*) bad "snippets contain a backslash — TOML line-ending escapes will mangle them" ;;
  *)    ok  "snippets are backslash-free (safe inside a TOML triple-quoted string)" ;;
esac

# --- Fakes. -------------------------------------------------------------------
# git   : only `git branch --show-current` is used; it answers $FAKE_BRANCH.
# gc    : `gc bd show <id> --json` returns $FAKE_META as the metadata object,
#         `gc bd update ...` and `gc runtime drain-ack` are recorded so the
#         assertions can prove WHAT was written and WHETHER the arm halted.
mkdir -p "$TMP/bin"

cat > "$TMP/bin/git" <<'GIT'
#!/usr/bin/env bash
if [ "$1" = "branch" ] && [ "$2" = "--show-current" ]; then
  printf '%s\n' "${FAKE_BRANCH:-}"
  exit 0
fi
exit 0
GIT

cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
case "$1 $2" in
  "runtime drain-ack") printf 'DRAIN\n' >> "$FAKE_LOG"; exit 0 ;;
  "bd show")           printf '[{"metadata":%s}]\n' "${FAKE_META:-{\}}"; exit 0 ;;
  "bd update")         shift 2; printf 'UPDATE|%s\n' "$*" >> "$FAKE_LOG"; exit 0 ;;
esac
exit 0
GC

chmod +x "$TMP/bin/git" "$TMP/bin/gc"
export PATH="$TMP/bin:$PATH"
export WORK_BEAD_ID=tk-work

# run_gate <current-branch> <metadata-json>
#   -> prints "<rc>|<log>"; the log is the recorded gc writes, newline-joined
#      into one field so a single `eq` can assert both the outcome and the
#      side effects.
run_gate() {
  : > "$TMP/log"
  printf '%s\n' "$GATE" > "$TMP/gate.sh"
  local rc=0
  FAKE_BRANCH="$1" FAKE_META="$2" FAKE_LOG="$TMP/log" \
    bash "$TMP/gate.sh" > "$TMP/out" 2>&1 || rc=$?
  printf '%s|%s' "$rc" "$(tr '\n' ';' < "$TMP/log")"
}

# run_resolve <current-branch> <base_branch> <metadata-json>
#   -> prints "<rc>|<LANDING_TARGET or empty>"
# `{{base_branch}}` is a formula placeholder, substituted here exactly as the
# molecule materializer substitutes it before the polecat reads the step.
run_resolve() {
  : > "$TMP/log"
  printf '%s\n' "$RESOLVE" | sed "s|{{base_branch}}|$2|g" > "$TMP/resolve.sh"
  local rc=0
  CURRENT_BRANCH="$1" FAKE_META="$3" FAKE_LOG="$TMP/log" \
    bash "$TMP/resolve.sh" > "$TMP/out" 2>&1 || rc=$?
  printf '%s|%s' "$rc" "$(sed -n 's/^landing target: //p' "$TMP/out")"
}

printf '%s\n' "$GATE" > "$TMP/gate.sh"
bash -n "$TMP/gate.sh" \
  && ok "extracted gate is syntactically valid bash" \
  || bad "extracted gate failed bash -n"
printf '%s\n' "$RESOLVE" | sed "s|{{base_branch}}|main|g" > "$TMP/resolve.sh"
bash -n "$TMP/resolve.sh" \
  && ok "extracted resolver is syntactically valid bash" \
  || bad "extracted resolver failed bash -n"

# --- 1. Branch gate. ----------------------------------------------------------

# FRESH work, nothing recorded: the per-bead convention is the only check
# available, and passing it must record the branch the refinery will merge.
eq "$(run_gate polecat/tk-work '{}')" \
   "0|UPDATE|tk-work --set-metadata branch=polecat/tk-work;" \
   "fresh + no metadata.branch: accepts polecat/<bead-id> and records it"

# The case the gate exists for: workspace-setup was skipped and the polecat is
# still on its agent home branch. Nothing recorded a branch, so the convention
# catches it. Must halt, and must not record the wrong branch.
eq "$(run_gate polecat/tk-agent-home '{}')" \
   "1|DRAIN;" \
   "fresh + wrong branch: halts, drain-acks, records no branch"

# THE REGRESSION (tk-3yj8g). Rework child: metadata.branch names the reviewed
# branch and the polecat is standing on it. Base rejected this; the invariant
# is satisfied, so it must pass — and metadata.branch already agrees, so
# nothing is rewritten.
eq "$(run_gate polecat/su-uzy9.5 '{"branch":"polecat/su-uzy9.5"}')" \
   "0|" \
   "rework: accepts CURRENT_BRANCH == metadata.branch and rewrites nothing"

# The rework harm the gate still has to catch: a polecat that cut
# polecat/<bead-id> from the reviewed branch instead of resuming it. That forks
# the branch under review, so it must halt even though the name looks correct.
eq "$(run_gate polecat/tk-work '{"branch":"polecat/su-uzy9.5"}')" \
   "1|DRAIN;" \
   "rework: halts on a forked polecat/<bead-id> branch, not just any mismatch"

# submit step 4 detaches HEAD before deleting the branch, so a re-run of this
# step lands here. An empty branch name must never be treated as a match.
eq "$(run_gate '' '{"branch":"polecat/su-uzy9.5"}')" \
   "1|DRAIN;" \
   "detached HEAD with metadata.branch set: halts"
eq "$(run_gate '' '{}')" \
   "1|DRAIN;" \
   "detached HEAD with no metadata.branch: halts"

# An empty-STRING metadata.branch is the absent case, not a branch named "".
# `// empty` collapses both, and the fallback must engage rather than compare
# against "".
eq "$(run_gate polecat/tk-work '{"branch":""}')" \
   "0|UPDATE|tk-work --set-metadata branch=polecat/tk-work;" \
   "empty-string metadata.branch falls back to the convention"

# --- 2. Target resolution. ----------------------------------------------------

# THE REGRESSION (tk-3yj8g). Rework child: base_branch is the reviewed branch
# by design, metadata.target is the real landing branch. Base wrote
# target=polecat/su-uzy9.5 onto a bead whose branch IS polecat/su-uzy9.5.
eq "$(run_resolve polecat/su-uzy9.5 polecat/su-uzy9.5 '{"target":"main"}')" \
   "0|main" \
   "rework: preserves metadata.target=main, never writes the self-merge"

# Fresh work: nothing recorded a target and base_branch is a real other
# branch, so branch-from and merge-into coincide.
eq "$(run_resolve polecat/tk-work main '{}')" \
   "0|main" \
   "fresh: falls back to base_branch when no target was set"

# Owned convoy: the caller's integration branch survives, even though
# base_branch happens to equal it.
eq "$(run_resolve polecat/tk-work integration/tk-c1 '{"target":"integration/tk-c1"}')" \
   "0|integration/tk-c1" \
   "owned convoy: preserves an integration-branch target"

# A caller-set target always wins, including when it disagrees with
# base_branch — the caller knew where this lands and this step does not.
eq "$(run_resolve polecat/tk-work polecat/su-uzy9.5 '{"target":"integration/tk-c1"}')" \
   "0|integration/tk-c1" \
   "caller-set target wins over base_branch"

# Malformed work order: nothing named a target and the only candidate is the
# branch being pushed. Guessing writes a merge that cannot succeed, so halt —
# before the push, with nothing to clean up.
eq "$(run_resolve polecat/su-uzy9.5 polecat/su-uzy9.5 '{}')" \
   "1|" \
   "no target + base_branch == current branch: fails closed instead of self-merging"

# Same fail-closed rule when the var never rendered: an empty target strands
# the bead just as thoroughly as a self-merge.
eq "$(run_resolve polecat/tk-work '' '{}')" \
   "1|" \
   "no target + empty base_branch: fails closed"

# Empty-STRING target is the absent case (see the branch twin above), so the
# fallback must engage rather than write "".
eq "$(run_resolve polecat/tk-work main '{"target":""}')" \
   "0|main" \
   "empty-string metadata.target falls back to base_branch"

# --- 3. Target consumption. ---------------------------------------------------
# The write itself is the site that shipped the defect, so assert on what
# reaches the bead: the resolved target, and --append-notes rather than the
# --notes that silently erases the mayor's dispatch note (tk-6kf6r).
run_consume() {
  : > "$TMP/log"
  printf '%s\n' "$CONSUME" > "$TMP/consume.sh"
  local rc=0
  LANDING_TARGET="$1" FAKE_LOG="$TMP/log" bash "$TMP/consume.sh" > "$TMP/out" 2>&1 || rc=$?
  printf '%s|%s' "$rc" "$(tr '\n' ';' < "$TMP/log")"
}

printf '%s\n' "$CONSUME" > "$TMP/consume.sh"
bash -n "$TMP/consume.sh" \
  && ok "extracted consumer is syntactically valid bash" \
  || bad "extracted consumer failed bash -n"

eq "$(run_consume main)" \
   "0|UPDATE|tk-work --set-metadata target=main --append-notes Implemented: <brief summary>;" \
   "writes the resolved target and APPENDS notes (never --notes)"

eq "$(run_consume integration/tk-c1)" \
   "0|UPDATE|tk-work --set-metadata target=integration/tk-c1 --append-notes Implemented: <brief summary>;" \
   "carries an integration-branch target through to the bead"

# A partial re-run that skips step 1b must not write target="". An empty
# metadata value round-trips as set-but-empty and is not the same as absent,
# so a silent empty write is its own strand.
eq "$(run_consume '')" \
   "1|DRAIN;" \
   "unset LANDING_TARGET: halts instead of writing an empty target"

# --- 4. The snippets compose. -------------------------------------------------
# The resolver consumes $CURRENT_BRANCH, which the gate sets. Run them in
# sequence exactly as the step does, on the rework shape that broke both.
: > "$TMP/log"
printf '%s\n' "$GATE" > "$TMP/both.sh"
printf '%s\n' "$RESOLVE" | sed "s|{{base_branch}}|polecat/su-uzy9.5|g" >> "$TMP/both.sh"
BOTH_RC=0
FAKE_BRANCH=polecat/su-uzy9.5 FAKE_META='{"branch":"polecat/su-uzy9.5","target":"main"}' \
  FAKE_LOG="$TMP/log" bash "$TMP/both.sh" > "$TMP/out" 2>&1 || BOTH_RC=$?
eq "$BOTH_RC" "0" "composed run exits 0 on the rework shape"
eq "$(sed -n 's/^landing target: //p' "$TMP/out")" "main" \
   "composed run resolves the landing target to main"
eq "$(tr '\n' ';' < "$TMP/log")" "" \
   "composed run performs no bead writes (branch and target both already correct)"

echo
echo "submit-branch-gate: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
