#!/usr/bin/env bash
# gc-bead-host.sh — spawn-or-resume a bead-host and maintain the durable
# bead<->session binding. Phase 1 of the Bead-Universe Operating Model
# (epic tk-q4xaj; bead tk-husu6; design Key Components 1-2).
#
# A bead-host is the resident LLM for one work bead (agents/bead-host),
# aliased to the bead id and run in resume mode. This is the "thin sugar"
# the design's Interface table names `gc bead-host <id>`: it creates the
# host (or resumes an existing one) and writes the durable link
# atomically on host creation.
#
# THE BINDING (metadata-only; no schema migration):
#
#   reverse link (source of truth) — on the SESSION bead:
#       hosts_bead = <work-bead-id>
#   forward cache (optional, O(1) accelerator) — on the WORK bead:
#       host_session       = <session-bead-id>       (stable; survives drain)
#       host_session_name  = <session_name>          (the wake handle)
#       host_session_epoch = <continuation_epoch>    (incarnation marker)
#   grounding (the assigned-work wake reason; tk-z130v.3) — on the WORK bead:
#       assignee           = <session_name>          (revives the host after an
#                                                      involuntary drain)
#   lineage (the 1:0..N / transcript-replay hook) — on the WORK bead:
#       gc.session_lineage = <JSON array of {session,name,epoch,at}>
#
# Keyed on the STABLE session identity (session bead id + session_name +
# continuation_epoch), never the ephemeral tmux name — the tmux name goes
# stale on drain, the bead id / session_name / epoch do not. continuation_
# epoch stays constant across resume-mode wakes (generation bumps every
# wake); a change in epoch means the conversation lineage was reset.
#
# REVERSE SEARCH CAVEAT (see specs/tk-husu6/binding-report.md §"Reverse
# search"): session beads (issue_type=session, HQ `lx` ledger) are
# addressable by id (`gc bd show`/`update <id>`) but are NOT returned by
# `gc bd list --metadata-field` — `bd list` filters the session type out.
# So the design's "ListByMetadata hosts_bead=<bead>" has no direct CLI
# surface; `resolve` realizes the reverse search by enumerating
# `gc session list` and confirming each candidate's hosts_bead by id.
# tk-3gga1 tracks adding a native `gc session list --metadata-field`.
#
# Atomicity: bd has no cross-bead transaction. `link` writes the reverse
# (source-of-truth) link FIRST, then the forward cache, then lineage, and
# every write is idempotent — a partial failure leaves the source of truth
# intact and the whole op is safe to re-run.
#
# Side effects: `up`/`link` mutate bead metadata AND ground the work bead
# (assignee=session_name), `unlink` clears the links and ungrounds — but only
# its OWN grounding (a newer non-host assignee is preserved), `backfill` grounds
# every already-linked host in one pass (skipping any bead a non-host owner
# already holds), and `up` creates or wakes a live session. `resolve`/`lineage`
# are read-only.

set -euo pipefail

PROG="${0##*/}"

log()  { printf '%s\n' "$*" >&2; }
die()  { printf '%s: %s\n' "$PROG" "$*" >&2; exit 1; }

usage() {
    cat <<EOF
Usage: $PROG <command> [args]
       $PROG <bead-id>                  Shorthand for '$PROG up <bead-id>'.

Commands:
  up <bead-id>                         Spawn-or-resume the bead's host and write
                                       the durable dual-link (the default verb).
  resolve <bead-id>                    Print the bead's host session(s). Read-only.
  link <bead-id> <session-bead-id> [name] [epoch]
                                       Write the dual-link, ground the work bead
                                       (assignee=session_name), + append lineage.
                                       The atomic binding step (used by 'up';
                                       exposed for fixtures and recovery). Idempotent.
  unlink <bead-id> [session-bead-id]   Remove the links + unground the work bead
                                       (clear its assignee) so it can be stopped.
                                       Clears the assignee ONLY while it is still
                                       the host's own session name — a newer
                                       non-host owner is preserved.
  backfill                             Ground every already-linked host in one
                                       pass (set assignee=session_name from the
                                       reverse link). One-time migration for hosts
                                       linked before grounding shipped; new/resumed
                                       hosts ground automatically via 'up'. Skips a
                                       bead already assigned to a non-host owner.
                                       Idempotent.
  lineage <bead-id>                    Print the work bead's host lineage. Read-only.
  help                                 Show this help.

A bead-host is agents/bead-host run in resume mode, aliased to the bead id.
See specs/tk-husu6/binding-report.md for the full contract and the operator
confirmatory checklist.
EOF
}

