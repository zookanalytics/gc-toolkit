#!/usr/bin/env bash
# Hermetic test for doctor/check-closed-implies-landed/run.sh — the
# closed-but-unlanded detector (component-model I5). Stubs `gc` (rig roster),
# `bd` (bead ledger) and `gh` (open-PR list) on PATH, and builds throwaway git
# repos so the origin-remote parse runs for real. No live city, Dolt, or
# network.
#
# Run it by hand: `bash doctor/check-closed-implies-landed/run.test.sh`.
# Nothing globs doctor/*/run.test.sh — like its siblings it is a reviewer- and
# author-invoked regression gate, not a discovered suite.
#
# Covered:
#   (1)  clean city: closed anchors whose PRs are not open -> OK (exit 0)
#   (2)  CLOSED + merge_result=pull_request + PR OPEN -> ERROR (exit 2), naming
#        rig, bead and the host-qualified repo#number   [the tk-fip23 class]
#   (3)  CLOSED + merge_result=pre_open_gate + PR OPEN -> ERROR (both in-flight
#        spellings)
#   (4)  CLOSED + NO merge_result + PR OPEN -> ERROR, and the row says which
#        spelling it wore                                [the tk-vnlll class]
#   (5)  merge_result=merged over an OPEN PR -> NOT flagged (a disposition)
#   (6)  merge_result=<a marker this check never heard of> -> NOT flagged; the
#        allow-list widens fail-closed
#   (7)  a review child (task_kind=review) -> NOT flagged
#   (8)  anchor_bead / source_anchor_bead / source_review_bead -> NOT flagged
#   (9)  a surviving gc.routed_to -> NOT flagged
#   (10) no branch -> NOT flagged, noted, and counted in the summary
#   (11) a worker assignee (neither empty nor refinery) -> NOT flagged
#   (12) tracking_only -> NOT flagged
#   (13) merge_hold -> WARN (exit 1), not ERROR: a human owns it
#   (14) merge_hold stored as a JSON BOOLEAN -> still held (the ascii_downcase
#        abort would otherwise evaporate the whole candidate set)
#   (15) two closed candidates on ONE open PR -> ERROR naming the ambiguity
#        phase 0a refuses on
#   (15b) ...but the same NUMBER in two different repositories is not ambiguity
#   (16) reopened_not_landed=PR#n@open -> ERROR with the re-close/flap message
#   (17) reopened_not_landed=PR#n (attempted, unconfirmed) -> the ORDINARY
#        error, not the flap message: that reopen may never have landed
#   (18) a PR not in the open list (merged or closed) -> NOT flagged
#   (19) a LIVE bead carrying merge_result for the same PR -> NOT flagged, and
#        the note names it        [acquits a closed rework child under a live
#                                  parent anchor, which carries no child marker]
#   (20) ...but the live-anchor lookup FAILING does not acquit anything: the
#        violation is reported with the lookup named as UNDETERMINED
#   (21a) a pr_url in ANOTHER repository, OPEN there -> ERROR reported against
#        THAT repository, never against this rig's same-numbered PR
#   (21b) ...MERGED there -> NOT flagged, even with #10 open here (the false
#        positive a per-repository read is what removes)
#   (21c) ...unreadable there -> WARN, never silently clean
#   (21d) ...past the cross-repository read cap -> UNDETERMINED, not a silent trim
#   (22) pr_number with no pr_url resolves against this rig's origin -> ERROR
#   (23) a suspended rig -> skipped, and its bead store is never queried
#   (24) rig roster unavailable -> WARN (exit 1), never a silent OK
#   (25) a bead store unavailable -> WARN (exit 1), never a silent OK
#   (26) the open-PR read failing -> WARN (exit 1), never a silent OK
#   (27) an unresolvable origin remote -> WARN (exit 1), store not checked
#   (28) `gh` absent from PATH -> WARN (exit 1)
#   (29) a FULL open-PR page -> WARN that a PR past it is invisible
#   (30) error outranks warning
#   (31) each rig's ledger is read with --db pinned to ITS OWN store
#   (32) the wall-clock budget stops the sweep and NAMES the stores it did not
#        reach, rather than overrunning the doctor's own --check-timeout (which
#        abandons the check and discards every finding it had collected)
#   (33) a failing `mktemp -d` refuses the scan rather than sweeping zero rows
#        and reporting the green summary  [the tk-lslk2 false-empty vector]
#   (34) THE FORK KEY SET (tk-p47n3f). merge-skill.sh and reconcile-merged-prs.sh
#        treat `fork_pr`/`fork_pr_url` as first-class PR keys, and the fork-sync
#        flow stamps NO pr_number at all, so a check keyed on pr_number alone
#        reports OK over exactly the violation it exists to find:
#        (34a) a bare fork_pr over an OPEN PR -> ERROR, against this rig origin
#        (34b) fork_pr_url only, no number key anywhere -> ERROR
#        (34c) a fork_pr_url naming ANOTHER repository is repository-qualified
#              exactly as a pr_url is: MERGED there is NOT flagged, even with
#              the same number open HERE
#        (34d) ...and a fork_pr qualified by a foreign fork_pr_url that is OPEN
#              there is reported against THAT repository
#        (34e) a bead naming two DIFFERENT PRs under pr_number and fork_pr is
#              judged on both — neither reference is deduped away
#        (34f) a LIVE fork_pr-keyed anchor acquits the spent closed predecessor
#              naming the same PR (the narrow lookup would have flagged it)
#        (34g) ...but the two families naming the SAME PR are ONE reference
#   (INV) detect-only: no fix.sh ships next to run.sh (a sibling fix.sh would
#        auto-opt this check into `gc doctor --fix`)
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/run.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }
# The greps below are lookups whose "found nothing" result is itself a
# legitimate assertion outcome, so they must report rather than abort.
has()   { grep -q -- "$1" "$2" && ok "$3" || bad "$3 (missing '$1' in: $(cat "$2"))"; }
hasnt() { grep -q -- "$1" "$2" && bad "$3 (unexpected '$1')" || ok "$3"; }

