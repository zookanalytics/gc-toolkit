#!/usr/bin/env bash
# review-checks — the one parser AND resolver of the check index. The index is
# review-checks.toml at the repo root; it declares each check's name, the method
# that governs it, one line of purpose, and the phase it gates. Two jobs:
#
#   review-checks.sh --file <index> [--check <name>]
#     Emit the index as TSV, one row per check:
#       <name>\t<method>\t<purpose>\t<phase>
#
#   review-checks.sh --resolve --check-set <cs> --through <phase> \
#       [--file <index> | --at <oid>] [--with-phase]
#     Emit the checks in <cs> that gate the transition <phase> — every check
#     whose phase is at or before <phase> — one per line (or `<name>\t<phase>`
#     with --with-phase). This is the ONE place that knows none/off are the
#     gateless sentinels and `approval` is a merge rule, not a lane; all three
#     are dropped here so no transition re-derives the drop. Each stage
#     transition (create, draft-to-ready, merge) asks this instead of carrying
#     its own list, so one anchor is judged by one rule.
#
# Phase ordering: pre-open < open-as-draft < ready-for-review < merge. A check
# that reads only the diff is pre-open; one that needs the deployed preview is
# open-as-draft. A check_set token declared in no readable index defaults to
# pre-open (the backstop the dispatcher can act on) with a warning, never
# dropped silently — merge alone would strand it (see the resolve loop).
#
# Index resolution for --resolve: --file wins; else --at reads it from a commit
# (git show <oid>:review-checks.toml, under the toplevel or GC_RIG_ROOT); else
# the working-tree review-checks.toml. When NO index is readable, --resolve
# falls back to the pre-phase behavior — every non-sentinel, non-approval token
# gates every transition — so a readless pass never opens an ungated PR.
#
# The index declares mechanical facts only — a check's name, its method, its
# purpose, its phase. When a check applies to a given diff is a judgment its
# method states in prose, not a column here, so this parser reads no applies-when.
# Callers: signoff.sh, skills/review-triage, pr-open.sh, merge.sh, gate-ensure.sh,
# pr-facts.sh, review-outcome.sh, pr-summary-region.sh, liveness-sweep.sh,
# review-checks.test.sh.
# Exit: 0 ok · 1 no readable index, or --check not declared · 2 usage.
set -uo pipefail

usage() { sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }
warn() { echo "review-checks: $*" >&2; }

MODE="emit"
FILE=""; ONLY_CHECK=""; CHECK_SET=""; THROUGH=""; AT=""; WITH_PHASE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --resolve)     MODE="resolve"; shift ;;
    --file)        FILE="${2:-}";      shift 2 || { usage >&2; exit 2; } ;;
    --check)       ONLY_CHECK="${2:-}"; shift 2 || { usage >&2; exit 2; } ;;
    --check-set)   CHECK_SET="${2:-}"; shift 2 || { usage >&2; exit 2; } ;;
    --through)     THROUGH="${2:-}";   shift 2 || { usage >&2; exit 2; } ;;
    --at)          AT="${2:-}";        shift 2 || { usage >&2; exit 2; } ;;
    --with-phase)  WITH_PHASE=1; shift ;;
    -h|--help)     usage; exit 2 ;;
    *) echo "review-checks: unknown argument '$1'" >&2; usage >&2; exit 2 ;;
  esac
done

# Rank a phase, or empty for a value outside the ordered set.
phase_rank() {
  case "$1" in
    pre-open)          echo 1 ;;
    open-as-draft)     echo 2 ;;
    ready-for-review)  echo 3 ;;
    merge)             echo 4 ;;
    *)                 echo "" ;;
  esac
}

