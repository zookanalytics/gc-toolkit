#!/usr/bin/env bash
# Hermetic test for doctor/check-routed-work-claimable (I3). Stub gc/bd only.
# Covers: exact-equality route classification (repair / candidates / padded /
# blank / unknown), the sentinel and empty exemptions, the widened assignee
# arm, the folded rig-scoped-order arm, the reachability arm (stranded /
# legitimate wait / parent shape / dependency shape / excluded type), and
# every fail-closed probe — including that a failing probe surfaces its
# stderr, not just its rc. Also the cost shape the doctor budget rests on: slim
# listings, batched re-reads, stores and their listings read at once, a report
# merged in rig order, and a scan that cannot report counted as NOT checked.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$HERE/run.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-check-routed-work-claimable-test.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 (found '$2')" ;; *) ok "$3" ;; esac; }

CITY="$TMP/testcity"
mkdir -p "$TMP/bin" "$TMP/stores" "$CITY" "$TMP/alpha" "$TMP/beta" "$TMP/pack/orders"

cat > "$TMP/agents.json" <<EOF
{"city_path":"$CITY","agents":[
  {"qualified_name":"alpha/pack.polecat"},
  {"qualified_name":"beta/pack.polecat"},
  {"qualified_name":"alpha/pack.refinery"},
  {"qualified_name":"pack.mayor"}]}
EOF
cat > "$TMP/rigs.json" <<EOF
{"rigs":[
  {"name":"testcity","path":"$CITY"},
  {"name":"alpha","path":"$TMP/alpha"},
  {"name":"beta","path":"$TMP/beta"}]}
EOF
printf '{"orders":[]}' > "$TMP/orders.json"

cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
case "$1 $2" in
  "agent list") rc="${AGENTS_RC:-0}"; [ "$rc" -eq 0 ] || { [ -n "${AGENTS_ERR:-}" ] && printf '%s\n' "$AGENTS_ERR" >&2; exit "$rc"; }; cat "$AGENTS_JSON" ;;
  "rig list")   rc="${RIGS_RC:-0}";   [ "$rc" -eq 0 ] || { [ -n "${RIGS_ERR:-}" ] && printf '%s\n' "$RIGS_ERR" >&2; exit "$rc"; }; cat "$RIGS_JSON" ;;
  "order list") rc="${ORDERS_RC:-0}"; [ "$rc" -eq 0 ] || { [ -n "${ORDERS_ERR:-}" ] && printf '%s\n' "$ORDERS_ERR" >&2; exit "$rc"; }; cat "$ORDERS_JSON" ;;
  "bd "*)    shift; VIA_GC_BD=1 exec "$(dirname "$0")/bd" "$@" ;;
  *) exit 0 ;;
esac
GC
cat > "$TMP/bin/bd" <<'BD'
#!/usr/bin/env bash
# The check reaches the store through `gc bd`; a direct `bd` is the regression
# this guard catches, so only the gc stub above may run this one.
[ -n "${VIA_GC_BD:-}" ] || { echo "stub bd: called directly, not through gc bd" >&2; exit 127; }
# Each call is logged when a case asks, so it can assert what the check read.
[ -n "${CALL_LOG:-}" ] && printf '%s\n' "$*" >> "$CALL_LOG"
sub="$1"; db=""; prev=""
for a in "$@"; do [ "$prev" = "--db" ] && db="$a"; prev="$a"; done
name=$(basename "$(dirname "$db")")
bd_die() { [ -n "${BD_ERR:-}" ] && printf '%s\n' "$BD_ERR" >&2; exit 3; }
[ "$name" = "${BD_FAIL_STORE:-}" ] && bd_die
# BD_SLOW names the stores whose listings (list, ready, blocked) each take
# BD_SLOW_SECS, "all" for every store. BD_BLANK names <store>:<subcommand>
# reads that answer whitespace at rc 0.
case "$sub" in list|ready|blocked)
    case " ${BD_SLOW:-} " in *" $name "*|*" all "*) sleep "${BD_SLOW_SECS:-3}" ;; esac
    [ "$name:$sub" = "${BD_BLANK:-}" ] && { printf '  '; exit 0; } ;;
