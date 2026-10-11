#!/usr/bin/env bash
# Hermetic test for submit-and-exit.sh, the mechanics of mol-polecat-work's
# terminal step.
#
# What it holds:
#   1. BRANCH GATE — the invariant is CURRENT_BRANCH == metadata.branch;
#      `polecat/<bead-id>` is only how FRESH work satisfies it. A rework
#      child legitimately stands on the reviewed branch.
#   2. TARGET RESOLVE — the base branch is "branch FROM", never "land INTO".
#      A caller-set metadata.target wins; the base fills in only for fresh
#      work; nothing resolvable fails closed (never a self-merge).
#   3. REFINERY HANDOFF — three gc bd update writes (metadata + APPENDED notes
#      clearing the route, then --status=open, then the refinery --assignee)
#      carry target + refinery assignee + cleared route, split so the claim
#      guard cannot refuse reassigning a bead this session still holds; a
#      partial handoff cannot ship. The summary and a retitle follow the anchor.
#   4. CHAIN CLOSE — five session-owned steps close forward via step-close.sh
#      at ALL THREE terminal exits (handoff, the auto_push=false halt, and the
#      store-only exit), and workflow-finalize is never touched.
#   5. STORE-ONLY EXIT — a run that produced no commit releases the bead the
#      way the halt arm does, in three writes the claim guard accepts, and
#      refuses the arm outright when the run has a diff to land.
#   6. SESSION PINS — every terminal exit that lets go of the bead removes the
#      claim's gc.session_id and gc.session_name in its first write, the same
#      pair at all three.
#   7. ORDER — the push precedes the bring-current guard, the guard precedes the
#      handoff, and the branch release follows both the handoff and the chain
#      close.
#   8. WIRING — mol-polecat-work's submit-and-exit step runs the script.
#
# Runs submit-and-exit.sh, and the real escalate-hold-drain.sh it calls, against
# a fake `git` and `gc`, a step-close.sh that enforces bd's blocked-issue rule,
# and stub escalate.sh, molecule-hold.sh and bring-current-guard.sh. No live
# city, Dolt, network, or worktrees.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TOML="$ROOT/formulas/mol-polecat-work.toml"
SUT="$HERE/submit-and-exit.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-submit-and-exit-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"   # tomllib_python only; the assertions below are this suite's own

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 ('$2' not in '$1')" ;; esac; }

command -v jq >/dev/null 2>&1 || { echo "jq is required for this test" >&2; exit 1; }
[ -f "$TOML" ] || { echo "formula not found: $TOML" >&2; exit 1; }
[ -x "$SUT" ] && ok "submit-and-exit.sh is executable" || bad "submit-and-exit.sh missing or not executable: $SUT"
bash -n "$SUT" && ok "submit-and-exit.sh is syntactically valid bash" || bad "submit-and-exit.sh failed bash -n"

# --- The formula wiring. ------------------------------------------------------
# The step runs the script's entry points; a formula edit that drops one fails
# here. The step text is read through tomllib so the checks cannot match a
# neighbouring step.
if TOML_PY="$(tomllib_python)"; then
  SUBMIT_DESC="$("$TOML_PY" -c "
import sys, tomllib
d = tomllib.load(open(sys.argv[1],'rb'))
print([s for s in d['steps'] if s['id']=='submit-and-exit'][0]['description'])
" "$TOML")"
  has "$SUBMIT_DESC" '/submit-and-exit.sh" handoff --bead "$WORK_BEAD_ID" --base {{base_branch}} --refinery "${GC_RIG:+$GC_RIG/}{{binding_prefix}}refinery"' \
      "the step hands off through submit-and-exit.sh handoff with the rendered refinery address"
  has "$SUBMIT_DESC" '--step-bead "${CLAIMED_STEP_BEAD_ID:-}"' "and passes the claimed step bead as the hold's hint"
  has "$SUBMIT_DESC" '--summary-file "$PR_SUMMARY_FILE"' "and carries the PR summary file"
  has "$SUBMIT_DESC" '/submit-and-exit.sh" store-only --bead "$WORK_BEAD_ID" --base {{base_branch}}' \
      "the step's store-only exit runs submit-and-exit.sh store-only"
  has "$SUBMIT_DESC" '/submit-and-exit.sh" anchor --bead "$WORK_BEAD_ID"' "the step reads the anchor's title through submit-and-exit.sh anchor"
  # TOML `"""` strings treat a trailing backslash as a line-ending escape and eat
  # the newline, so a shell continuation in the step text silently joins lines.
  case "$SUBMIT_DESC" in
    *\\*) bad "the submit-and-exit step text contains a backslash — TOML line-ending escapes will mangle it" ;;
    *)    ok  "the submit-and-exit step text is backslash-free" ;;
  esac
else
  echo "skip - the submit-and-exit step text: $TOML_PY"
fi

# The declared default is what a source-read reconstruction renders, and it is
# reached only when the poured step was bypassed. Empty renders `<rig>/refinery`,
# an address no agent holds, and the refinery's exact-match find-work then never
# reads the bead.
BP_DEFAULT="$(awk '
  /^\[vars\.binding_prefix\]$/ {f=1; next}
  f && /^\[/                    {exit}
  f && /^default[ \t]*=/         {sub(/^default[ \t]*=[ \t]*"/, ""); sub(/"$/, ""); print; exit}
' "$TOML")"
[ -n "$BP_DEFAULT" ] \
  && ok "binding_prefix declares a non-empty default ($BP_DEFAULT)" \
  || bad "binding_prefix default is EMPTY — a source-read renders <rig>/refinery, which names no agent"

# --- Fakes. -------------------------------------------------------------------
# git   : `branch --show-current` answers $FAKE_BRANCH; the store-only probes
#         answer $FAKE_AHEAD / $FAKE_DIRTY / $FAKE_PUSHED, each empty by default
#         so the arm sees a run with nothing to land. `push` is recorded and
#         exits $FAKE_PUSH_RC; once a push lands, `ls-remote` answers
#         $FAKE_LOCAL_HEAD, the head `rev-parse HEAD` reports, unless
#         $FAKE_PUSH_LOST says the ref never reached origin. `checkout` and
#         `branch -D` are recorded.
# gc    : `gc bd show <id> --json` returns $FAKE_META as the metadata object,
#         `gc bd update ...` and `gc runtime drain-ack` are recorded so the
#         assertions can prove WHAT was written and WHETHER the run halted.
#         `gc bd update` ENFORCES bd's claim guard: an assignee change on an
#         in_progress bead is refused and rolled back (records nothing, exits 1),
#         so a one-shot handoff fails exactly as it does against real bd and only
#         the metadata -> status=open -> assignee split lands. Current state is
#         reconstructed from this scenario's own log (reset per scenario), so a
#         fresh bead is in_progress and held — what the polecat holds at handoff.
#         `gc agent list --json` answers $FAKE_AGENTS; the value UNREADABLE
#         makes the call fail, which reaches the roster check as a different
#         cause than an empty roster but must take the same arm. `gc session
#         wake|nudge` record WAKE and NUDGE.
mkdir -p "$TMP/bin"

{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/git" <<'GIT'
case "$1 $2" in
  "branch --show-current") printf '%s\n' "${FAKE_BRANCH:-}"; exit 0 ;;
  "rev-list --count")      printf '%s\n' "${FAKE_AHEAD:-0}"; exit 0 ;;
  "status --porcelain")    [ -n "${FAKE_DIRTY:-}" ] && printf '%s\n' "$FAKE_DIRTY"; exit 0 ;;
  "rev-parse HEAD")        printf '%s\n' "${FAKE_LOCAL_HEAD:-sha-local}"; exit 0 ;;
  "ls-remote origin")
    if [ -e "${FAKE_PUSH_STATE:-/nonexistent}" ] && [ -z "${FAKE_PUSH_LOST:-}" ]; then
      printf '%s\trefs/heads/x\n' "${FAKE_LOCAL_HEAD:-sha-local}"
    elif [ -n "${FAKE_PUSHED:-}" ]; then
      printf '%s\n' "$FAKE_PUSHED"
    fi
    exit 0 ;;
  "push origin")
    printf 'GIT|push %s\n' "$3" >> "${FAKE_LOG:-/dev/null}"
    [ "${FAKE_PUSH_RC:-0}" = "0" ] && : > "${FAKE_PUSH_STATE:-/dev/null}"
    exit "${FAKE_PUSH_RC:-0}" ;;