D="$TMP/fixtures"
export GC_STUB_DIR="$D"

# ---------------------------------------------------------------------------
# Stubs. Every invocation is logged so a test can assert that a suspended rig's
# store was never touched and that each --db was pinned to the right store.
# ---------------------------------------------------------------------------
mkdir -p "$TMP/bin"

cat > "$TMP/bin/gc" <<'STUB'
#!/usr/bin/env bash
D="${GC_STUB_DIR:?}"
echo "gc $*" >> "$D/calls.log"
if [ "${1:-}" = "rig" ] && [ "${2:-}" = "list" ]; then
    [ -f "$D/rigs-fail" ] && exit 1
    [ -f "$D/rigs.json" ] && { cat "$D/rigs.json"; exit 0; }
    exit 1
fi
exit 1
STUB

cat > "$TMP/bin/bd" <<'STUB'
#!/usr/bin/env bash
# Two shapes of `list` reach here and must not share a fixture: the CLOSED
# candidate scans (--status closed --has-metadata-key
# pr_url|pr_number|fork_pr|fork_pr_url) and the live-anchor lookup
# (--status=<live list> --has-metadata-key merge_result).
# One fixture for both would answer "is this PR already anchored?" with the
# candidate list itself.
D="${GC_STUB_DIR:?}"
echo "bd $*" >> "$D/calls.log"
[ "${1:-}" = "list" ] || exit 1
db=""; key=""; status=""; prev=""
for a in "$@"; do
    case "$prev" in
        --db) db="$a" ;;
        --has-metadata-key) key="$a" ;;
        --status) status="$a" ;;
    esac
    case "$a" in --status=*) status="${a#--status=}" ;; esac
    prev="$a"
done
# rig key = the directory holding .beads
rig="$(basename "$(dirname "$db")")"
[ -f "$D/bd-fail-$rig" ] && exit 1
case "$status" in
    closed) f="$D/closed-$key-$rig.json" ;;
    *)      f="$D/live-$rig.json" ;;
esac
# An absent fixture is an EMPTY store, not a broken one.
[ -f "$f" ] && { cat "$f"; exit 0; }
echo '[]'
exit 0
STUB

cat > "$TMP/bin/gh" <<'STUB'
#!/usr/bin/env bash
D="${GC_STUB_DIR:?}"
echo "gh $*" >> "$D/calls.log"
[ "${1:-}" = "pr" ] || exit 1
repo=""; prev=""
for a in "$@"; do
    [ "$prev" = "--repo" ] && repo="$a"
    prev="$a"
done
safe="$(printf '%s' "$repo" | tr -c 'A-Za-z0-9._-' '_')"
[ -f "$D/gh-fail" ] && exit 1
case "${2:-}" in
    list)
        f="$D/prs-$safe.json"
        [ -f "$f" ] && { cat "$f"; exit 0; }
        echo '[]'
        exit 0 ;;
    view)
        # The targeted cross-repository read. An absent fixture is an
        # UNREADABLE PR, not a merged one — the script must not read a failed
        # call as "it landed".
        f="$D/prstate-$safe-${3:-}"
        [ -f "$f" ] && { cat "$f"; exit 0; }
        exit 1 ;;
esac
exit 1
STUB

chmod +x "$TMP/bin/gc" "$TMP/bin/bd" "$TMP/bin/gh"
PATH="$TMP/bin:$PATH"
export PATH

# ---------------------------------------------------------------------------
# Fixture helpers.
# ---------------------------------------------------------------------------
RIGS_JSON=""

reset() {
    rm -rf "$D"
    mkdir -p "$D"
    : > "$D/calls.log"
    RIGS_JSON='{"rigs":[]}'
}

# mkrig <name> <origin-url|-> [suspended]
# Builds a REAL throwaway git repo so the origin parse in run.sh runs for real.
# `-` means "a repo with no origin remote at all".
mkrig() {
    # Split, not one `local`: word expansion happens BEFORE the builtin runs, so
    # a `path="$TMP/rigs/$name"` in the same statement expands $name unset.
    local name="$1" url="$2" susp="${3:-false}"
    local path="$TMP/rigs/$name"
    mkdir -p "$path"
    git -C "$path" init -q 2>/dev/null
    [ "$url" = "-" ] || git -C "$path" remote add origin "$url" 2>/dev/null
    RIGS_JSON=$(printf '%s' "$RIGS_JSON" | jq -c \
        --arg n "$name" --arg p "$path" --argjson s "$susp" \
        '.rigs += [{name:$n, path:$p, suspended:$s}]')
}

# closed <rig> <key: pr_url|pr_number|fork_pr|fork_pr_url> <json-array>
closed() { printf '%s' "$3" > "$D/closed-$2-$1.json"; }
# live <rig> <json-array>
live()   { printf '%s' "$2" > "$D/live-$1.json"; }
# prstate <host-qualified repo> <number> <OPEN|MERGED|CLOSED>
prstate() {
    local safe; safe="$(printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_')"
    printf '%s\n' "$3" > "$D/prstate-$safe-$2"
}
# prs <host-qualified repo> <json-array of {number}>
prs() {
    local safe; safe="$(printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_')"
    printf '%s' "$2" > "$D/prs-$safe.json"
}

OUT="$TMP/out"
RC=0
run_check() {
    printf '%s' "$RIGS_JSON" > "$D/rigs.json"
    set +e
    bash "$SCRIPT" > "$OUT" 2>&1
    RC=$?
    set -e
    set +e
}

