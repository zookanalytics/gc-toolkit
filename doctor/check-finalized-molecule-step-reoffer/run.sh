#!/usr/bin/env bash
# Pack doctor check: no graph.v2 step bead stays OPEN under a CLOSED molecule root.
#
# THE INVARIANT. A graph.v2 molecule is a root bead plus step beads, each step
# carrying `gc.root_bead_id` pointing back at that root. The root closes when the
# formula's terminal step (`workflow-finalize`) runs. From that moment the
# molecule is terminal: every downstream step is closed, so nothing can consume
# another pass of any step. An OPEN step under a CLOSED root therefore has no
# reader — and is still work the pool will hand out.
#
# WHY IT IS NOT HARMLESS. `gc hook --claim` has no gate on the state of a step's
# own molecule, and a step does not need its own route to be offered: a blank
# `gc.routed_to` on the step still resolves through the ROOT's route, and the
# claim then re-stamps the step's. So the pool spawns a polecat, hands it the
# step, and the step re-executes in full. Observed cost of one cycle of the
# tk-ciuad loop: a pool slot, a city-wide `bd list`/`bd ready` census (206 rows),
# ~150 batched `bd show` reads, a `gh pr list` network call, and a metadata write
# onto a CLOSED root where no normalize step remains to read it. The re-execution
# is the real hazard, not the wasted slot — re-running `workspace-setup` checks
# out `metadata.branch`, which may be the live head of an approved PR under an
# active codex re-gate.
#
# TWO SHAPES, REPORTED SEPARATELY. They are different defects and the
# discriminator is free — no history query, just one metadata key on the step:
#
#   * REOPENED — the step carries `gc.outcome`. It ran to completion and stamped
#     its own verdict, and something reset it to open AFTERWARDS. This is
#     tk-ciuad: the reopen lands in the same SECOND as the teardown of the
#     polecat session that had just closed the step, and it is self-perpetuating
#     — each fresh polecat closes, drains, and its own teardown reopens the bead
#     again. Four incarnations across two polecats before it was caught by hand.
#
#   * NEVER-CLOSED — no `gc.outcome`. The step never ran and the molecule
#     finalized around it. The orphaned-repour family (tk-dchq5 and kin). Less
#     dramatic per cycle but longer-lived: these sit for days, because nothing
#     re-offers them often enough for a human to notice.
#
# THE DURABLE FIX IS NOT HERE. Refusing the offer beats detecting it afterwards,
# and that gate belongs in the gc binary — either at the release that reopens the
# bead, or in `gc hook --claim`, which should refuse a step whose
# `gc.root_bead_id` names a closed root. The elimination evidence narrowing that
# search (four write sites acquitted at file:line, and one earlier acquittal
# OVERTURNED — `ReleaseWorkBead`'s atomic tier is structurally unreachable for
# step beads, because `singleWriteRequired` diverts every bead carrying
# `gc.continuation_group`) is in specs/tk-ciuad/finalized-molecule-step-reoffer.md.
# This check is the pack-side backstop that keeps the failure loud until then,
# and the regression gate after.
#
# WHAT IS FLAGGED — a bead with `status=open` carrying `gc.root_bead_id`, whose
# root resolves IN THE SAME STORE with `status=closed`, and whose root closed
# longer ago than the grace window.
#
# WHAT IS NOT FLAGGED:
#   * An open step under an open or in_progress root. That is a live molecule.
#   * A closed step under a closed root. That is the normal terminal state.
#   * A root closed WITHIN the grace window. Finalize is not atomic — on a
#     healthy molecule the root closes a few seconds BEFORE its own
#     workflow-finalize step does, so a zero-grace check would flag every
#     molecule in the city at the instant it completes. Reported as a note.
#   * A step whose root resolves in no store here and whose `gc.root_store_ref`
#     names somewhere else. Cross-store roots are legitimate; noted, not judged.
#
# FAIL-CLOSED. Every probe that cannot be READ warns rather than passes. A check
# that reports OK when it cannot see reproduces the very silence it exists to
# remove — nothing reported this loop for four cycles, or the tk-iekvu strand for
# four days.
#
# Exit codes: 0=OK, 1=Warning, 2=Error
# stdout: first line=message, rest=details

set -u

# `gc doctor` applies no timeout to pack checks, so an unbounded probe against a
# wedged control plane or bead store would hang the whole doctor run.
BOUND="${GC_DOCTOR_CHECK_TIMEOUT:-30}"