bead_json() {
    # bead_json <bead-id> -> the bead object (.[0]) or empty on miss.
    gc bd show "$1" --json 2>/dev/null | jq -c '.[0] // empty' 2>/dev/null || true
}

bead_exists() {
    [ -n "$(bead_json "$1")" ]
}

meta_get() {
    # meta_get <bead-id> <key> -> value or empty.
    bead_json "$1" | jq -r --arg k "$2" '.metadata[$k] // empty' 2>/dev/null || true
}

require_bead() {
    bead_exists "$1" || die "bead '$1' not found (looked up via 'gc bd show')"
}

# host_title <work> — the scannable bead-host session title,
# "<bead-id> · <bead-title>", capped to ~60 display chars so the prefix+S
# picker shows which bead a host belongs to instead of the generic
# "gc-toolkit.bead-host". jq slices by Unicode codepoint (never splits a
# multibyte char); falls back to the bare id when the bead has no title.
host_title() {
    local work="$1" t
    t="$(bead_json "$work" | jq -r --arg id "$work" '
        (.title // "") as $bt
        | (if ($bt | length) > 0 then ($id + " · " + $bt) else $id end)
        | .[0:60]' 2>/dev/null || true)"
    [ -n "$t" ] || t="$work"
    printf '%s' "$t"
}

# ---- host liveness (the dead-corpse vocabulary; tk-8v5j0) -------------------

# is_dead_state <state> — the bead-host lifecycle states that mean a corpse
# (NOT resumable). Centralized so resolve and up agree on what "dead" is. A
# bead-host's lifecycle is carried in the session bead's metadata.state:
# awake/asleep/active are live & resumable; a never-spawned create lands in
# failed-create (and closes the bead).
is_dead_state() {
    case "$1" in
        failed-create|failed|closed|terminated|dead|aborted|gone|errored) return 0 ;;
        *) return 1 ;;
    esac
}

# session_is_dead <session-bead-id> — succeeds (0) when the session bead is a
# dead/failed/closed corpse that must NOT be reported as a resumable host. Two
# independent signals: a failed create CLOSES the bead (status=closed), and the
# lifecycle metadata.state lands in a dead state. Either ⇒ dead; a vanished
# bead (no object) is also dead. resolve uses this so a stale forward-cache
# pointer at a failed-create corpse resolves as "no host" and `up` recreates.
session_is_dead() {
    local obj status state
    obj="$(bead_json "$1")"
    [ -n "$obj" ] || return 0
    status="$(printf '%s' "$obj" | jq -r '.status // empty' 2>/dev/null || true)"
    if [ "$status" = "closed" ]; then return 0; fi
    state="$(printf '%s' "$obj" | jq -r '.metadata.state // empty' 2>/dev/null || true)"
    is_dead_state "$state"
}

