#!/usr/bin/env bash
# Hermetic test for assets/scripts/work-submit.sh, mol-polecat-work's
# submit-and-exit.
#
# It runs against a real git repository with a real bare origin, a gc stub over a
# JSON store that its reads serve and its writes change, and the real work-lib.sh,
# decline.sh, claim-close.sh, hand-back.sh and store-only-exit.sh. The guard, the
# gate, the wait and the cancel are stubs that record their calls. Everything goes
# into one log, in order, so a case can read what landed before what. No live
# city, Dolt, network, or PRs.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-work-submit-test.XXXXXX")"
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1${2:+ ($2)}"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3" "got '$1' want '$2'"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3" "'$2' not in '$1'" ;; esac; }
no()  { case "$1" in *"$2"*) bad "$3" "'$2' unexpectedly in '$1'" ;; *) ok "$3" ;; esac; }

command -v jq >/dev/null 2>&1 || { echo "jq is required for this test" >&2; exit 1; }
REAL_GIT="$(command -v git)" || { echo "git is required for this test" >&2; exit 1; }
unset "${!GC_@}" "${!BEADS_@}" 2>/dev/null || true

export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$TMP/gitconfig"
git config --file "$GIT_CONFIG_GLOBAL" user.name "tester"
git config --file "$GIT_CONFIG_GLOBAL" user.email "tester@example.com"
git config --file "$GIT_CONFIG_GLOBAL" commit.gpgsign false
git config --file "$GIT_CONFIG_GLOBAL" init.defaultBranch main
git config --file "$GIT_CONFIG_GLOBAL" advice.detachedHead false

PACK="$TMP/pack"; BIN="$TMP/bin"; mkdir -p "$PACK" "$BIN"
cp "$HERE/work-submit.sh" "$HERE/work-lib.sh" "$HERE/decline.sh" "$HERE/claim-close.sh" "$HERE/bd-lib.sh" \
   "$HERE/hand-back.sh" "$HERE/store-only-exit.sh" "$HERE/run-lib.sh" "$HERE/deferred-dispatch.sh" "$PACK/" 2>/dev/null
export REAL_GIT LOG="$TMP/log" STORE="$TMP/store.json"

# git: push and ls-remote can be made to fail, and a push is logged.
cat > "$BIN/git" <<'SH'
#!/usr/bin/env bash
case "${1:-}" in
  push)
    printf 'push %s\n' "$*" >> "$LOG"
    [ -z "${PUSH_FAIL:-}" ] || { echo "remote: refused (stub)" >&2; exit 1; } ;;
  ls-remote)
    [ -z "${LS_REMOTE_WRONG:-}" ] || { [ ! -e "$LS_REMOTE_WRONG" ] || { printf 'deadbeef\trefs/heads/x\n'; exit 0; }; : > "$LS_REMOTE_WRONG"; } ;;
  branch)
    case "${2:-}" in -D) printf 'release %s\n' "${3:-}" >> "$LOG" ;; esac ;;
esac
exec "$REAL_GIT" "$@"
SH
# gc over the store. A write whose arguments contain UPDATE_FAIL is refused. A list
# fails while LIST_DOWN is set, and a show while SHOW_DOWN is set.
cat > "$BIN/gc" <<'SH'
#!/usr/bin/env bash
case "${1:-} ${2:-}" in
  "runtime drain-ack") printf 'drain\n' >> "$LOG"; exit 0 ;;
  "hook current")
    [ -n "${HOOK_CURRENT:-}" ] || { echo "no claim" >&2; exit 1; }
    printf '%s\n' "$HOOK_CURRENT"; exit 0 ;;
  "convoy status") printf '{"children":[{"id":"tk-w"}]}\n'; exit 0 ;;
  "agent list")
    [ -z "${ROSTER_DOWN:-}" ] || exit 1
    printf '{"agents":[{"qualified_name":"%s"}]}\n' "${ROSTER:-gc-toolkit/gc-toolkit.refinery}"; exit 0 ;;
  "session wake"|"session nudge") printf '%s %s %s\n' "$1" "$2" "$3" >> "$LOG"; exit 0 ;;
  "session list") printf '{"sessions":[]}\n'; exit 0 ;;
esac
[ "${1:-}" = "bd" ] || { echo "gc stub: unsupported '$*'" >&2; exit 2; }
verb="${2:-}"; id="${3:-}"
case "$verb" in
  show)
    [ -z "${SHOW_DOWN:-}" ] || exit 1
    out=$(jq -c --arg id "$id" '[.[] | select(.id == $id)]' "$STORE")
    if [ "$out" = "[]" ]; then printf '{"error":"no issues found matching the provided IDs"}\n'; exit 1; fi
    printf '%s\n' "$out" ;;
  list)
    printf 'list %s\n' "$*" >> "$LOG"
    [ -z "${LIST_DOWN:-}" ] || exit 1
    field=""; shift 2
    while [ $# -gt 0 ]; do case "$1" in --metadata-field) field="$2"; shift 2 ;; *) shift ;; esac; done
    jq -c --arg b "${field#branch=}" '[.[] | select((.status // "") != "closed") | select((.metadata.branch // "") == $b)]' "$STORE" ;;
  dep)
    [ "${3:-}" = list ] && { printf '[]\n'; exit 0; } ;;
  update)
    all="$*"
    case " $all " in *"${UPDATE_FAIL:-@@never@@}"*) echo "bd: refused (stub)" >&2; exit 1 ;; esac
    printf 'update %s\n' "${all#bd update }" >> "$LOG"
    shift 3
    while [ $# -gt 0 ]; do
      case "$1" in
        --set-metadata)   k="${2%%=*}"; v="${2#*=}"; f='.metadata[$k] = $v'; shift 2 ;;
        --unset-metadata) k="$2"; v=""; f='.metadata |= del(.[$k])'; shift 2 ;;
        --status=*)       k="status"; v="${1#--status=}"; f='.status = $v'; shift ;;
        --assignee=*)     k="assignee"; v="${1#--assignee=}"; f='.assignee = $v'; shift ;;
        --append-notes)   k="notes"; v="$2"; f='.notes = ((.notes // "") + $v)'; shift 2 ;;
        --title)          k="title"; v="$2"; f='.title = $v'; shift 2 ;;
        *) shift; continue ;;
      esac
      jq -c --arg id "$id" --arg k "$k" --arg v "$v" "map(if .id == \$id then $f else . end)" "$STORE" > "$STORE.new" && mv "$STORE.new" "$STORE"
    done ;;
  *) echo "gc stub: unsupported 'bd $verb'" >&2; exit 2 ;;
