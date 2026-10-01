#!/usr/bin/env bash
# Hermetic test that the deacon warrant-file block, after migrating onto the
# shared file-warrant.sh, still behaves the way it did: a session id in
# warrant.target, the role in the title, deacon as requester, the dog route —
# and it ledgers ONLY a fresh filing, never a dedup skip. Also proves a refusal
# (owner resolves to no live session) files nothing, ledgers nothing, and does
# not abort the sweep. Stubbed gc + ledger; no live city, Dolt or network.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TOML="$ROOT/formulas/mol-deacon-patrol.toml"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-deacon-warrant-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 (found '$2' in: $1)" ;; *) ok "$3" ;; esac; }

command -v jq >/dev/null 2>&1 || { echo "jq is required for this test" >&2; exit 1; }

extract() { awk -v n="$1" '
  $0 ~ "^[[:space:]]*# >>> " n "[[:space:]]*$" {inb=1; next}
  $0 ~ "^[[:space:]]*# <<< " n "[[:space:]]*$" {inb=0}
  inb' "$TOML"; }

# Substitute exactly as the materializer ({{binding_prefix}}) and the deacon
# (the <...> prose placeholders) fill them. <session> is fed a real session id,
# which is the deacon's documented, correct input.
render() { printf '%s\n' "$1" \
  | sed 's|{{binding_prefix}}|gc-toolkit.|g' \
  | sed 's|<session>|lx-wisp-dq|g' \
  | sed 's|<rig>/<role>|gc-toolkit/gc-toolkit.deacon|g' \
  | sed 's|<what is stale and for how long>|wisp stale 30m|g'; }

WARRANT="$(extract warrant-file)"
[ -n "$WARRANT" ] && ok "warrant-file block extracted" || bad "warrant-file block EMPTY — markers missing from $TOML"
has "$WARRANT" 'file-warrant.sh' "the block delegates to the shared filer"

# SUT scripts dir: the real filer beside a ledger stub that logs its argv.
RIGROOT="$TMP/rig"; mkdir -p "$RIGROOT/assets/scripts"
cp "$ROOT/assets/scripts/file-warrant.sh" "$RIGROOT/assets/scripts/"
chmod +x "$RIGROOT/assets/scripts/file-warrant.sh"
cat > "$RIGROOT/assets/scripts/gc-deacon-ledger.sh" <<'STUB'
#!/usr/bin/env bash
printf 'LEDGER %s\n' "$*" >> "${LEDGER_LOG:?}"
STUB
chmod +x "$RIGROOT/assets/scripts/gc-deacon-ledger.sh"

# A stateful gc stub: bd create writes the warrant into a JSON store both the
# dedup query and the post-create re-read read back.
BIN="$TMP/bin"; mkdir -p "$BIN"
export STUB_GC_LOG="$TMP/gc.log" STUB_STORE="$TMP/store.json" LEDGER_LOG="$TMP/ledger.log"
cat > "$BIN/gc" <<'STUB'
#!/usr/bin/env bash
set -u
printf '%s\n' "$*" >> "${STUB_GC_LOG:?}"
STORE="${STUB_STORE:?}"; [ -s "$STORE" ] || echo '[]' > "$STORE"
sub="${1:-}"; verb="${2:-}"
case "$sub $verb" in
  "session list")
    [ -n "${STUB_SESSIONS_FAIL:-}" ] && { echo "gc: session list unavailable" >&2; exit 1; }
    printf '%s\n' "${STUB_SESSIONS:-{\"sessions\":[]}}" ;;
  "bd list")
    shift 2 || true
    tv=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --metadata-field) shift; case "${1:-}" in warrant.target=*) tv="${1#warrant.target=}" ;; esac ;;
        --metadata-field=*) case "${1#--metadata-field=}" in warrant.target=*) tv="${1#*warrant.target=}" ;; esac ;;
      esac
      shift || true
    done
    jq -c --arg t "$tv" '[ .[] | select($t == "" or ((.metadata["warrant.target"] // "") == $t)) ]' "$STORE" ;;
  "bd create")
    shift 2 || true
    title=""; meta="{}"
    while [ $# -gt 0 ]; do
      case "$1" in
        --title=*) title="${1#--title=}" ;;
        --title) shift; title="${1:-}" ;;
        --metadata) shift; meta="${1:-}" ;;
        --metadata=*) meta="${1#--metadata=}" ;;
      esac
      shift || true
    done
    n=$(jq 'length' "$STORE"); nid="tk-w$((n + 1))"
    tmp="$(mktemp "${STORE%/*}/.gc-stub.XXXXXX")"
    jq -c --arg id "$nid" --arg t "$title" --argjson m "$meta" \
      '. + [{id: $id, status: "open", title: $t, metadata: $m}]' "$STORE" > "$tmp" && mv "$tmp" "$STORE"
    printf '{"id":"%s"}\n' "$nid" ;;
  *) echo "unexpected gc invocation: $*" >&2; exit 99 ;;
esac
STUB
chmod +x "$BIN/gc"
export PATH="$BIN:$PATH"
export GC_RIG_ROOT="$RIGROOT" GC_RIG=gc-toolkit
export STUB_SESSIONS='{"sessions":[{"id":"lx-wisp-dq","alias":"gc-toolkit/gc-toolkit.deacon","session_name":"gc-toolkit--gc-toolkit__deacon","state":"active"}]}'

render "$WARRANT" > "$TMP/warrant.sh"
bash -n "$TMP/warrant.sh" && ok "rendered deacon warrant block is valid bash" || bad "deacon warrant block failed bash -n"

reset() { echo '[]' > "$STUB_STORE"; }
# The block consumes the filer's stdout internally (FILED=$(...)) and speaks to
# the ledger and stderr, so its own stdout carries nothing to assert — discard it.
run() {
  : > "$STUB_GC_LOG"; : > "$LEDGER_LOG"
  bash "$TMP/warrant.sh" >/dev/null 2>"$TMP/err"; RC=$?
  ERR="$(cat "$TMP/err")"
  LOG="$(cat "$STUB_GC_LOG")"
  LEDGER="$(cat "$LEDGER_LOG")"
  META="$(grep -F 'bd create' "$STUB_GC_LOG" | sed 's/^.*--metadata //' | head -1)"
}
mget() { printf '%s' "$META" | jq -r --arg k "$1" '.[$k] // ""' 2>/dev/null; }

echo "# a fresh filing: the warrant the deacon files is unchanged, and it is ledgered"
reset
run
has "$LOG" 'bd create' "a warrant is filed"
eq "$(mget 'warrant.target')" "lx-wisp-dq" "warrant.target is the session id, as the deacon's correct pattern always had it"
has "$LOG" 'Stuck: gc-toolkit/gc-toolkit.deacon' "the role is what the title names"
eq "$(mget 'warrant.requester')" "deacon" "requester is deacon"
eq "$(mget 'gc.routed_to')" "gc-toolkit.dog" "routed at the dog, binding_prefix rendered"
has "$LEDGER" 'append warrant' "the fresh filing is ledgered"
has "$LEDGER" 'bead:tk-w1' "with the filed warrant id"

echo "# a repeat for the same session is not re-ledgered (ledger the filing, not the skip)"
# the store still holds tk-w1 for lx-wisp-dq from the previous run
run
hasnt "$LOG" 'bd create' "no second warrant is filed"
eq "$LEDGER" "" "and the skip writes no ledger line"

echo "# owner resolves to no live session: refuse, file nothing, ledger nothing, survive"
reset; export STUB_SESSIONS='{"sessions":[]}'
run
eq "$RC" 0 "the block survives the refusal rather than aborting the sweep"
hasnt "$LOG" 'bd create' "nothing is filed"
eq "$LEDGER" "" "nothing is ledgered"
has "$ERR" "escalate this wedged session" "and the block says to escalate instead"

echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ]
