#!/bin/sh
# work-context.sh — deliver the work bead's own description into the polecat's
# context, deterministically, at the moment the bead is claimed. The formula
# reads the bead jq-filtered to metadata, and a mid-workflow respawn never
# runs load-context, so without this hook the spec silently degrades to
# title-only. Runs as a Claude `PostToolUse` hook on Bash: after every claim
# it resolves the claimed bead to its work bead and injects the description
# as `additionalContext`. Full derivation: specs/tk-osf13/. A claim that hands
# the session the workflow root of a molecule that is still running is
# released instead, and the session is told why (guard_workflow_root).
#
# Invariants:
#   * ALWAYS exit 0 — never block the polecat's tool call.
#   * stdout is a single JSON object or empty — never prose.
#   * Idempotent per (session, work bead); best-effort — the load-context
#     instruction stays the fallback.
#   * The common case (not a claim) stays cheap: one jq, then exit.
#   * The one store write is the release of a claimed workflow root.

set -u

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub
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

show_bead() {
  run_bounded gc bd show "$1" --json 2>/dev/null | scrub
}

# emit_notice prints <text> as the hook's one JSON object and ends the hook.
emit_notice() {
  printf '%s\n' "$1" \
    | jq -Rs '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: .}}' 2>/dev/null
  exit 0
}

