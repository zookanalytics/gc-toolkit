#!/usr/bin/env bash
# Hermetic test for mol-polecat-work's `submit-and-exit` contract.
#
# What it holds:
#   1. BRANCH GATE — the invariant is CURRENT_BRANCH == metadata.branch;
#      `polecat/<bead-id>` is only how FRESH work satisfies it. A rework
#      child legitimately stands on the reviewed branch.
#   2. TARGET RESOLVE — {{base_branch}} is "branch FROM", never "land INTO".
#      A caller-set metadata.target wins; base_branch fills in only for
#      fresh work; nothing resolvable fails closed (never a self-merge).
#   3. ATOMIC HANDOFF — one gc bd update carries target + refinery assignee
#      + cleared route + APPENDED notes; a partial handoff cannot ship.
#   4. CHAIN CLOSE — six session-owned steps close forward via step-close.sh
#      at ALL FOUR terminal exits (handoff, the auto_push=false halt, the
#      store-only exit, and the operator-merge park), and workflow-finalize
#      is never touched.
#   5. STORE-ONLY EXIT — a run that produced no commit releases the bead the
#      way the halt arm does, in three writes the claim guard accepts, and
#      refuses the arm outright when the run has a diff to land.
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
ANCHOR="$(extract submit-anchor-resolve)"
CONSUME="$(extract submit-target-consume)"
CLOSE="$(extract submit-chain-close)"
HALT="$(extract submit-auto-push-halt)"
HALT_CLOSE="$(extract submit-halt-chain-close)"
STORE="$(extract submit-store-only-exit)"
STORE_CLOSE="$(extract submit-store-only-chain-close)"
OPMERGE="$(extract submit-operator-merge-park)"
OPMERGE_CLOSE="$(extract submit-operator-merge-chain-close)"

[ -n "$CLOSE" ] \
  && ok "chain close extracted between submit-chain-close markers" \
  || bad "chain-close extraction EMPTY — markers missing from $TOML"

[ -n "$HALT" ] \
  && ok "auto_push=false arm extracted between submit-auto-push-halt markers" \
  || bad "halt-arm extraction EMPTY — markers missing from $TOML"

[ -n "$STORE" ] \
  && ok "store-only arm extracted between submit-store-only-exit markers" \
  || bad "store-only-arm extraction EMPTY — markers missing from $TOML"

[ -n "$OPMERGE" ] \
  && ok "operator-merge arm extracted between submit-operator-merge-park markers" \
  || bad "operator-merge-arm extraction EMPTY — markers missing from $TOML"

# The halt arm nests its chain-close copy under a DIFFERENT marker name on
# purpose. `extract` is a flag-flip over the whole file, so two regions sharing
# one name concatenate into a single extraction and every assertion below
# silently doubles. Pin the outer name to one occurrence so a rename that
# collides is caught here rather than as a confusing diff.
eq "$(sed -n '/^# >>> submit-chain-close$/p' "$TOML" | wc -l | tr -d ' ')" "1" \
   "exactly one submit-chain-close region (the halt copy has its own name)"

[ -n "$CONSUME" ] \
  && ok "consumer extracted between submit-target-consume markers" \
  || bad "consumer extraction EMPTY — markers missing from $TOML"

[ -n "$GATE" ] \
  && ok "gate extracted between submit-branch-gate markers" \
  || bad "gate extraction EMPTY — markers missing from $TOML"
[ -n "$RESOLVE" ] \
  && ok "resolver extracted between submit-target-resolve markers" \
  || bad "resolver extraction EMPTY — markers missing from $TOML"
[ -n "$ANCHOR" ] \
  && ok "anchor resolver extracted between submit-anchor-resolve markers" \
  || bad "anchor-resolver extraction EMPTY — markers missing from $TOML"

# TOML `"""` strings treat a trailing backslash as a line-ending escape and eat
# the newline plus the following indentation. A shell line-continuation written
# inside one therefore silently joins lines. Both snippets are written
# backslash-free so what the polecat reads is what this test runs; assert it,
# because reintroducing a continuation is an easy and invisible edit.
case "$GATE$RESOLVE$ANCHOR$CONSUME$CLOSE$HALT$HALT_CLOSE$STORE$STORE_CLOSE$OPMERGE$OPMERGE_CLOSE" in
  *\\*) bad "snippets contain a backslash — TOML line-ending escapes will mangle them" ;;
  *)    ok  "snippets are backslash-free (safe inside a TOML triple-quoted string)" ;;
esac

# The declared default is what a source-read reconstruction renders, and it is
# reached only when the poured step was bypassed. Empty renders `<rig>/refinery`,
# an address no agent holds, and the refinery's exact-match find-work then never
# reads the bead. Every substitution below pins `gc-toolkit.` explicitly, so none
# of them can see the default.
BP_DEFAULT="$(awk '
  /^\[vars\.binding_prefix\]$/ {f=1; next}
  f && /^\[/                    {exit}
  f && /^default[ \t]*=/         {sub(/^default[ \t]*=[ \t]*"/, ""); sub(/"$/, ""); print; exit}
' "$TOML")"
[ -n "$BP_DEFAULT" ] \
  && ok "binding_prefix declares a non-empty default ($BP_DEFAULT)" \
  || bad "binding_prefix default is EMPTY — a source-read renders <rig>/refinery, which names no agent"

# --- Fakes. -------------------------------------------------------------------
# git   : `branch --show-current` answers $FAKE_BRANCH; the three probes the
#         store-only arm makes answer $FAKE_AHEAD / $FAKE_DIRTY / $FAKE_PUSHED,
#         each empty by default so the arm sees a run with nothing to land.
# gc    : `gc bd show <id> --json` returns $FAKE_META as the metadata object,
#         `gc bd update ...` and `gc runtime drain-ack` are recorded so the
#         assertions can prove WHAT was written and WHETHER the arm halted.
#         `gc agent list --json` answers $FAKE_AGENTS; the value UNREADABLE
#         makes the call fail, which reaches the guard as a different cause
#         than an empty roster but must take the same arm.
mkdir -p "$TMP/bin"

cat > "$TMP/bin/git" <<'GIT'
#!/usr/bin/env bash
# `git -C <dir> remote get-url origin` is the operator-merge arm's rig-origin
# probe; it answers $FAKE_RIG_ORIGIN regardless of the dir so a case can set the
# repo the refinery covers without a real checkout.
if [ "$1" = "-C" ]; then
  case "$3 $4" in "remote get-url") printf '%s\n' "${FAKE_RIG_ORIGIN:-}" ;; esac
  exit 0
fi
case "$1 $2" in
  "branch --show-current") printf '%s\n' "${FAKE_BRANCH:-}"; exit 0 ;;
  "rev-list --count")      printf '%s\n' "${FAKE_AHEAD:-0}"; exit 0 ;;
  "status --porcelain")    [ -n "${FAKE_DIRTY:-}" ] && printf '%s\n' "$FAKE_DIRTY"; exit 0 ;;
  "ls-remote origin")      [ -n "${FAKE_PUSHED:-}" ] && printf '%s\n' "$FAKE_PUSHED"; exit 0 ;;
esac
exit 0
GIT

cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
case "$1 $2" in
  "runtime drain-ack") printf 'DRAIN\n' >> "$FAKE_LOG"; exit 0 ;;
  "bd show")           printf '[{"metadata":%s}]\n' "${FAKE_META:-{\}}"; exit 0 ;;
  "bd update")         shift 2; printf 'UPDATE|%s\n' "$*" >> "$FAKE_LOG"; exit 0 ;;
  "bd list")           printf '%s\n' "${FAKE_ANCHOR_ROWS-[]}"; exit 0 ;;
  "agent list")        [ "${FAKE_AGENTS-}" = "UNREADABLE" ] && exit 1
                       printf '{"agents":%s}\n' "${FAKE_AGENTS:-[]}"; exit 0 ;;
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

