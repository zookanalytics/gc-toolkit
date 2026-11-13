#!/usr/bin/env bash
# Hermetic test for doctor/check-armed-dispatch-owed. Stub gc/bd only; no live
# city, Dolt, or network. The check reads each store's arms from the start's
# dry run, `gctk bead start-armed --dry-run`, which the suite builds from this
# checkout and runs over the stub stores. Covers: the OWED finding (an arm the
# next pass would start, whose own blocks edges closed long ago, that never
# dispatched, and an arm nothing holds whose formula the start cannot resolve,
# named with why), the STRANDED finding (armed at a non-open status, or with a
# record that does not decode, whatever its age), the narrowing
# exemptions (still waiting on its own open blocker; dispatchable only
# recently, within the order's window; armed only recently, after its blockers
# closed; delivered via merge_result; closed; assigned; held by a hold label;
# capped at the configured sling-failure cap, which the start asks a person
# about; a wait edge into another store, which the start holds), the
# fail-closed probes (an unreadable armed listing, one that is not a JSON array,
# a hold walk that cannot read, an unreadable rig list, a scan that cannot
# report, no scratch directory), the stderr each failed read reports, the hold,
# as the start reads it over the stub stores (an arm a park holds, on its epic
# or two levels up, or whose epic waits on a task or on a human gate, is not
# owed, and neither is one in flight under a park; a park or a human gate
# released just now dates the window, and a park released before the arm was
# armed does not; a pinned blocker holds nothing, a human gate included, as a
# closed one does, while one in progress, blocked, deferred or hooked still
# holds; an ancestor the store does not return, and a blocker on such an
# ancestor, hold nothing; an arm with a waits-for edge of its own is held and
# noted unjudged), the suspended-rig skip, and the quiet path (no armed beads).
# One dry run reads a store, so a store costs a fixed number of queries. The
# stores are scanned at once, no more of them than the fan-out cap, each
# store's read kept apart from the others', and reported in rig order, and the
# rig and order registries are read at once. The cases that assert those
# mechanisms assert them directly, not just the findings.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$HERE/run.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-check-armed-dispatch-owed-test.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 (found '$2' in: $1)" ;; *) ok "$3" ;; esac; }
# line_of <text> <needle> — the number of the first line of <text> holding <needle>
line_of() { printf '%s\n' "$1" | grep -n -F -- "$2" | head -1 | cut -d: -f1; }

mkdir -p "$TMP/bin" "$TMP/stores" "$TMP/alpha" "$TMP/pack/orders" "$TMP/empty-city" "$TMP/tmpdir"
# The interval the owed window takes from the pack, as orders/deferred-dispatch.toml declares it.
printf '[order]\ntrigger = "cooldown"\ninterval = "5m"\nscope = "rig"\n' > "$TMP/pack/orders/deferred-dispatch.toml"
cat > "$TMP/rigs.json" <<EOF
{"rigs":[{"name":"alpha","path":"$TMP/alpha"}]}
EOF
# rigs_of <name>... — a rig list naming those stores, in that order
rigs_of() {
    local r sep="" body=""
    for r in "$@"; do
        mkdir -p "$TMP/$r"
        body="$body$sep$(jq -nc --arg n "$r" --arg p "$TMP/$r" '{name:$n,path:$p}')"; sep=","
    done
    printf '{"rigs":[%s]}\n' "$body" > "$TMP/rigs-multi.json"
}