# --- A claimed workflow root ---------------------------------------------
# A pool can hand a session the root (gc.kind=workflow) of a molecule that is
# still running. Gascity's default on_boot hook reopens every in_progress,
# unassigned bead routed to the pool at each city start, roots included, and
# order dispatch leaves the root it pours open and routed. The root's
# description is the formula body, and a session that ran it would run the
# molecule a second time beside its own steps: a second worktree on the same
# branch, or a second sweep of the same window. So while the molecule is live
# the claim is released here, before any step runs, and no formula is injected.
#
# The molecule is live while a step of it that has not closed is in progress,
# is held by a session, or waits in the pool the root was claimed from. Its
# steps carry the work, and its workflow-finalize step closes the root once
# they finish. A root with no such step returns to the injection below
# unchanged.
#
# The release is one update guarded on the assignee and status read here, so a
# root that changed hands or closed since is never written. It clears the
# assignee and the route, and touches neither the root's status nor any step.
# Sling launches a root in_progress, gascity's continuation nudge serves a
# pre-assigned step only while its root reads in_progress, and bd's claim
# refuses an in_progress bead. The route goes because a routed root is pool
# demand again once anything reopens it, as the on_boot hook does at every
# city start. The workflow-finalize step closes the root from either status.
guard_workflow_root() {
  formula="$(printf '%s' "$claimed_json" | jq -r '.[0].metadata["gc.formula_name"] // .[0].title // "workflow"' 2>/dev/null)"
  route="$(printf '%s' "$response" | grep -o '"route":"[^"]*"' | head -1 | sed 's/.*:"//; s/"$//')"
  [ -n "$route" ] || route="$(printf '%s' "$claimed_json" | jq -r '.[0].metadata["gc.routed_to"] // empty' 2>/dev/null)"
  steps="$(run_bounded gc bd list --metadata-field="gc.root_bead_id=$claimed" --json --limit=0 2>/dev/null | scrub)"
  # Prints {verdict, held}: verdict is live, orphan or unreadable, and held
  # names up to three live steps, the ones in progress first.
  assessed="$(printf '%s' "$steps" | jq -c --arg route "$route" '
    def live: type == "object" and (.status // "") != "closed"
      and ((.status // "") == "in_progress"
           or (.assignee // "") != ""
           or ($route != "" and ((.metadata // {})["gc.routed_to"] // "") == $route));
    def rank: if .status == "in_progress" then 0 elif (.assignee // "") != "" then 1 else 2 end;
    def phrase:
      ((.metadata // {})["gc.step_ref"] // "") as $ref
      | (.assignee // "") as $who
      | (if $ref != "" then "\($ref) (\(.id))" else (.id // "a step") end)
        + (if .status == "in_progress" then (if $who != "" then " in progress under \($who)" else " in progress" end)
           elif $who != "" then " held by \($who)"
           else " waiting in the pool" end);
    if type != "array" then {verdict: "unreadable"}
    else [ .[] | select(live) ] | sort_by(rank) as $live
      | if ($live | length) == 0 then {verdict: "orphan"}
        else {verdict: "live",
              held: (($live[0:3] | map(phrase) | join("; "))
                     + (if ($live | length) > 3 then "; and \(($live | length) - 3) more" else "" end))}
        end
    end' 2>/dev/null)"
  verdict="$(printf '%s' "$assessed" | jq -r '.verdict // empty' 2>/dev/null)"
  dont="Do not run its formula, and do not touch its steps, branch or worktree."
  case "$verdict" in
    live) : ;;
    orphan) return 0 ;;
    *) emit_notice "Claimed bead $claimed is the workflow root of a $formula molecule, not a work bead. The work-context hook could not read its steps, so it cannot tell whether another session is running the molecule, and it did not release the claim. $dont Read the steps first: gc bd list --metadata-field gc.root_bead_id=$claimed --json" ;;
  esac

  held="$(printf '%s' "$assessed" | jq -r '.held // ""' 2>/dev/null)"
  about="Claimed bead $claimed is the workflow root of a running $formula molecule, not work. Its live steps: $held."
  me="$(printf '%s' "$response" | grep -o '"assignee":"[^"]*"' | head -1 | sed 's/.*:"//; s/"$//')"
  [ -n "$me" ] || me="${GC_SESSION_ID:-}"
  holder="$(printf '%s' "$claimed_json" | jq -r '.[0].assignee // empty' 2>/dev/null)"
  read_status="$(printf '%s' "$claimed_json" | jq -r '.[0].status // empty' 2>/dev/null)"
  case "$read_status" in
    open|in_progress) status="$read_status" ;;
    *) status="" ;;
  esac
  if [ -z "$me" ] || [ "$holder" != "$me" ] || [ -z "$status" ]; then
    emit_notice "$about The work-context hook did not release it, because the root does not read as this claim: its assignee is ${holder:-empty} and its status ${read_status:-unknown}. $dont Read it (gc bd show $claimed --json) before acting on it."
  fi

  note="[$(date -u +%Y-%m-%dT%H:%M:%SZ)] work-context hook: gc hook --claim handed this workflow root to $me while its molecule ran. Live steps: $held. A root is not work while its steps run, so the hook released the claim before the session acted on it, leaving the root unassigned and unrouted with its status unchanged. The molecule's workflow-finalize step closes it."
  run_bounded gc bd update "$claimed" --if-assignee="$holder" --if-status="$status" \
    --set-metadata=gc.routed_to= --assignee= --append-notes="$note" \
    </dev/null >/dev/null 2>&1
  rc=$?
  case "$rc" in
    0) emit_notice "$about The work-context hook released the claim: the root is unassigned and unrouted again, with a note saying why, so no pool offers it, and the molecule's workflow-finalize step closes it. $dont Run gc hook --claim --json again for your own work." ;;
    13) emit_notice "$about The work-context hook wrote nothing, because the root changed after the claim: its assignee or status no longer matches what the hook read. $dont Read it (gc bd show $claimed --json) before acting on it." ;;
    *) emit_notice "$about The work-context hook could not release the claim (gc bd update exited $rc). $dont Release only the root, then claim again: gc bd update $claimed --if-assignee=$holder --if-status=$status --set-metadata=gc.routed_to= --assignee= --append-notes=\"<why>\"" ;;
  esac
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
# The response is the only sound source for the claimed id. $GC_TRIGGER_BEAD_ID
# is spawn-fixed and no claim refreshes it, so a pool worker's copy names a bead
# it is not working; load-context covers a claim that printed no id.
[ -n "$claimed" ] || exit 0

# --- 4. Claimed bead -> work bead ----------------------------------------
# A claimed formula step carries gc.root_bead_id; the root carries the input
# convoy; the convoy's single tracked member is the work bead. A bead claimed
# outside a formula IS the work bead, unless it is a workflow root, which the
# guard above releases while its molecule runs.
work="$claimed"
claimed_json="$(show_bead "$claimed")"
root="$(printf '%s' "$claimed_json" | jq -r '.[0].metadata["gc.root_bead_id"] // empty' 2>/dev/null)"
if [ -z "${root:-}" ] \
  && [ "$(printf '%s' "$claimed_json" | jq -r '.[0].metadata["gc.kind"] // empty' 2>/dev/null)" = "workflow" ]; then
  guard_workflow_root
fi
if [ -n "${root:-}" ]; then
  convoy="$(show_bead "$root" | jq -r '.[0].metadata["gc.input_convoy_id"] // empty' 2>/dev/null)"
  if [ -n "${convoy:-}" ]; then
    member="$(run_bounded gc convoy status "$convoy" --json 2>/dev/null \
      | scrub \
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