# --- 3. The atomic handoff. -----------------------------------------------------
# ONE gc bd update carries the whole transition — resolved target, refinery
# assignee, cleared route, APPENDED notes — so a partial handoff cannot strand
# the bead between writes, and --notes can never erase the dispatch note.
# {{binding_prefix}} is substituted the way the materializer does; GC_RIG is
# controlled per case.
# ROSTER_OK is the shape `gc agent list --json` returns: every agent carries a
# rig-qualified name, and the guard also accepts the binding-qualified tail so a
# session outside a rig still resolves. Neither form ever yields bare
# `refinery`, which is what makes the empty-prefix address detectable at all.
ROSTER_OK='[{"qualified_name":"gc-toolkit/gc-toolkit.refinery"},{"qualified_name":"myrig/gc-toolkit.refinery"},{"qualified_name":"gc-toolkit/gc-toolkit.polecat"}]'

# $3 is set-but-empty on purpose in the empty-prefix case, so `${3-...}` and not
# `${3:-...}` is the expansion that renders it.
run_consume() { # <landing-target> [gc-rig] [binding-prefix] [agents-json|UNREADABLE]
  : > "$TMP/log"
  printf '%s\n' "$CONSUME" | sed "s|{{binding_prefix}}|${3-gc-toolkit.}|g" > "$TMP/consume.sh"
  local rc=0
  LANDING_TARGET="$1" GC_RIG="${2-}" FAKE_AGENTS="${4-$ROSTER_OK}" FAKE_LOG="$TMP/log" \
    bash "$TMP/consume.sh" > "$TMP/out" 2>&1 || rc=$?
  printf '%s|%s' "$rc" "$(tr '\n' ';' < "$TMP/log")"
}

printf '%s\n' "$CONSUME" | sed "s|{{binding_prefix}}|gc-toolkit.|g" > "$TMP/consume.sh"
bash -n "$TMP/consume.sh" \
  && ok "extracted handoff is syntactically valid bash" \
  || bad "extracted handoff failed bash -n"

eq "$(run_consume main)" \
   "0|UPDATE|tk-work --status=open --assignee=gc-toolkit.refinery --set-metadata target=main --set-metadata gc.routed_to= --append-notes Implemented: <brief summary>;" \
   "one atomic write: target + refinery assignee + cleared route + APPENDED notes"

eq "$(run_consume integration/tk-c1)" \
   "0|UPDATE|tk-work --status=open --assignee=gc-toolkit.refinery --set-metadata target=integration/tk-c1 --set-metadata gc.routed_to= --append-notes Implemented: <brief summary>;" \
   "carries an integration-branch target through to the bead"

eq "$(run_consume main myrig)" \
   "0|UPDATE|tk-work --status=open --assignee=myrig/gc-toolkit.refinery --set-metadata target=main --set-metadata gc.routed_to= --append-notes Implemented: <brief summary>;" \
   "rig sessions get the rig-qualified refinery address"

# A partial re-run that skips step 1b must not write target="". An empty
# metadata value round-trips as set-but-empty and is not the same as absent,
# so a silent empty write is its own strand.
eq "$(run_consume '')" \
   "1|DRAIN;" \
   "unset LANDING_TARGET: halts instead of writing an empty target"

# An empty {{binding_prefix}} is what the formula's declared default renders
# whenever this command is rebuilt from the .toml instead of read out of the
# poured step. The address becomes `gc-toolkit/refinery`. The refinery's
# find-work is exact-match on assignee, so a bead written there is never read
# and no error is raised anywhere. The halt must come BEFORE the write, so the
# log carries DRAIN and no UPDATE at all.
eq "$(run_consume main gc-toolkit '')" \
   "1|DRAIN;" \
   "empty binding prefix: halts on an address no agent holds, writing nothing"

# The check is roster membership, not merely a non-empty prefix — a wrong prefix
# strands exactly as thoroughly as an absent one.
eq "$(run_consume main gc-toolkit typo.)" \
   "1|DRAIN;" \
   "unbound binding prefix: halts on an address no agent holds, writing nothing"

# The permissive arm. A roster the guard could not read proves nothing about the
# address, and failing closed there would stall handoffs that are almost always
# correct. A call that fails and a roster that is genuinely empty arrive by
# different routes and must both write.
eq "$(run_consume main myrig gc-toolkit. UNREADABLE)" \
   "0|UPDATE|tk-work --status=open --assignee=myrig/gc-toolkit.refinery --set-metadata target=main --set-metadata gc.routed_to= --append-notes Implemented: <brief summary>;" \
   "unreadable roster: hands off rather than stalling on what it cannot check"

eq "$(run_consume main myrig gc-toolkit. '[]')" \
   "0|UPDATE|tk-work --status=open --assignee=myrig/gc-toolkit.refinery --set-metadata target=main --set-metadata gc.routed_to= --append-notes Implemented: <brief summary>;" \
   "empty roster: hands off rather than stalling on what it cannot check"

# --- 3b. The PR summary the handoff carries. ----------------------------------
# pr-open.sh publishes metadata.pr_summary as the PR's ## Summary and falls back
# to the anchor's description, which is dispatch text. Only the polecat has read
# the diff, so the summary rides the SAME atomic write as the rest of the
# transition; a second write is a second thing a crash can lose.
#
# run_consume_file <summary-file-path> [strict]
#   -> prints "<rc>|<log>" with PR_SUMMARY_FILE pointed at the given path. The
#      path is passed unconditionally, so an absent file is tested as the
#      polecat's shell actually presents it: the variable set, the file gone.
run_consume_file() {
  : > "$TMP/log"
  : > "$TMP/summary-consume.sh"
  if [ "${2:-}" = "strict" ]; then printf 'set -euo pipefail\n' > "$TMP/summary-consume.sh"; fi
  printf '%s\n' "$CONSUME" | sed "s|{{binding_prefix}}|gc-toolkit.|g" >> "$TMP/summary-consume.sh"
  local rc=0
  LANDING_TARGET=main GC_RIG="" FAKE_AGENTS="$ROSTER_OK" FAKE_LOG="$TMP/log" \
    PR_SUMMARY_FILE="$1" bash "$TMP/summary-consume.sh" > "$TMP/out" 2>&1 || rc=$?
  printf '%s|%s' "$rc" "$(tr '\n' ';' < "$TMP/log")"
}

printf 'Compares heads instead of names.' > "$TMP/summary.txt"
eq "$(run_consume_file "$TMP/summary.txt")" \
   "0|UPDATE|tk-work --status=open --assignee=gc-toolkit.refinery --set-metadata target=main --set-metadata gc.routed_to= --set-metadata pr_summary=Compares heads instead of names. --append-notes Implemented: <brief summary>;" \
   "a carried summary rides the one atomic write as pr_summary"

# A real summary is prose, not a line. The fake logs argv verbatim, so an
# embedded newline shows up as a second logged line — which is the proof that
# the value reaches gc unmangled rather than truncated at the first line.
printf 'Line one.\nLine two.' > "$TMP/summary-multiline.txt"
eq "$(run_consume_file "$TMP/summary-multiline.txt")" \
   "0|UPDATE|tk-work --status=open --assignee=gc-toolkit.refinery --set-metadata target=main --set-metadata gc.routed_to= --set-metadata pr_summary=Line one.;Line two. --append-notes Implemented: <brief summary>;" \
   "a multi-line summary reaches the write whole"

# Both no-summary shapes fall back to the unsummarized handoff
# BYTE-IDENTICALLY. An empty metadata value round-trips as set-but-empty rather
# than absent, so writing one asserts a summary that was never composed;
# pr-open.sh's whitespace guard is a second line of defence, not a licence to
# write the key.
: > "$TMP/summary-empty.txt"
eq "$(run_consume_file "$TMP/summary-empty.txt")" \
   "0|UPDATE|tk-work --status=open --assignee=gc-toolkit.refinery --set-metadata target=main --set-metadata gc.routed_to= --append-notes Implemented: <brief summary>;" \
   "an empty summary file writes no pr_summary key at all"

eq "$(run_consume_file "$TMP/summary-absent.txt")" \
   "0|UPDATE|tk-work --status=open --assignee=gc-toolkit.refinery --set-metadata target=main --set-metadata gc.routed_to= --append-notes Implemented: <brief summary>;" \
   "a PR_SUMMARY_FILE naming no file hands off unsummarized rather than halting"