esac
if [ "$1" = "checkout" ] || { [ "$1" = "branch" ] && [ "$2" = "-D" ]; }; then
  printf 'GIT|%s\n' "$*" >> "${FAKE_LOG:-/dev/null}"
  exit "${FAKE_GIT_RC:-0}"
fi
exit 0
GIT

{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/gc" <<'GC'
case "$1 $2" in
  "runtime drain-ack") printf 'DRAIN\n' >> "$FAKE_LOG"; exit 0 ;;
  "bd show")           printf '[{"title":"%s","metadata":%s}]\n' "${FAKE_SHOW_TITLE:-}" "${FAKE_META:-{\}}"; exit 0 ;;
  "bd update")
    # Model bd's claim guard (validation.AssigneeNotStolen): reassigning an
    # in_progress bead held by someone the caller is not is refused, and the
    # refusal rolls the WHOLE call back. The polecat's actor is its session NAME
    # (BEADS_ACTOR) while the hook-claim holder is its session ID, so the two
    # never match; we model that as always mismatched and refuse any assignee
    # CHANGE while the bead is in_progress. Once --status=open lands, the bead is
    # no longer in_progress and the assignee write is accepted.
    shift 2
    id="$1"; argv="$*"
    # $FAKE_TITLE_REFUSE refuses any title write, as bd refuses a title it will
    # not store, so the handoff can be shown to survive a refused retitle.
    case " $argv " in *' --title '*) [ -n "${FAKE_TITLE_REFUSE:-}" ] && { printf 'Error: title refused\n' >&2; exit 1; } ;; esac
    cur_status=in_progress; cur_assignee=lx-holder
    if [ -s "${FAKE_LOG:-/dev/null}" ]; then
      beadlines=$(grep -F "UPDATE|$id " "$FAKE_LOG" 2>/dev/null || true)
      s=$(printf '%s\n' "$beadlines" | grep -oE -- '--status=[^ ]*' | tail -1 | sed 's/^--status=//')
      [ -n "$s" ] && cur_status="$s"
      if grep -qE -- '--assignee=' <<< "$beadlines"; then
        cur_assignee=$(printf '%s\n' "$beadlines" | grep -oE -- '--assignee=[^ ]*' | tail -1 | sed 's/^--assignee=//')
      fi
    fi
    has_assignee=0; new_assignee=""
    case " $argv " in *' --assignee='*) has_assignee=1; new_assignee=$(printf '%s\n' "$argv" | grep -oE -- '--assignee=[^ ]*' | head -1 | sed 's/^--assignee=//') ;; esac
    # $FAKE_FORCE_GUARD forces the refusal on any assignee change regardless of
    # status, to exercise the handoff's fail-closed arm on a write that is
    # refused even after the split (a shape the real guard should never take).
    if [ "$has_assignee" = 1 ] && [ -n "$cur_assignee" ] && [ "$new_assignee" != "$cur_assignee" ] && { [ "$cur_status" = in_progress ] || [ -n "${FAKE_FORCE_GUARD:-}" ]; }; then
      printf 'cannot reassign %s: held by "%s" (in_progress); coordinate with the holder — pass --force only if their claim is abandoned\n' "$id" "$cur_assignee" >&2
      printf 'Error: 1 of 1 issues failed to update\n' >&2
      exit 1
    fi
    printf 'UPDATE|%s\n' "$argv" >> "$FAKE_LOG"; exit 0 ;;
  "bd list")           printf '%s\n' "${FAKE_ANCHOR_ROWS-[]}"; exit 0 ;;
  "agent list")        [ "${FAKE_AGENTS-}" = "UNREADABLE" ] && exit 1
                       printf '{"agents":%s}\n' "${FAKE_AGENTS:-[]}"; exit 0 ;;
  "session wake")      printf 'WAKE\n' >> "$FAKE_LOG"; exit 0 ;;
  "session nudge")     printf 'NUDGE\n' >> "$FAKE_LOG"; exit 0 ;;
esac
exit 0
GC

chmod +x "$TMP/bin/git" "$TMP/bin/gc"
export PATH="$TMP/bin:$PATH"

# molecule-hold.sh and escalate.sh, which the real escalate-hold-drain.sh
# resolves through GC_MOLECULE_HOLD_TOOL and GC_ESCALATE_TOOL. Every fail-closed
# arm ESCALATES (records a release path), then HOLDS, then drains: a step left
# `open` and routed is re-offered to a fresh polecat every cycle, and a hold with
# no visit is a silent park no human is asked to clear. Each stub records its
# call so the order can be asserted, and returns a code the assertions control.
mkdir -p "$TMP/stubs"
cat > "$TMP/stubs/molecule-hold.sh" <<'HOLD'
#!/usr/bin/env bash
# The verb alone goes in the ordered trace; the argv goes where the reason
# assertions can read it without widening every expected log string.
printf 'HOLD\n' >> "$FAKE_LOG"
printf '%s\n' "$*" >> "${FAKE_HOLD:-/dev/null}"
exit "${FAKE_HOLD_RC:-0}"
HOLD
cat > "$TMP/stubs/escalate.sh" <<'ESC'
#!/usr/bin/env bash
printf 'ESCALATE\n' >> "$FAKE_LOG"
printf '%s\n' "$*" >> "${FAKE_ESCALATE:-/dev/null}"
exit "${FAKE_ESC_RC:-0}"
ESC
cat > "$TMP/stubs/bring-current-guard.sh" <<'BCG'
#!/usr/bin/env bash
printf 'GUARD\n' >> "$FAKE_LOG"
printf '%s\n' "$*" >> "${FAKE_GUARD_ARGV:-/dev/null}"
exit "${FAKE_GUARD_RC:-0}"
BCG

