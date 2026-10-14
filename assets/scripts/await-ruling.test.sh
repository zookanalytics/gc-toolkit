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
#   * the pool outlives the route clear: the update that clears the route keys
#     records it as resling_target, so after an arm that is refused or whose
#     write fails, a re-run with no --target arms to the same pool;
#   * the claim: a bead open or in_progress under any of this session's names,
#     or under the owner --release-from names, is released with bd's
#     compare-and-swap unclaim before the arm, its session pins dropped, and
#     read back open and unassigned; any other claim is refused before the
#     edge, and a release that does not land leaves the claim and arms nothing;
#   * fail-closed: an unreadable bead, a parked bead, no visit, a refused edge,
#     a refused route clear, a refused arm, no pool to re-sling to;
#   * a closed work bead needs no wait and exits 0;
#   * usage errors;
#   * every metadata key the script writes is registered in lifecycle.toml;
#   * a situation that recurs after its visit closed moot: the real escalate.sh
#     files nothing inside its verdict window, so the wait cannot land, and
#     with the window off it files a fresh visit the wait lands on.
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
# records an edge unless $FAKE_DEP_FAIL is set. `bd update` applies --status,
# --assignee, --set-metadata, --unset-metadata and --append-notes; it refuses
# when the id is in $FAKE_UPD_FAIL, and refuses the arm's write (one that sets
# gc.dispatch_when_ready) when $FAKE_ARM_WRITE_FAIL is set. `bd unclaim <id>
# --if-assignee <a>` is bd's compare-and-swap release: it reopens the bead and
# clears its assignee only while the assignee is <a>, and refuses a closed or
# unassigned bead; $FAKE_UNCLAIM_FAIL refuses it outright, and
# $FAKE_UNCLAIM_NOOP answers success and changes nothing. `bd create` files an
# open bead from --title and --metadata and answers its id, so the real
# escalate.sh can run against the store.
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
    if [ -n "${FAKE_ARM_WRITE_FAIL:-}" ]; then
      for x in "$@"; do
        case "$x" in gc.dispatch_when_ready=*) echo "bd: store fault writing $id (stub)" >&2; exit 1 ;; esac
      done
    fi
    tmp="$S.n"; cp "$S" "$tmp"
    while [ $# -gt 0 ]; do
      case "$1" in
        --status=*|--assignee=*)
          f="${1%%=*}"; f="${f#--}"
          jq -c --arg id "$id" --arg f "$f" --arg v "${1#*=}" 'map(if .id == $id then .[$f] = $v else . end)' "$tmp" > "$tmp.x" && mv "$tmp.x" "$tmp" ;;
        --status|--assignee)
          f="${1#--}"; shift
          jq -c --arg id "$id" --arg f "$f" --arg v "$1" 'map(if .id == $id then .[$f] = $v else . end)' "$tmp" > "$tmp.x" && mv "$tmp.x" "$tmp" ;;
        --set-metadata) shift; jq -c --arg id "$id" --arg k "${1%%=*}" --arg v "${1#*=}" 'map(if .id == $id then .metadata[$k] = $v else . end)' "$tmp" > "$tmp.x" && mv "$tmp.x" "$tmp" ;;
        --unset-metadata) shift; jq -c --arg id "$id" --arg k "$1" 'map(if .id == $id then (.metadata |= del(.[$k])) else . end)' "$tmp" > "$tmp.x" && mv "$tmp.x" "$tmp" ;;
        --append-notes) shift; jq -c --arg id "$id" --arg n "$1" 'map(if .id == $id then .notes = ((.notes // "") + $n) else . end)' "$tmp" > "$tmp.x" && mv "$tmp.x" "$tmp" ;;
      esac
      shift
    done
    mv "$tmp" "$S"
    echo "✓ Updated issue: $id" ;;
  unclaim)
    id="${1:-}"; shift || true
    want=""
    while [ $# -gt 0 ]; do
      case "$1" in --if-assignee) shift; want="${1:-}" ;; --if-assignee=*) want="${1#*=}" ;; esac
      shift
    done
    [ -n "${FAKE_UNCLAIM_FAIL:-}" ] && { echo "Error unclaiming $id: store fault (stub)" >&2; exit 1; }
    row=$(jq -c --arg id "$id" '[ .[] | select(.id == $id) ] | .[0] // empty' "$S")
    [ -n "$row" ] || { echo "Error resolving $id (stub)" >&2; exit 1; }
    [ "$(printf '%s' "$row" | jq -r '.status // "open"')" = closed ] && { echo "Error unclaiming $id: cannot unclaim closed issue $id" >&2; exit 1; }
    held=$(printf '%s' "$row" | jq -r '.assignee // ""')
    if [ -z "$want" ] || [ "$held" != "$want" ]; then
      echo "Error unclaiming $id: assignee mismatch: $id is held by \"$held\", expected \"$want\"" >&2; exit 1
    fi
    if [ -z "${FAKE_UNCLAIM_NOOP:-}" ]; then
      jq -c --arg id "$id" 'map(if .id == $id then (.status = "open" | .assignee = "") else . end)' "$S" > "$S.x" && mv "$S.x" "$S"
    fi
    echo "✓ Unclaimed $id" ;;
  create)
    title=""; meta="{}"
    while [ $# -gt 0 ]; do
      case "$1" in
        --title) shift; title="${1:-}" ;;
        --metadata) shift; meta="${1:-}"; [ -n "$meta" ] || meta="{}" ;;
      esac
      shift || true
    done
    n=$(( $(jq 'length' "$S") + 1 ))
    jq -c --arg id "tk-new$n" --arg t "$title" --argjson m "$meta" \
      '. + [{"id": $id, "status": "open", "assignee": "", "title": $t, "metadata": $m}]' "$S" > "$S.x" && mv "$S.x" "$S"
    printf '{"id":"tk-new%s"}\n' "$n" ;;
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
field() { jq -r --arg i "$1" --arg f "$2" '(.[] | select(.id == $i) | .[$f]) // ""' "$FAKE_STORE"; }
blocks_rows() { grep -c '^tk-work|blocks|' "$FAKE_DEPS" | tr -d ' '; }
# claim <status> <assignee> — put the work bead in that claim, with the session
# pins a hook claim stamps.
claim() {
  jq -c --arg s "$1" --arg a "$2" 'map(if .id == "tk-work" then (.status = $s | .assignee = $a
    | .metadata["gc.session_id"] = "lx-pin" | .metadata["gc.session_name"] = "pool__polecat-lx-pin") else . end)' \
    "$FAKE_STORE" > "$FAKE_STORE.n" && mv "$FAKE_STORE.n" "$FAKE_STORE"
}
# The session the script runs in, under each of its four names.
SELF=(GC_SESSION_NAME=pool__polecat-lx-me GC_SESSION_ID=lx-me GC_AGENT=rig/rig.polecat GC_ALIAS=me-alias)

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