# The step's own blocks run before this one under one shell, and a polecat that
# skipped 4b leaves PR_SUMMARY_FILE unset. Under `set -u` an unguarded read
# would kill the handoff after the push — the branch pushed, the bead never
# handed off.
: > "$TMP/log"
printf 'set -euo pipefail\n' > "$TMP/nosummary.sh"
printf '%s\n' "$CONSUME" | sed "s|{{binding_prefix}}|gc-toolkit.|g" >> "$TMP/nosummary.sh"
NOSUM_RC=0
LANDING_TARGET=main GC_RIG="" FAKE_AGENTS="$ROSTER_OK" FAKE_LOG="$TMP/log" \
  bash "$TMP/nosummary.sh" > "$TMP/out" 2>&1 || NOSUM_RC=$?
eq "$NOSUM_RC|$(tr '\n' ';' < "$TMP/log")" \
   "0|UPDATE|tk-work --status=open --assignee=gc-toolkit.refinery --set-metadata target=main --set-metadata gc.routed_to= --append-notes Implemented: <brief summary>;" \
   "strict shell, PR_SUMMARY_FILE never set: hands off unsummarized, no set -u crash"

eq "$(run_consume_file "$TMP/summary.txt" strict)" \
   "0|UPDATE|tk-work --status=open --assignee=gc-toolkit.refinery --set-metadata target=main --set-metadata gc.routed_to= --set-metadata pr_summary=Compares heads instead of names. --append-notes Implemented: <brief summary>;" \
   "strict shell: a carried summary still writes"

# The polecat pastes this block into a live shell, and `bash "$TMP/consume.sh"`
# above does not model one that runs strict. Both of the guard's reads are
# pipefail traps: `... | grep -q` returns 141 when grep matches and exits before
# the writer finishes, and the roster pipeline returns non-zero whenever `gc`
# fails, which is the case the permissive arm exists to serve. Either one turns
# a correct handoff into a halt under `set -euo pipefail`, so run the real
# snippet under it.
run_strict_consume() { # <landing-target> <gc-rig> <agents-json|UNREADABLE>
  : > "$TMP/log"
  printf 'set -euo pipefail\n' > "$TMP/strict.sh"
  printf '%s\n' "$CONSUME" | sed "s|{{binding_prefix}}|gc-toolkit.|g" >> "$TMP/strict.sh"
  local rc=0
  LANDING_TARGET="$1" GC_RIG="$2" FAKE_AGENTS="$3" FAKE_LOG="$TMP/log" \
    bash "$TMP/strict.sh" > "$TMP/out" 2>&1 || rc=$?
  printf '%s|%s' "$rc" "$(tr '\n' ';' < "$TMP/log")"
}

# The SIGPIPE half needs a roster larger than the 64K pipe buffer, with the match
# up front: `grep -q` exits on the first hit while the writer is still blocked,
# the writer takes SIGPIPE, and pipefail reports 141 for a pipeline that found
# what it was looking for. A small roster fits in the buffer and never triggers
# it. The fixture is therefore sized to straddle two limits — the roster it
# renders must clear the 64K pipe buffer, while the JSON carrying it reaches the
# fake through the environment and must stay under MAX_ARG_STRLEN (128K), which
# execve enforces per variable. 1200 entries gives ~97K of roster from ~83K of
# JSON; overshooting the cap surfaces as a bare rc=126, not as a useful failure.
ROSTER_BIG="$(jq -cn '[{qualified_name:"gc-toolkit/gc-toolkit.refinery"}]
  + [range(1200) | {qualified_name:("filler-rig-\(.)/gc-toolkit.polecat-padding-entry")}]')"

eq "$(run_strict_consume main gc-toolkit "$ROSTER_BIG")" \
   "0|UPDATE|tk-work --status=open --assignee=gc-toolkit/gc-toolkit.refinery --set-metadata target=main --set-metadata gc.routed_to= --append-notes Implemented: <brief summary>;" \
   "strict shell: a matching address in an oversized roster still writes (the pipe form takes SIGPIPE here)"

eq "$(run_strict_consume main gc-toolkit UNREADABLE)" \
   "0|UPDATE|tk-work --status=open --assignee=gc-toolkit/gc-toolkit.refinery --set-metadata target=main --set-metadata gc.routed_to= --append-notes Implemented: <brief summary>;" \
   "strict shell: a failed roster call still reaches the permissive arm rather than killing the step"

eq "$(run_strict_consume main gc-toolkit '[{"qualified_name":"gc-toolkit/gc-toolkit.polecat"}]')" \
   "1|DRAIN;" \
   "strict shell: a roster without the address still halts, and the diagnostic does not die on an empty grep"

# --- 3c. The anchor the summary belongs on. -----------------------------------
# pr-open.sh reads pr_summary off the row it enumerates: the OPEN bead carrying
# a merge_result for this branch. On fresh work that is the claimed bead. On a
# rework or rebase child it is a different bead, and a summary written to the
# child is never published — the PR body silently falls back to the dispatch
# text, which is the fallback the summary exists to remove.
#
# run_anchor_resolve <current-branch> <bd-list-rows-json> -> "<rc>|<GATING_ANCHOR>"
#   Rows are the shape real `gc bd list --json` returns. The block runs under
#   `set -euo pipefail`: it sits between a push and a handoff, so a crash here
#   costs the handoff, and both of its reads are pipefail traps.
run_anchor_resolve() {
  : > "$TMP/log"
  { printf 'set -euo pipefail\n'
    printf '%s\n' "$ANCHOR"
    printf 'printf "RESOLVED:%%s\\n" "$GATING_ANCHOR"\n'; } > "$TMP/anchor.sh"
  local rc=0
  CURRENT_BRANCH="$1" FAKE_ANCHOR_ROWS="$2" FAKE_LOG="$TMP/log" \
    bash "$TMP/anchor.sh" > "$TMP/out" 2>&1 || rc=$?
  printf '%s|%s' "$rc" "$(sed -n 's/^RESOLVED://p' "$TMP/out")"
}

printf '%s\n' "$ANCHOR" > "$TMP/anchor-syntax.sh"
bash -n "$TMP/anchor-syntax.sh" \
  && ok "extracted anchor resolver is syntactically valid bash" \
  || bad "extracted anchor resolver failed bash -n"

ANCHOR_ROW='[{"id":"tk-anchor","created_at":"2026-07-01T00:00:00Z","metadata":{"merge_result":"pull_request","branch":"polecat/su-uzy9.5"}}]'

# Fresh work: nothing else on the branch. The claimed bead IS the anchor, and
# the summary rides the handoff exactly as it did before this block existed.
eq "$(run_anchor_resolve polecat/tk-work '[]')" "0|" \
   "fresh: no other bead on the branch -> no anchor, the claimed bead is it"

# THE CASE THIS EXISTS FOR. A rework child standing on the reviewed branch: the
# anchor is a different, open, merge_result-carrying bead.
eq "$(run_anchor_resolve polecat/su-uzy9.5 "$ANCHOR_ROW")" "0|tk-anchor" \
   "rework child: the open merge_result-carrying bead on the branch is the anchor"

# Self-exclusion. An idempotent re-run reads its own stamped row back; a bead
# that elected itself would then stamp the summary onto itself twice and call
# it delivered.
eq "$(run_anchor_resolve polecat/tk-work \
      '[{"id":"tk-work","created_at":"2026-07-01T00:00:00Z","metadata":{"merge_result":"pull_request","branch":"polecat/tk-work"}}]')" \
   "0|" \
   "the claimed bead's own row is excluded from its anchor lookup"

# Carrying a merge_result is the whole predicate. A sibling child on the same
# branch has none and is not an anchor.
eq "$(run_anchor_resolve polecat/su-uzy9.5 \
      '[{"id":"tk-sibling","created_at":"2026-07-01T00:00:00Z","metadata":{"branch":"polecat/su-uzy9.5"}}]')" \
   "0|" \
   "a sibling carrying no merge_result is not an anchor"

# Every anchor state counts, not just the two gating ones: an anchor parked for
# a person still owns the PR, and the summary still belongs on it.
eq "$(run_anchor_resolve polecat/su-uzy9.5 \
      '[{"id":"tk-anchor","created_at":"2026-07-01T00:00:00Z","metadata":{"merge_result":"blocked","branch":"polecat/su-uzy9.5"}}]')" \
   "0|tk-anchor" \
   "an anchor parked in a human state is still the summary's destination"