esac
case "$sub" in
  # BD_REAP_SCAN_AT names a store whose listing removes the check's scan
  # scratch from under it, as a scratch reaper would.
  list)    [ "$name" = "${BD_REAP_SCAN_AT:-}" ] && rm -rf "${TMPDIR:?}"/gctk-check-routed-work-claimable-scan.*
           f="$STORES/$name.json" ;;
  # A healthy store offers every open bead, so `ready` serves the `list`
  # fixture unless a case overrides it, and `blocked` is empty unless one does.
  # `ready` applies the --unassigned and --has-metadata-key filters as bd does,
  # so a read that asks for the wrong rows loses candidates it should offer.
  ready)   [ "$name" = "${BD_FAIL_READY:-}" ] && bd_die
           f="$STORES/$name.ready.json"; [ -f "$f" ] || f="$STORES/$name.json"
           un=0; key=""; prev=""
           for a in "$@"; do
               [ "$a" = "--unassigned" ] && un=1
               [ "$prev" = "--has-metadata-key" ] && key="$a"
               prev="$a"
           done
           if [ -f "$f" ]; then
               jq -c --argjson un "$un" --arg key "$key" '[.[]
                   | select($un == 0 or ((.assignee // "") == ""))
                   | select($key == "" or ((.metadata // {})[$key] != null))]' "$f"
           else printf '[]'; fi
           exit 0 ;;
  blocked) [ "$name" = "${BD_FAIL_BLOCKED:-}" ] && bd_die
           f="$STORES/$name.blocked.json" ;;
  # `show <id>...` re-reads beads at report time, many per call. Like bd, it
  # answers with the rows it found at rc 0, and with an error object at rc 1
  # when none resolved. Its fixture defaults to the `list` snapshot, so a case
  # only sets `<store>.show.json` when the two must differ (a just-closed bead,
  # a closed molecule root the open list omits).
  show)    [ "$name" = "${BD_FAIL_SHOW:-}" ] && bd_die
           f="$STORES/$name.show.json"; [ -f "$f" ] || f="$STORES/$name.json"
           ids=(); skip=0
           for a in "${@:2}"; do
               if [ "$skip" = 1 ]; then skip=0; continue; fi
               case "$a" in --db) skip=1 ;; -*) ;; *) ids+=("$a") ;; esac
           done
           rows='[]'
           [ -f "$f" ] && rows=$(jq -c --args '[.[] | select((.id // "") as $i | any($ARGS.positional[]; . == $i))]' "${ids[@]}" < "$f")
           if [ "$(printf '%s' "$rows" | jq 'length')" = 0 ]; then
               printf '{"error":"no issues found matching the provided IDs","schema_version":1}\n'
               exit 1
           fi
           printf '%s' "$rows"; exit 0 ;;
  *) printf '[]'; exit 0 ;;
esac
if [ -f "$f" ]; then cat "$f"; else printf '[]'; fi
BD
chmod +x "$TMP/bin/gc" "$TMP/bin/bd"
export PATH="$TMP/bin:$PATH" STORES="$TMP/stores"
run_check() {
    AGENTS_JSON="${AGENTS_JSON:-$TMP/agents.json}" RIGS_JSON="${RIGS_JSON:-$TMP/rigs.json}" \
    ORDERS_JSON="${ORDERS_JSON:-$TMP/orders.json}" GC_PACK_DIR="$TMP/pack" bash "$CHECK" 2>&1
}
routed() { printf '{"id":"%s","status":"open","metadata":{"gc.routed_to":"%s"}}' "$1" "$2"; }
assigned() { printf '{"id":"%s","status":"open","assignee":"%s","metadata":{}}' "$1" "$2"; }
store() { local n="$1"; shift; local IFS=,; printf '[%s]' "$*" > "$TMP/stores/$n.json"; }
clear_stores() { rm -f "$TMP/stores/"*.json; }
routed_parent() { printf '{"id":"%s","status":"open","issue_type":"task","parent":"%s","metadata":{"gc.routed_to":"%s"}}' "$1" "$3" "$2"; }
routed_dep() { printf '{"id":"%s","status":"open","issue_type":"task","dependencies":[{"issue_id":"%s","depends_on_id":"%s","type":"blocks"}],"metadata":{"gc.routed_to":"%s"}}' "$1" "$1" "$3" "$2"; }
routed_typed() { printf '{"id":"%s","status":"open","issue_type":"%s","metadata":{"gc.routed_to":"%s"}}' "$1" "$3" "$2"; }
blocked_row() { printf '{"id":"%s","status":"open","blocked_by":["%s"],"blocked_by_count":1}' "$1" "$2"; }
ready_store() { local n="$1"; shift; local IFS=,; printf '[%s]' "$*" > "$TMP/stores/$n.ready.json"; }
blocked_store() { local n="$1"; shift; local IFS=,; printf '[%s]' "$*" > "$TMP/stores/$n.blocked.json"; }
# A graph.v2 molecule step: routed + unassigned, carrying the step markers arm 4
# keys its live-molecule carve-out on, with a blocks edge to its ordering
# predecessor — the shape the arm otherwise reads as an inverted strand edge.
# Args: id route step_id root_id blocker root_rig.
routed_step() { printf '{"id":"%s","status":"open","issue_type":"task","dependencies":[{"depends_on_id":"%s","type":"blocks"}],"metadata":{"gc.routed_to":"%s","gc.step_id":"%s","gc.root_bead_id":"%s","gc.root_store_ref":"rig:%s"}}' "$1" "$5" "$2" "$3" "$4" "$6"; }
open_bead()   { printf '{"id":"%s","status":"open"}' "$1"; }
inprogress_bead() { printf '{"id":"%s","status":"in_progress"}' "$1"; }
closed_bead() { printf '{"id":"%s","status":"closed"}' "$1"; }
show_store()  { local n="$1"; shift; local IFS=,; printf '[%s]' "$*" > "$TMP/stores/$n.show.json"; }

