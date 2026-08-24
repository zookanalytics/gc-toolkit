#!/usr/bin/env bash
# Pack doctor check: every wait is a graph EDGE, not a sentence.
# (docs/component-model.md §3, invariant I1; the rule is docs/lifecycle-
# composition.md §1.)
#
# THE INVARIANT. "Every dependency is recorded in the bead graph — no wait
# lives only in prose or in a metadata string."
#
# WHY A SENTENCE IS NOT A RECORD. A sentence freezes at the moment it is
# written and is never true again. Two subjects — one genuinely blocked, one
# entirely finished — produce mechanically identical rows when the only
# difference between them is prose, so every surface that re-derives "is this
# still waiting?" reads both as wanting nothing, forever. The edge is what
# makes the wait machine-answerable; `gc-helm takeaway --waiting-on` writes one
# beside the prose for exactly this reason.
#
# ── WHAT IS FLAGGED ─────────────────────────────────────────────────────────
# An OPEN bead whose prose contains WAIT LANGUAGE naming another bead, with no
# dependency edge between the two in either direction. Two shapes, reported
# separately because they are different degrees of the same defect:
#
#   UNEDGED       The named bead is still open. The wait is real and the graph
#                 cannot answer it.
#
#   FROZEN        The named bead has already CLOSED. This is the defect in its
#                 terminal form: the thing being waited for is done, the
#                 sentence still says it is pending, and nothing anywhere can
#                 notice — precisely the state lifecycle-composition §1
#                 describes. Measured 2026-08-24 on gc-toolkit: of 8 prose
#                 waits, 6 had no edge, and 5 of those named an already-closed
#                 bead.
#
# ── WAIT LANGUAGE, NOT BEAD MENTIONS, AND THAT IS THE WHOLE DESIGN ──────────
# The obvious predicate — "an open bead that names another bead id where no
# edge exists" — is unusable, and measuring it is what says so. On gc-toolkit,
# 2026-08-24: 115 of 909 open beads name another bead somewhere in their notes.
# Five express a wait. The other 110 are provenance ("Implemented
# (tk-clvkf6)"), file paths (`specs/tk-z9nln/consolidation-plan.md`), and
# CONCLUSIONS ("folded into tk-mpl1c") — and a conclusion is prose BY DESIGN:
# lifecycle-composition §1 says it is stored once and never cleared. A check
# that demanded an edge for every conclusion would be demanding the opposite of
# the rule it enforces, at a hundred-to-one noise ratio, and would be muted
# within a day.
#
# So the trigger is the VERB. Only a phrase asserting an ongoing dependency —
# waiting on / blocked by / awaiting / pending / depends on / gated on /
# holding for — followed closely by a bead id is treated as a wait.
#
# ── WHY CANDIDATE IDS ARE RESOLVED BEFORE BEING JUDGED ──────────────────────
# The id pattern alone is not safe here. Rig and tool names collide with it
# head-on: `gc-toolkit` and `gc-helm` both match a `gc-` prefixed id, and both
# appear constantly in exactly the prose being scanned. Resolving each
# candidate against the store before judging it removes that class entirely and
# costs one batched read per store. An id resolving to nothing is reported as
# its own note — prose naming a bead that does not exist is a different defect,
# and swallowing it would hide it.
#
# ── BOTH EDGE SPELLINGS, BOTH DIRECTIONS ────────────────────────────────────
# `bd list --json` renders an edge as {type, depends_on_id}; `bd show --json`
# renders the SAME edge as {dependency_type, id}. Reading one spelling only
# would find no edges at all and report every prose wait as a violation — the
# loudest possible false positive, and one this check hit while being written.
# Both are read.
#
# Direction is not required to be one way. The invariant asks that the relation
# be IN THE GRAPH, so an edge from either side satisfies it; demanding a
# particular direction would flag correctly-recorded pairs over a convention
# the invariant does not state.
#
# ── SCOPE: THE EDGE, NOT THE PROSE ──────────────────────────────────────────
# This asserts the edge EXISTS. It never asks for the sentence to be removed.
# The prose is the durable record of what was concluded and is never cleared
# (lifecycle-composition.md, "A conclusion is prose"). The remedy for a finding
# is to ADD the edge.
#
# ── FAIL-CLOSED ─────────────────────────────────────────────────────────────
# Every probe that cannot be READ warns rather than passes. A check that
# reports OK when it could not see reproduces the silence it exists to remove.
#
# Exit codes: 0=OK, 1=Warning, 2=Error
# stdout: first line=message, rest=details