esac
exit 0
SH
chmod +x "$BIN/git" "$BIN/gc"

recorder() { # <name> <log word> <rc var>
  cat > "$PACK/$1" <<STUB
#!/usr/bin/env bash
printf '$2 %s\n' "\$*" >> "\$LOG"
exit "\${$3:-0}"
STUB
  chmod +x "$PACK/$1"
}
recorder run-cancel.sh cancel CANCEL_RC
recorder human-gate.sh gate GATE_RC
recorder await-ruling.sh await AWAIT_RC
recorder bring-current-guard.sh guard GUARD_RC

# --- History: a bare origin whose main holds the base. ------------------------------
g() { "$REAL_GIT" -C "$@"; }
O="$TMP/origin.git"
"$REAL_GIT" init -q --bare "$O"
SEED="$TMP/seed"; "$REAL_GIT" clone -q "$O" "$SEED" 2>/dev/null
printf 'base\n' > "$SEED/base.txt"; g "$SEED" add base.txt; g "$SEED" commit -qm base; g "$SEED" push -q origin HEAD:main

STEP_ROW='{"id":"st-submit","status":"in_progress","assignee":"sess-me","metadata":{"gc.step_ref":"mol-polecat-work.submit-and-exit","gc.root_bead_id":"root-1"}}'