# A closed anchor in the canonical gating shape, as one JSON object.
# bead <id> <pr_number> [merge_result] [extra-metadata-json]
bead() {
    # The extra-metadata default is a plain variable, never a `${4:-{}}`
    # in-word default: the braces there are the expansion's own and the value
    # reaches jq malformed, which silently yields an EMPTY fixture.
    local extra="${4:-}"
    [ -n "$extra" ] || extra='{}'
    jq -nc --arg id "$1" --arg n "$2" --arg mr "${3:-}" --argjson x "$extra" '
      {id:$id, status:"closed", assignee:"alpha/gc-toolkit.refinery",
       metadata: ({pr_number:$n, branch:("polecat/" + $id)}
                  + (if $mr == "" then {} else {merge_result:$mr} end)
                  + $x)}'
}

# foreign <id> <num> <foreign-repo-url-path> — a closed anchor whose pr_url
# names a repository other than its rig's origin.
foreign_bead() {
    jq -nc --arg id "$1" --arg n "$2" --arg u "$3" '
      {id:$id, status:"closed", assignee:"",
       metadata:{pr_number:$n, branch:("polecat/" + $id),
                 merge_result:"pull_request", pr_url:$u}}'
}

# fork_bead <id> <fork_pr|-> <merge_result|""> [fork_pr_url]
# The fork-sync shape: fork_pr / fork_pr_url and NO pr_number at all. `-` omits
# the number key, leaving fork_pr_url as the only thing naming a PR.
fork_bead() {
    local id="$1" n="$2" mr="${3:-}" u="${4:-}"
    jq -nc --arg id "$id" --arg n "$n" --arg mr "$mr" --arg u "$u" '
      {id:$id, status:"closed", assignee:"alpha/gc-toolkit.refinery",
       metadata: ({branch:("polecat/" + $id)}
                  + (if $n == "-" then {} else {fork_pr:$n} end)
                  + (if $u == "" then {} else {fork_pr_url:$u} end)
                  + (if $mr == "" then {} else {merge_result:$mr} end))}'
}

# ---------------------------------------------------------------------------
# (1) Clean city — closed anchors, none of their PRs open.
# ---------------------------------------------------------------------------
reset
mkrig alpha "git@github.com:acme/alpha.git"
closed alpha pr_number "[$(bead a-1 10 pull_request),$(bead a-2 11 "")]"
prs github.com/acme/alpha '[]'
run_check
eq "$RC" 0 "(1) clean city exits 0"
has "OK: no closed bead claims unlanded work" "$OUT" "(1) green summary"
has "2 anchor-shaped candidate PR reference(s), 0 with a still-open PR" "$OUT" "(1) summary states what was scanned"

# ---------------------------------------------------------------------------
# (2)(3)(4) The three non-terminal spellings, each over an OPEN PR.
# ---------------------------------------------------------------------------
reset
mkrig alpha "git@github.com:acme/alpha.git"
closed alpha pr_number "[$(bead a-1 10 pull_request),$(bead a-2 11 pre_open_gate),$(bead a-3 12 "")]"
prs github.com/acme/alpha '[{"number":10},{"number":11},{"number":12}]'
run_check
eq "$RC" 2 "(2) a closed bead over an open PR exits 2"
has "3 closed bead(s) claim work that has not landed" "$OUT" "(2) headline counts all three"
has "alpha/a-1: CLOSED over OPEN github.com/acme/alpha#10" "$OUT" "(2) names rig, bead and host-qualified repo#number"
has "merge_result=pull_request, which records a HANDOFF" "$OUT" "(2) says which spelling"
has "alpha/a-2: CLOSED over OPEN github.com/acme/alpha#11" "$OUT" "(3) pre_open_gate is flagged too"
has "merge_result=pre_open_gate" "$OUT" "(3) names the pre_open_gate spelling"
has "alpha/a-3: CLOSED over OPEN github.com/acme/alpha#12" "$OUT" "(4) an ABSENT merge_result is flagged"
has "NO merge_result at all" "$OUT" "(4) names the tk-vnlll spelling"

# ---------------------------------------------------------------------------
# (5)(6) Terminal dispositions, and an unknown marker, over OPEN PRs.
# ---------------------------------------------------------------------------
reset
mkrig alpha "git@github.com:acme/alpha.git"
closed alpha pr_number "[$(bead a-1 10 merged),$(bead a-2 11 abandoned),$(bead a-3 12 retargeted),$(bead a-4 13 some_future_marker)]"
prs github.com/acme/alpha '[{"number":10},{"number":11},{"number":12},{"number":13}]'
run_check
eq "$RC" 0 "(5) terminal dispositions over an open PR are not flagged"
hasnt "a-1" "$OUT" "(5) merged is out of scope"
hasnt "a-2" "$OUT" "(5) abandoned is out of scope"
hasnt "a-3" "$OUT" "(5) retargeted is out of scope"
hasnt "a-4" "$OUT" "(6) an unknown marker reads as a disposition (allow-list widens fail-closed)"

# ---------------------------------------------------------------------------
# (7)(8)(9) Children and routed beads are not landing claims.
# ---------------------------------------------------------------------------
reset
mkrig alpha "git@github.com:acme/alpha.git"
closed alpha pr_number "[
  $(bead a-rev 10 pull_request '{"task_kind":"review"}'),
  $(bead a-ab  11 pull_request '{"anchor_bead":"a-1"}'),
  $(bead a-sa  12 pull_request '{"source_anchor_bead":"a-1"}'),
  $(bead a-sr  13 pull_request '{"source_review_bead":"a-rev"}'),
  $(bead a-rt  14 pull_request '{"gc.routed_to":"alpha/gc-toolkit.polecat"}')
]"
prs github.com/acme/alpha '[{"number":10},{"number":11},{"number":12},{"number":13},{"number":14}]'
run_check
eq "$RC" 0 "(7)(8)(9) children and routed beads are not flagged"
hasnt "a-rev" "$OUT" "(7) a review child is not a landing claim"
hasnt "a-ab" "$OUT" "(8) anchor_bead excludes"
hasnt "a-sa" "$OUT" "(8) source_anchor_bead excludes"
hasnt "a-sr" "$OUT" "(8) source_review_bead excludes"
hasnt "a-rt" "$OUT" "(9) a surviving gc.routed_to excludes"
has "0 anchor-shaped candidate PR reference(s)" "$OUT" "(7) they never even become candidates"