# --- 1. rig-unqualified route: error, repair named ------------------------
store alpha "$(routed a-1 pack.polecat)"
OUT=$(run_check); RC=$?
eq "$RC" "2" "a rig-unqualified pool route is an ERROR"
has "$OUT" "a-1" "the error names the bead"
has "$OUT" "gc.routed_to=alpha/pack.polecat" "the error names the exact repair"
clear_stores

# --- 2. city store: candidates listed, no repair guessed ------------------
store testcity "$(routed c-1 pack.polecat)"
OUT=$(run_check); RC=$?
eq "$RC" "2" "a bare rig-pool route in the CITY store is an ERROR"
has "$OUT" "alpha/pack.polecat, beta/pack.polecat" "it lists every candidate"
hasnt "$OUT" "set gc.routed_to" "it does not guess a repair it cannot know"
clear_stores

# --- 3. exempt shapes ------------------------------------------------------
store alpha "$(routed a-2 alpha/pack.refinery)" "$(routed a-3 pack.mayor)" \
            "$(routed a-4 human)" "$(routed a-5 '')"
OUT=$(run_check); RC=$?
eq "$RC" "0" "exact identity / bare-but-live city identity / human sentinel / empty route all pass"
hasnt "$OUT" "a-2" "the working route is not a finding"
hasnt "$OUT" "a-4" "the human sentinel is not a finding"
clear_stores

# --- 4. padded and blank routes (compared AS STORED) -----------------------
store alpha "$(routed p-1 ' alpha/pack.refinery ')" "$(routed p-2 '   ')"
OUT=$(run_check); RC=$?
eq "$RC" "2" "a whitespace-padded live identity is an ERROR, not an OK"
has "$OUT" '" alpha/pack.refinery "' "the stored bytes are quoted so the padding is visible"
has "$OUT" "set gc.routed_to=alpha/pack.refinery" "the de-padded repair is named"
has "$OUT" "p-2" "a whitespace-only route is an ERROR, not a cleared route"
clear_stores

# --- 5. unknown route: note, not verdict -----------------------------------
store alpha "$(routed u-1 not-an-agent-at-all)"
OUT=$(run_check); RC=$?
eq "$RC" "0" "an unrecognizable route does not fail the check"
has "$OUT" "reported, not judged" "it is still reported in the details"
clear_stores

# --- 6. the WIDENED assignee arm --------------------------------------------
store alpha "$(assigned s-1 alpha/pack.refinery)" "$(assigned s-2 human)"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a live-identity assignee and the human sentinel pass"
store alpha "$(assigned s-3 pack.polecat)"
OUT=$(run_check); RC=$?
eq "$RC" "2" "a rig-unqualified ASSIGNEE on an open bead is an ERROR"
has "$OUT" "assignee=" "the finding names the assignee field, not the route"
has "$OUT" "set assignee=alpha/pack.polecat" "the repair is the qualified assignee"
store alpha "$(assigned s-4 someone-external)"
OUT=$(run_check); RC=$?
eq "$RC" "0" "an assignee resembling nothing is a note, not a verdict"
has "$OUT" "s-4" "the unjudgeable assignee is still reported"
clear_stores

# --- 7. the folded rig-scoped-order arm -------------------------------------
printf 'scope = "rig"\n' > "$TMP/pack/orders/sweeper.toml"
cat > "$TMP/orders-unbound.json" <<EOF
{"orders":[{"name":"sweeper","rig":"","source":"$TMP/pack/orders/sweeper.toml"}]}
EOF
OUT=$(ORDERS_JSON="$TMP/orders-unbound.json" run_check); RC=$?
eq "$RC" "2" "a scope=rig order registered with no rig bound is an ERROR"
has "$OUT" "sweeper" "the unbound order is named"
cat > "$TMP/orders-city.json" <<EOF
{"orders":[{"name":"citywide","rig":"","source":"$TMP/pack/orders/citywide.toml"}]}
EOF
printf 'scope = "city"\n' > "$TMP/pack/orders/citywide.toml"
OUT=$(ORDERS_JSON="$TMP/orders-city.json" run_check); RC=$?
eq "$RC" "0" "a scope=city order with no rig is the point of city scope"