N=0
# prepare <branch> <work metadata json> [<extra store rows json array>] — a tree on
# <branch> with one commit past main, and a store holding the work bead and step.
prepare() {
  N=$((N + 1)); C="$TMP/tree-$N"; CO="$TMP/origin-$N.git"
  cp -R "$O" "$CO"
  "$REAL_GIT" clone -q "$CO" "$C" 2>/dev/null
  if [ "$1" = DETACHED ]; then
    g "$C" checkout -q --detach origin/main
  else
    g "$C" checkout -q -b "$1" origin/main
    printf 'work\n' > "$C/work.txt"; g "$C" add work.txt; g "$C" commit -qm work
  fi
  HEAD_SHA=$(g "$C" rev-parse HEAD)
  jq -nc --argjson m "$2" --argjson x "${3:-[]}" --argjson s "$STEP_ROW" --arg d "$C" \
    '[{id: "tk-w", title: "the work", status: "open", assignee: "", metadata: ({work_dir: $d} + $m)}, $s] + $x' > "$STORE"
  : > "$LOG"
}
# submit [<VAR=value>...] -- <args...> — the script as the step calls it, from a
# directory that is not the tree.
submit() {
  local envs=()
  while [ $# -gt 0 ] && [ "$1" != -- ]; do envs+=("$1"); shift; done
  shift
  OUT=$(cd "$TMP" && env PATH="$BIN:$PATH" WORK_READ_WAIT=0 GC_SESSION_ID=sess-me GC_RIG=gc-toolkit HOOK_CURRENT=st-submit \
    ${envs[@]+"${envs[@]}"} "$PACK/work-submit.sh" "$@" 2>&1); RC=$?
}
go() { submit "$@" -- --convoy cv-1 --base main --notes "Implemented: it"; }
meta() { jq -r --arg i "${2:-tk-w}" --arg k "$1" '.[] | select(.id == $i) | .metadata // {} | if has($k) then .[$k] else "<absent>" end' "$STORE"; }
field() { jq -r --arg i "${2:-tk-w}" --arg k "$1" '.[] | select(.id == $i) | .[$k] // ""' "$STORE"; }
words() { awk '{print $1}' "$LOG" | tr '\n' ' '; }
pushed() { grep -c '^push ' "$LOG" | tr -d ' '; }
ON_ORIGIN() { g "$CO" rev-parse -q --verify "refs/heads/$1" 2>/dev/null; }
closed_step() { field status st-submit; }

echo "# fresh work lands whole"
FRESH='{}'
prepare polecat/tk-w "$FRESH"
go
eq "$RC" 0 "(1) fresh work exits 0"
eq "$(ON_ORIGIN polecat/tk-w)" "$HEAD_SHA" "(1) the branch is on origin at HEAD"
eq "$(meta target)" "main" "(1) base fills in the landing target"
eq "$(meta branch)" "polecat/tk-w" "(1) metadata.branch is recorded with the handoff"
eq "$(field assignee)" "gc-toolkit/gc-toolkit.refinery" "(1) the bead is the refinery's"
eq "$(field status)" "open" "(1) open"
eq "$(meta gc.routed_to)" "" "(1) route cleared"
eq "$(closed_step)" "closed" "(1) this step is closed"
eq "$(meta gc.outcome st-submit)" "pass" "(1) with outcome pass"
eq "$(g "$C" branch --show-current)" "" "(1) the local branch is released"
eq "$(g "$C" branch --list polecat/tk-w)" "" "(1) and deleted"
has "$(field notes)" "Implemented: it" "(1) the notes are appended"

echo "# the handoff is ordered"
ORDER=$(grep -nE '^(push|guard|update tk-w|session|update st-submit|release|drain)' "$LOG" | cut -d: -f2 | awk '{print $1, $2}')
line_of() { printf '%s\n' "$ORDER" | grep -n "$1" | head -n 1 | cut -d: -f1; }
[ "$(line_of '^push')" -lt "$(line_of '^guard')" ] && ok "(2) the push comes before the guard" || bad "(2) the push comes before the guard"
[ "$(line_of '^guard')" -lt "$(line_of '^update tk-w')" ] && ok "(2) the guard comes before the handoff" || bad "(2) the guard comes before the handoff"
[ "$(line_of '^update st-submit')" -lt "$(line_of '^release')" ] && ok "(2) the step closes before the branch is released" || bad "(2) the step closes before the branch is released"
[ "$(line_of '^release')" -lt "$(line_of '^drain')" ] && ok "(2) the branch is released before the drain" || bad "(2) the branch is released before the drain"
eq "$(printf '%s\n' "$ORDER" | tail -n 1)" "drain " "(2) the drain is last"
HANDOFF=$(grep '^update tk-w' "$LOG")
FIRST=$(printf '%s\n' "$HANDOFF" | sed -n 1p); SECOND=$(printf '%s\n' "$HANDOFF" | sed -n 2p); THIRD=$(printf '%s\n' "$HANDOFF" | sed -n 3p)
has "$FIRST" "--set-metadata target=main" "(2) the first write carries the target"
has "$FIRST" "--set-metadata gc.routed_to=" "(2) and clears the route"
has "$FIRST" "--unset-metadata gc.session_id --unset-metadata gc.session_name" "(2) and removes the session pins"
has "$FIRST" "--unset-metadata work_holder" "(2) and lets go of the tree"
has "$FIRST" "--append-notes Implemented: it" "(2) and appends the notes"
no "$FIRST" "--notes " "(2) it never replaces the notes"
no "$FIRST" "--assignee" "(2) it carries no assignee, which the claim guard refuses"
no "$FIRST" "--status" "(2) and no status"
eq "$SECOND" "update tk-w --status=open" "(2) the second write is the status alone"
eq "$THIRD" "update tk-w --assignee=gc-toolkit/gc-toolkit.refinery" "(2) the third write is the assignee alone"
has "$(grep '^session' "$LOG" | sed -n 1p)" "session wake gc-toolkit/gc-toolkit.refinery" "(2) the refinery is woken"
eq "$(grep -c 'workflow-finalize' "$LOG" | tr -d ' ')" 0 "(2) workflow-finalize is never touched"

echo "# a rework child stands on the reviewed branch, and a caller's target wins"
prepare polecat/tk-anchor '{"branch":"polecat/tk-anchor","target":"integration/x"}'
go
eq "$RC" 0 "(3) a rework child on metadata.branch passes the gate"
eq "$(meta target)" "integration/x" "(3) a caller-set target is not overwritten"
eq "$(meta branch)" "polecat/tk-anchor" "(3) metadata.branch stands"
no "$(grep '^update tk-w' "$LOG" | sed -n 1p)" "--set-metadata branch=" "(3) and is not rewritten"

echo "# the branch gate fails closed"
prepare polecat/stray '{"branch":"polecat/tk-w"}'
go
eq "$RC" 1 "(4) on another branch: stops"
has "$OUT" "BRANCH SHAPE GATE FAILED" "(4) says so"
has "$OUT" "gate source:     metadata.branch" "(4) names the source"
has "$OUT" "check out 'polecat/tk-w'" "(4) says how to recover"
eq "$(pushed)" 0 "(4) nothing is pushed"
grep -q '^gate --subject tk-w --key polecat-branch-shape ' "$LOG" && ok "(4) files a gate under its key" || bad "(4) files a gate under its key"
has "$(grep '^gate ' "$LOG")" "clearing it re-slings tk-w" "(4) the gate says clearing it re-slings"
grep -q '^await tk-w --key polecat-branch-shape --formula mol-polecat-work$' "$LOG" && ok "(4) the work waits on it" || bad "(4) the work waits on it"
grep -q '^cancel --step mol-polecat-work.submit-and-exit ' "$LOG" && ok "(4) the run is cancelled" || bad "(4) the run is cancelled"
eq "$(words | sed 's/update //g')" "gate await cancel drain " "(4) in order, with the holder released first"
prepare polecat/stray "$FRESH"
go
eq "$RC" 1 "(4b) fresh work off polecat/<bead>: stops"
has "$OUT" "polecat/<bead-id> convention" "(4b) names the convention"
has "$OUT" "Re-run workspace-setup" "(4b) says how to recover"
prepare DETACHED '{"branch":"polecat/tk-w"}'
go
eq "$RC" 1 "(4c) a detached HEAD: stops"
has "$OUT" "<detached HEAD>" "(4c) says so"
eq "$(pushed)" 0 "(4c) nothing is pushed"
prepare polecat/stray '{"branch":"polecat/tk-w"}'
go GATE_RC=1
eq "$(words | sed 's/update //g')" "gate " "(4d) a gate that does not land stops the rest"
prepare polecat/stray '{"branch":"polecat/tk-w"}'
go AWAIT_RC=1
eq "$(words | sed 's/update //g')" "gate await " "(4d) a wait that does not land stops the cancel"
prepare polecat/stray '{"branch":"polecat/tk-w"}'
go CANCEL_RC=1
eq "$(words | sed 's/update //g')" "gate await cancel " "(4d) a cancel that does not land stops the drain"

echo "# a target nothing names fails closed"
prepare main-copy "$FRESH"
g "$C" branch -q -M polecat/tk-w
submit -- --convoy cv-1 --base polecat/tk-w --notes "n"
eq "$RC" 1 "(5) base is the branch being pushed: stops"
has "$OUT" "TARGET RESOLUTION FAILED" "(5) says so"
eq "$(pushed)" 0 "(5) nothing is pushed"
grep -q '^gate --subject tk-w --key polecat-no-landing-target ' "$LOG" && ok "(5) files a gate under its key" || bad "(5) files a gate under its key"

echo "# nothing is pushed with work left behind"
prepare polecat/tk-w "$FRESH"
printf 'loose\n' > "$C/loose.txt"
go
eq "$RC" 3 "(6) an uncommitted change exits 3"
has "$OUT" "UNCOMMITTED WORK" "(6) says so"
has "$OUT" "loose.txt" "(6) names it"
eq "$(pushed)" 0 "(6) nothing is pushed"
eq "$(grep -c '^drain' "$LOG" | tr -d ' ')" 0 "(6) no drain: the commit is the session's to make"
eq "$(field assignee)" "" "(6) nothing is handed off"

echo "# auto_push=false halts at branch-ready"
prepare polecat/tk-w '{"auto_push":"false","gc.session_id":"sess-me","gc.session_name":"x"}'
go
eq "$RC" 0 "(7) exits 0"
eq "$(pushed)" 0 "(7) nothing is pushed"
eq "$(meta branch_ready)" "true" "(7) branch_ready is recorded"
eq "$(meta halt_reason)" "auto_push_false" "(7) halt_reason is recorded"
eq "$(meta target)" "main" "(7) the landing target is recorded"
eq "$(field status)" "open" "(7) the bead rests open"
eq "$(field assignee)" "" "(7) unassigned"
eq "$(meta gc.session_id)" "<absent>" "(7) its pins go with the hand-back"
eq "$(meta work_holder)" "<absent>" "(7) and its holder"
eq "$(closed_step)" "closed" "(7) this step is closed"
eq "$(tail -n 1 "$LOG")" "drain" "(7) and the drain is last"
eq "$(g "$C" branch --show-current)" "polecat/tk-w" "(7) the branch stays checked out"
prepare polecat/tk-w '{"auto_push":false}'
go
eq "$(meta halt_reason)" "auto_push_false" "(7b) a boolean false halts too"

echo "# the store-only exit"
prepare DETACHED '{"gc.session_id":"sess-me","gc.session_name":"x"}'
submit -- --store-only "filed tk-z" --notes "what closes this" --convoy cv-1 --base main --done ""
eq "$RC" 0 "(8) a run with no commit exits 0: $OUT"
eq "$(meta halt_reason)" "store_only" "(8) the exit is recorded"
has "$(field notes)" "Store-only exit: filed filed tk-z. what closes this" "(8) the notes name what was filed"
eq "$(field status) $(field assignee)" "open " "(8) the bead rests open and unassigned"
eq "$(meta gc.routed_to)" "" "(8) unrouted"
eq "$(meta gc.session_id)" "<absent>" "(8) with its pins removed"
eq "$(closed_step)" "closed" "(8) this step is closed"
eq "$(pushed)" 0 "(8) nothing is pushed"
eq "$(tail -n 1 "$LOG")" "drain" "(8) and the drain is last"
prepare polecat/tk-w "$FRESH"
submit -- --store-only "filed tk-z" --notes "n" --convoy cv-1 --base main --done ""
eq "$RC" 1 "(8b) a run with a commit ahead of the base: refused"
eq "$(meta halt_reason)" "<absent>" "(8b) nothing is recorded"
eq "$(closed_step)" "in_progress" "(8b) the step stays open"
eq "$(grep -c '^drain' "$LOG" | tr -d ' ')" 1 "(8b) the session drains, so the step is offered again"

mv "$PACK/store-only-exit.sh" "$TMP/store-only-exit.real"
recorder store-only-exit.sh storeonly STORE_ONLY_RC
prepare DETACHED "$FRESH"
submit -- --store-only "filed tk-z" --notes "n" --done "the brief" --convoy cv-1 --base main
has "$(grep '^storeonly ' "$LOG")" "storeonly --bead tk-w --base main --convoy cv-1 --done the brief" "(8c) the bead, the base, the convoy and the brief reach the check"
prepare DETACHED "$FRESH"
submit STORE_ONLY_RC=1 -- --store-only "filed tk-z" --notes "n" --convoy cv-1 --base main
eq "$RC|$(words)" "1|storeonly drain " "(8d) a refused check writes nothing, drains and exits 1"
mv "$TMP/store-only-exit.real" "$PACK/store-only-exit.sh"

echo "# withdrawn work ends the run, and landed work closes the step"
prepare polecat/tk-w "$FRESH"
jq -c 'map(if .id == "tk-w" then .status = "closed" else . end)' "$STORE" > "$STORE.n" && mv "$STORE.n" "$STORE"
go
eq "$RC" 1 "(9) closed mid-run: stops"
grep -q '^cancel --step mol-polecat-work.submit-and-exit --reason work bead tk-w was closed while its run was mid-flight' "$LOG" && ok "(9) the run is cancelled" || bad "(9) the run is cancelled"
eq "$(pushed)" 0 "(9) nothing is pushed"
eq "$(closed_step)" "in_progress" "(9) the step is the cancel's to close"
for landed in '"gc.work_outcome":"shipped"' '"merge_result":"merged"'; do
  prepare polecat/tk-w "{$landed}"
  jq -c 'map(if .id == "tk-w" then .status = "closed" else . end)' "$STORE" > "$STORE.n" && mv "$STORE.n" "$STORE"
  go
  eq "$RC" 0 "(10) closed with $landed: exits 0"
  eq "$(closed_step)" "closed" "(10) closed with $landed: this step closes"
  eq "$(grep -c '^cancel' "$LOG" | tr -d ' ')" 0 "(10) closed with $landed: nothing is cancelled"
  eq "$(pushed)" 0 "(10) closed with $landed: nothing is pushed"
  eq "$(tail -n 1 "$LOG")" "drain" "(10) closed with $landed: and it drains"
done

echo "# push failures hand nothing off"
prepare polecat/tk-w "$FRESH"
go PUSH_FAIL=1
eq "$RC" 1 "(11) a refused push: stops"
has "$OUT" "PUSH FAILED" "(11) says so"
has "$OUT" "Never force-push" "(11) with the merge instruction"
eq "$(field assignee)" "" "(11) nothing is handed off"
eq "$(closed_step)" "in_progress" "(11) the step stays open"
eq "$(tail -n 1 "$LOG")" "drain" "(11) the session drains"
prepare polecat/tk-w "$FRESH"
go "LS_REMOTE_WRONG=$TMP/ls-seen-$N"
eq "$RC" 1 "(12) a ref on origin that is not HEAD: stops"
has "$OUT" "PUSH VERIFICATION FAILED" "(12) says so"
eq "$(field assignee)" "" "(12) nothing is handed off"

echo "# the bring-current guard holds the handoff"
prepare polecat/tk-w "$FRESH"
go
GUARD=$(grep '^guard ' "$LOG")
has "$GUARD" "guard --bead tk-w --to $HEAD_SHA" "(13) the guard reads the pushed head"
has "$GUARD" "--from " "(13) with where origin stood before the push"
prepare polecat/tk-w "$FRESH"
go GUARD_RC=3
eq "$RC" 3 "(14) an audit owed exits 3"
has "$OUT" "BRING-CURRENT AUDIT INCOMPLETE" "(14) says so"
eq "$(grep -c '^drain' "$LOG" | tr -d ' ')" 0 "(14) no drain: the audit is the session's to finish"
eq "$(field assignee)" "" "(14) nothing is handed off"
eq "$(pushed)" 1 "(14) the push stands"
prepare polecat/tk-w "$FRESH"
go GUARD_RC=1
eq "$RC" 1 "(15) a guard that did not finish: stops"
has "$OUT" "BRING-CURRENT GUARD DID NOT FINISH" "(15) says so"
eq "$(tail -n 1 "$LOG")" "drain" "(15) the session drains"
eq "$(field assignee)" "" "(15) nothing is handed off"

echo "# a refused handoff write stops the chain"
for piece in "--append-notes" "--status=open" "--assignee=gc-toolkit"; do
  prepare polecat/tk-w "$FRESH"
  go "UPDATE_FAIL=$piece"
  eq "$RC" 1 "(16) $piece refused: stops"
  has "$OUT" "HANDOFF REFUSED" "(16) $piece refused: says so"
  grep -q '^gate --subject tk-w --key polecat-handoff-refused ' "$LOG" && ok "(16) $piece refused: files a gate" || bad "(16) $piece refused: files a gate"
  eq "$(closed_step)" "in_progress" "(16) $piece refused: the step is the cancel's to close"
done

echo "# the refinery's address must name an agent"
prepare polecat/tk-w "$FRESH"
go ROSTER=gc-toolkit/other.refinery
eq "$RC" 1 "(17) an address no agent holds: stops"
has "$OUT" "REFINERY ADDRESS NAMES NO AGENT" "(17) says so"
has "$OUT" "gc-toolkit/other.refinery" "(17) names the bound refineries"
eq "$(field assignee)" "" "(17) nothing is handed off"
prepare polecat/tk-w "$FRESH"
go ROSTER_DOWN=1
eq "$RC" 0 "(18) a roster that cannot be read: hands off unchecked"
has "$OUT" "roster unreadable" "(18) says so"
prepare polecat/tk-w "$FRESH"
submit -- --convoy cv-1 --base main --notes n --binding-prefix other.
eq "$RC" 1 "(19) the address follows the binding the pour rendered"
has "$OUT" "gc-toolkit/other.refinery" "(19) and is the one refused"

echo "# the summary and the title follow the anchor"
SUM="$TMP/summary.md"
prepare polecat/tk-w "$FRESH"
printf 'the summary\n' > "$SUM"
submit -- --convoy cv-1 --base main --notes n --summary-file "$SUM" --title "A better title"
eq "$(meta pr_summary)" "the summary" "(20) fresh work: the summary lands on this bead"
has "$(grep '^update tk-w' "$LOG" | sed -n 2p)" "pr_summary=the summary" "(20) in the first handoff write"
eq "$(field title)" "A better title" "(20) a retitle lands on this bead"
[ ! -e "$SUM" ] && ok "(20) the summary file is gone once handed off" || bad "(20) the summary file is gone once handed off"
ANCHOR_ROW='[{"id":"tk-a","title":"the anchor","status":"open","assignee":"","created_at":"2026-01-01","metadata":{"branch":"polecat/tk-a","merge_result":"pull_request"}}]'
prepare polecat/tk-a '{"branch":"polecat/tk-a"}' "$ANCHOR_ROW"
printf 'the summary\n' > "$SUM"
submit -- --convoy cv-1 --base main --notes n --summary-file "$SUM" --title "A better title"
has "$OUT" "gating anchor: tk-a" "(21) a child names its anchor"
eq "$(meta pr_summary tk-a)" "the summary" "(21) the summary lands on the anchor"
eq "$(meta pr_summary)" "<absent>" "(21) and not on the child"
eq "$(field title tk-a)" "A better title" "(21) the retitle lands on the anchor"
eq "$(field title)" "the work" "(21) and not on the child"
prepare polecat/tk-a '{"branch":"polecat/tk-a"}' "$ANCHOR_ROW"
printf 'the summary\n' > "$SUM"
submit UPDATE_FAIL=pr_summary= -- --convoy cv-1 --base main --notes n --summary-file "$SUM"
eq "$RC" 0 "(22) a summary the anchor refuses costs the PR its body, not the handoff"
has "$OUT" "pr_summary did not reach anchor tk-a" "(22) and says so"
eq "$(field assignee)" "gc-toolkit/gc-toolkit.refinery" "(22) the handoff lands"
prepare polecat/tk-w "$FRESH"
submit UPDATE_FAIL=--title -- --convoy cv-1 --base main --notes n --title "A new title"
eq "$RC" 0 "(23) a retitle bd refuses cannot roll the handoff back"
has "$OUT" "the retitle did not reach tk-w" "(23) and says so"
prepare polecat/tk-w "$FRESH"
submit -- --convoy cv-1 --base main --notes n --title "   "
eq "$(grep -c -- '--title' "$LOG" | tr -d ' ')" 0 "(24) a blank title writes nothing"
prepare polecat/tk-w "$FRESH"
: > "$SUM"
submit -- --convoy cv-1 --base main --notes n --summary-file "$SUM"
eq "$(meta pr_summary)" "<absent>" "(25) an empty summary file writes no summary"

echo "# which bead is the anchor"
TWO='[{"id":"tk-new","status":"open","created_at":"2026-02-01","metadata":{"branch":"polecat/b","merge_result":"pre_open_gate"}},{"id":"tk-old","status":"open","created_at":"2026-01-01","metadata":{"branch":"polecat/b","merge_result":"pull_request"}},{"id":"tk-none","status":"open","created_at":"2025-01-01","metadata":{"branch":"polecat/b"}}]'
prepare polecat/b '{"branch":"polecat/b"}' "$TWO"
submit -- --anchor-only --convoy cv-1
eq "$RC" 0 "(26) --anchor-only exits 0"
has "$OUT" "anchor: tk-old" "(26) the oldest other bead that carries a merge_result"
eq "$(grep -cE '^(update|push|drain)' "$LOG" | tr -d ' ')" 0 "(26) --anchor-only writes nothing"
prepare polecat/tk-w "$FRESH"
submit -- --anchor-only --convoy cv-1
has "$OUT" "none other on this branch" "(27) fresh work is its own anchor"
has "$OUT" "title: the work" "(27) and prints its title"
prepare polecat/tk-w '{"branch":"polecat/tk-w","merge_result":"pull_request"}'
submit -- --anchor-only --convoy cv-1
has "$OUT" "none other on this branch" "(27b) a bead carrying its own merge_result is no child of itself"
prepare polecat/tk-a '{"branch":"polecat/tk-a"}' "$(jq -c '.[0].title = "the anchor"' <<<"$ANCHOR_ROW")"
submit -- --anchor-only --convoy cv-1
has "$OUT" "title: the anchor" "(28) a child prints the anchor's title"

prepare polecat/tk-a '{"branch":"polecat/tk-a"}' "$ANCHOR_ROW"
: > "$LOG"
submit -- --convoy cv-1 --base main --notes n --anchor tk-a --title "T"
eq "$(grep -c '^list ' "$LOG" | tr -d ' ')" 0 "(29) an anchor passed along is not looked up again"
eq "$(field title tk-a)" "T" "(29) and receives the write"
prepare polecat/tk-a '{"branch":"polecat/tk-a"}' "$ANCHOR_ROW"
submit -- --convoy cv-1 --base main --notes n --anchor "" --title "T"
eq "$(field title)" "T" "(29b) an empty --anchor names none: the claimed bead is the anchor"

REBUILD='[{"id":"tk-cv","status":"open","issue_type":"convoy","metadata":{"branch":"integration/x"}}]'
prepare integration/x '{"branch":"integration/x","task_kind":"rework","anchor_bead":"tk-cv"}' "$REBUILD"
submit -- --anchor-only --convoy cv-1
has "$OUT" "anchor: tk-cv" "(30) a rebuild child's anchor is the convoy it names"
prepare integration/x '{"branch":"integration/x","task_kind":"rework","anchor_bead":"tk-cv","source_review_bead":"tk-r"}' "$REBUILD"
submit -- --anchor-only --convoy cv-1
has "$OUT" "none other" "(30b) a review's rework never anchors the convoy"
prepare polecat/tk-a '{"branch":"polecat/tk-a","anchor_bead":"tk-a"}' "$ANCHOR_ROW"
submit LIST_DOWN=1 -- --anchor-only --convoy cv-1
has "$OUT" "could not list the branch's beads" "(31) a list that fails says so"
has "$OUT" "anchor: tk-a" "(31) and a rework child's anchor_bead answers"
prepare polecat/tk-w "$FRESH"
submit LIST_DOWN=1 -- --anchor-only --convoy cv-1
has "$OUT" "none other" "(32) with no anchor_bead, the summary falls to the claimed bead"

echo "# the store"
prepare polecat/tk-w "$FRESH"
go SHOW_DOWN=1
eq "$RC" 1 "(33) a store that does not answer: stops"
has "$OUT" "The store did not answer" "(33) says so"
eq "$(pushed)" 0 "(33) nothing is pushed: an absent target or auto_push is not read off a failed read"
eq "$(grep -cE '^(gate|cancel) ' "$LOG" | tr -d ' ')" 0 "(33) asks nothing and cancels nothing"
eq "$(tail -n 1 "$LOG")" "drain" "(33) the step goes back to the pool"
prepare polecat/tk-w "$FRESH"
printf '[]' > "$STORE"
go
eq "$RC" 1 "(34) no such bead: stops"
eq "$(pushed)" 0 "(34) nothing is pushed"

echo "# a close that does not land leaves the step for the next run"
prepare polecat/tk-w "$FRESH"
go UPDATE_FAIL=gc.outcome=
eq "$RC" 1 "(35) the close refused: stops"
has "$OUT" "this step is not closed" "(35) says so"
eq "$(field assignee)" "gc-toolkit/gc-toolkit.refinery" "(35) the handoff stands"
eq "$(grep -c '^drain' "$LOG" | tr -d ' ')" 0 "(35) no drain: it would hand the step back"
eq "$(g "$C" branch --show-current)" "polecat/tk-w" "(35) the branch stays, so a re-offered step reads the same shape"

echo "# a claimant with no poured workflow holds the work bead itself"
# hold <bead> <assignee> : the bead in_progress under <assignee>, with the session
# pins a claim leaves, as `gc hook --claim` leaves a bead routed with no pour.
hold() {
  jq -c --arg id "$1" --arg who "$2" 'map(if .id == $id then .status = "in_progress" | .assignee = $who
    | .metadata["gc.session_id"] = $who | .metadata["gc.session_name"] = "x" | .metadata["gc.routed_to"] = "pool" else . end)' "$STORE" > "$STORE.n" && mv "$STORE.n" "$STORE"
}
direct() { submit HOOK_CURRENT=tk-w -- --bead tk-w --base main --notes "Implemented: it"; }
prepare polecat/tk-w "$FRESH"; hold tk-w sess-me
direct
eq "$RC" 0 "(36) a direct claim hands off and exits 0: $OUT"
eq "$(ON_ORIGIN polecat/tk-w)" "$HEAD_SHA" "(36) the branch is on origin at HEAD"
eq "$(field status) $(field assignee)" "open gc-toolkit/gc-toolkit.refinery" "(36) the bead is the refinery's, and open"
eq "$(meta gc.routed_to)" "" "(36) unrouted"
eq "$(meta gc.session_id)" "<absent>" "(36) with its pins removed"
eq "$(meta branch)" "polecat/tk-w" "(36) and its branch recorded"
no "$OUT" "is not closed" "(36) it asks for no close"
eq "$(closed_step)" "in_progress" "(36) no step is written: it closes nothing of any other run"
eq "$(grep -c '^update st-submit' "$LOG" | tr -d ' ')" 0 "(36) not even a stray stamp"
eq "$(g "$C" branch --list polecat/tk-w)" "" "(36) the local branch is released"
eq "$(tail -n 1 "$LOG")" "drain" "(36) and the drain is last"

