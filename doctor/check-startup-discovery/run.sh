#!/usr/bin/env bash
# Pack doctor check: patrol-agent startup discovery is complete and
# ephemeral-aware.
#
#   refinery + deacon — tiers 2 and 3 present (see below)
#   refinery + deacon + witness + boot — every wisp query is
#                                 ephemeral-aware (--include-infra)
#   witness — every wisp reconcile query is scoped to mol-witness-patrol
#             roots (see below)
#   boot — the deacon-wisp read is scoped to mol-deacon-patrol roots
#          (see below)
#
# Tier-1 (in-progress wisp) was the historical query and is preserved.
# Tier-2 catches routed work beads with metadata.branch — these arrive when a
# polecat completes work after the inheriting session has already booted from
# the controller-driven respawn (handoff for controller-restartable, the
# chained reset for on-demand named) but before the boot-time tier-1 query
# fired. Without tier-2 the work bead is invisible to the inheriting session
# and sits open until manual nudge. See rigs/gc-toolkit/specs/tk-fyzvk for
# the full diagnostic.
#
# Tier-3 catches open patrol wisps left behind by pour-before-burn
# cycle-recycle, including pathological multi-wisp accumulation from a
# runaway event-watch loop.
#
# The --include-infra assertion (tk-1waw2) covers a different failure of the
# same reconcile: patrol wisps are ephemeral and live in <store>.wisps, but
# `gc bd list` reads .issues by default. A --type=molecule query without
# --include-infra therefore returns empty even while wisps exist, the agent
# concludes it has no wisp, pours a fresh one, and leaks the prior one on
# every restart. The witness shipped that bug (three leaked wisps observed
# live 2026-06-26); deacon and refinery already comply, so the check locks
# the invariant in for all three.
#
# The formula-scoping assertion (tk-6sbaf) covers the mirror-image hazard in
# the same reconcile: molecule roots are formula-specific, so a reconcile that
# keeps one wisp and burns the rest must filter on the patrol title or it can
# adopt — or destroy — an unrelated molecule root that happens to be assigned
# to the same agent. Only the witness block burns surplus during startup, so
# only it is held to this.
#
# Both of those assertions are NEGATIVE: they score the queries a block
# already has. A block that simply LOST its wisp query scores zero of each and
# passes — the doctor would keep reporting boot's read as ephemeral-aware and
# title-scoped after the read it describes stopped existing (caught reviewing
# tk-jd4b8: deleting the fenced boot query still exited 0). The required-query
# assertion (tk-vl2nu) closes that by asserting POSITIVELY that the boot block
# still carries the dedicated patrol-wisp read, at both call sites the fragment
# supersedes — the fenced Step 2 command and the Command Quick-Reference table
# row. The row needs an assertion of its own because every check above scores
# fenced code only and skips it by construction.
#
# Post-tk-kdu2v5 the doctrine lives in a single shared fragment file
# (template-fragments/layered-startup-discovery.template.md) with named
# blocks consumed by deacon, refinery, and witness via
# inject_fragments_append. The check inspects each block's region
# separately. The witness block is reconcile-only by design — the witness
# monitors other agents' work rather than receiving branch-bearing work
# beads — so tiers 2 and 3 are not asserted against it.
#
# Exit codes: 0=OK, 1=Warning, 2=Error
# stdout: first line=message, rest=details

set -u

dir="${GC_PACK_DIR:-.}"
fragment="$dir/template-fragments/layered-startup-discovery.template.md"
violations=()

if [ ! -f "$fragment" ]; then
    echo "1 startup-discovery gap(s) — see rigs/gc-toolkit/specs/tk-fyzvk for context"
    echo "template-fragments/layered-startup-discovery.template.md: missing fragment file"
    exit 2
fi

# extract_block <define-name> — the fragment region between
# `{{ define "<name>" }}` and its closing `{{ end }}`.
extract_block() {
    awk -v name="$1" '
        $0 ~ "\\{\\{ *define \"" name "\" *\\}\\}" { capture = 1; next }
        capture && /\{\{ *end *\}\}/ { capture = 0 }
        capture { print }
    ' "$fragment"
}

