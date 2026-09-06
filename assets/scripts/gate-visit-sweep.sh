#!/usr/bin/env bash
# gate-visit-sweep — file one converse visit on the bead each open human gate
# blocks. The gate is the pack's human-escalation STATE; the visit is its
# RESOLUTION (the conversation that settles it). A human gate created by any
# producer — gc-helm.sh demand, mol-first-reaction — gets a visit here, in one
# place, so the visit-on-gate rule and its operator control live together.
#
# ONE VISIT PER GATE. The sweep's idempotence key is the gate itself: once a
# visit stands for a gate, the gate is stamped gc.gate_visit=<visit-id> and is
# never re-offered. Keying on "is a visit open right now" instead would re-file
# every two minutes after any sitting that ends with the gate still open — a
# benign close, a cut-short hold that re-states the demand, an operator
# `dismiss` — spawning a fresh converse session per cooldown for a question
# already put to a person. The return trip for a cut-short hold is the liveness
# sweep's, as today.
#
# Operator controls (docs/gascity-human-engagement.md):
#   * stamp gc.gate_visit=skip on a gate BEFORE the sweep reaches it to suppress
#     its visit (any non-empty value is honoured as "handled");
#   * `gc bd update <gate> --unset-metadata gc.gate_visit` to re-offer a visit.
#
# Left alone, deliberately:
#   * a gate ASSIGNED to a person (`demand --kind task --assignee`): the work is
#     theirs to perform and close, and converse's discharge skips assigned
#     demands on purpose — a visit could neither resolve nor re-state it;
#   * a gate whose gated bead is no longer open: the gate outlived its work, a
#     visit on closed work would only spawn a session to find it moot. The sweep
#     names such a gate on stderr every pass until it is resolved by hand.
#
# A visit already standing for the gated bead — the sitting that filed the
# demand mid-hold, matched by continuation_group, tracks edge OR stall_root
# (the union liveness-sweep reads; `open` alone reads only the first two) —
# is recorded on the gate as its visit without filing a second one.
#
# Rig-scoped (orders/gate-visit-sweep.toml): each importing rig sweeps its own
# store, and the gate and its gated bead live in the same store. Per-gate
# best-effort — one unfilable visit never skips the rest — but a failure to
# ENUMERATE exits non-zero, so an unreadable store never reads as "no gates".
set -u

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload. All but
# LF go: raw TAB and CR do not occur in bd/gh output, and the TAB-splitting
# consumers downstream split jq's own @tsv, emitted after this runs.
scrub() { tr -d '\000-\011\013-\037'; }
# <<< control-char-scrub

PROG="gate-visit-sweep"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HELM="${GC_HELM_TOOL:-$SCRIPT_DIR/gc-helm.sh}"

command -v jq >/dev/null 2>&1 \
    || { echo "$PROG: jq is required but not found in PATH" >&2; exit 1; }
[ -x "$HELM" ] \
    || { echo "$PROG: gc-helm.sh not found or not executable at $HELM" >&2; exit 1; }

# Every non-closed status: the demand readers' set (signoff, pr-facts,
# liveness-recheck), so a gate an operator deferred or pinned is still swept.
LIVE_STATUSES="open,in_progress,blocked,deferred,hooked,pinned"

# list_guarded <label> <gc bd list args…> — one scrubbed JSON array on stdout,
# or a message and non-zero. The list status is read BEFORE the scrub, since
# piping into tr would report tr's success and mask a failed list that still
# printed an array; a non-array is unreadable too. Either way nothing is filed:
# an unreadable store must never read as an empty one.
list_guarded() {
    local label="$1" raw; shift
    raw=$(gc bd list "$@" 2>/dev/null) \
        || { echo "$PROG: could not list $label — store unreadable, nothing filed" >&2; return 1; }
    raw=$(printf '%s' "$raw" | scrub)
    printf '%s' "$raw" | jq -e 'type == "array"' >/dev/null 2>&1 \
        || { echo "$PROG: $label listing is not a JSON array — store unreadable, nothing filed" >&2; return 1; }
    printf '%s' "$raw"
}

# Open human gates that name the work they hold: issue_type=gate/await_type=
# human beads carrying gc.demand_for. `bd list` hides gates, so --include-gates
# is load-bearing.
GATES_RAW=$(list_guarded "human gates" --include-gates --has-metadata-key gc.demand_for \
    --status="$LIVE_STATUSES" --limit=0 --json) || exit 1
