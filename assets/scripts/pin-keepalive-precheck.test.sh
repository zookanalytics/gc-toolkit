#!/usr/bin/env bash
# pin-keepalive-precheck.test.sh — the CHECK entry of orders/pin-keepalive.toml
# is a thin wrapper: it runs pin-keepalive.sh in --check mode. The predicate,
# cooldown and fail-open behaviour are proved against the main script in
# pin-keepalive.test.sh; this file pins only the wrapper's own contract — it
# forwards --check (and any extra args) to its SIBLING, resolved by the script's
# own location rather than the caller's cwd, so the order runner reaches the
# real check wherever it is invoked from.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
WRAP="$ROOT/assets/scripts/pin-keepalive-precheck.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n        %s\n' "$1" "$2"; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3" "missing '$2' in: $1" ;; esac; }

[ -s "$WRAP" ] || { echo "missing $WRAP"; exit 1; }
[ -x "$WRAP" ] || { echo "$WRAP is not executable"; exit 1; }

echo "── the wrapper is valid shell ──"
bash -n "$WRAP" && ok "pin-keepalive-precheck.sh: valid bash" \
    || bad "pin-keepalive-precheck.sh: valid bash" "bash -n failed"

# A shim standing in for the real main script, recording the args it was handed.
mk_shim() { # mk_shim <dir>
  mkdir -p "$1"
  cp "$WRAP" "$1/pin-keepalive-precheck.sh"
  cat > "$1/pin-keepalive.sh" <<'SHIM'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$WRAP_ARGS"
exit 0
SHIM
  chmod +x "$1/pin-keepalive-precheck.sh" "$1/pin-keepalive.sh"
}

echo "── the wrapper forwards --check and any extra args to the main script ──"
mk_shim "$TMP/d"
WRAP_ARGS="$TMP/args" "$TMP/d/pin-keepalive-precheck.sh" --force >/dev/null 2>&1
has "$(cat "$TMP/args" 2>/dev/null)" "--check --force" "it prepends --check and preserves --force"

echo "── the sibling is resolved by the wrapper's own location, not the cwd ──"
: > "$TMP/args"
( cd / && WRAP_ARGS="$TMP/args" "$TMP/d/pin-keepalive-precheck.sh" >/dev/null 2>&1 )
has "$(cat "$TMP/args" 2>/dev/null)" "--check" "invoked from another cwd it still finds its sibling"

echo
printf '%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
