#!/bin/sh
# gc-attention.sh — read-only cross-rig human-attention board.
#
# Usage: gc-attention [--json] [--limit=N] [--timeout=SECONDS]
#
# Renders, ranked, the OPEN tracking anchors across ALL rigs that most
# plausibly need a human's attention right now. A glance tool: read-only
# (no bead writes), every Dolt query is bounded by timeout(1), and a rig
# that errors or is empty is skipped rather than aborting the board.
#
# This is the P2 "render-what-floats" first cut from decision lo-0hvt:
# DETERMINISTIC facts only. No LLM commentary, no LLM-judged weight, no
# theme-lens grouping, no pick-a-row launcher — those are deferred (see
# FOLLOW-UPS at the foot of this file).
#
# ── What is an anchor ────────────────────────────────────────────────
# Three kinds of OPEN top-level anchors are collected, cross-rig:
#   1. epic       — every open `epic`-type bead (per-rig durable anchor).
#   2. convoy     — OWNED convoys that are NOT under an epic (floating
#                   "epic-improvisers"). Machine `sling-*` convoys and
#                   un-owned convoys are excluded.
#   3. decision   — every open `decision`-type bead (human-gated; only a
#                   human can move it).
#
# Beads live in separate per-rig Dolt databases (lo/tk/sl/gc/su/…), so
# the board enumerates `gc rig list` and queries each rig's `.beads`
# directory by path via `gc bd --db`. `gc convoy list` already spans
# rigs, so it is used directly for the convoy gather. `--global` is NOT
# relied upon (it needs shared-server mode).
#
# ── Per-anchor deterministic frontier facts ──────────────────────────
#   • N/M            — children/members closed (N) of total (M). Epic
#                      children come from the `--parent` roll-up; convoy
#                      members from the convoy bead's tracks deps
#                      (`bd show --include-dependents`). N/M and the
#                      frontier derive from the SAME child set, so a row
#                      cannot self-contradict. `gc convoy list` .progress
#                      is kept ONLY as a cross-check: any disagreement
#                      with the resolved set is surfaced as
#                      `progress_mismatch` in the JSON output.
#   • open/in-progress/assigned — counts over the open frontier.
#   • stranded       — decomposed (M>0) with open children but ZERO
#                      in-progress: work exists but nothing is moving.
#   • empty          — an epic/convoy with no children (M==0).
#   • complete       — M>0 but every child closed (0 open): awaiting
#                      graduation/close.
#   • stale_days     — days since the anchor itself was last updated.
#   • cross_rig_refs — DETERMINISTIC prose scan of the anchor body for
#                      bead-ids belonging to OTHER rigs (cross-rig work
#                      is forced into prose today; formal cross-rig dep
#                      edges are rare). A stranded anchor that blocks
#                      another rig is more urgent, so refs add weight.
#
# ── Ranking heuristic (deterministic; documented) ────────────────────
# Each anchor gets a SEVERITY band, then rows sort by band, then by a
# weight PROXY, then by staleness:
#
#   HIGH      stranded frontier (decomposed, open, 0 in-progress).
#   ELEVATED  a `decision` (human-gated), OR an otherwise-NORMAL anchor
#             gone stale (> STALE_DAYS days).
#   NORMAL    active frontier (has in-progress work).
#   LOW       empty epic (0 children) or complete convoy (all closed).
#
#   weight PROXY = M (subtree size)
#                + priority weight (P1→3, P2→2, P3→1, P4→0)
#                + cross-rig ref count (capped).
#
# The proxy is intentionally crude — subtree size + priority + cross-rig
# blast radius — NOT an LLM weight. Sort key is
# (severity_band, weight, stale_days) descending.
#
# ── Output ───────────────────────────────────────────────────────────
# Default: a human-readable ranked table + one-line legend.
# `--json`: a ranked JSON array; each element carries every fact above
# plus the computed `severity`, `weight`, `rank_score`, `frontier`
# (one-line summary) and `needs` (short hint). `--json` is the stable
# contract for downstream tooling.
#
# Exit codes:
#   0   board rendered (even if zero anchors found)
#   2   usage error
#   3   missing dependency (jq / gc) or could not enumerate rigs
#
# Read-only guarantee: this script issues only `gc rig list`,
# `gc convoy list`, and `gc bd list/show` reads. It never writes a bead.