# wait_until_registered <session-bead-id> — block (bounded) until a freshly
# created or woken host actually registers, so a caller that switches/attaches
# into the tmux session does not race a slow cold start (tk-8v5j0 acceptance
# #3). `gc session new --no-attach` returns at state=start-pending; the runtime
# and tmux session register a moment later (observed 0–60s+). Returns:
#   0  a live state was reached, OR the budget elapsed (best-effort proceed —
#      the switch helper keeps its own poll budget as a backstop)
#   1  the host went to a dead/failed-create state — a HARD failure the caller
#      must surface instead of reporting a phantom "up"
# Budget is GC_BEAD_HOST_UP_TIMEOUT seconds (default 60).
wait_until_registered() {
    local sid="$1" budget="${GC_BEAD_HOST_UP_TIMEOUT:-60}" waited=0 obj status state
    case "$budget" in ''|*[!0-9]*) budget=60 ;; esac
    while [ "$waited" -lt "$budget" ]; do
        obj="$(bead_json "$sid")"
        if [ -n "$obj" ]; then
            status="$(printf '%s' "$obj" | jq -r '.status // empty' 2>/dev/null || true)"
            state="$(printf '%s' "$obj" | jq -r '.metadata.state // empty' 2>/dev/null || true)"
            if [ "$status" = "closed" ] || is_dead_state "$state"; then return 1; fi
            case "$state" in awake|active|asleep|running|ready|resumed|live) return 0 ;; esac
        fi
        sleep 1
        waited=$((waited + 1))
    done
    log "warning: bead-host $sid did not register within ${budget}s — proceeding (caller's switch keeps polling)"
    return 0
}

# ---- link / unlink / lineage (pure metadata; testable offline) -------------

iso_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

cmd_link() {
    local work="${1:-}" sess="${2:-}" name="${3:-}" epoch="${4:-}"
    [ -n "$work" ] && [ -n "$sess" ] || { usage; die "link needs <bead-id> <session-bead-id>"; }
    require_bead "$work"
    require_bead "$sess"

    # Default name/epoch from the session bead when not supplied.
    [ -n "$name" ]  || name="$(meta_get "$sess" session_name)"
    [ -n "$epoch" ] || epoch="$(meta_get "$sess" continuation_epoch)"
    [ -n "$epoch" ] || epoch="1"

    # 1) Reverse link FIRST — the source of truth, on the session bead.
    gc bd update "$sess" --set-metadata "hosts_bead=$work" >/dev/null

    # 2) Forward cache — on the work bead.
    gc bd update "$work" \
        --set-metadata "host_session=$sess" \
        --set-metadata "host_session_name=$name" \
        --set-metadata "host_session_epoch=$epoch" >/dev/null

    # 2b) Ground the host (tk-z130v.3): set the work bead's `assignee` to the
    # host's session NAME. That assignment is the "assigned-work wake reason" —
    # gascity core's compute_awake_set revives a session that is the assignee of
    # a bead with awake-demand (in_progress, or open+Ready) with NO Drained gate,
    # so a bead-host brought back by the reconciler after an INVOLUNTARY
    # config-drift drain keeps its conversation instead of dying. This is the
    # grounding, not any fork exemption.
    #
    # Use the session NAME, never the session bead id: a bead id flips
    # `gc bd update --assignee` to the HQ store ("no issue found"), and the
    # awake-set matches on the name. `assignee=session_name` is also an already
    # established convention (see assets/scripts/gc-helm.sh "a child bead's
    # assignee is its OWNING session — the session_name"), and the witness
    # liveness map keys on session_name, so a drained/asleep grounded host still
    # resolves live, not orphaned (formulas/mol-witness-patrol.toml
    # recover-orphaned-beads).
    #
    # Guard on a non-empty name: an empty --assignee would CLEAR the assignee and
    # unground the host. Idempotent — a re-link writes the same value, so
    # re-binding the same session does not thrash the assignment.
    [ -n "$name" ] && gc bd update "$work" --assignee "$name" >/dev/null

    # 3) Lineage append (idempotent on session+epoch) — on the work bead.
    local lineage entry
    lineage="$(meta_get "$work" gc.session_lineage)"
    [ -n "$lineage" ] || lineage="[]"
    entry="$(jq -cn --arg s "$sess" --arg n "$name" --arg e "$epoch" --arg at "$(iso_now)" \
        '{session:$s, name:$n, epoch:($e|tonumber? // $e), at:$at}')"
    lineage="$(printf '%s' "$lineage" | jq -c --argjson e "$entry" \
        'if any(.[]?; .session==$e.session and (.epoch|tostring)==($e.epoch|tostring)) then . else . + [$e] end' \
        2>/dev/null || printf '[%s]' "$entry")"
    gc bd update "$work" --set-metadata "gc.session_lineage=$lineage" >/dev/null

    log "linked: $work <-> $sess (name=$name epoch=$epoch)"
    printf '%s\n' "$sess"
}