# Fake step-close. Records every step ATTEMPTED, and closes one only when its
# blocker is already closed — bd's rule:
#
#     tk-3kabdu: updating issue: cannot close blocked issue: tk-3kabdu is blocked by [tk-8yvm91]
#
# A fake that closed anything asked of it would pass a dependent-first loop
# that, run live, closes exactly ONE bead and reports five refusals. A stub must
# refuse what the tool refuses, or it hides a dead branch behind a green suite.
# $FAKE_REFUSE forces an identity refusal ("not this session's bead")
# independently of blocking.
cat > "$TMP/stubs/step-close.sh" <<'STEPCLOSE'
#!/usr/bin/env bash
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
# self-review is not in the polecat's chain-close list — the orchestrator closes
# the ralph control on convergence — so a blocker of self-review counts as closed
# when it is recorded in FAKE_ENGINE_CLOSED, which stands in for that engine close.
if [ -n "$blocker" ] \
  && ! grep -qx "mol-polecat-work.$blocker" "$FAKE_CLOSED" \
  && ! grep -qx "mol-polecat-work.$blocker" "${FAKE_ENGINE_CLOSED:-/dev/null}"; then
  echo "  ${step}: updating issue: cannot close blocked issue: blocked by [$blocker]" >&2
  exit 2
fi
printf '%s\n' "$step" >> "$FAKE_CLOSED"
[ -n "${FAKE_LOG:-}" ] && printf 'CLOSE|%s\n' "$step" >> "$FAKE_LOG"
exit 0
STEPCLOSE
chmod +x "$TMP/stubs/"*.sh
export GC_MOLECULE_HOLD_TOOL="$TMP/stubs/molecule-hold.sh" GC_ESCALATE_TOOL="$TMP/stubs/escalate.sh"
export GC_STEP_CLOSE_TOOL="$TMP/stubs/step-close.sh" GC_BRING_CURRENT_GUARD_TOOL="$TMP/stubs/bring-current-guard.sh"
export FAKE_HOLD="$TMP/hold" FAKE_HOLD_RC=0 FAKE_ESCALATE="$TMP/escalate" FAKE_ESC_RC=0
export FAKE_CLOSED="$TMP/closed" FAKE_ATTEMPTED="$TMP/attempted" FAKE_ENGINE_CLOSED="$TMP/engine-closed"
export FAKE_PUSH_STATE="$TMP/pushed" FAKE_LOG="$TMP/log"
: > "$TMP/hold"; : > "$TMP/escalate"; : > "$TMP/closed"; : > "$TMP/attempted"

# The orchestrator closes the self-review ralph control on convergence, before
# submit-and-exit's session runs its chain-close, so self-review is not in the
# loop's list. This file stands in for that engine close: it satisfies the
# submit-and-exit blocker the fake enforces, without the loop having closed it.
printf 'mol-polecat-work.self-review\n' > "$TMP/engine-closed"

# reset — a fresh scenario: empty log, no push landed, nothing closed.
reset() { : > "$TMP/log"; : > "$TMP/hold"; : > "$TMP/escalate"; : > "$TMP/closed"; : > "$TMP/attempted"; rm -f "$TMP/pushed"; }
# trace — the sequence of things a run DID, one token per event.
trace() { sed 's/|.*//' "$TMP/log" | tr '\n' ',' | sed 's/,$//'; }
log1() { tr '\n' ';' < "$TMP/log"; }

NOTE="Implemented: <brief summary>"
REFINERY_OK="gc-toolkit.refinery"

# run_gate <current-branch> <metadata-json>
#   -> prints "<rc>|<log>"; the log is the recorded gc writes, newline-joined
#      into one field so a single `eq` can assert both the outcome and the
#      side effects.
run_gate() {
  reset
  local rc=0
  FAKE_BRANCH="$1" FAKE_META="$2" "$SUT" branch-gate --bead tk-work --base main --step-bead st-submit > "$TMP/out" 2>&1 || rc=$?
  printf '%s|%s' "$rc" "$(log1)"
}

# run_resolve <current-branch> <base-branch> <metadata-json>
#   -> prints "<rc>|<LANDING_TARGET or empty>"
run_resolve() {
  reset
  local rc=0
  FAKE_BRANCH="$1" FAKE_META="$3" "$SUT" target --bead tk-work --base "$2" --step-bead st-submit > "$TMP/out" 2>&1 || rc=$?
  printf '%s|%s' "$rc" "$(sed -n 's/^landing target: //p' "$TMP/out")"
}

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
   "1|ESCALATE;HOLD;DRAIN;" \
   "fresh + wrong branch: escalates, halts, drain-acks, records no branch"

# Rework child: metadata.branch names the reviewed branch and the polecat is
# standing on it. The invariant is satisfied, so it must pass — and
# metadata.branch already agrees, so nothing is rewritten.
eq "$(run_gate polecat/su-uzy9.5 '{"branch":"polecat/su-uzy9.5"}')" \
   "0|" \
   "rework: accepts CURRENT_BRANCH == metadata.branch and rewrites nothing"

# The rework harm the gate still has to catch: a polecat that cut
# polecat/<bead-id> from the reviewed branch instead of resuming it. That forks
# the branch under review, so it must halt even though the name looks correct.
eq "$(run_gate polecat/tk-work '{"branch":"polecat/su-uzy9.5"}')" \
   "1|ESCALATE;HOLD;DRAIN;" \
   "rework: halts on a forked polecat/<bead-id> branch, not just any mismatch"

# An empty branch name must never be treated as a match.
eq "$(run_gate '' '{"branch":"polecat/su-uzy9.5"}')" \
   "1|ESCALATE;HOLD;DRAIN;" \
   "detached HEAD with metadata.branch set: halts"
eq "$(run_gate '' '{}')" \
   "1|ESCALATE;HOLD;DRAIN;" \
   "detached HEAD with no metadata.branch: halts"

# An empty-STRING metadata.branch is the absent case, not a branch named "".
eq "$(run_gate polecat/tk-work '{"branch":""}')" \
   "0|UPDATE|tk-work --set-metadata branch=polecat/tk-work;" \
   "empty-string metadata.branch falls back to the convention"

# --- 2. Target resolution. ----------------------------------------------------

# Rework child: the base is the reviewed branch by design, metadata.target is
# the real landing branch. Writing target=<base> would be a self-merge.
eq "$(run_resolve polecat/su-uzy9.5 polecat/su-uzy9.5 '{"target":"main"}')" \
   "0|main" \
   "rework: preserves metadata.target=main, never writes the self-merge"

eq "$(run_resolve polecat/tk-work main '{}')" \
   "0|main" \
   "fresh: falls back to the base when no target was set"

eq "$(run_resolve polecat/tk-work integration/tk-c1 '{"target":"integration/tk-c1"}')" \
   "0|integration/tk-c1" \
   "owned convoy: preserves an integration-branch target"

eq "$(run_resolve polecat/tk-work polecat/su-uzy9.5 '{"target":"integration/tk-c1"}')" \
   "0|integration/tk-c1" \
   "caller-set target wins over the base"

# Nothing named a target and the only candidate is the branch being pushed.
eq "$(run_resolve polecat/su-uzy9.5 polecat/su-uzy9.5 '{}')" \
   "1|" \
   "no target + base == current branch: fails closed instead of self-merging"

eq "$(run_resolve polecat/tk-work '' '{}')" \
   "1|" \
   "no target + empty base: fails closed"

eq "$(run_resolve polecat/tk-work main '{"target":""}')" \
   "0|main" \
   "empty-string metadata.target falls back to the base"