# How long after a root closes its steps may still be settling. Finalize writes
# the root's close and the terminal step's close as separate commits, seconds
# apart, so a small window is normal and a large one is not.
GRACE="${GC_DOCTOR_FINALIZED_STEP_GRACE:-300}"

# Roots are resolved with a batched `bd show`. Chunked so a city with a very
# large open-step population cannot build an argv past the exec limit.
CHUNK="${GC_DOCTOR_ROOT_CHUNK:-100}"

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

# Bead descriptions and notes carry control characters that make jq abort
# mid-parse, which would otherwise cost us a whole store. Everything below 0x20
# except the newline goes — a literal TAB is invalid inside a JSON string just
# like the rest, and it also clears the 0x1F these rows are joined on, so no
# payload byte can pose as a field separator.
strip_ctl() { tr -d '\000-\011\013-\037'; }

# Parse an ISO-8601 instant to epoch seconds. GNU first, BSD/macOS second.
# Prints nothing and returns 1 when neither can read it — the caller then
# reports the finding WITHOUT the grace window rather than suppressing it,
# because an unreadable timestamp is not evidence that a molecule is settling.
epoch_of() {
    local ts="$1" out base
    out=$(date -u -d "$ts" +%s 2>/dev/null) && [ -n "$out" ] && { printf '%s' "$out"; return 0; }
    base="${ts%Z}"
    base="${base%%.*}"
    out=$(date -u -j -f '%Y-%m-%dT%H:%M:%S' "$base" +%s 2>/dev/null) && [ -n "$out" ] && { printf '%s' "$out"; return 0; }
    return 1
}

NOW=$(date -u +%s 2>/dev/null || echo 0)

# ---------------------------------------------------------------------------
# The stores to scan: every rig, plus the city root (which `gc rig list`
# includes). A step and its root live in the same store on the ordinary path;
# gc.root_store_ref records the exception.
# ---------------------------------------------------------------------------
rigs_raw=$(run_bounded gc rig list --json 2>/dev/null)
rigs_rc=$?

if [ "$rigs_rc" -ne 0 ] || [ -z "$rigs_raw" ]; then
    echo "cannot determine whether any finalized molecule is still offering steps"
    echo "\`gc rig list --json\` failed (rc=$rigs_rc) or returned nothing; there is no set of bead stores to scan."
    exit 1
fi