# ── 4b. a claim on the work bead is released before the arm ──────────────────
# The arm refuses an in_progress bead and reconcile never slings over an
# assignee, so the wait releases a claim no live worker holds: this session's,
# or the one --release-from names.
for who in pool__polecat-lx-me lx-me rig/rig.polecat me-alias; do
  for st in open in_progress; do
    reset; claim "$st" "$who"
    OUT=$(env "${SELF[@]}" "$SCRIPT" tk-work --key "$KEY" --formula mol-polecat-work 2>&1); RC=$?
    eq "$RC" 0 "$st under this session's '$who': the wait lands"
    eq "$(field tk-work status)|$(field tk-work assignee)" "open|" "$st under '$who': the bead is reopened and unassigned"
    eq "$(meta tk-work gc.dispatch_when_ready)" "$POOL" "$st under '$who': the re-sling is armed"
  done
done
eq "$(grep -c '^bd unclaim tk-work --if-assignee me-alias$' "$GC_LOG" | tr -d ' ')" 1 \
  "the release is a compare-and-swap on the assignee the script read"
eq "$(meta tk-work gc.session_id)|$(meta tk-work gc.session_name)" "<absent>|<absent>" \
  "the claim's session pins are dropped, so no orphan sweep restores a pool route from them"
eq "$(blocks_rows)" 1 "a released claim: one edge onto the visit"

