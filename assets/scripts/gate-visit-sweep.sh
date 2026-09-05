#!/usr/bin/env bash
# gate-visit-sweep — file one converse visit on the bead each open human gate
# blocks. The gate is the pack's human-escalation STATE; the visit is its
# RESOLUTION (the conversation that settles it). A human gate created by any
# producer — gc-helm.sh demand, mol-first-reaction — gets a visit here, in one
# place, so the visit-on-gate rule and its operator control live together.
#
# Default: every open human gate carrying gc.demand_for gets a visit on its
# gated bead. Operator override (the selection point): stamp gc.gate_visit on a
# gate with a falsey value (skip/no/false/off/0) to suppress that gate's visit
# (docs/gascity-human-engagement.md).
#
# The visit is filed through gc-helm.sh `open`, which files ONE open visit per
# subject and returns cleanly when one already exists — so this cooldown sweep
# re-runs safely, re-offering a visit only while the gate is still open, and a
# gate missed on one pass is caught on the next (no event subscription needed).
#
# Rig-scoped (orders/gate-visit-sweep.toml): each importing rig sweeps its own
# store, and the gate and its gated bead live in the same store. Per-gate
# best-effort — one unfilable visit never skips the rest — but a failure to
# ENUMERATE the gates exits non-zero, so an unreadable store never reads as
# "no gates".
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

# Enumerate open human gates that name the work they hold. A demand is an
# issue_type=gate/await_type=human bead carrying gc.demand_for (the gated
# bead); `bd list` hides gates, so --include-gates is load-bearing. A read
# failure exits non-zero: an unreadable store must never read as an empty one.
# The list status is read before `scrub`, since piping into tr would report
# tr's success and mask a failed list that still printed an array.
GATES_RAW=$(gc bd list --include-gates --has-metadata-key gc.demand_for \
    --status=open,in_progress --limit=0 --json 2>/dev/null) \
    || { echo "$PROG: could not list human gates — store unreadable, nothing filed" >&2; exit 1; }
GATES_RAW=$(printf '%s' "$GATES_RAW" | scrub)
printf '%s' "$GATES_RAW" | jq -e 'type == "array"' >/dev/null 2>&1 \
    || { echo "$PROG: gate listing is not a JSON array — store unreadable, nothing filed" >&2; exit 1; }

# (gate-id, gated-bead, title) for each open human gate not opted out.
# gc.gate_visit set to a falsey value is the operator's per-gate suppression.
ROWS=$(printf '%s' "$GATES_RAW" | jq -r '
  .[]
  | select((.await_type // "") == "human")
  | select(((.metadata["gc.gate_visit"] // "") | ascii_downcase) as $v
           | $v != "skip" and $v != "no" and $v != "false" and $v != "off" and $v != "0")
  | ((.metadata["gc.demand_for"] // "") | tostring) as $for
  | select($for != "")
  | [.id, $for, (.title // "")] | @tsv')

FILED=0
FAILED=0
while IFS=$'\t' read -r gate_id gated title; do
    [ -n "$gate_id" ] && [ -n "$gated" ] || continue
    reason="resolve the human gate on $gated"
    body="A human gate ($gate_id) blocks $gated and awaits a person."
    [ -n "$title" ] && body="$body
Question: $title"
    body="$body
Settle it in this sitting, then resolve the gate: gc bd gate resolve $gate_id"
    # `open` is idempotent — one open visit per subject — so a re-file is a
    # no-op, not a duplicate. A subject that no longer resolves is its own skip.
    if "$HELM" open "$gated" --reason "$reason" --body "$body" >/dev/null 2>&1; then
        FILED=$((FILED + 1))
    else
        echo "$PROG: FAILED to file a visit on $gated for gate $gate_id (will retry next sweep)" >&2
        FAILED=$((FAILED + 1))
    fi
done <<EOF
$ROWS
EOF

[ "$FILED" -gt 0 ] && echo "$PROG: ensured a visit on $FILED gated bead(s)"
if [ "$FAILED" -gt 0 ]; then
    echo "$PROG: $FAILED visit(s) failed to file (see above; will retry)" >&2
    exit 1
fi
exit 0