# --- 3. The refinery handoff (three writes). ----------------------------------
# ROSTER_OK is the shape `gc agent list --json` returns: every agent carries a
# rig-qualified name, and the roster check also accepts the binding-qualified
# tail so a session outside a rig still resolves. Neither form ever yields bare
# `refinery`, which is what makes the empty-prefix address detectable at all.
ROSTER_OK='[{"qualified_name":"gc-toolkit/gc-toolkit.refinery"},{"qualified_name":"myrig/gc-toolkit.refinery"},{"qualified_name":"gc-toolkit/gc-toolkit.polecat"}]'

# run_consume <landing-target> [refinery-address] [agents-json|UNREADABLE] [extra args...]
run_consume() {
  reset
  local target="$1" refinery="${2-$REFINERY_OK}" agents="${3-$ROSTER_OK}"
  shift; [ $# -gt 0 ] && shift; [ $# -gt 0 ] && shift
  local rc=0
  FAKE_AGENTS="$agents" "$SUT" consume --bead tk-work --target "$target" --refinery "$refinery" \
    --note "$NOTE" --step-bead st-submit "$@" > "$TMP/out" 2>&1 || rc=$?
  printf '%s|%s' "$rc" "$(log1)"
}
HANDOFF_META="UPDATE|tk-work --set-metadata target=main --set-metadata gc.routed_to= --unset-metadata gc.session_id --unset-metadata gc.session_name"
HANDOFF3="$HANDOFF_META --append-notes $NOTE;UPDATE|tk-work --status=open;UPDATE|tk-work --assignee=gc-toolkit.refinery;"

eq "$(run_consume main)" "0|$HANDOFF3" \
   "three writes: metadata+notes (route cleared), then status=open, then refinery assignee"

# CONTROL: a single gc bd update that reassigns the bead to the refinery while
# it is in_progress. bd's claim guard refuses it and rolls the whole call back;
# the fake enforces exactly that, so the one-shot records nothing and exits
# non-zero. This is what makes the split load-bearing.
reset
ONESHOT_RC=0
gc bd update tk-work --status=open --assignee=gc-toolkit.refinery --set-metadata target=main --set-metadata gc.routed_to="" --append-notes "Implemented: x" >/dev/null 2>&1 || ONESHOT_RC=$?
eq "$ONESHOT_RC|$(log1)" "1|" \
   "control: a one-shot handoff is REFUSED by the claim guard and records nothing"

eq "$(run_consume integration/tk-c1)" \
   "0|UPDATE|tk-work --set-metadata target=integration/tk-c1 --set-metadata gc.routed_to= --unset-metadata gc.session_id --unset-metadata gc.session_name --append-notes $NOTE;UPDATE|tk-work --status=open;UPDATE|tk-work --assignee=gc-toolkit.refinery;" \
   "carries an integration-branch target through to the bead"

eq "$(run_consume main myrig/gc-toolkit.refinery)" \
   "0|$HANDOFF_META --append-notes $NOTE;UPDATE|tk-work --status=open;UPDATE|tk-work --assignee=myrig/gc-toolkit.refinery;" \
   "rig sessions hand off to the rig-qualified refinery address"

# A run that skipped the target stage must not write target="". An empty
# metadata value round-trips as set-but-empty, which is its own strand.
eq "$(run_consume '')" "1|ESCALATE;HOLD;DRAIN;" \
   "unset target: escalates, holds, then halts instead of writing an empty target"
has_hold() { grep -q -- "$1" "$TMP/hold"; }
has_hold "LANDING_TARGET unset" \
  && ok "the handoff guard's hold names why it held" \
  || bad "handoff guard hold has no reason: $(cat "$TMP/hold")"

# The handoff itself fails closed. The three writes are chained; if one is
# refused even after --status=open — forced here with FAKE_FORCE_GUARD — the
# run must NOT close its chain and drain past the strand.
reset
REFUSED_RC=0
FAKE_AGENTS="$ROSTER_OK" FAKE_FORCE_GUARD=1 "$SUT" consume --bead tk-work --target main --refinery "$REFINERY_OK" \
  --note "$NOTE" --step-bead st-submit > "$TMP/out" 2>&1 || REFUSED_RC=$?
eq "$REFUSED_RC|$(log1)" \
   "1|$HANDOFF_META --append-notes $NOTE;UPDATE|tk-work --status=open;ESCALATE;HOLD;DRAIN;" \
   "a refused handoff write escalates, holds, then drains — never closes the chain"
has_hold "refinery handoff refused" \
  && ok "the handoff-refusal hold names why it held" \
  || bad "handoff-refusal hold has no reason: $(cat "$TMP/hold")"
has_hold "--step mol-polecat-work.submit-and-exit" \
  && ok "the handoff-refusal holds its own step" \
  || bad "handoff-refusal did not hold submit-and-exit: $(cat "$TMP/hold")"
has_hold "--bead st-submit" \
  && ok "the hold carries the claimed step bead as its hint" \
  || bad "the hold lost the claimed step bead: $(cat "$TMP/hold")"

# --- 3b. Fail-closed arms HOLD before they drain. -----------------------------
run_gate polecat/tk-work '{"branch":"polecat/su-uzy9.5"}' >/dev/null
has_hold "--step mol-polecat-work.submit-and-exit" \
  && ok "branch-shape refusal holds its own step" \
  || bad "branch-shape refusal drained without holding: $(cat "$TMP/hold")"
has_hold "branch shape gate" \
  && ok "and the hold carries the reason a human releases it on" \
  || bad "branch-shape hold has no reason: $(cat "$TMP/hold")"

run_resolve polecat/su-uzy9.5 polecat/su-uzy9.5 '{}' >/dev/null
has_hold "--step mol-polecat-work.submit-and-exit" \
  && ok "target-resolution refusal holds its own step" \
  || bad "target-resolution refusal drained without holding: $(cat "$TMP/hold")"
has_hold "no landing branch" \
  && ok "and names what must be set to release it" \
  || bad "target-resolution hold has no reason: $(cat "$TMP/hold")"
eq "$(log1)" "ESCALATE;HOLD;DRAIN;" \
   "and escalates, then holds, before it drains"

# An empty binding prefix renders `gc-toolkit/refinery`. The refinery's
# find-work is exact-match on assignee, so a bead written there is never read.
# The halt comes BEFORE the write, so the log carries DRAIN and no UPDATE.
eq "$(run_consume main gc-toolkit/refinery)" "1|DRAIN;" \
   "empty binding prefix: halts on an address no agent holds, writing nothing"
eq "$(run_consume main gc-toolkit/typo.refinery)" "1|DRAIN;" \
   "unbound binding prefix: halts on an address no agent holds, writing nothing"

# A roster the check could not read proves nothing about the address, and
# failing closed there would stall handoffs that are almost always correct. A
# call that fails and a roster that is genuinely empty both write.
eq "$(run_consume main myrig/gc-toolkit.refinery UNREADABLE)" \
   "0|$HANDOFF_META --append-notes $NOTE;UPDATE|tk-work --status=open;UPDATE|tk-work --assignee=myrig/gc-toolkit.refinery;" \
   "unreadable roster: hands off rather than stalling on what it cannot check"
eq "$(run_consume main myrig/gc-toolkit.refinery '[]')" \
   "0|$HANDOFF_META --append-notes $NOTE;UPDATE|tk-work --status=open;UPDATE|tk-work --assignee=myrig/gc-toolkit.refinery;" \
   "empty roster: hands off rather than stalling on what it cannot check"

# --- 3c. The PR summary the handoff carries. ----------------------------------
# A handed-off summary file is removed, so each case writes its fixture afresh.
summaries() {
  printf 'Compares heads instead of names.' > "$TMP/summary.txt"
  printf 'Line one.\nLine two.' > "$TMP/summary-multiline.txt"
  : > "$TMP/summary-empty.txt"
}
summaries
eq "$(run_consume main "$REFINERY_OK" "$ROSTER_OK" --summary-file "$TMP/summary.txt")" \
   "0|$HANDOFF_META --set-metadata pr_summary=Compares heads instead of names. --append-notes $NOTE;UPDATE|tk-work --status=open;UPDATE|tk-work --assignee=gc-toolkit.refinery;" \
   "a carried summary rides the metadata write as pr_summary"
[ -e "$TMP/summary.txt" ] \
  && bad "a handed-off summary file is removed" \
  || ok "a handed-off summary file is removed"

# The fake logs argv verbatim, so an embedded newline shows up as a second
# logged line — the proof that the value reaches gc unmangled.
summaries
eq "$(run_consume main "$REFINERY_OK" "$ROSTER_OK" --summary-file "$TMP/summary-multiline.txt")" \
   "0|$HANDOFF_META --set-metadata pr_summary=Line one.;Line two. --append-notes $NOTE;UPDATE|tk-work --status=open;UPDATE|tk-work --assignee=gc-toolkit.refinery;" \
   "a multi-line summary reaches the write whole"

# Both no-summary shapes fall back to the unsummarized handoff byte-identically.
summaries
eq "$(run_consume main "$REFINERY_OK" "$ROSTER_OK" --summary-file "$TMP/summary-empty.txt")" "0|$HANDOFF3" \
   "an empty summary file writes no pr_summary key at all"
eq "$(run_consume main "$REFINERY_OK" "$ROSTER_OK" --summary-file "$TMP/summary-absent.txt")" "0|$HANDOFF3" \
   "a summary file that is gone hands off unsummarized rather than halting"

# Under errexit and pipefail the roster check's reads are traps: `... | grep -q`
# returns 141 when grep matches and exits before the writer finishes, and the
# roster pipeline returns non-zero whenever `gc` fails. Run the stage strict.
run_strict_consume() { # <refinery-address> <agents-json|UNREADABLE>
  reset
  local rc=0
  FAKE_AGENTS="$2" bash -euo pipefail "$SUT" consume --bead tk-work --target main --refinery "$1" \
    --note "$NOTE" --step-bead st-submit > "$TMP/out" 2>&1 || rc=$?
  printf '%s|%s' "$rc" "$(log1)"
}
# A roster larger than the 64K pipe buffer, with the match up front, makes a
# `grep -q` reader exit while the writer is still blocked. The JSON reaches the
# fake through the environment and must stay under the per-variable execve cap.
ROSTER_BIG="$(jq -cn '[{qualified_name:"gc-toolkit/gc-toolkit.refinery"}]
  + [range(1200) | {qualified_name:("filler-rig-\(.)/gc-toolkit.polecat-padding-entry")}]')"
eq "$(run_strict_consume gc-toolkit/gc-toolkit.refinery "$ROSTER_BIG")" \
   "0|$HANDOFF_META --append-notes $NOTE;UPDATE|tk-work --status=open;UPDATE|tk-work --assignee=gc-toolkit/gc-toolkit.refinery;" \
   "strict shell: a matching address in an oversized roster still writes"
eq "$(run_strict_consume gc-toolkit/gc-toolkit.refinery UNREADABLE)" \
   "0|$HANDOFF_META --append-notes $NOTE;UPDATE|tk-work --status=open;UPDATE|tk-work --assignee=gc-toolkit/gc-toolkit.refinery;" \
   "strict shell: a failed roster call still reaches the permissive arm"
eq "$(run_strict_consume gc-toolkit/gc-toolkit.refinery '[{"qualified_name":"gc-toolkit/gc-toolkit.polecat"}]')" \
   "1|DRAIN;" \
   "strict shell: a roster without the address still halts, and the diagnostic does not die on an empty grep"

# --- 3d. The anchor the summary belongs on. -----------------------------------
# run_anchor_resolve <current-branch> <bd-list-rows-json> -> "<rc>|<anchor>"
#   Rows are the shape real `gc bd list --json` returns, and the stage runs
#   strict: an unreadable probe must degrade, not kill the run.
run_anchor_resolve() {
  reset
  local rc=0
  FAKE_BRANCH="$1" FAKE_ANCHOR_ROWS="$2" bash -euo pipefail "$SUT" anchor --bead tk-work > "$TMP/out" 2>&1 || rc=$?
  printf '%s|%s' "$rc" "$(sed -n 's/^gating anchor: \([^ ]*\) (this bead is a child.*/\1/p' "$TMP/out")"
}
ANCHOR_ROW='[{"id":"tk-anchor","created_at":"2026-07-01T00:00:00Z","metadata":{"merge_result":"pull_request","branch":"polecat/su-uzy9.5"}}]'

eq "$(run_anchor_resolve polecat/tk-work '[]')" "0|" \
   "fresh: no other bead on the branch -> no anchor, the claimed bead is it"
eq "$(run_anchor_resolve polecat/su-uzy9.5 "$ANCHOR_ROW")" "0|tk-anchor" \
   "rework child: the open merge_result-carrying bead on the branch is the anchor"
eq "$(run_anchor_resolve polecat/tk-work \
      '[{"id":"tk-work","created_at":"2026-07-01T00:00:00Z","metadata":{"merge_result":"pull_request","branch":"polecat/tk-work"}}]')" \
   "0|" \
   "the claimed bead's own row is excluded from its anchor lookup"
eq "$(run_anchor_resolve polecat/su-uzy9.5 \
      '[{"id":"tk-sibling","created_at":"2026-07-01T00:00:00Z","metadata":{"branch":"polecat/su-uzy9.5"}}]')" \
   "0|" \
   "a sibling carrying no merge_result is not an anchor"
eq "$(run_anchor_resolve polecat/su-uzy9.5 \
      '[{"id":"tk-anchor","created_at":"2026-07-01T00:00:00Z","metadata":{"merge_result":"blocked","branch":"polecat/su-uzy9.5"}}]')" \
   "0|tk-anchor" \
   "an anchor parked in a human state is still the summary's destination"
eq "$(run_anchor_resolve polecat/su-uzy9.5 \
      '[{"id":"tk-aaaa1","created_at":"2026-07-15T00:00:00Z","metadata":{"merge_result":"pull_request","branch":"polecat/su-uzy9.5"}},{"id":"tk-zzzz9","created_at":"2026-07-01T00:00:00Z","metadata":{"merge_result":"pull_request","branch":"polecat/su-uzy9.5"}}]')" \
   "0|tk-zzzz9" \
   "two candidates -> oldest on created_at, matching merge-push's tiebreak"
eq "$(run_anchor_resolve '' "$ANCHOR_ROW")" "0|" \
   "detached HEAD: no lookup rather than matching branchless beads"
eq "$(run_anchor_resolve polecat/su-uzy9.5 'not json at all')" "0|" \
   "an unparseable probe resolves to no anchor instead of killing the run"

reset
FAKE_BRANCH=polecat/su-uzy9.5 FAKE_ANCHOR_ROWS="$ANCHOR_ROW" FAKE_SHOW_TITLE="Compare heads" \
  "$SUT" anchor --bead tk-work > "$TMP/out" 2>&1 || true
has "$(cat "$TMP/out")" "anchor title: Compare heads" "anchor prints the title the PR is composed from"

# --- 3e. The summary follows the anchor. --------------------------------------
summaries
eq "$(run_consume main "$REFINERY_OK" "$ROSTER_OK" --summary-file "$TMP/summary-multiline.txt" --anchor tk-anchor)" \
   "0|UPDATE|tk-anchor --set-metadata pr_summary=Line one.;Line two.;$HANDOFF3" \
   "child: the summary is stamped on the anchor, ahead of the three handoff writes"
summaries
eq "$(run_consume main "$REFINERY_OK" "$ROSTER_OK" --summary-file "$TMP/summary.txt" --anchor tk-anchor | tr ';' '\n' | sed -n '1p')" \
   "0|UPDATE|tk-anchor --set-metadata pr_summary=Compares heads instead of names." \
   "the anchor stamp is written before the handoff, not after it"
eq "$(run_consume main "$REFINERY_OK" "$ROSTER_OK" --summary-file "$TMP/summary-empty.txt" --anchor tk-anchor)" "0|$HANDOFF3" \
   "no summary: the anchor is not touched"

# --- 3f. A retitle follows the anchor. ----------------------------------------
eq "$(run_consume main "$REFINERY_OK" "$ROSTER_OK" --title 'Compare heads, not names' --anchor tk-anchor)" \
   "0|UPDATE|tk-anchor --title Compare heads, not names;$HANDOFF3" \
   "child: the retitle is written to the anchor, ahead of the three handoff writes"
eq "$(run_consume main "$REFINERY_OK" "$ROSTER_OK" --title 'Compare heads, not names')" \
   "0|UPDATE|tk-work --title Compare heads, not names;$HANDOFF3" \
   "fresh work: the claimed bead is the anchor, retitled in a write of its own ahead of the handoff"
eq "$(run_consume main "$REFINERY_OK" "$ROSTER_OK" --title '   ' --anchor tk-anchor)" "0|$HANDOFF3" \
   "a whitespace-only title is no retitle"
eq "$(FAKE_TITLE_REFUSE=1 run_consume main "$REFINERY_OK" "$ROSTER_OK" --title 'Compare heads, not names' --anchor tk-anchor)" "0|$HANDOFF3" \
   "a refused retitle costs the title, and the handoff still lands whole"

# A hold that did not land must not drain, and an escalation that did not land
# must neither hold nor drain.
FAKE_HOLD_RC=1
eq "$(run_gate polecat/tk-agent-home '{}')" "1|ESCALATE;HOLD;" \
   "branch-shape refusal: a refused hold halts WITHOUT draining"
run_resolve polecat/su-uzy9.5 polecat/su-uzy9.5 '{}' >/dev/null
eq "$(log1)" "ESCALATE;HOLD;" "target resolution: a refused hold halts WITHOUT draining"
eq "$(run_consume '')" "1|ESCALATE;HOLD;" "the handoff guard: a refused hold halts WITHOUT draining"
FAKE_HOLD_RC=0
FAKE_ESC_RC=1
eq "$(run_gate polecat/tk-agent-home '{}')" "1|ESCALATE;" \
   "branch-shape refusal: a refused escalation neither holds nor drains"
eq "$(run_consume '')" "1|ESCALATE;" "the handoff guard: a refused escalation neither holds nor drains"
FAKE_ESC_RC=0

# --- 4. The push and the bring-current guard. ---------------------------------
# run_push [env assignments...] -> "<rc>|<trace>"
run_push() {
  reset; : > "$TMP/guard-argv"
  local rc=0
  env FAKE_BRANCH=polecat/tk-work FAKE_GUARD_ARGV="$TMP/guard-argv" "$@" \
    "$SUT" push --bead tk-work > "$TMP/out" 2>&1 || rc=$?
  printf '%s|%s' "$rc" "$(trace)"
}
eq "$(run_push FAKE_PUSHED="sha-pre	refs/heads/polecat/tk-work")" "0|GIT,GUARD" \
   "a verified push runs the guard, and a guard that finishes lets the handoff proceed"
eq "$(cat "$TMP/guard-argv")" "guard --bead tk-work --to sha-local --from sha-pre" \
   "the guard runs on the claimed bead with the pushed head and the origin head from before the push"
eq "$(run_push)" "0|GIT,GUARD" "a first push (nothing on origin) still runs the guard"
eq "$(cat "$TMP/guard-argv")" "guard --bead tk-work --to sha-local --from " \
   "an unread origin head passes the empty start through rather than dropping the flag"
eq "$(run_push FAKE_GUARD_RC=1)" "1|GIT,GUARD,DRAIN" "a guard that cannot finish drains before any handoff write"
has "$(cat "$TMP/out")" "BRING-CURRENT GUARD DID NOT FINISH" "and says the bead is not handed off"
eq "$(run_push FAKE_PUSH_RC=1)" "1|GIT,DRAIN" "a refused push drains and never reaches the guard"
has "$(cat "$TMP/out")" "never force-push" "and says to merge, never force-push"
eq "$(run_push FAKE_PUSH_LOST=1)" "1|GIT,DRAIN" "a push origin does not hold fails verification before the guard"
has "$(cat "$TMP/out")" "PUSH VERIFICATION FAILED" "and names the failed verification"

# --- 5. Step-chain close. -----------------------------------------------------
# run_close [refused-step] [env assignments...] -> "<rc>|<steps CLOSED, in order>"
run_close() {
  reset
  local refuse="${1-}"; [ $# -gt 0 ] && shift
  local rc=0
  env FAKE_REFUSE="$refuse" "$@" bash -e "$SUT" chain-close --bead tk-work > "$TMP/out" 2>&1 || rc=$?
  printf '%s|%s' "$rc" "$(sed 's/^mol-polecat-work\.//' "$TMP/closed" | tr '\n' ',' | sed 's/,$//')"
}
attempted() { sed 's/^mol-polecat-work\.//' "$TMP/attempted" | tr '\n' ',' | sed 's/,$//'; }

# The five steps this session owns and closes forward. self-review is absent by
# design: it is the ralph control the orchestrator closes on convergence.
LOOP_STEPS="load-context,workspace-setup,preflight-tests,implement,submit-and-exit"

eq "$(run_close)" "0|$LOOP_STEPS" \
   "closes the five session-owned steps, forward order, load-context first"
eq "$(run_close | sed 's/.*,//')" "submit-and-exit" \
   "submit-and-exit closes last, arming the control-dispatcher backstop"
case ",$(run_close)," in
  *workflow-finalize*) bad "chain close must never close workflow-finalize" ;;
  *)                   ok  "leaves workflow-finalize to the control-dispatcher" ;;