# fenced_code <block> — the block's fenced code lines, with backslash
# continuations spliced so a query wrapped across lines is judged as one
# command. Prose is dropped: it names the same flags while explaining why
# they are there, and must not be scored as a query.
fenced_code() {
    printf '%s\n' "$1" \
        | awk '
            /^[[:space:]]*```/ { in_fence = !in_fence; next }
            in_fence { print }
        ' \
        | sed -e :a -e '/\\$/N; s/\\\n[[:space:]]*/ /; ta'
}

# table_rows <block> — the block's Markdown table rows. These live OUTSIDE
# the fences, so every fenced_code assertion skips them; a quick-reference
# row that teaches a broken command is invisible without this.
table_rows() {
    printf '%s\n' "$1" \
        | awk '
            /^[[:space:]]*```/ { in_fence = !in_fence; next }
            !in_fence && /^[[:space:]]*\|/ { print }
        '
}

# check_required_query <label> <site> <text> <token>...
# Positive assertion: <text> must contain at least one line carrying EVERY
# token. This is what fails closed when a required query is deleted outright
# rather than degraded — the flag assertions in check_block only score
# commands that are already `--type=molecule`, so a vanished query scores
# clean on all of them.
check_required_query() {
    local label="$1"
    local site="$2"
    local matches="$3"
    shift 3
    local token
    for token in "$@"; do
        matches=$(printf '%s\n' "$matches" | grep -F -- "$token" || true)
        if [ -z "$matches" ]; then
            violations+=("$label: $site is missing the required patrol-wisp query (no single command carries all of: $*)")
            return
        fi
    done
}

# check_block <define-name> <label> [require_tiers] [patrol_title]
# require_tiers=tiers → also assert the tier-2 and tier-3 queries.
# patrol_title=<formula>  → also assert every molecule-root query is scoped to
#                           that formula's wisps.
check_block() {
    local block_name="$1"
    local label="$2"
    local require_tiers="${3:-}"
    local patrol_title="${4:-}"
    local block
    block=$(extract_block "$block_name")

    if [ -z "$block" ]; then
        violations+=("$label: missing {{ define \"$block_name\" }} block in template-fragments/layered-startup-discovery.template.md")
        return
    fi
    if [ "$require_tiers" = "tiers" ]; then
        # Tier 2: routed work bead query must include --has-metadata-key=branch
        if ! printf '%s' "$block" | grep -q -- "--has-metadata-key=branch"; then
            violations+=("$label: missing tier-2 routed-work-bead query (--has-metadata-key=branch)")
        fi
        # Tier 3: open-patrol-wisp adoption must include --type=molecule + --status=open
        if ! printf '%s' "$block" | grep -E -q -- "(--status=open[^|]*--type=molecule|--type=molecule[^|]*--status=open)"; then
            violations+=("$label: missing tier-3 open-patrol-wisp query (--status=open --type=molecule)")
        fi
    fi
    # Ephemeral-awareness: every `gc bd list --type=molecule` reconcile must
    # carry --include-infra or it never sees a wisp. Score fenced code only —
    # the surrounding prose names the same flags while explaining why, and
    # must not read as a violation. Splice backslash continuations so a query
    # wrapped across lines is judged as one command.
    local joined offenders
    joined=$(fenced_code "$block")
    offenders=$(printf '%s\n' "$joined" \
        | grep -- "gc bd list" \
        | grep -- "--type=molecule" \
        | grep -cv -- "--include-infra" || true)
    if [ "${offenders:-0}" -gt 0 ]; then
        violations+=("$label: $offenders wisp query(ies) missing --include-infra (ephemeral wisps are invisible without it)")
    fi
    # Formula scoping: molecule roots are formula-specific, so a reconcile that
    # picks a survivor and BURNS the rest must filter on the patrol title first
    # — otherwise an unrelated molecule root assigned to the same agent is
    # adopted as the patrol wisp or destroyed as "surplus". Asserted for the
    # witness (whose reconcile burns) and for boot (whose read must land on the
    # deacon's patrol wisp, not on whatever molecule the deacon happens to hold
    # — the crowding failure tk-jd4b8 fixed). The deacon/refinery tier-1 resume
    # query feeds no burn, so it is intentionally unscoped there, and their
    # tier-3 adoption already filters on title.
    if [ -n "$patrol_title" ]; then
        local unscoped
        unscoped=$(printf '%s\n' "$joined" \
            | grep -- "gc bd list" \
            | grep -- "--type=molecule" \
            | grep -cvF -- "$patrol_title" || true)
        if [ "${unscoped:-0}" -gt 0 ]; then
            violations+=("$label: $unscoped wisp query(ies) not scoped to $patrol_title (an unrelated molecule root could be adopted or burned)")
        fi
    fi
}

