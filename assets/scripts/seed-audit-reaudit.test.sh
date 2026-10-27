#!/usr/bin/env bash
# Hermetic test for assets/scripts/seed-audit-reaudit.sh — the one writer of the
# seed audit's re-audit. Stubbed gc over a JSON store; no live city, Dolt, or
# network. merge.test.sh pins the merge gate's hand-off to it. This suite pins
# the writer's own contract: the usage refusals; a base that is not the default
# branch, read from origin/HEAD, filing nothing; a filed re-audit carrying its
# identity in the create, listing the files and who found them, settled before
# it is slung on mol-polecat-work to the pool route, with the stdout line the
# merge gate quotes; one live re-audit per base, whether dispatched, held,
# armed to re-sling once its wait clears, or never dispatched (adopted, made
# whole and slung), while a closed one or
# another base's files beside it; the stops that dispatch nothing (an
# unanswered dedup query, an unsettled priority, a pour that does not stamp),
# each leaving what a retry adopts; and every metadata key it writes registered
# in lifecycle.toml.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/seed-audit-reaudit.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-seed-audit-reaudit-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
# Host signing of commits must not make this suite need a signing agent.
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=commit.gpgsign GIT_CONFIG_VALUE_0=false

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
hasin() { grep -qF -- "$2" <<< "$1"; }
has()   { if hasin "$1" "$2"; then ok "$3"; else bad "$3 (missing '$2')"; fi; }
hasnt() { if hasin "$1" "$2"; then bad "$3 (found '$2')"; else ok "$3"; fi; }

BIN="$TMP/bin"; mkdir -p "$BIN"

# The store is a JSON array of beads. Every call is logged, so a case reads
# what was written and in what order.
cat > "$BIN/gc" <<'STUB'
#!/usr/bin/env bash
set -u
STORE="${STUB_STORE:?}"
printf '%s\n' "$*" >> "${STUB_GC_LOG:?}"
if [ "${1:-}" = "sling" ]; then
  # A graph.v2 pour retires gc.routed_to and stamps gc.execution_routed_to=<pool>,
  # unless the case says the pour left no stamp.
  shift; pool=""; bead=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --rig|--on) shift ;;
      -*) ;;
      *) if [ -z "$pool" ]; then pool="$1"; elif [ -z "$bead" ]; then bead="$1"; fi ;;
    esac
    shift || true
  done
  [ -z "${STUB_SLING_NOSTAMP:-}" ] || exit 0
  tmp=$(mktemp "${TMPDIR:-/tmp}/gctk-sar.XXXXXX")
  jq -c --arg id "$bead" --arg p "$pool" \
    'map(if .id == $id then (.metadata["gc.execution_routed_to"] = $p | .metadata |= del(.["gc.routed_to"])) else . end)' \
    "$STORE" > "$tmp" && mv "$tmp" "$STORE"
  exit 0
fi
# Any other non-bd command (the agent list pool-route.sh reads) is a quiet
# success: pool-route reads the empty agent set as unreadable and returns the
# route unverified.
[ "${1:-}" = "bd" ] || exit 0
shift
case "${1:-}" in
  show)
    out=$(jq -c --arg id "$2" '[.[] | select(.id == $id)]' "$STORE")
    if [ "$(printf '%s' "$out" | jq 'length')" = "0" ]; then echo '{"error":"no issues found"}'
    else printf '%s\n' "$out"; fi ;;
  update)
    shift; id="$1"; shift
    tmp=$(mktemp "${TMPDIR:-/tmp}/gctk-sar.XXXXXX"); cp "$STORE" "$tmp"
    while [ $# -gt 0 ]; do
      case "$1" in
        --set-metadata) shift; k="${1%%=*}"; v="${1#*=}"
          jq -c --arg id "$id" --arg k "$k" --arg v "$v" \
            'map(if .id == $id then .metadata[$k] = $v else . end)' "$tmp" > "$tmp.n" && mv "$tmp.n" "$tmp" ;;
      esac
      shift || true
    done
    mv "$tmp" "$STORE"; echo "updated $id" ;;
  create)
    shift
    title=""; body=""; cmeta='{}'; prio=2
    while [ $# -gt 0 ]; do
      case "$1" in
        --title) shift; title="${1:-}" ;;
        -d|--description) shift; body="${1:-}" ;;
        --metadata) shift; cmeta="${1:-}" ;;
        --priority=*) prio="${1#--priority=}" ;;
      esac
      shift || true
    done
    n=$(cat "$STUB_SEQ" 2>/dev/null || echo 0); n=$((n + 1)); printf '%s' "$n" > "$STUB_SEQ"
    tmp=$(mktemp "${TMPDIR:-/tmp}/gctk-sar.XXXXXX")
    jq -c --arg id "re-$n" --arg t "$title" --arg d "$body" --argjson m "$cmeta" --argjson p "$prio" \
      '. + [{"id":$id,"title":$t,"description":$d,"status":"open","assignee":"","priority":$p,"metadata":$m,"notes":""}]' \
      "$STORE" > "$tmp" && mv "$tmp" "$STORE"
    printf '{"id":"re-%s"}\n' "$n" ;;
  list)
    [ -z "${STUB_LIST_FAIL:-}" ] || { echo "Error: store unreachable" >&2; exit 1; }
    shift
    statuses=""; fields=()
    while [ $# -gt 0 ]; do
      case "$1" in
        --status=*) statuses="${1#--status=}" ;;
        --metadata-field) shift; fields+=("${1:-}") ;;
      esac
      shift || true
    done
    out=$(jq -c --arg st "$statuses" '[ .[] | (.status // "open") as $b
      | select($st == "" or (($st | split(",")) | index($b))) ]' "$STORE")
    for f in ${fields[@]+"${fields[@]}"}; do
      out=$(printf '%s' "$out" | jq -c --arg k "${f%%=*}" --arg v "${f#*=}" \
        '[ .[] | select(((((.metadata // {})[$k]) // "") | tostring) == $v) ]')
    done
    printf '%s\n' "$out" ;;