# Two candidates: the OLDEST wins, the same tiebreak merge-push applies, so the
# two never disagree about which bead is the anchor.
eq "$(run_anchor_resolve polecat/su-uzy9.5 \
      '[{"id":"tk-aaaa1","created_at":"2026-07-15T00:00:00Z","metadata":{"merge_result":"pull_request","branch":"polecat/su-uzy9.5"}},{"id":"tk-zzzz9","created_at":"2026-07-01T00:00:00Z","metadata":{"merge_result":"pull_request","branch":"polecat/su-uzy9.5"}}]')" \
   "0|tk-zzzz9" \
   "two candidates -> oldest on created_at, matching merge-push's tiebreak"

# Step 4 detaches HEAD, so a re-run reaches this with no branch name. An empty
# branch must not be sent to `--metadata-field branch=`, which matches every
# bead recording no branch at all.
eq "$(run_anchor_resolve '' "$ANCHOR_ROW")" "0|" \
   "detached HEAD: no lookup rather than matching branchless beads"

# Unreadable answer. The step is between a push and a handoff; degrading to the
# dispatch-text fallback costs a good PR body, halting costs the handoff.
eq "$(run_anchor_resolve polecat/su-uzy9.5 'not json at all')" "0|" \
   "an unparseable probe resolves to no anchor instead of killing the step"

# --- 3d. The summary follows the anchor. --------------------------------------
# run_consume_anchor <summary-file> <gating-anchor> -> "<rc>|<log>"
run_consume_anchor() {
  : > "$TMP/log"
  printf 'set -euo pipefail\n' > "$TMP/anchor-consume.sh"
  printf '%s\n' "$CONSUME" | sed "s|{{binding_prefix}}|gc-toolkit.|g" >> "$TMP/anchor-consume.sh"
  local rc=0
  LANDING_TARGET=main GC_RIG="" FAKE_AGENTS="$ROSTER_OK" FAKE_LOG="$TMP/log" \
    GATING_ANCHOR="$2" PR_SUMMARY_FILE="$1" bash "$TMP/anchor-consume.sh" > "$TMP/out" 2>&1 || rc=$?
  printf '%s|%s' "$rc" "$(tr '\n' ';' < "$TMP/log")"
}

# THE ACCEPTANCE. A child's summary is stamped on the anchor — the row
# pr-open.sh enumerates — and the claimed bead's handoff carries no pr_summary,
# because writing it there would assert a summary nothing reads.
eq "$(run_consume_anchor "$TMP/summary.txt" tk-anchor)" \
   "0|UPDATE|tk-anchor --set-metadata pr_summary=Compares heads instead of names.;UPDATE|tk-work --status=open --assignee=gc-toolkit.refinery --set-metadata target=main --set-metadata gc.routed_to= --append-notes Implemented: <brief summary>;" \
   "child: the summary is stamped on the anchor, and the handoff stays otherwise atomic"

# The anchor write comes FIRST. It is metadata on a bead this session does not
# hold; sequencing it before the handoff keeps the write that releases the bead
# last, so a failure between the two loses a PR body, never the handoff.
eq "$(run_consume_anchor "$TMP/summary.txt" tk-anchor | tr ';' '\n' | sed -n '1p')" \
   "0|UPDATE|tk-anchor --set-metadata pr_summary=Compares heads instead of names." \
   "the anchor stamp is written before the handoff, not after it"

# Prose reaches the anchor whole, the same as it does the claimed bead.
eq "$(run_consume_anchor "$TMP/summary-multiline.txt" tk-anchor)" \
   "0|UPDATE|tk-anchor --set-metadata pr_summary=Line one.;Line two.;UPDATE|tk-work --status=open --assignee=gc-toolkit.refinery --set-metadata target=main --set-metadata gc.routed_to= --append-notes Implemented: <brief summary>;" \
   "a multi-line summary reaches the anchor whole"

# No summary composed: nothing is written to the anchor at all. An empty
# metadata value round-trips as set-but-empty, which would assert a summary the
# polecat never wrote and suppress pr-open.sh's own description fallback.
eq "$(run_consume_anchor "$TMP/summary-empty.txt" tk-anchor)" \
   "0|UPDATE|tk-work --status=open --assignee=gc-toolkit.refinery --set-metadata target=main --set-metadata gc.routed_to= --append-notes Implemented: <brief summary>;" \
   "no summary: the anchor is not touched"

# An empty GATING_ANCHOR is the fresh-work case and must be byte-identical to
# the pre-change behavior: one write, carrying the summary.
eq "$(run_consume_anchor "$TMP/summary.txt" '')" \
   "0|UPDATE|tk-work --status=open --assignee=gc-toolkit.refinery --set-metadata target=main --set-metadata gc.routed_to= --set-metadata pr_summary=Compares heads instead of names. --append-notes Implemented: <brief summary>;" \
   "fresh work: unchanged single atomic write carrying the summary"

# --- 4. The snippets compose. -------------------------------------------------
# They share variables across the step: the resolver reads $CURRENT_BRANCH from
# the gate, and the handoff reads $LANDING_TARGET from the resolver. Run all
# three in sequence exactly as the step does, on the rework shape — the
# end-to-end case the gate + resolver exist for.
: > "$TMP/log"
printf '%s\n' "$GATE" > "$TMP/both.sh"
printf '%s\n' "$RESOLVE" | sed "s|{{base_branch}}|polecat/su-uzy9.5|g" >> "$TMP/both.sh"
printf '%s\n' "$CONSUME" | sed "s|{{binding_prefix}}|gc-toolkit.|g" >> "$TMP/both.sh"
BOTH_RC=0
FAKE_BRANCH=polecat/su-uzy9.5 FAKE_META='{"branch":"polecat/su-uzy9.5","target":"main"}' \
  GC_RIG="" FAKE_AGENTS="$ROSTER_OK" FAKE_LOG="$TMP/log" bash "$TMP/both.sh" > "$TMP/out" 2>&1 || BOTH_RC=$?
eq "$BOTH_RC" "0" "composed run exits 0 on the rework shape"
eq "$(sed -n 's/^landing target: //p' "$TMP/out")" "main" \
   "composed run resolves the landing target to main, not to the pushed branch"
# The only write is the atomic handoff: metadata.branch already agreed, so
# nothing rewrites it, and target lands on main rather than the self-merge.
eq "$(tr '\n' ';' < "$TMP/log")" \
   "UPDATE|tk-work --status=open --assignee=gc-toolkit.refinery --set-metadata target=main --set-metadata gc.routed_to= --append-notes Implemented: <brief summary>;" \
   "composed run writes only the atomic handoff, with target=main"

# The same four snippets on the shape the whole change is for: a rework child
# whose branch is anchored by another open bead, with a summary composed. End to
# end, the summary must land on tk-anchor and the handoff on tk-work.
: > "$TMP/log"
printf '%s\n' "$GATE" > "$TMP/four.sh"
printf '%s\n' "$RESOLVE" | sed "s|{{base_branch}}|polecat/su-uzy9.5|g" >> "$TMP/four.sh"
printf '%s\n' "$ANCHOR" >> "$TMP/four.sh"
printf '%s\n' "$CONSUME" | sed "s|{{binding_prefix}}|gc-toolkit.|g" >> "$TMP/four.sh"
FOUR_RC=0
FAKE_BRANCH=polecat/su-uzy9.5 FAKE_META='{"branch":"polecat/su-uzy9.5","target":"main"}' \
  FAKE_ANCHOR_ROWS="$ANCHOR_ROW" PR_SUMMARY_FILE="$TMP/summary.txt" \
  GC_RIG="" FAKE_AGENTS="$ROSTER_OK" FAKE_LOG="$TMP/log" bash "$TMP/four.sh" > "$TMP/out" 2>&1 || FOUR_RC=$?
eq "$FOUR_RC" "0" "composed rework run exits 0"
eq "$(tr '\n' ';' < "$TMP/log")" \
   "UPDATE|tk-anchor --set-metadata pr_summary=Compares heads instead of names.;UPDATE|tk-work --status=open --assignee=gc-toolkit.refinery --set-metadata target=main --set-metadata gc.routed_to= --append-notes Implemented: <brief summary>;" \
   "composed rework run: summary to the anchor, handoff to the claimed bead"