check_block "layered-startup-discovery-refinery" "refinery" tiers
check_block "layered-startup-discovery-deacon" "deacon" tiers
check_block "layered-startup-discovery-witness" "witness" "" "mol-witness-patrol"
# Boot READS the deacon's wisp (freshness signal) rather than reconciling its
# own, so tiers 2 and 3 do not apply — but the ephemeral-awareness and
# title-scoping assertions do, and for boot they are the whole point of the
# block (tk-jd4b8). The wisp read is a dedicated --type=molecule query filtered
# to mol-deacon-patrol precisely so a busy deacon's other in-progress rows
# cannot crowd the wisp out of a capped result; asserting the title here is what
# stops that query drifting back to the broad untyped form that made the signal
# dead in the first place. The block's second, deliberately untyped "what else
# is the deacon holding" query is not scored by either assertion — both key on
# --type=molecule.
check_block "layered-startup-discovery-boot" "boot" "" "mol-deacon-patrol"

# ...and assert POSITIVELY that boot's dedicated read still exists. The two
# assertions in check_block are both negative — they score the wisp queries a
# block has — so deleting boot's query passes them vacuously, and the whole
# point of this block is that the query exists. Both call sites the fragment
# supersedes get their own assertion: the Step 2 command inside the fence, and
# the Command Quick-Reference row, which is a table cell and so is skipped by
# every fence-scoped check.
#
# Every token below is load-bearing; the query is only correct with all of them:
#
#   --limit=0    a capped read lets a busy deacon's other in-progress rows crowd
#                the wisp out and takes the freshness signal dead again,
#                silently and only under load.
#   --assignee=  the read answers "how fresh is THE DEACON's wisp". Widening it
#                off --assignee does not recover the orphan case it looks like
#                it would (a wisp poured but never assigned): it instead lets a
#                stale orphan sitting beside a healthy assigned wisp feed the
#                "very stale wisp -> clearly stuck" triage row a false positive.
#                The block's own "Empty is not a verdict" prose says so; without
#                this token the doctor lets the query drift off it anyway.
#   --json       both sites are machine-read — the fenced command pipes into
#                `jq`, and the quick-reference row is copied out to be parsed.
#                Human-format output silently breaks that pipe.
boot_block=$(extract_block "layered-startup-discovery-boot")
if [ -n "$boot_block" ]; then
    check_required_query "boot" "Step 2 wisp read" "$(fenced_code "$boot_block")" \
        "gc bd list" "--assignee={{ .BindingPrefix }}deacon" "--status=in_progress" \
        "--type=molecule" "--include-infra" "--limit=0" "--json" "mol-deacon-patrol"
    check_required_query "boot" "Command Quick-Reference wisp row" "$(table_rows "$boot_block")" \
        "gc bd list" "--assignee={{ .BindingPrefix }}deacon" "--status=in_progress" \
        "--type=molecule" "--include-infra" "--limit=0" "--json" "mol-deacon-patrol"
fi

if [ ${#violations[@]} -eq 0 ]; then
    echo "refinery + deacon startup discovery includes tiers 2 and 3; all wisp queries are ephemeral-aware; witness reconcile is scoped to mol-witness-patrol; boot carries the dedicated mol-deacon-patrol wisp read at both sites (Step 2 and the quick-reference row)"
    exit 0
fi

echo "${#violations[@]} startup-discovery gap(s) — see specs/tk-fyzvk/ for context"
for v in "${violations[@]}"; do
    echo "$v"
done
exit 2