prepare polecat/tk-w '{"auto_push":"false"}'; hold tk-w sess-me
direct
eq "$RC" 0 "(37) a direct claim halts at branch-ready and exits 0: $OUT"
eq "$(pushed)" 0 "(37) nothing is pushed"
eq "$(meta halt_reason)" "auto_push_false" "(37) the halt is recorded"
eq "$(field status) $(field assignee)" "open " "(37) the claim is released"
eq "$(closed_step)" "in_progress" "(37) no step is written"
eq "$(tail -n 1 "$LOG")" "drain" "(37) and the drain is last"
# A call interrupted after the release leaves a bead with no holder, which is no
# other session's claim.
: > "$LOG"
direct
eq "$RC" 0 "(37b) the call again, with the claim already released: exits 0: $OUT"
eq "$(field status) $(field assignee)" "open " "(37b) the bead stays released"
eq "$(pushed)" 0 "(37b) still nothing is pushed"
eq "$(tail -n 1 "$LOG")" "drain" "(37b) and the drain is last"

prepare DETACHED "$FRESH"; hold tk-w sess-me
submit HOOK_CURRENT=tk-w -- --store-only "tk-z" --notes "what closes this" --bead tk-w --base main
eq "$RC" 0 "(38) a direct claim's store-only exit exits 0: $OUT"
eq "$(meta halt_reason)" "store_only" "(38) the exit is recorded"
eq "$(field status) $(field assignee)" "open " "(38) the claim is released"
eq "$(meta gc.routed_to)" "" "(38) unrouted"
eq "$(closed_step)" "in_progress" "(38) no step is written"
eq "$(tail -n 1 "$LOG")" "drain" "(38) and the drain is last"