# candidate_session_ids <work> — print the bead id of every session bead that
# MIGHT host <work>, for unlink to confirm-and-clear. The forward host_session
# cache is only an accelerator and may be absent (a partial link, a manually
# cleared cache, or the documented "perf cache only" case), so unlink must NOT
# rely on it to find the session — it enumerates the source-of-truth reverse
# link instead. Two surfaces cover the REVERSE SEARCH CAVEAT (session beads are
# not uniformly bd-listable):
#   (1) `gc bd list --metadata-field hosts_bead=<work>` — listable beads only
#       (real session beads are filtered out by `gc bd list`); covers the
#       design's ListByMetadata mechanism and the fixture's stand-in beads.
#       These are already a confirmed metadata match.
#   (2) `gc session list` — real session beads, prefiltered by the bead-host
#       template or an alias match (a cheap candidate filter, never proof of
#       hosting; the caller confirms hosts_bead==<work> by id).
candidate_session_ids() {
    local work="$1"
    gc bd list --metadata-field "hosts_bead=$work" --json 2>/dev/null \
        | jq -r '.[]?.id // empty' 2>/dev/null || true
    gc session list --state all --json 2>/dev/null \
        | jq -r --arg w "$work" \
            '(.sessions // .)[]? | select((.template // "" | test("bead-host")) or (.alias // "") == $w) | .id' \
        2>/dev/null || true
}

