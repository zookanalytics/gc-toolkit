#!/usr/bin/env bash
# Thin wiring check: the converse pool's SPAWN predicate counts only visits a
# converse session can be offered. Both halves are load-bearing. The --db pin
# holds the count to the rig store; without it bare `bd ready` resolves from
# converse's work_dir, which carries no .beads, and reads the CITY store a
# rig-scope session cannot claim from. The flags hold the count to the offer's
# own serving rules (PoolDemandServeRules).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE/../.."
TOML="$ROOT/agents/converse/agent.toml"
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }

[ -s "$TOML" ] || { echo "missing $TOML" >&2; exit 1; }

BLOCK=$(awk '/^scale_check = /{f=1; next} f && /^'"'''"'$/{exit} f' "$TOML")
[ -n "$BLOCK" ] \
  && ok "converse declares a scale_check" \
  || bad "converse declares no scale_check — the default probe reads the city store and counts visits no session can claim"

case "$BLOCK" in
  *'--db {{.RigRoot}}/.beads'*)
    ok "the count is pinned to the rig store the target reads" ;;
  *)
    bad "scale_check is not pinned to {{.RigRoot}}/.beads" ;;
esac

case "$BLOCK" in
  *'gc.routed_to=$target'*) ok "counts routed visits" ;;
  *) bad "scale_check does not filter on gc.routed_to" ;;
esac

case "$BLOCK" in
  *'target="{{.Rig}}/gc-toolkit.converse"'*)
    ok "the target is this rig's converse pool" ;;
  *)
    bad "scale_check names a target other than {{.Rig}}/gc-toolkit.converse" ;;
esac

for FLAG in '--unassigned' '--exclude-type=epic' '"hold:mayor"' '"hold:external"'; do
  case "$BLOCK" in
    *"$FLAG"*) ok "mirrors the offer's $FLAG" ;;
    *) bad "scale_check omits $FLAG, which the offer applies" ;;
  esac
done

case "$(printf '%s\n' "$BLOCK" | head -1)" in
  _=*) ok "line 1 is a bare assignment (absorbs the reconciler's env prefix)" ;;
  *)   bad "line 1 must stay a bare assignment or the prepended env prefix is lost" ;;
esac

if grep -q '^work_query = ' "$TOML"; then
  bad "converse declares a work_query — a custom one scopes the hook's federated store set, narrowing the CLAIM path too"
else
  ok "no work_query: the claim path keeps its federated store set"
fi

if printf '%s\n' "$BLOCK" | sh -n 2>/dev/null; then
  ok "scale_check block is valid sh"
else
  bad "scale_check block is not valid sh"
fi

echo
echo "converse-demand-wiring: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