set -eu

# ── Tunables ─────────────────────────────────────────────────────────
STALE_DAYS=14          # > this many days since update → staleness bump
XREF_CAP=5             # max cross-rig refs that count toward weight

usage() {
    cat >&2 <<'EOF'
Usage: gc-attention [--json] [--limit=N] [--timeout=SECONDS]

Read-only cross-rig board of OPEN anchors (epics, floating owned
convoys, decisions) ranked by how much they need a human's attention.

  --json             Emit the ranked board as a JSON array (stable contract).
  --limit=N          Show only the top N rows (0 = all, default).
  --timeout=SECONDS  Per-query timeout bound for Dolt reads (default 10).
  -h, --help         This help.

Deterministic first cut (decision lo-0hvt): no LLM interpretation.
EOF
}

# ── Argument parsing ─────────────────────────────────────────────────
JSON=0
LIMIT=0
TIMEOUT=10
while [ $# -gt 0 ]; do
    case "$1" in
        --json) JSON=1; shift ;;
        --limit=*) LIMIT="${1#--limit=}"; shift ;;
        --limit)
            shift; [ $# -gt 0 ] || { echo "gc-attention: --limit requires a value" >&2; usage; exit 2; }
            LIMIT="$1"; shift ;;
        --timeout=*) TIMEOUT="${1#--timeout=}"; shift ;;
        --timeout)
            shift; [ $# -gt 0 ] || { echo "gc-attention: --timeout requires a value" >&2; usage; exit 2; }
            TIMEOUT="$1"; shift ;;
        -h|--help) usage; exit 0 ;;
        --) shift; break ;;
        -*) echo "gc-attention: unknown flag '$1'" >&2; usage; exit 2 ;;
        *) echo "gc-attention: unexpected argument '$1'" >&2; usage; exit 2 ;;
    esac
done

case "$LIMIT" in (*[!0-9]*) echo "gc-attention: --limit must be a non-negative integer" >&2; exit 2 ;; esac
case "$TIMEOUT" in (*[!0-9]*) echo "gc-attention: --timeout must be a non-negative integer (seconds)" >&2; exit 2 ;; esac

# ── Dependencies ─────────────────────────────────────────────────────
command -v jq >/dev/null 2>&1 || { echo "gc-attention: jq is required" >&2; exit 3; }
command -v gc >/dev/null 2>&1 || { echo "gc-attention: gc is required" >&2; exit 3; }

# ── Scratch space ────────────────────────────────────────────────────
TMP=$(mktemp -d 2>/dev/null) || { echo "gc-attention: could not allocate temp dir" >&2; exit 3; }
trap 'rm -rf "$TMP"' EXIT INT TERM HUP
ANCHORS="$TMP/anchors.ndjson"
: > "$ANCHORS"

NOW_EPOCH=$(date -u +%s)
NOW_ISO=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Bounded gc wrapper: never let a slow/wedged Dolt query abort the board.
# Echoes stdout on success, nothing on failure (caller defaults to []).
gcq() { timeout "$TIMEOUT" gc "$@" 2>/dev/null || true; }

# Validate that a blob is a JSON array; otherwise yield "[]". This guards
# against error text leaking from a failed/timed-out query into jq.
as_array() {
    if printf '%s' "$1" | jq -e 'type=="array"' >/dev/null 2>&1; then
        printf '%s' "$1"
    else
        printf '[]'
    fi
}

# ── Enumerate rigs ───────────────────────────────────────────────────
RIGS_RAW=$(gcq rig list --json)
RIGS=$(printf '%s' "$RIGS_RAW" | jq -c '[.rigs[]? | {name, path, prefix}]' 2>/dev/null || printf '[]')
if [ "$(printf '%s' "$RIGS" | jq 'length')" -eq 0 ]; then
    echo "gc-attention: could not enumerate rigs (gc rig list returned nothing)" >&2
    exit 3
fi
PREFIXES=$(printf '%s' "$RIGS" | jq -c '[.[].prefix]')
RIGNAMES=$(printf '%s' "$RIGS" | jq -c '[.[].name]')

