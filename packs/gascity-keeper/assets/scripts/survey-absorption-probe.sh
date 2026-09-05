#!/bin/bash
# Evidence generator for the `survey` step of mol-upstream-gc-rebase, and the
# audit that prices how often survey misses what the rebase later finds.
#
# ## What the probe measures
#
# For each divergent commit, how much of what the commit ADDS is already
# present in the upstream copy of the same file, and WHERE. Each added line is
# normalized for whitespace, dropped if it carries no identity (blank,
# bracket-only, comment, under twelve characters), and then looked up verbatim
# in upstream's copy of the file it was added to. The output carries three
# things a surveyor cannot get from `git range-diff`: the containment ratio,
# the upstream line span where the overlap sits, and the added lines that
# upstream does NOT have.
#
# ## Why this reports overlap and never a verdict
#
# Containment is a text test, and text overlap is not absorption. Measured
# across the 31-commit divergent set this was built from, the four commits
# above the default threshold included a commit whose whole point was one
# unmatched line (a GC_/DOLT_ environment filter) inserted into a function
# whose remaining lines are a Go idiom upstream also uses for a different
# purpose. Match locality does not rescue it either: that commit's overlap and
# a true absorption's overlap are both single contiguous upstream runs.
#
# What separates them is what upstream's code MEANS at the overlap, which is a
# reading task. So the probe names the file and line span to read and hands
# over the unmatched remainder, the survey step requires that reading before a
# verdict, and the verdict stays with the surveyor. Treating `overlap: high`
# as a drop would lose local work, which under the upstream-always-wins drop
# policy is the expensive direction to be wrong in.
#
# ## Usage
#
#   survey-absorption-probe.sh --repo <path> --upstream <ref> [--threshold N] <sha>...
#   survey-absorption-probe.sh --repo <path> --upstream <ref> --range <A>..<B>
#   gc bd show <bead> --json | survey-absorption-probe.sh --audit
#
# The probe emits a JSON array on stdout, one object per commit, oldest first,
# always 1:1 with the input. `--audit` instead reads a bead document on stdin
# and reports the commits the survey called `keep` that the rebase loop later
# classified `dropped-absorbed` — the survey miss rate, from the two records
# the rebase already leaves on the bead.
#
# Exit 0 on success, 1 on a usage or git error.
set -uo pipefail

REPO=""
UPSTREAM=""
RANGE=""
THRESHOLD=60
AUDIT=0
SHAS=()

die() { echo "survey-absorption-probe: $1" >&2; exit 1; }

# A value-taking flag must be followed by a value: one more argument, and not
# another flag. There is no `set -e`, so without this guard a trailing value
# flag leaves one argument `shift 2` cannot consume, and the parse loop spins
# on it forever instead of failing closed.
need_val() {
    local flag="$1" count="$2" val="$3"
    [ "$count" -ge 2 ] || die "$flag requires a value"
    case "$val" in -*) die "$flag requires a value, got flag: $val" ;; esac
}

while [ $# -gt 0 ]; do
    case "$1" in
    --repo)      need_val --repo "$#" "${2:-}";      REPO="$2";      shift 2 ;;
    --upstream)  need_val --upstream "$#" "${2:-}";  UPSTREAM="$2";  shift 2 ;;
    --range)     need_val --range "$#" "${2:-}";     RANGE="$2";     shift 2 ;;
    --threshold) need_val --threshold "$#" "${2:-}"; THRESHOLD="$2"; shift 2 ;;
    --audit)     AUDIT=1; shift ;;
    -h|--help)   sed -n '2,48p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)          die "unknown flag: $1" ;;
    *)           SHAS+=("$1"); shift ;;
    esac
done

