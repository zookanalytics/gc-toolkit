#!/usr/bin/env bash
# Hermetic test for doctor/check-startup-discovery/run.sh, focused on the boot
# block's REQUIRED-QUERY assertion (tk-vl2nu).
#
# THE HOLE IT CLOSES: the ephemeral-awareness and title-scoping assertions are
# both negative — they score the `gc bd list --type=molecule` commands a block
# already has. Delete boot's wisp query outright and both score zero, so the
# check exited 0 while its own summary claimed boot's read was scoped. Found
# reviewing tk-jd4b8 by deleting the fenced query and re-running: still 0.
#
# Every case mutates a throwaway copy of the SHIPPED fragment, so the fixtures
# cannot drift from what boot actually reads. No live city, Dolt, or network.
#
# Covered:
#   (1)  shipped fragment satisfies every assertion -> OK (exit 0)
#   (2)  fenced Step 2 wisp query deleted -> ERROR   [was exit 0]
#   (3)  Command Quick-Reference wisp row deleted -> ERROR   [was exit 0]
#   (4)  fenced query regressed to the old broad untyped form -> ERROR
#   (5)  fenced query lost --limit=0 -> ERROR (crowd-out regression: an
#        uncapped read is what keeps a busy deacon's other in-progress rows
#        from pushing the wisp out of the result)
#   (6)  fenced query lost --include-infra -> ERROR
#   (7)  fenced query lost --assignee -> ERROR (an unscoped read lets a stale
#        orphan wisp feed the "very stale wisp" triage row a false positive)
#   (8)  fenced query lost --json -> ERROR (the command pipes into `jq`)
#   (9)  quick-reference row lost --include-infra -> ERROR (fence-scoped
#        assertions never see this row, which is why it needs its own)
#   (10) quick-reference row lost the mol-deacon-patrol scope -> ERROR
#   (11) quick-reference row lost --assignee -> ERROR
#   (12) quick-reference row lost --json -> ERROR
#   (13) both boot sites deleted -> ERROR naming BOTH sites (the surrounding
#        prose names the same flags; it must not satisfy either assertion)
#   (14) whole boot block deleted -> ERROR, reported once as a missing define
#        rather than three times
#   (15) witness block deleted -> ERROR (pre-existing assertion, unaffected)
#   (16) deacon tier-2 query removed -> ERROR (pre-existing assertion, still
#        wired after the block/fence extraction was factored into helpers)
#   (17) --status=in_progress reintroduced into the fenced wisp read -> ERROR,
#        and the required-query assertion does NOT fire (tk-a6kpx)
#   (18) --status=in_progress reintroduced into the quick-reference row -> same
#   (19) --status=open on the fenced read -> ERROR (any status filter, not just
#        the value that keeps recurring)
#   (20) the shipped fence's own `#` comment naming --status=in_progress does
#        not trip the absence assertion
#
# Cases 17-19 are the ones the absence assertion exists for, and each asserts
# that NO required-query violation accompanies it. That is the whole point: the
# mutated query still carries every required token, so the positive list passes
# it — which is how the flag drifted back in three times while a green check
# reported boot's read as correct. A case that only checked the exit code would
# pass on the wrong assertion and prove nothing.
#
# Every boot case mutates the boot block ONLY, through rewrite_boot_command or
# boot_sed. The strings they rewrite are not boot-unique — the wisp query's flag
# run appears verbatim in four witness lines — so an unscoped mutation breaks the
# witness block too, and a case whose assertion is not boot-labelled can then
# pass on witness fallout without proving the boot regression it is named for.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SCRIPT="$HERE/run.sh"
FRAGMENT="$ROOT/template-fragments/layered-startup-discovery.template.md"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has() { if grep -q -- "$1" "$2"; then ok "$3"; else bad "$3 (missing '$1' in $(cat "$2"))"; fi; }

# pack <name> — throwaway GC_PACK_DIR holding a pristine copy of the shipped
# fragment. Echoes the dir; `frag` locates the copy inside it.
pack() {
    local d="$TMP/$1"
    mkdir -p "$d/template-fragments"
    cp "$FRAGMENT" "$d/template-fragments/layered-startup-discovery.template.md"
    echo "$d"
}
frag() { echo "$1/template-fragments/layered-startup-discovery.template.md"; }

run_check() { # $1=pack dir -> echoes exit code, output in <pack>/out
    GC_PACK_DIR="$1" bash "$SCRIPT" > "$1/out" 2>&1
    echo $?
}

