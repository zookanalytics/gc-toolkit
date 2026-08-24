#!/bin/sh
# work-context.sh — deliver the work bead's own description into the polecat's
# context, deterministically, at the moment the bead is claimed. The formula
# reads the bead jq-filtered to metadata, and a mid-workflow respawn never
# runs load-context, so without this hook the spec silently degrades to
# title-only. Runs as a Claude `PostToolUse` hook on Bash: after every claim
# it resolves the claimed bead to its work bead and injects the description
# as `additionalContext`. Full derivation: specs/tk-osf13/.
#
# Invariants:
#   * ALWAYS exit 0 — never block the polecat's tool call.
#   * stdout is a single JSON object or empty — never prose.
#   * Idempotent per (session, work bead); best-effort — the load-context
#     instruction stays the fallback.
#   * The common case (not a claim) stays cheap: one jq, then exit.

set -u
export PATH="$HOME/go/bin:$HOME/.local/bin:$PATH"

# --- 1. Self-gate: Claude polecat pools only -----------------------------
# GC_AGENT is the pool NAME (gc-toolkit/gc-toolkit.nux) and cannot identify the
# role — pool polecats are named after people, not roles. GC_TEMPLATE is the
# role: <prefix>/<rig>.<agent-base>, e.g. gc-toolkit/gc-toolkit.polecat.
[ "${GC_PROVIDER:-claude}" = "claude" ] || exit 0
template="${GC_TEMPLATE:-}"
[ -n "$template" ] || exit 0
case "${template##*.}" in
  polecat) : ;;
  *) exit 0 ;; # refinery/witness/deacon/mechanik/converse — not a work-bead worker
esac

command -v jq >/dev/null 2>&1 || exit 0
command -v gc >/dev/null 2>&1 || exit 0

# Bound every `gc` read: a wedged Dolt must not hold the tool call open.
run_bounded() {
  if command -v timeout >/dev/null 2>&1; then
    timeout 10 "$@"
  else
    "$@"
  fi
}

# `bd show --json` can emit raw control characters that make jq abort on
# otherwise-valid rows; strip them (sparing TAB) before every parse.
show_bead() {
  run_bounded gc bd show "$1" --json 2>/dev/null | tr -d '\000-\010\013\014\016-\037'
}

# --- 2. Is this tool call a claim? ---------------------------------------
payload="$(cat 2>/dev/null)" || exit 0
[ -n "$payload" ] || exit 0

command_line="$(printf '%s' "$payload" | jq -r '.tool_input.command // ""' 2>/dev/null)" || exit 0
case "$command_line" in
  *--claim*) : ;;
  *) exit 0 ;; # the overwhelmingly common path: not a claim, nothing to do
esac

# --- 3. Resolve the claimed bead -----------------------------------------
# `gc hook --claim --json` prints {"bead_id":"tk-...",...}, but city.toml
# warnings pollute the same stream, so scan for the field rather than parsing
# the whole response as JSON.
#
# Bash's tool_response is an OBJECT ({stdout, stderr, ...}), so tojson re-escapes
# the JSON the command printed and the field arrives as \"bead_id\":\"tk-...\".
# Unescape before scanning, or the match silently never fires on the real
# payload shape (it fires only on clients that hand back a bare string).
response="$(printf '%s' "$payload" | jq -r '
  (.tool_response // "")
  | if type == "string" then . else tojson end' 2>/dev/null | sed 's/\\"/"/g')"
claimed="$(printf '%s' "$response" \
  | grep -o '"bead_id":"[^"]*"' \
  | head -1 \
  | sed 's/.*:"//; s/"$//')"
# `gc bd update <id> --claim` has no JSON envelope; fall back to the bead this
# session was spawned on, which resolves to the same workflow root.
[ -n "$claimed" ] || claimed="${GC_TRIGGER_BEAD_ID:-}"
[ -n "$claimed" ] || exit 0

# --- 4. Claimed bead -> work bead ----------------------------------------
# A claimed formula step carries gc.root_bead_id; the root carries the input
# convoy; the convoy's single tracked member is the work bead. A bead claimed
# outside a formula IS the work bead.
work="$claimed"
root="$(show_bead "$claimed" | jq -r '.[0].metadata["gc.root_bead_id"] // empty' 2>/dev/null)"
if [ -n "${root:-}" ]; then
  convoy="$(show_bead "$root" | jq -r '.[0].metadata["gc.input_convoy_id"] // empty' 2>/dev/null)"
  if [ -n "${convoy:-}" ]; then
    member="$(run_bounded gc convoy status "$convoy" --json 2>/dev/null \
      | tr -d '\000-\010\013\014\016-\037' \
      | jq -r 'if (.children | length) == 1 then .children[0].id else empty end' 2>/dev/null)"
    [ -n "${member:-}" ] && work="$member"
  fi
fi

# --- 5. Inject once per (session, work bead) -----------------------------
session="$(printf '%s' "$payload" | jq -r '.session_id // ""' 2>/dev/null)"
[ -n "$session" ] || session="${GC_SESSION_ID:-nosession}"
safe_key="$(printf '%s.%s' "$session" "$work" | tr -c 'A-Za-z0-9._-' '_')"
mark_dir="${TMPDIR:-/tmp}/gc-work-context"
mark="$mark_dir/$safe_key"
mkdir -p "$mark_dir" 2>/dev/null || exit 0
[ -e "$mark" ] && exit 0

# --- 6. Emit the description --------------------------------------------
bead_json="$(show_bead "$work")"
[ -n "$bead_json" ] || exit 0
title="$(printf '%s' "$bead_json" | jq -r '.[0].title // ""' 2>/dev/null)"
description="$(printf '%s' "$bead_json" | jq -r '.[0].description // ""' 2>/dev/null)"
# No description is the normal case for a title-only bead — inject nothing
# rather than an empty banner that reads as "the filer wrote nothing here".
[ -n "${description:-}" ] || exit 0

# Cap the injection. A description long enough to blow the context window is
# itself the pathology; deliver the head and name the command that reads the
# rest, which is strictly better than today's nothing.
limit=12000
# `cut -c` truncates per LINE, not per string, so it silently caps nothing on a
# multi-line description — `head -c` is the one that bounds the whole payload.
if [ "${#description}" -gt "$limit" ]; then
  description="$(printf '%s' "$description" | head -c "$limit")
[...truncated at ${limit} chars — read the rest with: gc bd show $work]"
fi

: > "$mark" 2>/dev/null || true

printf 'Work bead %s — description as filed (delivered by the work-context hook,\nbecause the formula reads this bead for metadata only):\n\n# %s\n\n%s\n' \
  "$work" "$title" "$description" \
  | jq -Rs '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: .}}' 2>/dev/null

exit 0
