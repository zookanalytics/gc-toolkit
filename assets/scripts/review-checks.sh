#!/usr/bin/env bash
# review-checks — the one parser AND resolver of the check index. An index is a
# review-checks.toml that declares each check's name, one line of purpose, and
# the phase it gates. A rig's effective index has two layers:
#
#   The pack's index: the review-checks.toml at the root of the pack this script
#   ships in, two directories above it. It declares every check the pack ships a
#   skill for, so every rig gets every one of them.
#   The rig's index: the review-checks.toml the commit --at names carries, read
#   from the repository of the checkout the caller runs in or GC_RIG_ROOT's, and
#   fetched from origin by id when neither holds the commit. It is optional. A
#   row for a check the pack declares changes that check's purpose or phase, key
#   by key, and a key it leaves out (or leaves empty) keeps the pack's value. A
#   row for any other check adds a check of the rig's own.
#
# A caller names the commit it judges, and the rig's rows come from that commit
# and from nowhere else. A call that names no commit (--at missing or empty) is a
# usage error, so a reader that lost its commit fails instead of resolving under
# the pack's rows alone. Two exceptions name an index outright and stand in for
# both layers: --file <index>, and GC_REVIEW_CHECKS_INDEX, which names the whole
# effective index so a hermetic test fixes what every reader sees. --file wins
# over the variable, and both win over --at.
#
#   review-checks.sh --resolve --check-set <cs> --through <phase> \
#       (--at <oid> | --file <index>) [--with-phase]
#     Emit the checks in <cs> that gate the transition <phase>: every check whose
#     phase is at or before <phase>, one per line, or `<name>\t<phase>` with
#     --with-phase. This is the ONE place that knows none/off are the gateless
#     sentinels and `approval` is a merge rule, not a lane; all three are dropped
#     here so no transition re-derives the drop.
#
#   review-checks.sh --show (--at <oid> | --file <index>)
#   review-checks.sh --check <name> (--at <oid> | --file <index>)
#     Emit the effective index as TSV, one row per check, `<name>\t<purpose>\t<phase>`:
#     every row, or the one row --check names. A check is known by its name
#     case-folded: --check TRIAGE emits the triage row as its index writes it, and
#     a check_set token Correctness resolves by [checks.correctness] but is
#     emitted as written, since it names a lane. A row the pack and a rig both
#     declare keeps the pack's name.
#
#   review-checks.sh --extension <check> --at <oid>
#     Print the rig's guidance for <check>, the docs/review-<check>.md the commit
#     carries, <check> folded to lowercase. A commit that carries none prints
#     nothing and exits 0, the common case. The file exists only at a commit, so
#     this always needs --at, whatever names the index.
#
# Phase ordering: pre-open < open-as-draft < ready-for-review < merge. A check
# that reads only the diff is pre-open; one that needs the deployed preview is
# open-as-draft. A check_set token no layer declares takes pre-open (the backstop
# the dispatcher can act on), never dropped silently: merge alone would strand it
# (see the resolve loop). A declared check with no phase also takes pre-open, with
# a warning. A declared phase outside the ordered set is an index error: the
# resolve of a set naming that check refuses it rather than guess a phase, --check
# of it refuses, and --show leaves it out and names it on stderr. Read at a
# commit, such a row holds only the branches whose commit carries it.
#
# A commit that carries no review-checks.toml adds no rows. A commit that no
# repository here holds or can fetch fails the call: another tree's index never
# answers for that commit. With no repository here at all, there is no rig layer
# to read, and the call says so on stderr. The index text is read through pipes,
# never a scratch file. The `method` key of an older index is ignored: a check's
# method is the skill named from the check.
#
# The index declares mechanical facts only. When a check applies to a given diff
# is a judgment its method states in prose, not a column here.
# Callers: signoff.sh, skills/review-triage, pr-open.sh, gctk merge, gate-ensure.sh,
# pr-facts.sh, review-outcome.sh, pr-summary-region.sh, liveness-sweep.sh,
# review-dispatch-body.sh, review-checks.test.sh.
# Exit: 0 ok · 1 a commit --at names cannot be read, an extension at a readable
# commit cannot be read, --check names a check no layer declares or one whose
# phase is outside the ordered set, a resolved check's phase is outside the
# ordered set, or (emit) no index declares any check · 2 usage, a call that names
# no commit included.
set -uo pipefail

