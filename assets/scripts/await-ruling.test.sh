#!/usr/bin/env bash
# Hermetic test for assets/scripts/await-ruling.sh.
#
# The constraint: a declined run is cancelled, and nothing resumes a cancelled
# run, so the wait for a person's ruling sits on the WORK bead: a `blocks` edge
# onto the visit that asks for the ruling, and a deferred-dispatch arm that
# re-slings the work when the visit closes. A cancel with no recorded wait would
# leave the work open, unrouted and unarmed, so every way the wait can fail to
# land exits non-zero.
#
# What is exercised here:
#   * the edge: <work> is blocked by the open visit filed under (work, key), and
#     a visit under another key, another subject or a closed one is not taken;
#   * the arm: the real deferred-dispatch.sh records a re-sling to the pool the
#     last pour ran on, --on <formula>, after the route keys a pour leaves are
#     cleared (the arm refuses a routed bead);
#   * re-running converges: an edge and an arm already in place count as landed
#     and no second edge is written;
#   * fail-closed: an unreadable bead, a non-open bead, no visit, a refused edge,
#     a refused route clear, a refused arm, no pool to re-sling to;
#   * a closed work bead needs no wait and exits 0;
#   * usage errors.
#
# No live city, Dolt, network, or beads: a tmpdir, a `gc` stub over a JSON store
# and an edge file, and the scripts themselves.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/await-ruling.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-await-ruling-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has()   { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 (found '$2' in: $1)" ;; *) ok "$3" ;; esac; }

command -v jq >/dev/null 2>&1 || { echo "jq is required for this test" >&2; exit 1; }
[ -x "$SCRIPT" ] || { echo "not executable: $SCRIPT" >&2; exit 1; }

unset "${!GC_@}" "${!BEADS_@}" 2>/dev/null || true
mkdir -p "$TMP/bin"

# --- gc stub over a JSON store and an edge file ("A|type|B": A depends on B). --
# `bd show` answers an array, or an error object for an unknown id. `bd list`
# filters on --status= and every --metadata-field k=v. `bd dep list <id>` answers
# the beads <id> depends on, each with dependency_type and status. `bd dep add`
# records an edge unless $FAKE_DEP_FAIL is set. `bd update` applies
# --set-metadata, --unset-metadata and --append-notes; it refuses when the id is
# in $FAKE_UPD_FAIL.
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/gc" <<'GC'
set -u
S="${FAKE_STORE:?}"; D="${FAKE_DEPS:?}"
printf '%s\n' "$*" >> "${GC_LOG:?}"
[ "${1:-}" = "bd" ] || { echo "gc stub: unsupported '$*'" >&2; exit 2; }
shift
[ "${1:-}" = "--db" ] && shift 2
verb="${1:-}"; shift || true
case "$verb" in
  show)
    [ -n "${FAKE_SHOW_FAIL:-}" ] && { echo "bd: store down (stub)" >&2; exit 1; }
    out=$(jq -c --arg id "${1:-}" '[ .[] | select(.id == $id) ]' "$S")
    if [ "$out" = "[]" ]; then printf '{"error":"no issue found matching %s"}\n' "${1:-}"; else printf '%s\n' "$out"; fi ;;
  list)
    st=""; mfs=()
    while [ $# -gt 0 ]; do
      case "$1" in
        --status=*) st="${1#--status=}" ;;
        --metadata-field) shift; mfs+=("$1") ;;
      esac
      shift
    done
    filter='.'
    for kv in ${mfs[@]+"${mfs[@]}"}; do
      filter="$filter | select((.metadata[\"${kv%%=*}\"] // \"\") == \"${kv#*=}\")"
    done
    jq -c --arg st "$st" "[ .[] | (.status // \"open\") as \$bst | select(\$st == \"\" or ((\$st | split(\",\")) | index(\$bst))) | $filter ]" "$S" ;;
  dep)
    sub="${1:-}"; shift || true
    case "$sub" in
      list)
        id="${1:-}"
        rows=$(awk -F'|' -v a="$id" '$1 == a { print $2 "|" $3 }' "$D")
        printf '%s\n' "$rows" | jq -R -s -c --slurpfile s "$S" '
          split("\n") | map(select(length > 0) | split("|")) as $e
          | [ $e[] | . as [$t, $b] | ($s[0][] | select(.id == $b)) as $row
              | {id: $b, dependency_type: $t, status: ($row.status // "open")} ]' ;;
      add)
        [ -n "${FAKE_DEP_FAIL:-}" ] && { echo "bd: refused (stub)" >&2; exit 1; }
        a="${1:-}"; b="${2:-}"; t="blocks"
        shift 2 || true
        for x in "$@"; do case "$x" in --type=*) t="${x#--type=}" ;; esac; done
        printf '%s|%s|%s\n' "$a" "$t" "$b" >> "$D" ;;
      *) exit 2 ;;
    esac ;;
  update)
    id="${1:-}"; shift || true
    case " ${FAKE_UPD_FAIL:-} " in *" $id "*) echo "bd: cannot update $id (stub)" >&2; exit 1 ;; esac
    tmp="$S.n"; cp "$S" "$tmp"
    while [ $# -gt 0 ]; do
      case "$1" in
        --set-metadata) shift; jq -c --arg id "$id" --arg k "${1%%=*}" --arg v "${1#*=}" 'map(if .id == $id then .metadata[$k] = $v else . end)' "$tmp" > "$tmp.x" && mv "$tmp.x" "$tmp" ;;
        --unset-metadata) shift; jq -c --arg id "$id" --arg k "$1" 'map(if .id == $id then (.metadata |= del(.[$k])) else . end)' "$tmp" > "$tmp.x" && mv "$tmp.x" "$tmp" ;;
        --append-notes) shift; jq -c --arg id "$id" --arg n "$1" 'map(if .id == $id then .notes = ((.notes // "") + $n) else . end)' "$tmp" > "$tmp.x" && mv "$tmp.x" "$tmp" ;;
      esac
      shift
    done
    mv "$tmp" "$S"
    echo "✓ Updated issue: $id" ;;
  *) echo "gc stub: unsupported 'bd $verb'" >&2; exit 2 ;;