esac
STUB
chmod +x "$BIN/gc"
# The priority writer, logged into the same call log so a case reads its order
# against the sling; STUB_SETTLE_RC makes it refuse.
printf '#!/usr/bin/env bash\nprintf "settle %%s\\n" "$2" >> "${STUB_GC_LOG:?}"\n[ -z "${STUB_SETTLE_RC:-}" ] || { echo "queue-priority: settle: could not take the priority lock" >&2; exit "$STUB_SETTLE_RC"; }\n' > "$BIN/queue-priority"
chmod +x "$BIN/queue-priority"
export PATH="$BIN:$PATH"
export GC_RIG="gc-toolkit"
export GC_QUEUE_PRIORITY_TOOL="$BIN/queue-priority"
export STUB_STORE="$TMP/store.json" STUB_GC_LOG="$TMP/gc.log" STUB_SEQ="$TMP/seq"
unset STUB_LIST_FAIL STUB_SETTLE_RC STUB_SLING_NOSTAMP

# The checkout the writer runs in: its origin/HEAD names the default branch.
repo() { # <dir> <default branch>
  git init -q "$1" && git -C "$1" symbolic-ref refs/remotes/origin/HEAD "refs/remotes/origin/$2"
}
repo "$TMP/main-repo" main
repo "$TMP/trunk-repo" trunk
mkdir -p "$TMP/no-repo"

# reset [<bead-json>...]: seed the store and clear the logs.
reset() {
  local rows="" b
  for b in "$@"; do rows="${rows:+$rows,}$b"; done
  printf '[%s]\n' "$rows" > "$STUB_STORE"
  : > "$STUB_GC_LOG"; printf '0' > "$STUB_SEQ"
}
run() { ( cd "${RUN_IN:-$TMP/main-repo}" && "$SUT" "$@" ); }
meta()    { jq -r --arg id "$1" --arg k "$2" 'first(.[] | select(.id == $id) | .metadata[$k]) // ""' "$STUB_STORE"; }
field()   { jq -r --arg id "$1" --arg k "$2" 'first(.[] | select(.id == $id) | .[$k]) // ""' "$STUB_STORE"; }
beads()   { jq 'length' "$STUB_STORE"; }
calls()   { grep -c -- "$1" "$STUB_GC_LOG" | tr -d ' '; }
ROUTE="gc-toolkit/gc-toolkit.polecat"
PAGES=(--page agents/claude.md --page formulas/mol-polecat-base.md)
reaudit() { # id [status] [assignee] [extra-metadata-json]
  printf '{"id":"%s","status":"%s","assignee":"%s","metadata":{"seed_audit_reaudit":"main","target":"main"%s},"notes":""}' \
    "$1" "${2:-open}" "${3:-}" "${4:-}"
}

echo "# --- usage ---"
reset
OUT=$(run 2>&1); RC=$?
eq "$RC" "1" "no --base is a usage error"
has "$OUT" "--base is required" "…naming the flag"
OUT=$(run --base "two words" 2>&1); RC=$?
eq "$RC" "1" "a --base that is no branch name is a usage error"
OUT=$(run --base main --frobnicate 2>&1); RC=$?
eq "$RC" "1" "an unknown flag is a usage error"
eq "$(calls 'bd ')" "0" "…and none of them reads or writes the store"

