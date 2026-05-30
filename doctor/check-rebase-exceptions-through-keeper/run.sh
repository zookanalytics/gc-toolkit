#!/usr/bin/env bash
# Pack doctor check: every human-needing rebase exception surfaces THROUGH
# the keeper — a durable bead handback (reassign to the requesting keeper +
# metadata.aborted_at + failure context in the bead notes) plus a keeper
# nudge — never a best-effort mail to the operator as the only signal, and
# never a direct reassignment to the operator's mail alias
# (notify_recipient).
#
# Background (tk-i6cdyq): the gascity-keeper is THE single upstream
# front-door. Rebase aborts (workspace-setup / check / install / push /
# rebase-mismatch) used to reassign the work bead to notify_recipient (the
# operator) with best-effort mail as the only operator signal — the
# operator could miss the mail and the bead landed off the keeper's hook.
# The keeper's prime sweep keys on metadata.aborted_at among beads assigned
# to IT, so the durable, un-missable surface REQUIRES the bead to be
# reassigned to $REQUESTING_KEEPER (which falls back to notify_recipient
# only when no keeper was stamped). The refinery race-loss handback shares
# the same contract.
#
# This check locks the invariant in three places:
#   A. rebase formula: no abort/handback assigns the bead directly to
#      notify_recipient (the keeper-bypass pattern).
#   B. rebase formula: every executable `gc bd update ... --set-metadata
#      aborted_at=` command also carries --assignee="$REQUESTING_KEEPER",
#      and the count of such abort sites matches EXPECTED_ABORT_SITES
#      (drift guard in both directions).
#   C. refinery overlay race-loss: sets metadata.aborted_at (so the keeper
#      prime sweep catches it) AND nudges the keeper (timely signal).
#
# Site discovery joins shell line-continuations before applying the
# discriminator, so a future edit that wraps a `gc bd update` command
# differently cannot silently slip past this check.
#
# Exit codes: 0=OK, 1=Warning, 2=Error
# stdout: first line=message, rest=details

set -u

dir="${GC_PACK_DIR:-.}"
REBASE="$dir/packs/gascity-keeper/formulas/mol-upstream-gc-rebase.toml"
OVERLAY="$dir/packs/gascity-keeper/template-fragments/refinery-rebase-handling.template.md"
violations=()

# Executable abort sites in the rebase formula that set metadata.aborted_at
# via `gc bd update`. Today: workspace-setup, check, install, push.
# (rebase-mismatch is described in prose, not an executable `gc bd update`
# command, so it is not counted here.) Add/remove an abort site -> bump this
# and confirm the new site routes through $REQUESTING_KEEPER.
EXPECTED_ABORT_SITES=4

# ---- A. rebase formula: no direct assignee to notify_recipient ----
if [ ! -f "$REBASE" ]; then
    violations+=("missing rebase formula: $REBASE")
else
    while IFS= read -r m; do
        [ -n "$m" ] && violations+=("rebase formula assigns a bead directly to notify_recipient (must route through \$REQUESTING_KEEPER): $m")
    done < <(grep -nE -- '--assignee=[^[:space:]]*notify_recipient' "$REBASE")
fi

# ---- B. each aborted_at gc-bd-update command routes to $REQUESTING_KEEPER ----
# Join shell line-continuations into logical commands, keep the ones that
# are `gc bd update ... --set-metadata aborted_at=...`, and assert each
# carries --assignee="$REQUESTING_KEEPER". Robust to flag reordering and to
# edits that wrap the command across more/fewer physical lines.
find_abort_cmds() {
    awk '
        function emit() {
            if ((cmd ~ /gc bd update/) && (cmd ~ /--set-metadata aborted_at=/))
                print start "\t" cmd
            cmd = ""; start = 0
        }
        BEGIN { cmd = ""; start = 0 }
        {
            line = $0
            cont = sub(/\\$/, "", line)
            if (cmd == "") start = NR
            cmd = (cmd == "" ? line : cmd " " line)
            if (!cont) emit()
        }
        END { if (cmd != "") emit() }
    ' "$1"
}

if [ -f "$REBASE" ]; then
    abort_sites=$(find_abort_cmds "$REBASE")
    if [ -z "$abort_sites" ]; then
        found=0
    else
        found=$(printf '%s\n' "$abort_sites" | grep -c .)
    fi

    if [ "$found" -ne "$EXPECTED_ABORT_SITES" ]; then
        violations+=("expected $EXPECTED_ABORT_SITES executable aborted_at handback site(s) in rebase formula, found $found — site discovery is stale OR an abort site was added/removed; update EXPECTED_ABORT_SITES and confirm each routes through \$REQUESTING_KEEPER")
    fi

    while IFS=$'\t' read -r ln cmd; do
        [ -z "$ln" ] && continue
        if ! printf '%s' "$cmd" | grep -qE -- '--assignee="\$REQUESTING_KEEPER"'; then
            violations+=("rebase formula:$ln: aborted_at handback without --assignee=\"\$REQUESTING_KEEPER\" (would bypass the keeper)")
        fi
    done <<< "$abort_sites"
fi

# ---- C. refinery overlay race-loss: aborted_at + keeper nudge ----
if [ ! -f "$OVERLAY" ]; then
    violations+=("missing refinery overlay: $OVERLAY")
else
    if ! grep -qE -- '--set-metadata aborted_at=refinery-race-loss' "$OVERLAY"; then
        violations+=("refinery overlay race-loss handback does not set metadata.aborted_at=refinery-race-loss (keeper prime sweep would not catch it)")
    fi
    if ! grep -qE 'gc session nudge "\$KEEPER_TARGET"' "$OVERLAY"; then
        violations+=("refinery overlay race-loss handback does not nudge the keeper (no timely signal)")
    fi
fi

if [ ${#violations[@]} -eq 0 ]; then
    echo "rebase exceptions route through the keeper (durable handback + nudge; no notify_recipient bypass)"
    exit 0
fi

echo "${#violations[@]} rebase-exception-routing violation(s)"
for v in "${violations[@]}"; do
    echo "$v"
done
exit 2