cmd_unlink() {
    local work="${1:-}" sess="${2:-}"
    [ -n "$work" ] || { usage; die "unlink needs <bead-id>"; }
    require_bead "$work"

    # Snapshot the work bead ONCE, before any clear, for three fields:
    #   - host_session (forward cache): names one session to unbind and may be
    #     the ONLY pointer left if that session dropped out of `gc session list`
    #     and isn't bd-listable.
    #   - host_session_name (one grounding-owner signal, the forward cache) + the
    #     CURRENT assignee: read up front so ungrounding can be made CONDITIONAL —
    #     the metadata clear below wipes host_session_name, so it must be captured
    #     first. The reverse link and the explicit session arg supply the other
    #     grounding-owner names (see the decision below).
    local obj cached host_name cur_assignee
    obj="$(bead_json "$work")"
    cached="$(printf '%s' "$obj" | jq -r '.metadata.host_session // empty' 2>/dev/null || true)"
    host_name="$(printf '%s' "$obj" | jq -r '.metadata.host_session_name // empty' 2>/dev/null || true)"
    cur_assignee="$(printf '%s' "$obj" | jq -r '.assignee // empty' 2>/dev/null || true)"

    # Decide whether the work bead's `assignee` is OUR grounding (clear it on
    # teardown) or a real non-host owner (preserve it). The grounding set
    # `assignee` to a host's session NAME; whose name that is must NOT be decided
    # from the forward cache `host_session_name` alone. That cache is an OPTIONAL
    # accelerator (see the binding header) and may be absent — a partial link, a
    # manually cleared cache, the "perf cache only" case. Deciding from it alone
    # left `assignee=<session_name>` behind on the no-forward-cache path, so the
    # host kept its assigned-work wake reason and revived ~20s after every drain
    # (tk-v369i). Derive the grounding-owner name from the authoritative sources
    # instead: the reverse link (source of truth, on the session bead, matched in
    # the clear loop below) and the explicit session arg (the caller names the
    # exact host being torn down); the forward cache, when present, is just one
    # more signal.
    #
    # Ours to clear iff the current assignee equals a grounding-owner name. A newer
    # NON-host assignee — a real agent/operator that took the bead after it was
    # grounded — matches none of them and is PRESERVED; blindly clearing it would
    # strip a live assignment and strand that owner's work. This is exactly the
    # contract the witness filter keys on (host-bead-skip.test.sh): assignee == a
    # host's session_name ⇒ grounded (ours to clear); otherwise ⇒ a real assignee
    # (keep).
    local is_grounding=""
    if [ -n "$cur_assignee" ] && [ -n "$host_name" ] && [ "$cur_assignee" = "$host_name" ]; then
        is_grounding=1   # forward cache (optional) confirms it — the fast path
    fi

    # Clear the reverse link — the SOURCE OF TRUTH — on every session bead bound
    # to this work bead, and match the assignee against each bound host's
    # session_name as we go. Do NOT depend on the forward cache to LOCATE the
    # reverse link either: if the cache is missing, a left-behind hosts_bead would
    # let `resolve` keep returning the host and `up` re-wake it. Candidates,
    # deduped: the explicit session arg, the cache we read up front, and the
    # authoritative reverse search. Every candidate is confirmed by id (it STILL
    # points here) before we clear it or trust its name, so a stale cache or shared
    # alias can neither unbind another work's host nor authorize clearing a real
    # assignee.
    local candidates seen=" " cleared="" s="" sn=""
    candidates="$(printf '%s\n' "$sess" "$cached"; candidate_session_ids "$work")"
    while IFS= read -r s; do
        [ -n "$s" ] || continue
        case "$seen" in *" $s "*) continue ;; esac
        seen="$seen$s "
        [ "$(meta_get "$s" hosts_bead)" = "$work" ] || continue
        if [ -z "$is_grounding" ] && [ -n "$cur_assignee" ]; then
            sn="$(meta_get "$s" session_name)"
            if [ -n "$sn" ] && [ "$cur_assignee" = "$sn" ]; then is_grounding=1; fi
        fi
        gc bd update "$s" --unset-metadata hosts_bead >/dev/null 2>&1 || true
        cleared="${cleared:+$cleared,}$s"
    done <<<"$candidates"

    # The explicit session arg names the exact host being torn down (e.g. `up`'s
    # stale-binding cleanup passes the dead session id). Trust its session_name as
    # a grounding-owner name even when the reverse link was already cleared, so the
    # partial-teardown case still ungrounds. meta_get is empty for a dead/unknown
    # session bead — a safe no-op.
    if [ -z "$is_grounding" ] && [ -n "$cur_assignee" ] && [ -n "$sess" ]; then
        sn="$(meta_get "$sess" session_name)"
        if [ -n "$sn" ] && [ "$cur_assignee" = "$sn" ]; then is_grounding=1; fi
    fi

    # Clear the forward cache on the work bead — and unground IN THE SAME WRITE
    # when the assignee is ours. Teardown must clear the wake reason (`--assignee=`
    # empty, the same clear gc-helm.sh's `takeaway --release` performs) so the host
    # loses its assigned-work wake reason and can actually be stopped — but only
    # the wake reason WE set.
    if [ -n "$is_grounding" ]; then
        gc bd update "$work" \
            --assignee= \
            --unset-metadata host_session \
            --unset-metadata host_session_name \
            --unset-metadata host_session_epoch >/dev/null 2>&1 || true
    else
        gc bd update "$work" \
            --unset-metadata host_session \
            --unset-metadata host_session_name \
            --unset-metadata host_session_epoch >/dev/null 2>&1 || true
        if [ -n "$cur_assignee" ]; then
            log "unlink: preserving non-host assignee '$cur_assignee' on $work (grounded name '${host_name:-<none>}')"
        fi
    fi

    log "unlinked: $work (cleared -> ${cleared:-<none>}); lineage preserved"
}

cmd_lineage() {
    local work="${1:-}"
    [ -n "$work" ] || { usage; die "lineage needs <bead-id>"; }
    require_bead "$work"
    local lineage; lineage="$(meta_get "$work" gc.session_lineage)"
    [ -n "$lineage" ] || lineage="[]"
    printf '%s\n' "$lineage" | jq '.' 2>/dev/null || printf '%s\n' "$lineage"
}

# ---- backfill (one-time grounding migration) -------------------------------