# Every live bead, read once: it answers "is the gated bead still open?" and
# "does a visit already stand for it?" for every gate below, instead of one
# `open` exec (rig list + show + full list) per gate per pass.
LIVE_RAW=$(list_guarded "live beads" --status="$LIVE_STATUSES" --limit=0 --json) || exit 1

# (gate-id, gated-bead, title) per gate still owed a visit. Typed metadata
# (`--metadata '{"gc.gate_visit":false}'`) is read through tostring so a
# non-string value is "handled", never a jq abort; a jq failure is a failed
# read, not an empty queue.
ROWS=$(printf '%s' "$GATES_RAW" | jq -r '
  .[]
  | select((.await_type // "") == "human")
  | select(((.assignee // "") | tostring) == "")
  | select(((.metadata["gc.gate_visit"] | if . == null then "" else tostring end)) == "")
  | ((.metadata["gc.demand_for"] // "") | tostring) as $for
  | select($for != "")
  | [.id, $for, (.title // "")] | @tsv') \
    || { echo "$PROG: could not read the gate listing (jq failed) — nothing filed" >&2; exit 1; }

FILED=0; HELD=0; STALE=0; FAILED=0
while IFS=$'\t' read -r gate_id gated title; do
    [ -n "$gate_id" ] && [ -n "$gated" ] || continue

    live=$(printf '%s' "$LIVE_RAW" | jq -r --arg b "$gated" \
        '[ .[] | select((.id // "") == $b) ] | length' 2>/dev/null || echo 0)
    if [ "${live:-0}" -lt 1 ]; then
        echo "$PROG: gate $gate_id blocks $gated, which is not open — the gate outlives its work; no visit filed. Resolve it by hand: gc bd gate resolve $gate_id" >&2
        STALE=$((STALE + 1)); continue
    fi

    # A visit already standing for the gated bead: the same union of stamp,
    # tracks edge and stall_root that liveness-sweep reads as "conversing".
    visit=$(printf '%s' "$LIVE_RAW" | jq -r --arg s "$gated" '
      [ .[] | select((.metadata.task_kind // "") == "visit")
        | select(((.metadata["gc.continuation_group"] // "") == $s)
                 or ((.metadata.stall_root // "") == $s)
                 or ([ .dependencies[]?
                       | select((.type // "") == "tracks")
                       | select((.depends_on_id // "") == $s) ] | length > 0))
        | .id ] | first // empty' 2>/dev/null || true)

    if [ -n "$visit" ]; then
        HELD=$((HELD + 1))
    else
        reason="resolve the human gate on $gated"
        body="A human gate ($gate_id) blocks $gated and awaits a person."
        [ -n "$title" ] && body="$body
Question: $title"
        body="$body
Settle it in this sitting, then resolve the gate: gc bd gate resolve $gate_id"
        if out=$("$HELM" open "$gated" --reason "$reason" --body "$body" 2>&1); then
            # `open` names the visit either way: "visit <id> filed on" for a
            # fresh one, "visit <id> is already open for" when one stands.
            visit=$(printf '%s\n' "$out" \
                | sed -n 's/^.*: visit \([^ ]*\) \(filed on\|is already open for\) .*$/\1/p' | head -n 1)
            FILED=$((FILED + 1))
        else
            echo "$PROG: FAILED to file a visit on $gated for gate $gate_id (will retry next sweep)" >&2
            FAILED=$((FAILED + 1)); continue
        fi
    fi

    # Record the visit on the gate — the idempotence key. A stamp that does not
    # land is retried next pass; `open` stays a no-op while that visit is open.
    gc bd update "$gate_id" --set-metadata "gc.gate_visit=${visit:-filed}" >/dev/null 2>&1 \
        || echo "$PROG: warning: could not stamp gc.gate_visit=${visit:-filed} on $gate_id — it will be re-checked next sweep" >&2
done <<EOF2
$ROWS
EOF2

if [ "$FILED" -gt 0 ] || [ "$HELD" -gt 0 ] || [ "$STALE" -gt 0 ]; then
    echo "$PROG: filed $FILED visit(s); $HELD gate(s) already under a visit; $STALE gate(s) on closed work"
fi
if [ "$FAILED" -gt 0 ]; then
    echo "$PROG: $FAILED visit(s) failed to file (see above; will retry)" >&2
    exit 1
fi
exit 0
