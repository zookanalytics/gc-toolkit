#!/usr/bin/env bash
# doctor/check-wait-is-an-edge — I1: every wait is a graph edge, not a string.
# Per bead store: where a LIVE bead's own metadata states that it is waiting
# on another bead, a BLOCKING dependency edge must record that wait in one
# direction or the other. Live is every non-closed status: parking or claiming
# a bead does not answer the wait it states, it only stops the bead appearing
# in the narrower listing. A string answers no query, so a wait held only in
# metadata is invisible to `bd ready` and to every surface that re-derives what
# is still blocked (docs/lifecycle-composition.md §1). A non-blocking edge is
# no better: `bd dep add --help` states that type=blocks is what excludes the
# dependent from `bd ready`, so a tracks, parent-child or related record leaves
# the wait exactly as unanswerable as the bare string does. Two findings are
# reported apart because they differ in degree: UNEDGED names a bead that is
# still live, FROZEN a closed one, where the wait is over and nothing can
# notice.
# Read-only. Exit 0=OK 1=Warning 2=Error. stdout: first line = message, then
# "  - detail" lines. Live probes are bounded; an UNREADABLE probe warns (1),
# never passes.

set -u

BOUND="${GC_DOCTOR_CHECK_TIMEOUT:-30}"
# Candidate ids resolve through a batched `bd show`, split so a store with a
# large candidate set cannot build an argv past the exec limit.
CHUNK="${GC_DOCTOR_WAIT_CHUNK:-100}"
# EVERY NON-CLOSED STATUS. `closed` is the only value that ends a wait; a bead
# that has been claimed, parked or blocked still states one, and its wait is as
# unanswerable as an open bead's. `hooked` and `blocked` are bd's "wip"
# category and `pinned` its "frozen" one, so all three are live — the same set
# and the same reasoning as docs/gascity-dispatch-containment.md. Not a
# parameter: an env knob here would let a caller narrow the invariant to a
# subset of beads and still read as a clean run. One comma-separated value,
# because repeating `--status` silently overwrites the previous one.
LIVE_STATUSES='open,in_progress,blocked,deferred,hooked,pinned'

errors=(); warnings=(); notes=()
run_bounded() { if command -v timeout >/dev/null 2>&1; then timeout "$BOUND" "$@" </dev/null; else "$@" </dev/null; fi; }
detail() { local v; for v in "$@"; do printf '  - %s\n' "$v"; done; }
# Rows below are joined on 0x1F, which this scrub also clears, so no payload
# byte can pose as a field separator.
# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload. All but
# LF go: raw TAB and CR do not occur in bd/gh output, and the TAB-splitting
# consumers downstream split jq's own @tsv, emitted after this runs.
scrub() { tr -d '\000-\011\013-\037'; }
# <<< control-char-scrub

# ---------------------------------------------------------------------------
# The wait predicate, as one jq program so the pattern lives in one place.
# Emits <source-id> US <verb> US <candidate-id> US <source-edge-ids>.
#
# ONLY SURFACES THE BEAD WRITES ABOUT ITSELF ARE READ, which is what makes a
# match attributable. Free-form notes are excluded on measurement rather than
# taste: across this city every live bead whose notes carry wait language names
# a THIRD PARTY as the waiter, because survey and audit beads record other
# beads' states in the same words a first-person wait uses. Attributing those to
# whoever wrote them down would report the graph as broken where it is correct.
#
# THE TRIGGER IS THE VERB wherever the value is prose. A bare bead mention is
# usually provenance or a conclusion, and a conclusion is prose BY DESIGN:
# lifecycle-composition.md §1 has it stored once and never cleared, so
# demanding an edge for every mention would demand the opposite of the rule.
#
# THE ID PREFIXES COME FROM THE LIVE ROSTER. A generic "letters, hyphen, token"
# shape reads ordinary hyphenated English as bead ids, and each non-id becomes
# its own note in front of the real findings.
#
# ONLY BLOCKING EDGES ARE COLLECTED, on both sides of the join. Both spellings
# are tested because the same edge is keyed `.type` by `bd list` and
# `.dependency_type` by `bd show`, each command rendering the other field null.
#
# THE SOURCE'S EDGE IDS RIDE ALONG as a fourth field, which is a size
# constraint rather than a convenience: the live listing runs to megabytes and
# passing it to a second jq as --argjson exceeds the single-argument limit,
# which fails the store closed. The payload crosses once, already reduced to
# the ids the join needs.
# ---------------------------------------------------------------------------
# A key that DECLARES a dependency. The value is the wait, so no verb is
# needed; `gc-helm.sh takeaway --waiting-on` writes both this and the edge, and
# warns on stderr when it could wire only the string.
WAITKEY_RE='^(gc\.)?(blocked_on|blocked_by|waiting_on|waits_on|waiting_for|wait_on|depends_on|dependent_on|gated_on|holding_for|held_by)(_[a-z0-9_]+)?$'
# A key whose value is this bead's own status prose, read with the verb
# predicate. `gc.takeaway` is the board headline a bead carries about itself.
PROSEKEY_RE='^gc\.takeaway$|reason$'