# rewrite_boot_command <file> <needle> [replacement]
# Replace the whole LOGICAL command containing <needle> — a maximal run of
# backslash-continued lines — with <replacement>, or delete it if omitted.
# Line-based sed would leave a dangling `| jq ...` continuation behind.
# Scoped to the boot block: the needles below also match witness commands.
rewrite_boot_command() {
    awk -v needle="$2" -v repl="${3:-}" '
        index($0, "{{ define \"layered-startup-discovery-boot\" }}") { in_boot = 1 }
        { buf = buf $0 "\n" }
        /\\$/ { next }
        {
            if (in_boot && index(buf, needle)) { if (repl != "") print repl }
            else printf "%s", buf
            buf = ""
            if ($0 == "{{ end }}") in_boot = 0
        }
        END { if (buf != "" && !(in_boot && index(buf, needle))) printf "%s", buf }
    ' "$1" > "$1.new" && mv "$1.new" "$1"
}

# boot_sed <file> <sed-program> — run <sed-program> against the boot block only,
# for the same reason. Braces so the program may carry its own address (the
# quick-reference row cases do).
BOOT_BLOCK='/{{ define "layered-startup-discovery-boot" }}/,/^{{ end }}$/'
boot_sed() { sed -i "$BOOT_BLOCK{$2;}" "$1"; }

# The fenced Step 2 wisp read, and the quick-reference row that mirrors it.
WISP_CMD='--type=molecule --include-infra --limit=0'
QUICKREF_ROW='| Check the deacon patrol wisp |'
BROAD_FORM='gc bd list --assignee={{ .BindingPrefix }}deacon --status=in_progress --json'
# Single-token regressions of the fenced read: each drops exactly one required
# token and keeps every other, so the required-query assertion is the only one
# that can fire and the case proves which token it is holding. Swapping the
# whole logical command — rather than sed-ing a flag out of it — is what leaves
# the sibling broad "what else is the deacon holding" query alone: that query
# shares its entire first line with the wisp read, verbatim.
#
# Neither fixture carries --status: it is forbidden here (tk-a6kpx), so leaving
# it in would fire the absence assertion alongside the missing-token one and
# these cases would stop isolating the token they are named for.
WISP_NO_ASSIGNEE='gc bd list --type=molecule --include-infra --limit=0 --json --title=mol-deacon-patrol'
WISP_NO_JSON='gc bd list --assignee={{ .BindingPrefix }}deacon --type=molecule --include-infra --limit=0 --title=mol-deacon-patrol'
# The forbidden filter, put back at each site. The fenced substitution matches
# the wisp read's flag run only — the quick-reference row orders the same flags
# differently, and the sibling broad query is untyped — so each case mutates one
# site and the other stays clean.
FENCED_FLAGS='--type=molecule --include-infra --limit=0 --json'

# --- (1) the shipped fragment ----------------------------------------------
D=$(pack shipped)
rc=$(run_check "$D")
eq "$rc" "0" "(1) shipped fragment -> exit 0"
has "boot carries the dedicated mol-deacon-patrol wisp read" "$D/out" \
    "(1) summary reports boot's read, and only when it is actually there"

# --- (2) fenced Step 2 query deleted ---------------------------------------
D=$(pack fenced-deleted)
rewrite_boot_command "$(frag "$D")" "$WISP_CMD"
rc=$(run_check "$D")
eq "$rc" "2" "(2) deleting the fenced Step 2 wisp query -> exit 2"
has "boot: Step 2 wisp read is missing" "$D/out" "(2) the violation names the site"

# --- (3) quick-reference row deleted ---------------------------------------
D=$(pack quickref-deleted)
boot_sed "$(frag "$D")" "/$QUICKREF_ROW/d"
rc=$(run_check "$D")
eq "$rc" "2" "(3) deleting the quick-reference wisp row -> exit 2"
has "boot: Command Quick-Reference wisp row is missing" "$D/out" \
    "(3) the violation names the site"

# --- (4) fenced query regressed to the broad untyped form ------------------
D=$(pack fenced-broad)
rewrite_boot_command "$(frag "$D")" "$WISP_CMD" "$BROAD_FORM"
rc=$(run_check "$D")
eq "$rc" "2" "(4) fenced query back to the broad untyped form -> exit 2"
has "boot: Step 2 wisp read is missing" "$D/out" "(4) the regression is caught"

# --- (5) fenced query lost --limit=0 ---------------------------------------
D=$(pack fenced-capped)
boot_sed "$(frag "$D")" \
    's/--type=molecule --include-infra --limit=0 --json/--type=molecule --include-infra --json/'
rc=$(run_check "$D")
eq "$rc" "2" "(5) fenced query without --limit=0 -> exit 2"
has "boot: Step 2 wisp read is missing" "$D/out" "(5) an uncapped read is part of the contract"