# A crashed owner's claim is released only on the caller's word.
reset; claim in_progress lx-dead
OUT=$(env "${SELF[@]}" "$SCRIPT" tk-work --key "$KEY" --formula mol-polecat-work 2>&1); RC=$?
eq "$RC" 1 "in_progress under a foreign owner, no --release-from: exit 1"
has "$OUT" "under lx-dead, a claim neither in this session's name nor proven gone" "a foreign claim: says why it is kept"
eq "$(blocks_rows)" 0 "a foreign claim: refused before the edge"
eq "$(field tk-work status)|$(field tk-work assignee)" "in_progress|lx-dead" "a foreign claim: left as it was"
eq "$(meta tk-work gc.execution_routed_to)" "$POOL" "a foreign claim: the route keys are untouched"
OUT=$(env "${SELF[@]}" "$SCRIPT" tk-work --key "$KEY" --formula mol-polecat-work --release-from lx-other 2>&1); RC=$?
eq "$RC" 1 "--release-from naming a different owner: exit 1"
eq "$(field tk-work assignee)" "lx-dead" "--release-from naming a different owner: the claim is kept"
OUT=$(env "${SELF[@]}" "$SCRIPT" tk-work --key "$KEY" --formula mol-polecat-work --release-from lx-dead 2>&1); RC=$?
eq "$RC" 0 "--release-from naming the crashed owner: the wait lands"
eq "$(field tk-work status)|$(field tk-work assignee)" "open|" "--release-from: the crashed owner's claim is released"
eq "$(meta tk-work gc.dispatch_when_ready)" "$POOL" "--release-from: the re-sling is armed"
eq "$(grep -c '^tk-work|blocks|tk-v1$' "$FAKE_DEPS" | tr -d ' ')" 1 "--release-from: the work bead waits on the visit"

# An in_progress bead that names no assignee is reopened.
reset; claim in_progress ""
run tk-work --key "$KEY" --formula mol-polecat-work
eq "$RC" 0 "in_progress with no assignee: the wait lands"
eq "$(field tk-work status)" "open" "in_progress with no assignee: reopened"

# The release is checked, not assumed.
reset; claim in_progress lx-me
OUT=$(env "${SELF[@]}" FAKE_UNCLAIM_FAIL=1 "$SCRIPT" tk-work --key "$KEY" --formula mol-polecat-work 2>&1); RC=$?
eq "$RC" 1 "a refused release: exit 1"
has "$OUT" "the claim of lx-me on tk-work was not released" "a refused release: said"
eq "$(field tk-work status)|$(field tk-work assignee)" "in_progress|lx-me" "a refused release: the claim stands"
eq "$(meta tk-work gc.dispatch_when_ready)" "<absent>" "a refused release: nothing is armed"
eq "$(blocks_rows)" 1 "a refused release: the edge onto the visit stays"
OUT=$(env "${SELF[@]}" "$SCRIPT" tk-work --key "$KEY" --formula mol-polecat-work 2>&1); RC=$?
eq "$RC" 0 "after a refused release: a re-run lands the wait"
eq "$(field tk-work status)|$(field tk-work assignee)" "open|" "after a refused release: the re-run releases the claim"
eq "$(blocks_rows)" 1 "after a refused release: still one edge"
reset; claim open lx-me
OUT=$(env "${SELF[@]}" FAKE_UNCLAIM_NOOP=1 "$SCRIPT" tk-work --key "$KEY" --formula mol-polecat-work 2>&1); RC=$?
eq "$RC" 1 "a release that reports success and changes nothing: the read-back fails it"
has "$OUT" "assignee 'lx-me'" "the read-back names the assignee it found"

reset; claim in_progress lx-me
OUT=$(env "${SELF[@]}" "$SCRIPT" tk-work --key "$KEY" --formula mol-polecat-work --dry-run 2>&1); RC=$?
eq "$RC" 0 "dry run over a claim: exit 0"
has "$OUT" "after releasing its claim (status in_progress, assignee lx-me)" "dry run over a claim: names the release"
eq "$(field tk-work assignee)" "lx-me" "dry run over a claim: nothing released"