# shellcheck disable=SC2016  # $prefixes is a jq variable fed by --arg; shell expansion here would be the bug
WAIT_JQ='
# The verb group is CAPTURING: jq scan() returns only capture groups, so a
# non-capturing group drops the verb and shifts the id into the wrong field.
# BOUNDED ON BOTH SIDES. Without a trailing boundary the alternation matches a
# prefix of a longer word, turning "blocked only on mechanism" into a wait;
# without a leading one, "unblocked by" matches "blocked by" and inverts the
# sentence. Boundaries are the whole guard, deliberately: a negated-verb list
# would have to enumerate every negation, and each phrase it missed would drop
# a REAL wait silently.
def verbs: "(waiting on|waits on|waiting for|wait on|wait for|blocked on|blocked by|awaiting|await|pending|depends on|dependent on|gated on|gating on|holding for|hold for|held by|hinges on)";
# The tail floor admits the shortest id this city mints; a more natural-looking
# floor skips those beads, and a skipped bead shows up as a finding that never
# appears.
def idbare: "(?:" + $prefixes + ")-[a-z0-9][a-z0-9.]{2,}";
# THE SUBJECT WINDOW, captured so a wait can be attributed to whoever the
# sentence says is waiting: the subject is the NEAREST bead id before the verb.
# A sentence ends at a period followed by space or end of line, never at a bare
# period, because ids are hierarchical and a subject named su-xkmq.4 would
# otherwise put the boundary inside its own id and hide itself.
def nb: "(?:[^.\n]|\\.(?![ \t\n]|$))";
def lead: "(" + nb + "*)";
# BETWEEN VERB AND ID: a lazy same-sentence window, so the candidate is the
# FIRST id after the verb and a wait cannot reach across a sentence boundary
# into unrelated prose. It stays a window rather than a word allowlist: a
# status line writes "blocked on design bead tk-x" and "gated on the review of
# tk-y", and every word an allowlist missed would drop a real wait in silence.
def gap: "(?:" + nb + "{0,40}?)";
# EVERY id in the wait phrase, not only the first: scan() resumes after each
# match, so one verb followed by a LIST would otherwise yield one pair and
# leave every later target unexamined. The continuation is SEPARATOR-GATED
# rather than a wider character window, which would sweep in ids from unrelated
# prose later in the sentence.
def glue: "(?:[ \t]*(?:,|;|&|/|\\band\\b|\\bor\\b|\\bplus\\b))+[ \t]*";
def tail: "((?:" + glue + idbare + ")*)";
# A sentence-final period lands inside the id match, because the pattern admits
# dots for hierarchical ids like tk-yhwfv.3. Trailing dots go, interior dots
# stay, applied per id because any member of a list can end the sentence.
def clean: sub("\\.+$"; "");
def blocking: (.type // "") == "blocks" or (.dependency_type // "") == "blocks";
.[]?
| . as $b
| ($b.id // "" | tostring) as $src
| ($b.metadata // {}) as $meta
| ( [ ($b.dependencies // [])[] | select(blocking)
      | ((.depends_on_id // .id) // "")
      | select(. != "") ] | join(",") ) as $srcedges
| (
    # RULE A — the KEY is the wait. A key that declares a dependency needs no
    # verb: every bead id in its value is a wait this bead has stated about
    # itself, so an id there with no edge is a string-shaped wait outright.
    ( $meta | to_entries[]
      | select(.key | test($waitkey))
      | .key as $k | (.value | tostring)
      | [ scan(idbare) ] | .[]
      | clean | select(. != $src and . != "") as $cand
      | [ $src, ("metadata " + $k + " names " + $cand), $cand, $srcedges ] )
  ,
    # RULE B — the VALUE is status prose the bead writes about ITSELF, which is
    # the whole reason a match here can be attributed. Free-form notes are not
    # read: in this city they are a ledger of what OTHER beads are doing, where
    # the subject of a wait sentence is routinely a third party.
    ( $meta | to_entries[]
      | select(.key | test($prosekey))
      | (.value | tostring)
      | [ scan("(?i)" + lead + "\\b" + verbs + "\\b" + gap + "(" + idbare + ")" + tail) ]
      | .[]?
      | . as $m
      | ( ($m[0] // "") | [ scan(idbare) ] | last // "" ) as $subj
      | select($subj == "" or $subj == $src)
      | ( [ $m[2] ] + ( ($m[3] // "") | [ scan(idbare) ] ) )
      | .[]
      | clean | select(. != $src and . != "") as $cand
      | [ $src, ("prose says \"" + ($m[1] | ascii_downcase) + " " + $cand + "\""), $cand, $srcedges ] )
  )
| join("\u001f")
'

rigs_raw=$(run_bounded gc rig list --json 2>/dev/null); rigs_rc=$?
if [ "$rigs_rc" -ne 0 ] || [ -z "$rigs_raw" ]; then
    echo "cannot determine whether every wait is recorded as an edge (I1)"
    detail "\`gc rig list --json\` failed (rc=$rigs_rc) or returned nothing; there is no set of bead stores to scan."
    exit 1
fi

# US-joined so a rig with an empty name still yields its path field intact.
scopes=$(printf '%s' "$rigs_raw" | jq -r '.rigs[]? | select((.path // "") != "")
    | [((.name // "") | gsub("[[:cntrl:]]"; " ")), .path, ((.suspended // false) | tostring)]
    | join("\u001f")' 2>/dev/null)
# Sorted longest-first so a longer prefix is not shadowed by one that prefixes it.
PREFIXES=$(printf '%s' "$rigs_raw" | jq -r '[ .rigs[]? | (.prefix // "") | select(test("^[a-z]{1,8}$")) ]
    | unique | sort_by(-length) | join("|")' 2>/dev/null)
# A candidate resolves in the store its PREFIX names, not in the store that
# mentioned it. Waits cross rigs, and one resolved store-locally answers "no
# issues found", which downgrades a real unedged wait to a note.
PREFIX_MAP=$(printf '%s' "$rigs_raw" | jq -r '.rigs[]? | select((.path // "") != "")
    | (.prefix // "") as $p | select($p | test("^[a-z]{1,8}$"))
    | [$p, (.path + "/.beads")] | join("\u001f")' 2>/dev/null)
# Rig and agent names match the <prefix>-<tail> shape exactly, so the scan
# cannot help proposing them. Resolution stops them being ERRORS; this stops
# them being noise, and it reaches only candidates that resolved nowhere, so a
# name that is genuinely a bead is judged on its edges like any other.
RIG_NAMES=$(printf '%s' "$rigs_raw" | jq -r '.rigs[]? | (.name // "") | select(. != "")' 2>/dev/null)

if [ -z "$scopes" ]; then
    echo "cannot determine whether every wait is recorded as an edge (I1)"
    detail "\`gc rig list --json\` listed no rig paths; the listing shape changed or the output is corrupt."
    exit 1
fi
if [ -z "$PREFIXES" ]; then
    echo "cannot determine whether every wait is recorded as an edge (I1)"
    detail "\`gc rig list --json\` reported no usable issue prefixes; a bead id cannot be told from ordinary hyphenated prose without them."
    exit 1
fi
if [ -z "$PREFIX_MAP" ]; then
    # Two views of one roster disagree: candidates could be matched and never
    # resolved, which reports every wait as a note and the city as clean.
    echo "cannot determine whether every wait is recorded as an edge (I1)"
    detail "\`gc rig list --json\` yielded issue prefixes but no prefix-to-store map; a candidate bead id could be recognised but never resolved."
    exit 1
fi

is_known_identifier() { # <candidate> — a rig name, or one of its dotted agent names
    local c="$1" n
    [ -n "$RIG_NAMES" ] || return 1
    while IFS= read -r n; do
        [ -n "$n" ] || continue
        [ "$c" = "$n" ] && return 0
        # $n is quoted, so a glob character inside a rig name stays literal.
        case "$c" in "$n".*) return 0 ;; esac
    done <<RIGNAME_EOF
$RIG_NAMES
RIGNAME_EOF
    return 1
}

checked=0
while IFS=$'\037' read -r rig_name rig_path suspended; do
    [ -n "$rig_path" ] || continue
    label="${rig_name:-<city>}"
    if [ "$suspended" = "true" ]; then
        notes+=("$label: skipped (suspended — querying its store would auto-start an orphan Dolt server)")
        continue
    fi
    db="$rig_path/.beads"
    # An absent store is an uninitialised rig, not a clean one. Silence here
    # is the failure this check exists to remove, so it is noted.
    if [ ! -d "$db" ]; then
        notes+=("$label: skipped (no bead store at $db)")
        continue
    fi

    live_raw=$(run_bounded bd list --db "$db" --status "$LIVE_STATUSES" --json --limit 0 2>/dev/null); live_rc=$?
    if [ "$live_rc" -ne 0 ]; then
        warnings+=("$label: could not list live beads in $db (rc=$live_rc) — this store was NOT checked")
        continue
    fi
    # An empty store answers `[]`; an empty STRING is not that answer.
    if [ -z "$live_raw" ]; then
        warnings+=("$label: \`bd list\` over $db returned no output — this store was NOT checked")
        continue
    fi
    live_json=$(printf '%s' "$live_raw" | scrub)
    if ! printf '%s' "$live_json" | jq -e 'type=="array"' >/dev/null 2>&1; then
        warnings+=("$label: live listing from $db is not a JSON array — this store was NOT checked")
        continue
    fi
    checked=$((checked + 1))

    pairs=$(printf '%s' "$live_json" | jq -r --arg prefixes "$PREFIXES" --arg waitkey "$WAITKEY_RE" --arg prosekey "$PROSEKEY_RE" "$WAIT_JQ" 2>/dev/null); pairs_rc=$?
    if [ "$pairs_rc" -ne 0 ]; then
        warnings+=("$label: could not scan live beads in $db for wait language — this store was NOT checked")
        continue
    fi
    [ -n "$pairs" ] || continue

    cand_ids=$(printf '%s\n' "$pairs" | awk -F'\037' 'NF>=3 {print $3}' | sort -u)
    [ -n "$cand_ids" ] || continue

    resolved='[]'; chunk=(); chunk_failed=""
    flush_chunk() { # <owning-store-db>
        local cdb="$1" out rc merged
        [ "${#chunk[@]}" -ne 0 ] || return 0
        out=$(run_bounded bd show --db "$cdb" "${chunk[@]}" --json 2>/dev/null); rc=$?
        out=$(printf '%s' "$out" | scrub)
        if [ -z "$out" ]; then chunk_failed="rc=$rc, no output from $cdb"; return 1; fi
        # `bd show` EXITS non-zero when nothing in the batch resolved, printing
        # a well-formed no-matches error on stdout. That is a determinate
        # answer, not a failed read, and a batch made entirely of non-ids is
        # ordinary once candidates are grouped by owning store. Narrow on
        # purpose: any other non-zero exit still fails the store closed.
        if [ "$rc" -ne 0 ] \
           && ! printf '%s' "$out" | jq -e 'type == "object"
                   and ((.error // "") | test("no issues? found"; "i"))' >/dev/null 2>&1; then
            chunk_failed="rc=$rc reading $cdb"; return 1
        fi
        # An ARRAY when at least one id resolves, a bare OBJECT when none does.
        # Adding an object to an array is a jq type error, so treating that
        # shape as corruption would fail the store for the ordinary all-non-id
        # batch. PROJECTED before merging: keeping whole bead bodies would
        # rebuild the oversized argv the fourth pair field exists to avoid.
        # `blocking` mirrors the pairs program's filter, which is what keeps the
        # two sides of the join asking the same question of an edge.
        merged=$(printf '%s' "$out" | jq -c --argjson a "$resolved" \
            'def blocking: (.type // "") == "blocks" or (.dependency_type // "") == "blocks";
             if type == "array" then
                 $a + [ .[] | {id: (.id // "" | tostring),
                               status: (.status // "" | tostring),
                               edges: [ (.dependencies // [])[]
                                        | select(blocking)
                                        | ((.depends_on_id // .id) // "")
                                        | select(. != "") ]} ]
             elif type == "object" then $a
             else null end' 2>/dev/null)
        if [ -z "$merged" ] || [ "$merged" = "null" ]; then chunk_failed="unparseable"; return 1; fi
        resolved="$merged"; chunk=(); return 0
    }

    while IFS=$'\037' read -r cand_pfx cand_db; do
        [ -n "$cand_pfx" ] && [ -n "$cand_db" ] || continue
        [ -d "$cand_db" ] || continue
        # Prefixes are [a-z]{1,8} by the roster filter, so this pattern carries
        # no regex metacharacters.
        group=$(printf '%s\n' "$cand_ids" | grep -E "^${cand_pfx}-" 2>/dev/null) || group=""
        [ -n "$group" ] || continue
        # Each owning store starts with an EMPTY batch: a leftover id from the
        # previous prefix would be looked up in the wrong store and resolve to
        # nothing, turning a real bead into an unresolved note.
        chunk=()
        while IFS= read -r cid; do
            [ -n "$cid" ] || continue
            chunk+=("$cid")
            if [ "${#chunk[@]}" -ge "$CHUNK" ]; then flush_chunk "$cand_db" || break; fi
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
        # A partial resolve reclassifies real beads as "not a bead id" and
        # drops every finding under them.
        warnings+=("$label: could not resolve candidate bead ids for beads in $db ($chunk_failed) — this store was NOT checked")
        continue
    fi

    # Each pair carries the SOURCE's blocking edge ids; the projected resolve
    # carries each candidate's status and ITS blocking edges, which is the
    # reverse direction. A blocking edge from either side satisfies the
    # invariant, which asks that the relation be answerable and states no
    # direction. Non-blocking edges reached neither list.
    verdicts=$(printf '%s\n' "$pairs" | jq -R -s -r --argjson res "$resolved" '
        ( [ $res[] | {key: .id, value: .} ] | from_entries ) as $resmap
      | split("\n") | map(select(length > 0)) | map(split("\u001f"))
      | map(select(length >= 4)) | unique
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
                errors+=("$label bead $src: $verb, and $cand is already CLOSED with no \`blocks\` edge between them. The wait resolved and nothing surfaced it, so this bead reads as pending for good. Record the edge, and give this bead its disposition (I1).") ;;
            unedged)
                errors+=("$label bead $src: $verb ($cand is $status), but no \`blocks\` edge records it, so \`bd ready\` cannot answer whether this is still waiting. Add that edge. Any other type records the relation without gating on it (I1).") ;;
            unresolved)
                # A rig or agent name sharing the id SHAPE names a place, not a
                # missing bead.
                is_known_identifier "$cand" && continue
                notes+=("$label bead $src: $verb, but $cand resolves to no bead in any store this city knows — a wait naming something that does not exist, or an id whose prefix belongs to no rig here") ;;
        esac
    done <<VERDICT_EOF
$verdicts
VERDICT_EOF
done <<SCOPE_EOF
$scopes
SCOPE_EOF

if [ "$checked" -eq 0 ]; then
    echo "cannot determine whether every wait is recorded as an edge (I1)"
    detail "No bead store could be examined."
    detail ${warnings[@]+"${warnings[@]}"}
    detail ${notes[@]+"${notes[@]}"}
    exit 1
fi
if [ "${#errors[@]}" -ne 0 ]; then
    echo "waits recorded only as a string, with no edge the graph can answer (I1): ${#errors[@]} finding(s)"
    detail "${errors[@]}"
    detail ${warnings[@]+"${warnings[@]}"}
    detail ${notes[@]+"${notes[@]}"}
    exit 2
fi
if [ "${#warnings[@]}" -ne 0 ]; then
    echo "every stated wait found across $checked store(s) is an edge, but some probes could not be read (I1)"
    detail "${warnings[@]}"
    detail ${notes[@]+"${notes[@]}"}
    exit 1
fi
echo "OK: every wait a live bead states about itself across $checked store(s) is also a graph edge"
detail ${notes[@]+"${notes[@]}"}
exit 0
