#!/usr/bin/env bash
# doctor-finding-gate — the close-time gate for beads that name a `gc doctor`
# finding. Close-on-land closes a bead when its PR merges; nothing between the
# merge and the close re-runs the check, so "merged" silently reads as "fixed".
# This gate re-asks doctor at close time. It never REFUSES a close (closed
# means landed); it annotates a partial one and names the successor.
#   probe <bead-id>      names of checks this bead names that STILL FIRE.
#                        exit 0 none (clean) · 1 some (partial) · 2 indeterminate
#   successor <check>    print an OPEN bead tracking <check>, minting one
#                        (keyed on metadata.doctor_check, so convergent).
#   publish [<file>|-]   install a validated `gc doctor --json` payload at the
#                        shared cache so probes answer without a doctor run.
# A bead "names" a check via metadata.doctor_check, or any whole token in its
# title/description/notes that INTERSECTS what doctor actually reported —
# never a shape match, which would cry wolf on check-shaped prose.
# Fail-soft: every unreadable input exits 2 and prints nothing — a false
# "still firing" files a successor against a defect that is fixed.
# Callers: the refinery close arm (--no-run probe), the deacon patrol (publish).
set -uo pipefail

# Each command handler stages its payload in a temp file and removes it on
# every branch it can reach. A signal reaches none of them, and only one
# handler runs per invocation, so one registered path covers both.
DFG_TMP=""
trap 'rm -f "$DFG_TMP" 2>/dev/null' EXIT
trap 'exit 130' INT; trap 'exit 143' TERM; trap 'exit 129' HUP

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload. All but
# LF go: raw TAB and CR do not occur in bd/gh output, and the TAB-splitting
# consumers downstream split jq's own @tsv, emitted after this runs.
scrub() { tr -d '\000-\011\013-\037'; }
# <<< control-char-scrub

usage() {
  cat >&2 <<'USAGE'
usage: doctor-finding-gate.sh probe <bead-id> [--json <file>] [--cache <file>]
                                              [--ttl <seconds>] [--no-run]
       doctor-finding-gate.sh successor <check-name> [--pool <pool>]
                                                     [--source <bead-id>]
       doctor-finding-gate.sh publish [<file>|-] [--cache <file>]
USAGE
}

# Where a payload is cached between callers (the deacon patrol writes it).
default_cache() {
  if [ -n "${GC_DOCTOR_GATE_CACHE:-}" ]; then
    printf '%s' "$GC_DOCTOR_GATE_CACHE"
  elif [ -n "${GC_CITY_RUNTIME_DIR:-}" ]; then
    printf '%s' "$GC_CITY_RUNTIME_DIR/doctor-findings.json"
  elif [ -n "${GC_CITY:-}" ]; then
    printf '%s' "$GC_CITY/.gc/runtime/doctor-findings.json"
  else
    printf '%s' "${TMPDIR:-/tmp}/gc-doctor-findings.json"
  fi
}

# Long TTL by design: a stale payload costs one disposable false successor; a
# short one costs a multi-minute doctor run inside the refinery's idle loop.
DEFAULT_TTL=3600
# Live-run bound; under ~300s doctor returns rc 124 and an empty payload.
DOCTOR_TIMEOUT="${GC_DOCTOR_GATE_TIMEOUT:-300}"

# file_age_seconds <path> — seconds since mtime, or empty if it cannot be read.
# GNU and BSD stat disagree on the flag, and neither is guaranteed here.
file_age_seconds() {
  local f="$1" mtime="" now
  now=$(date +%s 2>/dev/null) || return 1
  mtime=$(stat -c %Y "$f" 2>/dev/null) \
    || mtime=$(stat -f %m "$f" 2>/dev/null) \
    || return 1
  case "$mtime" in ''|*[!0-9]*) return 1 ;; esac
  printf '%s' "$((now - mtime))"
}

# Usable = parses AND carries .results: a drifted schema reads as "every
# check is green", which would certify every close as clean.
payload_ok() {
  [ -s "$1" ] || return 1
  jq -e 'type == "object" and (.results | type == "array")' "$1" >/dev/null 2>&1
}

# Write beside the target and rename (atomic within one directory): a reader
# must never observe a partial payload — missing checks read as green.
install_cache() {
  local src="$1" cache="$2" dir tmp
  dir=$(dirname "$cache" 2>/dev/null) || return 1
  [ -n "$dir" ] || return 1
  mkdir -p "$dir" 2>/dev/null || return 1
  tmp="$cache.$$"
  if cp "$src" "$tmp" 2>/dev/null && mv -f "$tmp" "$cache" 2>/dev/null; then
    return 0
  fi
  rm -f "$tmp" 2>/dev/null
  return 1
}

