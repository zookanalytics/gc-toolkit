#!/usr/bin/env bash
# converse-capability.test.sh — the shared converse-capability predicate
# (converse-capability.sh). rig_carries_converse reads the import-resolved roster
# `gc agent list --json` reports, keyed on rig NAME; it never globs a checkout.
#
# The regression this pins: a rig that obtains converse by IMPORTING
# the pack carries no agents/converse-* under its own checkout, yet the roster
# registers <rig>/gc-toolkit.converse. A checkout glob refuses every such rig; the
# roster affirms it. The predicate must agree with the roster — so a rig PRESENT
# in a readable roster is capable and a rig ABSENT from one is not, while an
# unreadable/malformed/empty roster fails open (a degraded data plane is not a
# dead zone).
#
# Hermetic: a stub `gc` on PATH serves `agent list` from a per-case roster; no
# live city, Dolt, or network. Each check runs in a subshell so the predicate's
# memoized roster never leaks between cases.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
LIB="$HERE/converse-capability.sh"

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n        %s\n' "$1" "$2"; }
# is <label> <got> <want>
is() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "got '$2', want '$3'"; fi; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/converse-cap.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"

# Stub gc: only `agent list` is consulted. $ROSTER is the JSON it prints.
# $ROSTER_FAIL makes the listing exit non-zero (gc could not answer). Every call
# appends a byte to $ROSTER_CALLS so the memoization case can count fetches.
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
if [ "$1 ${2:-}" = "agent list" ]; then
  printf 'x' >> "${ROSTER_CALLS:-/dev/null}"
  [ -n "${ROSTER_FAIL:-}" ] && { echo "agent list: data plane down" >&2; exit 1; }
  printf '%s' "${ROSTER:-}"
  exit 0
fi
exit 0
GC
chmod +x "$TMP/bin/gc"
export PATH="$TMP/bin:$PATH"
export ROSTER_CALLS="$TMP/roster_calls"
export ROSTER=""

[ -r "$LIB" ] || { echo "converse-capability.test: cannot read $LIB" >&2; exit 1; }
# shellcheck source=converse-capability.sh
. "$LIB" || { echo "converse-capability.test: cannot source $LIB" >&2; exit 1; }
command -v rig_carries_converse >/dev/null 2>&1 \
    || { echo "converse-capability.test: sourcing defined no rig_carries_converse" >&2; exit 1; }

# A roster registering converse (base + variants) for each named rig. Built the
# way `gc agent list --json` renders it: an object with an .agents array of
# {qualified_name} entries.
roster_converse_for() {
    jq -n --arg rigs "$*" '{agents:
        [ ($rigs | split(" ")[] | select(length > 0)) as $r
          | {qualified_name: ($r + "/gc-toolkit.converse")},
            {qualified_name: ($r + "/gc-toolkit.converse-opus")},
            {qualified_name: ($r + "/gc-toolkit.converse-codex")} ]}'
}

# cap <rig> -> "0" capable, "1" not. Runs in a subshell so the predicate's
# memoized roster is discarded between cases; $ROSTER is read fresh each case.
cap() ( if rig_carries_converse "$1"; then echo 0; else echo 1; fi )

# --- agrees with the roster ---------------------------------------------------

# The regression: an importer carries converse ONLY in the roster, never in its
# own checkout. The predicate takes a rig NAME and reads the roster, so a rig
# present there is capable regardless of any checkout.
export ROSTER="$(roster_converse_for gc-toolkit gascity signal-loom)"
is "an imported rig present in the roster is capable" "$(cap gascity)" 0
is "the pack-source rig is capable" "$(cap gc-toolkit)" 0

# A readable roster that does not register the rig is a real answer, not a
# degraded plane: the predicate must say NOT capable, never fail open here.
is "a rig absent from a readable roster is NOT capable" "$(cap shutupandlisten)" 1

# An HQ / city-store root carries no converse in the roster — correctly excluded.
export ROSTER="$(roster_converse_for gc-toolkit gascity)"
is "an HQ/city root absent from the roster is NOT capable" "$(cap loomington)" 1

# --- the match is converse-specific and variant-aware -------------------------

export ROSTER='{"agents":[{"qualified_name":"gc-toolkit/gc-toolkit.converse"}]}'
is "a base-only converse entry is capable" "$(cap gc-toolkit)" 0

export ROSTER='{"agents":[{"qualified_name":"gc-toolkit/gc-toolkit.converse-opus"}]}'
is "a model-variant-only converse entry is capable" "$(cap gc-toolkit)" 0

export ROSTER='{"agents":[{"qualified_name":"gc-toolkit/gc-toolkit.proactive"}]}'
is "a proactive-only rig is NOT converse-capable" "$(cap gc-toolkit)" 1

# The "/" in the key stops one rig name matching another it is a prefix of.
export ROSTER='{"agents":[{"qualified_name":"gc-toolkit-extra/gc-toolkit.converse"}]}'
is "a rig name that is a prefix of another is NOT matched" "$(cap gc-toolkit)" 1

# --- fail open on an unreadable roster ----------------------------------------

export ROSTER=""        # gc answered with nothing
is "an empty roster fails open (capable)" "$(cap gascity)" 0

export ROSTER="x"; export ROSTER_FAIL=1   # gc could not answer
is "a failed listing fails open (capable)" "$(cap gascity)" 0
unset ROSTER_FAIL

export ROSTER='{"not":"a roster"}'   # well-formed JSON, wrong shape
is "a malformed roster fails open (capable)" "$(cap gascity)" 0

export ROSTER='{"agents":"not-an-array"}'
is "a roster whose .agents is not an array fails open (capable)" "$(cap gascity)" 0

# --- the roster is fetched once per shell (picker loop pays one query) ---------

export ROSTER="$(roster_converse_for gc-toolkit gascity)"
: > "$ROSTER_CALLS"
( rig_carries_converse gc-toolkit; rig_carries_converse gascity; rig_carries_converse loomington ) >/dev/null 2>&1
is "three checks in one shell fetch the roster once" "$(wc -c < "$ROSTER_CALLS" | tr -d ' ')" 1

echo
echo "converse-capability: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