# Ground every host that was linked BEFORE grounding shipped: for each hosted
# work bead, set its `assignee` to the host session's name (tk-z130v.3). New and
# resumed hosts ground automatically via cmd_link, so this only catches up the
# already-live ones — run once after deploy. It matters because the tk-z130v.4
# exemption drop is gated on all live hosts being grounded first. Idempotent:
# re-running writes the same assignee, so a second pass is a safe no-op-in-effect.
#
# Enumerate the reverse link (hosts_bead, on the SESSION bead) across BOTH
# surfaces, the same split as candidate_session_ids: listable beads via
# `gc bd list --has-metadata-key hosts_bead` (real session beads are filtered out
# of `bd list`) and real session beads via `gc session list` (bead-host
# template). For each, ground work=hosts_bead with the session's session_name —
# never the session bead id (a bead id flips `--assignee` to the HQ store). The
# hosts span rigs (bead-host scope is "city"), so pin each ground write to the
# work bead's OWN rig ledger (rig_db_for_bead) — the same rig-pinning gc-helm.sh
# uses — so a city-wide pass lands every assignee in the right ledger.

# rig_db_for_bead <bead-id> — the .beads dir of the rig owning the bead, keyed by
# id prefix (chars before the first '-'); empty if unresolved (then the write
# falls back to the ambient bd context). Mirrors gc-helm.sh's rig_path_for_bead.
# Cached — `gc rig list` runs at most once per process.
_RIGS_JSON=""
rig_db_for_bead() {
    [ -n "$_RIGS_JSON" ] || _RIGS_JSON="$(gc rig list --json 2>/dev/null \
        | jq -c '[.rigs[]? | {prefix, path}]' 2>/dev/null || printf '[]')"
    local path
    path="$(printf '%s' "$_RIGS_JSON" | jq -r --arg p "${1%%-*}" \
        '.[] | select(.prefix==$p) | .path' 2>/dev/null | head -n1)"
    [ -n "$path" ] && [ -d "$path/.beads" ] && printf '%s' "$path/.beads"
}

cmd_backfill() {
    local sids grounded=0 skipped=0 sid work name db cur
    sids="$( { gc bd list --has-metadata-key hosts_bead --json 2>/dev/null \
                   | jq -r '.[]?.id // empty' 2>/dev/null || true
               gc session list --state all --json 2>/dev/null \
                   | jq -r '(.sessions // .)[]? | select((.template // "") | test("bead-host")) | .id' \
                   2>/dev/null || true
             } | awk 'NF && !seen[$0]++' )"
    while IFS= read -r sid; do
        [ -n "$sid" ] || continue
        work="$(meta_get "$sid" hosts_bead)"; [ -n "$work" ] || continue
        name="$(meta_get "$sid" session_name)"; [ -n "$name" ] || continue
        db="$(rig_db_for_bead "$work")"
        # Preserve a non-host assignee. backfill grounds an UNGROUNDED host (empty
        # assignee) or re-affirms one already grounded to this host (assignee ==
        # name, idempotent). If the work bead is assigned to a DIFFERENT owner, a
        # real agent took it after linking — grounding would clobber that live
        # assignment (the same host_session_name != assignee case the witness
        # filter preserves, host-bead-skip.test.sh). Skip and log instead of
        # overwriting. Read the current assignee from the work bead's OWN rig
        # ledger (same --db pin as the ground write) so a city-wide pass reads the
        # right ledger cross-rig.
        # shellcheck disable=SC2086  # ${db:+--db "$db"} expands to 0 or 2 space-free fields
        cur="$(gc bd show "$work" ${db:+--db "$db"} --json 2>/dev/null | jq -r '.[0].assignee // empty' 2>/dev/null || true)"
        if [ -n "$cur" ] && [ "$cur" != "$name" ]; then
            log "skip: $work already assigned to '$cur' (not host '$name') — preserving non-host assignee"
            skipped=$((skipped + 1))
            continue
        fi
        # shellcheck disable=SC2086  # ${db:+--db "$db"} expands to 0 or 2 space-free fields
        if gc bd update "$work" ${db:+--db "$db"} --assignee "$name" >/dev/null 2>&1; then
            log "grounded: $work -> $name (host $sid)"
            grounded=$((grounded + 1))
        else
            log "skip: could not ground $work (host $sid)"
        fi
    done <<<"$sids"
    log "backfill: grounded $grounded host bead(s), preserved $skipped non-host assignee(s)"
    printf '%s\n' "$grounded"
}

