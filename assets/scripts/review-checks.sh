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
# open-as-draft. A check_set token the index does not declare takes pre-open
# (the backstop the dispatcher can act on), never dropped silently — merge
# alone would strand it (see the resolve loop). A declared check with no phase
# also takes pre-open, with a warning. A declared phase outside the ordered set
# is an index error: the resolve refuses it rather than guess a phase.
#
# Index resolution for --resolve: --file wins; else GC_REVIEW_CHECKS_INDEX;
# else --at reads the index a commit carries (git show <oid>:review-checks.toml
# in the toplevel's or GC_RIG_ROOT's repository, fetching the commit from
# origin when neither holds it); else the working-tree review-checks.toml. A
# commit that carries no index falls through to the working tree. A commit
# that no repository here holds or can fetch fails the resolve: another
# tree's index never answers for that head. When no index is readable at all
# (a repo that keeps none), every token is undeclared and takes pre-open, so
# every non-sentinel, non-approval token gates every transition and a readless
# pass never opens an ungated PR. The index text is read through pipes, never
# a scratch file.
#
# The index declares mechanical facts only — a check's name, its method, its
# purpose, its phase. When a check applies to a given diff is a judgment its
# method states in prose, not a column here, so this parser reads no applies-when.
# Callers: signoff.sh, skills/review-triage, pr-open.sh, merge.sh, gate-ensure.sh,
# pr-facts.sh, review-outcome.sh, pr-summary-region.sh, liveness-sweep.sh,
# review-checks.test.sh.
# Exit: 0 ok · 1 no readable index or --check not declared (emit), or a --at
# commit that cannot be read or a declared phase outside the ordered set
# (resolve) · 2 usage.
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

# The index text for --resolve and a name for where it came from; both stay empty
# when no index is readable. The text travels through variables and pipes, never
# a scratch file, so a full TMPDIR cannot turn a readable index into a missing one.
IDX_TEXT=""; IDX_SRC=""
# A full commit id, the only form worth asking origin for by name.
is_oid() {
  case "$1" in ""|*[!0-9a-f]*) return 1 ;; esac
  [ "${#1}" -eq 40 ] || [ "${#1}" -eq 64 ]
}
read_index_file() { # <path> — 0 and IDX_TEXT/IDX_SRC set when it reads
  local t
  [ -r "$1" ] || return 1
  t=$(cat "$1") || return 1
  IDX_TEXT="$t"; IDX_SRC="$1"
}
# Sets IDX_TEXT/IDX_SRC from --file, else the GC_REVIEW_CHECKS_INDEX override,
# else the commit --at names, else the working-tree file. Non-zero only when --at
# names a commit that no repository here holds or can fetch: the caller asked for
# that head's gates, and another tree's index is not an answer for it.
resolve_index() {
  local root at_repo="" t
  local -a roots=() repos=()
  if [ -n "$FILE" ]; then read_index_file "$FILE"; return 0; fi
  # An explicit environment override, authoritative when set: readable, it is the
  # index; unreadable, there is none (every token takes pre-open), never a silent
  # reach past it. It lets a hermetic test fix the index a cadence caller's --at
  # would otherwise resolve from the live checkout.
  if [ -n "${GC_REVIEW_CHECKS_INDEX:-}" ]; then read_index_file "$GC_REVIEW_CHECKS_INDEX"; return 0; fi
  for root in "$(git rev-parse --show-toplevel 2>/dev/null)" "${GC_RIG_ROOT:-}"; do
    [ -n "$root" ] || continue
    roots+=("$root")
    git -C "$root" rev-parse --git-dir >/dev/null 2>&1 && repos+=("$root")
  done
  if [ -n "$AT" ] && [ "${#repos[@]}" -gt 0 ]; then
    for root in "${repos[@]}"; do
      git -C "$root" cat-file -e "$AT^{commit}" 2>/dev/null && { at_repo="$root"; break; }
    done
    # A head pushed since this checkout last fetched is not here yet: fetch it by
    # id, once, rather than read some other commit's index for it.
    if [ -z "$at_repo" ] && is_oid "$AT"; then
      for root in "${repos[@]}"; do
        git -C "$root" fetch --quiet --no-tags --no-write-fetch-head origin "$AT" >/dev/null 2>&1 || continue
        git -C "$root" cat-file -e "$AT^{commit}" 2>/dev/null && { at_repo="$root"; break; }
      done
    fi
    [ -n "$at_repo" ] || return 1
    if t=$(git -C "$at_repo" show "$AT:review-checks.toml" 2>/dev/null) && [ -n "$t" ]; then
      IDX_TEXT="$t"; IDX_SRC="$AT:review-checks.toml"; return 0
    fi
    # The commit carries no index of its own: the working tree's stands in below.
  fi
  for root in ${roots[@]+"${roots[@]}"}; do
    read_index_file "$root/review-checks.toml" && return 0
  done
  return 0
}

