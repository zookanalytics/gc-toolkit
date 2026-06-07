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
# Side effects: `up`/`link`/`unlink` mutate bead metadata (and `up` creates
# or wakes a live session). `resolve`/`lineage` are read-only.

set -euo pipefail

PROG="${0##*/}"

log()  { printf '%s\n' "$*" >&2; }
die()  { printf '%s: %s\n' "$PROG" "$*" >&2; exit 1; }

usage() {
    cat <<EOF
Usage: $PROG <command> [args]

Commands:
  up <bead-id>                         Spawn-or-resume the bead's host and write
                                       the durable dual-link (the default verb).
  resolve <bead-id>                    Print the bead's host session(s). Read-only.
  link <bead-id> <session-bead-id> [name] [epoch]
                                       Write the dual-link + append lineage. The
                                       atomic binding step (used by 'up'; exposed
                                       for fixtures and recovery). Idempotent.
  unlink <bead-id> [session-bead-id]   Remove the links (cleanup / re-bind).
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

cmd_unlink() {
    local work="${1:-}" sess="${2:-}"
    [ -n "$work" ] || { usage; die "unlink needs <bead-id>"; }
    require_bead "$work"
    [ -n "$sess" ] || sess="$(meta_get "$work" host_session)"

    gc bd update "$work" \
        --unset-metadata host_session \
        --unset-metadata host_session_name \
        --unset-metadata host_session_epoch >/dev/null 2>&1 || true
    if [ -n "$sess" ] && bead_exists "$sess"; then
        gc bd update "$sess" --unset-metadata hosts_bead >/dev/null 2>&1 || true
    fi
    log "unlinked: $work (was -> ${sess:-<none>}); lineage preserved"
}

cmd_lineage() {
    local work="${1:-}"
    [ -n "$work" ] || { usage; die "lineage needs <bead-id>"; }
    require_bead "$work"
    local lineage; lineage="$(meta_get "$work" gc.session_lineage)"
    [ -n "$lineage" ] || lineage="[]"
    printf '%s\n' "$lineage" | jq '.' 2>/dev/null || printf '%s\n' "$lineage"
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
        # session list, or a fixture using listable stand-in beads).
        local cached; cached="$(meta_get "$work" host_session)"
        if [ -n "$cached" ] && bead_exists "$cached" && [ "$(meta_get "$cached" hosts_bead)" = "$work" ]; then
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

    # Already bound + a live/suspended session? Resume it.
    local existing
    existing="$(cmd_resolve "$work" 2>/dev/null | head -1 || true)"
    if [ -n "$existing" ]; then
        local sid sname salias sstate
        IFS=$'\t' read -r sid sname salias sstate <<<"$existing"
        log "host exists for $work: session=$sid state=$sstate — waking/resuming"
        gc session wake "${salias:-$work}" >/dev/null 2>&1 || true
        cmd_link "$work" "$sid" "$sname" "$(meta_get "$sid" continuation_epoch)" >/dev/null
        printf '%s\n' "$sid"
        return 0
    fi

    # No host — create one aliased to the bead (alias=bead-id enforces 1:1).
    log "creating bead-host for $work"
    local out sid sname
    out="$(gc session new bead-host --alias "$work" --no-attach --json 2>/dev/null)" \
        || die "gc session new bead-host failed (is the bead-host agent loaded? run 'gc reload')"
    sid="$(printf '%s' "$out"   | jq -r '.session_id // empty')"
    sname="$(printf '%s' "$out" | jq -r '.session_name // empty')"
    [ -n "$sid" ] || die "gc session new returned no session_id: $out"

    cmd_link "$work" "$sid" "$sname" "$(meta_get "$sid" continuation_epoch)" >/dev/null
    log "bead-host up: $work -> session $sid ($sname)"
    printf '%s\n' "$sid"
}

# ---- dispatch --------------------------------------------------------------

main() {
    local cmd="${1:-help}"
    shift || true
    case "$cmd" in
        up)       cmd_up "$@" ;;
        resolve)  cmd_resolve "$@" ;;
        link)     cmd_link "$@" ;;
        unlink)   cmd_unlink "$@" ;;
        lineage)  cmd_lineage "$@" ;;
        -h|--help|help) usage ;;
        *) usage; die "unknown command: $cmd" ;;
    esac
}

main "$@"
