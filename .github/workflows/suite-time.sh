#!/usr/bin/env bash
# suite-time.sh — the suite's time, from the seconds `tools/run-tests.sh
# --seconds` keeps for each run. Each tests.yml job that runs the suite shows
# them in its job summary and uploads them as the run's artifact
# suite-times-<job>, and pr-size.sh puts the section below in the size comment
# it keeps on each pull request.
#
# Usage:
#   suite-time.sh summary <file>
#       The job summary: the runs' summed test-seconds, and each run's seconds,
#       slowest first.
#   suite-time.sh section --repo <host/owner/name> --head <commit> --merge-base <commit>
#       The size comment's section on the suite's time, read from the newest
#       tests run of a pull request at the head. It shows each job's time
#       beside the timeout-minutes the head's tests.yml gives it, and each suite
#       job's summed test-seconds beside those of main's latest completed run
#       that recorded them, with the factor between the two. It lists the test
#       files the change adds, with their seconds at the head, the files it
#       removes, with their seconds on main, and the files whose time on test
#       moved by more than 10% and at least 2 seconds. The Linux check is the
#       reference for one file's move because its runs hold within 10% of each
#       other, and a move under 2 seconds can be the rounding of the runner's
#       whole seconds. A head with no run, or with a run that has not finished
#       or ran no job, gets one sentence instead. It runs from inside a checkout
#       that holds both commits.
#
# The seconds come from an artifact the head's own run uploaded, which a change
# can edit, so only lines of the runner's shape are read and nothing from them
# runs. The section names the run and main's commits its numbers come from.
# Nothing here fails a check or holds a merge: the size comment only shows it.
#
# Exit: 0 printed; 1 a read failed, said on stderr; 2 usage.
set -uo pipefail
# Byte order for every sort, whatever the runner's locale.
export LC_ALL=C

PROG=suite-time
WORKFLOW=tests.yml
# The jobs that run the suite, and the one a file's move is read on.
SUITES=(test test-macos)
REF='test'
# The rows a list shows before it says how many more there are.
CAP=20

usage() {
  echo "usage: $PROG summary <file>" >&2
  echo "       $PROG section --repo <host/owner/name> --head <commit> --merge-base <commit>" >&2
  exit 2
}
die() { echo "$PROG: $*" >&2; exit 1; }

# The lines of a seconds file that have the runner's shape: a *.test.sh path
# with an optional [part], whole seconds, and PASS, FAIL[<exit>] or TIMEOUT.
valid() {
  awk -F'\t' 'NF == 3 && $1 ~ /^[A-Za-z0-9._\/-]+\.test\.sh([[][A-Za-z0-9_-]+[]])?$/ &&
    $2 ~ /^[0-9]+$/ && length($2) <= 6 && $3 ~ /^(PASS|TIMEOUT|FAIL[[][0-9]+[]])$/' "$1" 2>/dev/null
}

summary() {
  local rows
  rows=$(valid "$1")
  printf '### Suite time\n\n'
  if [ -z "$rows" ]; then
    printf 'No run recorded its seconds.\n'
    return 0
  fi
  printf '%s\n' "$rows" | awk -F'\t' '{ n++; s += $2 }
    END { printf "%d runs took %d test-seconds. Each run'\''s seconds, slowest first:\n\n", n, s }'
  printf '| Run | Seconds | Status |\n|---|---:|---|\n'
  printf '%s\n' "$rows" | sort -t "$(printf '\t')" -k2,2nr -k1,1 \
    | awk -F'\t' '{ printf "| `%s` | %d | %s |\n", $1, $2, $3 }'
}

[ $# -ge 1 ] || usage
VERB=$1; shift
case "$VERB" in
  summary) [ $# -eq 1 ] || usage; summary "$1"; exit 0 ;;
  section) ;;
  *) usage ;;
esac

REPO_Q="" HEAD="" MB=""
while [ $# -gt 0 ]; do
  [ $# -ge 2 ] || usage
  case "$1" in
    --repo) REPO_Q=$2 ;;
    --head) HEAD=$2 ;;
    --merge-base) MB=$2 ;;
    *) usage ;;
  esac
  shift 2