usage() { sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }
warn() { echo "review-checks: $*" >&2; }

HERE="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PACK_INDEX="$(CDPATH='' cd -- "$HERE/../.." && pwd)/review-checks.toml"

MODE=""
FILE=""; ONLY_CHECK=""; CHECK_SET=""; THROUGH=""; AT=""; WITH_PHASE=""; EXT_CHECK=""
set_mode() { # <mode> — one mode per call
  if [ -n "$MODE" ] && [ "$MODE" != "$1" ]; then
    echo "review-checks: --$MODE and --$1 are different calls; name one" >&2; usage >&2; exit 2
  fi
  MODE="$1"
}
while [ $# -gt 0 ]; do
  case "$1" in
    --resolve)     set_mode resolve; shift ;;
    --show)        set_mode show; shift ;;
    --extension)   set_mode extension; EXT_CHECK="${2:-}"; shift 2 || { usage >&2; exit 2; } ;;
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
[ -n "$MODE" ] || MODE=show

# A call names the commit it judges, unless an index is named outright. The
# extension is a file only a commit carries, so nothing stands in for its commit.
if [ -z "$AT" ]; then
  if [ "$MODE" = extension ]; then
    echo "review-checks: --extension needs --at <oid>, the commit whose docs/review-<check>.md it reads" >&2; exit 2
  fi
  if [ -z "$FILE" ] && [ -z "${GC_REVIEW_CHECKS_INDEX:-}" ]; then
    echo "review-checks: no commit named (--at is missing or empty) and no index named (--file, GC_REVIEW_CHECKS_INDEX); a rig's rows are read only at the commit being judged" >&2
    exit 2
  fi
fi

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

# Parse index text on stdin into TSV rows: <name>\t<purpose>\t<phase>. A check is a
# [checks.<name>] table with string keys. The grammar is a minimal TOML subset:
# table headers, `key = "value"` lines, `#` comments, blanks. A value's surrounding
# double quotes are stripped; any other table ends the checks context so a stray
# key outside a [checks.*] header is never read into a check.
parse_index() {
  awk '
    function trim(s) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s }
    function val(l,   v) {
      v = l; sub(/^[^=]*=[[:space:]]*/, "", v)
      v = trim(v)
      sub(/^"/, "", v); sub(/"$/, "", v)
      return v
    }
    function flush() {
      if (name != "") printf "%s\t%s\t%s\n", name, purpose, phase
      name = ""; purpose = ""; phase = ""
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
    name != "" && /^[[:space:]]*purpose[[:space:]]*=/ { purpose = val($0); next }
    name != "" && /^[[:space:]]*phase[[:space:]]*=/   { phase   = val($0); next }
    END { flush() }
  '
}

# Lay rows over rows. Lines tagged P are the pack's and R the rig's; within a
# layer the first row for a name stands. A rig row for a pack check replaces each
# key it gives a value; any other rig row is appended, so the pack's checks come
# first in the pack's order and the rig's own follow in the rig's.
overlay() {
  awk -F'\t' -v OFS='\t' '
    NF < 2 || $2 == "" { next }
    {
      k = tolower($2)
      if ($1 == "P") {
        if (k in pk) next
        pk[k] = 1; ord[++n] = k; nm[k] = $2; pu[k] = $3; ph[k] = $4
        next
      }
      if (k in rk) next
      rk[k] = 1
      if (k in pk) { if ($3 != "") pu[k] = $3; if ($4 != "") ph[k] = $4; next }
      pk[k] = 1; ord[++n] = k; nm[k] = $2; pu[k] = $3; ph[k] = $4
    }
    END { for (i = 1; i <= n; i++) { k = ord[i]; print nm[k], pu[k], ph[k] } }
  '
}

# The repositories a commit is looked for in: the toplevel of the checkout the
# caller runs in, then GC_RIG_ROOT's.
REPOS=()
for root in "$(git rev-parse --show-toplevel 2>/dev/null)" "${GC_RIG_ROOT:-}"; do
  [ -n "$root" ] || continue
  git -C "$root" rev-parse --git-dir >/dev/null 2>&1 && REPOS+=("$root")