prepare polecat/tk-w '{"merge_result":"merged"}'; hold tk-w sess-me
jq -c 'map(if .id == "tk-w" then .status = "closed" else . end)' "$STORE" > "$STORE.n" && mv "$STORE.n" "$STORE"
direct
eq "$RC" 0 "(39) a direct claim already landed exits 0: $OUT"
eq "$(words)" "drain " "(39) and only drains"
prepare polecat/tk-w "$FRESH"; hold tk-w sess-me
jq -c 'map(if .id == "tk-w" then .status = "closed" else . end)' "$STORE" > "$STORE.n" && mv "$STORE.n" "$STORE"
direct
eq "$RC" 1 "(39b) a direct claim closed unlanded: stops"
has "$OUT" "was closed while this session held it" "(39b) says so"
eq "$(words)" "drain " "(39b) with no run to cancel, it only drains"

# A call interrupted after the handoff and before the release leaves the branch here.
prepare polecat/tk-w "$FRESH"; hold tk-w sess-me
direct
g "$C" checkout -q -b polecat/tk-w "$HEAD_SHA"
: > "$LOG"
direct
eq "$RC" 0 "(40) the call again, with the bead already the refinery's: exits 0: $OUT"
eq "$(field status) $(field assignee)" "open gc-toolkit/gc-toolkit.refinery" "(40) the handoff stands"
eq "$(g "$C" branch --list polecat/tk-w)" "" "(40) the release finishes"
eq "$(tail -n 1 "$LOG")" "drain" "(40) and the drain is last"