# --- 8. fail-CLOSED arms -----------------------------------------------------
OUT=$(AGENTS_RC=1 run_check); RC=$?
eq "$RC" "1" "a failed \`gc agent list\` warns (with no identity set every route looks dead)"
OUT=$(RIGS_RC=1 run_check); RC=$?
eq "$RC" "1" "a failed \`gc rig list\` warns"
OUT=$(BD_FAIL_STORE=alpha run_check); RC=$?
eq "$RC" "1" "an unreadable store warns"
has "$OUT" "NOT checked" "the warning says the store was skipped, not clean"
OUT=$(ORDERS_RC=1 run_check); RC=$?
eq "$RC" "1" "an unreadable order registry warns (the arm did not run)"

# --- 8b. a failing probe surfaces its stderr, not just its rc ----------------
# The rc alone does not say WHY a probe failed, so a transient I3 recurs
# undiagnosable; every fail-closed arm carries the failing command's first
# stderr line.
OUT=$(AGENTS_RC=1 AGENTS_ERR="dolt: cannot open database: connection refused" run_check); RC=$?
eq "$RC" "1" "a failed \`gc agent list\` still warns"
has "$OUT" "connection refused" "the agent-list I3 detail carries the probe's stderr"

OUT=$(RIGS_RC=1 RIGS_ERR="rig registry: permission denied" run_check); RC=$?
eq "$RC" "1" "a failed \`gc rig list\` still warns"
has "$OUT" "permission denied" "the rig-list I3 detail carries the probe's stderr"

store alpha "$(routed a-1 alpha/pack.polecat)"
OUT=$(BD_FAIL_STORE=alpha BD_ERR="dolt: relation \"issues\" does not exist" run_check); RC=$?
eq "$RC" "1" "an unreadable store still warns"
has "$OUT" "NOT checked" "the store-skip warning still says the store was skipped"
has "$OUT" "does not exist" "the store-skip warning carries \`gc bd list\` stderr"
clear_stores

store alpha "$(routed n-1 alpha/pack.polecat)"
ready_store alpha "$(routed n-1 alpha/pack.polecat)"; blocked_store alpha
OUT=$(BD_FAIL_READY=alpha BD_ERR="dolt: query timed out" run_check); RC=$?
eq "$RC" "1" "an unreadable \`bd ready\` still warns"
has "$OUT" "query timed out" "the reachability warning carries the probe's stderr"
clear_stores

OUT=$(ORDERS_RC=1 ORDERS_ERR="order registry: socket unavailable" run_check); RC=$?
eq "$RC" "1" "a failed \`gc order list\` still warns"
has "$OUT" "socket unavailable" "the order-registry warning carries the probe's stderr"

# A probe that fails with no stderr adds no empty, dangling stderr line.
OUT=$(AGENTS_RC=1 run_check); RC=$?
eq "$RC" "1" "a failed \`gc agent list\` with no stderr still warns"
hasnt "$OUT" "stderr:" "no stderr line is printed when the probe emitted none"

# --- 9. an ERROR outranks a WARNING -----------------------------------------
store beta "$(routed b-1 pack.polecat)"
OUT=$(BD_FAIL_STORE=alpha run_check); RC=$?
eq "$RC" "2" "a finding plus an unreadable store still exits ERROR"
has "$OUT" "b-1" "the finding survives alongside the warning"
clear_stores

# --- 10. clean pass -----------------------------------------------------------
OUT=$(run_check); RC=$?
eq "$RC" "0" "empty stores are OK"
has "$OUT" "OK:" "the pass message is the OK line"

# --- 11. the reachability arm: a valid address is not an offer ---------------
store alpha "$(routed n-1 alpha/pack.polecat)"
ready_store alpha; blocked_store alpha
OUT=$(run_check); RC=$?
eq "$RC" "2" "a routed bead in neither bd ready nor bd blocked is an ERROR"
has "$OUT" "n-1" "the finding names the bead"
has "$OUT" 'gc.routed_to="alpha/pack.polecat"' "the finding names the route"
has "$OUT" "no parent and no blocks edge" "the finding names the shape it matched"
clear_stores

store alpha "$(routed n-2 alpha/pack.polecat)"
ready_store alpha; blocked_store alpha "$(blocked_row n-2 w-9)"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a routed bead waiting in bd blocked on an open blocker still PASSES"
hasnt "$OUT" "n-2" "a legitimate wait is the common case, not a finding"
clear_stores

