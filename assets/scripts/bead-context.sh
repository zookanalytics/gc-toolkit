#!/usr/bin/env bash
# bead-context.sh — one call answers "what is this bead, and is it actionable?"
# for a bead id. It prints the bead's status, title, type, assignee and routing;
# every dependency WITH its own status, resolved from the store that dependency
# lives in; the metadata that decides an anchor's fate (branch, target, PR,
# merge_result, gate lanes, successor pointer); the store the bead itself lives
# in; and a verdict on whether an open `blocks`-blocker holds it back. It exists
# so an agent stops re-running the show/jq/cross-store dance by hand every time
# it needs to know whether a blocked bead's blockers have landed.
#
# The store is derived from each id's prefix through `gc rig list --json`, the
# same binding assets/scripts/bead-store.sh proves, so a blocker in another
# rig's store is read from THAT store rather than reported unknown. Three
# `gc bd show --json` quirks are handled so the read never dies on live data: a
# `gc bd:` notice line that can precede the JSON on stdout is stripped; raw C0
# control bytes in accumulated notes are scrubbed before jq; and the payload
# that is an ARRAY when the id resolves but an `{"error":…}` OBJECT when it does
# not is discriminated on `type`, never on the exit code the two share.
#
# Reads only — it never writes the store, and a bead it cannot resolve is
# reported, not assumed. --json prints the whole context as one object for a
# machine; the default is a human-readable block.
#
# It reports the fields that decide a bead's fate, not its free-text body. Notes,
# description and comments are left out on purpose, so the context stays bounded
# and this complements `gc bd show <id>` rather than replacing it.
#
# Usage:
#   bead-context.sh <bead-id> [--store rig:<name> | --db <path>] [--json]
#
# Exit: 0 reported · 2 usage · 4 the subject id could not be resolved to a bead.
# Doctrine: docs/bead-store-resolution.md. Test: bead-context.test.sh.
# Run on demand to inspect one bead: a triage read, an unblock check, a
# hand-off. It reports; it does not drive the dispatch loop.
set -uo pipefail

PROG="bead-context"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

die()  { echo "$PROG: $1" >&2; exit "${2:-1}"; }

usage() {
  cat >&2 <<'U'
usage: bead-context.sh <bead-id> [--store rig:<name> | --db <path>/.beads] [--json]

Prints one bead's working context: status, dependencies each with their own
status (resolved from the store the dependency lives in), the metadata that
decides its fate, its successor pointer, and whether an open blocks-blocker
holds it. --store / --db pin the owning store when the id prefix is ambiguous
or names the city's own store, which no --rig value reaches. --json emits the
whole context as one object.

Examples:
  bead-context.sh tk-8kc5dz            human-readable context and verdict
  bead-context.sh tk-8kc5dz --json     the same context as one JSON object
  bead-context.sh su-1a2b3c --store rig:shutupandlisten   pin a foreign store
U
  exit 2
}

BEAD=""; STORE_REF=""; DB=""; JSON_OUT=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --store) [ "$#" -ge 2 ] || die "--store needs a value (rig:<name>)" 2; STORE_REF="$2"; shift 2 ;;
    --db)    [ "$#" -ge 2 ] || die "--db needs a value (<path>/.beads)" 2; DB="$2"; shift 2 ;;
    --json)  JSON_OUT=1; shift ;;
    -h|--help) usage ;;
    -*)      die "unknown argument '$1' (try --help)" 2 ;;
    *)       [ -z "$BEAD" ] || die "more than one bead id given ('$BEAD' and '$1')" 2; BEAD="$1"; shift ;;
  esac
done
[ -n "$BEAD" ] || usage

# A bounded call: an unreachable Dolt server hangs, and a tool that hangs never
# answers. Mirrors bead-store.sh, whose resolution this shares.
bounded() {
  if command -v timeout >/dev/null 2>&1; then timeout 20 "$@"; else "$@"; fi
}

# The rig roster is read once and reused for every prefix resolution below, so a
# bead with a dozen same-store deps does not re-shell `gc rig list` a dozen times.
RIGS_JSON=$(bounded gc rig list --json 2>/dev/null | scrub || true)