# ---------------------------------------------------------------------------
# (10)(11)(12) Shapes that reach the classifier and are noted, not flagged.
# ---------------------------------------------------------------------------
reset
mkrig alpha "git@github.com:acme/alpha.git"
NOBRANCH=$(jq -nc '{id:"a-nb", status:"closed", assignee:"",
                    metadata:{pr_number:"10", merge_result:"pull_request"}}')
WORKER=$(jq -nc '{id:"a-wk", status:"closed", assignee:"alpha/gc-toolkit.furiosa",
                  metadata:{pr_number:"11", branch:"polecat/a-wk", merge_result:"pull_request"}}')
closed alpha pr_number "[$NOBRANCH,$WORKER,$(bead a-tr 12 pull_request '{"tracking_only":"true"}')]"
prs github.com/acme/alpha '[{"number":10},{"number":11},{"number":12}]'
run_check
eq "$RC" 0 "(10)(11)(12) branchless, worker-assigned and tracking_only are not flagged"
has "records no branch" "$OUT" "(10) the branchless bead is noted, not dropped silently"
has "1 branchless, not a landing claim" "$OUT" "(10) and counted in the summary"
has "not the gating anchor shape" "$OUT" "(11) a worker assignee is noted"
has "tracking_only record" "$OUT" "(12) tracking_only is noted"
has "3 with a still-open PR" "$OUT" "(10) all three did reach the classifier"

# ---------------------------------------------------------------------------
# (13)(14) An operator hold is a WARNING — a human owns it — including when the
# marker was stored as a JSON boolean rather than a string.
# ---------------------------------------------------------------------------
reset
mkrig alpha "git@github.com:acme/alpha.git"
BOOLHOLD=$(jq -nc '{id:"a-bh", status:"closed", assignee:"",
                    metadata:{pr_number:"11", branch:"polecat/a-bh",
                              merge_result:"pull_request", merge_hold:true}}')
closed alpha pr_number "[$(bead a-mh 10 pull_request '{"merge_hold":"operator"}'),$BOOLHOLD]"
prs github.com/acme/alpha '[{"number":10},{"number":11}]'
run_check
eq "$RC" 1 "(13) an operator hold warns rather than errors"
has "WARN:  alpha/a-mh" "$OUT" "(13) the held bead is a warning"
has "under an operator hold (merge_hold=operator)" "$OUT" "(13) names the hold"
has "WARN:  alpha/a-bh" "$OUT" "(14) a BOOLEAN merge_hold still holds"
has "merge_hold=true" "$OUT" "(14) and renders the boolean"
hasnt "ERROR:" "$OUT" "(13) neither is escalated to an error"

# ---------------------------------------------------------------------------
# (15) Two closed candidates on one open PR — phase 0a refuses, silently.
# ---------------------------------------------------------------------------
reset
mkrig alpha "git@github.com:acme/alpha.git"
closed alpha pr_number "[$(bead a-1 10 pull_request),$(bead a-2 10 pull_request)]"
prs github.com/acme/alpha '[{"number":10}]'
run_check
eq "$RC" 2 "(15) an ambiguous PR errors"
has "NOT the only closed candidate naming that PR" "$OUT" "(15) names the ambiguity"
has "reopens NEITHER" "$OUT" "(15) says the healer refuses"
eq "$(grep -c 'ERROR:' "$OUT")" 2 "(15) both candidates are reported"

# (15b) The SAME number in two DIFFERENT repositories is not ambiguity. A pull
# number is unique only within a repository, so keying the duplicate check on
# the number alone would fuse two unrelated anchors into one unresolvable pair
# and stop naming either as the ordinary repair it is.
reset
mkrig alpha "git@github.com:acme/alpha.git"
closed alpha pr_number "[$(bead a-1 10 pull_request)]"
closed alpha pr_url "[$(foreign_bead a-2 10 https://github.com/other/repo/pull/10)]"
prs github.com/acme/alpha '[{"number":10}]'
prstate github.com/other/repo 10 OPEN
run_check
eq "$RC" 2 "(15b) both are errors"
eq "$(grep -c 'ERROR:' "$OUT")" 2 "(15b) reported separately"
hasnt "NOT the only closed candidate" "$OUT" "(15b) and neither is called ambiguous — the key carries the repository"

# ---------------------------------------------------------------------------
# (16)(17) The staged reopened_not_landed marker: CONFIRMED is the flap case,
# ATTEMPTED is an ordinary retry.
# ---------------------------------------------------------------------------
reset
mkrig alpha "git@github.com:acme/alpha.git"
closed alpha pr_number "[
  $(bead a-cf 10 pull_request '{"reopened_not_landed":"PR#10@open"}'),
  $(bead a-at 11 pull_request '{"reopened_not_landed":"PR#11"}')
]"
prs github.com/acme/alpha '[{"number":10},{"number":11}]'
run_check
eq "$RC" 2 "(16) both marker states error"
has "already reopened it once and CONFIRMED it open" "$OUT" "(16) the confirmed marker is the flap case"
has "find the writer that is re-closing it" "$OUT" "(16) and names the next action"
has "alpha/a-at: CLOSED over OPEN" "$OUT" "(17) an ATTEMPTED marker is reported"
has "should reopen it on the next refinery-reconcile tick" "$OUT" "(17) as the ORDINARY retry case"