esac
exit 0
GC
chmod +x "$TMP/bin/gc"
export PATH="$TMP/bin:$PATH"
export FAKE_STORE="$TMP/store.json" FAKE_DEPS="$TMP/deps.txt" GC_LOG="$TMP/gc.log"

POOL="gc-toolkit/gc-toolkit.polecat"
KEY="polecat-branch-divergence"
reset() {
  cat > "$FAKE_STORE" <<JSON
[
 {"id":"tk-work","status":"open","assignee":"","metadata":{"gc.execution_routed_to":"$POOL","branch":"polecat/tk-work"}},
 {"id":"tk-v1","status":"open","assignee":"","metadata":{"task_kind":"visit","escalation_key":"$KEY","gc.continuation_group":"tk-work","gc.routed_to":"human"}},
 {"id":"tk-v0","status":"closed","assignee":"","metadata":{"task_kind":"visit","escalation_key":"$KEY","gc.continuation_group":"tk-work"}},
 {"id":"tk-vx","status":"open","assignee":"","metadata":{"task_kind":"visit","escalation_key":"other-key","gc.continuation_group":"tk-work"}},
 {"id":"tk-vy","status":"open","assignee":"","metadata":{"task_kind":"visit","escalation_key":"$KEY","gc.continuation_group":"tk-elsewhere"}}
]
JSON
  printf 'tk-v1|tracks|tk-work\ntk-v0|tracks|tk-work\n' > "$FAKE_DEPS"
  : > "$GC_LOG"
}
run() { OUT=$("$SCRIPT" "$@" 2>&1); RC=$?; }
meta() { jq -r --arg i "$1" --arg k "$2" '(.[] | select(.id == $i) | .metadata[$k]) // "<absent>"' "$FAKE_STORE"; }
blocks_rows() { grep -c '^tk-work|blocks|' "$FAKE_DEPS" | tr -d ' '; }

