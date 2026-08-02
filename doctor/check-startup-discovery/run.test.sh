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
#   (7)  quick-reference row lost --include-infra -> ERROR (fence-scoped
#        assertions never see this row, which is why it needs its own)
#   (8)  quick-reference row lost the mol-deacon-patrol scope -> ERROR
#   (9)  both boot sites deleted -> ERROR naming BOTH sites (the surrounding
#        prose names the same flags; it must not satisfy either assertion)
#   (10) whole boot block deleted -> ERROR, reported once as a missing define
#        rather than three times
#   (11) witness block deleted -> ERROR (pre-existing assertion, unaffected)
#   (12) deacon tier-2 query removed -> ERROR (pre-existing assertion, still
#        wired after the block/fence extraction was factored into helpers)
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

# rewrite_command <file> <needle> [replacement]
# Replace the whole LOGICAL command containing <needle> — a maximal run of
# backslash-continued lines — with <replacement>, or delete it if omitted.
# Line-based sed would leave a dangling `| jq ...` continuation behind.
rewrite_command() {
    awk -v needle="$2" -v repl="${3:-}" '
        { buf = buf $0 "\n" }
        /\\$/ { next }
        {
            if (index(buf, needle)) { if (repl != "") print repl }
            else printf "%s", buf
            buf = ""
        }
        END { if (buf != "" && index(buf, needle) == 0) printf "%s", buf }
    ' "$1" > "$1.new" && mv "$1.new" "$1"
}

# The fenced Step 2 wisp read, and the quick-reference row that mirrors it.
WISP_CMD='--type=molecule --include-infra --limit=0'
QUICKREF_ROW='| Check the deacon patrol wisp |'
BROAD_FORM='gc bd list --assignee={{ .BindingPrefix }}deacon --status=in_progress --json'

# --- (1) the shipped fragment ----------------------------------------------
D=$(pack shipped)
rc=$(run_check "$D")
eq "$rc" "0" "(1) shipped fragment -> exit 0"
has "boot carries the dedicated mol-deacon-patrol wisp read" "$D/out" \
    "(1) summary reports boot's read, and only when it is actually there"

# --- (2) fenced Step 2 query deleted ---------------------------------------
D=$(pack fenced-deleted)
rewrite_command "$(frag "$D")" "$WISP_CMD"
rc=$(run_check "$D")
eq "$rc" "2" "(2) deleting the fenced Step 2 wisp query -> exit 2"
has "boot: Step 2 wisp read is missing" "$D/out" "(2) the violation names the site"

# --- (3) quick-reference row deleted ---------------------------------------
D=$(pack quickref-deleted)
sed -i "/$QUICKREF_ROW/d" "$(frag "$D")"
rc=$(run_check "$D")
eq "$rc" "2" "(3) deleting the quick-reference wisp row -> exit 2"
has "boot: Command Quick-Reference wisp row is missing" "$D/out" \
    "(3) the violation names the site"

# --- (4) fenced query regressed to the broad untyped form ------------------
D=$(pack fenced-broad)
rewrite_command "$(frag "$D")" "$WISP_CMD" "$BROAD_FORM"
rc=$(run_check "$D")
eq "$rc" "2" "(4) fenced query back to the broad untyped form -> exit 2"
has "boot: Step 2 wisp read is missing" "$D/out" "(4) the regression is caught"

# --- (5) fenced query lost --limit=0 ---------------------------------------
D=$(pack fenced-capped)
sed -i 's/--type=molecule --include-infra --limit=0 --json/--type=molecule --include-infra --json/' \
    "$(frag "$D")"
rc=$(run_check "$D")
eq "$rc" "2" "(5) fenced query without --limit=0 -> exit 2"
has "boot: Step 2 wisp read is missing" "$D/out" "(5) an uncapped read is part of the contract"

# --- (6) fenced query lost --include-infra ---------------------------------
D=$(pack fenced-no-infra)
sed -i 's/--type=molecule --include-infra --limit=0/--type=molecule --limit=0/' "$(frag "$D")"
rc=$(run_check "$D")
eq "$rc" "2" "(6) fenced query without --include-infra -> exit 2"
has "missing --include-infra" "$D/out" "(6) the ephemeral-awareness assertion still fires"

# --- (7) quick-reference row lost --include-infra --------------------------
D=$(pack quickref-no-infra)
sed -i "/$QUICKREF_ROW/s/--include-infra //" "$(frag "$D")"
rc=$(run_check "$D")
eq "$rc" "2" "(7) quick-reference row without --include-infra -> exit 2"
has "boot: Command Quick-Reference wisp row is missing" "$D/out" \
    "(7) caught even though fence-scoped assertions cannot see the row"

# --- (8) quick-reference row lost the patrol-title scope -------------------
D=$(pack quickref-unscoped)
sed -i "/$QUICKREF_ROW/s/--title=mol-deacon-patrol //" "$(frag "$D")"
rc=$(run_check "$D")
eq "$rc" "2" "(8) quick-reference row without the patrol title -> exit 2"
has "boot: Command Quick-Reference wisp row is missing" "$D/out" "(8) the scope is required"

# --- (9) both sites gone, prose intact -------------------------------------
D=$(pack both-sites-deleted)
rewrite_command "$(frag "$D")" "$WISP_CMD"
sed -i "/$QUICKREF_ROW/d" "$(frag "$D")"
rc=$(run_check "$D")
eq "$rc" "2" "(9) both boot sites deleted -> exit 2"
eq "$(grep -c 'is missing the required patrol-wisp query' "$D/out")" "2" \
    "(9) both sites are reported, and prose naming the flags satisfies neither"

# --- (10) whole boot block deleted -----------------------------------------
D=$(pack boot-block-deleted)
sed -i '/{{ define "layered-startup-discovery-boot" }}/,/^{{ end }}$/d' "$(frag "$D")"
rc=$(run_check "$D")
eq "$rc" "2" "(10) whole boot block deleted -> exit 2"
has 'boot: missing {{ define "layered-startup-discovery-boot" }} block' "$D/out" \
    "(10) reported as a missing block"
eq "$(grep -c 'is missing the required patrol-wisp query' "$D/out")" "0" \
    "(10) a missing block is reported once, not once per required query"

# --- (11) witness block deleted (pre-existing assertion) -------------------
D=$(pack witness-deleted)
sed -i '/{{ define "layered-startup-discovery-witness" }}/,/^{{ end }}$/d' "$(frag "$D")"
rc=$(run_check "$D")
eq "$rc" "2" "(11) witness block deleted -> exit 2"
has 'witness: missing {{ define "layered-startup-discovery-witness" }} block' "$D/out" \
    "(11) the pre-existing witness assertion is unaffected"

# --- (12) deacon tier-2 query removed (pre-existing assertion) -------------
D=$(pack deacon-no-tier2)
sed -i 's/--has-metadata-key=branch/--has-metadata-key=BRANCHLESS/g' "$(frag "$D")"
rc=$(run_check "$D")
eq "$rc" "2" "(12) tier-2 query removed -> exit 2"
has "missing tier-2 routed-work-bead query" "$D/out" \
    "(12) the tier assertions survived factoring extraction into helpers"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