# ---------------------------------------------------------------------------
# (18) A PR that is not open is the whole point — nothing to report.
# ---------------------------------------------------------------------------
reset
mkrig alpha "git@github.com:acme/alpha.git"
closed alpha pr_number "[$(bead a-1 10 pull_request)]"
prs github.com/acme/alpha '[{"number":99}]'
run_check
eq "$RC" 0 "(18) a merged/closed PR leaves the bead alone"
hasnt "a-1" "$OUT" "(18) and it is not named"

# ---------------------------------------------------------------------------
# (19) A LIVE bead carrying merge_result for the same PR IS the anchor. This is
# the shape a closed rework child under a live parent anchor wears — it carries
# no child metadata marker at all, so only this lookup acquits it.
# ---------------------------------------------------------------------------
reset
mkrig alpha "git@github.com:acme/alpha.git"
closed alpha pr_number "[$(bead a-child 10 "")]"
live alpha '[{"id":"a-parent","status":"open","metadata":{"pr_number":"10","merge_result":"pull_request"}}]'
prs github.com/acme/alpha '[{"number":10}]'
run_check
eq "$RC" 0 "(19) a PR already anchored by a live bead is not flagged"
has "NOT flagged: alpha/a-parent is live" "$OUT" "(19) and the note names the anchor"
has "1 already anchored by a live bead" "$OUT" "(19) counted in the summary"

# ---------------------------------------------------------------------------
# (20) ...but an unreadable live lookup must not acquit anything.
# ---------------------------------------------------------------------------
reset
mkrig alpha "git@github.com:acme/alpha.git"
closed alpha pr_number "[$(bead a-1 10 pull_request)]"
prs github.com/acme/alpha '[{"number":10}]'
run_check_with_live_fail() {
    printf '%s' "$RIGS_JSON" > "$D/rigs.json"
    # A `bd` that answers the closed scans and then dies on the live lookup.
    cat > "$TMP/bin/bd" <<'STUB'
#!/usr/bin/env bash
D="${GC_STUB_DIR:?}"
echo "bd $*" >> "$D/calls.log"
[ "${1:-}" = "list" ] || exit 1
db=""; key=""; status=""; prev=""
for a in "$@"; do
    case "$prev" in
        --db) db="$a" ;;
        --has-metadata-key) key="$a" ;;
        --status) status="$a" ;;
    esac
    case "$a" in --status=*) status="${a#--status=}" ;; esac
    prev="$a"
done
rig="$(basename "$(dirname "$db")")"
case "$status" in
    closed) f="$D/closed-$key-$rig.json"; [ -f "$f" ] && { cat "$f"; exit 0; }; echo '[]'; exit 0 ;;
    *) exit 1 ;;
esac
STUB
    chmod +x "$TMP/bin/bd"
    bash "$SCRIPT" > "$OUT" 2>&1
    RC=$?
}
run_check_with_live_fail
eq "$RC" 2 "(20) an unreadable live-anchor lookup still reports the violation"
has "UNDETERMINED" "$OUT" "(20) and names the lookup as undetermined"
# Restore the ordinary bd stub for the remaining scenarios.
cat > "$TMP/bin/bd" <<'STUB'
#!/usr/bin/env bash
D="${GC_STUB_DIR:?}"
echo "bd $*" >> "$D/calls.log"
[ "${1:-}" = "list" ] || exit 1
db=""; key=""; status=""; prev=""
for a in "$@"; do
    case "$prev" in
        --db) db="$a" ;;
        --has-metadata-key) key="$a" ;;
        --status) status="$a" ;;
    esac
    case "$a" in --status=*) status="${a#--status=}" ;; esac
    prev="$a"
done
rig="$(basename "$(dirname "$db")")"
[ -f "$D/bd-fail-$rig" ] && exit 1
case "$status" in
    closed) f="$D/closed-$key-$rig.json" ;;
    *)      f="$D/live-$rig.json" ;;
esac
[ -f "$f" ] && { cat "$f"; exit 0; }
echo '[]'
exit 0
STUB
chmod +x "$TMP/bin/bd"

# ---------------------------------------------------------------------------
# (21) A pr_url in ANOTHER repository. A pull number is unique only within a
# repository, so this repo's open-PR list cannot answer for it — and a
# same-numbered PR open HERE must not flag it.
# ---------------------------------------------------------------------------
# (21a) OPEN in the repository it actually names -> ERROR, reported against
# THAT repository. A same-numbered PR open here must not be what decides it.
reset
mkrig alpha "git@github.com:acme/alpha.git"
closed alpha pr_url "[$(foreign_bead a-fx 10 https://github.com/other/repo/pull/10)]"
prs github.com/acme/alpha '[{"number":10}]'
prstate github.com/other/repo 10 OPEN
run_check
eq "$RC" 2 "(21a) a foreign PR confirmed OPEN is an error"
has "CLOSED over OPEN github.com/other/repo#10" "$OUT" "(21a) reported against the repository it names"
hasnt "acme/alpha#10" "$OUT" "(21a) not against this rig's same-numbered PR"

# (21b) MERGED there -> not flagged, even though #10 is open HERE. Without the
# per-repository read this is exactly the false positive.
reset
mkrig alpha "git@github.com:acme/alpha.git"
closed alpha pr_url "[$(foreign_bead a-fx 10 https://github.com/other/repo/pull/10)]"
prs github.com/acme/alpha '[{"number":10}]'
prstate github.com/other/repo 10 MERGED
run_check
eq "$RC" 0 "(21b) a foreign PR that merged is not flagged"
hasnt "a-fx" "$OUT" "(21b) and is not named"