# US-joined, not tab: a rig whose name is empty must still yield an empty FIRST
# field and a path in the second. Under a tab IFS bash would collapse the pair,
# land the path in rig_name, leave rig_path empty, and `continue` — silently
# skipping a whole store, which is the fail-open this check exists to remove.
scopes=$(printf '%s' "$rigs_raw" \
    | jq -r '.rigs[]? | select((.path // "") != "")
             | [((.name // "") | gsub("[[:cntrl:]]"; " ")), .path]
             | join("\u001f")' 2>/dev/null)

if [ -z "$scopes" ]; then
    echo "cannot determine whether any finalized molecule is still offering steps"
    echo "\`gc rig list --json\` listed no rig paths; the listing shape changed or the output is corrupt."
    exit 1
fi

while IFS=$'\037' read -r rig_name rig_path; do
    [ -n "$rig_path" ] || continue
    label="${rig_name:-<city>}"
    db="$rig_path/.beads"

    steps_raw=$(run_bounded bd list --db "$db" \
        --status open --has-metadata-key gc.root_bead_id \
        --json --limit 0 2>/dev/null)
    steps_rc=$?

    if [ "$steps_rc" -ne 0 ]; then
        warnings+=("$label: could not list open step beads in $db (rc=$steps_rc) — this store was NOT checked")
        continue
    fi

    # An empty store answers `[]`; an empty STRING means the probe produced
    # nothing at all, which is not the same thing and is not a pass.
    if [ -z "$steps_raw" ]; then
        warnings+=("$label: \`bd list\` over $db returned no output — this store was NOT checked")
        continue
    fi

    steps=$(printf '%s' "$steps_raw" | strip_ctl)

    root_ids=$(printf '%s' "$steps" | jq -r '
        [ .[]? | (.metadata["gc.root_bead_id"] // "" | tostring)
                 | sub("^[[:space:]]+"; "") | sub("[[:space:]]+$"; "")
                 | select(. != "") ]
        | unique | .[]' 2>/dev/null)
    root_rc=$?

    if [ "$root_rc" -ne 0 ]; then
        warnings+=("$label: open-step listing from $db could not be parsed — this store was NOT checked")
        continue
    fi

    [ -n "$root_ids" ] || continue

    # Batched root resolution. A chunk that fails to READ aborts the whole
    # store: a partial root map would silently reclassify every step under a
    # missing root as "cross-store, not judged", which is exactly the fail-open
    # this check exists to remove.
    roots_json='[]'
    chunk_failed=""
    chunk=()

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
        # `bd show` answers an ARRAY when at least one id resolves, but an
        # OBJECT — {"error":"no issues found matching the provided IDs"} — when
        # NONE of them does, at rc=0 either way. Adding an object to an array is
        # a jq type error, so taking that shape as corruption would warn "store
        # NOT checked" for the ordinary case of a chunk made entirely of
        # cross-store roots, and skip every real finding in that store with it.
        # An object contributes nothing; its ids then surface as unresolved-root
        # notes, which is what they are. Anything that is neither shape is still
        # corruption and still fails the store.
        merged=$(printf '%s' "$out" | jq -c --argjson a "$roots_json" '
            if type == "array" then $a + .
            elif type == "object" then $a
            else error("unexpected root payload") end' 2>/dev/null)
        if [ -z "$merged" ]; then
            chunk_failed="unparseable root payload"
            return 1
        fi
        roots_json="$merged"
        chunk=()
        return 0
    }

    while IFS= read -r rid; do
        [ -n "$rid" ] || continue
        chunk+=("$rid")
        if [ "${#chunk[@]}" -ge "$CHUNK" ]; then
            flush_chunk || break
        fi
    done <<< "$root_ids"
    [ -n "$chunk_failed" ] || flush_chunk || true

    if [ -n "$chunk_failed" ]; then
        warnings+=("$label: could not resolve molecule roots in $db ($chunk_failed) — this store was NOT checked")
        continue
    fi

    # --- findings, grouped per (root, class) --------------------------------
    # One line per molecule per shape, not one per step: a molecule that
    # finalized around seven open steps is ONE defect, and seven lines of it
    # would bury the single-step reopen loop that is the more urgent shape.
    rows=$(printf '%s' "$steps" | jq -r --argjson roots "$roots_json" '
        ($roots | map(select(type == "object" and ((.id // "") | tostring) != ""))
                | map({key: (.id | tostring), value: .}) | from_entries) as $R
        | [ .[]?
            | . as $s
            | ((($s.metadata["gc.root_bead_id"] // "") | tostring)
               | sub("^[[:space:]]+"; "") | sub("[[:space:]]+$"; "")) as $rid
            | select($rid != "")
            | ($R[$rid] // null) as $root
            | select($root != null and ((($root.status // "") | tostring)) == "closed")
            | { rid: $rid,
                closed_at: (($root.closed_at // "") | tostring),
                sid: ((($s.id // "?") | tostring) | gsub("[[:cntrl:]]"; " ")),
                cls: (if ((($s.metadata["gc.outcome"] // "") | tostring)
                          | sub("^[[:space:]]+"; "") | sub("[[:space:]]+$"; "")) != ""
                      then "reopened" else "stranded" end) } ]
        | group_by(.rid + "\u001f" + .cls)
        | .[]
        | [ .[0].cls, .[0].rid, .[0].closed_at,
            (length | tostring),
            ([.[].sid] | sort | join(", ")) ]
        | join("\u001f")' 2>/dev/null)
    rows_rc=$?

    if [ "$rows_rc" -ne 0 ]; then
        warnings+=("$label: open-step/root join over $db could not be computed — this store was NOT checked")
        continue
    fi

    # Steps whose root resolved nowhere in this store. A cross-store root is
    # legitimate, so this is a note; but it is REPORTED, because a root that
    # simply does not exist any more looks identical from here.
    unresolved=$(printf '%s' "$steps" | jq -r --argjson roots "$roots_json" '
        ($roots | map(select(type == "object" and ((.id // "") | tostring) != ""))
                | map({key: (.id | tostring), value: .}) | from_entries) as $R
        | [ .[]?
            | . as $s
            | ((($s.metadata["gc.root_bead_id"] // "") | tostring)
               | sub("^[[:space:]]+"; "") | sub("[[:space:]]+$"; "")) as $rid
            | select($rid != "")
            | select($R[$rid] == null)
            | { rid: $rid,
                ref: (((($s.metadata["gc.root_store_ref"] // "") | tostring)) | gsub("[[:cntrl:]]"; " ")),
                sid: ((($s.id // "?") | tostring) | gsub("[[:cntrl:]]"; " ")) } ]
        | group_by(.rid)
        | .[]
        | [ .[0].rid, .[0].ref, ([.[].sid] | sort | join(", ")) ]
        | join("\u001f")' 2>/dev/null)

    if [ -n "$unresolved" ]; then
        while IFS=$'\037' read -r u_rid u_ref u_sids; do
            [ -n "$u_rid" ] || continue
            notes+=("$label: open step(s) $u_sids name molecule root $u_rid, which does not resolve in $db (gc.root_store_ref=${u_ref:-<unset>}) — a cross-store root is legitimate, a deleted one is not; reported, not judged")
        done <<< "$unresolved"
    fi

    [ -n "$rows" ] || continue

    while IFS=$'\037' read -r class rid closed_at count sids; do
        [ -n "$class" ] || continue

        # Grace window. Finalize closes the root a few seconds BEFORE the
        # terminal step's own close lands, so a molecule caught mid-finalize is
        # normal and must not flap the check red. An unreadable or absent
        # timestamp does NOT buy that benefit of the doubt.
        age_note=""
        if [ -n "$closed_at" ] && [ "$NOW" != "0" ]; then
            if closed_epoch=$(epoch_of "$closed_at"); then
                age=$(( NOW - closed_epoch ))
                if [ "$age" -lt "$GRACE" ] && [ "$age" -ge 0 ]; then
                    notes+=("$label: molecule $rid closed ${age}s ago and still has $count open step(s) ($sids) — within the ${GRACE}s settle window, so this is finalize in progress rather than a strand")
                    continue
                fi
            else
                age_note=" (root closed_at=\"$closed_at\" could not be parsed, so the settle window was not applied)"
            fi
        elif [ -z "$closed_at" ]; then
            age_note=" (root carries no closed_at, so the settle window was not applied)"
        fi

        case "$class" in
            reopened)
                errors+=("$label: molecule $rid is CLOSED (closed_at=${closed_at:-<unset>}) yet $count of its step(s) are open AND already carry gc.outcome — $sids. These completed and were RESET afterwards; the pool re-offers them and each pass re-executes the step against a dead molecule, then re-stamps a closed root. Self-perpetuating: the reopen fires on the teardown of the session that just closed the step.$age_note")
                ;;
            *)
                errors+=("$label: molecule $rid is CLOSED (closed_at=${closed_at:-<unset>}) yet $count of its step(s) never closed — $sids. The molecule finalized around them; nothing downstream can consume another pass, but the pool can still offer them.$age_note")
                ;;
        esac
    done <<< "$rows"
done <<< "$scopes"

if [ "${#errors[@]}" -ne 0 ]; then
    echo "finalized molecules still offering steps: ${#errors[@]} molecule(s)"
    print_lines "${errors[@]}"
    print_lines "${warnings[@]+"${warnings[@]}"}" "${notes[@]+"${notes[@]}"}"
    echo ""
    echo "Each of these is an open step bead under a molecule whose root already closed. A finalized molecule has no consumer for another step pass, but \`gc hook --claim\` does not gate on the root's state and a step is offer-able through the ROOT's route even with a blank gc.routed_to — so the pool hands it out and the step re-executes. Close the open steps (verify every DOWNSTREAM step is already closed first, or the close readies a step and mints duplicate work), and clear the assignee in a SEPARATE write so the bead leaves the by-assignee release enumerations. The durable gate belongs in the gc binary; the narrowed search — four write sites acquitted at file:line and one earlier acquittal overturned — is in specs/tk-ciuad/finalized-molecule-step-reoffer.md."
    exit 2
fi

if [ "${#warnings[@]}" -ne 0 ]; then
    echo "finalized-molecule step offers partially determined"
    print_lines "${warnings[@]}"
    print_lines "${notes[@]+"${notes[@]}"}"
    exit 1
fi

echo "OK: no open step bead sits under a closed molecule root"
print_lines "${notes[@]+"${notes[@]}"}"
exit 0