esac
eq "$(run_close >/dev/null; sed -n '/^UPDATE|/p' "$TMP/log" | tr '\n' ';')" "" \
   "writes nothing to any bead (the work bead stays the refinery's)"

# A refusal must not abort the loop, even under errexit.
REFUSED_FIRST="$(run_close mol-polecat-work.load-context)"
eq "$REFUSED_FIRST|$(attempted)" "0|submit-and-exit|$LOOP_STEPS" \
   "a refused load-context blocks its inline successors, but submit-and-exit still closes; all five attempted"
REFUSED_MID="$(run_close mol-polecat-work.implement)"
eq "$REFUSED_MID|$(attempted)" \
   "0|load-context,workspace-setup,preflight-tests,submit-and-exit|$LOOP_STEPS" \
   "a refused implement skips only itself; submit-and-exit closes via the engine's self-review; loop continues"

# No step-close.sh must fail loudly rather than drain with the chain open.
eq "$(run_close '' GC_STEP_CLOSE_TOOL="$TMP/nonexistent")" "1|" \
   "missing step-close.sh: fails loudly, closes nothing"

# CONTROL: the same closes dependent-first. Against bd's real rule they close
# only the two unblocked ends, which is why the order is forward.
reset
for step in submit-and-exit implement preflight-tests workspace-setup load-context; do
  "$TMP/stubs/step-close.sh" --step "mol-polecat-work.$step" --outcome pass >/dev/null 2>&1 || true