# (21c) unreadable there -> WARN, never silently clean.
reset
mkrig alpha "git@github.com:acme/alpha.git"
closed alpha pr_url "[$(foreign_bead a-fx 10 https://github.com/other/repo/pull/10)]"
prs github.com/acme/alpha '[]'
run_check
eq "$RC" 1 "(21c) an unreadable foreign PR warns"
has "state could not be read" "$OUT" "(21c) and says so"
has "github.com/other/repo" "$OUT" "(21c) naming the foreign repository"

# (21d) the cross-repository read cap: past it, UNDETERMINED rather than a
# silent trim.
reset
mkrig alpha "git@github.com:acme/alpha.git"
FBEADS=""
for i in $(seq 1 26); do
    [ -z "$FBEADS" ] || FBEADS="$FBEADS,"
    FBEADS="$FBEADS$(foreign_bead "a-f$i" "$i" "https://github.com/other/repo/pull/$i")"
    prstate github.com/other/repo "$i" OPEN
done
closed alpha pr_url "[$FBEADS]"
prs github.com/acme/alpha '[]'
run_check
eq "$RC" 2 "(21d) foreign PRs confirmed open still error"
eq "$(grep -c 'ERROR:' "$OUT")" 25 "(21d) exactly the cap is read"
has "WARN:  alpha: closed bead .* past this run's cap of 25 cross-repository reads" "$OUT" "(21d) and the overflow is a WARNING — a note would let a silent trim read as clean"

# ---------------------------------------------------------------------------
# (22) pr_number with no pr_url resolves against this rig's own origin.
# ---------------------------------------------------------------------------
reset
mkrig alpha "https://github.com/acme/alpha.git"
closed alpha pr_number "[$(bead a-1 10 pull_request)]"
prs github.com/acme/alpha '[{"number":10}]'
run_check
eq "$RC" 2 "(22) an https origin parses and a bare pr_number resolves against it"
has "github.com/acme/alpha#10" "$OUT" "(22) named in the rig's own repository"

# ---------------------------------------------------------------------------
# (23) A suspended rig is skipped, and its store is never opened.
# ---------------------------------------------------------------------------
reset
mkrig alpha "git@github.com:acme/alpha.git"
mkrig zeta  "git@github.com:acme/zeta.git" true
closed zeta pr_number "[$(bead z-1 10 pull_request)]"
prs github.com/acme/zeta '[{"number":10}]'
run_check
eq "$RC" 0 "(23) a suspended rig does not fail the check"
has "zeta: skipped (suspended" "$OUT" "(23) and is reported as skipped"
hasnt "z-1" "$OUT" "(23) its beads are never judged"
grep -q "rigs/zeta/.beads" "$D/calls.log" && bad "(23) the suspended rig's store was queried" || ok "(23) the suspended rig's store was never queried"

# ---------------------------------------------------------------------------
# (24)(25)(26)(27)(28) Every unreadable input is a warning, never a silent OK.
# ---------------------------------------------------------------------------
reset
mkrig alpha "git@github.com:acme/alpha.git"
: > "$D/rigs-fail"
run_check
eq "$RC" 1 "(24) an unavailable rig roster warns"
has "cannot determine whether any closed bead is unlanded" "$OUT" "(24) and says nothing was scanned"

reset
mkrig alpha "git@github.com:acme/alpha.git"
: > "$D/bd-fail-alpha"
run_check
eq "$RC" 1 "(25) an unavailable bead store warns"
has "this store was NOT checked" "$OUT" "(25) naming what was skipped"

reset
mkrig alpha "git@github.com:acme/alpha.git"
closed alpha pr_number "[$(bead a-1 10 pull_request)]"
: > "$D/gh-fail"
run_check
eq "$RC" 1 "(26) an unreadable open-PR list warns"
has "did not return a readable result" "$OUT" "(26) and says the candidates were not checked"
hasnt "OK: no closed bead" "$OUT" "(26) it never reads as clean"

reset
mkrig noremote "-"
run_check
eq "$RC" 1 "(27) a rig with no origin remote warns"
has "cannot resolve" "$OUT" "(27) naming the unresolvable checkout"

reset
mkrig alpha "git@github.com:acme/alpha.git"
closed alpha pr_number "[$(bead a-1 10 pull_request)]"
# A PATH that genuinely lacks gh. Hiding only the STUB is not enough — the real
# gh is still on the inherited PATH, `command -v gh` succeeds, and the arm under
# test never runs (it reports an unreadable PR list instead, which is a
# different arm passing for the wrong reason).
mkdir -p "$TMP/nogh"
NOGH_OK=1
for t in bash env jq git timeout tr sed grep awk mktemp rm cat basename dirname; do
    p="$(command -v "$t" 2>/dev/null || true)"
    if [ -n "$p" ]; then ln -sf "$p" "$TMP/nogh/$t"; else NOGH_OK=0; fi
done
ln -sf "$TMP/bin/gc" "$TMP/nogh/gc"
ln -sf "$TMP/bin/bd" "$TMP/nogh/bd"
if [ "$NOGH_OK" = 1 ] && ! PATH="$TMP/nogh" command -v gh >/dev/null 2>&1; then
    printf '%s' "$RIGS_JSON" > "$D/rigs.json"
    PATH="$TMP/nogh" bash "$SCRIPT" > "$OUT" 2>&1
    RC=$?
    eq "$RC" 1 "(28) gh absent from PATH warns"
    has "is not on PATH" "$OUT" "(28) and names the missing tool"
else
    bad "(28) could not build a gh-free PATH, so the arm was not exercised"
fi