done
# A full commit id, the only form worth asking origin for by name.
is_oid() {
  case "$1" in ""|*[!0-9a-f]*) return 1 ;; esac
  [ "${#1}" -eq 40 ] || [ "${#1}" -eq 64 ]
}
# The repository that holds the commit --at names, in AT_REPO. A commit pushed
# since this checkout last fetched is not here yet: it is fetched by id, once,
# rather than some other commit's file read for it. Non-zero when there are
# repositories and none holds or can fetch the commit. With none at all, AT_REPO
# stays empty and the call returns 0: there is no rig layer to read.
AT_REPO=""
find_at_repo() {
  local root
  [ "${#REPOS[@]}" -gt 0 ] || return 0
  for root in "${REPOS[@]}"; do
    git -C "$root" cat-file -e "$AT^{commit}" 2>/dev/null && { AT_REPO="$root"; return 0; }
  done
  if is_oid "$AT"; then
    for root in "${REPOS[@]}"; do
      git -C "$root" fetch --quiet --no-tags --no-write-fetch-head origin "$AT" >/dev/null 2>&1 || continue
      git -C "$root" cat-file -e "$AT^{commit}" 2>/dev/null && { AT_REPO="$root"; return 0; }
    done
  fi
  return 1
}
# The text of <path> at the commit in AT_REPO, in AT_TEXT. 0 and AT_TEXT empty when
# the commit carries no such file; non-zero when it carries one that will not read.
AT_TEXT=""
read_at() { # <path>
  AT_TEXT=""
  git -C "$AT_REPO" cat-file -e "$AT:$1" 2>/dev/null || return 0
  AT_TEXT=$(git -C "$AT_REPO" show "$AT:$1" 2>/dev/null) || return 1
}
no_commit_warning() {
  warn "commit '$AT' is in no repository here and could not be fetched from origin; the rig's files at that commit are unreadable"
}

# --- the extension ------------------------------------------------------------
if [ "$MODE" = extension ]; then
  case "$EXT_CHECK" in
    ""|*[!A-Za-z0-9_-]*) echo "review-checks: --extension takes a check name ([A-Za-z0-9_-]+), got '$EXT_CHECK'" >&2; exit 2 ;;
  esac
  EXT_PATH="docs/review-$(printf '%s' "$EXT_CHECK" | tr '[:upper:]' '[:lower:]').md"
  find_at_repo || { no_commit_warning; exit 1; }
  if [ -z "$AT_REPO" ]; then
    warn "no repository here to read '$AT' from (no checkout toplevel, GC_RIG_ROOT unset); $EXT_PATH went unread"
    exit 1
  fi
  read_at "$EXT_PATH" || { warn "$AT:$EXT_PATH is there but would not read"; exit 1; }
  [ -z "$AT_TEXT" ] || printf '%s\n' "$AT_TEXT"
  exit 0
fi

# --- the effective index ------------------------------------------------------
# ROWS holds it as <name>\t<purpose>\t<phase>; IDX_SRC names what was read, and
# stays empty when nothing was.
ROWS=""; IDX_SRC=""
read_named_index() { # <path> — the whole index; unreadable leaves it empty
  local t
  if [ -r "$1" ] && t=$(cat "$1"); then
    ROWS=$(printf '%s\n' "$t" | parse_index); IDX_SRC="$1"
  fi
}
if [ -n "$FILE" ]; then
  read_named_index "$FILE"
elif [ -n "${GC_REVIEW_CHECKS_INDEX:-}" ]; then
  read_named_index "$GC_REVIEW_CHECKS_INDEX"
else
  PACK_ROWS=""; RIG_ROWS=""
  if [ -r "$PACK_INDEX" ] && PACK_TEXT=$(cat "$PACK_INDEX"); then
    PACK_ROWS=$(printf '%s\n' "$PACK_TEXT" | parse_index); IDX_SRC="$PACK_INDEX"
  fi
  find_at_repo || { no_commit_warning; exit 1; }
  if [ -z "$AT_REPO" ]; then
    warn "no repository here to read '$AT' from (no checkout toplevel, GC_RIG_ROOT unset); no rig rows are read"
  else
    read_at review-checks.toml || { warn "$AT:review-checks.toml is there but would not read"; exit 1; }
    if [ -n "$AT_TEXT" ]; then
      RIG_ROWS=$(printf '%s\n' "$AT_TEXT" | parse_index)
      IDX_SRC="${IDX_SRC:+$IDX_SRC + }$AT:review-checks.toml"
    fi
  fi
  ROWS=$( { [ -z "$PACK_ROWS" ] || printf '%s\n' "$PACK_ROWS" | awk '{ print "P\t" $0 }'
            [ -z "$RIG_ROWS" ]  || printf '%s\n' "$RIG_ROWS"  | awk '{ print "R\t" $0 }'; } | overlay)