# --- audit mode ---------------------------------------------------------------
# Both records the audit joins live on the rebase bead already: `commit_verdicts`
# from the survey step and `conflict_resolutions` from the rebase check loop.
# Each is a JSON document stored as a metadata STRING, so each needs a second
# decode. `gc bd show` may print a store banner before the JSON, so the
# document is picked up from its first structural character.
if [ "$AUDIT" -eq 1 ]; then
    BEAD=$(sed -n '/^[[{]/,$p')
    [ -n "$BEAD" ] || die "--audit read no JSON document on stdin"
    printf '%s' "$BEAD" | jq -e 'if type == "array" then .[0] else . end
        | (.metadata.commit_verdicts // "[]" | fromjson) as $verdicts
        | (.metadata.conflict_resolutions // "[]" | fromjson) as $resolutions
        | ($resolutions | map(select(.classification == "dropped-absorbed"))) as $absorbed
        | ($verdicts | map(select(.verdict == "keep"))) as $kept
        | ($absorbed | map(.commit_sha)) as $absorbed_shas
        # The survey builds its verdict table from `git log --oneline`, whose
        # abbreviations vary in length (seven or eight hex here), while the loop
        # records a longer commit_sha; the two are abbreviations of one commit.
        # Match by prefix in either direction so a short kept SHA still joins its
        # longer dropped-absorbed row.
        | ($kept | map(select(.sha as $s | ($s | length) > 0
            and ($absorbed_shas | any(. as $a | ($a | length) > 0
                and (($a | startswith($s)) or ($s | startswith($a)))))))) as $missed
        | {
            bead: .id,
            surveyed: ($verdicts | length),
            kept: ($kept | length),
            absorbed_at_rebase: ($absorbed | length),
            survey_misses: ($missed | length),
            miss_rate_pct: (if ($kept | length) == 0 then 0
                            else (($missed | length) * 100 / ($kept | length) | floor) end),
            missed_commits: ($missed | map({sha, subject, survey_rationale: .rationale}))
          }' || die "--audit could not parse the bead document (commit_verdicts / conflict_resolutions must be JSON)"
    exit 0
fi

# --- probe mode ---------------------------------------------------------------
[ -n "$REPO" ]     || die "--repo is required"
[ -n "$UPSTREAM" ] || die "--upstream is required"
[ -d "$REPO" ]     || die "--repo $REPO is not a directory"
case "$THRESHOLD" in ''|*[!0-9]*) die "--threshold must be an integer" ;; esac

git -C "$REPO" rev-parse --verify "$UPSTREAM^{commit}" >/dev/null 2>&1 \
    || die "--upstream $UPSTREAM does not resolve in $REPO"

if [ -n "$RANGE" ]; then
    [ ${#SHAS[@]} -eq 0 ] || die "--range and explicit shas are mutually exclusive"
    while IFS= read -r sha; do
        [ -n "$sha" ] && SHAS+=("$sha")
    done < <(git -C "$REPO" rev-list --reverse "$RANGE" 2>/dev/null)
    [ ${#SHAS[@]} -gt 0 ] || die "--range $RANGE selected no commits"
fi

[ ${#SHAS[@]} -gt 0 ] || die "no commits given (pass shas or --range)"

# Collapse whitespace runs and trim, so re-indentation never decides
# containment. Applied identically to both sides of every comparison.
normalize() { sed 's/[[:space:]][[:space:]]*/ /g; s/^ //; s/ $//'; }

# A line carries identity when it is long enough to be distinctive and is not
# pure syntax or commentary. A comment prefix missing from this list costs one
# false ELIGIBLE line and never a false match, since a comment can only count
# as matched when upstream carries it verbatim.
carries_identity() {
    local n="$1"
    [ "${#n}" -ge 12 ] || return 1
    case "$n" in
        '//'*|'#'*|'/*'*|'*'*|'--'*|'<!--'*) return 1 ;;
    esac
    case "$n" in
        *[![:punct:][:space:]]*) return 0 ;;
        *) return 1 ;;
    esac
}

# Longest run of consecutive upstream line numbers on stdin (sorted ascending),
# printed as "first-last", or empty when there is no overlap. This is the span
# the surveyor is sent to read.
longest_span() {
    awk '
        { n[NR] = $1 }
        END {
            best = 0; bs = 0; be = 0; run = 1; s = n[1]
            for (i = 2; i <= NR; i++) {
                if (n[i] == n[i-1] + 1) { run++ } else { run = 1; s = n[i] }
                if (run > best) { best = run; bs = s; be = n[i] }
            }
            if (NR == 1) { best = 1; bs = n[1]; be = n[1] }
            if (best > 0) printf "%d-%d", bs, be
        }'
}

printf '['
first_commit=1

upstream_raw=$(mktemp "${TMPDIR:-/tmp}/gctk-survey-absorption.XXXXXX")
upstream_pat=$(mktemp "${TMPDIR:-/tmp}/gctk-survey-absorption.XXXXXX")
eligible_file=$(mktemp "${TMPDIR:-/tmp}/gctk-survey-absorption.XXXXXX")
unmatched_file=$(mktemp "${TMPDIR:-/tmp}/gctk-survey-absorption.XXXXXX")
hits_file=$(mktemp "${TMPDIR:-/tmp}/gctk-survey-absorption.XXXXXX")
trap 'rm -f "$upstream_raw" "$upstream_pat" "$eligible_file" "$unmatched_file" "$hits_file"' EXIT

for SHA in "${SHAS[@]}"; do
    FULL=$(git -C "$REPO" rev-parse --verify "$SHA^{commit}" 2>/dev/null) \
        || die "sha $SHA does not resolve in $REPO"
    SUBJECT=$(git -C "$REPO" log -1 --format=%s "$FULL")

    total_eligible=0
    total_matched=0
    files_json=""
    first_file=1
    : > "$unmatched_file"

    while IFS= read -r f; do
        [ -n "$f" ] || continue

        if git -C "$REPO" cat-file -e "$UPSTREAM:$f" 2>/dev/null; then
            status="present"
            git -C "$REPO" show "$UPSTREAM:$f" | normalize > "$upstream_raw"
            # Blank lines are dropped and duplicates collapsed: neither can
            # match anything here, since matching is whole-line (`-x`) against
            # added lines that are always at least twelve characters, and both
            # only enlarge the pattern file.
            sed '/^$/d' "$upstream_raw" | sort -u > "$upstream_pat"
        else
            status="absent-upstream"
            : > "$upstream_raw"
            : > "$upstream_pat"
        fi

        : > "$eligible_file"
        while IFS= read -r line; do
            n=$(printf '%s\n' "${line#+}" | normalize)
            carries_identity "$n" || continue
            printf '%s\n' "$n" >> "$eligible_file"
        done < <(git -C "$REPO" show --format='' "$FULL" -- "$f" | grep '^+' | grep -v '^+++')

        f_eligible=$(wc -l < "$eligible_file")
        span=""
        if [ -s "$upstream_pat" ] && [ -s "$eligible_file" ]; then
            f_matched=$(grep -cxF -f "$upstream_pat" "$eligible_file" 2>/dev/null || true)
            grep -vxF -f "$upstream_pat" "$eligible_file" >> "$unmatched_file" 2>/dev/null || true
            # Swap the roles to locate the overlap: every upstream line equal to
            # one of the added lines, by line number.
            grep -nxF -f "$eligible_file" "$upstream_raw" 2>/dev/null \
                | cut -d: -f1 > "$hits_file" || true
            [ -s "$hits_file" ] && span=$(longest_span < "$hits_file")
        else
            f_matched=0
            cat "$eligible_file" >> "$unmatched_file"
        fi
        [ -n "$f_matched" ] || f_matched=0

        total_eligible=$((total_eligible + f_eligible))
        total_matched=$((total_matched + f_matched))

        entry=$(jq -nc --arg path "$f" --arg status "$status" --arg span "$span" \
            --argjson eligible "$f_eligible" --argjson matched "$f_matched" \
            '{path:$path, status:$status, eligible:$eligible, matched:$matched,
              upstream_span:(if $span == "" then null else $span end)}')
        [ "$first_file" -eq 1 ] && first_file=0 || files_json="$files_json,"
        files_json="$files_json$entry"
    done < <(git -C "$REPO" show --format='' --name-only "$FULL" | sed '/^$/d')

    if [ "$total_eligible" -eq 0 ]; then
        containment=0
        overlap="no-signal"
    else
        containment=$(( total_matched * 100 / total_eligible ))
        if [ "$containment" -ge "$THRESHOLD" ]; then
            overlap="high"
        elif [ "$total_matched" -gt 0 ]; then
            overlap="partial"
        else
            overlap="none"
        fi
    fi

    # `must_read` is the only thing the probe asserts: this commit's added text
    # overlaps upstream enough that a `keep` verdict is not safe to issue
    # without opening the span. It is not a drop recommendation.
    must_read=false
    [ "$overlap" = "high" ] && must_read=true

    commit_json=$(jq -nc \
        --arg sha "$(git -C "$REPO" rev-parse --short "$FULL")" \
        --arg subject "$SUBJECT" \
        --arg overlap "$overlap" \
        --argjson must_read "$must_read" \
        --argjson eligible "$total_eligible" \
        --argjson matched "$total_matched" \
        --argjson containment "$containment" \
        --argjson files "[$files_json]" \
        --rawfile unmatched "$unmatched_file" \
        '{sha:$sha, subject:$subject, eligible:$eligible, matched:$matched,
          containment:$containment, overlap:$overlap, must_read:$must_read,
          files:$files,
          unmatched_lines:($unmatched | split("\n") | map(select(length > 0)))}')

    [ "$first_commit" -eq 1 ] && first_commit=0 || printf ','
    printf '%s' "$commit_json"
done

printf ']\n'