# ---- resolve (reverse search; enumerate-and-confirm) -----------------------

# Reverse-resolve: given a work bead, find its host session(s).
#
# Fast path: the forward cache on the work bead (O(1)). Authoritative
# search: enumerate `gc session list` (the only CLI surface that lists
# session beads), PREFILTER the candidates cheaply (a bead-host template
# session, or any session aliased to the bead), then RESOLVE strictly by the
# source-of-truth reverse link, confirmed by id: a session hosts the bead
# iff its session bead carries hosts_bead == <bead>. Alias is a PREFILTER
# ONLY, never proof of hosting — a still-live session merely aliased to the
# bead (after `unlink`, or a foreign session sharing the alias) must NOT
# resolve. Prints one TSV row per host:
#   <session-bead-id>\t<session_name>\t<alias>\t<state>
cmd_resolve() {
    local work="${1:-}"
    [ -n "$work" ] || { usage; die "resolve needs <bead-id>"; }
    require_bead "$work"

    local found=0

    # Authoritative: enumerate sessions, confirm the reverse link by id.
    local rows
    rows="$(gc session list --state all --json 2>/dev/null \
        | jq -r '(.sessions // .)[]? | [.id, (.session_name // ""), (.alias // ""), (.state // ""), (.template // "")] | @tsv' \
        2>/dev/null || true)"
    if [ -n "$rows" ]; then
        while IFS=$'\t' read -r sid sname salias sstate stmpl; do
            [ -n "$sid" ] || continue
            # Prefilter (cheap): a bead-host template session, or any session
            # aliased to the bead. Alias here is ONLY a prefilter to bound the
            # per-session metadata reads below — never proof of hosting.
            case "$stmpl" in *bead-host*) : ;; *) [ "$salias" = "$work" ] || continue ;; esac
            # Resolve strictly by the source-of-truth reverse link, by id.
            # NOT `|| salias == work`: an alias-only match (a live session left
            # aliased after `unlink`, or a foreign session sharing the alias)
            # must not resolve — else `unlink` could never unbind a live host
            # and `up` would immediately re-wake it.
            [ "$(meta_get "$sid" hosts_bead)" = "$work" ] || continue
            printf '%s\t%s\t%s\t%s\n' "$sid" "$sname" "$salias" "$sstate"
            found=1
        done <<<"$rows"
    fi

    if [ "$found" -eq 0 ]; then
        # Fall back to the forward cache (e.g. host suspended out of the
        # session list, or a fixture using listable stand-in beads). Skip a
        # DEAD pointer (tk-8v5j0): a failed-create / closed corpse still carries
        # the reverse link, so without this guard resolve reports it as
        # resumable and `up` wake-masks it forever. A dead cache pointer must
        # resolve as "no host" so `up` creates fresh.
        local cached; cached="$(meta_get "$work" host_session)"
        if [ -n "$cached" ] && bead_exists "$cached" \
           && [ "$(meta_get "$cached" hosts_bead)" = "$work" ] \
           && ! session_is_dead "$cached"; then
            printf '%s\t%s\t%s\t%s\n' "$cached" \
                "$(meta_get "$cached" session_name)" \
                "$(meta_get "$cached" alias)" \
                "cached"
            found=1
        fi
    fi

    [ "$found" -eq 1 ] || { log "no host bound to $work"; return 1; }
}

# ---- up (spawn-or-resume + link) -------------------------------------------

