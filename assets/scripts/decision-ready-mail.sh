#!/usr/bin/env bash
# decision-ready-mail — mail human when a decision bead becomes ready
# for review (status=open, all blockers closed).
#
# Implements tk-f2wpu under the operator's 2026-05-15 spec on that bead:
#   - Channel: gc mail send <operator>; cockpit panel + nudge are out of
#     scope.
#   - Trigger: periodic doctor-style sweep (this script). The other
#     allowed option (bead-close lifecycle hook) requires modifying the
#     installed beads hooks, which `gc` rewrites — sweep is the simpler
#     and tested path.
#   - Recipient: bead owner, falling back to "human" when the owner field
#     does not resolve to a mailable identity. Today bead.owner is a
#     GitHub no-reply email (e.g. 275398848+zook-bot@users.noreply…) with
#     no mail-target mapping in this city, so every send currently lands
#     on the "human" inbox. Mapping owners → aliases can be added later
#     without touching this contract.
#   - Body: bead ID, title, latest closed child (the de-facto synthesis
#     artifact), and the full list of closed blocking dependencies.
#
# Idempotent across runs via metadata.gc.decision_notified=true on the
# decision bead. A reopened decision bead would re-notify only if that
# flag is cleared; clearing on reopen is deferred to a follow-up since
# the operator scope flagged reopen-handling as out of scope here.
#
# Coverage: HQ (city-level beads) + every rig. Mirrors the orphan-sweep
# fanout pattern — `bd ready` without --rig is HQ-scoped, so rigs must
# be walked explicitly.
set -euo pipefail

GC_BIN="${GC_BIN:-gc}"
LOG_PREFIX="decision-ready-mail"
# DRY_RUN=1 prints the recipient + subject + body that would be sent
# (and the metadata flag that would be set) without touching state.
# Useful for inspecting transition behavior before the order goes live.
DRY_RUN="${DRY_RUN:-0}"

# Force cwd to the city root so `gc bd ready` without --rig is
# unambiguously HQ-scoped. Otherwise the script picks up whichever rig
# the controller (or a manual invocation) happens to sit in, double-
# counting that rig's beads against the explicit --rig fanout below.
CITY="${GC_CITY:-}"
if [ -z "$CITY" ]; then
    CITY=$("$GC_BIN" rig list --json 2>/dev/null | jq -r '.city_path // ""' 2>/dev/null || true)
fi
if [ -n "$CITY" ] && [ -d "$CITY" ]; then
    cd "$CITY"
fi

# send_one <bead-id> <title> <owner> <closed-deps-tsv>
#
# closed-deps-tsv: tab-separated "id\ttitle\tclosed_at" rows (one per line),
# ordered most-recent-first by closed_at. Empty when the decision had no
# blockers (a "born-ready" decision).
send_one() {
    local bid="$1" title="$2" owner="$3" closed_tsv="$4"

    # Recipient: bead owner → mail target mapping is empty in this city,
    # so fall back to "human". When a mapping is added, this is the seam.
    local recipient="human"
    if [ -n "$owner" ] && [ "$owner" != "null" ]; then
        # Future: owner_to_alias "$owner" || recipient="human"
        :
    fi

    local subject body latest_id latest_title latest_at
    subject="Decision ready for review: ${bid} — ${title:0:60}"

    if [ -n "$closed_tsv" ]; then
        IFS=$'\t' read -r latest_id latest_title latest_at \
            <<<"$(printf '%s\n' "$closed_tsv" | head -1)"
        body=$(printf 'Decision bead %s has all blockers closed and is awaiting your review.\n\nTitle: %s\n\nLatest closed child (synthesis artifact): %s — %s (closed %s)\n\nClosed blockers:\n%s\n\nView: gc bd show %s\n' \
            "$bid" "$title" "$latest_id" "$latest_title" "$latest_at" \
            "$(printf '%s\n' "$closed_tsv" | awk -F'\t' '{printf "  - %s: %s\n", $1, $2}')" \
            "$bid")
    else
        body=$(printf 'Decision bead %s is open with no blockers and is awaiting your review.\n\nTitle: %s\n\n(No blocking dependencies were recorded against this decision.)\n\nView: gc bd show %s\n' \
            "$bid" "$title" "$bid")
    fi

    if [ "$DRY_RUN" = "1" ]; then
        printf '%s [DRY_RUN] would mail %s\n  subject: %s\n  body:\n%s\n  flag: %s gc.decision_notified=true\n' \
            "$LOG_PREFIX" "$recipient" "$subject" \
            "$(printf '%s\n' "$body" | sed 's/^/    /')" "$bid"
        return 0
    fi

    if ! "$GC_BIN" mail send "$recipient" -s "$subject" -m "$body" >/dev/null 2>&1; then
        echo "$LOG_PREFIX: mail send failed for $bid" >&2
        return 1
    fi

    # Mark the bead so subsequent ticks do not re-notify. `bd update`
    # auto-resolves the bead prefix to the right rig store.
    if ! "$GC_BIN" bd update "$bid" --set-metadata gc.decision_notified=true >/dev/null 2>&1; then
        echo "$LOG_PREFIX: bd update flag failed for $bid (mail already sent)" >&2
        return 1
    fi

    echo "$LOG_PREFIX: notified $bid"
    return 0
}

# process_scope <scope-flag>
# scope-flag is either "" (HQ) or "--rig <name>".
process_scope() {
    local scope_flag="$1"
    local ready_json
    # shellcheck disable=SC2086
    ready_json=$("$GC_BIN" bd ready -t decision $scope_flag --json 2>/dev/null || true)
    case "$ready_json" in ''|'[]') return 0 ;; esac

    # Stream bead ids that still need notification. jq filters out beads
    # already flagged so we skip a second `bd show` round-trip for them.
    local ids
    ids=$(printf '%s' "$ready_json" \
        | jq -r '.[] | select((.metadata."gc.decision_notified" // "") != "true") | .id' \
        2>/dev/null || true)
    [ -z "$ids" ] && return 0

    while IFS= read -r bid; do
        [ -z "$bid" ] && continue
        local full title owner deps closed_tsv
        full=$("$GC_BIN" bd show "$bid" --json 2>/dev/null || true)
        [ -z "$full" ] && continue
        title=$(printf '%s' "$full" | jq -r '.[0].title // ""' 2>/dev/null || echo "")
        owner=$(printf '%s' "$full" | jq -r '.[0].owner // ""' 2>/dev/null || echo "")
        deps=$(printf '%s' "$full" | jq -c '.[0].dependencies // []' 2>/dev/null || echo "[]")
        # Closed blockers, ordered most-recent-first. Excludes relates-to,
        # which is non-blocking by convention.
        closed_tsv=$(printf '%s' "$deps" \
            | jq -r '[.[]
                     | select(.dependency_type != "relates-to")
                     | select(.status == "closed")]
                     | sort_by(.closed_at // "") | reverse
                     | .[] | [.id, .title, (.closed_at // "")] | @tsv' \
            2>/dev/null || echo "")
        send_one "$bid" "$title" "$owner" "$closed_tsv" || true
    done <<<"$ids"
}

# HQ scope (no --rig).
process_scope ""

# Rig scope: walk every rig in the city. Mirrors orphan-sweep.sh.
RIG_LIST=$("$GC_BIN" rig list --json 2>/dev/null || true)
if [ -n "$RIG_LIST" ]; then
    while IFS= read -r rig; do
        [ -z "$rig" ] && continue
        process_scope "--rig $rig"
    done < <(printf '%s' "$RIG_LIST" | jq -r '.rigs[] | select(.hq == false) | .name' 2>/dev/null || true)
fi