fi

# A row's phase as every reader takes it: a missing phase is pre-open, with a
# warning, and a phase outside the ordered set is refused (non-zero) after its
# warning, so no reader guesses one.
row_phase() { # <name> <declared-phase>
  if [ -z "$2" ]; then
    warn "check '$1' is declared with no phase ($IDX_SRC); defaulting to pre-open"
    printf 'pre-open'; return 0
  fi
  if [ -z "$(phase_rank "$2")" ]; then
    warn "check '$1' declares phase '$2', which is not a phase (pre-open|open-as-draft|ready-for-review|merge), in $IDX_SRC; fix the index"
    return 1
  fi
  printf '%s' "$2"
}

if [ "$MODE" = "resolve" ]; then
  [ -n "$THROUGH" ] || { echo "review-checks: --resolve needs --through <phase>" >&2; usage >&2; exit 2; }
  THRU_RANK=$(phase_rank "$THROUGH")
  [ -n "$THRU_RANK" ] || { echo "review-checks: --through '$THROUGH' is not a phase (pre-open|open-as-draft|ready-for-review|merge)" >&2; exit 2; }

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
    row=$(printf '%s\n' "$ROWS" | awk -F'\t' -v n="$low" 'NF && tolower($1) == n { print "y:" $3; exit }')
    if [ -z "$row" ]; then
      # Undeclared, including every token when no index read at all: pre-open,
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
    # A phase outside the ordered set (a misspelling, a wrong case) is an index
    # error, not an absent phase: guessing pre-open would make a merge-phase check
    # gate the create, and guessing merge would open the PR ungated. Refuse, and
    # every caller holds its transition.
    ph=$(row_phase "$tok" "${row#y:}") || exit 1
    if [ "$(phase_rank "$ph")" -le "$THRU_RANK" ]; then emit_one "$tok" "$ph"; fi
  done < <(printf '%s\n' "$CHECK_SET" | tr ',' '\n' | sed 's/[[:space:]]//g; /^$/d')
  [ -n "$IDX_SRC" ] || warn "no readable check index (the pack's index, the commit's and any index named outright all came up empty); every non-sentinel token takes pre-open and gates every transition"
  exit 0
fi

# --- emit mode (the TSV) -------------------------------------------------------
if [ -z "$ROWS" ]; then
  if [ -n "$IDX_SRC" ]; then echo "review-checks: '$IDX_SRC' declares no checks" >&2
  elif [ -n "$FILE" ]; then echo "review-checks: no readable index at '$FILE'" >&2
  else echo "review-checks: no readable check index" >&2; fi
  exit 1
fi

# The rows are split on the unit separator, which a TOML string here never
# carries: tab is whitespace to read, which would fold an empty purpose away.
emit_row() { # <tsv-row> — 0 printed, non-zero when its phase is refused
  local name purpose declared ph
  IFS=$'\037' read -r name purpose declared <<< "$(printf '%s' "$1" | tr '\t' '\037')"
  ph=$(row_phase "$name" "$declared") || return 1
  printf '%s\t%s\t%s\n' "$name" "$purpose" "$ph"
}
if [ -n "$ONLY_CHECK" ]; then
  ROW=$(printf '%s\n' "$ROWS" | awk -F'\t' -v c="$ONLY_CHECK" 'NF && tolower($1) == tolower(c) { print; exit }')
  [ -n "$ROW" ] || { echo "review-checks: '$IDX_SRC' does not declare check '$ONLY_CHECK'" >&2; exit 1; }
  emit_row "$ROW" || exit 1
  exit 0
fi
while IFS= read -r row; do
  [ -n "$row" ] || continue
  # A refused row is not on the menu; its warning names it.
  emit_row "$row" || continue
done <<< "$ROWS"
exit 0