# Parse an index file into TSV rows: <name>\t<method>\t<purpose>\t<phase>.
# A check is a [checks.<name>] table with string keys. The grammar is a minimal
# TOML subset: table headers, `key = "value"` lines, `#` comments, blanks. A
# value's surrounding double quotes are stripped; any other table ends the checks
# context so a stray key outside a [checks.*] header is never read into a check.
parse_index() { # <file>
  awk '
    function trim(s) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s }
    function val(l,   v) {
      v = l; sub(/^[^=]*=[[:space:]]*/, "", v)
      v = trim(v)
      sub(/^"/, "", v); sub(/"$/, "", v)
      return v
    }
    function flush() {
      if (name != "") printf "%s\t%s\t%s\t%s\n", name, method, purpose, phase
      name = ""; method = ""; purpose = ""; phase = ""
    }
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*\[/ {
      flush()
      if ($0 ~ /^[[:space:]]*\[checks\.[A-Za-z0-9_-]+\][[:space:]]*$/) {
        h = $0; sub(/^[[:space:]]*\[checks\./, "", h); sub(/\][[:space:]]*$/, "", h)
        name = h
      }
      next
    }
    name != "" && /^[[:space:]]*method[[:space:]]*=/  { method  = val($0); next }
    name != "" && /^[[:space:]]*purpose[[:space:]]*=/ { purpose = val($0); next }
    name != "" && /^[[:space:]]*phase[[:space:]]*=/   { phase   = val($0); next }
    END { flush() }
  ' "$1"
}

# Resolve an index file for --resolve: --file, else --at <oid> via git show
# (toplevel then GC_RIG_ROOT, mirroring signoff.sh resolve_index), else the
# working-tree review-checks.toml. Prints a readable path, or nothing. A caller
# that gets nothing takes the no-index fallback.
RESOLVED_TMP=""
IDX=""
cleanup() { [ -n "$RESOLVED_TMP" ] && rm -f "$RESOLVED_TMP"; }
trap cleanup EXIT
# Sets IDX to a readable index path (empty when none), and RESOLVED_TMP when it
# created a temp blob. Called directly (not in $(...)) so the globals — and the
# cleanup trap that reads them — land in this shell, never a lost subshell.
resolve_index_file() {
  IDX=""
  if [ -n "$FILE" ]; then
    [ -r "$FILE" ] && IDX="$FILE"
    return
  fi
  # An explicit environment override, authoritative when set: readable → use it,
  # unreadable → no index (the fallback), never a silent reach past it. It lets a
  # hermetic test fix the index a cadence caller's --at would otherwise resolve
  # from the live checkout.
  if [ -n "${GC_REVIEW_CHECKS_INDEX:-}" ]; then
    [ -r "$GC_REVIEW_CHECKS_INDEX" ] && IDX="$GC_REVIEW_CHECKS_INDEX"
    return
  fi
  local root blob
  if [ -n "$AT" ]; then
    blob=$(mktemp "${TMPDIR:-/tmp}/gctk-review-checks-index.XXXXXX") || blob=""
    if [ -n "$blob" ]; then
      for root in "$(git rev-parse --show-toplevel 2>/dev/null)" "${GC_RIG_ROOT:-}"; do
        [ -n "$root" ] || continue
        if git -C "$root" show "$AT:review-checks.toml" >"$blob" 2>/dev/null && [ -s "$blob" ]; then
          RESOLVED_TMP="$blob"; IDX="$blob"; return
        fi
      done
      rm -f "$blob"
    fi
  fi
  for root in "$(git rev-parse --show-toplevel 2>/dev/null)" "${GC_RIG_ROOT:-}"; do
    [ -n "$root" ] || continue
    if [ -r "$root/review-checks.toml" ]; then IDX="$root/review-checks.toml"; return; fi
  done
}