# --- (6) fenced query lost --include-infra ---------------------------------
# The assertion names boot, and the mutation is boot-scoped: the same flag run
# appears in four witness lines, and an unscoped sed made this case satisfiable
# by witness fallout alone.
D=$(pack fenced-no-infra)
boot_sed "$(frag "$D")" 's/--type=molecule --include-infra --limit=0/--type=molecule --limit=0/'
rc=$(run_check "$D")
eq "$rc" "2" "(6) fenced query without --include-infra -> exit 2"
has "boot: 1 wisp query(ies) missing --include-infra" "$D/out" \
    "(6) the ephemeral-awareness assertion fires, and fires for boot"

# --- (7) fenced query lost --assignee --------------------------------------
D=$(pack fenced-no-assignee)
rewrite_boot_command "$(frag "$D")" "$WISP_CMD" "$WISP_NO_ASSIGNEE"
rc=$(run_check "$D")
eq "$rc" "2" "(7) fenced query without --assignee -> exit 2"
has "boot: Step 2 wisp read is missing" "$D/out" \
    "(7) an unscoped read cannot pass as the deacon-wisp read"
eq "$(grep -c 'is missing the required patrol-wisp query' "$D/out")" "1" \
    "(7) only the fenced site is faulted — the quick-reference row is untouched"

# --- (8) fenced query lost --json ------------------------------------------
D=$(pack fenced-no-json)
rewrite_boot_command "$(frag "$D")" "$WISP_CMD" "$WISP_NO_JSON"
rc=$(run_check "$D")
eq "$rc" "2" "(8) fenced query without --json -> exit 2"
has "boot: Step 2 wisp read is missing" "$D/out" \
    "(8) the command pipes into jq, so --json is part of the contract"
eq "$(grep -c 'is missing the required patrol-wisp query' "$D/out")" "1" \
    "(8) only the fenced site is faulted"

# --- (9) quick-reference row lost --include-infra --------------------------
D=$(pack quickref-no-infra)
boot_sed "$(frag "$D")" "/$QUICKREF_ROW/s/--include-infra //"
rc=$(run_check "$D")
eq "$rc" "2" "(9) quick-reference row without --include-infra -> exit 2"
has "boot: Command Quick-Reference wisp row is missing" "$D/out" \
    "(9) caught even though fence-scoped assertions cannot see the row"

# --- (10) quick-reference row lost the patrol-title scope ------------------
D=$(pack quickref-unscoped)
boot_sed "$(frag "$D")" "/$QUICKREF_ROW/s/--title=mol-deacon-patrol //"
rc=$(run_check "$D")
eq "$rc" "2" "(10) quick-reference row without the patrol title -> exit 2"
has "boot: Command Quick-Reference wisp row is missing" "$D/out" "(10) the scope is required"

# --- (11) quick-reference row lost --assignee ------------------------------
D=$(pack quickref-no-assignee)
boot_sed "$(frag "$D")" "/$QUICKREF_ROW/s/--assignee={{ .BindingPrefix }}deacon //"
rc=$(run_check "$D")
eq "$rc" "2" "(11) quick-reference row without --assignee -> exit 2"
has "boot: Command Quick-Reference wisp row is missing" "$D/out" \
    "(11) the row is held to the same assignee scope as the fenced read"
eq "$(grep -c 'is missing the required patrol-wisp query' "$D/out")" "1" \
    "(11) only the row is faulted — the fenced read is untouched"

# --- (12) quick-reference row lost --json ----------------------------------
D=$(pack quickref-no-json)
boot_sed "$(frag "$D")" "/$QUICKREF_ROW/s/ --json//"
rc=$(run_check "$D")
eq "$rc" "2" "(12) quick-reference row without --json -> exit 2"
has "boot: Command Quick-Reference wisp row is missing" "$D/out" \
    "(12) the row is copied out to be parsed, so --json is required"
eq "$(grep -c 'is missing the required patrol-wisp query' "$D/out")" "1" \
    "(12) only the row is faulted"

# --- (13) both sites gone, prose intact ------------------------------------
D=$(pack both-sites-deleted)
rewrite_boot_command "$(frag "$D")" "$WISP_CMD"
boot_sed "$(frag "$D")" "/$QUICKREF_ROW/d"
rc=$(run_check "$D")
eq "$rc" "2" "(13) both boot sites deleted -> exit 2"
eq "$(grep -c 'is missing the required patrol-wisp query' "$D/out")" "2" \
    "(13) both sites are reported, and prose naming the flags satisfies neither"

# --- (14) whole boot block deleted -----------------------------------------
D=$(pack boot-block-deleted)
sed -i '/{{ define "layered-startup-discovery-boot" }}/,/^{{ end }}$/d' "$(frag "$D")"
rc=$(run_check "$D")
eq "$rc" "2" "(14) whole boot block deleted -> exit 2"
has 'boot: missing {{ define "layered-startup-discovery-boot" }} block' "$D/out" \
    "(14) reported as a missing block"