# ── 5. fail-closed ───────────────────────────────────────────────────────────
reset
jq -c 'map(if .id == "tk-work" then .status = "blocked" else . end)' "$FAKE_STORE" > "$FAKE_STORE.n" && mv "$FAKE_STORE.n" "$FAKE_STORE"
run tk-work --key "$KEY" --formula mol-polecat-work
eq "$RC" 1 "a parked (blocked) work bead cannot be armed: exit 1"
eq "$(blocks_rows)" 0 "a parked work bead: no edge"

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
eq "$(meta tk-work gc.execution_routed_to)" "$POOL" "a refused route clear: the pour's pool stamp is untouched"

# A refused arm after the route clear: the pool is kept on the bead, so the
# re-run after the refusal lifts arms with no --target.
reset
jq -c 'map(if .id == "tk-work" then .metadata["gc.dispatch_when_ready_slung"] = "slung@2026-10-12T00:00:00Z" else . end)' "$FAKE_STORE" > "$FAKE_STORE.n" && mv "$FAKE_STORE.n" "$FAKE_STORE"
run tk-work --key "$KEY" --formula mol-polecat-work
eq "$RC" 1 "an arm deferred-dispatch refuses (a prior sling not yet retired): exit 1"
has "$OUT" "the re-sling was not armed" "a refused arm: said, with deferred-dispatch's reason"
eq "$(blocks_rows)" 1 "a refused arm: the edge onto the visit stays"
eq "$(meta tk-work gc.execution_routed_to)" "" "a refused arm: the route keys are cleared"
eq "$(meta tk-work gc.dispatch_when_ready)" "<absent>" "a refused arm: nothing is armed"
eq "$(meta tk-work resling_target)" "$POOL" "a refused arm: the pool the cleared route named is kept as resling_target"
eq "$(grep -F -- '--set-metadata gc.execution_routed_to= ' "$GC_LOG" | grep -cF -- "--set-metadata resling_target=$POOL" | tr -d ' ')" 1 \
  "a refused arm: resling_target is written by the update that clears the route keys"
# The reconcile order lifts this refusal itself: it retires a proven marker by
# disarming the bead.
"$HERE/deferred-dispatch.sh" disarm tk-work --reason "the reconcile order retires a proven marker" >/dev/null 2>&1
eq "$(meta tk-work gc.dispatch_when_ready_slung)" "<absent>" "the refusal lifted: the marker is retired"
run tk-work --key "$KEY" --formula mol-polecat-work
eq "$RC" 0 "the refusal lifted: a re-run without --target exits 0"
eq "$(blocks_rows)" 1 "the refusal lifted: still one edge"
eq "$(meta tk-work gc.dispatch_when_ready)" "$POOL" "the refusal lifted: armed to the pool the cleared route named"
eq "$(meta tk-work gc.dispatch_when_ready_args)" '["--on","mol-polecat-work"]' "the refusal lifted: the arm pours mol-polecat-work"

# An arm whose write fails after the route clear: the pool the first run was
# given is kept, so a re-run without --target arms to it.
reset
OUT=$(FAKE_ARM_WRITE_FAIL=1 "$SCRIPT" tk-work --key "$KEY" --formula mol-polecat-work --target gc-toolkit/gc-toolkit.polecat-codex 2>&1); RC=$?
eq "$RC" 1 "an arm whose write fails: exit 1"
has "$OUT" "a re-run arms it to gc-toolkit/gc-toolkit.polecat-codex" "an arm whose write fails: says where a re-run arms it"
eq "$(meta tk-work gc.dispatch_when_ready)" "<absent>" "an arm whose write fails: nothing is armed"
eq "$(meta tk-work resling_target)" "gc-toolkit/gc-toolkit.polecat-codex" "an arm whose write fails: the --target pool is kept as resling_target"
run tk-work --key "$KEY" --formula mol-polecat-work
eq "$RC" 0 "after an arm whose write failed: a re-run without --target exits 0"
eq "$(blocks_rows)" 1 "after an arm whose write failed: still one edge"
eq "$(meta tk-work gc.dispatch_when_ready)" "gc-toolkit/gc-toolkit.polecat-codex" "after an arm whose write failed: armed to the pool the first run was given"
eq "$(meta tk-work gc.dispatch_when_ready_args)" '["--on","mol-polecat-work"]' "after an arm whose write failed: the arm pours mol-polecat-work"

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

