#!/usr/bin/env bash
# An agent's work_dir and its max_active_sessions have to agree about how many
# instances of that agent exist. A work_dir templated on {{.AgentBase}} gives
# every instance its own tree, which is what lets the routed-pool path
# materialize numbered instances. An untemplated one names a single tree that
# concurrent instances would share. Neither shape is wrong on its own, so the
# agreement is the thing to hold: a per-instance work_dir with no cap is
# unbounded by construction, and a shared work_dir with a cap above 1 hands one
# directory to several sessions.
#
# The pairing needs a test because each half reads as reasonable alone, and the
# damage lands somewhere else entirely. An uncapped per-instance agent whose
# patrol reconciles one wisp per rig has its instances burning each other's
# in-flight wisps, and nothing in the agent's own config looks wrong.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE/../.."
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }

TOMLS=()
for T in "$ROOT"/agents/*/agent.toml "$ROOT"/packs/*/agents/*/agent.toml; do
  [ -s "$T" ] && TOMLS+=("$T")
done
[ "${#TOMLS[@]}" -gt 0 ] || { echo "no agent TOMLs under $ROOT" >&2; exit 1; }

# toplevel <toml> <key> — the key's value, read only from the region above the
# first [table] header, so a same-named key inside [env] or [pool] cannot be
# mistaken for the agent's own.
toplevel() {
  awk -v k="$2" '
    /^[[:space:]]*\[/ { exit }
    $0 ~ "^" k "[[:space:]]*=" {
      sub("^" k "[[:space:]]*=[[:space:]]*", "")
      sub(/[[:space:]]*(#.*)?$/, "")
      gsub(/^"|"$/, "")
      print; exit
    }
  ' "$1"
}

for TOML in "${TOMLS[@]}"; do
  NAME=$(basename "$(dirname "$TOML")")
  WORK_DIR=$(toplevel "$TOML" work_dir)
  CAP=$(toplevel "$TOML" max_active_sessions)

  # A cap the runtime cannot parse as a number bounds nothing, so it is the same
  # finding as a missing one and has to be caught here rather than compared below.
  case "${CAP:-0}" in
    ''|*[!0-9-]*|*-*[!0-9]*|-) bad "$NAME: max_active_sessions = $CAP is not an integer, so nothing bounds the pool"; continue ;;
  esac

  if [ -z "$WORK_DIR" ]; then
    bad "$NAME: declares no work_dir, so nothing says whether its instances share a tree"
    continue
  fi

  case "$WORK_DIR" in
    *'{{'*'.AgentBase'*'}}'*) PER_INSTANCE=yes ;;
    *)                        PER_INSTANCE=no ;;
  esac

  if [ "$PER_INSTANCE" = yes ]; then
    if [ -z "$CAP" ]; then
      bad "$NAME: work_dir is per-instance ({{.AgentBase}}) but no max_active_sessions bounds it — the pool path can materialize instances without limit"
    elif [ "$CAP" -lt 1 ]; then
      ok "$NAME: per-instance work_dir, max_active_sessions = $CAP holds the pool closed"
    else
      ok "$NAME: per-instance work_dir, bounded at max_active_sessions = $CAP"
    fi
    continue
  fi

  if [ -n "$CAP" ] && [ "$CAP" -gt 1 ]; then
    bad "$NAME: max_active_sessions = $CAP but work_dir names one shared tree ($WORK_DIR) — give it {{.AgentBase}} or lower the cap"
  else
    if [ -n "$CAP" ]; then
      ok "$NAME: single work_dir, held to one session by max_active_sessions = $CAP"
    else
      ok "$NAME: single work_dir, and no cap declared, so one session at a time"
    fi
  fi
done

echo
echo "pool-cap-wiring: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