done
case "$REPO_Q" in */*/*) ;; *) usage ;; esac
[ -n "$HEAD" ] && [ -n "$MB" ] || usage
HOST=${REPO_Q%%/*} REPO=${REPO_Q#*/}
HEAD=$(git rev-parse --verify -q "$HEAD^{commit}") || die "cannot read the head $HEAD"
SHORT=${HEAD:0:12}

TMP=$(mktemp -d "${TMPDIR:-/tmp}/suite-time.XXXXXX") || die "mktemp failed"
trap 'rm -rf "$TMP"' EXIT

# api <path>: GitHub's answer for the path, kept for read_json. A read that
# fails ends the run.
api() { gh api "$1" --hostname "$HOST" > "$TMP/api" 2>/dev/null || die "could not read $1"; }
# read_json <program> <path>: the program's output over the last answer. It
# runs inside $(...), so its caller exits on its failure.
read_json() { jq -r "$1" "$TMP/api" 2>/dev/null || die "could not parse what $2 returned"; }

# download <run> <job> <file>: the job's seconds from the run's artifact, as
# far as they have the runner's shape.
n=0
download() {
  n=$((n + 1))
  gh run download "$1" -R "$REPO_Q" -n "suite-times-$2" -D "$TMP/dl.$n" >/dev/null 2>&1 \
    || die "could not download suite-times-$2 from run $1"
  valid "$TMP/dl.$n/suite-times.tsv" > "$3"
}

# The newest tests run of a pull request at the head.
q="repos/$REPO/actions/workflows/$WORKFLOW/runs?head_sha=$HEAD&event=pull_request&per_page=1"
api "$q"
RUN_LINE=$(read_json '.workflow_runs[0] // empty | [.id, .status, (.conclusion // "none"), .html_url] | @tsv' "$q") || exit 1
if [ -z "$RUN_LINE" ]; then
  printf 'No tests run has tested head `%s`, so the suite'\''s time is not shown.\n' "$SHORT"
  exit 0
fi
IFS=$'\t' read -r RUN STATUS CONCLUSION URL <<<"$RUN_LINE"
case "$RUN" in ''|*[!0-9]*) die "the run list gave no run id" ;; esac
if [ "$STATUS" != completed ]; then
  printf 'The [tests run](%s) at head `%s` has not finished, so the suite'\''s time shows once it does.\n' "$URL" "$SHORT"
  exit 0
fi
if [ "$CONCLUSION" = skipped ]; then
  printf 'The [tests run](%s) at head `%s` ran no job, so the suite'\''s time is not shown.\n' "$URL" "$SHORT"
  exit 0
fi

# Each job's name, conclusion and seconds from start to end, in the run's order.
q="repos/$REPO/actions/runs/$RUN/jobs?per_page=100"
api "$q"
JOBS=$(read_json '.jobs[] | [(.name | gsub("[^A-Za-z0-9_. ()-]"; "?")), (.conclusion // "none"),
  (if .started_at and .completed_at then (.completed_at | fromdateiso8601) - (.started_at | fromdateiso8601) else -1 end)] | @tsv' "$q") || exit 1