# ── 1. the wait lands: edge onto the right visit, arm to the last pour's pool ─
reset
run tk-work --key "$KEY" --formula mol-polecat-work
eq "$RC" 0 "the wait lands"
has "$OUT" "tk-work waits on visit tk-v1 ($KEY); closing the visit re-slings it to $POOL --on mol-polecat-work" "the result names the visit, the pool and the formula"
eq "$(grep -c '^tk-work|blocks|tk-v1$' "$FAKE_DEPS" | tr -d ' ')" 1 "the work bead is blocked by the open visit under its key"
eq "$(blocks_rows)" 1 "no edge onto a closed visit, another key's or another subject's"
eq "$(meta tk-work gc.dispatch_when_ready)" "$POOL" "the re-sling is armed to the pool the last pour ran on"
eq "$(meta tk-work gc.dispatch_when_ready_args)" '["--on","mol-polecat-work"]' "the re-sling pours the named formula"
has "$(meta tk-work gc.dispatch_when_ready_reason)" "tk-v1" "the arm's reason names the visit"
eq "$(meta tk-work gc.execution_routed_to)" "" "the pour's route stamp is cleared, so the bead advertises no finished pour"
eq "$(meta tk-work gc.routed_to)" "" "the work bead is unrouted"
eq "$(meta tk-work branch)" "polecat/tk-work" "the branch record is kept for the re-sling to resume"

# ── 2. re-running converges ──────────────────────────────────────────────────
run tk-work --key "$KEY" --formula mol-polecat-work
eq "$RC" 0 "a re-run with the wait in place exits 0, though the first run cleared the pour's pool stamp"
eq "$(blocks_rows)" 1 "a re-run writes no second edge"
eq "$(meta tk-work gc.dispatch_when_ready)" "$POOL" "a re-run re-arms to the pool the first run armed"
reset
run tk-work --key "$KEY" --formula mol-polecat-work
run tk-work --key "$KEY" --formula mol-polecat-work --target "$POOL"
eq "$RC" 0 "a re-run naming the pool re-arms in place"
eq "$(meta tk-work gc.dispatch_when_ready)" "$POOL" "the re-arm holds the same target"
eq "$(blocks_rows)" 1 "the re-arm writes no second edge"

# ── 3. --target wins over the pour's stamp ───────────────────────────────────
reset
run tk-work --key "$KEY" --formula mol-polecat-work --target gc-toolkit/gc-toolkit.polecat-codex
eq "$RC" 0 "--target: the wait lands"
eq "$(meta tk-work gc.dispatch_when_ready)" "gc-toolkit/gc-toolkit.polecat-codex" "--target: armed to the named pool"

# ── 3b. --subject: a visit filed on another bead, such as a rework's anchor ──
reset
jq -c '. + [{"id":"tk-va","status":"open","assignee":"","metadata":{"task_kind":"visit","escalation_key":"bring-current-question.tk-work","gc.continuation_group":"tk-anchor"}}]' "$FAKE_STORE" > "$FAKE_STORE.n" && mv "$FAKE_STORE.n" "$FAKE_STORE"
run tk-work --key bring-current-question.tk-work --formula mol-polecat-work
eq "$RC" 1 "--subject absent: the visit on the anchor is not the work bead's, so no wait"
run tk-work --key bring-current-question.tk-work --subject tk-anchor --formula mol-polecat-work
eq "$RC" 0 "--subject: the wait lands on the visit filed on the named bead"
eq "$(grep -c '^tk-work|blocks|tk-va$' "$FAKE_DEPS" | tr -d ' ')" 1 "--subject: the WORK bead, not the subject, is blocked by the visit"
eq "$(meta tk-work gc.dispatch_when_ready)" "$POOL" "--subject: the work bead is armed"

# ── 4. a closed work bead needs no wait ──────────────────────────────────────
reset
jq -c 'map(if .id == "tk-work" then .status = "closed" else . end)' "$FAKE_STORE" > "$FAKE_STORE.n" && mv "$FAKE_STORE.n" "$FAKE_STORE"
run tk-work --key "$KEY" --formula mol-polecat-work
eq "$RC" 0 "a closed work bead: exit 0"
has "$OUT" "is closed" "a closed work bead: says why nothing waits"
eq "$(blocks_rows)" 0 "a closed work bead: no edge"