# prefix -> owning rig name, empty unless exactly one rig carries it (an unknown
# or a two-rig prefix is not a store this tool may silently pick).
rig_name_for_prefix() {
  printf '%s' "$RIGS_JSON" | jq -r --arg p "$1" \
    '[.rigs[]? | select(.prefix == $p)] | if length == 1 then .[0].name else "" end' 2>/dev/null || true
}
# prefix -> that rig's `<path>/.beads` store, empty when unresolved or pathless.
db_for_prefix() {
  printf '%s' "$RIGS_JSON" | jq -r --arg p "$1" \
    '[.rigs[]? | select(.prefix == $p)] | if length == 1 and ((.[0].path // "") != "") then .[0].path + "/.beads" else "" end' 2>/dev/null || true
}
# rig name -> that rig's `<path>/.beads` store, for --store rig:<name>.
db_for_rig_name() {
  printf '%s' "$RIGS_JSON" | jq -r --arg n "$1" \
    '[.rigs[]? | select(.name == $n)] | if length == 1 and ((.[0].path // "") != "") then .[0].path + "/.beads" else "" end' 2>/dev/null || true
}

# `gc bd [--db <db>] show <id> --json`, cleaned of the two contaminants that
# break a naive pipe to jq: the `gc bd:` notice line that can lead stdout, and
# raw control bytes. The notice strip runs with `grep -a` (force text mode): a
# raw NUL byte in the notes otherwise switches grep to binary and drops the
# whole payload before scrub can remove the byte, so the read must stay text
# through the filter and let scrub take the C0 bytes out. `--brief-deps` drops
# each dependency's description and notes from the payload: only a dep's id,
# type and status are read here, and a hub bead's dependencies carry large
# bodies otherwise. `status` survives it, so the same-store fast path below is
# intact. Prints the cleaned payload; the caller discriminates shape.
bd_show_clean() {
  local db="$1" id="$2"
  if [ -n "$db" ]; then
    bounded gc bd --db "$db" show "$id" --json --brief-deps 2>/dev/null | grep -a -vE '^gc bd:' | scrub || true
  else
    bounded gc bd show "$id" --json --brief-deps 2>/dev/null | grep -a -vE '^gc bd:' | scrub || true
  fi
}

# ── Resolve the subject's store ─────────────────────────────────────────────
# --db wins outright; then --store rig:<name>; then the id's own prefix. When
# none resolves, the read falls back to an unpinned `gc bd show`, which finds a
# live id in whichever store holds it (it cannot prove an ABSENCE, but this tool
# reports rather than destroys, so a plain not-found is a safe answer).
SUBJ_PREFIX="${BEAD%%-*}"
SUBJ_RIG=""
if [ -n "$DB" ]; then
  SUBJ_RIG=$(printf '%s' "$RIGS_JSON" | jq -r --arg d "$DB" \
    '[.rigs[]? | select(((.path // "") + "/.beads") == $d)] | if length == 1 then .[0].name else "" end' 2>/dev/null || true)
elif [ -n "$STORE_REF" ]; then
  case "$STORE_REF" in
    rig:?*) SUBJ_RIG="${STORE_REF#rig:}"; DB=$(db_for_rig_name "$SUBJ_RIG") ;;
    *) die "--store wants the form rig:<name> (got '$STORE_REF')" 2 ;;
  esac
  [ -n "$DB" ] || die "--store $STORE_REF does not resolve to a rig with a store path in 'gc rig list'" 2
else
  SUBJ_RIG=$(rig_name_for_prefix "$SUBJ_PREFIX")
  DB=$(db_for_prefix "$SUBJ_PREFIX")
fi

RAW=$(bd_show_clean "$DB" "$BEAD")
KIND=$(printf '%s' "$RAW" | jq -r 'type' 2>/dev/null || true)
if [ "$KIND" != "array" ]; then
  # An object is the `{"error":…}` not-found; empty is an unreadable store. Both
  # are "no bead to report", distinct from a bead that exists and is empty.
  WHERE="${SUBJ_RIG:-${DB:-the ambient store}}"
  die "$BEAD did not resolve to a bead in $WHERE — nothing to report (pass --store rig:<name> or --db <path>/.beads if it lives elsewhere)" 4
fi