if [ "$MODE" = "resolve" ]; then
  [ -n "$CHECK_SET" ] || CHECK_SET=""   # an empty set resolves to no gates
  [ -n "$THROUGH" ] || { echo "review-checks: --resolve needs --through <phase>" >&2; usage >&2; exit 2; }
  THRU_RANK=$(phase_rank "$THROUGH")
  [ -n "$THRU_RANK" ] || { echo "review-checks: --through '$THROUGH' is not a phase (pre-open|open-as-draft|ready-for-review|merge)" >&2; exit 2; }

  resolve_index_file
  # name<TAB>phase map from the index, lowercased name for case-insensitive lookup.
  PHASES=""
  if [ -n "$IDX" ]; then
    PHASES=$(parse_index "$IDX" | awk -F'\t' '{ n=tolower($1); print n "\t" $4 }')
  fi

  emit_one() { # <original-token> <phase-or-empty>
    if [ -n "$WITH_PHASE" ]; then printf '%s\t%s\n' "$1" "${2:-merge}"; else printf '%s\n' "$1"; fi
  }

  # Tokenize the check_set, preserving each token's original case (it names a
  # lane), deduping on the lowercased form, dropping the three non-lanes.
  seen=""
  printf '%s\n' "$CHECK_SET" | tr ',' '\n' | sed 's/[[:space:]]//g; /^$/d' | while IFS= read -r tok || [ -n "$tok" ]; do
    [ -n "$tok" ] || continue
    low=$(printf '%s' "$tok" | tr '[:upper:]' '[:lower:]')
    case "$low" in none|off|approval) continue ;; esac
    case " $seen " in *" $low "*) continue ;; esac
    seen="$seen $low"
    if [ -z "$IDX" ]; then
      # No readable index: fall back to the pre-phase behavior — every surviving
      # token gates every transition. Preserves current behavior for a repo whose
      # checks are all pre-open, and never opens an ungated PR.
      emit_one "$tok" ""
      continue
    fi
    ph=$(printf '%s' "$PHASES" | awk -F'\t' -v n="$low" '$1 == n { print $2; exit }')
    declared=$(printf '%s' "$PHASES" | awk -F'\t' -v n="$low" '$1 == n { print "y"; exit }')
    rank=$(phase_rank "$ph")
    if [ -n "$rank" ]; then
      [ "$rank" -le "$THRU_RANK" ] && emit_one "$tok" "$ph"
    elif [ "$declared" = "y" ]; then
      # Declared but unphased — an index predating the phase column. Before phases
      # every declared check gated the create, so default to pre-open rather than
      # open the PR ungated during the rollout window.
      warn "check '$tok' is declared but carries no phase ($IDX); defaulting to pre-open"
      emit_one "$tok" "pre-open"
    else
      # Undeclared token: default to pre-open — the earliest phase, the one
      # gate-ensure dispatches at every stage, so the token always has a path
      # to its review rather than a merge-only gate that could hold the merge
      # with no review ever produced. Pre-open also matches the pre-phase
      # behavior — every check_set token gated the create — so a live anchor
      # still carrying a legacy token (e.g. `codex`) keeps gating the create
      # and stays satisfiable. Never dropped silently.
      warn "check '$tok' is declared in no readable index ($IDX); defaulting to pre-open"
      emit_one "$tok" "pre-open"
    fi
  done
  if [ -z "$IDX" ]; then warn "no readable check index (--file/--at/working tree all failed); every non-sentinel token gates every transition"; fi
  exit 0
fi

# --- emit mode (the TSV) -------------------------------------------------------
[ -n "$FILE" ] || { usage >&2; exit 2; }
[ -r "$FILE" ] || { echo "review-checks: no readable index at '$FILE'" >&2; exit 1; }

ROWS=$(parse_index "$FILE")
if [ -z "$ROWS" ]; then
  echo "review-checks: '$FILE' declares no checks" >&2
  exit 1
fi

if [ -n "$ONLY_CHECK" ]; then
  ROW=$(printf '%s\n' "$ROWS" | awk -F'\t' -v c="$ONLY_CHECK" '$1 == c { print; exit }')
  [ -n "$ROW" ] || { echo "review-checks: '$FILE' does not declare check '$ONLY_CHECK'" >&2; exit 1; }
  printf '%s\n' "$ROW"
  exit 0
fi
printf '%s\n' "$ROWS"
exit 0