if [ "$MODE" = "resolve" ]; then
  [ -n "$CHECK_SET" ] || CHECK_SET=""   # an empty set resolves to no gates
  [ -n "$THROUGH" ] || { echo "review-checks: --resolve needs --through <phase>" >&2; usage >&2; exit 2; }
  THRU_RANK=$(phase_rank "$THROUGH")
  [ -n "$THRU_RANK" ] || { echo "review-checks: --through '$THROUGH' is not a phase (pre-open|open-as-draft|ready-for-review|merge)" >&2; exit 2; }

  if ! resolve_index; then
    warn "commit '$AT' is in no repository here and could not be fetched from origin; the index at that head is unreadable"
    exit 1
  fi
  # name<TAB>phase from the index, the name lowercased for a case-insensitive lookup.
  PHASES=""
  [ -n "$IDX_TEXT" ] && PHASES=$(printf '%s\n' "$IDX_TEXT" | parse_index - | awk -F'\t' '{ print tolower($1) "\t" $4 }')

  emit_one() { # <original-token> <phase>
    if [ -n "$WITH_PHASE" ]; then printf '%s\t%s\n' "$1" "$2"; else printf '%s\n' "$1"; fi
  }

  # Tokenize the check_set, preserving each token's original case (it names a
  # lane), deduping on the lowercased form, dropping the three non-lanes. The loop
  # runs in this shell, so a malformed phase exits the resolve itself.
  seen=""
  while IFS= read -r tok; do
    [ -n "$tok" ] || continue
    low=$(printf '%s' "$tok" | tr '[:upper:]' '[:lower:]')
    case "$low" in none|off|approval) continue ;; esac
    case " $seen " in *" $low "*) continue ;; esac
    seen="$seen $low"
    row=$(printf '%s\n' "$PHASES" | awk -F'\t' -v n="$low" '$1 == n { print "y:" $2; exit }')
    if [ -z "$row" ]; then
      # Undeclared, including every token when there is no index at all: pre-open,
      # the earliest phase and the one gate-ensure dispatches at every stage, so
      # the token always has a path to its review rather than a merge-only gate
      # that could hold the merge with no review ever produced. Pre-open gates
      # every transition, so a live anchor still carrying a legacy token (e.g.
      # `codex`) keeps gating the create and stays satisfiable. Never dropped
      # silently. With no index, the one summary warning below covers every token.
      [ -n "$IDX_SRC" ] && warn "check '$tok' is not declared in the index ($IDX_SRC); defaulting to pre-open"
      emit_one "$tok" pre-open
      continue
    fi
    ph="${row#y:}"
    if [ -z "$ph" ]; then
      # Declared with no phase key, the shape of an index written before the phase
      # column: every declared check of that shape gated the create, so it takes
      # pre-open rather than open the PR ungated.
      warn "check '$tok' is declared with no phase ($IDX_SRC); defaulting to pre-open"
      emit_one "$tok" pre-open
      continue
    fi
    rank=$(phase_rank "$ph")
    if [ -z "$rank" ]; then
      # A phase value outside the ordered set (a misspelling, a wrong case) is an
      # index error, not an absent phase: guessing pre-open would make a
      # merge-phase check gate the create, and guessing merge would open the PR
      # ungated. Refuse, and every caller holds its transition.
      warn "check '$tok' declares phase '$ph', which is not a phase (pre-open|open-as-draft|ready-for-review|merge), in $IDX_SRC; fix the index"
      exit 1
    fi
    if [ "$rank" -le "$THRU_RANK" ]; then emit_one "$tok" "$ph"; fi
  done < <(printf '%s\n' "$CHECK_SET" | tr ',' '\n' | sed 's/[[:space:]]//g; /^$/d')
  [ -n "$IDX_SRC" ] || warn "no readable check index (--file, GC_REVIEW_CHECKS_INDEX, --at and the working tree all came up empty); every non-sentinel token takes pre-open and gates every transition"
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