echo "# --- only the default branch is re-audited ---"
reset
OUT=$(run --base integration/x "${PAGES[@]}" 2>/dev/null); RC=$?
eq "$RC" "0" "a base that is not the default branch exits 0"
eq "$OUT" "none integration/x not-default" "…saying it is not the default branch"
eq "$(calls 'bd ')" "0" "…and reads or writes nothing"
OUT=$(RUN_IN="$TMP/trunk-repo" run --base trunk 2>/dev/null); RC=$?
eq "$RC" "0" "the default branch is read from origin/HEAD"
has "$OUT" "re-1 $ROUTE filed" "…so a checkout whose default is trunk re-audits trunk"
reset
OUT=$(RUN_IN="$TMP/trunk-repo" run --base main 2>/dev/null)
eq "$OUT" "none main not-default" "…and not main"
reset
OUT=$(RUN_IN="$TMP/no-repo" run --base main 2>/dev/null)
has "$OUT" "re-1 $ROUTE filed" "a checkout with no origin/HEAD takes main as the default"

echo "# --- the re-audit is filed whole and slung ---"
reset
OUT=$(run --base main "${PAGES[@]}" --seen-by "The merge gate, checking PR#7," 2>/dev/null); RC=$?
eq "$RC" "0" "a base with no live re-audit files one"
eq "$OUT" "re-1 $ROUTE filed" "…printing the line the merge gate quotes"
eq "$(beads)" "1" "…exactly one bead"
eq "$(meta re-1 seed_audit_reaudit)" "main" "…carrying its identity, the base"
eq "$(meta re-1 target)" "main" "…and the branch it lands on"
has "$(cat "$STUB_GC_LOG")" '--metadata {"seed_audit_reaudit":"main","target":"main"} --json' "…both written in the create itself"
eq "$(calls '^bd update re-1')" "0" "…with no second write to complete it"
eq "$(field re-1 title)" "Re-render the seed audit on main: the gc binary moved its text" "…titled for the work"
BODY=$(field re-1 description)
has "$BODY" "- generated/seed-audit/agents/claude.md" "…listing each file it was handed"
has "$BODY" "- generated/seed-audit/formulas/mol-polecat-base.md" "…every one of them"
has "$BODY" "The merge gate, checking PR#7, found main already stale" "…and who found it"
has "$BODY" 'run `assets/scripts/render-seed-audit.sh` and commit generated/seed-audit as it renders' "…stating the work"
eq "$(field re-1 priority)" "2" "…at P2"
eq "$(meta re-1 gc.execution_routed_to)" "$ROUTE" "the pour stamps the pool route"
has "$(grep -- '^sling ' "$STUB_GC_LOG")" "--rig gc-toolkit $ROUTE re-1 --on mol-polecat-work" "…slung on mol-polecat-work"
SETTLE_AT=$(grep -n '^settle re-1$' "$STUB_GC_LOG" | cut -d: -f1)
SLING_AT=$(grep -n '^sling ' "$STUB_GC_LOG" | cut -d: -f1)
if [ -n "$SETTLE_AT" ] && [ -n "$SLING_AT" ] && [ "$SETTLE_AT" -lt "$SLING_AT" ]; then
  ok "…after it is settled at its priority"
else bad "…after it is settled at its priority (settle at '${SETTLE_AT:-none}', sling at '${SLING_AT:-none}')"; fi

echo "# --- one live re-audit per base ---"
reset "$(reaudit re-9 open "" ',"gc.execution_routed_to":"gc-toolkit/gc-toolkit.polecat"')"
OUT=$(run --base main "${PAGES[@]}" 2>&1); RC=$?
eq "$RC" "0" "a re-audit already dispatched exits 0"
has "$OUT" "re-9 $ROUTE in-flight" "…reporting it in flight"
eq "$(beads)" "1" "…filing no second one"
eq "$(calls '^sling ')" "0" "…and slinging nothing"
eq "$(calls '^agent list')" "0" "…at the cost of the dedup read alone, with no route to prove"

reset "$(reaudit re-9 in_progress "someone")"
OUT=$(run --base main 2>&1); RC=$?
eq "$RC" "0" "a re-audit someone holds exits 0"
has "$OUT" "re-9 - held" "…reporting it held"
has "$OUT" "held (status in_progress, assignee someone)" "…naming what holds it"
eq "$(beads)" "1" "…filing no second one"
eq "$(calls '^sling ')" "0" "…and slinging nothing"