# ── 5. fail-closed ───────────────────────────────────────────────────────────
reset
jq -c 'map(if .id == "tk-work" then .status = "blocked" else . end)' "$FAKE_STORE" > "$FAKE_STORE.n" && mv "$FAKE_STORE.n" "$FAKE_STORE"
run tk-work --key "$KEY" --formula mol-polecat-work
eq "$RC" 1 "a non-open work bead cannot be armed: exit 1"
eq "$(blocks_rows)" 0 "a non-open work bead: no edge"

reset
run tk-work --key no-such-key --formula mol-polecat-work
eq "$RC" 1 "no open visit under the key: exit 1"
has "$OUT" "file it with escalate.sh first" "no visit: says what to do"
eq "$(meta tk-work gc.dispatch_when_ready)" "<absent>" "no visit: nothing armed"

reset
OUT=$(FAKE_DEP_FAIL=1 "$SCRIPT" tk-work --key "$KEY" --formula mol-polecat-work 2>&1); RC=$?
eq "$RC" 1 "a refused edge: exit 1"
eq "$(meta tk-work gc.dispatch_when_ready)" "<absent>" "a refused edge: nothing armed after it"

reset
OUT=$(FAKE_UPD_FAIL=tk-work "$SCRIPT" tk-work --key "$KEY" --formula mol-polecat-work 2>&1); RC=$?
eq "$RC" 1 "a refused route clear: exit 1"
has "$OUT" "could not clear the route keys" "a refused route clear: said"

reset
jq -c 'map(if .id == "tk-work" then .metadata["gc.dispatch_when_ready_slung"] = "slung@2026-10-12T00:00:00Z" else . end)' "$FAKE_STORE" > "$FAKE_STORE.n" && mv "$FAKE_STORE.n" "$FAKE_STORE"
run tk-work --key "$KEY" --formula mol-polecat-work
eq "$RC" 1 "an arm deferred-dispatch refuses (a prior sling not yet retired): exit 1"
has "$OUT" "the re-sling was not armed" "a refused arm: said, with deferred-dispatch's reason"

reset
jq -c 'map(if .id == "tk-work" then (.metadata |= del(.["gc.execution_routed_to"])) else . end)' "$FAKE_STORE" > "$FAKE_STORE.n" && mv "$FAKE_STORE.n" "$FAKE_STORE"
run tk-work --key "$KEY" --formula mol-polecat-work
eq "$RC" 1 "no pool to re-sling to: exit 1"
eq "$(blocks_rows)" 0 "no pool: no edge, since nothing could re-sling it"

reset
OUT=$(FAKE_SHOW_FAIL=1 "$SCRIPT" tk-work --key "$KEY" --formula mol-polecat-work 2>&1); RC=$?
eq "$RC" 1 "an unreadable work bead: exit 1"
run tk-nosuch --key "$KEY" --formula mol-polecat-work
eq "$RC" 1 "an unknown work bead: exit 1"

# ── 6. dry run and usage ─────────────────────────────────────────────────────
reset
run tk-work --key "$KEY" --formula mol-polecat-work --dry-run
eq "$RC" 0 "dry run: exit 0"
has "$OUT" "DRY RUN: tk-work would wait on visit tk-v1" "dry run: names the visit"
eq "$(blocks_rows)" 0 "dry run: no edge"
eq "$(meta tk-work gc.dispatch_when_ready)" "<absent>" "dry run: no arm"

for args in "--key $KEY --formula mol-polecat-work" "tk-work --formula mol-polecat-work" "tk-work --key $KEY" "tk-work --key" "tk-work tk-other --key $KEY --formula f" "tk-work --key {{key}} --formula f" "tk-work --key $KEY --formula f --bogus"; do
  # shellcheck disable=SC2086  # each case is a word list on purpose
  run $args
  eq "$RC" 2 "usage refused: $args"
done

echo
echo "await-ruling.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
