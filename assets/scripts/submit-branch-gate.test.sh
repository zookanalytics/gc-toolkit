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
#      at BOTH terminal exits (handoff, and the auto_push=false halt), and
#      workflow-finalize is never touched.
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
CLOSE="$(extract submit-chain-close)"
HALT="$(extract submit-auto-push-halt)"
HALT_CLOSE="$(extract submit-halt-chain-close)"

[ -n "$CLOSE" ] \
  && ok "chain close extracted between submit-chain-close markers" \
  || bad "chain-close extraction EMPTY — markers missing from $TOML"

[ -n "$HALT" ] \
  && ok "auto_push=false arm extracted between submit-auto-push-halt markers" \
  || bad "halt-arm extraction EMPTY — markers missing from $TOML"

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

# TOML `"""` strings treat a trailing backslash as a line-ending escape and eat
# the newline plus the following indentation. A shell line-continuation written
# inside one therefore silently joins lines. Both snippets are written
# backslash-free so what the polecat reads is what this test runs; assert it,
# because reintroducing a continuation is an easy and invisible edit.
case "$GATE$RESOLVE$CONSUME$CLOSE$HALT$HALT_CLOSE" in
  *\\*) bad "snippets contain a backslash — TOML line-ending escapes will mangle them" ;;
  *)    ok  "snippets are backslash-free (safe inside a TOML triple-quoted string)" ;;
esac

# The declared default is what a source-read reconstruction renders, and it is
# reached only when the poured step was bypassed — exactly when nothing else is
# watching. Empty renders `<rig>/refinery`, an address no agent holds, and the
# refinery's exact-match find-work then never reads the bead (tk-xkz600). Every
# substitution below pins `gc-toolkit.` explicitly, so none of them can see it.
BP_DEFAULT="$(awk '
  /^\[vars\.binding_prefix\]$/ {f=1; next}
  f && /^\[/                    {exit}
  f && /^default[ \t]*=/         {sub(/^default[ \t]*=[ \t]*"/, ""); sub(/"$/, ""); print; exit}
' "$TOML")"
[ -n "$BP_DEFAULT" ] \
  && ok "binding_prefix declares a non-empty default ($BP_DEFAULT)" \
  || bad "binding_prefix default is EMPTY — a source-read renders <rig>/refinery, which names no agent"

# --- Fakes. -------------------------------------------------------------------
# git   : only `git branch --show-current` is used; it answers $FAKE_BRANCH.
# gc    : `gc bd show <id> --json` returns $FAKE_META as the metadata object,
#         `gc bd update ...` and `gc runtime drain-ack` are recorded so the
#         assertions can prove WHAT was written and WHETHER the arm halted.
#         `gc agent list --json` answers $FAKE_AGENTS; the value UNREADABLE
#         makes the call fail, which reaches the guard as a different cause
#         than an empty roster but must take the same arm.
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

# $3 is set-but-empty on purpose in the bug case, so `${3-...}` (not `${3:-...}`)
# is the expansion that renders it.
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

# THE BUG (tk-xkz600). {{binding_prefix}} rendered empty, which is what the
# formula's own declared default produced whenever this command was rebuilt from
# the .toml instead of read out of the poured step. The address becomes
# `gc-toolkit/refinery`; the refinery's find-work is exact-match on assignee, so
# the bead is simply never read and no error is raised anywhere. Two occurrences
# in one day, one of them found only because the refinery happened to trip over
# it out of band. The halt must come BEFORE the write, so the log carries DRAIN
# and no UPDATE at all.
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