store alpha "$(routed_parent n-3 alpha/pack.polecat anc-1)"
ready_store alpha; blocked_store alpha
OUT=$(run_check); RC=$?
eq "$RC" "2" "a routed bead a parent excludes from bd ready is an ERROR"
has "$OUT" "parent anc-1" "the parent shape names the parent"
clear_stores

store alpha "$(routed_dep n-4 alpha/pack.polecat anc-2)"
ready_store alpha; blocked_store alpha
OUT=$(run_check); RC=$?
eq "$RC" "2" "a routed bead whose blocks edge explains no reported wait is an ERROR"
has "$OUT" "depends on anc-2" "the dependency shape names the bead it waits on"
has "$OUT" "edge direction" "the dependency shape names the inverted edge"
clear_stores

store alpha "$(assigned n-5 alpha/pack.refinery)"
ready_store alpha; blocked_store alpha
OUT=$(run_check); RC=$?
eq "$RC" "0" "an ASSIGNED bead is claimed, not queued — the arm does not judge it"
clear_stores

store alpha "$(routed n-6 pack.polecat)"
ready_store alpha; blocked_store alpha
OUT=$(run_check); RC=$?
eq "$RC" "2" "a bead whose ADDRESS is broken is still an ERROR"
has "$OUT" "set gc.routed_to=alpha/pack.polecat" "arm 1 names the repair"
hasnt "$OUT" "no pool offers it" "the arm does not pile onto an address that must be fixed first"
clear_stores

store alpha "$(routed_typed n-7 alpha/pack.polecat molecule)"
ready_store alpha; blocked_store alpha
OUT=$(run_check); RC=$?
eq "$RC" "0" "a routed molecule is not an ERROR — bd ready excludes the type by design"
has "$OUT" "n-7: gc.routed_to=\"alpha/pack.polecat\" is set on a molecule" "the excluded type is still reported"
clear_stores

# Nothing makes bead ids unique ACROSS stores, so what one store offers must not
# vouch for the next store's bead of the same id.
store alpha "$(routed n-8 alpha/pack.polecat)"
store beta "$(routed n-8 beta/pack.polecat)"
ready_store alpha "$(routed n-8 alpha/pack.polecat)"; blocked_store alpha
ready_store beta; blocked_store beta
OUT=$(run_check); RC=$?
eq "$RC" "2" "an id offered in one store does not vouch for the same id stranded in the next"
has "$OUT" "beta bead n-8" "the stranded store is the one named"
hasnt "$OUT" "alpha bead n-8" "the store that offers it is not named"
clear_stores

# --- 11b. a LIVE graph.v2 molecule step is not a strand ----------------------
# Routed, unassigned, in neither list because its molecule schedules it through
# session affinity — and its blocks edge to the prior step is the molecule's own
# ordering, not the inverted strand edge the arm names for a plain routed bead.
store alpha "$(routed_step sm-1 alpha/pack.polecat mol-x.advance sm-root sm-blk alpha)" "$(open_bead sm-root)"
ready_store alpha; blocked_store alpha
OUT=$(run_check); RC=$?
eq "$RC" "0" "a live graph.v2 molecule step (root still open) is not a strand"
has "$OUT" "sm-1" "the live step is still reported"
has "$OUT" "which is open" "the note names the molecule as live"
hasnt "$OUT" "check the edge direction" "the step's ordering edge is not read as an inverted strand edge"
clear_stores

# --- 11c. an ORPHAN step of a CLOSED molecule stays a finding -----------------
# Same markers, but the root has closed: the molecule is done and no session
# will resume this step, so it is a genuine strand. The closed root is absent
# from the open-bead `list` but readable by the report-time `show` re-read.
store alpha "$(routed_step sm-2 alpha/pack.polecat mol-y.advance sm-root2 sm-blk2 alpha)"
ready_store alpha; blocked_store alpha
show_store alpha "$(routed_step sm-2 alpha/pack.polecat mol-y.advance sm-root2 sm-blk2 alpha)" "$(closed_bead sm-root2)"
OUT=$(run_check); RC=$?
eq "$RC" "2" "a graph.v2 step whose molecule is CLOSED is a genuine orphan strand"
has "$OUT" "sm-2" "the orphan step is named"
has "$OUT" "orphaned step" "the error names it an orphan of a done molecule"
clear_stores

# --- 11c2. a live molecule step whose root is IN_PROGRESS is not a strand ------
# A graph.v2 root spends most of its life in_progress, not open (a review or work
# root runs in_progress while its steps execute). The exemption must treat
# in_progress as live too, or every in-flight step re-earns the blocking false
# positive this check was filed to stop.
store alpha "$(routed_step sm-4 alpha/pack.polecat mol-w.advance sm-root4 sm-blk4 alpha)" "$(inprogress_bead sm-root4)"
ready_store alpha; blocked_store alpha
OUT=$(run_check); RC=$?
eq "$RC" "0" "a live graph.v2 molecule step (root in_progress) is not a strand"
has "$OUT" "sm-4" "the in_progress-root step is reported"
has "$OUT" "which is in_progress" "the note names the in_progress molecule as live"
hasnt "$OUT" "orphaned step" "an in_progress root is not read as a done molecule"
clear_stores