set -u

# `gc doctor` DOES bound pack checks (`--check-timeout`, default 60s) and a
# check that overruns is abandoned with its findings DISCARDED — so every probe
# is individually bounded. Cost is two reads per store: one open listing (0.4s
# for 909 beads) and one batched resolve of the candidate ids.
BOUND="${GC_DOCTOR_CHECK_TIMEOUT:-30}"

# Candidate ids are resolved with a batched `bd show`. Chunked so a store with a
# very large candidate set cannot build an argv past the exec limit.
CHUNK="${GC_DOCTOR_WAIT_CHUNK:-100}"

errors=()
warnings=()
notes=()

run_bounded() {
    if command -v timeout >/dev/null 2>&1; then
        timeout "$BOUND" "$@" </dev/null
    else
        # No coreutils timeout (some macOS hosts). Degrade to an unbounded call
        # rather than skipping the check entirely.
        "$@" </dev/null
    fi
}

# `printf '%s\n' "${arr[@]}"` with an EMPTY array still prints a blank line,
# which reads as an unexplained detail row in doctor output. Print nothing.
print_lines() { [ "$#" -eq 0 ] || printf '%s\n' "$@"; }

# Bead notes and descriptions carry control characters that make jq abort
# mid-parse, which would otherwise cost a whole store. Everything below 0x20
# except the newline goes — a literal TAB is invalid inside a JSON string just
# like the rest, and it also clears the 0x1F these rows are joined on, so no
# payload byte can pose as a field separator.
strip_ctl() { tr -d '\000-\011\013-\037'; }

