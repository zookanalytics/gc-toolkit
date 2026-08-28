#!/usr/bin/env bash
# gascity renders the routed-pool serving rules from one value,
# config.PoolDemandServeRules, so the controller's demand count and the worker's
# Tier-3 claim query cannot come to serve different sets;
# cmd/gc/demand_serve_agreement_test.go holds that agreement. A scale_check in a
# pack TOML is a hand-written copy of those rules that test cannot see, and it
# drifts the moment a rule is added upstream. It is legitimate only as the count
# form of a work_query the same agent declares, and then it must agree with that
# query.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE/../.."
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }

TOMLS=("$ROOT"/agents/*/agent.toml)
[ -s "${TOMLS[0]}" ] || { echo "no agent TOMLs under $ROOT/agents" >&2; exit 1; }

# block <toml> <key> — the key's value: the body of a ''' block, or the rest of
# the line for a single-line string.
block() {
  awk -v k="$2" -v q="'''" '
    !inblock && $0 ~ "^" k " = " {
      rest = substr($0, length(k) + 4)
      if (rest == q) { inblock = 1; next }
      print rest; exit
    }
    inblock && $0 == q { exit }
    inblock { print }
  ' "$1"
}

# ready_flags — the serving flags of every bd ready in the block on stdin. Each
# line is cut at the first pipe so a jq stage contributes no tokens. --json,
# --limit and --sort shape the output rather than the served set, so the list
# and count forms differ there by design.
ready_flags() {
  sed -n 's/.*bd ready//p' \
    | sed 's/|.*//' \
    | grep -oE -- '--[a-z-]+(=[^ ]+)?( +("[^"]*"|[^- ][^ ]*))?' \
    | tr -s ' ' \
    | grep -vE '^--(json|limit|sort)([ =]|$)' \
    | sort -u
}

# The reconciler prepends VAR='…' to line 1 of a declared block, so line 1 must
# be a bare assignment for the prefix to land somewhere harmless.
check_env_prefix_landing() {
  case "$(printf '%s\n' "$2" | head -1)" in
    _=*) ok "$1: line 1 absorbs the reconciler's env prefix" ;;
    *)   bad "$1: line 1 must be a bare assignment or the prepended env prefix is lost" ;;
  esac
}

for TOML in "${TOMLS[@]}"; do
  NAME=$(basename "$(dirname "$TOML")")
  SCALE_CHECK=$(block "$TOML" scale_check)
  WORK_QUERY=$(block "$TOML" work_query)

  if [ -z "$SCALE_CHECK" ]; then
    ok "$NAME: no scale_check, so the default routed-pool predicate counts its demand"
    continue
  fi

  if [ -z "$WORK_QUERY" ]; then
    bad "$NAME: a scale_check with no work_query re-implements PoolDemandServeRules; drop it and let the default predicate count"
    continue
  fi
  ok "$NAME: scale_check is paired with the work_query it has to agree with"

  check_env_prefix_landing "$NAME work_query" "$WORK_QUERY"
  check_env_prefix_landing "$NAME scale_check" "$SCALE_CHECK"

  SERVED=$(diff \
    <(printf '%s\n' "$WORK_QUERY" | ready_flags) \
    <(printf '%s\n' "$SCALE_CHECK" | ready_flags) 2>&1)
  if [ -z "$SERVED" ]; then
    ok "$NAME: the count form serves the set its work_query serves"
  else
    bad "$NAME: scale_check and work_query disagree on what bd ready serves"
    printf '%s\n' "$SERVED" | sed 's/^/       /'
  fi

  printf '%s\n' "$WORK_QUERY" | sh -n 2>/dev/null \
    && ok "$NAME: work_query is valid sh" \
    || bad "$NAME: work_query is not valid sh"
  printf '%s\n' "$SCALE_CHECK" | sh -n 2>/dev/null \
    && ok "$NAME: scale_check is valid sh" \
    || bad "$NAME: scale_check is not valid sh"
done

# converse's visits are filed in both the city store and the rig store, and its
# work_dir carries no .beads, so the claim resolves its store by walk-up. A
# custom work_query would pin that to one store and hide the other half.
CONVERSE="$ROOT/agents/converse/agent.toml"
if [ -s "$CONVERSE" ]; then
  if [ -z "$(block "$CONVERSE" work_query)" ]; then
    ok "converse: no work_query, so the claim keeps the store set its visits arrive in"
  else
    bad "converse: a custom work_query pins the claim to one store; converse-routed visits are filed in both"
  fi
else
  bad "missing $CONVERSE"
fi

echo
echo "pool-demand-wiring: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