# --- 5. Step-chain close. -----------------------------------------------------
# The husk generator (tk-y389z, tk-zab6q): mol-polecat-work closed no step
# bead, so every completed run left all seven open. They keep gc.routed_to on
# the polecat pool, the drain releases their assignee, and `load-context` — the
# only step nothing blocks — goes ready and claimable. The next polecat is
# offered a finished run as if it were new work. Half the open ledger was this.
#
# THE FAKE MODELS bd's BLOCKED-ISSUE RULE, and that is the point. Each step is
# blocked by the one before it and `bd` refuses to close a blocked issue:
#
#     tk-3kabdu: updating issue: cannot close blocked issue: tk-3kabdu is blocked by [tk-8yvm91]
#
# A fake that closed anything asked of it would pass a dependent-first loop
# that, run live, closes exactly ONE bead and reports five refusals — which is
# what shipped in the first draft of this change and what a live run caught.
# A stub must refuse what the tool refuses, or it hides a dead branch behind a
# green suite.

mkdir -p "$TMP/pack/assets/scripts"
cat > "$TMP/pack/assets/scripts/step-close.sh" <<'STEPCLOSE'
#!/usr/bin/env bash
# Fake step-close. Records every step ATTEMPTED, and closes one only when its
# blocker is already closed — bd's rule. $FAKE_REFUSE forces an identity
# refusal ("not this session's bead") independently of blocking.
step=""
while [ $# -gt 0 ]; do
  case "$1" in
    --step)    step="$2"; shift 2 ;;
    --outcome) shift 2 ;;
    *)         shift ;;
  esac
done
printf '%s\n' "$step" >> "$FAKE_ATTEMPTED"
case "${step#mol-polecat-work.}" in
  load-context)     blocker="" ;;
  workspace-setup)  blocker="load-context" ;;
  preflight-tests)  blocker="workspace-setup" ;;
  implement)        blocker="preflight-tests" ;;
  self-review)      blocker="implement" ;;
  submit-and-exit)  blocker="self-review" ;;
  *)                blocker="" ;;
esac
if [ -n "${FAKE_REFUSE:-}" ] && [ "$step" = "$FAKE_REFUSE" ]; then
  echo "step-close: FATAL — not this session's bead for $step" >&2; exit 2
fi
if [ -n "$blocker" ] && ! grep -qx "mol-polecat-work.$blocker" "$FAKE_CLOSED"; then
  echo "  ${step}: updating issue: cannot close blocked issue: blocked by [$blocker]" >&2
  exit 2
fi
printf '%s\n' "$step" >> "$FAKE_CLOSED"
# Also into the shared ordered log, when one is set: the halt-arm test needs
# the closes placed relative to the bead write and the drain, and one file is
# the only way to see that order.
[ -n "${FAKE_LOG:-}" ] && printf 'CLOSE|%s\n' "$step" >> "$FAKE_LOG"
exit 0
STEPCLOSE
chmod +x "$TMP/pack/assets/scripts/step-close.sh"

printf '%s\n' "$CLOSE" > "$TMP/close.sh"
bash -n "$TMP/close.sh" \
  && ok "extracted chain close is syntactically valid bash" \
  || bad "extracted chain close failed bash -n"

# Run the block under `set -e`. That is the strict reading of a shell snippet,
# and it is what makes the loop's `|| echo` load-bearing rather than
# decorative: without `set -e` a refused close is ignored by the shell anyway,
# so a test that dropped it would pass against a block with no tolerance at
# all. It also proves the snippet is safe to paste into a fail-fast harness —
# the candidate-resolution `[ -x ... ] && { ...; }` is exempt from `set -e`
# because a failing command before the final `&&` does not trigger the exit.
printf 'set -e\n%s\n' "$CLOSE" > "$TMP/close-run.sh"

# run_close [refused-step] [pack-dir] -> "<rc>|<steps CLOSED, in order>"
run_close() {
  : > "$TMP/closed"; : > "$TMP/attempted"; : > "$TMP/log"
  local rc=0
  GC_PACK_DIR="${2-$TMP/pack}" GC_RIG_ROOT="" GC_CITY_PATH="" \
    FAKE_REFUSE="${1-}" FAKE_CLOSED="$TMP/closed" FAKE_ATTEMPTED="$TMP/attempted" \
    FAKE_LOG="$TMP/log" \
    bash "$TMP/close-run.sh" > "$TMP/out" 2>&1 || rc=$?
  printf '%s|%s' "$rc" "$(sed 's/^mol-polecat-work\.//' "$TMP/closed" | tr '\n' ',' | sed 's/,$//')"
}
# steps the loop TRIED, regardless of outcome — proves it did not abort early.
attempted() { sed 's/^mol-polecat-work\.//' "$TMP/attempted" | tr '\n' ',' | sed 's/,$//'; }

ALL_SIX="load-context,workspace-setup,preflight-tests,implement,self-review,submit-and-exit"

# THE ORDER. Forward is the only order bd permits: the chain can unwind only
# from the unblocked end, and closing each step is what unblocks the next.
eq "$(run_close)" "0|$ALL_SIX" \
   "closes all six session-owned steps, forward order, load-context first"

# submit-and-exit closes LAST. It is workflow-finalize's only blocker, so
# reaching it is what arms the control-dispatcher finalizer as the backstop.
eq "$(run_close | sed 's/.*,//')" "submit-and-exit" \
   "submit-and-exit closes last, arming the control-dispatcher backstop"

# `workflow-finalize` is routed to core.control-dispatcher, which closes the
# workflow root and force-closes whatever is still open. Closing it here would
# take the finalizer's job and skip the root close.
case ",$(run_close)," in
  *workflow-finalize*) bad "chain close must never close workflow-finalize" ;;
  *)                   ok  "leaves workflow-finalize to the control-dispatcher" ;;
esac

# The work bead belongs to the refinery from step 6 onward. This block closes
# machinery only — it must not write to a bead at all.
eq "$(run_close >/dev/null; sed -n '/^UPDATE|/p' "$TMP/log" | tr '\n' ';')" "" \
   "writes nothing to any bead (the work bead stays the refinery's)"

# A refusal must not abort the loop. Refusing the FIRST step is the worst case:
# every later step is then blocked, so nothing closes at all — but all six must
# still be attempted and the block must exit 0.
REFUSED_FIRST="$(run_close mol-polecat-work.load-context)"
eq "$REFUSED_FIRST|$(attempted)" "0||$ALL_SIX" \
   "a refusal on the first step: nothing closes, but all six are still attempted"

# A refusal mid-chain closes everything up to it and blocks the rest, and still
# must not abort.
REFUSED_MID="$(run_close mol-polecat-work.implement)"
eq "$REFUSED_MID|$(attempted)" \
   "0|load-context,workspace-setup,preflight-tests|$ALL_SIX" \
   "a refusal mid-chain: predecessors close, successors block, loop continues"

# No step-close.sh on any candidate path must fail loudly rather than drain
# with the chain silently open — that is the failure this whole section exists
# to prevent, and `:?` is what makes it audible.
eq "$(run_close '' "$TMP/nonexistent")" "1|" \
   "missing step-close.sh: fails loudly, closes nothing"

# CONTROL: the same loop reversed. This is the shape that shipped in the first
# draft, and against a fake that ignored blocking it passed. Against bd's real
# rule it closes exactly one bead. Keeping it here is what stops the order
# being "simplified" back.
: > "$TMP/closed"; : > "$TMP/attempted"; : > "$TMP/log"
printf 'set -e\n%s\n' "$CLOSE" \
  | sed 's/^for STEP in .*; do$/for STEP in submit-and-exit self-review implement preflight-tests workspace-setup load-context; do/' \
  > "$TMP/close-rev.sh"
GC_PACK_DIR="$TMP/pack" GC_RIG_ROOT="" GC_CITY_PATH="" \
  FAKE_CLOSED="$TMP/closed" FAKE_ATTEMPTED="$TMP/attempted" FAKE_LOG="$TMP/log" \
  bash "$TMP/close-rev.sh" > "$TMP/out" 2>&1 || true