done
eq "$(sed 's/^mol-polecat-work\.//' "$TMP/closed" | tr '\n' ',' | sed 's/,$//')" \
   "submit-and-exit,load-context" \
   "control: dependent-first closes only the two unblocked ends; the middle stays blocked"

# --- 6. The auto_push=false halt exit. ----------------------------------------
# run_halt [env assignments...] -> "<rc>"; the ordered trace is left in $TMP/log.
run_halt() {
  reset
  local rc=0
  env FAKE_BRANCH=polecat/tk-work FAKE_META='{"auto_push":false}' "$@" \
    "$SUT" auto-push-halt --bead tk-work --target main --step-bead st-submit > "$TMP/out" 2>&1 || rc=$?
  printf '%s' "$rc"
}
eq "$(run_halt)" "0" "halt arm exits 0"
eq "$(trace)" "UPDATE,UPDATE,UPDATE,CLOSE,CLOSE,CLOSE,CLOSE,CLOSE,DRAIN" \
   "halt arm parks the bead in three writes, closes five steps, THEN drains"
eq "$(sed -n 's/^CLOSE|mol-polecat-work\.//p' "$TMP/log" | tr '\n' ',' | sed 's/,$//')" "$LOOP_STEPS" \
   "halt arm closes the same five steps, forward order"