# Resolve a bead-id prefix (chars before the first '-') to {name,path}.
rig_for_prefix() {
    printf '%s' "$RIGS" | jq -c --arg p "$1" '.[] | select(.prefix==$p)' 2>/dev/null | head -n1
}

# ── Gather epics + decisions per rig ─────────────────────────────────
printf '%s' "$RIGS" | jq -c '.[]' | while IFS= read -r rig; do
    name=$(printf '%s' "$rig" | jq -r '.name')
    path=$(printf '%s' "$rig" | jq -r '.path')
    prefix=$(printf '%s' "$rig" | jq -r '.prefix')
    beads="$path/.beads"
    [ -d "$beads" ] || continue

    # Epics: roll up children via --parent (all statuses, so closed count is real).
    epics=$(as_array "$(gcq bd list --db "$beads" --type epic --status open --json)")
    printf '%s' "$epics" | jq -c '.[]' | while IFS= read -r epic; do
        eid=$(printf '%s' "$epic" | jq -r '.id')
        children=$(as_array "$(gcq bd list --db "$beads" --parent "$eid" --status open,in_progress,closed,blocked,deferred --json)")
        printf '%s' "$epic" | jq -c \
            --argjson ch "$children" --arg rig "$name" --arg prefix "$prefix" \
            '{id, title:(.title//""), kind:"epic", source:"epic", rig:$rig, prefix:$prefix,
              priority:(.priority//3), updated_at:(.updated_at//""), description:(.description//""),
              progress:null,
              children:[$ch[] | {id, status, assignee}]}' >> "$ANCHORS"
    done

    # Decisions: human-gated; no child roll-up needed (rank is elevated regardless).
    decisions=$(as_array "$(gcq bd list --db "$beads" --type decision --status open --json)")
    printf '%s' "$decisions" | jq -c \
        --arg rig "$name" --arg prefix "$prefix" \
        '.[] | {id, title:(.title//""), kind:"decision", source:"decision", rig:$rig, prefix:$prefix,
                priority:(.priority//3), updated_at:(.updated_at//""), description:(.description//""),
                progress:null, children:[]}' >> "$ANCHORS"
done