# bd resolves a bare id as an exact-or-prefix match, so .[0] may be a longer
# bead the prefix hit. Report whichever id actually resolved rather than echoing
# the input, and normalize the fields in one pass.
SUBJ=$(printf '%s' "$RAW" | jq -c '.[0]')
NORM=$(printf '%s' "$SUBJ" | jq -c '
  (.metadata // {}) as $m |
  {
    id, status, title,
    type: .issue_type,
    assignee: (.assignee // null),
    routed_to: ($m["gc.routed_to"] // null),
    execution_routed_to: ($m["gc.execution_routed_to"] // null),
    branch: ($m["branch"] // null),
    target: ($m["target"] // $m["merged_target"] // null),
    existing_pr: ($m["existing_pr"] // null),
    pr_number: ($m["pr_number"] // null),
    pr_url: ($m["pr_url"] // null),
    merge_result: ($m["merge_result"] // null),
    prepare_mode: ($m["prepare_mode"] // null),
    rejection_reason: ($m["rejection_reason"] // null),
    work_dir: ($m["work_dir"] // null),
    check_set: ($m["check_set"] // null),
    checks: ($m | to_entries | map(select(.key | startswith("check."))) | map({(.key): .value}) | add // {}),
    successor: ($m["gc.superseded_by"] // $m["superseded_by"] // null),
    successor_store: ($m["gc.superseded_by_store"] // $m["superseded_by_store"] // null),
    supersedes: ($m["gc.supersedes"] // $m["supersedes"] // null),
    deps_raw: [.dependencies[]? | {id, type: (.dependency_type // null), status: (.status // null)}]
  }')

# ── Resolve each dependency against the store it lives in ───────────────────
# An embedded status is what the subject's store could join; a dependency in
# another store comes back without one, and THAT is the cross-store case this
# tool exists to close. Prefer the embedded status; when it is absent, ask the
# dependency's own store. Every dependency is annotated with its owning rig.
DEP_LINES=()
OPEN_BLOCKERS=()
while IFS=$'\t' read -r dep_id dep_type dep_status; do
  [ -n "$dep_id" ] || continue
  dep_prefix="${dep_id%%-*}"
  dep_rig=$(rig_name_for_prefix "$dep_prefix")
  resolved_via="embedded"
  if [ -z "$dep_status" ] || [ "$dep_status" = "null" ]; then
    dep_db=$(db_for_prefix "$dep_prefix")
    if [ -n "$dep_db" ]; then
      dep_raw=$(bd_show_clean "$dep_db" "$dep_id")
      dep_status=$(printf '%s' "$dep_raw" | jq -r 'if type == "array" and length > 0 then (.[0].status // "unknown") else "unknown" end' 2>/dev/null || echo unknown)
      resolved_via="cross-store"
    else
      dep_status="unknown"
      resolved_via="unresolved-store"
    fi
  fi
  [ -n "$dep_status" ] || dep_status="unknown"
  # A blocks-edge that is not proven closed is what holds the bead. An
  # unresolved status counts as holding: fail closed, never call it landed.
  if [ "$dep_type" = "blocks" ] && [ "$dep_status" != "closed" ]; then
    OPEN_BLOCKERS+=("$dep_id")
  fi
  DEP_LINES+=("$(jq -nc \
    --arg id "$dep_id" --arg type "$dep_type" --arg status "$dep_status" \
    --arg rig "$dep_rig" --arg via "$resolved_via" \
    '{id: $id, type: $type, status: $status, store: (if $rig == "" then null else $rig end), resolved_via: $via}')")
done < <(printf '%s' "$NORM" | jq -rc '.deps_raw[]? | [.id, (.type // ""), (.status // "")] | @tsv')

if [ "${#DEP_LINES[@]}" -gt 0 ]; then
  DEPS_JSON=$(printf '%s\n' "${DEP_LINES[@]}" | jq -sc '.')
else
  DEPS_JSON="[]"
fi
if [ "${#OPEN_BLOCKERS[@]}" -gt 0 ]; then
  BLOCKERS_JSON=$(printf '%s\n' "${OPEN_BLOCKERS[@]}" | jq -R . | jq -sc '.')
  ACTIONABLE=false
else
  BLOCKERS_JSON="[]"
  ACTIONABLE=true
fi

FINAL=$(printf '%s' "$NORM" | jq -c \
  --argjson deps "$DEPS_JSON" \
  --argjson blockers "$BLOCKERS_JSON" \
  --argjson actionable "$ACTIONABLE" \
  --arg store_rig "$SUBJ_RIG" \
  --arg store_db "$DB" \
  'del(.deps_raw) + {
     store: {rig: (if $store_rig == "" then null else $store_rig end), db: (if $store_db == "" then null else $store_db end)},
     dependencies: $deps,
     open_blockers: $blockers,
     actionable: $actionable
   }')

if [ -n "$JSON_OUT" ]; then
  printf '%s\n' "$FINAL" | jq '.'
  exit 0
fi

# ── Human-readable block ────────────────────────────────────────────────────
g() { printf '%s' "$FINAL" | jq -r "$1" 2>/dev/null; }
val() { case "$1" in ""|null) printf '%s' "$2" ;; *) printf '%s' "$1" ;; esac; }

RESOLVED_ID=$(g '.id')
printf '%s: %s\n\n' "$PROG" "$RESOLVED_ID"
printf '  Status      %s\n' "$(g '.status')"
printf '  Title       %s\n' "$(g '.title // ""')"
printf '  Type        %s\n' "$(val "$(g '.type // ""')" '(none)')"
printf '  Assignee    %s\n' "$(val "$(g '.assignee // ""')" '(unassigned)')"
printf '  Store       %s\n' "$(val "$(g '.store.rig // ""')" "(unresolved: prefix '$SUBJ_PREFIX')")"

RT=$(g '.routed_to // ""'); XRT=$(g '.execution_routed_to // ""')
[ -n "$RT" ]  && printf '  Routed to   %s\n' "$RT"
[ -n "$XRT" ] && printf '  Execution   %s  (provenance, not a live route)\n' "$XRT"

printf '\n  Metadata\n'
printf '    branch        %s\n' "$(val "$(g '.branch // ""')" '(unset)')"
printf '    target        %s\n' "$(val "$(g '.target // ""')" '(unset)')"
PR=$(g 'if .existing_pr then .existing_pr elif .pr_url then .pr_url elif .pr_number then (.pr_number|tostring) else "" end')
printf '    pr            %s\n' "$(val "$PR" '(none)')"
printf '    merge_result  %s\n' "$(val "$(g '.merge_result // ""')" '(unanchored)')"
printf '    check_set     %s\n' "$(val "$(g '.check_set // ""')" '(default)')"
# Gate lanes and resume markers are situational; show them only when present.
CHECKS=$(g '.checks | to_entries[]? | "    \(.key)   \(.value)"'); [ -n "$CHECKS" ] && printf '%s\n' "$CHECKS"
PM=$(g '.prepare_mode // ""');      [ -n "$PM" ] && printf '    prepare_mode  %s\n' "$PM"
RR=$(g '.rejection_reason // ""');  [ -n "$RR" ] && printf '    rejection     %s\n' "$RR"
WD=$(g '.work_dir // ""');          [ -n "$WD" ] && printf '    work_dir      %s\n' "$WD"

SUCC=$(g '.successor // ""'); SUCC_STORE=$(g '.successor_store // ""')
if [ -n "$SUCC" ]; then
  printf '    successor     %s%s\n' "$SUCC" "$( [ -n "$SUCC_STORE" ] && printf ' in %s' "$SUCC_STORE")"
fi

DEP_COUNT=$(g '.dependencies | length')
printf '\n  Dependencies (%s)\n' "$DEP_COUNT"
if [ "$DEP_COUNT" != "0" ]; then
  printf '    %-12s %-13s %-12s %s\n' STATUS TYPE STORE ID
  printf '%s' "$FINAL" | jq -r '.dependencies[] | "\(.status // "unknown")\t\(.type // "?")\t\(.store // "?")\t\(.id)"' \
    | while IFS=$'\t' read -r s t st i; do printf '    %-12s %-13s %-12s %s\n' "$s" "$t" "$st" "$i"; done
fi

if [ "$ACTIONABLE" = "true" ]; then
  printf '\n  Actionable  yes — no open blocks-blocker\n'
else
  printf '\n  Actionable  NO — open blocks-blocker(s): %s\n' "$(printf '%s' "$FINAL" | jq -r '.open_blockers | join(", ")')"
fi