cmd_probe() {
  local bead="" json="" cache="" ttl="$DEFAULT_TTL" norun=""
  bead="${1:-}"; shift || true
  [ -n "$bead" ] || { usage; return 2; }
  while [ $# -gt 0 ]; do
    case "$1" in
      --json)  json="${2:-}";  if [ $# -ge 2 ]; then shift 2; else shift; fi ;;
      --cache) cache="${2:-}"; if [ $# -ge 2 ]; then shift 2; else shift; fi ;;
      --ttl)   ttl="${2:-}";   if [ $# -ge 2 ]; then shift 2; else shift; fi ;;
      --no-run) norun=1; shift ;;
      *) shift ;;
    esac
  done
  case "$ttl" in ''|*[!0-9]*) ttl="$DEFAULT_TTL" ;; esac
  [ -n "$cache" ] || cache="$(default_cache)"

  command -v jq >/dev/null 2>&1 || return 2

  # Control bytes stripped: an unparseable bead must not read as "no bead".
  local row
  row=$(gc bd show "$bead" --json 2>/dev/null | scrub)
  [ -n "$row" ] || return 2
  jq -e 'type == "array" and length > 0' <<<"$row" >/dev/null 2>&1 || return 2

  local explicit text
  explicit=$(jq -r '.[0].metadata.doctor_check // "" | tostring' <<<"$row" 2>/dev/null)
  text=$(jq -r '.[0] | [(.title // ""), (.description // ""), (.notes // "")]
                       | map(tostring) | join(" ")' <<<"$row" 2>/dev/null)

  # Whole tokens over a check name's character class ([A-Za-z0-9:_-]): keeps
  # `check-set` from matching `check-set-heal`.
  local norm
  norm=" $(printf '%s %s' "$text" "$explicit" | tr -c 'A-Za-z0-9:_-' ' ' | tr -s ' ') "

  # The pre-filter only decides whether to PAY for a live run, never what to
  # report. Both shapes a check-prefixed name arrives in are plausible — bare
  # `check-x` at a word boundary and namespaced `gc-toolkit:check-x` — else a
  # cold-cache --no-run probe reads a namespaced-only bead as clean instead of
  # indeterminate.
  local plausible=""
  [ -n "$explicit" ] && plausible=1
  [ -z "$plausible" ] && case "$norm" in *" check-"*|*":check-"*) plausible=1 ;; esac

  # --- resolve a payload. ------------------------------------------------------
  local payload="" ran=""
  if [ -n "$json" ]; then
    payload_ok "$json" || return 2
    payload="$json"
  elif [ -n "${GC_DOCTOR_JSON:-}" ] && payload_ok "${GC_DOCTOR_JSON}"; then
    payload="${GC_DOCTOR_JSON}"
  else
    local age
    age=$(file_age_seconds "$cache" 2>/dev/null)
    if [ -n "$age" ] && [ "$age" -le "$ttl" ] && payload_ok "$cache"; then
      payload="$cache"
    elif [ -z "$plausible" ]; then
      # Nothing cached, nothing check-shaped: CLEAN, not unknown. Ordered
      # before --no-run so routine closes never read indeterminate.
      return 0
    elif [ -n "$norun" ]; then
      # Plausible, but this caller may not spend minutes finding out:
      # INDETERMINATE, never clean.
      return 2
    else
      # `gc doctor` exits 1 when findings exist — normal here; only the
      # payload's shape decides usability.
      local tmp
      tmp=$(mktemp "${TMPDIR:-/tmp}/gctk-doctor-finding-gate.XXXXXX" 2>/dev/null) || return 2
      DFG_TMP="$tmp"
      timeout "$DOCTOR_TIMEOUT" gc doctor --json >"$tmp" 2>/dev/null
      if payload_ok "$tmp"; then
        payload="$tmp"; ran="$tmp"
        install_cache "$tmp" "$cache" || true
      else
        rm -f "$tmp" 2>/dev/null
        return 2
      fi
    fi
  fi

  # FIRING = status outside the settled-green set (an exclusion: an unknown
  # future status must read as firing).
  local matched
  matched=$(jq -r --arg norm "$norm" '
      [ .results[]?
        | select((.name // "") != "")
        | select(((.status // "") | ascii_downcase) as $s
                 | ([ "ok", "pass", "passed", "skipped", "fixed", "n/a", "na" ]
                    | index($s)) | not)
        | .name ]
      | unique
      | map(select(. as $n
            | ($norm | contains(" " + $n + " "))
              or (($n | split(":") | last) as $bare
                  | $bare != $n and ($norm | contains(" " + $bare + " ")))))
      | .[]' "$payload" 2>/dev/null)

  [ -z "$ran" ] || rm -f "$ran" 2>/dev/null
  DFG_TMP=""

  [ -n "$matched" ] || return 0
  printf '%s\n' "$matched"
  return 1
}

cmd_successor() {
  local check="" pool="" source_bead=""
  check="${1:-}"; shift || true
  [ -n "$check" ] || { usage; return 2; }
  while [ $# -gt 0 ]; do
    case "$1" in
      --pool)   pool="${2:-}";        if [ $# -ge 2 ]; then shift 2; else shift; fi ;;
      --source) source_bead="${2:-}"; if [ $# -ge 2 ]; then shift 2; else shift; fi ;;
      *) shift ;;
    esac
  done
  command -v jq >/dev/null 2>&1 || return 2

  # Exact lookup on the metadata this script stamps; every non-closed status
  # is a live successor. ONE comma-separated --status: bd keeps only the last
  # repeated flag.
  local existing raw
  raw=$(gc bd list --status=open,in_progress,blocked \
          --metadata-field "doctor_check=$check" --limit=20 --json 2>/dev/null \
        | scrub)
  # An unreadable ledger is NOT an empty one.
  if [ -n "$raw" ]; then
    jq -e 'type == "array"' <<<"$raw" >/dev/null 2>&1 || return 2
    existing=$(jq -r '.[0].id // empty' <<<"$raw" 2>/dev/null)
    if [ -n "$existing" ]; then printf '%s\n' "$existing"; return 0; fi
  else
    return 2
  fi

  local title body id
  title="doctor check $check still fires after its fix bead closed"
  body="$(cat <<EOF
\`gc doctor\` still reports **$check** as a live finding after a bead filed
against it closed. Filed mechanically by the close-time doctor-finding gate
(assets/scripts/doctor-finding-gate.sh)${source_bead:+ when $source_bead closed}.
The predecessor merged; what is in question is whether it CLOSED THE FINDING,
and doctor says it did not.

## What to do

1. Re-run the check:
   \`gc doctor --json | jq '.results[] | select(.name == "$check")'\`
2. GREEN now? Close this bead — a false alarm the gate is supposed to produce.
3. Still firing? Fix what it reports. Read the predecessor's diff first: the
   recurring failure is a PR that improves the CHECK without remediating the
   STATE it checks.
4. Re-run the check before closing. This bead carries
   \`metadata.doctor_check=$check\`, so the gate annotates its own close too.
EOF
)"
  id=$(printf '%s' "$body" \
       | gc bd create "$title" -t task --body-file - --json 2>/dev/null \
       | jq -r '.id // empty' 2>/dev/null)
  # A title-only bead is a degraded but honest successor.
  [ -n "$id" ] || id=$(gc bd create "$title" -t task --json 2>/dev/null \
                       | jq -r '.id // empty' 2>/dev/null)
  [ -n "$id" ] || return 2

  # An ARRAY, not ${var:+--set-metadata "k=$v"}: that expansion word-splits
  # and leaves literal quotes in the stamped values.
  local -a meta=(--set-metadata "doctor_check=$check")
  [ -z "$source_bead" ] || meta+=(--set-metadata "doctor_finding_predecessor=$source_bead")
  [ -z "$pool" ] || meta+=(--set-metadata "gc.routed_to=$pool")
  gc bd update "$id" "${meta[@]}" >/dev/null 2>&1 || true
  printf '%s\n' "$id"
  return 0
}

cmd_publish() {
  local src="" cache=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --cache) cache="${2:-}"; if [ $# -ge 2 ]; then shift 2; else shift; fi ;;
      -) src="-"; shift ;;
      *) [ -n "$src" ] || src="$1"; shift ;;
    esac
  done
  command -v jq >/dev/null 2>&1 || return 2
  [ -n "$cache" ] || cache="$(default_cache)"

  # Buffer first: stdin is not seekable and validation precedes the cache.
  local tmp rc=2
  tmp=$(mktemp "${TMPDIR:-/tmp}/gctk-doctor-finding-gate.XXXXXX" 2>/dev/null) || return 2
  DFG_TMP="$tmp"
  if [ -n "$src" ] && [ "$src" != "-" ]; then
    cat -- "$src" >"$tmp" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; return 2; }
  else
    cat >"$tmp" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; return 2; }
  fi

  # Validate before installing: an empty payload installed here answers every
  # later probe "no check is firing". Refusing keeps the previous cache.
  if payload_ok "$tmp" && install_cache "$tmp" "$cache"; then
    printf '%s\n' "$cache"
    rc=0
  fi
  rm -f "$tmp" 2>/dev/null
  DFG_TMP=""
  return "$rc"
}

case "${1:-}" in
  probe)     shift; cmd_probe "$@" ;;
  successor) shift; cmd_successor "$@" ;;
  publish)   shift; cmd_publish "$@" ;;
  *) usage; exit 2 ;;
esac