eq "$(sed 's/^mol-polecat-work\.//' "$TMP/closed" | tr '\n' ',' | sed 's/,$//')" \
   "load-context" \
   "control: dependent-first closes only load-context (bd refuses blocked issues)"

# The done sequence lives ONLY in this formula now (the native polecat prompt
# points at it instead of duplicating it), so there is no prompt-fragment copy
# to keep in sync. The one remaining copy is the halt arm's, pinned below.

# --- 6. The auto_push=false halt exit. ----------------------------------------
# There are two TERMINAL exits from submit-and-exit — the refinery handoff, and
# this branch-ready halt — and only terminal exits close the chain. Every other
# arm halts with the work resumable, where the open chain IS the recovery
# mechanism. The first cut of this change closed the chain at the handoff and
# left the halt arm a comment saying to run "step 7's block", four lines above
# an `exit 0` that never reaches step 7. An opt-out halt therefore
# stranded exactly the husk the change exists to stop, and nothing here ran the
# arm to notice. This section runs it.

# run_halt <script> -> "<rc>"; the ordered trace is left in $TMP/log.
run_halt() {
  : > "$TMP/log"; : > "$TMP/closed"; : > "$TMP/attempted"
  local rc=0
  FAKE_BRANCH=polecat/tk-work FAKE_META='{"auto_push":false}' LANDING_TARGET=main \
    GC_PACK_DIR="$TMP/pack" GC_RIG_ROOT="" GC_CITY_PATH="" \
    FAKE_LOG="$TMP/log" FAKE_CLOSED="$TMP/closed" FAKE_ATTEMPTED="$TMP/attempted" \
    bash "$1" > "$TMP/out" 2>&1 || rc=$?
  printf '%s' "$rc"
}
# The sequence of things the arm DID, one token per event — the only view that
# can show the closes landing between the bead write and the drain.
trace() { sed 's/|.*//' "$TMP/log" | tr '\n' ',' | sed 's/,$//'; }

printf '%s\n' "$HALT" > "$TMP/halt.sh"
bash -n "$TMP/halt.sh" \
  && ok "extracted auto_push=false arm is syntactically valid bash" \
  || bad "extracted halt arm failed bash -n"

# THE REGRESSION. The six closes must happen, and they must happen after the
# bead is parked and before the session drains.
HALT_RC="$(run_halt "$TMP/halt.sh")"
eq "$HALT_RC" "0" "halt arm exits 0"
eq "$(trace)" "UPDATE,CLOSE,CLOSE,CLOSE,CLOSE,CLOSE,CLOSE,DRAIN" \
   "halt arm parks the bead, closes six steps, THEN drains"
eq "$(sed -n 's/^CLOSE|mol-polecat-work\.//p' "$TMP/log" | tr '\n' ',' | sed 's/,$//')" \
   "$ALL_SIX" \
   "halt arm closes the same six steps, forward order"

# The bead write is the halt's whole point and is unchanged by this: branch and
# target recorded, assignee cleared, branch_ready + halt_reason set so the
# caller can tell an opt-out halt from a failure, and --append-notes rather
# than the --notes that erases the dispatch note (tk-6kf6r).
eq "$(sed -n 's/^UPDATE|//p' "$TMP/log")" \
   "tk-work --status=open --assignee= --set-metadata branch=polecat/tk-work --set-metadata target=main --set-metadata branch_ready=true --set-metadata halt_reason=auto_push_false --set-metadata gc.routed_to= --append-notes Branch ready: auto_push=false (no push, no refinery handoff)" \
   "halt arm's bead write is intact (branch_ready, halt_reason, --append-notes)"

# The arm must not reach the push. A fake `git` answers everything with exit 0,
# so a stray `git push` would pass unnoticed; the drain-then-exit trace above is
# what proves the arm stopped, and this pins the arm's own contents.
case "$HALT" in
  *"git push"*) bad "halt arm contains a push — it must not reach one" ;;
  *)            ok  "halt arm never reaches git push" ;;
esac

# The two copies of the block must not drift. They cannot be one function: the
# arm exits before step 7, and each fenced block is its own shell. So the halt
# copy is step 7's, indented one level to sit inside the `if` — assert exactly
# that, not merely that both are present. Two copies of one shell block is how
# the --notes correction was defeated before (tk-t41dq).
printf '%s\n' "$HALT_CLOSE" > "$TMP/halt-close.sh"
sed 's/^/  /' "$TMP/close.sh" > "$TMP/close-indented.sh"
if diff -q "$TMP/halt-close.sh" "$TMP/close-indented.sh" >/dev/null 2>&1; then
  ok "halt arm ships step 7's chain-close block, byte for byte (+2 indent)"
else
  bad "halt arm and step 7 chain-close blocks have DRIFTED"
  diff "$TMP/halt-close.sh" "$TMP/close-indented.sh" | sed 's/^/       /' || true
fi

# CONTROL: the arm as it was reviewed — same shell, chain-close block removed,
# comment left behind. It still exits 0 and still parks the bead, so nothing
# short of looking for the closes can tell the two apart. That is why the trace
# assertion above is the one that matters.
printf '%s\n' "$HALT" \
  | awk '/# >>> submit-halt-chain-close$/{f=1} /# <<< submit-halt-chain-close$/{f=0; next} !f' \
  > "$TMP/halt-nochain.sh"
CTRL_RC="$(run_halt "$TMP/halt-nochain.sh")"
eq "$CTRL_RC|$(trace)" "0|UPDATE,DRAIN" \
   "control: comment-only halt arm drains with the chain open (the defect is real)"

# --- 6b. The store-only exit. -------------------------------------------------
# The third TERMINAL exit, for a run whose whole product is store work: no
# branch, no commit, nothing for the refinery to merge. Every arm below it is
# gated on a branch, so before this one existed such a run reached no ending in
# the formula at all — the bead kept gc.routed_to, which IS a pool's offer
# predicate, and the pool handed the same finished work to the next polecat.
# It releases the bead with the halt arm's fields — status, assignee, cleared
# route, halt_reason, appended notes — minus the three that describe a branch.
# Two arms, one convention for what releasing a bead means.

# run_store <script> [env assignments...] -> "<rc>"; trace left in $TMP/log.
run_store() {
  : > "$TMP/log"; : > "$TMP/closed"; : > "$TMP/attempted"
  local script="$1"; shift
  local rc=0
  env "$@" FAKE_BRANCH=main GC_PACK_DIR="$TMP/pack" GC_RIG_ROOT="" GC_CITY_PATH="" \
    FAKE_LOG="$TMP/log" FAKE_CLOSED="$TMP/closed" FAKE_ATTEMPTED="$TMP/attempted" \
    bash "$script" > "$TMP/out" 2>&1 || rc=$?
  printf '%s' "$rc"
}

# The shipped snippet declares STORE_ONLY_RECORD empty — the polecat fills it
# in. `armed` is that same snippet with the declaration filled, which is what
# taking the arm looks like.
printf '%s\n' "$STORE" | sed "s|{{base_branch}}|main|g" > "$TMP/store.sh"
sed 's|^STORE_ONLY_RECORD=""$|STORE_ONLY_RECORD="tk-filed,gc-filed"|' "$TMP/store.sh" > "$TMP/store-armed.sh"
bash -n "$TMP/store.sh" \
  && ok "extracted store-only arm is syntactically valid bash" \
  || bad "extracted store-only arm failed bash -n"
[ "$(cmp -s "$TMP/store.sh" "$TMP/store-armed.sh"; echo $?)" = "1" ] \
  && ok "store-only arm ships STORE_ONLY_RECORD empty (the polecat opts in)" \
  || bad "store-only arm does not ship an empty STORE_ONLY_RECORD declaration"

# Not opted in: the arm is inert. A polecat with a branch to push must fall
# through to the gate having written nothing and drained nothing.
eq "$(run_store "$TMP/store.sh")|$(trace)" "0|" \
   "empty STORE_ONLY_RECORD: falls through, writes nothing, does not drain"

# THE ARM. Three writes, then the six closes, then the drain — the order is the
# contract, not an accident: metadata bypasses the claim guard, --status=open is
# accepted from the holder, and only then does the plain --assignee write land.
eq "$(run_store "$TMP/store-armed.sh")" "0" "store-only arm exits 0"
eq "$(trace)" "UPDATE,UPDATE,UPDATE,CLOSE,CLOSE,CLOSE,CLOSE,CLOSE,CLOSE,DRAIN" \
   "store-only arm releases in three writes, closes six steps, THEN drains"