echo "# --bead validates the claim before anything is written"
prepare polecat/tk-w "$FRESH"
submit -- --bead tk-w --base main --notes "Implemented: it"
eq "$RC" 0 "(41) --bead while holding this step: exits 0: $OUT"
eq "$(closed_step)" "closed" "(41) the step closes, by claim-close.sh's checks"
eq "$(meta gc.outcome st-submit)" "pass" "(41) with outcome pass"
prepare polecat/tk-w "$FRESH"
submit UPDATE_FAIL=gc.outcome= -- --bead tk-w --base main --notes "n"
eq "$RC" 1 "(41b) that close refused: stops, as a step's close does"
has "$OUT" "this step is not closed" "(41b) says so"
eq "$(grep -c '^drain' "$LOG" | tr -d ' ')" 0 "(41b) no drain"

refused() { # <label> : exit 3, with no write of any kind and no drain.
  eq "$RC" 3 "$1: exit 3"
  has "$OUT" "tk-w is NOT handed off" "$1: says so"
  eq "$(pushed)" 0 "$1: nothing is pushed"
  eq "$(grep -cE '^(update|drain|gate|cancel|guard|session|release) ?' "$LOG" | tr -d ' ')" 0 "$1: nothing is written and nothing drains"
}
prepare polecat/tk-w "$FRESH"; hold tk-w sess-me
submit HOOK_CURRENT=tk-other -- --bead tk-w --base main --notes "n"
refused "(42) the current claim is another plain bead"
jq -c '. + [{id: "tk-other", status: "in_progress", assignee: "sess-me", metadata: {}}]' "$STORE" > "$STORE.n" && mv "$STORE.n" "$STORE"; : > "$LOG"
submit HOOK_CURRENT=tk-other -- --bead tk-w --base main --notes "n"
refused "(42b) one this session holds"
has "$OUT" "not mol-polecat-work.submit-and-exit" "(42b) and claim-close.sh names what it found"
prepare polecat/tk-w "$FRESH"; hold tk-w sess-me
submit HOOK_CURRENT= -- --bead tk-w --base main --notes "n"
refused "(43) no current claim can be read"
has "$OUT" "gc hook current names no bead" "(43) names that"
prepare polecat/tk-w "$FRESH"; hold tk-w sess-other
direct
refused "(44) the bead is another session's claim"
has "$OUT" "held by sess-other" "(44) names the holder"
prepare polecat/tk-w "$FRESH"
submit HOOK_CURRENT=st-submit -- --bead st-submit --base main --notes "n"
eq "$RC" 3 "(45) --bead names a step, even the one held: exit 3"
has "$OUT" "st-submit is the step mol-polecat-work.submit-and-exit" "(45) says so"
eq "$(pushed)" 0 "(45) nothing is pushed"
eq "$(closed_step)" "in_progress" "(45) and the step stays open"
prepare polecat/tk-w "$FRESH"; hold tk-w sess-other
submit HOOK_CURRENT=tk-other -- --anchor-only --bead tk-w
eq "$RC" 0 "(46) --anchor-only writes nothing, so it validates no claim"

echo "# a step's close stays strict over --convoy"
prepare polecat/tk-w "$FRESH"
go HOOK_CURRENT=tk-w
eq "$RC" 1 "(47) --convoy with a plain current claim: stops, as a step's close does"
has "$OUT" "this step is not closed" "(47) says so"
eq "$(grep -c '^drain' "$LOG" | tr -d ' ')" 0 "(47) no drain"

echo "# usage"
submit -- ; eq "$RC" 2 "no work named: usage error"
submit -- --bead a --convoy b --base x --notes n; eq "$RC" 2 "both named: usage error"
submit -- --bead a --base x; eq "$RC" 2 "no --notes: usage error"
submit -- --bead a --notes n; eq "$RC" 2 "no --base: usage error"
submit -- --nope; eq "$RC" 2 "an unknown flag: usage error"

echo
echo "work-submit: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