# --- 11c3. a step whose molecule root is UNREADABLE warns, never passes --------
# The candidate re-reads fine and is a graph.v2 step, but its root lives in a
# store whose `bd show` fails. Liveness is unknown, so the run warns — never a
# silent pass, never a manufactured orphan-strand error. root_store_ref points
# the root read at the beta store, and only that store's `bd show` is failed, so
# the candidate re-read in alpha still succeeds.
store alpha "$(routed_step sm-5 alpha/pack.polecat mol-z.advance sm-root5 sm-blk5 beta)"
ready_store alpha; blocked_store alpha
OUT=$(BD_FAIL_SHOW=beta run_check); RC=$?
eq "$RC" "1" "a graph.v2 step whose molecule root is UNREADABLE warns instead of passing"
has "$OUT" "liveness could not be read" "the warning names the unreadable root probe"
hasnt "$OUT" "orphaned step" "an unreadable root is not flagged as an orphan strand"
clear_stores

# --- 11c4. a step whose molecule root does NOT resolve warns, not a strand -----
# The roots of one store are read in one batch. Here the batch resolves the live
# root sm-root7 and not sm-gone, so it succeeds (rc=0) and gives sm-gone no
# status. The molecule cannot be proven dead (an unresolvable or cross-store
# root reads the same way), so this warns rather than manufacturing an
# orphan-strand error, and the step whose root did resolve is judged as usual.
store alpha "$(routed_step sm-6 alpha/pack.polecat mol-v.advance sm-gone sm-blk6 alpha)" \
            "$(routed_step sm-7 alpha/pack.polecat mol-u.advance sm-root7 sm-blk7 alpha)" "$(open_bead sm-root7)"
ready_store alpha; blocked_store alpha
OUT=$(run_check); RC=$?
eq "$RC" "1" "a graph.v2 step whose molecule root does not resolve warns, never passes"
has "$OUT" "sm-6: gc.routed_to=\"alpha/pack.polecat\" is the graph.v2 step mol-v.advance of molecule sm-gone, whose molecule liveness is undetermined" "the warning names the unresolvable root"
hasnt "$OUT" "orphaned step" "an unresolvable root is not flagged as an orphan strand"
has "$OUT" "sm-7: gc.routed_to=\"alpha/pack.polecat\" is the graph.v2 step mol-u.advance of molecule sm-root7, which is open" "a root the same batch resolved still exempts its step"
clear_stores

# --- 11c5. a root batch that resolves nothing warns for every step it served ---
# `bd show` exits 1 when none of its ids resolves, so the root read failed and
# each step it served warns that its root could not be read.
store alpha "$(routed_step sm-8 alpha/pack.polecat mol-t.advance sm-gone8 sm-blk8 alpha)"
ready_store alpha; blocked_store alpha
OUT=$(run_check); RC=$?
eq "$RC" "1" "a step whose root batch resolved nothing warns, never passes"
has "$OUT" "molecule sm-gone8, whose liveness could not be read (\`gc bd show sm-gone8\` rc=1)" "the warning names the failed root read"
hasnt "$OUT" "orphaned step" "a failed root read is not flagged as an orphan strand"
clear_stores

# --- 11d. a candidate that closed since the listing is dropped, not flagged ---
# The open-bead snapshot named it, but the report-time re-read finds it closed:
# the just-closed race that fired this check on an already-closed bead.
store alpha "$(routed n-jc alpha/pack.polecat)"
ready_store alpha; blocked_store alpha
show_store alpha "$(printf '{"id":"n-jc","status":"closed","metadata":{"gc.routed_to":"alpha/pack.polecat"}}')"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a candidate that closed between the listing and the report is dropped, not flagged"
has "$OUT" "closed between the listing and this report" "the note explains the just-closed race"
hasnt "$OUT" "no pool offers it" "the closed bead is not reported as a live strand"
clear_stores