HALT_FIRST="$(sed -n 's/^UPDATE|//p' "$TMP/log" | sed -n 1p)"
eq "$HALT_FIRST" \
   "tk-work --set-metadata branch=polecat/tk-work --set-metadata target=main --set-metadata branch_ready=true --set-metadata halt_reason=auto_push_false --set-metadata gc.routed_to= --unset-metadata gc.session_id --unset-metadata gc.session_name --append-notes Branch ready: auto_push=false (no push, no refinery handoff)" \
   "halt arm first write: branch + target + branch_ready + halt_reason + cleared route + session pins removed, --append-notes"
eq "$(sed -n 's/^UPDATE|//p' "$TMP/log" | sed -n 2p)" "tk-work --status=open" \
   "halt arm second write: --status=open alone, while the bead is still assigned"
eq "$(sed -n 's/^UPDATE|//p' "$TMP/log" | sed -n 3p)" "tk-work --assignee=" \
   "halt arm third write: --assignee cleared, after the status is open"
eq "$(run_halt FAKE_META='{}'; trace)" "0" "a bead that does not opt out passes the halt arm untouched"
eq "$(run_halt GC_STEP_CLOSE_TOOL="$TMP/nonexistent"; printf '|%s' "$(trace)")" "1|UPDATE,UPDATE,UPDATE" \
   "a halt with no step-close.sh stops before the drain, the chain left visibly open"

reset
HALT_UNSET_RC=0
FAKE_BRANCH=polecat/tk-work FAKE_META='{"auto_push":false}' \
  "$SUT" auto-push-halt --bead tk-work --step-bead st-submit > "$TMP/out" 2>&1 || HALT_UNSET_RC=$?
eq "$HALT_UNSET_RC|$(log1)" "1|ESCALATE;HOLD;DRAIN;" \
   "a halt reached with no landing target escalates and holds rather than recording an empty target"

# --- 6b. The store-only exit. -------------------------------------------------
# run_store [env assignments...] -> "<rc>"; trace left in $TMP/log.
STORE_NOTE="<what closes this bead, or the bead-rehome.sh invocation that disposes of it>"
run_store() {
  reset
  local rc=0
  env FAKE_BRANCH=main "$@" "$SUT" store-only --bead tk-work --base main --record "tk-filed,gc-filed" \
    --note "$STORE_NOTE" > "$TMP/out" 2>&1 || rc=$?
  printf '%s' "$rc"
}
eq "$(run_store)" "0" "store-only arm exits 0"
eq "$(trace)" "UPDATE,UPDATE,UPDATE,CLOSE,CLOSE,CLOSE,CLOSE,CLOSE,DRAIN" \
   "store-only arm releases in three writes, closes five steps, THEN drains"
eq "$(sed -n 's/^CLOSE|mol-polecat-work\.//p' "$TMP/log" | tr '\n' ',' | sed 's/,$//')" "$LOOP_STEPS" \
   "store-only arm closes the same five steps, forward order"
STORE_FIRST="$(sed -n 's/^UPDATE|//p' "$TMP/log" | sed -n 1p)"
eq "$STORE_FIRST" \
   "tk-work --set-metadata halt_reason=store_only --set-metadata gc.routed_to= --unset-metadata gc.session_id --unset-metadata gc.session_name --append-notes Store-only exit: filed tk-filed,gc-filed. $STORE_NOTE" \
   "first write: halt_reason + cleared route + session pins removed + the filed record, --append-notes not --notes"
eq "$(sed -n 's/^UPDATE|//p' "$TMP/log" | sed -n 2p)" "tk-work --status=open" \
   "second write: --status=open alone, while the bead is still assigned"
eq "$(sed -n 's/^UPDATE|//p' "$TMP/log" | sed -n 3p)" "tk-work --assignee=" \
   "third write: --assignee alone, after the status is open"
case "$(cat "$TMP/log")" in
  *"GIT|push"*) bad "store-only arm pushed — it has nothing to push" ;;
  *)            ok  "store-only arm never reaches git push" ;;
esac

# Each of the three signals of work to land refuses before writing anything.
eq "$(run_store FAKE_AHEAD=2)|$(trace)" "1|DRAIN" "commits ahead of base: refuses, drains, writes nothing"
eq "$(run_store FAKE_DIRTY=' M formulas/mol-polecat-work.toml')|$(trace)" "1|DRAIN" \
   "uncommitted changes: refuses, drains, writes nothing"
eq "$(run_store FAKE_PUSHED='abc123	refs/heads/polecat/tk-work')|$(trace)" "1|DRAIN" \
   "branch already on origin: refuses, drains, writes nothing"

# The arm is opt-in by its arguments: no record, no release.
reset
NORECORD_RC=0
"$SUT" store-only --bead tk-work --base main --note "x" > "$TMP/out" 2>&1 || NORECORD_RC=$?
eq "$NORECORD_RC|$(log1)" "2|" "store-only without a --record refuses as usage and writes nothing"