{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/gc" <<'GC'
# REG_BARRIER makes each registry read wait until both have started, and fail
# once it has waited 20s. Read one after the other, the first never gets past.
reg_barrier() {
  [ -n "${REG_BARRIER:-}" ] || return 0
  : > "$REG_BARRIER/$1"
  waited=0
  while [ ! -e "$REG_BARRIER/rigs" ] || [ ! -e "$REG_BARRIER/orders" ]; do
    [ "$waited" -lt 200 ] || exit 3
    sleep 0.1; waited=$((waited + 1))
  done
}
# A read the gctk under test makes answers from the store its --db names: the
# armed rows, the edge fixture and the rows the walk reads, merged, through the
# seam holds-store.stub.sh keeps. BD_FAIL_BLOCKERS fails each such read in its
# store, BD_FAIL_IDS one naming any of its ids, CALL_LOG gets "<store> holds
# <args>", and BD_ID_BARRIER_DIR with BD_ID_BARRIER_N holds the first read of
# each store until that many stores have started theirs.
if [ -n "${HOLDS_STUB_READ:-}" ] && [ "$1" = bd ]; then
  shift
  db=""; [ "${1:-}" = --db ] && db="${2:-}"
  name=$(basename "$(dirname "$db")")
  bd_die() { [ -n "${BD_ERR:-}" ] && printf '%s\n' "$BD_ERR" >&2; exit 3; }
  # The armed listing the dry run starts from: the store's own listing, which
  # the listing hooks below act on.
  case " $* " in
    *" list "*"--has-metadata-key gc.dispatch_when_ready "*)
      [ -n "${CALL_LOG:-}" ] && printf '%s list-armed %s\n' "$name" "$*" >> "$CALL_LOG"
      if [ -n "${INFLIGHT:-}" ]; then
        mkdir "${INFLIGHT:?}/${name:?}"; ls "$INFLIGHT" | wc -l | tr -d ' ' >> "$INFLIGHT.peaks"
        sleep 1; rmdir "${INFLIGHT:?}/${name:?}"
      fi
      if [ -n "${BD_BARRIER_DIR:-}" ]; then
        : > "$BD_BARRIER_DIR/$name"
        waited=0
        while started=("$BD_BARRIER_DIR"/*); [ "${#started[@]}" -lt "$BD_BARRIER_N" ]; do
          [ "$waited" -lt 200 ] || exit 3
          sleep 0.1; waited=$((waited + 1))
        done
      fi
      [ "$name" = "${BD_SLOW_STORE:-}" ] && sleep "$BD_SLOW_SECS"
      [ "$name" = "${BD_REAP_SCAN_AT:-}" ] && rm -rf "${TMPDIR:?}"/gctk-check-armed-dispatch-owed.*
      [ "$name" = "${BD_FAIL_LIST:-}" ] && bd_die
      [ "$name" = "${BD_BLANK_LIST:-}" ] && { printf '  '; exit 0; } ;;
    *) [ -n "${CALL_LOG:-}" ] && printf '%s holds %s\n' "$name" "$*" >> "$CALL_LOG" ;;
  esac
  if [ -n "${BD_ID_BARRIER_DIR:-}" ] && [ ! -e "$BD_ID_BARRIER_DIR/$name" ]; then
    : > "$BD_ID_BARRIER_DIR/$name"
    waited=0
    while started=("$BD_ID_BARRIER_DIR"/*); [ "${#started[@]}" -lt "$BD_ID_BARRIER_N" ]; do
      [ "$waited" -lt 200 ] || exit 3
      sleep 0.1; waited=$((waited + 1))
    done
  fi
  [ "$name" = "${BD_FAIL_BLOCKERS:-}" ] && bd_die
  for fid in ${BD_FAIL_IDS:-}; do case " $* " in *"$fid"*) bd_die ;; esac; done
  merged="$STORES/$name.holds-store.json"
  a="$STORES/$name.armed.json"; b="$STORES/$name.blockers.json"; e="$STORES/$name.edges.json"
  jq -n --slurpfile a "$( [ -f "$a" ] && echo "$a" || echo /dev/null )" \
        --slurpfile b "$( [ -f "$b" ] && echo "$b" || echo /dev/null )" \
        --slurpfile e "$( [ -f "$e" ] && echo "$e" || echo /dev/null )" '
    ($e[0] // []) as $E
    | (($a[0] // []) + ($b[0] // [])) | unique_by(.id)
    | map(. as $r | if has("dependencies") then . else .dependencies = [ $E[] | select(.issue_id == $r.id) ] end)' > "$merged"
  HOLDS_STORE="$merged" "${HOLDS_STUB:?}" answer "$@"; rc=$?
  case " $* " in *" list "*"--has-metadata-key gc.dispatch_when_ready "*) printf '%s\n' "$name" >> "${BD_DONE:-/dev/null}" ;; esac
  exit "$rc"
fi
case "$1 $2" in
  "rig list") reg_barrier rigs; rc="${RIGS_RC:-0}"
    [ "$rc" -eq 0 ] || { [ -n "${RIGS_ERR:-}" ] && printf '%s\n' "$RIGS_ERR" >&2; exit "$rc"; }
    cat "$RIGS_JSON" ;;
  # The order registry, for the cadence window. With no ORDERS_JSON it answers
  # nothing, the shape of a registry that did not read, and ORDERS_ERR is what
  # it says on stderr.
  "order list") reg_barrier orders; [ -n "${ORDERS_ERR:-}" ] && printf '%s\n' "$ORDERS_ERR" >&2
    [ -n "${ORDERS_JSON:-}" ] && cat "$ORDERS_JSON"; exit 0 ;;
  # Like real gc, a bd list, ready, search or show first names the store that
  # answers it on stderr, before bd runs and whether or not the read fails.
  "bd list"|"bd ready"|"bd search"|"bd show")
    shift; echo 'gc bd: answering from the rig "stub" store' >&2; VIA_GC_BD=1 exec "$(dirname "$0")/bd" "$@" ;;
  "bd "*)     shift; VIA_GC_BD=1 exec "$(dirname "$0")/bd" "$@" ;;
  *) exit 0 ;;
esac
GC
# The check's own reads are the rig and order registries. Each store is read by
# the start's dry run, whose reads the gc stub answers through the seam
# holds-store.stub.sh keeps, from the store its --db names: the armed rows, the
# edge fixture and the rows the walk reads, merged.
#   * The armed listing the dry run starts from (`bd list --has-metadata-key
#     gc.dispatch_when_ready`): BD_FAIL_LIST fails it, and BD_BLANK_LIST answers
#     whitespace at rc 0. BD_BARRIER_DIR and BD_BARRIER_N make each listing wait
#     until N have started (failing after 20s), BD_SLOW_STORE and BD_SLOW_SECS
#     slow one store, BD_REAP_SCAN_AT removes the check's scratch from under it
#     as a scratch reaper would, and BD_DONE gets the store's name once its
#     listing has answered. With INFLIGHT set, each listing marks its store in
#     flight for a second and appends how many stores were then in flight to
#     INFLIGHT.peaks.
#   * Every other read the dry run makes: BD_FAIL_BLOCKERS fails each such read
#     in its store, the listing included, BD_FAIL_IDS one naming any of its ids,
#     and BD_ID_BARRIER_DIR with BD_ID_BARRIER_N holds the first read of each
#     store until that many stores have started theirs.
# CALL_LOG, when set, gets one line per read ("<store> list-armed <args>" for the
# listing, "<store> holds <args>" for the rest), so a case can assert what a
# store's scan read. A failed read prints BD_ERR on stderr when set. The bd stub
# below answers any read the check would make itself, which none should.
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/bd" <<'BD'
[ -n "${VIA_GC_BD:-}" ] || { echo "stub bd: called directly, not through gc bd" >&2; exit 127; }
sub="$1"; shift
db=""; id_csv=""; prev=""; inc_gates=false; inc_infra=false; inc_templates=false
valueflag() { case "$1" in --db|--id|--limit|--actor|--type|--direction|--database|--max-rows|--offset|--has-metadata-key) return 0;; *) return 1;; esac; }
for a in "$@"; do
  if valueflag "$prev"; then
    case "$prev" in --db) db="$a" ;; --id) id_csv="$a" ;; esac
    prev="$a"; continue
  fi
  case "$a" in
    --include-gates) inc_gates=true ;;
    --include-infra) inc_infra=true ;;
    --include-templates) inc_templates=true ;;
  esac
  prev="$a"
done
name=$(basename "$(dirname "$db")")
bd_die() { [ -n "${BD_ERR:-}" ] && printf '%s\n' "$BD_ERR" >&2; exit 3; }
read="$sub"
if [ "$sub" = "list" ]; then
  if [ -n "$id_csv" ]; then read="list-id"; else read="list-armed"; fi
fi
[ -n "${CALL_LOG:-}" ] && printf '%s %s %s\n' "$name" "$read" "$*" >> "$CALL_LOG"
case "$read" in
  list-id)
    if [ -n "${BD_ID_BARRIER_DIR:-}" ]; then
      : > "$BD_ID_BARRIER_DIR/$name"
      waited=0
      while set -- "$BD_ID_BARRIER_DIR"/*; [ "$#" -lt "$BD_ID_BARRIER_N" ]; do
        [ "$waited" -lt 200 ] || exit 3
        sleep 0.1; waited=$((waited + 1))
      done
    fi
    [ "$name" = "${BD_FAIL_BLOCKERS:-}" ] && bd_die
    for fid in ${BD_FAIL_IDS:-}; do
      case ",$id_csv," in *",$fid,"*) bd_die ;; esac
    done
    f="$STORES/$name.blockers.json"
    if [ -f "$f" ]; then
      # Model bd's default hiding: a gate/infra/template blocker is returned
      # only when the matching --include flag was passed.
      want=$(printf '%s' "$id_csv" | tr ',' '\n' | jq -R . | jq -sc .)
      jq -c --argjson want "$want" --argjson ig "$inc_gates" --argjson ii "$inc_infra" --argjson it "$inc_templates" '
        [ .[]
          | select(.id as $i | $want | index($i))
          | select( (.issue_type // "task") as $t
                    | if   $t == "gate"                                     then $ig
                      elif ($t == "agent" or $t == "role" or $t == "message") then $ii
                      elif $t == "template"                                 then $it
                      else true end ) ]' "$f"
    else printf '[]'; fi ;;
  list-armed)
    if [ -n "${INFLIGHT:-}" ]; then
      mkdir "$INFLIGHT/$name"; ls "$INFLIGHT" | wc -l | tr -d ' ' >> "$INFLIGHT.peaks"
      sleep 1; rmdir "$INFLIGHT/$name"
    fi
    if [ -n "${BD_BARRIER_DIR:-}" ]; then
      : > "$BD_BARRIER_DIR/$name"
      waited=0
      while set -- "$BD_BARRIER_DIR"/*; [ "$#" -lt "$BD_BARRIER_N" ]; do
        [ "$waited" -lt 200 ] || exit 3
        sleep 0.1; waited=$((waited + 1))
      done
    fi
    [ "$name" = "${BD_SLOW_STORE:-}" ] && sleep "$BD_SLOW_SECS"
    [ "$name" = "${BD_REAP_SCAN_AT:-}" ] && rm -rf "${TMPDIR:?}"/gctk-check-armed-dispatch-owed.*
    [ "$name" = "${BD_FAIL_LIST:-}" ] && bd_die
    if [ "$name" = "${BD_BLANK_LIST:-}" ]; then
      printf '  '
    else
      f="$STORES/$name.armed.json"; e="$STORES/$name.edges.json"
      if [ ! -f "$f" ]; then printf '[]'
      elif [ -f "$e" ]; then
        jq -c --slurpfile e "$e" 'map(. as $b | if has("dependencies") then . else .dependencies = [ $e[0][] | select(.issue_id == $b.id) ] end)' "$f"
      else cat "$f"; fi
    fi
    printf '%s\n' "$name" >> "${BD_DONE:-/dev/null}" ;;
  dep)
    echo "stub bd: bd dep is no read the check makes" >&2; exit 3 ;;
  *) printf '[]'; exit 0 ;;
esac
BD
chmod +x "$TMP/bin/gc" "$TMP/bin/bd"
export PATH="$TMP/bin:$PATH" STORES="$TMP/stores"
# What holds an arm is the answer of gctk bead holds, so the suite builds gctk
# from this checkout and the check runs it over the stub stores above.
export HOLDS_STUB="$HERE/../../assets/scripts/holds-store.stub.sh" GC_NO_API=1
GCTK_BIN="$("$HOLDS_STUB" build "$TMP/gctk")" || { echo "FAIL - gctk did not build, so no hold can be read"; exit 1; }
# The config the start's dry run reads for an arm's default formula: the pool
# the fixtures arm for pours mol-polecat-work.
HOLDS_CONFIG=$(jq -nc '{ok: true, config: {Agents: [{Name: "pool", Dir: "rig", DefaultSlingFormula: "mol-polecat-work"}]}}')
export GCTK_BIN HOLDS_CONFIG

# GC_CITY_PATH is pinned to a fixture city, so the dispatch budget the window is
# derived from never comes from the AMBIENT city.toml. The check's own TMPDIR is
# a directory of its own, so the suite can see what a run leaves behind.
run_check() {
    RIGS_JSON="${RIGS_JSON:-$TMP/rigs.json}" GC_PACK_DIR="$TMP/pack" GC_CITY_PATH="${CITY_DIR:-$TMP/empty-city}" \
        TMPDIR="${CHECK_TMPDIR:-$TMP/tmpdir}" bash "$CHECK" 2>&1
}
clear_stores() { rm -f "$TMP/stores/"*.json; }

# Armed-bead fixtures (the start reads status, merge_result and the arm off this
# listing, and the hold walk reads each bead's own edges off it, as real `bd
# list --json` carries them).
armed_store() { local n="$1"; shift; local IFS=,; printf '[%s]' "$*" > "$TMP/stores/$n.armed.json"; }
aarmed()  { printf '{"id":"%s","status":"open","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_armed_at":"%s"}}' "$1" "${2:-2020-01-01T00:00:00Z}"; }
astatus() { printf '{"id":"%s","status":"%s","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_armed_at":"2020-01-01T00:00:00Z"}}' "$1" "$2"; }
amr()     { printf '{"id":"%s","status":"open","metadata":{"gc.dispatch_when_ready":"rig/pool","merge_result":"pull_request"}}' "$1"; }
aassigned() { printf '{"id":"%s","status":"open","assignee":"rig/rig.refinery","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_armed_at":"%s"}}' "$1" "${2:-2020-01-01T00:00:00Z}"; }
# amalformed <id> [armed_at] — an open arm whose sling arguments are no JSON
# array, a record the start reports as malformed.
amalformed() { printf '{"id":"%s","status":"open","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_args":"not json","gc.dispatch_when_ready_armed_at":"%s"}}' "$1" "${2:-2020-01-01T00:00:00Z}"; }
# anoformula <id> <target> [armed_at] — an open arm that names no formula, for a
# target the fixture config gives no agent, so the start cannot resolve one.
anoformula() { printf '{"id":"%s","status":"open","metadata":{"gc.dispatch_when_ready":"%s","gc.dispatch_when_ready_armed_at":"%s"}}' "$1" "$2" "${3:-2020-01-01T00:00:00Z}"; }
# alabelled <id> <label> — an open, unassigned arm carrying that label.
alabelled() { printf '{"id":"%s","status":"open","labels":["learning","%s"],"metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_armed_at":"2020-01-01T00:00:00Z"}}' "$1" "$2"; }
# A capped arm: fail count defaults to the cap (3); $2 overrides it. Paired with
# a long-closed own blocker it would read as owed-but-not-firing without the cap
# exemption.
acapped() { printf '{"id":"%s","status":"open","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_fail_count":"%s","gc.dispatch_when_ready_armed_at":"%s"}}' "$1" "${2:-3}" "${3:-2020-01-01T00:00:00Z}"; }
# An armed bead carrying its own edges, as the listing prints them: $2 is a
# comma list of parents, $3 of blockers.
aedged() {
    jq -nc --arg id "$1" --arg p "${2:-}" --arg b "${3:-}" '
        {id: $id, status: "open",
         metadata: {"gc.dispatch_when_ready": "rig/pool", "gc.dispatch_when_ready_armed_at": "2020-01-01T00:00:00Z"},
         dependencies: ( [ $p | split(",")[] | select(length > 0) | {issue_id: $id, depends_on_id: ., type: "parent-child"} ]
                       + [ $b | split(",")[] | select(length > 0) | {issue_id: $id, depends_on_id: ., type: "blocks"} ] )}'
}

# Edge fixtures — the store's edges as the armed listing's rows carry them
# (issue_id blocked-by depends_on_id), served on each armed row whose fixture
# sets no `dependencies` of its own.
edges_store() { local n="$1"; shift; local IFS=,; printf '[%s]' "$*" > "$TMP/stores/$n.edges.json"; }
e_blk() { printf '{"issue_id":"%s","depends_on_id":"%s","type":"blocks"}' "$1" "$2"; }
e_pc()  { printf '{"issue_id":"%s","depends_on_id":"%s","type":"parent-child"}' "$1" "$2"; }

# Blocker fixtures — the beads named as a blocker, with the status/closed_at the
# `bd list --id` lookup resolves. An open blocker omits closed_at, like real bd.
blockers_store() { local n="$1"; shift; local IFS=,; printf '[%s]' "$*" > "$TMP/stores/$n.blockers.json"; }
b_closed() { printf '{"id":"%s","status":"closed","closed_at":"%s"}' "$1" "$2"; }
b_open()   { printf '{"id":"%s","status":"open"}' "$1"; }
# A blocker at status $2. bd keeps a closed_at only on a closed bead, so it has
# none.
b_status() { printf '{"id":"%s","status":"%s"}' "$1" "$2"; }
# A closed GATE blocker — bd list hides it unless --include-gates is passed, so
# this exercises the include flags the status lookup must carry.
b_closed_gate() { printf '{"id":"%s","status":"closed","closed_at":"%s","issue_type":"gate"}' "$1" "$2"; }
# An ancestor the hold walk reads: $2 is a comma list of its parents, $3 of its
# blockers.
b_epic() {
    jq -nc --arg id "$1" --arg p "${2:-}" --arg b "${3:-}" '
        {id: $id, status: "open", issue_type: "epic", title: "epic \($id)",
         dependencies: ( [ $p | split(",")[] | select(length > 0) | {issue_id: $id, depends_on_id: ., type: "parent-child"} ]
                       + [ $b | split(",")[] | select(length > 0) | {issue_id: $id, depends_on_id: ., type: "blocks"} ] )}'
}
b_gate()   { printf '{"id":"%s","status":"open","issue_type":"gate","title":"Parked until the operator unparks it"}' "$1"; }
b_human_gate() { printf '{"id":"%s","status":"open","issue_type":"gate","await_type":"human","await_id":"decide-%s","title":"Decide %s"}' "$1" "$2" "$2"; }

OLD="2020-01-01T00:00:00Z"
RECENT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# --- 1. OWED: open arm, own blocks closed long ago, nothing holds it ---------
armed_store alpha "$(aarmed a-1)"
edges_store alpha "$(e_pc a-1 epic)" "$(e_blk a-1 b-0)"
blockers_store alpha "$(b_closed b-0 "$OLD")" "$(b_epic epic "" "")"
OUT=$(run_check); RC=$?
eq "$RC" "1" "an owed-but-not-firing arm warns (exit 1)"
has "$OUT" "owed but not firing" "the headline names the defect"
has "$OUT" "alpha bead a-1" "the finding names the rig and bead"
has "$OUT" "gctk bead disarm a-1 --reason" "the finding names the disarm remedy for that bead, gctk's verb"
has "$OUT" "Look: gctk bead start-armed --dry-run --db " "…and the look at the start's dry run in that rig's store"
clear_stores

# --- 2. STRANDED: armed at a non-open status ---------------------------------
armed_store alpha "$(astatus a-2 blocked)"
OUT=$(run_check); RC=$?
eq "$RC" "1" "an arm at a non-open status warns (exit 1)"
has "$OUT" "it is at status blocked" "the finding names the stranding status"
has "$OUT" "alpha bead a-2" "the stranded finding names the rig and bead"
has "$OUT" "Return it to open, or disarm it: gctk bead disarm a-2 --reason" "the stranded finding names gctk's disarm"
clear_stores

# --- 3. EXEMPT: still waiting on its OWN open blocker ------------------------
armed_store alpha "$(aarmed a-3)"
edges_store alpha "$(e_pc a-3 epic)" "$(e_blk a-3 b-0)"
blockers_store alpha "$(b_open b-0)"
OUT=$(run_check); RC=$?
eq "$RC" "0" "an arm with an open own blocker is correctly waiting (exit 0)"
has "$OUT" "OK:" "the quiet headline is printed"
clear_stores

# --- 4. EXEMPT: dispatchable only recently (within the order's window) -------
armed_store alpha "$(aarmed a-4)"
edges_store alpha "$(e_blk a-4 b-0)"
blockers_store alpha "$(b_closed b-0 "$RECENT")"
OUT=$(run_check); RC=$?
eq "$RC" "0" "an arm whose blocker closed just now is within cadence, not flagged"
hasnt "$OUT" "alpha bead a-4" "a recently-dispatchable arm is not reported"
clear_stores

# --- 6. EXEMPT: delivered by another path (merge_result) --------------------
armed_store alpha "$(amr a-6)"
edges_store alpha "$(e_blk a-6 b-0)"
blockers_store alpha "$(b_closed b-0 "$OLD")"
OUT=$(run_check); RC=$?
eq "$RC" "0" "an arm carrying merge_result is retired by the start, not flagged"
clear_stores

# --- 7. EXEMPT: closed bead ---------------------------------------------------
armed_store alpha "$(astatus a-7 closed)"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a closed armed bead owes no dispatch, not flagged"
clear_stores

# --- 7b. EXEMPT: an assigned (HELD) arm — the start sends no assigned bead ----
armed_store alpha "$(aassigned a-7b)"
edges_store alpha "$(e_blk a-7b b-0)"
blockers_store alpha "$(b_closed b-0 "$OLD")"
OUT=$(run_check); RC=$?
eq "$RC" "0" "an assigned (HELD) arm is not owed a dispatch, not flagged"
hasnt "$OUT" "alpha bead a-7b" "a handed-off/held arm is not reported as owed"
clear_stores

# --- 7b'. EXEMPT: an arm a hold label holds — the start sends no held bead -----
# Its own blocker closed long ago, so without the label it is owed; the label
# is Gas City's hold, in either value and any case, which no sling reads.
for lbl in hold:mayor ' Hold:External'; do
    armed_store alpha "$(alabelled a-7h "$lbl")"
    edges_store alpha "$(e_blk a-7h b-0)"
    blockers_store alpha "$(b_closed b-0 "$OLD")"
    OUT=$(run_check); RC=$?
    eq "$RC" "0" "an arm carrying '$lbl' is not owed a dispatch, not flagged"
    hasnt "$OUT" "alpha bead a-7h" "…and is not reported as owed"
    clear_stores
done
armed_store alpha "$(alabelled a-7h hold:po)"
edges_store alpha "$(e_blk a-7h b-0)"
blockers_store alpha "$(b_closed b-0 "$OLD")"
OUT=$(run_check); RC=$?
has "$OUT" "alpha bead a-7h" "a label that only resembles a hold leaves the arm owed"
clear_stores

# --- 7c. EXEMPT: a capped arm whose own blockers closed long ago — the start
#          asks a person about it, so it is surfaced, not silent --------------
armed_store alpha "$(acapped a-7c)"
edges_store alpha "$(e_blk a-7c b-0)"
blockers_store alpha "$(b_closed b-0 "$OLD")"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a capped arm (fail count at the cap) is exempt, not flagged as owed"
hasnt "$OUT" "alpha bead a-7c" "a capped arm is not reported"
clear_stores

# --- 7d. DISCRIMINATE: below the cap is still owed (the test is >=, not just
#          any nonzero fail count) --------------------------------------------
armed_store alpha "$(acapped a-7d 2)"
edges_store alpha "$(e_blk a-7d b-0)"
blockers_store alpha "$(b_closed b-0 "$OLD")"
OUT=$(run_check); RC=$?
eq "$RC" "1" "an arm below the cap (2 < 3) is still owed and flagged"
has "$OUT" "alpha bead a-7d" "a sub-cap owed arm is still reported"
clear_stores

# --- 7e. the cap honors GC_MAX_DISPATCH_SLING_FAILURES, as the arm's record
#          reads it -----------------------------------------------------------
armed_store alpha "$(acapped a-7e 2)"
edges_store alpha "$(e_blk a-7e b-0)"
blockers_store alpha "$(b_closed b-0 "$OLD")"
OUT=$(GC_MAX_DISPATCH_SLING_FAILURES=2 run_check); RC=$?
eq "$RC" "0" "with the cap lowered to 2, a 2-failure arm is capped and exempt"
hasnt "$OUT" "alpha bead a-7e" "the configured-cap override is the start's"
clear_stores

# --- 8b. FAIL CLOSED: the blocker-status read is unreadable ------------------
armed_store alpha "$(aarmed a-8b)"
edges_store alpha "$(e_blk a-8b b-0)"
blockers_store alpha "$(b_closed b-0 "$OLD")"
OUT=$(BD_FAIL_IDS=b-0 run_check); RC=$?
eq "$RC" "1" "an unreadable blocker read warns (exit 1)"
has "$OUT" "alpha bead a-8b: could not read what holds it" "the blocker read's failure is named"
hasnt "$OUT" "owed but not firing" "an unresolved blocker set is NOT a firm finding"
clear_stores

# --- 8e. a finding made before a later read in its store failed still stands -
armed_store alpha "$(astatus a-8e1 deferred)" "$(aarmed a-8e2)"
edges_store alpha "$(e_blk a-8e2 b-0)"
blockers_store alpha "$(b_closed b-0 "$OLD")"
OUT=$(BD_FAIL_IDS=b-0 run_check); RC=$?
eq "$RC" "1" "a stranded arm beside an unreadable blocker read warns (exit 1)"
has "$OUT" "alpha bead a-8e1: armed for dispatch, and it is at status deferred" "the stranded arm is still reported"
has "$OUT" "alpha bead a-8e2: could not read what holds it" "and the failed read is named"
clear_stores

# --- 8c. HELD: an edge of the arm's own onto a bead its store does not hold
#          holds nothing in bd's readiness, so the start holds the arm itself
#          until the wait moves into this store, and it is not owed -----------
armed_store alpha "$(aarmed a-8c)"
edges_store alpha "$(e_blk a-8c ghost)"
blockers_store alpha "$(b_closed other "$OLD")"
OUT=$(run_check); RC=$?
eq "$RC" "0" "an arm whose only edge is into another store is held, not owed (exit 0)"
hasnt "$OUT" "alpha bead a-8c" "it is not reported"
clear_stores

# --- 8d. a CLOSED GATE blocker still resolves — bd list hides gates by default,
#          so the status lookup must pass --include-gates; the blocks edge names
#          a blocker of any type ------------------------------------------------
armed_store alpha "$(aarmed a-8d)"
edges_store alpha "$(e_blk a-8d g-0)"
blockers_store alpha "$(b_closed_gate g-0 "$OLD")"
OUT=$(run_check); RC=$?
eq "$RC" "1" "an arm blocked only by a long-closed GATE is owed and flagged"
has "$OUT" "alpha bead a-8d" "the gate-blocked owed arm is reported (its gate blocker resolved)"
hasnt "$OUT" "could not read" "a gate blocker is resolved, not dropped as unreadable"
clear_stores

# --- 9. FAIL CLOSED: unreadable armed listing --------------------------------
armed_store alpha "$(aarmed a-9)"
OUT=$(BD_FAIL_LIST=alpha run_check); RC=$?
eq "$RC" "1" "an unreadable armed listing warns (exit 1)"
has "$OUT" "could not read the armed beads" "the listing failure is named"
clear_stores

# --- 9b. FAIL CLOSED: a listing that is not one JSON array is unreadable, not
#          an empty store ------------------------------------------------------
OUT=$(BD_BLANK_LIST=alpha run_check); RC=$?
eq "$RC" "1" "a listing of whitespace at rc 0 warns rather than passing (exit 1)"
has "$OUT" "alpha: could not read the armed beads in $TMP/alpha/.beads (gctk bead start-armed --dry-run rc=1) — this store was NOT checked" "the store is named as NOT checked"
hasnt "$OUT" "OK:" "it never reads as a clean pass"

# --- 10. FAIL CLOSED: unreadable rig list ------------------------------------
OUT=$(RIGS_RC=2 run_check); RC=$?
eq "$RC" "1" "an unreadable rig list warns (exit 1)"
has "$OUT" "cannot determine" "the rig-list failure is named"

# --- 11. SUSPENDED rig is skipped, not queried -------------------------------
cat > "$TMP/rigs-susp.json" <<EOF
{"rigs":[{"name":"alpha","path":"$TMP/alpha","suspended":true}]}
EOF
CALLS="$TMP/calls"; rm -f "$CALLS"
OUT=$(RIGS_JSON="$TMP/rigs-susp.json" CALL_LOG="$CALLS" run_check); RC=$?
eq "$RC" "0" "a suspended rig is skipped and the check passes"
has "$OUT" "skipped (suspended" "the skip is noted"
eq "$( [ -f "$CALLS" ] && grep -c . "$CALLS" || echo 0)" "0" "the suspended rig's store is never read"

# --- 12. QUIET PATH: no armed beads ------------------------------------------
clear_stores
OUT=$(run_check); RC=$?
eq "$RC" "0" "a store with no armed beads passes"
has "$OUT" "OK:" "the quiet headline is printed"

# --- 13. BATCH ONCE: three owed candidates cost ONE bead read, not three -----
#          This asserts the mechanism, not merely that three findings come back:
#          one dry run reads the store, listing its arms once and reading the
#          three in one read by id (the far beads' is another), and the check
#          makes no read of its own past the dry run.
armed_store alpha "$(aarmed m-1)" "$(aarmed m-2)" "$(aarmed m-3)"
edges_store alpha "$(e_blk m-1 x-1)" "$(e_blk m-2 x-2)" "$(e_blk m-3 x-3)"
blockers_store alpha "$(b_closed x-1 "$OLD")" "$(b_closed x-2 "$OLD")" "$(b_closed x-3 "$OLD")"
CALLS="$TMP/calls"; rm -f "$CALLS"
OUT=$(CALL_LOG="$CALLS" run_check); RC=$?
eq "$RC" "1" "three owed candidates warn (exit 1)"
has "$OUT" "alpha bead m-1" "the first owed candidate is reported"
has "$OUT" "alpha bead m-2" "the second owed candidate is reported"
has "$OUT" "alpha bead m-3" "the third owed candidate is reported"
eq "$(grep -c '^alpha list-armed ' "$CALLS")" "1" "the store's armed beads are listed once"
eq "$(grep -c '^alpha dep ' "$CALLS")" "0" "the store makes no dependency read: each arm's edges come off its listing row"
eq "$(grep -c -E '^alpha holds --db [^ ]* list --id [^ ]*m-[123]' "$CALLS")" "1" "the three arms are read in ONE read, not one per bead"
eq "$(grep -c '^alpha holds --db [^ ]* list --id m-1,m-2,m-3 ' "$CALLS")" "1" "that call names every candidate once"
eq "$(grep -vc -E '^alpha (list-armed|holds) ' "$CALLS")" "0" "the check makes no other read"
clear_stores

# --- 14. HELD: an arm whose own blocker closed long ago, under a parked epic,
#          is held by the park, so it is not owed ------------------------------
armed_store alpha "$(aedged h-1 epic-1 b-0)"
edges_store alpha "$(e_pc h-1 epic-1)" "$(e_blk h-1 b-0)"
blockers_store alpha "$(b_closed b-0 "$OLD")" "$(b_epic epic-1 "" park-1)" "$(b_gate park-1)"
OUT=$(run_check); RC=$?
eq "$RC" "0" "an armed child of a parked epic is held, not owed (exit 0)"
hasnt "$OUT" "alpha bead h-1" "a parked epic's armed child is not reported"
clear_stores

# --- 15. HELD two levels down: the feature between has no blocker of its own --
armed_store alpha "$(aedged h-2 feat-1 b-0)"
edges_store alpha "$(e_pc h-2 feat-1)" "$(e_blk h-2 b-0)"
blockers_store alpha "$(b_closed b-0 "$OLD")" "$(b_epic feat-1 epic-1 "")" "$(b_epic epic-1 "" park-1)" "$(b_gate park-1)"
OUT=$(run_check); RC=$?
eq "$RC" "0" "an arm two levels under a parked epic is held, not owed (exit 0)"
hasnt "$OUT" "alpha bead h-2" "the grandchild of a parked epic is not reported"
clear_stores

# --- 16. HELD: an epic that waits on an open task holds its armed work ---------
armed_store alpha "$(aedged h-3 epic-1 b-0)"
edges_store alpha "$(e_pc h-3 epic-1)" "$(e_blk h-3 b-0)"
blockers_store alpha "$(b_closed b-0 "$OLD")" "$(b_epic epic-1 "" t-1)" "$(b_open t-1)"
OUT=$(run_check); RC=$?
eq "$RC" "0" "an arm whose epic waits on an open task is held, not owed (exit 0)"
hasnt "$OUT" "alpha bead h-3" "it is not reported"
clear_stores

# --- 17. HELD: a human gate on the epic holds its armed work, as a park does --
armed_store alpha "$(aedged h-4 epic-1 b-0)"
edges_store alpha "$(e_pc h-4 epic-1)" "$(e_blk h-4 b-0)"
blockers_store alpha "$(b_closed b-0 "$OLD")" "$(b_epic epic-1 "" dg-1)" "$(b_human_gate dg-1 epic-1)"
OUT=$(run_check); RC=$?
eq "$RC" "0" "an arm whose epic waits on a human gate is held, not owed (exit 0)"
hasnt "$OUT" "alpha bead h-4" "it is not reported"
clear_stores

# --- 17a. OWED: a pinned human gate holds nothing, on the arm or on its epic,
#          as the store counts a pinned blocker of any kind as none (23), so an
#          arm behind one is slung and one still armed past the window is owed -
armed_store alpha "$(aedged h-6 "" pg-1)" "$(aedged h-7 epic-1 "")"
blockers_store alpha "$(b_human_gate pg-1 h-6 | jq -c '.status = "pinned"')" "$(b_epic epic-1 "" dg-1)" \
    "$(b_human_gate dg-1 epic-1 | jq -c '.status = "pinned"')"
OUT=$(run_check); RC=$?
eq "$RC" "1" "arms behind a pinned human gate of their own or of their epic are owed (exit 1)"
has "$OUT" "alpha bead h-6: armed and nothing has held it" "the arm whose own human gate is pinned is reported"
has "$OUT" "alpha bead h-7: armed and nothing has held it" "the arm whose epic's human gate is pinned is reported"
clear_stores

# --- 17c. HELD AND NOTED: an arm with a waits-for edge of its own is one the
#          store cannot judge yet, so reconcile holds it, and the check shows
#          the edge as unjudged rather than counting it owed ------------------
armed_store alpha "$(aarmed w-1)"
edges_store alpha "$(jq -nc '{issue_id: "w-1", depends_on_id: "sp-1", type: "waits-for"}')"
blockers_store alpha "$(b_closed sp-1 "$OLD")"
OUT=$(run_check); RC=$?
eq "$RC" "0" "an arm with a waits-for edge of its own is held, not owed (exit 0)"
has "$OUT" "alpha bead w-1: held by a waits-for edge onto sp-1, which the store cannot judge yet (unjudged)" "the check shows the edge as unjudged"
hasnt "$OUT" "owed but not firing" "and counts it as no owed dispatch"
clear_stores

# --- 17b. RELEASED: the epic's human gate was cleared just now, so the owed
#          window runs from its close, as it runs from a park's ---------------
armed_store alpha "$(aedged h-4 epic-1 b-0)"
edges_store alpha "$(e_pc h-4 epic-1)" "$(e_blk h-4 b-0)"
blockers_store alpha "$(b_closed b-0 "$OLD")" "$(b_epic epic-1 "" dg-1)" \
    "$(b_human_gate dg-1 epic-1 | jq -c --arg t "$RECENT" '.status = "closed" | .closed_at = $t')"
OUT=$(run_check); RC=$?
eq "$RC" "0" "an arm whose epic's human gate was cleared just now is within cadence, not owed"
hasnt "$OUT" "alpha bead h-4" "it is not reported"
clear_stores

# --- 18. RELEASED: the park closed just now, so the owed window runs from the
#          release, not from the arm's own blocker long ago ---------------------
armed_store alpha "$(aedged h-5 epic-1 b-0)"
edges_store alpha "$(e_pc h-5 epic-1)" "$(e_blk h-5 b-0)"
blockers_store alpha "$(b_closed b-0 "$OLD")" "$(b_epic epic-1 "" park-1)" "$(b_closed_gate park-1 "$RECENT")"
OUT=$(run_check); RC=$?
eq "$RC" "0" "an arm whose park was released just now is within cadence, not owed"
hasnt "$OUT" "alpha bead h-5" "it is not reported"
clear_stores

# --- 19. OWED: an ancestor the store does not return (a parent in another
#          store, or one deleted) holds nothing, as bd's cascade passes no hold
#          through a row the store does not hold, so the arm is owed -----------
armed_store alpha "$(aedged h-6 epic-ghost b-0)"
blockers_store alpha "$(b_closed b-0 "$OLD")"
OUT=$(run_check); RC=$?
eq "$RC" "1" "an arm whose parent has no row is owed (exit 1)"
has "$OUT" "alpha bead h-6: armed and nothing has held it" "it is reported as owed"
hasnt "$OUT" "could not read" "the parent with no row is not reported as unread"
clear_stores

# --- 20. FAIL CLOSED: a hold walk whose read fails leaves the store's arms NOT
#          checked -----------------------------------------------------------
armed_store alpha "$(aedged h-7 epic-1 b-0)"
edges_store alpha "$(e_pc h-7 epic-1)" "$(e_blk h-7 b-0)"
blockers_store alpha "$(b_closed b-0 "$OLD")" "$(b_epic epic-1 "" park-1)" "$(b_gate park-1)"
OUT=$(BD_FAIL_IDS=epic-1 run_check); RC=$?
eq "$RC" "1" "a hold walk that cannot read warns rather than passing (exit 1)"
has "$OUT" "alpha bead h-7: could not read what holds it" "the not-checked reason is named"
hasnt "$OUT" "owed but not firing" "a failed walk is NOT reported as owed"
clear_stores

# --- 21. HELD: the start selects by bd's readiness, which holds a bead in
#          flight under a parked epic as it holds one not yet started, so the
#          arm waits for the park to lift and is not owed --------------------
armed_store alpha "$(aedged h-8 epic-1 b-0 | jq -c '.metadata += {branch: "polecat/h-8", rejection_reason: "a test failed"}')"
edges_store alpha "$(e_pc h-8 epic-1)" "$(e_blk h-8 b-0)"
blockers_store alpha "$(b_closed b-0 "$OLD")" "$(b_epic epic-1 "" park-1)" "$(b_gate park-1)"
OUT=$(run_check); RC=$?
eq "$RC" "0" "an arm in flight under a parked epic is held, not owed (exit 0)"
hasnt "$OUT" "alpha bead h-8" "it is not reported"
clear_stores

# --- 22. OWED: a blocker the store does not return on an ancestor holds
#          nothing, so an arm with no blocker of its own is owed from its
#          armed_at ---------------------------------------------------------
armed_store alpha "$(aedged h-9 epic-1 "")"
blockers_store alpha "$(b_epic epic-1 "" gate-ghost)"
OUT=$(run_check); RC=$?
eq "$RC" "1" "an arm whose epic's only blocker has no row is owed (exit 1)"
has "$OUT" "alpha bead h-9: armed and nothing has held it" "it is reported as owed"
hasnt "$OUT" "could not read" "the blocker with no row is not reported as unread"
clear_stores

# --- 23. OWED: a pinned own blocker holds nothing, as a closed one does, as
#          the store counts it and gctk bead holds answers, so an arm behind it
#          alone is owed. A pinned blocker has no close, so the window runs
#          from the arm's armed_at --------------------------------------------
armed_store alpha "$(aedged p-1 "" pin-0)"
edges_store alpha "$(e_blk p-1 pin-0)"
blockers_store alpha "$(b_status pin-0 pinned)"
OUT=$(run_check); RC=$?
eq "$RC" "1" "an arm whose only own blocker is pinned is owed (exit 1)"
has "$OUT" "alpha bead p-1" "it is reported as owed"
armed_store alpha "$(aedged p-1 "" pin-0 | jq -c --arg t "$RECENT" '.metadata["gc.dispatch_when_ready_armed_at"] = $t')"
OUT=$(run_check); RC=$?
eq "$RC" "0" "the same arm armed just now is within cadence, not owed"
hasnt "$OUT" "alpha bead p-1" "…so it is not reported"
clear_stores

# --- 24. HELD: a blocker in progress, blocked, deferred or hooked still holds
#          its arm; only a closed or a pinned one releases it ------------------
armed_store alpha "$(aarmed s-1)" "$(aarmed s-2)" "$(aarmed s-3)" "$(aarmed s-4)"
edges_store alpha "$(e_blk s-1 x-1)" "$(e_blk s-2 x-2)" "$(e_blk s-3 x-3)" "$(e_blk s-4 x-4)"
blockers_store alpha "$(b_status x-1 in_progress)" "$(b_status x-2 blocked)" "$(b_status x-3 deferred)" "$(b_status x-4 hooked)"
OUT=$(run_check); RC=$?
eq "$RC" "0" "arms whose blockers are in progress, blocked, deferred or hooked are held, not owed (exit 0)"
hasnt "$OUT" "owed but not firing" "none of them is reported"
clear_stores

# --- 25. ARMED AFTER THE RELEASE: the epic's park closed long before the arm
#          was armed, so the window runs from the arm's armed_at, and an arm
#          armed just now is not owed. Armed long ago, the same arm is --------
armed_store alpha "$(aedged r-1 epic-1 "" | jq -c --arg t "$RECENT" '.metadata["gc.dispatch_when_ready_armed_at"] = $t')"
blockers_store alpha "$(b_epic epic-1 "" park-1)" "$(b_closed_gate park-1 "$OLD")"
OUT=$(run_check); RC=$?
eq "$RC" "0" "an arm armed just now under an epic whose park closed long ago is not owed"
hasnt "$OUT" "alpha bead r-1" "…so it is not reported"
armed_store alpha "$(aedged r-1 epic-1 "")"
OUT=$(run_check); RC=$?
eq "$RC" "1" "the same arm armed long ago is owed (exit 1)"
has "$OUT" "alpha bead r-1" "…and reported"
clear_stores

# --- 26. ARMED AFTER THE RELEASE: the arm's own blocker closed long before it
#          was armed, so an arm armed just now is not owed ----------------------
armed_store alpha "$(aedged r-2 "" b-0 | jq -c --arg t "$RECENT" '.metadata["gc.dispatch_when_ready_armed_at"] = $t')"
blockers_store alpha "$(b_closed b-0 "$OLD")"
OUT=$(run_check); RC=$?
eq "$RC" "0" "an arm armed just now whose own blocker closed long ago is not owed"
hasnt "$OUT" "alpha bead r-2" "…so it is not reported"
clear_stores

# --- 27. an armed_at that does not parse: the window runs from the release
#          alone, and with no release either the arm cannot be aged ----------
armed_store alpha "$(aedged u-1 "" b-0 | jq -c '.metadata["gc.dispatch_when_ready_armed_at"] = "not a time"')"
blockers_store alpha "$(b_closed b-0 "$OLD")"
OUT=$(run_check); RC=$?
eq "$RC" "1" "an arm whose armed_at does not parse is judged from its release (exit 1)"
has "$OUT" "alpha bead u-1" "…and reported"
armed_store alpha "$(aedged u-1 "" "" | jq -c '.metadata["gc.dispatch_when_ready_armed_at"] = "not a time"')"
OUT=$(run_check); RC=$?
eq "$RC" "0" "with no release either, the arm cannot be aged and is skipped"
hasnt "$OUT" "alpha bead u-1" "…so it is not reported"
clear_stores

# --- the owed window is the deferred-dispatch order's cadence window ----------
# check-cadence-live (I10) and this check read one definition
# (assets/scripts/order-cadence.sh): max(3×interval, one trip of the order
# dispatch rotation). 70 clock-driven registrations at the default budget of 4
# make a trip of ceil(70/4) = 18 passes, 2160s at 120s a pass, and the pack
# declares deferred-dispatch at 5m, so the window is 2160s.
ago() { jq -rn --argjson t "$(( $(date +%s) - $1 ))" '$t | todate'; }
{
    printf '{"orders":[{"name":"deferred-dispatch","rig":"alpha","trigger":"cooldown","interval":"5m"}'
    for i in $(seq 1 69); do printf ',{"name":"other-%s","rig":"","trigger":"cooldown","interval":"5m"}' "$i"; done
    printf ',{"name":"gated","rig":"alpha","trigger":"condition"}]}\n'
} > "$TMP/orders-busy.json"
armed_store alpha "$(aarmed w-1)"
edges_store alpha "$(e_blk w-1 c-1)"
blockers_store alpha "$(b_closed c-1 "$(ago 1200)")"
OUT=$(ORDERS_JSON="$TMP/orders-busy.json" run_check); RC=$?
eq "$RC" "0" "an arm ready for 1200s is inside a 2160s window (the 900s one called it owed)"
hasnt "$OUT" "alpha bead w-1" "…so it is not reported"
blockers_store alpha "$(b_closed c-1 "$(ago 2500)")"
OUT=$(ORDERS_JSON="$TMP/orders-busy.json" run_check); RC=$?
eq "$RC" "1" "an arm ready for 2500s, past the window, is owed"
has "$OUT" "(> 2160s)" "…and the finding states the window"
# No registry: the window falls back to the 30m minimum, and says so.
blockers_store alpha "$(b_closed c-1 "$(ago 1500)")"
OUT=$(run_check); RC=$?
eq "$RC" "0" "with no registry, an arm ready for 1500s is inside the 1800s minimum window"
has "$OUT" "did not read, so the owed window uses the 1800s minimum floor" "…and the fallback is noted"
blockers_store alpha "$(b_closed c-1 "$(ago 2000)")"
OUT=$(run_check); RC=$?
eq "$RC" "1" "with no registry, an arm ready for 2000s is owed"
has "$OUT" "(> 1800s)" "…against the minimum window"
clear_stores

# --- 28. the stores are scanned at once ---------------------------------------
# Each store's listing waits until all three have started, and fails once it has
# waited 20s. Read one after the other, no listing gets past.
rigs_of alpha beta gamma
for s in alpha beta gamma; do
    armed_store "$s" "$(aarmed "o-$s")"; edges_store "$s" "$(e_blk "o-$s" "b-$s")"; blockers_store "$s" "$(b_open "b-$s")"
done
mkdir -p "$TMP/barrier"
OUT=$(RIGS_JSON="$TMP/rigs-multi.json" BD_BARRIER_DIR="$TMP/barrier" BD_BARRIER_N=3 run_check); RC=$?
eq "$RC" "0" "three listings that each wait for all three to start finish clean"
hasnt "$OUT" "NOT checked" "and every store is checked"
clear_stores

# --- 29. findings come out in rig order, however the scans interleave --------
# alpha's listing is slowed so beta's scan finishes first; the report still
# lists alpha's finding before beta's, as the rig list orders them.
rigs_of alpha beta
armed_store alpha "$(aarmed o-1)"; edges_store alpha "$(e_blk o-1 b-1)"; blockers_store alpha "$(b_closed b-1 "$OLD")"
armed_store beta "$(aarmed o-2)"; edges_store beta "$(e_blk o-2 b-2)"; blockers_store beta "$(b_closed b-2 "$OLD")"
: > "$TMP/done"
OUT=$(RIGS_JSON="$TMP/rigs-multi.json" BD_SLOW_STORE=alpha BD_SLOW_SECS=2 BD_DONE="$TMP/done" run_check); RC=$?
eq "$(tr '\n' ' ' < "$TMP/done")" "beta alpha " "premise: beta's listing answered first"
eq "$RC" "1" "an owed arm in each of two stores warns"
LA=$(line_of "$OUT" "alpha bead o-1"); LB=$(line_of "$OUT" "beta bead o-2")
if [ -n "$LA" ] && [ -n "$LB" ] && [ "$LA" -lt "$LB" ]; then ok "alpha's finding is reported before beta's, in rig order"
else bad "alpha's finding is reported before beta's, in rig order (alpha line '${LA}', beta line '${LB}')"; fi
clear_stores

# --- 30. a store the budget cuts is named, and does not starve the others ----
rigs_of alpha beta gamma
armed_store alpha "$(aarmed o-3)"; edges_store alpha "$(e_blk o-3 b-3)"; blockers_store alpha "$(b_closed b-3 "$OLD")"
S=$(date +%s)
OUT=$(RIGS_JSON="$TMP/rigs-multi.json" BD_SLOW_STORE=beta BD_SLOW_SECS=60 GC_DOCTOR_CHECK_TIMEOUT=12 run_check); RC=$?
E=$(( $(date +%s) - S ))
if [ "$E" -lt 12 ]; then ok "the check returns inside its 12s budget (took ${E}s)"
else bad "the check returns inside its 12s budget (took ${E}s)"; fi
eq "$RC" "1" "a store the budget cut warns"
has "$OUT" "beta: could not read the armed beads in $TMP/beta/.beads (gctk bead start-armed --dry-run rc=124) — this store was NOT checked" "the wedged store is named as cut"
has "$OUT" "alpha bead o-3" "a store scanned beside it is still judged"
has "$OUT" "doctor budget before every store was scanned" "and it says the budget, not the data, ended the run"
clear_stores

# --- 31. a scan that cannot report is a store NOT checked, never a pass -------
# The scans report through the check's scratch. Removed mid-run, as a scratch
# reaper would remove it, the scan's report is lost and its store is named.
mkdir -p "$TMP/scratch"
armed_store alpha "$(aarmed r-1)"
OUT=$(CHECK_TMPDIR="$TMP/scratch" BD_REAP_SCAN_AT=alpha run_check); RC=$?
eq "$RC" "1" "a run whose scan lost its scratch warns instead of passing"
has "$OUT" "alpha: the scan of $TMP/alpha/.beads ended without reporting — this store was NOT checked" "the store whose report was lost is named"
hasnt "$OUT" "OK:" "it never reads as a clean pass"
clear_stores

# --- 32. no scratch directory, no scan ----------------------------------------
OUT=$(CHECK_TMPDIR="$TMP/no-such-dir" run_check); RC=$?
eq "$RC" "1" "with no scratch directory the check warns instead of passing"
has "$OUT" "could not create a scratch directory" "the warning names the missing scratch"

# --- 33. the rig and order registries are read at once -----------------------
# Each registry read waits until the other has started, and fails once it has
# waited 20s. Read one after the other, the first fails: an order registry read
# first leaves the window on its fallback, and a rig list read first leaves no
# store to scan. An arm ready for 2000s is owed under the 1800s fallback and
# inside the registry's 2160s window, so only a registry that read clears it.
armed_store alpha "$(aarmed w-1)"
edges_store alpha "$(e_blk w-1 c-1)"
blockers_store alpha "$(b_closed c-1 "$(ago 2000)")"
mkdir -p "$TMP/regbar"
OUT=$(ORDERS_JSON="$TMP/orders-busy.json" REG_BARRIER="$TMP/regbar" run_check); RC=$?
eq "$RC" "0" "rig and order reads that each wait for the other both answer"
hasnt "$OUT" "did not read" "the order registry read beside the rig list sets the window"
clear_stores

# --- 34. a failed read says why: each warning carries the probe's stderr -----
armed_store alpha "$(aarmed s-1)"
edges_store alpha "$(e_blk s-1 b-0)"
blockers_store alpha "$(b_closed b-0 "$OLD")"
OUT=$(BD_FAIL_LIST=alpha BD_ERR="dolt: database is locked" run_check); RC=$?
eq "$RC" "1" "a failed armed listing warns (exit 1)"
has "$OUT" "alpha: could not read the armed beads in $TMP/alpha/.beads (gctk bead start-armed --dry-run rc=1) — this store was NOT checked; gctk bead start-armed: could not list the armed beads: the store's read failed: gc bd list exited 3: dolt: database is locked" "the listing warning carries the stderr of its failed read"
OUT=$(BD_FAIL_IDS=b-0 BD_ERR="dolt: query timed out" run_check); RC=$?
has "$OUT" "alpha bead s-1: could not read what holds it in $TMP/alpha/.beads (what holds it could not be read, so it stays armed: the store's read failed: gc bd list exited 3: dolt: query timed out) — NOT checked" "the bead read's warning carries the stderr of its failed read"
OUT=$(RIGS_RC=2 RIGS_ERR="rig registry: permission denied" run_check); RC=$?
eq "$RC" "1" "a failed rig list warns (exit 1)"
has "$OUT" "rig-map: \`gc rig list --json\` exited 2: rig registry: permission denied" "the rig-list detail carries rig-map.sh's reason, with gc's stderr"
OUT=$(ORDERS_ERR="order registry: socket unavailable" run_check); RC=$?
has "$OUT" "minimum floor, not one trip of the dispatch rotation; \`gc order list\` stderr: order registry: socket unavailable" "an unread order registry's note carries its stderr"
OUT=$(BD_FAIL_LIST=alpha run_check); RC=$?
eq "$RC" "1" "a failed listing with no stderr still warns"
hasnt "$OUT" "stderr:" "a read that wrote no stderr adds no stderr clause"
OUT=$(BD_FAIL_BLOCKERS=alpha run_check); RC=$?
eq "$RC" "1" "a failed hold walk with no stderr still warns"
hasnt "$OUT" "stderr:" "…and adds no stderr clause"
clear_stores

# --- 35. the stores scan through the fan-out cap ------------------------------
# With a cap of one, each store's listing runs alone, and every store is still
# scanned and reported. Case 28 is the control: under the default cap the same
# listings run at once.
rigs_of alpha beta gamma
for s in alpha beta gamma; do
    armed_store "$s" "$(aarmed "c-$s")"; edges_store "$s" "$(e_blk "c-$s" "b-$s")"; blockers_store "$s" "$(b_closed "b-$s" "$OLD")"
done
mkdir -p "$TMP/inflight"; rm -f "$TMP/inflight.peaks"
OUT=$(RIGS_JSON="$TMP/rigs-multi.json" INFLIGHT="$TMP/inflight" GC_DOCTOR_FANOUT=1 run_check); RC=$?
eq "$(sort -n "$TMP/inflight.peaks" | tail -1)" "1" "with GC_DOCTOR_FANOUT=1 no two stores' listings were in flight at once"
eq "$(grep -c . "$TMP/inflight.peaks")" "3" "and every store was listed"
eq "$RC" "1" "an owed arm in each store warns"
for s in alpha beta gamma; do has "$OUT" "$s bead c-$s: armed and" "the owed arm in $s is reported"; done
hasnt "$OUT" "NOT checked" "no store is left unchecked by the cap"
clear_stores

# --- 36. each store's hold walk keeps its own files ---------------------------
# Each store's walk read waits until the other store's has started, so both
# stores have written what their walks read before either judges its arms. A
# walk sharing its seed or graph with the other store's would judge that
# store's arms, or its own against that store's blockers.
rigs_of alpha beta
armed_store alpha "$(aarmed k-1)"; edges_store alpha "$(e_blk k-1 kb-1)"; blockers_store alpha "$(b_open kb-1)"
armed_store beta "$(aarmed k-2)"; edges_store beta "$(e_blk k-2 kb-2)"; blockers_store beta "$(b_closed kb-2 "$OLD")"
mkdir -p "$TMP/idbarrier"
OUT=$(RIGS_JSON="$TMP/rigs-multi.json" BD_ID_BARRIER_DIR="$TMP/idbarrier" BD_ID_BARRIER_N=2 run_check); RC=$?
eq "$RC" "1" "of two stores whose walks read at once, the one with an owed arm warns (exit 1)"
has "$OUT" "beta bead k-2: armed and nothing has held it" "beta's arm is judged against beta's blockers"
hasnt "$OUT" "alpha bead k-1" "alpha's arm is judged against alpha's blockers, which hold it"
hasnt "$OUT" "could not read" "neither walk judges the other store's arms"
clear_stores

# --- 37. MALFORMED: an arm whose record does not decode is stranded ----------
# The start sends no malformed arm and counts no attempt on it, so the cap never
# asks a person about it. The check reports it at once, however recently it was
# armed, because no wait landing will dispatch it.
armed_store alpha "$(amalformed m-1 "$RECENT")"
OUT=$(run_check); RC=$?
eq "$RC" "1" "an arm whose record does not decode warns (exit 1)"
has "$OUT" "alpha bead m-1: armed for dispatch, and its arm does not decode" "the finding names the bead and that its arm does not decode"
has "$OUT" "do not decode as a JSON array of strings" "the finding names what in the record does not decode"
has "$OUT" "Disarm it (gctk bead disarm m-1 --reason" "the finding names the disarm remedy for that bead, gctk's verb"
clear_stores

# --- 38. an arm whose formula the start cannot resolve is owed past the window
# An arm that names no formula pours its target's default, and a target the
# city's config gives no agent has none, so the start sends nothing and counts
# no attempt. Nothing holds the arm, so it reads as owed once the window has
# passed, and the finding says why it has not dispatched.
armed_store alpha "$(anoformula f-1 rig/gone)" "$(anoformula f-2 rig/gone "$RECENT")"
OUT=$(run_check); RC=$?
eq "$RC" "1" "an old arm whose formula cannot be resolved warns (exit 1)"
has "$OUT" "alpha bead f-1: armed and nothing has held it" "it reads as owed but not firing"
has "$OUT" "no agent in the city's config answers to rig/gone" "the finding names why the start cannot send it"
hasnt "$OUT" "alpha bead f-2" "one armed within the window is not flagged yet"
clear_stores

echo "── every run removes its scratch ──"
eq "$(ls -A "$TMP/tmpdir")" "" "no run above left anything in its TMPDIR"

if grep -qE '^[[:space:]]*OWED_WINDOW_SECONDS=[0-9]' "$CHECK"; then
    bad "the check carries no owed-window constant of its own"
else ok "the check carries no owed-window constant of its own"; fi
grep -qF 'assets/scripts/order-cadence.sh' "$CHECK" && ok "the check sources assets/scripts/order-cadence.sh" \
    || bad "the check sources assets/scripts/order-cadence.sh"

echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