eq "$(grep -c 'is missing the required patrol-wisp query' "$D/out")" "0" \
    "(14) a missing block is reported once, not once per required query"

# --- (15) witness block deleted (pre-existing assertion) -------------------
D=$(pack witness-deleted)
sed -i '/{{ define "layered-startup-discovery-witness" }}/,/^{{ end }}$/d' "$(frag "$D")"
rc=$(run_check "$D")
eq "$rc" "2" "(15) witness block deleted -> exit 2"
has 'witness: missing {{ define "layered-startup-discovery-witness" }} block' "$D/out" \
    "(15) the pre-existing witness assertion is unaffected"

# --- (16) deacon tier-2 query removed (pre-existing assertion) -------------
D=$(pack deacon-no-tier2)
sed -i 's/--has-metadata-key=branch/--has-metadata-key=BRANCHLESS/g' "$(frag "$D")"
rc=$(run_check "$D")
eq "$rc" "2" "(16) tier-2 query removed -> exit 2"
has "missing tier-2 routed-work-bead query" "$D/out" \
    "(16) the tier assertions survived factoring extraction into helpers"

# --- (17) --status=in_progress back on the fenced read ---------------------
# The defect this whole assertion exists for: the deacon burns the previous wisp
# before claiming the next, so the live wisp is `open` across that window and a
# status-filtered read returns [] against a healthy deacon.
D=$(pack fenced-status-back)
boot_sed "$(frag "$D")" "s/$FENCED_FLAGS/--status=in_progress $FENCED_FLAGS/"
rc=$(run_check "$D")
eq "$rc" "2" "(17) --status=in_progress back on the fenced wisp read -> exit 2"
has "boot: Step 2 wisp read carries a --status filter" "$D/out" \
    "(17) the absence assertion fires, and fires for boot"
eq "$(grep -c 'is missing the required patrol-wisp query' "$D/out")" "0" \
    "(17) the required-token list still passes it — which is why absence must be asserted"
eq "$(grep -c 'carries a --status filter' "$D/out")" "1" \
    "(17) only the fenced site is faulted — the quick-reference row is untouched"

# --- (18) --status=in_progress back on the quick-reference row -------------
D=$(pack quickref-status-back)
boot_sed "$(frag "$D")" "/$QUICKREF_ROW/s/--type=molecule/--status=in_progress --type=molecule/"
rc=$(run_check "$D")
eq "$rc" "2" "(18) --status=in_progress back on the quick-reference row -> exit 2"
has "boot: Command Quick-Reference wisp row carries a --status filter" "$D/out" \
    "(18) the row gets its own absence assertion, as it does its own required-query one"
eq "$(grep -c 'is missing the required patrol-wisp query' "$D/out")" "0" \
    "(18) the required-token list still passes the row too"
eq "$(grep -c 'carries a --status filter' "$D/out")" "1" \
    "(18) only the row is faulted"

# --- (19) a different status value ------------------------------------------
# The assertion pins the ABSENCE of a status filter, not the one value that has
# recurred: --status=open false-empties the mirror-image window (a wisp already
# claimed and cooking), and every other value narrows a read whose answer is
# meant to be read off the row.
D=$(pack fenced-status-open)
boot_sed "$(frag "$D")" "s/$FENCED_FLAGS/--status=open $FENCED_FLAGS/"
rc=$(run_check "$D")
eq "$rc" "2" "(19) --status=open on the fenced wisp read -> exit 2"
has "boot: Step 2 wisp read carries a --status filter" "$D/out" \
    "(19) any status filter is pinned out, not just --status=in_progress"

# --- (20) the fence's own comment naming the forbidden flag ----------------
# The shipped fence documents why --status must stay out, naming the flag
# verbatim inside a `#` comment. The assertion scores only lines carrying the
# query's own selector tokens, so the comment must not read as a violation —
# case (1)'s exit 0 is what proves it, and this guards that case from silently
# ceasing to cover anything if the comment is ever reworded away.
D=$(pack shipped-comment)
eq "$(awk '/{{ define "layered-startup-discovery-boot" }}/{c=1} c{print} c&&/{{ end }}/{exit}' "$(frag "$D")" \
        | awk '/^[[:space:]]*```/ { f = !f; next }
               f && /^[[:space:]]*#/ && /--status=in_progress/ { n++ }
               END { print n + 0 }')" "1" \
    "(20) the shipped fence still carries the comment that names the forbidden flag"
eq "$(run_check "$D")" "0" \
    "(20) and a comment naming it does not trip the absence assertion"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