# ---------------------------------------------------------------------------
# The wait predicate, as one jq program so the pattern lives in exactly one
# place. Emits <source-id> US <verb> US <candidate-id> per match.
#
# THE PROSE SCANNED is the notes plus every metadata value whose KEY reads as a
# reason. The invariant names `blocked_reason` and `check.*.reason`;
# `blocked_reason` does not exist in this city, while `reason`,
# `rejection_reason` and `blocked_on_branch` do. Matching the key by SHAPE
# rather than against a hardcoded list covers the invariant's intent and
# today's actual keys at once, and does not silently stop working when a fourth
# is added.
#
# THE ID PREFIXES COME FROM THE LIVE ROSTER, not from a literal. A pattern of
# "two-to-four letters, a hyphen, then a token" reads ordinary hyphenated
# English as bead ids: the first live run turned `base-branch`, `in-flight`,
# `un-taken`, `pool-offer`, `bare-thread`, `byte-identical` and `re-verifies`
# into candidate ids, and each became its own "resolves to no bead" note. That
# is nine lines of noise in front of eighteen real findings, which is how a
# check gets muted. `gc rig list --json` reports each rig's issue_prefix, so
# the alternation is exactly the set of prefixes this city can mint — and it
# widens on its own when a rig is added.
#
# Resolution against the store is still what makes the match SAFE (a rig or
# agent name like `gc-toolkit` shares a real prefix and can only be rejected by
# looking it up); the prefix set is what keeps it QUIET.
#
# THE SOURCE'S OWN EDGE IDS RIDE ALONG, as a fourth field, and that is a size
# constraint rather than a convenience. The open listing is megabytes; passing
# it to a second jq as `--argjson` blows MAX_ARG_STRLEN (128 KB for a single
# argument, independent of the far larger ARG_MAX) and jq dies with "Argument
# list too long" — which this check did, on its first live run, and which the
# fail-closed arm correctly reported as "store NOT checked" rather than as a
# clean city. The payload therefore crosses the boundary ONCE, here, already
# reduced to the ids the join needs. Same defect and same fix as tk-hgmob in
# the helm board gather.
# ---------------------------------------------------------------------------
# shellcheck disable=SC2016  # $prefixes is a jq variable, fed by --arg below; shell expansion here would be the bug
WAIT_JQ='
# The verb group is CAPTURING. It was non-capturing in the first draft, which
# made jq`s scan() return only the id capture — so the verb slot held null, the
# id landed in the wrong field, and the check reported a clean city while six
# real violations sat in the store. A silent false negative is the worst thing
# a doctor check can be, so the shape of what scan() returns is pinned by the
# (SCAN) case in run.test.sh.
def verbs: "(waiting on|waits on|waiting for|blocked on|blocked by|awaiting|await|pending|depends on|dependent on|gated on|holding for|held by)";
# The tail is 3+ characters, which is the SHORTEST id this city actually mints:
# measured 2026-08-24 over every store, 2 open beads carry a 3-character tail
# (su-02g, tk-1co) against 1,008 at five. A 4-character floor reads more
# naturally and would have silently skipped those two — the kind of blind spot
# that only shows up as a finding that never appears.
def idpat: "((?:" + $prefixes + ")-[a-z0-9][a-z0-9.]{2,})";
.[]?
| . as $b
| ($b.id // "" | tostring) as $src
| ( [ ($b.notes // "" | tostring) ]
    + [ ($b.metadata // {} | to_entries[]
         | select(.key | test("(?i)reason|blocked")) | (.value | tostring)) ]
  ) as $prose
| $prose[]
| [ scan("(?i)" + verbs + "[^.\n]{0,40}?\\b" + idpat) ]
| .[]?
# A sentence-final period is swallowed by the id pattern, which has to admit
# dots for hierarchical ids like tk-yhwfv.3 — so "awaiting tk-8rm3q." yields
# "tk-8rm3q.", which resolves to nothing and would be reported as a wait on a
# bead that does not exist. Trailing dots are stripped; interior ones are kept.
| [ $src, (.[0] | ascii_downcase), (.[1] | sub("\\.+$"; "")),
    ([ ($b.dependencies // [])[] | ((.depends_on_id // .id) // "")
       | select(. != "") ] | join(",")) ]
| select(.[2] != $src and .[2] != "")
| join("\u001f")
'

# ---------------------------------------------------------------------------
# The stores to scan.
# ---------------------------------------------------------------------------
rigs_raw=$(run_bounded gc rig list --json 2>/dev/null)
rigs_rc=$?

if [ "$rigs_rc" -ne 0 ] || [ -z "$rigs_raw" ]; then
    echo "cannot determine whether every wait is recorded as an edge"
    echo "\`gc rig list --json\` failed (rc=$rigs_rc) or returned nothing; there is no set of bead stores to scan."
    exit 1
fi

# US-joined, not tab: a rig whose name is empty must still yield an empty FIRST
# field and a path in the second. Under a tab IFS bash would collapse the pair,
# land the path in rig_name and skip a whole store — the fail-open this check
# exists to remove.
scopes=$(printf '%s' "$rigs_raw" \
    | jq -r '.rigs[]? | select((.path // "") != "")
             | [((.name // "") | gsub("[[:cntrl:]]"; " ")), .path]
             | join("\u001f")' 2>/dev/null)

# The alternation of every issue prefix this city can mint. Sorted longest-first
# so a longer prefix cannot be shadowed by a shorter one that prefixes it.
PREFIXES=$(printf '%s' "$rigs_raw" \
    | jq -r '[ .rigs[]? | (.prefix // "") | select(test("^[a-z]{1,8}$")) ]
             | unique | sort_by(-length) | join("|")' 2>/dev/null)

if [ -z "$PREFIXES" ]; then
    # Without the prefix set the scan cannot tell a bead id from a hyphenated
    # word, and a check that guesses is worse than one that says it could not
    # look.
    echo "cannot determine whether every wait is recorded as an edge"
    echo "\`gc rig list --json\` reported no usable issue prefixes; a bead id cannot be told from ordinary hyphenated prose without them."
    exit 1
fi

if [ -z "$scopes" ]; then
    echo "cannot determine whether every wait is recorded as an edge"
    echo "\`gc rig list --json\` listed no rig paths; the listing shape changed or the output is corrupt."
    exit 1
fi

checked=0

while IFS=$'\037' read -r rig_name rig_path; do
    [ -n "$rig_path" ] || continue
    label="${rig_name:-<city>}"
    db="$rig_path/.beads"
    [ -d "$db" ] || continue

    open_raw=$(run_bounded bd list --db "$db" --status open --json --limit 0 2>/dev/null)
    open_rc=$?

    if [ "$open_rc" -ne 0 ]; then
        warnings+=("$label: could not list open beads in $db (rc=$open_rc) — this store was NOT checked")
        continue
    fi
    # An empty store answers `[]`; an empty STRING means the probe produced
    # nothing at all, which is not the same thing and is not a pass.
    if [ -z "$open_raw" ]; then
        warnings+=("$label: \`bd list\` over $db returned no output — this store was NOT checked")
        continue
    fi

    open_json=$(printf '%s' "$open_raw" | strip_ctl)
    if ! printf '%s' "$open_json" | jq -e 'type=="array"' >/dev/null 2>&1; then
        warnings+=("$label: open listing from $db is not a JSON array — this store was NOT checked")
        continue
    fi

    checked=$((checked + 1))

    pairs=$(printf '%s' "$open_json" | jq -r --arg prefixes "$PREFIXES" "$WAIT_JQ" 2>/dev/null)
    pairs_rc=$?
    if [ "$pairs_rc" -ne 0 ]; then
        warnings+=("$label: could not scan open beads in $db for wait language — this store was NOT checked")
        continue
    fi
    [ -n "$pairs" ] || continue

    # ── Resolve the candidate ids ───────────────────────────────────────────
    # Batched, and the ONLY thing separating a bead id from a rig or tool name
    # of the same shape.
    cand_ids=$(printf '%s\n' "$pairs" | awk -F'\037' 'NF>=3 {print $3}' | sort -u)
    [ -n "$cand_ids" ] || continue

    resolved='[]'
    chunk=()
    chunk_failed=""

    flush_chunk() {
        [ "${#chunk[@]}" -ne 0 ] || return 0
        local out rc merged
        out=$(run_bounded bd show --db "$db" "${chunk[@]}" --json 2>/dev/null)
        rc=$?
        if [ "$rc" -ne 0 ] || [ -z "$out" ]; then
            chunk_failed="rc=$rc"
            return 1
        fi
        out=$(printf '%s' "$out" | strip_ctl)
        # `bd show` answers an ARRAY when at least one id resolves and a bare
        # OBJECT — {"error":"no issues found..."} — when none does, rc=0 either
        # way. Adding an object to an array is a jq type error, so treating that
        # shape as corruption would fail the store for the ordinary case of a
        # chunk made entirely of non-ids. An object contributes nothing; its ids
        # then surface as unresolved notes, which is what they are.
        # PROJECTED before merging: a resolved bead carries its whole
        # description and notes, and the join below only needs the id, the
        # status and the edge ids. Keeping the bodies would rebuild the same
        # oversized argv the fourth field above exists to avoid.
        merged=$(printf '%s' "$out" | jq -c --argjson a "$resolved" \
            'if type == "array" then
                 $a + [ .[] | {id: (.id // "" | tostring),
                               status: (.status // "" | tostring),
                               edges: [ (.dependencies // [])[]
                                        | ((.depends_on_id // .id) // "")
                                        | select(. != "") ]} ]
             elif type == "object" then $a
             else null end' 2>/dev/null)
        if [ -z "$merged" ] || [ "$merged" = "null" ]; then
            chunk_failed="unparseable"
            return 1
        fi
        resolved="$merged"
        chunk=()
        return 0
    }

    while IFS= read -r cid; do
        [ -n "$cid" ] || continue
        chunk+=("$cid")
        if [ "${#chunk[@]}" -ge "$CHUNK" ]; then
            flush_chunk || break
        fi
    done <<CAND_EOF
$cand_ids
CAND_EOF
    [ -n "$chunk_failed" ] || flush_chunk || true

    if [ -n "$chunk_failed" ]; then
        # A partial resolve would silently reclassify real beads as "not a bead
        # id" and drop every finding under them — the fail-open this check
        # exists to remove.
        warnings+=("$label: could not resolve candidate bead ids in $db ($chunk_failed) — this store was NOT checked")
        continue
    fi

    # ── Judge each (source, verb, candidate) ────────────────────────────────
    # Every remaining question is answered from data already in hand: each pair
    # carries the SOURCE's edge ids (field 4), and the projected resolve
    # carries each candidate's status and ITS edges — the reverse direction.
    # Only the small projected set crosses argv; see the WAIT_JQ header on why.
    verdicts=$(printf '%s\n' "$pairs" | jq -R -s -r --argjson res "$resolved" '
        ( [ $res[] | {key: .id, value: .} ] | from_entries ) as $resmap
      | split("\n") | map(select(length > 0))
      | map(split("\u001f"))
      | map(select(length >= 4))
      | unique
      | map(
          .[0] as $src | .[1] as $verb | .[2] as $cand
        | (.[3] | split(",") | map(select(. != ""))) as $srcedges
        | ($resmap[$cand] // null) as $cb
        | if $cb == null then
              {kind: "unresolved", src: $src, verb: $verb, cand: $cand, status: ""}
          elif ($srcedges | index($cand)) != null
                or (($cb.edges // []) | index($src)) != null then
              {kind: "ok", src: $src, verb: $verb, cand: $cand, status: ""}
          else
              {kind: (if (($cb.status // "") == "closed") then "frozen" else "unedged" end),
               src: $src, verb: $verb, cand: $cand, status: ($cb.status // "?")}
          end)
      | map(select(.kind != "ok"))
      | .[] | [.kind, .src, .verb, .cand, .status] | join("\u001f")' 2>/dev/null)
    verdicts_rc=$?

    if [ "$verdicts_rc" -ne 0 ]; then
        warnings+=("$label: could not join wait language to the dependency graph in $db — this store was NOT checked")
        continue
    fi

    [ -n "$verdicts" ] || continue

    while IFS=$'\037' read -r kind src verb cand status; do
        [ -n "$kind" ] || continue
        case "$kind" in
            frozen)
                errors+=("$label/$src: prose says \"$verb $cand\" and $cand is already CLOSED, with no edge between them. Nothing can notice the wait ended — the sentence will say it is pending forever. Add the edge (I1).") ;;
            unedged)
                errors+=("$label/$src: prose says \"$verb $cand\" ($cand is $status) but no dependency edge records it, so no query can answer whether this is still waiting. Add the edge (I1).") ;;
            unresolved)
                notes+=("$label/$src: prose says \"$verb $cand\" but $cand resolves to no bead in this store — a wait naming something that does not exist, or a cross-store reference") ;;
        esac
    done <<VERDICT_EOF
$verdicts
VERDICT_EOF

done <<SCOPE_EOF
$scopes
SCOPE_EOF

if [ "$checked" -eq 0 ]; then
    echo "cannot determine whether every wait is recorded as an edge"
    echo "No bead store could be examined."
    print_lines "${warnings[@]+"${warnings[@]}"}"
    print_lines "${notes[@]+"${notes[@]}"}"
    exit 1
fi

n_err=${#errors[@]}
n_warn=${#warnings[@]}

if [ "$n_err" -gt 0 ]; then
    echo "$n_err wait(s) recorded only as prose, with no edge the graph can answer"
    print_lines "${errors[@]+"${errors[@]}"}"
    print_lines "${warnings[@]+"${warnings[@]}"}"
    print_lines "${notes[@]+"${notes[@]}"}"
    exit 2
fi

if [ "$n_warn" -gt 0 ]; then
    echo "every prose wait found across $checked store(s) has an edge, but $n_warn probe(s) could not be read"
    print_lines "${warnings[@]+"${warnings[@]}"}"
    print_lines "${notes[@]+"${notes[@]}"}"
    exit 1
fi

echo "every wait in prose across $checked store(s) is also a graph edge"
print_lines "${notes[@]+"${notes[@]}"}"
exit 0
