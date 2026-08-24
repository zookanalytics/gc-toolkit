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
# candidate before judging it removes that class entirely, at a handful of
# batched reads. An id resolving to nothing is reported as its own note —
# prose naming a bead that does not exist is a different defect, and swallowing
# it would hide it.
#
# ── RESOLUTION IS CITY-WIDE, NOT STORE-LOCAL ────────────────────────────────
# A candidate is resolved in the store its PREFIX names. Waits cross rigs:
# signal-loom sl-djvs says it is blocked on gc-toolkit tk-bq9ua, which is open
# in gc-toolkit with no edge either way. Looked up only in signal-loom that id
# answers "no issues found", the finding is downgraded to an unresolved NOTE,
# and the check can exit 0 with a real unedged wait standing in the graph
# (tk-w2dk5k P1). Both directions still answer across the boundary: the
# source's edge ids ride along on each pair, and the candidate's own edges come
# from its own store — so a cross-rig wait that IS recorded still reads as ok.
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
# is individually bounded. Cost per store is one open listing (0.4s for 909
# beads) plus one batched resolve per OWNING store the candidates name — at
# most one per rig, and in practice one or two, because a store's waits name
# their own rig or one neighbour.
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
# BOUNDED ON BOTH SIDES at the call site below. Without a trailing boundary the
# alternation matches a PREFIX of a longer word and converts conclusion prose
# into a dependency demand: `Blocked only on mechanism - see tk-bq9ua` matched
# `blocked on` inside `blocked onl`, and was reported as a wait on tk-bq9ua
# (tk-w2dk5k P2). Without a leading one, `unblocked by tk-x` matches `blocked
# by`, inverting the sentence outright.
#
# Boundaries are the whole guard, deliberately — no negated-verb heuristic sits
# on top. `not`/`no longer`/`previously` before a verb would have to be
# enumerated, and every phrase the list missed would silently drop a REAL wait.
# A detector whose failure mode is silence is the thing this check exists to
# remove, so the tightening stops where it can be proved: at word edges.
def verbs: "(waiting on|waits on|waiting for|blocked on|blocked by|awaiting|await|pending|depends on|dependent on|gated on|holding for|held by)";
# The tail is 3+ characters, which is the SHORTEST id this city actually mints:
# measured 2026-08-24 over every store, 2 open beads carry a 3-character tail
# (su-02g, tk-1co) against 1,008 at five. A 4-character floor reads more
# naturally and would have silently skipped those two — the kind of blind spot
# that only shows up as a finding that never appears.
def idbare: "(?:" + $prefixes + ")-[a-z0-9][a-z0-9.]{2,}";
def idpat: "(" + idbare + ")";
# EVERY id in the wait phrase, not just the first. `scan` resumes after the end
# of each match, so a single verb followed by a LIST produced exactly one pair:
# for `blocked by tk-good and tk-bad1`, the verb was consumed by the first id
# and nothing was left to re-trigger the alternation, so tk-bad1 was never
# emitted at all. Once the first id in a list carries an edge the check printed
# a clean city and exited 0 while every later target in the same sentence went
# unexamined — a false NEGATIVE, which is the one failure mode this check exists
# to remove (tk-9vbeim P1, reproduced against a fake ledger).
#
# The continuation is SEPARATOR-GATED rather than a wider character window. A
# bigger `{0,N}` bound would sweep in ids from unrelated prose later in the same
# sentence and report waits nobody wrote; requiring list glue — a comma,
# semicolon, ampersand, slash, `and`, `or`, `plus`, in any run — matches how a
# list is actually written and stops at the first word that is not one. So
# `blocked by tk-aaa, tk-bbb, and tk-ccc` yields three, while `blocked by
# tk-aaa and then we shipped tk-bbb later` still yields one. The verbs stay
# word-bounded for the same reason they already were.
def glue: "(?:[ \\t]*(?:,|;|&|/|\\band\\b|\\bor\\b|\\bplus\\b))+[ \\t]*";
def tail: "((?:" + glue + idbare + ")*)";
.[]?
| . as $b
| ($b.id // "" | tostring) as $src
| ( [ ($b.notes // "" | tostring) ]
    + [ ($b.metadata // {} | to_entries[]
         | select(.key | test("(?i)reason|blocked")) | (.value | tostring)) ]
  ) as $prose
| ( [ ($b.dependencies // [])[] | ((.depends_on_id // .id) // "")
      | select(. != "") ] | join(",") ) as $srcedges
| $prose[]
| [ scan("(?i)\\b" + verbs + "\\b[^.\n]{0,40}?\\b" + idpat + tail) ]
| .[]?
| . as $m
# $m is [verb, first-id, trailing-list]. The trailing group is glue+id repeats,
# so re-scanning it with the bare pattern yields the rest of the list in order.
| ( [ $m[1] ] + ( ($m[2] // "") | [ scan(idbare) ] ) )
| .[]
# A sentence-final period is swallowed by the id pattern, which has to admit
# dots for hierarchical ids like tk-yhwfv.3 — so "awaiting tk-8rm3q." yields
# "tk-8rm3q.", which resolves to nothing and would be reported as a wait on a
# bead that does not exist. Trailing dots are stripped; interior ones are kept.
# Applied per id, because any member of a list can end the sentence.
| sub("\\.+$"; "") as $cand
| select($cand != $src and $cand != "")
| [ $src, ($m[0] | ascii_downcase), $cand, $srcedges ]
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

# The same roster again, as a prefix -> STORE map. A candidate id is resolved in
# the store its prefix names, not in the store that happened to mention it; see
# the resolve block below for why that is a correctness requirement and not an
# optimisation.
PREFIX_MAP=$(printf '%s' "$rigs_raw" \
    | jq -r '.rigs[]? | select((.path // "") != "")
             | (.prefix // "") as $p | select($p | test("^[a-z]{1,8}$"))
             | [$p, (.path + "/.beads")] | join("\u001f")' 2>/dev/null)

# The roster's own NAMES, which are the things most likely to be mistaken for
# ids without being any. A rig called `gc-toolkit` and an agent called
# `gc-toolkit.furiosa` both match the `<prefix>-<tail>` shape exactly — `gc-` is
# gascity's prefix and `toolkit` is a legal tail — so the scan cannot help
# proposing them, and the live run reported both as unresolved wait notes.
#
# Resolution already stops them being ERRORS; this stops them being NOISE, which
# is the other way a check gets ignored. It is applied ONLY to candidates that
# resolved to no bead in any store, so it can never hide a real one: were
# `gc-toolkit` actually minted as a bead somewhere it would resolve, be judged
# on its edges like anything else, and never reach this filter.
RIG_NAMES=$(printf '%s' "$rigs_raw" \
    | jq -r '.rigs[]? | (.name // "") | select(. != "")' 2>/dev/null)

# A candidate is a known identifier when it IS a rig name, or is one of that
# rig's dotted agent/session names.
is_known_identifier() { # is_known_identifier <candidate>
    local c="$1" n
    [ -n "$RIG_NAMES" ] || return 1
    while IFS= read -r n; do
        [ -n "$n" ] || continue
        [ "$c" = "$n" ] && return 0
        # $n is quoted, so any glob character inside a rig name stays literal.
        case "$c" in "$n".*) return 0 ;; esac
    done <<RIGNAME_EOF
$RIG_NAMES
RIGNAME_EOF
    return 1
}

if [ -z "$PREFIXES" ]; then
    # Without the prefix set the scan cannot tell a bead id from a hyphenated
    # word, and a check that guesses is worse than one that says it could not
    # look.
    echo "cannot determine whether every wait is recorded as an edge"
    echo "\`gc rig list --json\` reported no usable issue prefixes; a bead id cannot be told from ordinary hyphenated prose without them."
    exit 1
fi

if [ -z "$PREFIX_MAP" ]; then
    # PREFIXES parsed but the map did not, so the two views of one roster
    # disagree. Candidates could still be MATCHED and never RESOLVED, which
    # reports every wait as an unresolved note and the city as clean.
    echo "cannot determine whether every wait is recorded as an edge"
    echo "\`gc rig list --json\` yielded issue prefixes but no prefix-to-store map; a candidate bead id could be recognised but never resolved."
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

    # ── Resolve the candidate ids, ACROSS STORES ────────────────────────────
    # Batched, and the ONLY thing separating a bead id from a rig or tool name
    # of the same shape.
    #
    # Each candidate is resolved in the store its PREFIX names, not in the
    # store that happened to mention it. A wait can cross rigs, and one does
    # today: signal-loom sl-djvs says it is blocked on gc-toolkit tk-bq9ua,
    # which is OPEN in gc-toolkit and carries no edge in either direction.
    # Resolved store-locally that lookup answers
    # {"error":"no issues found matching the provided IDs"}, so a real unedged
    # wait was downgraded to an "unresolved" NOTE and the check could exit 0
    # over it — the exact fail-open it exists to remove (tk-w2dk5k P1).
    #
    # Both halves of the judgement survive the crossing: the SOURCE's edge ids
    # ride along on each pair and a cross-store edge is just a foreign id in
    # that list, while the REVERSE direction comes from the candidate's own
    # `bd show` in its own store. So a cross-rig pair that IS recorded still
    # reads as ok.
    #
    # A candidate whose prefix names no rig in this city is resolvable nowhere
    # and stays a note, which is the honest answer for it.
    cand_ids=$(printf '%s\n' "$pairs" | awk -F'\037' 'NF>=3 {print $3}' | sort -u)
    [ -n "$cand_ids" ] || continue

    resolved='[]'
    chunk=()
    chunk_failed=""

    flush_chunk() {
        local cdb="$1"
        [ "${#chunk[@]}" -ne 0 ] || return 0
        local out rc merged
        out=$(run_bounded bd show --db "$cdb" "${chunk[@]}" --json 2>/dev/null)
        rc=$?
        out=$(printf '%s' "$out" | strip_ctl)
        if [ -z "$out" ]; then
            chunk_failed="rc=$rc, no output from $cdb"
            return 1
        fi
        # `bd show` EXITS 1 when nothing in the batch resolved, printing a
        # well-formed {"error":"no issues found matching the provided IDs"} on
        # stdout. That is a determinate answer — "none of these are beads here"
        # — and not a failed read, so it must not fail the store closed.
        #
        # Grouping by owning store is what makes an all-non-id batch routine:
        # `gc-toolkit` and `gc-toolkit.furiosa` are rig and agent names that
        # match the `gc-` id shape, and in a store whose waits name no gascity
        # bead they are the ENTIRE `gc-` group. Before grouping, every
        # candidate went to one store in one batch that always held at least
        # one real id, so rc was always 0 and this arm was never reached —
        # the old code was accidentally protected rather than correct.
        #
        # Narrow on purpose: only the no-matches error is accepted. Any OTHER
        # non-zero exit, or an error object saying anything else, is still an
        # unreadable store and still fails closed.
        if [ "$rc" -ne 0 ] \
           && ! printf '%s' "$out" | jq -e 'type == "object"
                   and ((.error // "") | test("no issues? found"; "i"))' >/dev/null 2>&1; then
            chunk_failed="rc=$rc reading $cdb"
            return 1
        fi
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

    # One pass per OWNING store. The candidate set is small (dozens at most),
    # so this is a handful of bounded reads even on a five-rig city.
    while IFS=$'\037' read -r cand_pfx cand_db; do
        [ -n "$cand_pfx" ] && [ -n "$cand_db" ] || continue
        [ -d "$cand_db" ] || continue
        # Prefixes are `[a-z]{1,8}` by the roster filter, so this pattern
        # carries no regex metacharacters.
        group=$(printf '%s\n' "$cand_ids" | grep -E "^${cand_pfx}-" 2>/dev/null) || group=""
        [ -n "$group" ] || continue
        # Start each owning store with an EMPTY batch: a leftover id from the
        # previous prefix would be looked up in the wrong store and resolve to
        # nothing, turning a real bead into an unresolved note.
        chunk=()
        while IFS= read -r cid; do
            [ -n "$cid" ] || continue
            chunk+=("$cid")
            if [ "${#chunk[@]}" -ge "$CHUNK" ]; then
                flush_chunk "$cand_db" || break
            fi
        done <<GROUP_EOF
$group
GROUP_EOF
        [ -n "$chunk_failed" ] && break
        flush_chunk "$cand_db" || true
        [ -n "$chunk_failed" ] && break
    done <<PFX_EOF
$PREFIX_MAP
PFX_EOF

    if [ -n "$chunk_failed" ]; then
        # A partial resolve would silently reclassify real beads as "not a bead
        # id" and drop every finding under them — the fail-open this check
        # exists to remove.
        warnings+=("$label: could not resolve candidate bead ids for beads in $db ($chunk_failed) — this store was NOT checked")
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
                # A rig or agent name that merely shares the id SHAPE is not a
                # wait naming a missing bead; it is a sentence naming a place.
                is_known_identifier "$cand" && continue
                notes+=("$label/$src: prose says \"$verb $cand\" but $cand resolves to no bead in any store this city knows — a wait naming something that does not exist, or an id whose prefix belongs to no rig here") ;;
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