# ── 7. every metadata key the script writes is registered ────────────────────
REGISTERED=$(sed -n '/^# The metadata-key registry/,$p' "$HERE/../../lifecycle/lifecycle.toml" \
  | sed 's/#.*//' | grep -oE '"[^"]+"' | tr -d '"' | sort -u)
WRITTEN=$(grep -oE -- '--set-metadata "?[A-Za-z_][A-Za-z0-9_.]*=' "$SCRIPT" | sed -E 's/^--set-metadata "?//; s/=$//' | sort -u)
has "$WRITTEN" "resling_target" "the extraction reads the script's writes"
UNREGISTERED=$(printf '%s\n' "$WRITTEN" | grep -Fxv -f <(printf '%s\n' "$REGISTERED") | tr '\n' ' ' | sed 's/ *$//') || true
eq "$UNREGISTERED" "" "every metadata key await-ruling.sh writes is registered in lifecycle.toml"

# ── 8. a situation that recurs after a person closed its visit moot ──────────
# Closing the visit is the "proceed" ruling, so the re-slung run can meet the
# same situation and escalate under the same key. escalate.sh answers a repeat
# inside its verdict window from the closed visit and files nothing, which
# leaves the wait no open visit to sit on. The decline arms that wait run
# escalate.sh with GC_ESCALATE_VERDICT_WINDOW=0. The real escalate.sh and the
# real await-ruling.sh run here against one store; the subject's store is left
# unproven so the visit files under GC_RIG, the store this stub serves.
printf '#!/usr/bin/env bash\nexit 3\n' > "$TMP/escalation-rig"; chmod +x "$TMP/escalation-rig"
escalate() { "$HERE/escalate.sh" --subject tk-work --key "$KEY" --message "Branch diverged; closing this visit re-slings tk-work" 2>&1; }
reset
CLOSED_AT=$(date -u -r $(( $(date +%s) - 3600 )) +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '@'$(( $(date +%s) - 3600 )) +%Y-%m-%dT%H:%M:%SZ)
jq -c --arg at "$CLOSED_AT" 'map(select(.id != "tk-v1")
  | if .id == "tk-v0" then (.closed_at = $at | .metadata["gc.outcome"] = "moot") else . end)' \
  "$FAKE_STORE" > "$FAKE_STORE.n" && mv "$FAKE_STORE.n" "$FAKE_STORE"
OUT=$(GC_RIG=gc-toolkit GC_ESCALATION_RIG_TOOL="$TMP/escalation-rig" escalate); RC=$?
eq "$RC" 0 "inside the window: escalate.sh exits 0"
has "$OUT" "was answered 'moot'" "inside the window: escalate.sh answers from the closed visit"
open_visits() { jq -r --arg k "$KEY" '[ .[] | select((.metadata.escalation_key // "") == $k and (.metadata["gc.continuation_group"] // "") == "tk-work" and (.status // "open") == "open") | .id ] | join(" ")' "$FAKE_STORE"; }
eq "$(open_visits)" "" \
  "inside the window: no open visit is filed"
run tk-work --key "$KEY" --formula mol-polecat-work
eq "$RC" 1 "inside the window: the wait has no open visit to sit on"
OUT=$(GC_RIG=gc-toolkit GC_ESCALATION_RIG_TOOL="$TMP/escalation-rig" GC_ESCALATE_VERDICT_WINDOW=0 escalate); RC=$?
eq "$RC" 0 "with the window off: escalate.sh files"
NEWV=$(open_visits)
[ -n "$NEWV" ] && [ "$NEWV" != tk-v0 ] && ok "with the window off: a fresh visit is open ($NEWV)" || bad "with the window off: no fresh open visit (got '$NEWV')"
run tk-work --key "$KEY" --formula mol-polecat-work
eq "$RC" 0 "with the window off: the wait lands"
eq "$(grep -c "^tk-work|blocks|$NEWV\$" "$FAKE_DEPS" | tr -d ' ')" 1 "with the window off: the work bead waits on the fresh visit"
eq "$(meta tk-work gc.dispatch_when_ready)" "$POOL" "with the window off: the re-sling is armed"

echo
echo "await-ruling.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