# --- 12. the reachability arm fails CLOSED -----------------------------------
store alpha "$(routed n-9 alpha/pack.polecat)"
ready_store alpha "$(routed n-9 alpha/pack.polecat)"; blocked_store alpha
OUT=$(BD_FAIL_READY=alpha run_check); RC=$?
eq "$RC" "1" "an unreadable \`bd ready\` warns instead of passing the store"
has "$OUT" "NOT checked for reachability" "the warning says the store was skipped, not clean"
OUT=$(BD_FAIL_BLOCKED=alpha run_check); RC=$?
eq "$RC" "1" "an unreadable \`bd blocked\` warns"
OUT=$(run_check); RC=$?
eq "$RC" "0" "with both listings readable the same bead passes — the warning was the probe, not the bead"
clear_stores
# A store with no routed, unassigned bead has nothing for the queues to answer,
# so their failure there hides nothing.
store alpha "$(assigned n-10 alpha/pack.refinery)"
OUT=$(BD_FAIL_READY=alpha run_check); RC=$?
eq "$RC" "0" "an unreadable \`bd ready\` in a store with no routed work hides nothing and passes"
clear_stores

# --- 13. the cross-store arm: a live address that reads another store ---------
# A rig-scope pool claims only beads in its own rig's store, so a bead routed at a
# pool whose rig does not own the bead's store is offered by nobody however valid
# the address — even while it sits in its own store's `bd ready`. Arm 1 (address
# is live) and the offerable test (bead is in ITS store's ready/blocked) both miss
# this; the store-reachability arm catches it. The roster carries each agent's
# scope so the arm can tell which store an identity reads.
cat > "$TMP/agents-scoped.json" <<EOF
{"city_path":"$CITY","agents":[
  {"qualified_name":"alpha/pack.polecat","scope":"rig"},
  {"qualified_name":"beta/pack.polecat","scope":"rig"},
  {"qualified_name":"pack.keeper","scope":"city"}]}
EOF
# A bead in the BETA store routed at alpha/pack.polecat (which reads ALPHA), and
# offerable in its own (beta) store's `bd ready`: the false pass this arm closes.
store beta "$(routed x-1 alpha/pack.polecat)"
ready_store beta "$(routed x-1 alpha/pack.polecat)"; blocked_store beta
OUT=$(AGENTS_JSON="$TMP/agents-scoped.json" run_check); RC=$?
eq "$RC" "2" "a bead routed at a rig-scope pool that reads another store is an ERROR"
has "$OUT" "x-1" "the cross-store finding names the bead"
has "$OUT" "CrossStoreRouteError" "the finding ties it to the sling guard it mirrors"
hasnt "$OUT" "no pool offers it and no queue shows it waiting" "it does not misreport an offerable bead with the generic stranded message"
clear_stores

# a same-store rig-scope route is not a cross-store finding (positive finding only)
store alpha "$(routed x-2 alpha/pack.polecat)"
ready_store alpha "$(routed x-2 alpha/pack.polecat)"; blocked_store alpha
OUT=$(AGENTS_JSON="$TMP/agents-scoped.json" run_check); RC=$?
eq "$RC" "0" "a same-store rig-scope route passes the cross-store arm"
clear_stores

# a city-scope identity reads the city store, so a rig-store bead routed at it
# is cross-store too — the arm catches the reverse direction.
store alpha "$(routed x-3 pack.keeper)"
ready_store alpha "$(routed x-3 pack.keeper)"; blocked_store alpha
OUT=$(AGENTS_JSON="$TMP/agents-scoped.json" run_check); RC=$?
eq "$RC" "2" "a rig-store bead routed at a city-scope identity (reads the city store) is an ERROR"
has "$OUT" "x-3" "the city-scope cross-store finding names the bead"
clear_stores

# an identity with no resolvable scope is not judged cross-store: the unscoped
# roster of every case above never fired this arm, which is why those cases stand.
store alpha "$(routed x-4 alpha/pack.polecat)"
ready_store alpha "$(routed x-4 alpha/pack.polecat)"; blocked_store alpha
OUT=$(run_check); RC=$?
eq "$RC" "0" "with an unscoped roster the cross-store arm makes no finding"
clear_stores

# --- 14. the reads ask only for what the arms judge ---------------------------
# Every probe costs a gc start-up, and a listing held whole costs time per byte,
# so the reads are slim and the re-reads batched. Three live steps whose roots
# live in two stores cost one candidate re-read and one root read per store,
# where a read per candidate and per root would cost six.
store alpha "$(routed_step sb-1 alpha/pack.polecat mol-b.a sb-root sb-blk alpha)" \
            "$(routed_step sb-2 alpha/pack.polecat mol-b.b sb-root sb-blk alpha)" \
            "$(routed_step sb-3 alpha/pack.polecat mol-c.a sb-root3 sb-blk3 beta)" "$(open_bead sb-root)"