# --- 6c. Session pins at every exit that lets go of the bead. ------------------
# The runtime's detached-handoff orphan sweep recovers a pool route from a pin
# left on a released bead, and the witness's orphan scan resolves an owner from
# it, so each exit removes the same pair in its first write and clears the route.
pins() { printf '%s\n' "$1" | grep -o -- '--unset-metadata gc\.session_[a-z]*' | sort -u | tr '\n' ' '; }
routes() { printf '%s\n' "$1" | grep -o -- '--set-metadata gc\.routed_to=[^ ]*' | sort -u; }
run_consume main >/dev/null
HANDOFF_FIRST="$(sed -n 's/^UPDATE|//p' "$TMP/log" | sed -n 1p)"
eq "$(pins "$HANDOFF_FIRST")" "--unset-metadata gc.session_id --unset-metadata gc.session_name " \
   "the refinery handoff removes both session pins"
eq "$(pins "$STORE_FIRST")" "$(pins "$HANDOFF_FIRST")" "the store-only exit removes the same pins"
eq "$(pins "$HALT_FIRST")" "$(pins "$HANDOFF_FIRST")" "the halt arm removes the same pins"
eq "$(routes "$STORE_FIRST")|$(routes "$HALT_FIRST")|$(routes "$HANDOFF_FIRST")" \
   "--set-metadata gc.routed_to=|--set-metadata gc.routed_to=|--set-metadata gc.routed_to=" \
   "every exit clears the route"

# --- 7. The whole handoff, in order. ------------------------------------------
# run_handoff [env assignments...] -> "<rc>"; trace left in $TMP/log.
run_handoff() {
  reset
  local rc=0
  env FAKE_BRANCH=polecat/su-uzy9.5 FAKE_AGENTS="$ROSTER_OK" "$@" \
    "$SUT" handoff --bead tk-work --base polecat/su-uzy9.5 --refinery "$REFINERY_OK" \
    --note "$NOTE" --step-bead st-submit --summary-file "$TMP/summary.txt" > "$TMP/out" 2>&1 || rc=$?
  printf '%s' "$rc"
}

# The rework shape the gate and resolver exist for: on the reviewed branch,
# metadata.target names main, and another open bead anchors the branch.
summaries
eq "$(run_handoff FAKE_META='{"branch":"polecat/su-uzy9.5","target":"main"}' FAKE_ANCHOR_ROWS="$ANCHOR_ROW")" "0" \
   "a rework handoff exits 0"
eq "$(sed -n 's/^landing target: //p' "$TMP/out")" "main" \
   "it resolves the landing target to main, not to the pushed branch"
eq "$(trace)" "GIT,GUARD,UPDATE,UPDATE,UPDATE,UPDATE,WAKE,NUDGE,CLOSE,CLOSE,CLOSE,CLOSE,CLOSE,GIT,GIT,DRAIN" \
   "push, guard, anchor summary, three handoff writes, wake, five closes, branch release, drain — in that order"
eq "$(sed -n 's/^UPDATE|//p' "$TMP/log" | tr '\n' ';')" \
   "tk-anchor --set-metadata pr_summary=Compares heads instead of names.;tk-work --set-metadata target=main --set-metadata gc.routed_to= --unset-metadata gc.session_id --unset-metadata gc.session_name --append-notes $NOTE;tk-work --status=open;tk-work --assignee=gc-toolkit.refinery;" \
   "the summary goes to the anchor and the handoff to the claimed bead; metadata.branch already agreed, so nothing rewrites it"
eq "$(sed -n 's/^GIT|//p' "$TMP/log" | tr '\n' ';')" \
   "push HEAD;checkout --detach;branch -D polecat/su-uzy9.5;" \
   "the branch is released only after the handoff and the chain close"

# An opt-out halts before the push: no push, no guard, no handoff.
eq "$(run_handoff FAKE_META='{"branch":"polecat/su-uzy9.5","target":"main","auto_push":false}')" "0" \
   "an auto_push=false handoff exits 0 at the halt"
case "$(cat "$TMP/log")" in
  *"GIT|push"*|*GUARD*) bad "the auto_push=false halt reached the push or the guard" ;;
  *)                    ok  "the auto_push=false halt never reaches the push or the guard" ;;
esac

# A refused gate stops the run before anything is pushed.
eq "$(run_handoff FAKE_META='{"branch":"polecat/other"}')|$(trace)" "1|ESCALATE,HOLD,DRAIN" \
   "a refused branch gate stops the handoff before the push"

# A handoff whose roster check halts closes nothing and releases nothing.
eq "$(run_handoff FAKE_META='{"branch":"polecat/su-uzy9.5","target":"main"}' FAKE_AGENTS='[{"qualified_name":"x/y.polecat"}]')|$(trace)" \
   "1|GIT,GUARD,DRAIN" \
   "a halted handoff closes no step and keeps the branch"

# --- 8. The branch release. ---------------------------------------------------
# run_release <current-branch> [git-rc] -> "<rc>|<git calls>"
run_release() {
  reset
  local rc=0
  FAKE_BRANCH="$1" FAKE_GIT_RC="${2-0}" "$SUT" release --bead tk-work > "$TMP/out" 2>&1 || rc=$?
  printf '%s|%s' "$rc" "$(log1)"
}
eq "$(run_release polecat/tk-work)" \
   "0|GIT|checkout --detach;GIT|branch -D polecat/tk-work;" \
   "on a branch: detaches, then deletes the branch it was standing on"
eq "$(run_release '')" "0|" "already detached: releases nothing"
eq "$(run_release polecat/tk-work 1)" "0|GIT|checkout --detach;" \
   "a failed release still exits 0 (the handoff is already durable)"

# --- 9. Usage. ----------------------------------------------------------------
reset
USAGE_RC=0
"$SUT" handoff --bead tk-work --base main --note x > "$TMP/out" 2>&1 || USAGE_RC=$?
eq "$USAGE_RC|$(log1)" "2|" "handoff without --refinery refuses as usage and runs nothing"
USAGE_RC=0
"$SUT" bogus --bead tk-work > "$TMP/out" 2>&1 || USAGE_RC=$?
eq "$USAGE_RC" "2" "an unknown command refuses as usage"

# --- 10. Negative control. ----------------------------------------------------
# The fixtures above pass against the script. They prove nothing unless the
# same fixtures FAIL against the implementation being replaced. A templated gate
# and an unconditional target are reproduced literally here as the control.
BASE_RC=0
cat > "$TMP/base-gate.sh" <<'BASE'
EXPECTED_BRANCH="polecat/$WORK_BEAD_ID"
[ "$CURRENT_BRANCH" = "$EXPECTED_BRANCH" ] || exit 1
BASE
WORK_BEAD_ID=tk-work CURRENT_BRANCH=polecat/su-uzy9.5 bash "$TMP/base-gate.sh" || BASE_RC=$?
eq "$BASE_RC" "1" \
   "control: a templated gate REJECTS the rework branch (the defect is real)"
OURS_TARGET="$(run_resolve polecat/su-uzy9.5 polecat/su-uzy9.5 '{"target":"main"}')"
eq "polecat/su-uzy9.5|$OURS_TARGET" "polecat/su-uzy9.5|0|main" \
   "control: an unconditional target renders the pushed branch (self-merge); the resolver renders main"

echo
echo "submit-and-exit: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