# ---------------------------------------------------------------------------
# (29) A full open-PR page is reported rather than assumed complete.
# ---------------------------------------------------------------------------
reset
mkrig alpha "git@github.com:acme/alpha.git"
closed alpha pr_number "[$(bead a-1 1 pull_request)]"
prs github.com/acme/alpha "$(jq -nc '[range(1;1001) | {number: .}]')"
run_check
has "returned a FULL page (1000)" "$OUT" "(29) a full PR page is reported"

# ---------------------------------------------------------------------------
# (30) Error outranks warning.
# ---------------------------------------------------------------------------
reset
mkrig alpha "git@github.com:acme/alpha.git"
mkrig beta  "-"
closed alpha pr_number "[$(bead a-1 10 pull_request)]"
prs github.com/acme/alpha '[{"number":10}]'
run_check
eq "$RC" 2 "(30) an error outranks a warning"
has "ERROR: alpha/a-1" "$OUT" "(30) the error is reported"
has "WARN:  beta: cannot resolve" "$OUT" "(30) and the warning still surfaces"

# ---------------------------------------------------------------------------
# (31) Each rig's ledger is read with --db pinned to ITS OWN store. An ambient
# BEADS_DIR would otherwise report one rig's beads under every rig's name.
# ---------------------------------------------------------------------------
reset
mkrig alpha "git@github.com:acme/alpha.git"
mkrig beta  "git@github.com:acme/beta.git"
run_check
has "rigs/alpha/.beads" "$D/calls.log" "(31) alpha's store is read by explicit --db"
has "rigs/beta/.beads" "$D/calls.log" "(31) beta's store is read by explicit --db"
eq "$(grep -c -- '--db' "$D/calls.log")" "8" "(31) exactly four key scans per rig, each --db pinned"

# ---------------------------------------------------------------------------
# (32) The wall-clock budget. A zero budget means every rig is past it, so the
# sweep must stop at the first one and say which stores it never reached — the
# alternative is overrunning `gc doctor --check-timeout`, which abandons the
# check and reports "outcome unknown" for all of them.
# ---------------------------------------------------------------------------
reset
mkrig alpha "git@github.com:acme/alpha.git"
mkrig beta  "git@github.com:acme/beta.git"
closed alpha pr_number "[$(bead a-1 10 pull_request)]"
prs github.com/acme/alpha '[{"number":10}]'
printf '%s' "$RIGS_JSON" > "$D/rigs.json"
GC_DOCTOR_CHECK_BUDGET=0 bash "$SCRIPT" > "$OUT" 2>&1
RC=$?
eq "$RC" 1 "(32) a spent budget warns"
has "stopped after 0 of 2 rig(s)" "$OUT" "(32) naming how many stores were reached"
has "were NOT checked" "$OUT" "(32) and that the rest were not"
hasnt "OK: no closed bead" "$OUT" "(32) it never reads as clean"
grep -q 'rigs/alpha/.beads' "$D/calls.log" && bad "(32) a store was queried past the budget" || ok "(32) no store was queried past the budget"

# ---------------------------------------------------------------------------
# (33) A failing `mktemp -d`. The enumeration loops are fed from a checked
# backing file precisely because bash creates a here-string's temp file
# SILENTLY: under disk pressure that redirection fails, the loop body runs zero
# times, and the check falls through to its green summary — indistinguishable
# from a healthy empty result (tk-lslk2). A bad TMPDIR cannot force this (bash
# validates it and falls back to /tmp), so the vector is a failing mktemp.
# ---------------------------------------------------------------------------
reset
mkrig alpha "git@github.com:acme/alpha.git"
closed alpha pr_number "[$(bead a-1 10 pull_request)]"
prs github.com/acme/alpha '[{"number":10}]'
mkdir -p "$TMP/nomktemp"
cat > "$TMP/nomktemp/mktemp" <<'MKSTUB'
#!/usr/bin/env bash
exit 1
MKSTUB
chmod +x "$TMP/nomktemp/mktemp"
printf '%s' "$RIGS_JSON" > "$D/rigs.json"
PATH="$TMP/nomktemp:$PATH" bash "$SCRIPT" > "$OUT" 2>&1
RC=$?
eq "$RC" 1 "(33) a failing mktemp refuses the scan"
has "refusing to scan" "$OUT" "(33) and says so rather than sweeping silently"
hasnt "OK: no closed bead" "$OUT" "(33) it never reads as clean"

# ---------------------------------------------------------------------------
# (34) THE FORK KEY SET. `pr_number`/`pr_url` is what the refinery stamps, but
# the fork-sync flow stamps `fork_pr`/`fork_pr_url` and no pr_number at all —
# merge-skill.sh (PR_NUM_JQ, PR_SELF_JQ) and reconcile-merged-prs.sh (pr_refs)
# both read all three keys, and reconcile-merged-prs.test.sh already carries a
# closed fork_pr-keyed anchor over an open PR. Read narrowly, every case below
# is invisible: the store scan never enumerates the bead, so no later stage can
# recover it, and the check reports OK over a live violation (tk-p47n3f).
# ---------------------------------------------------------------------------
# (34a) A bare fork_pr, no URL of any kind -> resolves against this rig origin.
reset
mkrig alpha "git@github.com:acme/alpha.git"
closed alpha fork_pr "[$(fork_bead a-fk 42 pull_request)]"
prs github.com/acme/alpha '[{"number":42}]'
run_check
eq "$RC" 2 "(34a) a fork_pr-keyed closed anchor over an open PR is an error"
has "alpha/a-fk: CLOSED over OPEN github.com/acme/alpha#42" "$OUT" "(34a) named against this rig own repository"