# ── Gather floating owned convoys (cross-rig) ────────────────────────
# `gc convoy list` already aggregates across rigs. Keep owned, drop the
# machine `sling-*` convoys, then resolve each to its rig and confirm it
# is floating (parent == null → not tracked under an epic).
convoys=$(printf '%s' "$(gcq convoy list --json)" | jq -c '[.convoys[]? | select(.owned==true) | select((.title // "") | startswith("sling-") | not)]' 2>/dev/null || printf '[]')
printf '%s' "$convoys" | jq -c '.[]' | while IFS= read -r convoy; do
    cid=$(printf '%s' "$convoy" | jq -r '.id')
    cprefix=${cid%%-*}
    rig=$(rig_for_prefix "$cprefix")
    [ -n "$rig" ] || continue
    name=$(printf '%s' "$rig" | jq -r '.name')
    path=$(printf '%s' "$rig" | jq -r '.path')
    beads="$path/.beads"
    [ -d "$beads" ] || continue

    # One show call yields the convoy body, its parent, and its members
    # (tracks deps → dependents). The dependents are the CANONICAL child
    # set: the render pass derives N/M and the frontier from it. The
    # `gc convoy list` .progress counts ride along only as a cross-check
    # (surfaced as progress_mismatch); they never feed N/M.
    show=$(gcq bd show "$cid" --db "$beads" --include-dependents --json)
    printf '%s' "$show" | jq -e 'type=="array" and length>0' >/dev/null 2>&1 || continue
    parent=$(printf '%s' "$show" | jq -r '.[0].parent // empty')
    # Floating only: a convoy with a parent is tracked by that parent.
    [ -z "$parent" ] || continue

    printf '%s' "$show" | jq -c \
        --argjson cv "$convoy" --arg rig "$name" --arg prefix "$cprefix" \
        '.[0] as $b
         | {id:$cv.id, title:($cv.title//$b.title//""), kind:"convoy", source:"convoy",
            rig:$rig, prefix:$prefix, priority:($b.priority//3),
            updated_at:($b.updated_at//""), description:($b.description//""),
            progress:($cv.progress // null),
            children:[($b.dependents // [])[] | {id, status, assignee}]}' >> "$ANCHORS"
done

# ── Compute facts, rank, render ──────────────────────────────────────
# Everything below is a single jq pass over the gathered anchors.
RENDER='
def sevrank: {"HIGH":3,"ELEVATED":2,"NORMAL":1,"LOW":0}[.];
def prio_w($p): (if $p==null then 1 else ([0, 4 - $p] | max) end);
def epoch($s): ($s | if . == null or . == "" then null
                     else (sub("\\.[0-9]+";"") | sub("Z$";"") )
                          | (try (. + "Z" | strptime("%Y-%m-%dT%H:%M:%SZ") | mktime) catch null) end);
def rpad($w): . as $s | ($s|tostring)[0:$w] as $t | $t + (($w - ($t|length)) as $g | if $g>0 then (" "*$g) else "" end);

[ inputs ]
| map(
    . as $a
    | ($a.children // []) as $ch
    # N/M and the frontier BOTH derive from $ch — the one resolved child
    # set (epic --parent roll-up, or convoy tracks deps). A convoy whose
    # dependents diverge from its tracked-member counts therefore still
    # renders self-consistently; the divergence itself is surfaced as
    # $pmismatch instead of silently skewing N/M.
    | ($ch|length) as $m
    | ([$ch[]|select(.status=="closed")]|length) as $closed
    | (if $a.progress == null then false
       else (($a.progress.total // -1) != $m or ($a.progress.closed // -1) != $closed) end) as $pmismatch
    | [$ch[] | select(.status != "closed")] as $openset
    | ($openset|length) as $open
    | ([$ch[]|select(.status=="in_progress")]|length) as $inprog
    | ([$openset[]|select((.assignee // "") != "")]|length) as $assigned
    | [ $openset[] | select((.assignee // "")=="" or .status!="in_progress") | .id ] as $open_ids
    | (epoch($a.updated_at)) as $upd
    | (if $upd==null then 0 else ((($now - $upd) / 86400) | floor) end) as $stale
    | ($prefixes - [$a.prefix]) as $others
    # Heuristic prose scan for OTHER-rig bead-ids that a WORK anchor (epic
    # / convoy) references — a stranded item that blocks another rig is
    # more urgent. Drop matches that are actually rig NAMES (e.g.
    # "gc-toolkit"). Decisions are skipped: their prose references things
    # they discuss, which is noise, not a blocking edge. Best-effort:
    # cross-rig links live in prose today, not formal dep edges.
    | (if $a.source=="decision" then []
       else ( [ ($a.description // "")
                | scan("(?:" + ($others|join("|")) + ")-[a-z0-9]{3,8}") ]
              | map(select(. as $r | ($rignames | index($r)) == null and $r != $a.id))
              | unique ) end) as $xrefs
    # severity band
    | (if $a.source=="decision" then "ELEVATED"
       elif $m==0 then "LOW"
       elif $open==0 then "LOW"
       elif ($open>0 and $inprog==0) then "HIGH"
       else "NORMAL" end) as $sev0
    | (if ($sev0=="NORMAL" and $stale > '"$STALE_DAYS"') then "ELEVATED" else $sev0 end) as $sev
    | ($m + prio_w($a.priority) + ([$xrefs|length, '"$XREF_CAP"'] | min)) as $weight
    # one-line frontier summary (N/M lives in its own column; no repeat)
    | (if $a.source=="decision" then "human-gated decision"
       elif $m==0 then "empty — no children"
       elif $open==0 then "all \($m) closed · 0 open"
       elif $inprog==0 then "\($open) open · 0 in-progress (stranded)"
       else "\($open) open · \($inprog) in-progress" end) as $frontier
    # short needs hint. cross-rig refs are surfaced only for a STRANDED
    # frontier, where a blocked downstream rig adds real urgency.
    | ($open_ids[0:3] | join(",")) as $heads
    | (if ($a.source!="decision" and $m>0 and $open>0 and $inprog==0 and ($xrefs|length)>0)
       then " · refs " + ($xrefs[0:3]|join(",")) else "" end) as $blurb
    | (if $a.source=="decision" then "operator decision"
       elif $m==0 then "decompose or close"
       elif $open==0 then (if $a.source=="convoy" then "graduate / close" else "close or extend" end)
       elif $inprog==0 then ("assign " + (if $heads=="" then "frontier" else $heads end) + (if ($open>3) then " (+\($open-3))" else "" end) + $blurb)
       else "in flight" end) as $needs
    | {
        id:$a.id, rig:$a.rig, kind:$a.kind, title:$a.title,
        severity:$sev, weight:$weight,
        n_closed:$closed, m_total:$m, open:$open, in_progress:$inprog, assigned:$assigned,
        stranded:($m>0 and $open>0 and $inprog==0), empty:($m==0 and $a.source!="decision"),
        complete:($m>0 and $open==0),
        progress_mismatch:$pmismatch,
        stale_days:$stale, priority:$a.priority, cross_rig_refs:$xrefs,
        updated_at:$a.updated_at, frontier:$frontier, needs:$needs,
        rank_score: (($sev|sevrank)*1000000 + $weight*1000 + ([$stale,999]|min))
      }
  )
| sort_by(-.rank_score)
| (if '"$LIMIT"' > 0 then .[0:'"$LIMIT"'] else . end)
'

BOARD=$(jq -c -n --argjson prefixes "$PREFIXES" --argjson rignames "$RIGNAMES" --argjson now "$NOW_EPOCH" "$RENDER" < "$ANCHORS")

if [ "$JSON" -eq 1 ]; then
    printf '%s\n' "$BOARD" | jq '.'
    exit 0
fi

# ── Human-readable table ─────────────────────────────────────────────
COUNT=$(printf '%s' "$BOARD" | jq 'length')
RIGCOUNT=$(printf '%s' "$RIGS" | jq 'length')
printf 'gc-attention — cross-rig human-attention board\n'
printf '%s · %s rigs · %s anchors\n\n' "$NOW_ISO" "$RIGCOUNT" "$COUNT"

if [ "$COUNT" -eq 0 ]; then
    printf 'No open anchors need attention. (Nothing floats.)\n'
    exit 0
fi

printf '%s' "$BOARD" | jq -r '
def rpad($w): . as $s | ($s|tostring)[0:$w] as $t | $t + (($w - ($t|length)) as $g | if $g>0 then (" "*$g) else "" end);
( ("SEV"|rpad(9)) + ("ID"|rpad(11)) + ("RIG"|rpad(13)) + ("KIND"|rpad(9)) + ("N/M"|rpad(7)) + ("FRONTIER"|rpad(36)) + "NEEDS" ),
( ("─"*8|rpad(9)) + ("─"*10|rpad(11)) + ("─"*12|rpad(13)) + ("─"*8|rpad(9)) + ("─"*6|rpad(7)) + ("─"*35|rpad(36)) + ("─"*16) ),
( .[] | ((.severity)|rpad(9)) + ((.id)|rpad(11)) + ((.rig)|rpad(13)) + ((.kind)|rpad(9))
        + ((if .kind=="decision" then "—" else "\(.n_closed)/\(.m_total)" end)|rpad(7))
        + ((.frontier)|rpad(36)) + (.needs) )
'
printf '\nLegend: HIGH=stranded (decomposed, nothing moving) · ELEVATED=decision/stale · NORMAL=active · LOW=empty/complete\n'
printf 'Read-only board. Ranking is a deterministic proxy (severity × weight × staleness); no LLM interpretation.\n'

# ── FOLLOW-UPS (out of scope for this deterministic first cut) ───────
#   • LLM commentary / LLM-judged weight & severity (the interpretation layer).
#   • Operator-defined theme-lens grouping (cross-rig themes as config).
#   • Pick-a-row → spawn/attach a thread (launcher).
#   • On-change assessment / caching (vs. recompute-on-run today).
#   • Formal cross-rig dependency edges (today cross-rig links are prose;
#     cross_rig_refs is a best-effort prose scan, not a dep graph).