# Each job of the head's tests.yml, with the timeout-minutes it sets or nothing:
# a job sits at two spaces under jobs:, and its keys at four.
LIMITS=$(git show "$HEAD:.github/workflows/$WORKFLOW" 2>/dev/null | awk '
  /^jobs:[[:space:]]*$/ { in_jobs = 1; next }
  in_jobs && /^[^[:space:]#]/ { in_jobs = 0 }
  !in_jobs { next }
  /^  [A-Za-z0-9_-]+:[[:space:]]*$/ { job = $1; sub(/:$/, "", job); order[++n] = job; limit[job] = ""; next }
  job != "" && /^    timeout-minutes:/ {
    v = $0; sub(/^    timeout-minutes:[[:space:]]*/, "", v); sub(/[[:space:]]*(#.*)?$/, "", v)
    limit[job] = v
  }
  END { for (i = 1; i <= n; i++) print order[i] "\t" limit[order[i]] }')
# limit_of <job>: its limit in minutes, which is GitHub's 360 for a job that
# sets none, or nothing when the job is not in the file or sets no number.
limit_of() {
  local j v
  while IFS=$'\t' read -r j v; do
    [ -n "$j" ] && [ "$j" = "$1" ] || continue
    [ -n "$v" ] || v=360
    case "$v" in *[!0-9]*) return 1 ;; esac
    printf '%s' "$v"; return 0
  done <<<"$LIMITS"
  return 1
}

# The suite jobs' seconds at the head.
q="repos/$REPO/actions/runs/$RUN/artifacts?per_page=100"
api "$q"
NAMES=$(read_json '.artifacts[] | select(.expired | not) | .name' "$q") || exit 1
NEED=()
for job in "${SUITES[@]}"; do
  : > "$TMP/pr.$job"; : > "$TMP/main.$job"
  grep -qxF "suite-times-$job" <<<"$NAMES" || continue
  download "$RUN" "$job" "$TMP/pr.$job"
  [ -s "$TMP/pr.$job" ] && NEED+=("$job")
done

# Main's seconds for each suite job the head recorded, from the latest
# completed run on main that recorded them. A run cancelled by the next push to
# main can still hold a job that finished, so each job takes its own run.
if [ "${#NEED[@]}" -gt 0 ]; then
  q="repos/$REPO/actions/workflows/$WORKFLOW/runs?branch=main&event=push&status=completed&per_page=10"
  api "$q"
  MAIN_RUNS=$(read_json '.workflow_runs[] | [.id, .head_sha] | @tsv' "$q") || exit 1
  while IFS=$'\t' read -r id sha && [ "${#NEED[@]}" -gt 0 ]; do
    case "$id" in ''|*[!0-9]*) continue ;; esac
    q="repos/$REPO/actions/runs/$id/artifacts?per_page=100"
    api "$q"
    NAMES=$(read_json '.artifacts[] | select(.expired | not) | .name' "$q") || exit 1
    LEFT=()
    for job in "${NEED[@]}"; do
      if grep -qxF "suite-times-$job" <<<"$NAMES"; then
        download "$id" "$job" "$TMP/main.$job"
        printf '%s' "${sha:0:9}" > "$TMP/main.$job.sha"
      else
        LEFT+=("$job")
      fi
    done
    NEED=("${LEFT[@]}")
  done <<<"$MAIN_RUNS"
fi

total() { awk -F'\t' '{ s += $2 } END { print s + 0 }' "$1"; }
is_suite() { local s; for s in "${SUITES[@]}"; do [ "$s" = "$1" ] && return 0; done; return 1; }

printf 'From the [tests run](%s) at head `%s`, beside main'\''s latest completed run that recorded each check'\''s seconds:\n\n' "$URL" "$SHORT"
printf '| Check | Job time | Test-seconds | Main | Factor |\n|---|---|---:|---:|---:|\n'
while IFS=$'\t' read -r name conclusion secs; do
  [ -n "$name" ] || continue
  if [ "$conclusion" = skipped ]; then
    took=skipped
  else
    case "$secs" in ''|-*|*[!0-9]*) took=unknown ;; *) took=$(printf '%dm%02ds' $((secs / 60)) $((secs % 60))) ;; esac
    if limit=$(limit_of "$name"); then took="$took of ${limit}m"; fi
    [ "$conclusion" = success ] || took="$took, $conclusion"
  fi
  here="" main="" factor=""
  if is_suite "$name"; then
    here="none recorded"
    if [ -s "$TMP/pr.$name" ]; then
      here=$(total "$TMP/pr.$name")
      main="none recorded"
      if [ -s "$TMP/main.$name" ]; then
        m=$(total "$TMP/main.$name")
        main="$m at \`$(cat "$TMP/main.$name.sha")\`"
        if [ "$m" -gt 0 ]; then
          f=$(( (here * 100 + m / 2) / m ))
          factor=$(printf '%d.%02d' $((f / 100)) $((f % 100)))
        fi
      fi
    fi
  fi
  printf '| %s | %s | %s | %s | %s |\n' "$name" "$took" "$here" "$main" "$factor"
done <<<"$JOBS"