# The live path: create the host if none exists, else wake the suspended
# one, then (re)write the binding. Must be run where `gc session new
# bead-host` resolves (the bead-host agent loaded into the running city).
cmd_up() {
    local work="${1:-}"
    [ -n "$work" ] || { usage; die "up needs <bead-id>"; }
    require_bead "$work"

    # A scannable session title, set on BOTH spawn and resume, so the
    # prefix+S picker and the Helm name the bead instead of the
    # generic "gc-toolkit.bead-host". Best-effort: a rename failure is never
    # fatal to spawn-or-resume.
    local htitle; htitle="$(host_title "$work")"

    # Already bound + a live/suspended session? Resume it — but VERIFY the
    # resume actually took. The original code masked the wake result
    # (`gc session wake ... || true`), so a dead/failed-create corpse that
    # slipped past resolve was reported as a phantom "up" and could never come
    # up (tk-8v5j0). Wake-and-verify: a failed wake — or a host that never
    # registers — means the binding is STALE. Unlink it and fall through to the
    # create path for a fresh host instead of masking the failure.
    local existing
    existing="$(cmd_resolve "$work" 2>/dev/null | head -1 || true)"
    if [ -n "$existing" ]; then
        local sid sname salias sstate
        IFS=$'\t' read -r sid sname salias sstate <<<"$existing"
        log "host exists for $work: session=$sid state=$sstate — waking/resuming"
        if gc session wake "${salias:-$work}" >/dev/null 2>&1 && wait_until_registered "$sid"; then
            gc session rename "$sid" "$htitle" >/dev/null 2>&1 || true
            cmd_link "$work" "$sid" "$sname" "$(meta_get "$sid" continuation_epoch)" >/dev/null
            printf '%s\n' "$sid"
            return 0
        fi
        log "host for $work did not resume (session=$sid state=${sstate:-?}) — stale binding; unlinking and creating fresh"
        cmd_unlink "$work" "$sid" >/dev/null 2>&1 || true
        # fall through to the create path below.
    fi

    # No host — create one aliased to the bead (alias=bead-id enforces 1:1),
    # titled with the bead so the picker is scannable.
    log "creating bead-host for $work"
    local out sid sname
    out="$(gc session new bead-host --alias "$work" --title "$htitle" --no-attach --json 2>/dev/null)" \
        || die "gc session new bead-host failed (is the bead-host agent loaded? run 'gc reload')"
    sid="$(printf '%s' "$out"   | jq -r '.session_id // empty')"
    sname="$(printf '%s' "$out" | jq -r '.session_name // empty')"
    [ -n "$sid" ] || die "gc session new returned no session_id: $out"

    # `gc session new --no-attach` returns at state=start-pending; the runtime
    # and the host's tmux session register a moment later. Block (bounded) until
    # it registers so the caller's switch/attach does not race the cold start
    # (tk-8v5j0 acceptance #3). A create that flips to failed-create is a hard
    # error — surface it, never report a phantom "up".
    if ! wait_until_registered "$sid"; then
        die "bead-host for $work failed to start (session $sid went failed-create/dead)"
    fi

    cmd_link "$work" "$sid" "$sname" "$(meta_get "$sid" continuation_epoch)" >/dev/null
    log "bead-host up: $work -> session $sid ($sname)"
    printf '%s\n' "$sid"
}

# ---- dispatch --------------------------------------------------------------

main() {
    local cmd="${1:-help}"
    case "$cmd" in
        up)       shift; cmd_up "$@" ;;
        resolve)  shift; cmd_resolve "$@" ;;
        link)     shift; cmd_link "$@" ;;
        unlink)   shift; cmd_unlink "$@" ;;
        backfill) shift; cmd_backfill "$@" ;;
        lineage)  shift; cmd_lineage "$@" ;;
        -h|--help|help|'') usage ;;
        -*) usage; die "unknown option: $cmd" ;;
        # Default verb: `$PROG <bead-id>` == `$PROG up <bead-id>` (the design's
        # Interface table names the convenience `gc bead-host <id>`). A bare
        # first arg is treated as a bead id — do NOT shift, so it reaches cmd_up
        # as $1; a non-bead typo surfaces as cmd_up's 'bead not found'.
        *) cmd_up "$@" ;;
    esac
}

main "$@"