store beta "$(inprogress_bead sb-root3)"
ready_store alpha; blocked_store alpha
: > "$TMP/calls.log"
OUT=$(CALL_LOG="$TMP/calls.log" run_check); RC=$?
eq "$RC" "0" "three live steps with roots in two stores pass"
has "$OUT" "sb-3: gc.routed_to=\"alpha/pack.polecat\" is the graph.v2 step mol-c.a of molecule sb-root3, which is in_progress" "a root in another store is read from that store"
eq "$(grep -c '^list ' "$TMP/calls.log")" "3" "one listing per store"
eq "$(grep '^list ' "$TMP/calls.log" | grep -vc -- '--brief')" "0" "every listing omits the free text"
eq "$(grep '^ready ' "$TMP/calls.log" | grep -c -- '--brief')" "3" "every ready read omits the free text"
eq "$(grep '^ready ' "$TMP/calls.log" | grep -c -- '--unassigned')" "3" "every ready read asks for unassigned rows only"
eq "$(grep '^ready ' "$TMP/calls.log" | grep -c -- '--has-metadata-key gc.routed_to')" "3" "every ready read asks for routed rows only"
eq "$(grep -c '^show ' "$TMP/calls.log")" "3" "the re-reads are one batch of candidates and one root batch per store"
eq "$(grep '^show ' "$TMP/calls.log" | grep -c 'sb-1 sb-2 sb-3 ')" "1" "one call re-reads every candidate"
clear_stores

# --- 15. the stores, and each store's listings, are read at once --------------
# Each of the three listings of each of the three stores takes 4s here. Read one
# after another they would take 36s, and with only the stores overlapping 12s;
# read at once they take about one listing's time.
S=$(date +%s)
OUT=$(BD_SLOW=all BD_SLOW_SECS=4 run_check); RC=$?
E=$(( $(date +%s) - S ))
eq "$RC" "0" "three slow stores still pass"
if [ "$E" -lt 10 ]; then ok "nine 4s listings overlap (took ${E}s)"
else bad "nine 4s listings overlap (took ${E}s, want under 10s)"; fi

# --- 16. findings come out in rig order, however the scans interleave ---------
# alpha's listings are slowed so beta's scan finishes first; the report still
# lists alpha's finding before beta's, as the rig list orders them.
store alpha "$(routed o-1 pack.polecat)"
store beta "$(routed o-2 pack.polecat)"
OUT=$(BD_SLOW=alpha BD_SLOW_SECS=2 run_check); RC=$?
eq "$RC" "2" "a finding in each of two stores is an ERROR"
case "$OUT" in
    *"alpha bead o-1"*"beta bead o-2"*) ok "the slower store's finding still comes first, in rig order" ;;
    *) bad "the slower store's finding still comes first, in rig order (got: $OUT)" ;;
esac
clear_stores

# --- 17. a scan that cannot report is a store NOT checked, never a pass -------
# The scans report through a scratch directory. Removed mid-run, as a scratch
# reaper would remove it, no store's report survives, and every store is named
# as not checked.
mkdir -p "$TMP/scratch"
store alpha "$(routed r-1 alpha/pack.polecat)"
OUT=$(TMPDIR="$TMP/scratch" BD_REAP_SCAN_AT=alpha run_check); RC=$?
eq "$RC" "1" "a run whose scans lost their scratch warns instead of passing"
has "$OUT" "alpha: the scan of $TMP/alpha/.beads ended without reporting — this store was NOT checked" "the store whose report was lost is named"
hasnt "$OUT" "OK:" "it never reads as a clean pass"
clear_stores

# --- 18. no scratch directory, no scan ----------------------------------------
OUT=$(TMPDIR="$TMP/no-such-dir" run_check); RC=$?
eq "$RC" "1" "with no scratch directory the check warns instead of passing"
has "$OUT" "could not create a scratch directory" "the warning names the missing scratch"

# --- 19. a listing that is not one JSON array is unreadable, not empty ---------
# A read that answers whitespace at rc 0 holds no array. Taken as an empty
# store it would pass the store, and taken as an empty ready queue it would
# flag every candidate it should have offered.
store alpha "$(routed w-1 alpha/pack.polecat)"
OUT=$(BD_BLANK=alpha:list run_check); RC=$?
eq "$RC" "1" "a whitespace open-bead listing warns instead of passing the store"
has "$OUT" "alpha: open-bead listing from $TMP/alpha/.beads could not be parsed — this store was NOT checked" "the warning names the unparsable listing"
OUT=$(BD_BLANK=alpha:ready run_check); RC=$?
eq "$RC" "1" "a whitespace ready queue warns instead of flagging the candidates"
has "$OUT" "the \`bd ready\`/\`bd blocked\` listings from $TMP/alpha/.beads could not be parsed" "the warning names the unparsable queue"
hasnt "$OUT" "no pool offers it" "no candidate is flagged from an unread queue"
clear_stores

echo
echo "check-routed-work-claimable: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