# (34b) fork_pr_url and nothing else — no number key anywhere on the bead.
reset
mkrig alpha "git@github.com:acme/alpha.git"
closed alpha fork_pr_url "[$(fork_bead a-fu - pull_request https://github.com/acme/alpha/pull/43)]"
prs github.com/acme/alpha '[{"number":43}]'
run_check
eq "$RC" 2 "(34b) a fork_pr_url-keyed closed anchor over an open PR is an error"
has "alpha/a-fu: CLOSED over OPEN github.com/acme/alpha#43" "$OUT" "(34b) the number is parsed out of fork_pr_url"

# (34c) A fork_pr_url naming ANOTHER repository is repository-qualified exactly
# as a pr_url is. MERGED there, and #10 open HERE, must stay clean — matching
# this rig same-numbered PR would be answering about a stranger.
reset
mkrig alpha "git@github.com:acme/alpha.git"
closed alpha fork_pr_url "[$(fork_bead a-fx - pull_request https://github.com/other/repo/pull/10)]"
prs github.com/acme/alpha '[{"number":10}]'
prstate github.com/other/repo 10 MERGED
run_check
eq "$RC" 0 "(34c) a foreign fork_pr_url that merged is not flagged"
hasnt "a-fx" "$OUT" "(34c) and is not named"
# A "not flagged" assertion passes for free against a script that never
# enumerated the bead. Pin that it WAS scanned and DID become a candidate, so
# this case can only pass by way of the per-repository read.
has "1 closed PR-referencing bead(s) scanned, 1 anchor-shaped candidate PR reference(s), 0 with a still-open PR" "$OUT" "(34c) and the clean verdict came from reading that repository, not from never scanning the bead"

# (34d) ...and the number key qualified by that same foreign URL is read there
# too: fork_pr places its repository from fork_pr_url, never from origin.
reset
mkrig alpha "git@github.com:acme/alpha.git"
closed alpha fork_pr "[$(fork_bead a-fy 10 pull_request https://github.com/other/repo/pull/10)]"
prs github.com/acme/alpha '[{"number":10}]'
prstate github.com/other/repo 10 OPEN
run_check
eq "$RC" 2 "(34d) a fork_pr in another repository, open there, is an error"
has "CLOSED over OPEN github.com/other/repo#10" "$OUT" "(34d) reported against the repository fork_pr_url names"
hasnt "acme/alpha#10" "$OUT" "(34d) not against this rig same-numbered PR"

# (34e) One bead, two DIFFERENT PRs under two keys. It is closed over both, so
# both are judged; a projection yielding one pair per bead drops whichever key
# it did not prefer, and a survivor set deduped on the bead id alone drops the
# second reference after the fact. Fixtured under both keys because a live `bd`
# returns such a bead from both scans.
reset
mkrig alpha "git@github.com:acme/alpha.git"
TWOKEY=$(jq -nc '{id:"a-two", status:"closed", assignee:"alpha/gc-toolkit.refinery",
                  metadata:{pr_number:"50", fork_pr:"51", branch:"polecat/a-two",
                            merge_result:"pull_request"}}')
closed alpha pr_number "[$TWOKEY]"
closed alpha fork_pr   "[$TWOKEY]"
prs github.com/acme/alpha '[{"number":50},{"number":51}]'
run_check
eq "$RC" 2 "(34e) a bead naming two open PRs errors"
has "github.com/acme/alpha#50" "$OUT" "(34e) the pr_number reference is judged"
has "github.com/acme/alpha#51" "$OUT" "(34e) and so is the fork_pr one"
eq "$(grep -c 'ERROR:' "$OUT")" 2 "(34e) both references are reported, neither deduped away"

# (34f) The live-owner half. A LIVE fork_pr-keyed anchor IS the bead the merge
# path sees holding this PR, so the closed one is a spent predecessor. Looked
# up on pr_number alone the live owner is invisible and the predecessor is
# flagged — a false positive on a perfectly tracked PR.
reset
mkrig alpha "git@github.com:acme/alpha.git"
closed alpha fork_pr "[$(fork_bead a-old 60 pull_request)]"
live alpha '[{"id":"a-live", "status":"open", "metadata":{"fork_pr":"60", "merge_result":"pull_request"}}]'
prs github.com/acme/alpha '[{"number":60}]'
run_check
eq "$RC" 0 "(34f) a live fork_pr-keyed anchor acquits the closed predecessor"
has "alpha/a-live is live and carries a merge_result for the same PR" "$OUT" "(34f) and the note names the anchor"
has "already anchored by a live bead" "$OUT" "(34f) counted in the summary"

# (34g) ...but the two families naming the SAME PR are ONE reference, not two.
# A bead carrying pr_number and fork_pr with the same value is the ordinary
# belt-and-braces shape, and reporting it twice would read as two violations.
reset
mkrig alpha "git@github.com:acme/alpha.git"
SAMEKEY=$(jq -nc '{id:"a-same", status:"closed", assignee:"alpha/gc-toolkit.refinery",
                   metadata:{pr_number:"70", fork_pr:"70", branch:"polecat/a-same",
                             merge_result:"pull_request"}}')
closed alpha pr_number "[$SAMEKEY]"
closed alpha fork_pr   "[$SAMEKEY]"
prs github.com/acme/alpha '[{"number":70}]'
run_check
eq "$RC" 2 "(34g) one PR named under both keys still errors"
eq "$(grep -c 'ERROR:' "$OUT")" 1 "(34g) exactly once — the two keys are one reference, not two violations"

# ---------------------------------------------------------------------------
# (INV) Detect only — a sibling fix.sh would auto-opt this into `gc doctor --fix`.
# ---------------------------------------------------------------------------
[ -e "$HERE/fix.sh" ] && bad "(INV) a fix.sh ships beside run.sh; this check is detect-only" \
                      || ok "(INV) detect-only: no fix.sh beside run.sh"

echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