# The test files the change adds and removes. The run tested the head merged
# with main's tip, so main's run and the head's differ by main's later commits
# too, and only git says which files are the change's.
git diff --name-only --no-renames --diff-filter=A "$MB" "$HEAD" -- '*.test.sh' > "$TMP/added" 2>/dev/null \
  && git diff --name-only --no-renames --diff-filter=D "$MB" "$HEAD" -- '*.test.sh' > "$TMP/removed" 2>/dev/null \
  || die "could not read the change from $MB to $HEAD"

# One line per listed file, sorted: "A" for added and "D" for removed, with the
# file's seconds on each suite job; "M" for a file whose time on REF moved, with
# the size of the move first. A file's parts are summed.
ARGS=()
for job in "${SUITES[@]}"; do ARGS+=(kind=pr "job=$job" "$TMP/pr.$job" kind=main "job=$job" "$TMP/main.$job"); done
LISTS=$(awk -F'\t' -v ref="$REF" -v suites="${SUITES[*]}" '
  kind == "pr" || kind == "main" {
    f = $1; sub(/[[].*$/, "", f)
    s[kind, job, f] += $2
    if (kind == "pr" && job == ref) on_ref[f] = 1
    next
  }
  kind == "add" || kind == "del" {
    f = $0; gsub(/[^A-Za-z0-9._\/-]/, "?", f)
    listed[f] = kind
    line = (kind == "add" ? "A" : "D") "\t0\t" f
    side = (kind == "add" ? "pr" : "main")
    for (i = 1; i <= nsuites; i++) line = line "\t" (((side, sj[i], f) in s) ? s[side, sj[i], f] : "")
    print line
  }
  BEGIN { nsuites = split(suites, sj, " ") }
  END {
    for (f in on_ref) {
      if (f in listed || !(("main", ref, f) in s)) continue
      p = s["pr", ref, f]; m = s["main", ref, f]; d = p - m; a = d < 0 ? -d : d
      if (a >= 2 && a * 10 > m) print "M\t" a "\t" f "\t" m "\t" p
    }
  }' "${ARGS[@]}" kind=add "$TMP/added" kind=del "$TMP/removed" | sort -t "$(printf '\t')" -k1,1 -k2,2nr -k3,3)

# table <kind> <heading> <header row>: the kind's lines as a table under the
# heading, at most CAP rows and then how many more there are.
table() {
  local rows
  rows=$(printf '%s\n' "$LISTS" | awk -F'\t' -v k="$1" '$1 == k')
  [ -n "$rows" ] || return 0
  printf '\n%s\n\n%s\n' "$2" "$3"
  printf '%s\n' "$rows" | awk -F'\t' -v cap="$CAP" -v k="$1" '
    NR <= cap {
      if (k == "M") {
        printf "| `%s` | %d | %d | %s |\n", $3, $4, $5, ($4 > 0 ? sprintf("%.2f", $5 / $4) : "")
      } else {
        line = "| `" $3 "` |"
        for (i = 4; i <= NF; i++) line = line " " $i " |"
        print line
      }
    }
    END { if (NR > cap) printf "\nAnd %d more.\n", NR - cap }'
}
cols=""; rule=""
for job in "${SUITES[@]}"; do cols="$cols $job |"; rule="$rule---:|"; done
table A "Test files the change adds, with their seconds at this head:" "| File |$cols"$'\n'"|---|$rule"
table D "Test files the change removes, with their seconds on main:" "| File |$cols"$'\n'"|---|$rule"
table M "Test files whose time on $REF moved by more than 10% and at least 2 seconds:" \
  "| File | Main | This head | Factor |"$'\n'"|---|---:|---:|---:|"

notes=()
[ -s "$TMP/added" ] || [ -s "$TMP/removed" ] || notes+=("The change adds and removes no test file.")
if [ ! -s "$TMP/pr.$REF" ]; then
  notes+=("No file's move on $REF is shown, because the run at this head recorded no seconds for $REF.")
elif [ ! -s "$TMP/main.$REF" ]; then
  notes+=("No file's move on $REF is shown, because no recent run on main recorded seconds for $REF.")
elif ! grep -q '^M' <<<"$LISTS"; then
  notes+=("No file's time on $REF moved by more than 10% and at least 2 seconds.")
fi
[ "${#notes[@]}" -eq 0 ] || printf '\n%s\n' "${notes[*]}"
exit 0