eq "$(sed -n 's/^CLOSE|mol-polecat-work\.//p' "$TMP/log" | tr '\n' ',' | sed 's/,$//')" \
   "$ALL_SIX" \
   "store-only arm closes the same six steps, forward order"

# The writes themselves, and their ORDER, which is the whole reason there are
# three. A gc bd update that moves the assignee while this session still holds
# the bead is refused by bd's claim guard, and the refusal rolls back the
# metadata and the notes batched into the same call. Metadata first (it bypasses
# the guard), then --status=open from the holder, then the plain --assignee. The
# intermediate — open, still assigned, unrouted — no pool query can see.
eq "$(sed -n 's/^UPDATE|//p' "$TMP/log" | sed -n 1p)" \
   "tk-work --set-metadata halt_reason=store_only --set-metadata gc.routed_to= --append-notes Store-only exit: filed tk-filed,gc-filed. <what closes this bead, or the bead-rehome.sh invocation that disposes of it>" \
   "first write: halt_reason + cleared route + the filed record, --append-notes not --notes"
eq "$(sed -n 's/^UPDATE|//p' "$TMP/log" | sed -n 2p)" "tk-work --status=open" \
   "second write: --status=open alone, while the bead is still assigned"
eq "$(sed -n 's/^UPDATE|//p' "$TMP/log" | sed -n 3p)" "tk-work --assignee=" \
   "third write: --assignee alone, after the status is open"
eq "$(sed -n 's/^UPDATE|//p' "$TMP/log" | sed -n 1p | grep -c -- '--assignee')" "0" \
   "the assignee is NOT batched with the metadata (that call is refused whole)"

# The release is the halt arm's, so the two are compared rather than described:
# every gc.routed_to write in either arm clears it, and neither routes anywhere.
eq "$(printf '%s\n' "$STORE" | grep -o -- '--set-metadata gc.routed_to=[^ ]*' | sort -u)" \
   "$(printf '%s\n' "$HALT" | grep -o -- '--set-metadata gc.routed_to=[^ ]*' | sort -u)" \
   "store-only arm clears the route exactly as the halt arm does"
case "$STORE" in
  *'gc.routed_to=""'*) ok  "store-only arm clears gc.routed_to" ;;
  *)                   bad "store-only arm does not clear gc.routed_to — the pool re-offers the bead" ;;
esac
case "$STORE" in
  *"--notes "*) bad "store-only arm uses --notes, which REPLACES the dispatch note" ;;
  *)            ok  "store-only arm appends notes rather than replacing them" ;;
esac

# THE REFUSAL. The arm is opt-in prose, so the only thing standing between a
# half-finished run and a released bead is this check. Each of the three
# signals alone must refuse, and refuse before writing anything.
eq "$(run_store "$TMP/store-armed.sh" FAKE_AHEAD=2)|$(trace)" "1|DRAIN" \
   "commits ahead of base: refuses, drains, writes nothing"
eq "$(run_store "$TMP/store-armed.sh" FAKE_DIRTY=' M formulas/mol-polecat-work.toml')|$(trace)" "1|DRAIN" \
   "uncommitted changes: refuses, drains, writes nothing"
eq "$(run_store "$TMP/store-armed.sh" FAKE_PUSHED='abc123	refs/heads/polecat/tk-work')|$(trace)" "1|DRAIN" \
   "branch already on origin: refuses, drains, writes nothing"

# The arm must not reach the push, and must not hand the bead to the refinery:
# there is no branch, so a handoff would strand it in the merge queue forever.
case "$STORE" in
  *"git push"*)  bad "store-only arm contains a push — it has nothing to push" ;;
  *)             ok  "store-only arm never reaches git push" ;;
esac
eq "$(printf '%s\n' "$STORE" | grep -o -- '--assignee=[^ ]*' | sort -u | tr '\n' ',' | sed 's/,$//')" \
   '--assignee=""' \
   "the arm's only assignee write CLEARS it — a branchless bead handed to the refinery never merges"

# Same drift guard the halt arm gets: the chain-close copy is step 7's block,
# indented one level to sit inside the `if`.
printf '%s\n' "$STORE_CLOSE" > "$TMP/store-close.sh"
if diff -q "$TMP/store-close.sh" "$TMP/close-indented.sh" >/dev/null 2>&1; then
  ok "store-only arm ships step 7's chain-close block, byte for byte (+2 indent)"
else
  bad "store-only arm and step 7 chain-close blocks have DRIFTED"
  diff "$TMP/store-close.sh" "$TMP/close-indented.sh" | sed 's/^/       /' || true
fi

# CONTROL: the same arm with its chain-close removed still exits 0 and still
# releases the bead, so only the trace above tells a complete arm from one that
# leaves six step beads open to be re-offered as new work.
awk '/# >>> submit-store-only-chain-close$/{f=1} /# <<< submit-store-only-chain-close$/{f=0; next} !f' \
  "$TMP/store-armed.sh" > "$TMP/store-nochain.sh"
eq "$(run_store "$TMP/store-nochain.sh")|$(trace)" "0|UPDATE,UPDATE,UPDATE,DRAIN" \
   "control: chain-less store-only arm drains with the chain open (the defect is real)"

# --- 6c. The operator-merge park exit. ----------------------------------------
# The fourth TERMINAL exit, for a run whose PR lives in a repository this rig's
# refinery does not cover — a bead slung into this pool whose work belonged to an
# HQ-rig repo, pushed and PR'd there by hand. The refinery reads a PR by NUMBER
# in its OWN repo (merge.sh), so handing off aims it at whatever carries that
# number there. This arm parks the anchor for a person instead: the store-only
# release shape, but routed to the `human` sentinel rather than cleared, with the
# PR recorded and no merge_result stamped.
RIG_HTTPS="https://github.com/zookanalytics/gc-toolkit.git"
RIG_SSH="git@github.com:zookanalytics/gc-toolkit.git"
FOREIGN_PR="https://github.com/zookanalytics/loomington/pull/3"

printf '%s\n' "$OPMERGE" > "$TMP/opmerge.sh"
awk '/# >>> submit-operator-merge-chain-close$/{f=1} /# <<< submit-operator-merge-chain-close$/{f=0; next} !f' \
  "$TMP/opmerge.sh" > "$TMP/opmerge-nochain.sh"

# run_opmerge <pr-url> <rig-origin> [chainless] -> "<rc>"; trace left in $TMP/log.
#   Fills OPERATOR_MERGE_PR the way a polecat does. FAKE_RIG_ORIGIN is the repo
#   the refinery covers; the arm's `git -C "$GC_RIG_ROOT" remote get-url origin`
#   answers it, so no real second checkout is needed.
run_opmerge() {
  : > "$TMP/log"; : > "$TMP/closed"; : > "$TMP/attempted"
  local src="$TMP/opmerge.sh"
  [ "${3:-}" = chainless ] && src="$TMP/opmerge-nochain.sh"
  sed "s|^OPERATOR_MERGE_PR=\"\"\$|OPERATOR_MERGE_PR=\"$1\"|" "$src" > "$TMP/opmerge-run.sh"
  local rc=0
  FAKE_RIG_ORIGIN="$2" GC_PACK_DIR="$TMP/pack" GC_RIG_ROOT="$TMP/rig" GC_CITY_PATH="" \
    FAKE_LOG="$TMP/log" FAKE_CLOSED="$TMP/closed" FAKE_ATTEMPTED="$TMP/attempted" \
    bash "$TMP/opmerge-run.sh" > "$TMP/out" 2>&1 || rc=$?
  printf '%s' "$rc"
}

bash -n "$TMP/opmerge.sh" \
  && ok "extracted operator-merge arm is syntactically valid bash" \
  || bad "extracted operator-merge arm failed bash -n"

# Ships the opt-in variable empty, like store-only's — the polecat fills it.
case "$OPMERGE" in
  *'OPERATOR_MERGE_PR=""'*) ok  "operator-merge arm ships OPERATOR_MERGE_PR empty (the polecat opts in)" ;;
  *)                        bad "operator-merge arm does not ship an empty OPERATOR_MERGE_PR declaration" ;;