reset "$(reaudit re-9 blocked)"
OUT=$(run --base main 2>/dev/null)
eq "$OUT" "re-9 - held" "a parked re-audit is left to whoever parked it"

# A declined run leaves its bead open, unassigned and unrouted, waiting on a
# visit with a re-sling armed for when the visit closes (await-ruling.sh).
reset "$(reaudit re-9 open "" ',"gc.dispatch_when_ready":"gc-toolkit/gc-toolkit.polecat","resling_target":"gc-toolkit/gc-toolkit.polecat"')"
OUT=$(run --base main 2>&1); RC=$?
eq "$RC" "0" "a re-audit armed to re-sling once its wait clears exits 0"
has "$OUT" "re-9 - held" "…reporting it held"
has "$OUT" "held (armed for gc-toolkit/gc-toolkit.polecat)" "…naming the arm"
eq "$(beads)" "1" "…filing no second one"
eq "$(calls '^sling ')" "0" "…and slinging nothing past the wait"

reset '{"id":"re-9","status":"open","assignee":"","metadata":{"seed_audit_reaudit":"main"},"notes":""}'
OUT=$(run --base main 2>&1); RC=$?
eq "$RC" "0" "a re-audit filed and never dispatched is adopted"
has "$OUT" "re-9 $ROUTE adopted" "…reporting it adopted"
eq "$(beads)" "1" "…filing no second one"
eq "$(meta re-9 target)" "main" "…made whole before it is slung"
eq "$(meta re-9 gc.execution_routed_to)" "$ROUTE" "…and slung"

reset "$(reaudit re-9 closed "" ',"gc.execution_routed_to":"gc-toolkit/gc-toolkit.polecat"')" \
  '{"id":"re-8","status":"open","assignee":"","metadata":{"seed_audit_reaudit":"trunk","gc.execution_routed_to":"x"},"notes":""}'
OUT=$(run --base main 2>/dev/null); RC=$?
eq "$OUT" "re-1 $ROUTE filed" "a closed re-audit, and another base's live one, leave this base none"
eq "$(meta re-1 seed_audit_reaudit)" "main" "…so one is filed for it"

echo "# --- stops that dispatch nothing ---"
reset
OUT=$(STUB_LIST_FAIL=1 run --base main 2>&1); RC=$?
eq "$RC" "2" "a dedup query that does not answer exits 2"
has "$OUT" "dedup query failed" "…saying why"
eq "$(beads)" "0" "…and files nothing"

reset
OUT=$(STUB_SETTLE_RC=1 run --base main 2>&1); RC=$?
eq "$RC" "2" "a re-audit whose priority does not settle exits 2"
has "$OUT" "re-1 did not settle at its priority" "…naming the bead"
has "$OUT" "could not take the priority lock" "…with the writer's own reason"
eq "$(calls '^sling ')" "0" "…and slings nothing"
OUT=$(run --base main 2>/dev/null); RC=$?
eq "$OUT" "re-1 $ROUTE adopted" "…while a retry adopts and slings it"
eq "$(beads)" "1" "…filing no second one"

reset
OUT=$(STUB_SLING_NOSTAMP=1 run --base main 2>&1); RC=$?
eq "$RC" "2" "a pour that does not stamp the route exits 2"
has "$OUT" "did not stamp gc.execution_routed_to=$ROUTE" "…saying so"
eq "$(meta re-1 gc.routed_to)" "" "…and stamps no bare route in its place"

echo "# --- metadata-key drift against lifecycle.toml ---"
# A key the writer stamps that nothing registers is state no audit can account
# for. The identity rides the create's payload, outside a flag extraction, so
# its keys are read off what the create wrote.
REGISTERED=$(sed -n '/^# The metadata-key registry/,$p' "$HERE/../../lifecycle/lifecycle.toml" \
  | sed 's/#.*//' | grep -oE '"[^"]+"' | tr -d '"' | sort -u)
reset; run --base main >/dev/null 2>&1
WRITTEN=$(jq -r '.[0].metadata | keys[] | select(startswith("gc.") | not)' "$STUB_STORE" | sort -u)
has "$WRITTEN" "seed_audit_reaudit" "the extraction reads the writer's identity"
UNREGISTERED=$(printf '%s\n' "$WRITTEN" \
  | grep -Fxv -f <(printf '%s\n' "$REGISTERED") | tr '\n' ' ' | sed 's/ *$//') || true
eq "$UNREGISTERED" "" "every metadata key seed-audit-reaudit.sh writes is registered in lifecycle.toml"

echo
echo "===================="
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
