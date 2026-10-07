#!/usr/bin/env bash
# proactive-scan-sling.sh — the scheduled intake trigger for the proactive
# first-reaction pool. The engine is tools/gc-proactive.sh; this is the thin
# trigger layer the order orders/proactive-scan-sling.toml schedules, so a
# newly-filed bead gets a first reaction at intake instead of waiting for the
# liveness-sweep backstop.
#
# It runs `scan --sling` only where a slung reaction can be claimed. `deliverable`
# reads the live city roster and exits non-zero when this rig's proactive pool is
# absent, suspended, or capped at zero, so an importing rig without a live pool is
# a clean no-op rather than routing reactions to a target nobody can claim. An
# unreadable roster leaves `deliverable` on the yes side, the same fail-toward-
# action bias the picker uses for an operator-facing react.
#
# scan --sling is bounded by GC_PROACTIVE_SLING_CAP reactions per sweep and
# GC_PROACTIVE_SCAN_LIMIT beads per scan; the cadence is the order's interval.
# The pool it slings into caps concurrency at its own max_active_sessions, so an
# over-slung sweep queues at zero cost rather than overrunning the pool.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# Same resolution the other assets/scripts callers use (first-reaction-dispose.sh,
# patrol-finding.sh): the engine is a sibling of this directory under the pack
# root, overridable for tests.
PROACTIVE="${GC_PROACTIVE_TOOL:-$HERE/../../tools/gc-proactive.sh}"
[ -x "$PROACTIVE" ] || { printf 'proactive-scan-sling: picker not executable at %s\n' "$PROACTIVE" >&2; exit 1; }

# Gate on deliverability so a rig without a live proactive pool skips cleanly
# (exit 0 = the order ran and had nothing to do here) instead of slinging
# reactions that would sit unclaimed.
if ! verdict="$("$PROACTIVE" deliverable 2>&1)"; then
  printf 'proactive-scan-sling: no sweep this rig — %s\n' "$verdict"
  exit 0
fi

exec "$PROACTIVE" scan --sling