esac

# Not opted in: inert. A polecat handing off the normal way falls through having
# written nothing and drained nothing.
eq "$(run_opmerge '' "$RIG_HTTPS")|$(trace)" "0|" \
   "empty OPERATOR_MERGE_PR: falls through, writes nothing, does not drain"

# THE ARM. A foreign PR: three writes, then six closes, then the drain — the
# same release order store-only proved, so the claim guard accepts it.
eq "$(run_opmerge "$FOREIGN_PR" "$RIG_HTTPS")" "0" "operator-merge arm exits 0 on a foreign PR"
eq "$(trace)" "UPDATE,UPDATE,UPDATE,CLOSE,CLOSE,CLOSE,CLOSE,CLOSE,CLOSE,DRAIN" \
   "operator-merge arm parks in three writes, closes six steps, THEN drains"
eq "$(sed -n 's/^CLOSE|mol-polecat-work\.//p' "$TMP/log" | tr '\n' ',' | sed 's/,$//')" \
   "$ALL_SIX" \
   "operator-merge arm closes the same six steps, forward order"

# The three writes and their order. The FIRST carries the park: halt_reason, the
# repo-qualified pr_url, the human route, and the note APPENDED. The route is
# `human`, not cleared — the one field that differs from store-only.
eq "$(sed -n 's/^UPDATE|//p' "$TMP/log" | sed -n 1p)" \
   "tk-work --set-metadata halt_reason=awaiting_operator_merge --set-metadata pr_url=$FOREIGN_PR --set-metadata gc.routed_to=human --append-notes Parked for operator merge: $FOREIGN_PR is in zookanalytics/loomington, which this rig's refinery does not cover. A person merges the PR and closes this bead. No merge_result is stamped: merge.sh reads the PR number in the refinery's own repo, not this pr_url." \
   "first write: halt_reason + pr_url + human route + the note, --append-notes not --notes"
eq "$(sed -n 's/^UPDATE|//p' "$TMP/log" | sed -n 2p)" "tk-work --status=open" \
   "second write: --status=open alone, while the bead is still assigned"
eq "$(sed -n 's/^UPDATE|//p' "$TMP/log" | sed -n 3p)" "tk-work --assignee=" \
   "third write: --assignee alone, after the status is open"
eq "$(sed -n 's/^UPDATE|//p' "$TMP/log" | sed -n 1p | grep -c -- '--assignee')" "0" \
   "the assignee is NOT batched with the metadata (that call is refused whole)"

# The park routes to the human sentinel and stamps NO merge_result — a
# merge_result would put the anchor on merge.sh's enumeration, which is the whole
# thing this arm exists to avoid.
case "$OPMERGE" in
  *"gc.routed_to=human"*) ok  "operator-merge arm routes to the human sentinel" ;;
  *)                      bad "operator-merge arm does not route to human — the pool re-offers the bead" ;;
esac
# The note explains "No merge_result is stamped", so match the WRITE form rather
# than the bare word the prose also carries.
case "$OPMERGE" in
  *"--set-metadata merge_result"*) bad "operator-merge arm writes a merge_result — merge.sh would enumerate the anchor" ;;
  *)                               ok  "operator-merge arm stamps no merge_result" ;;
esac
case "$OPMERGE" in
  *"--notes "*) bad "operator-merge arm uses --notes, which REPLACES the dispatch note" ;;
  *)            ok  "operator-merge arm appends notes rather than replacing them" ;;
esac
case "$OPMERGE" in
  *"git push"*) bad "operator-merge arm contains a push — the branch is already on its foreign origin" ;;
  *)            ok  "operator-merge arm never reaches git push" ;;
esac

# ssh-form rig origin canonicalizes the same as https, so the discriminator holds
# whichever URL form the refinery's checkout records.
eq "$(run_opmerge "$FOREIGN_PR" "$RIG_SSH")" "0" \
   "ssh-form rig origin: still parks the foreign PR (canonicalization agrees across URL forms)"

# THE REFUSALS. The arm is opt-in prose, so this is what stops a misfilled
# variable from parking real refinery work or a non-PR string. A PR in the rig's
# OWN repo belongs to the refinery: refuse, drain, write nothing.
eq "$(run_opmerge "https://github.com/zookanalytics/gc-toolkit/pull/9" "$RIG_HTTPS")|$(trace)" "1|DRAIN" \
   "a PR in the rig's own repo: refuses, drains, writes nothing"
eq "$(run_opmerge "not-a-pr-url" "$RIG_HTTPS")|$(trace)" "1|DRAIN" \
   "a non-URL OPERATOR_MERGE_PR: refuses, drains, writes nothing"
# A URL that names an owner/repo but is not a pull request — a bare repo URL or
# an issue URL — carries no /pull/<n>, so it must refuse rather than park a
# pr_url with no PR behind it. (Weaken the check to a plain owner/repo match and
# both park instead: that is the regression these two guard.)
eq "$(run_opmerge "https://github.com/zookanalytics/loomington/issues/3" "$RIG_HTTPS")|$(trace)" "1|DRAIN" \
   "an issue URL (owner/repo, no /pull/<n>): refuses, drains, writes nothing"
eq "$(run_opmerge "https://github.com/zookanalytics/loomington" "$RIG_HTTPS")|$(trace)" "1|DRAIN" \
   "a bare repo URL (owner/repo, no /pull/<n>): refuses, drains, writes nothing"

# Same drift guard the other terminal arms get: the chain-close copy is step 7's
# block, indented one level to sit inside the `if`.
printf '%s\n' "$OPMERGE_CLOSE" > "$TMP/opmerge-close.sh"
if diff -q "$TMP/opmerge-close.sh" "$TMP/close-indented.sh" >/dev/null 2>&1; then
  ok "operator-merge arm ships step 7's chain-close block, byte for byte (+2 indent)"
else
  bad "operator-merge arm and step 7 chain-close blocks have DRIFTED"
  diff "$TMP/opmerge-close.sh" "$TMP/close-indented.sh" | sed 's/^/       /' || true
fi

# CONTROL: the same arm with its chain-close removed still parks and drains, so
# only the trace tells a complete arm from one that leaves six step beads open.
eq "$(run_opmerge "$FOREIGN_PR" "$RIG_HTTPS" chainless)|$(trace)" "0|UPDATE,UPDATE,UPDATE,DRAIN" \
   "control: chain-less operator-merge arm drains with the chain open (the defect is real)"

# --- 7. Negative control. -----------------------------------------------------
# Everything above passes against the shipped snippets. That proves nothing
# unless the same fixtures FAIL against the implementation being replaced —
# otherwise a future reconciliation could restore base and the suite would stay
# green. Base's two lines are reproduced literally here; they are a control, not
# a mirror of base, and are not expected to track it.
BASE_RC=0
cat > "$TMP/base-gate.sh" <<'BASE'
EXPECTED_BRANCH="polecat/$WORK_BEAD_ID"
[ "$CURRENT_BRANCH" = "$EXPECTED_BRANCH" ] || exit 1
BASE
CURRENT_BRANCH=polecat/su-uzy9.5 bash "$TMP/base-gate.sh" || BASE_RC=$?
eq "$BASE_RC" "1" \
   "control: base's templated gate REJECTS the rework branch (the defect is real)"

# Base wrote target={{base_branch}} unconditionally. Render it through the same
# substitution the resolver gets, on the same fixture, and compare both answers
# against the branch being pushed: base's IS that branch, the shipped
# resolver's is not.
printf '%s\n' 'TARGET="{{base_branch}}"; printf "%s" "$TARGET"' \
  | sed "s|{{base_branch}}|polecat/su-uzy9.5|g" > "$TMP/base-target.sh"
BASE_TARGET="$(bash "$TMP/base-target.sh")"
OURS_TARGET="$(run_resolve polecat/su-uzy9.5 polecat/su-uzy9.5 '{"target":"main"}')"
eq "$BASE_TARGET|$OURS_TARGET" "polecat/su-uzy9.5|0|main" \
   "control: base renders target == the pushed branch (self-merge); shipped resolver renders main"

echo
echo "submit-branch-gate: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
