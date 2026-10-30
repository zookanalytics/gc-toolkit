#!/usr/bin/env bash
# Hermetic test for merge-push's zero-diff guard (the `zero-diff-guard` block of
# formulas/mol-refinery-patrol.toml) across two patrol attempts at one direct
# landing.
#
# The guard parks a bead whose branch introduces no change against its target
# as refused_false_completion. A direct landing whose push lands and whose
# record fails leaves that shape behind, because origin/<target> then carries
# the branch. direct-merge-push.sh stamps direct_landing_sha on the bead before
# it pushes, and the guard sends a bead whose target carries the stamp down the
# direct path, which records the landing.
#
# Each attempt runs the real blocks, extracted verbatim from the formula, in the
# order a patrol runs them: the rebase step's shared-branch-merge-mode, then
# merge-push's branch-has-real-change, zero-diff-guard and, for a direct bead,
# direct-merge-push. A few lines stand in for merge-push's opening read, which
# gives the guard the bead, the strategy and lifecycle.sh. The gate between the
# two steps judges the prepared head and decides nothing here, so it is left
# out. The blocks run against real git repositories, the real
# direct-merge-push.sh, refinery-workspace.sh, detached-job.sh, bd-lib.sh,
# await-ruling.sh and deferred-dispatch.sh, a stub gc that keeps the beads and
# their edges in files, a stub lifecycle.sh that logs, and a stub escalate.sh
# that logs and files its visit. They run from a directory that is no git
# checkout, as a refinery's scratch directory is, so every git call has to name
# the rig by path.
# Proves:
#   - an attempt that pushes and then cannot record leaves the landing on
#     origin, the stamp on the bead and the branch on origin, and the next
#     attempt stages the branch again and records the landing at the stamped
#     commit without parking, escalating or draining, whether origin/main
#     stayed at the landing or moved on past it, and whatever strategy the
#     bead reads by then; the branch is deleted once the landing is recorded;
#   - a branch that never introduced work is still refused, parked and
#     escalated, with no stamp and with a stamp its target does not carry, and
#     so is a branch whose commits net to no change;
#   - a check that cannot run leaves the work with the refinery to retry,
#     counting the failures in a row on the bead. The third files a visit with
#     the verdict window off, which says the check could not run and names
#     git's error and the directory, never that the branch has no change. The
#     work then waits on that visit, with no lifecycle park and no
#     merge_result: a blocks edge onto the visit, the refinery's assignment
#     released and a fresh mol-polecat-work pour armed, which the
#     deferred-dispatch pass holds while the visit is open and pours once it
#     closes. A graduated convoy, which no pour rebuilds, is parked blocked
#     instead, held by a blocks edge onto the visit, with no pour armed;
#   - a visit that is not filed, a pack without await-ruling.sh, a wait whose
#     edge or arm does not land, and a convoy whose edge does not land or
#     whose park lifecycle.sh refuses each leave the work assigned to the
#     refinery and counted at the cap, the refinery taking back an
#     assignment the wait released, and the next failed check's wait lands.
#     A take-back that fails says the work is stranded. A check that runs
#     clears the count.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TOML="$ROOT/formulas/mol-refinery-patrol.toml"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-unrecorded-direct-landing-test.XXXXXX")"
# git names the prep worktree under the repository's resolved path, so every
# path is built on a resolved root.
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1${2:+ ($2)}"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3" "got '$1' want '$2'"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3" "missing '$2' in: $1" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3" "found '$2' in: $1" ;; *) ok "$3" ;; esac; }

command -v git >/dev/null 2>&1 || { echo "git is required" >&2; exit 1; }
command -v jq  >/dev/null 2>&1 || { echo "jq is required"  >&2; exit 1; }
[ -s "$TOML" ] || { echo "missing $TOML" >&2; exit 1; }

unset GC_RIG_ROOT GC_RIG GC_CITY GC_CITY_PATH GC_PACK_DIR GC_BD_LIB GC_RECONCILE_BD_CACHE 2>/dev/null || true
unset DIRECT_MERGE_PUSH_ATTEMPTS DIRECT_MERGE_PUSH_BACKOFF 2>/dev/null || true
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR 2>/dev/null || true
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

# A block comes out with {{binding_prefix}} rendered as the patrol fills it in:
# the binding it was poured with, gc-toolkit. here.
fence() { awk -v m="$1" '$0 ~ ("# >>> " m "$") {f=1; next} $0 ~ ("# <<< " m "$") {f=0} f' "$TOML" | sed 's|{{binding_prefix}}|gc-toolkit.|g'; }

echo "── the blocks ──"
for m in shared-branch-merge-mode branch-has-real-change zero-diff-guard direct-merge-push; do
  if [ -n "$(fence "$m")" ]; then ok "$m: extracted between its markers"; else bad "$m: extracted between its markers"; fi
done
fence shared-branch-merge-mode > "$TMP/prep.sh"
# delete_merged_branches takes the patrol's default, true.
{
  echo 'BEAD_JSON=$(gc bd show $WORK --json)'
  echo 'MERGE_STRATEGY="$STRATEGY"'
  echo 'LC="${TEST_LC:-$(gc gc-toolkit scripts-dir)/lifecycle.sh}"'
  fence branch-has-real-change
  fence zero-diff-guard
  echo 'if [ "$MERGE_STRATEGY" = direct ]; then'
  fence direct-merge-push | sed 's|{{delete_merged_branches}}|true|g'
  echo 'fi'
  echo 'echo "MERGE_STRATEGY=$MERGE_STRATEGY"'
} > "$TMP/merge-push.sh"
for f in prep merge-push; do
  case "$(cat "$TMP/$f.sh")" in
    *'{{'*) bad "$f: no unrendered formula placeholder left" ;;
    *)      ok  "$f: no unrendered formula placeholder left" ;;
  esac
  if bash -n "$TMP/$f.sh" 2>/dev/null; then ok "$f: valid bash"; else bad "$f: valid bash"; fi
done

# bare_git <file>: the first argument of every git invocation that does not
# start with -C, outside comment lines.
bare_git() {
  awk '
    /^[[:space:]]*#/ { next }
    {
      line = $0
      while (match(line, "(^|[^-.A-Za-z0-9_/])git[[:space:]]+[^[:space:]]+")) {
        n = split(substr(line, RSTART, RLENGTH), w, "[[:space:]]+")
        if (w[n] != "-C") print w[n]
        line = substr(line, RSTART + RLENGTH)
      }
    }' "$1" | tr '\n' ' '
}
fence branch-has-real-change > "$TMP/bhrc.sh"
fence zero-diff-guard > "$TMP/zdg.sh"
eq "$(bare_git "$TMP/bhrc.sh")" "" "branch-has-real-change: every git call names its repo with -C"
eq "$(bare_git "$TMP/zdg.sh")" "" "zero-diff-guard: every git call names its repo with -C, and its script lookup reads no cwd checkout"

# The pack the blocks find their scripts in, which gc names.
CITY="$TMP/city"
PACK="$CITY/rigs/gc-toolkit/assets/scripts"
mkdir -p "$PACK" "$TMP/bin"
cp "$HERE/direct-merge-push.sh" "$HERE/bd-lib.sh" "$HERE/refinery-workspace.sh" "$HERE/detached-job.sh" "$HERE/rig-root.sh" \
  "$HERE/await-ruling.sh" "$HERE/deferred-dispatch.sh" "$HERE/hold-lib.sh" "$PACK/"
cat > "$PACK/lifecycle.sh" <<'LC'
#!/usr/bin/env bash
echo "$*" >> "$FAKE_LC_LOG"
[ -z "${LC_FAIL:-}" ] || { echo "lifecycle: refused" >&2; exit 1; }
exit 0
LC
# escalate logs its argv and the verdict window it ran under. With FAKE_STORE
# set it files the visit as the real one does: an open visit routed to human,
# keyed by the situation and the subject, with a tracks edge onto the subject,
# and a call for a situation already open files nothing. ESC_FAIL refuses.
cat > "$PACK/escalate.sh" <<'ESC'
#!/usr/bin/env bash
echo "escalate $*" >> "$FAKE_LOG"
echo "escalate-window ${GC_ESCALATE_VERDICT_WINDOW-unset}" >> "$FAKE_LOG"
[ -z "${ESC_FAIL:-}" ] || { echo "escalate: could not file the visit (stub)" >&2; exit 1; }
[ -n "${FAKE_STORE:-}" ] || exit 0
subject=""; key=""; message=""
while [ $# -gt 0 ]; do
  case "$1" in
    --subject) subject="$2"; shift 2 ;;
    --key)     key="$2"; shift 2 ;;
    --message) message="$2"; shift 2 ;;
    *) shift ;;
  esac
done
open=$(jq --arg k "$key" --arg s "$subject" '[ .[] | select(.status == "open" and .metadata.escalation_key == $k and .metadata["gc.continuation_group"] == $s) ] | length' "$FAKE_STORE")
[ "$open" = 0 ] || exit 0
id="visit$(( $(jq 'length' "$FAKE_STORE") + 1 ))"
jq -c --arg id "$id" --arg k "$key" --arg s "$subject" --arg t "${message%%. *}" \
  '. + [{id: $id, status: "open", assignee: "", title: $t, metadata: {task_kind: "visit", escalation_key: $k, "gc.continuation_group": $s, "gc.routed_to": "human"}}]' \
  "$FAKE_STORE" > "$FAKE_STORE.new" && mv "$FAKE_STORE.new" "$FAKE_STORE"
printf '%s|tracks|%s\n' "$id" "$subject" >> "$FAKE_DEPS"
ESC
chmod +x "$PACK"/*.sh
# gc names the pack for `gc gc-toolkit scripts-dir` and answers the roster for
# `rig list`. The work bead is the one row of the
# bead file; FAKE_STORE, when set, holds every other bead, and FAKE_DEPS the
# edges, one "A|type|B" line for "A depends on B". `bd show` answers a row, or
# bd's error object for an id it does not hold. `bd list` filters on --status,
# --id, --has-metadata-key and each --metadata-field, answers with --ready only
# an open bead whose every blocks edge names a closed bead, leaves closed beads
# out unless --all or a status names them, and gives each row its edges in the
# listing shape. `bd dep
# list` answers a bead's edges in the show shape, and `bd dep add` records one
# unless FAKE_DEP_FAIL is set. `bd unclaim --if-assignee` is bd's
# compare-and-swap release. `bd update` refuses with exit 13 and writes nothing
# when an --if-assignee or --if-status guard does not hold, refuses an arm's
# write (one setting gc.dispatch_when_ready) when FAKE_ARM_WRITE_FAIL is set and
# an assignment when FAKE_ASSIGN_FAIL is set, and otherwise applies --status,
# --assignee, --set-metadata, --unset-metadata and --append-notes to the work
# bead. Every call but a read is logged. A `--db <path>` pin is dropped.
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
if [ "$1" = bd ] && [ "${2:-}" = --db ]; then set -- bd "${@:4}"; fi
work_id() { jq -r '.[0].id' "$FAKE_META"; }
rows() {
  if [ -n "${FAKE_STORE:-}" ] && [ -s "$FAKE_STORE" ]; then jq -s -c '.[0] + .[1]' "$FAKE_META" "$FAKE_STORE"; else jq -c . "$FAKE_META"; fi
}
edges() {
  { [ -n "${FAKE_DEPS:-}" ] && [ -f "$FAKE_DEPS" ] && cat "$FAKE_DEPS"; } | jq -R -s -c 'split("\n") | map(select(length > 0) | split("|") | {from: .[0], type: .[1], to: .[2]})'
}
case "$1 ${2:-}" in
  "gc-toolkit scripts-dir") [ -n "${STUB_PACK:-}" ] || exit 1; printf '%s/assets/scripts\n' "$STUB_PACK" ;;
  "rig list") cat "$FAKE_ROSTER" ;;
  "bd show")
    if [ "${3:-}" = "$(work_id)" ]; then cat "$FAKE_META"
    else
      row=$(rows | jq -c --arg id "${3:-}" '[ .[] | select(.id == $id) ]')
      if [ "$row" = "[]" ]; then printf '{"error":"no issue found matching %s"}\n' "${3:-}"; else printf '%s\n' "$row"; fi
    fi ;;
  "bd list")
    shift 2
    st=""; ids=""; all=""; hk=""; ready=""; mfs="[]"
    while [ $# -gt 0 ]; do
      case "$1" in
        --status=*) st="${1#--status=}" ;;
        --id=*) ids="${1#--id=}" ;;
        --id) shift; ids="${1:-}" ;;
        --all) all=1 ;;
        --ready) ready=1 ;;
        --has-metadata-key) shift; hk="${1:-}" ;;
        --metadata-field) shift; mfs=$(printf '%s' "$mfs" | jq -c --arg kv "${1:-}" '. + [{k: ($kv | sub("=.*$"; "")), v: ($kv | sub("^[^=]*="; ""))}]') ;;
      esac
      shift
    done
    # --ready answers an open bead whose every blocks edge names a closed bead.
    rows | jq -c --argjson e "$(edges)" --argjson mf "$mfs" --arg st "$st" --arg ids "$ids" --arg all "$all" \
        --arg hk "$hk" --arg ready "$ready" '
      . as $rows
      | [ .[] | . as $b
        | .dependencies = [ $e[] | select(.from == $b.id) | {depends_on_id: .to, type: .type} ]
        | select(if $st != "" then ((($st | split(",")) | index($b.status // "open")) != null)
                 elif $all == "" then ($b.status // "open") != "closed" else true end)
        | select($ids == "" or ((($ids | split(",")) | index($b.id)) != null))
        | select($hk == "" or ((($b.metadata // {}) | type) == "object" and (($b.metadata // {}) | has($hk))))
        | select($ready == "" or (($b.status // "open") == "open"
            and ([ $e[] | select(.from == $b.id and .type == "blocks") | .to as $t
                   | $rows[] | select(.id == $t and (.status // "open") != "closed") ] | length) == 0))
        | select(all($mf[]; (($b.metadata[.k] // "") | tostring) == .v)) ]' ;;
  "bd dep")
    case "${3:-}" in
      list)
        rows | jq -c --argjson e "$(edges)" --arg id "${4:-}" '
          . as $r | [ $e[] | select(.from == $id) | . as $x | ($r[] | select(.id == $x.to)) as $b
            | {id: $x.to, dependency_type: $x.type, status: ($b.status // "open"), title: ($b.title // "")} ]' ;;
      add)
        echo "$*" >> "$FAKE_LOG"
        [ -z "${FAKE_DEP_FAIL:-}" ] || { echo "bd: refused the edge (stub)" >&2; exit 1; }
        t=blocks
        for x in "$@"; do case "$x" in --type=*) t="${x#--type=}" ;; esac; done
        printf '%s|%s|%s\n' "${4:-}" "$t" "${5:-}" >> "$FAKE_DEPS" ;;
      *) echo "$*" >> "$FAKE_LOG" ;;
    esac ;;
  "bd unclaim")
    echo "$*" >> "$FAKE_LOG"
    id="${3:-}"; want=""
    shift 3
    while [ $# -gt 0 ]; do
      case "$1" in --if-assignee) shift; want="${1:-}" ;; --if-assignee=*) want="${1#*=}" ;; esac
      shift
    done
    held=$(jq -r '.[0].assignee // ""' "$FAKE_META")
    if [ "$id" != "$(work_id)" ] || [ -z "$want" ] || [ "$held" != "$want" ]; then
      echo "Error unclaiming $id: held by \"$held\", expected \"$want\" (stub)" >&2; exit 1
    fi
    jq -c '.[0].status = "open" | .[0].assignee = ""' "$FAKE_META" > "$FAKE_META.new" && mv "$FAKE_META.new" "$FAKE_META" ;;
  "bd update")
    echo "$*" >> "$FAKE_LOG"
    [ "${3:-}" = "$(work_id)" ] || exit 0
    shift 3
    for x in "$@"; do
      case "$x" in gc.dispatch_when_ready=*) [ -z "${FAKE_ARM_WRITE_FAIL:-}" ] || { echo "bd: store fault (stub)" >&2; exit 1; } ;; esac
    done
    args=("$@")
    i=0
    while [ "$i" -lt "${#args[@]}" ]; do
      case "${args[$i]}" in
        --if-assignee|--if-status)
          f="${args[$i]#--if-}"; i=$((i + 1))
          [ "$(jq -r --arg f "$f" '.[0][$f] // ""' "$FAKE_META")" = "${args[$i]:-}" ] || { echo "bd: the $f guard did not hold (stub)" >&2; exit 13; } ;;
        --assignee) [ -z "${FAKE_ASSIGN_FAIL:-}" ] || [ -z "${args[$((i + 1))]:-}" ] || { echo "bd: refused the assignment (stub)" >&2; exit 1; } ;;
      esac
      i=$((i + 1))
    done
    while [ $# -gt 0 ]; do
      case "$1" in
        --status|--assignee)
          jq -c --arg f "${1#--}" --arg v "${2:-}" '.[0][$f] = $v' "$FAKE_META" > "$FAKE_META.new" && mv "$FAKE_META.new" "$FAKE_META"
          shift 2 ;;
        --status=*|--assignee=*)
          f="${1%%=*}"
          jq -c --arg f "${f#--}" --arg v "${1#*=}" '.[0][$f] = $v' "$FAKE_META" > "$FAKE_META.new" && mv "$FAKE_META.new" "$FAKE_META"
          shift ;;
        --set-metadata)
          jq --arg kv "$2" '.[0].metadata[($kv | sub("=.*$"; ""))] = ($kv | sub("^[^=]*="; ""))' "$FAKE_META" > "$FAKE_META.new" \
            && mv "$FAKE_META.new" "$FAKE_META"
          shift 2 ;;
        --unset-metadata)
          jq --arg k "$2" 'del(.[0].metadata[$k])' "$FAKE_META" > "$FAKE_META.new" && mv "$FAKE_META.new" "$FAKE_META"
          shift 2 ;;
        --append-notes)
          jq --arg n "$2" '.[0].notes = ((.[0].notes // "") + $n)' "$FAKE_META" > "$FAKE_META.new" && mv "$FAKE_META.new" "$FAKE_META"
          shift 2 ;;
        --if-assignee|--if-status) shift 2 ;;
        *) shift ;;
      esac
    done ;;
  *) echo "$*" >> "$FAKE_LOG" ;;
esac
exit 0
GC
chmod +x "$TMP/bin/gc"
export PATH="$TMP/bin:$PATH"

# The cwd every block runs from: a directory git finds no repository in, as in
# a scratch directory under the system temp dir.
ELSEWHERE="$TMP/elsewhere"
mkdir -p "$ELSEWHERE"
if git -C "$ELSEWHERE" rev-parse --git-dir >/dev/null 2>&1; then
  bad "precondition: the blocks' cwd is no git checkout" "$ELSEWHERE is inside one"
else
  ok "precondition: the blocks' cwd is no git checkout"
fi

# commit <repo> <message>: a commit that adds a file, since the guard judges a
# branch by the change in its tree.
commit() {
  printf '%s\n' "$2" > "$1/${2// /-}"
  git -C "$1" add -A
  git -C "$1" commit -q -m "$2"
  git -C "$1" rev-parse HEAD
}
stamp() { jq -r '.[0].metadata.direct_landing_sha // "none"' "$D/bead.json"; }
on_origin() { if git -C "$D/origin.git" rev-parse -q --verify "refs/heads/$1" >/dev/null; then echo yes; else echo no; fi; }
merged_tries() { grep -c '^transition wb --to merged ' "$D/lc.log"; }

# fixture <dir> work|nowork|netzero: origin with main at BASE and polecat/wb
# one commit ahead of it (work), at BASE itself (nowork), or two commits ahead
# whose second removes what the first added (netzero), the rig cloned from it,
# and a direct-strategy bead. Sets D, BASE, FEATURE and PREP.
fixture() {
  D="$1"
  mkdir -p "$D"
  git init -q --bare -b main "$D/origin.git"
  git init -q -b main "$D/seed"
  BASE=$(commit "$D/seed" "base")
  git -C "$D/seed" push -q "$D/origin.git" main
  git -C "$D/seed" checkout -q -b polecat/wb
  case "$2" in
    work) FEATURE=$(commit "$D/seed" "feature") ;;
    netzero)
      commit "$D/seed" "added then removed" >/dev/null
      git -C "$D/seed" rm -q added-then-removed
      git -C "$D/seed" commit -q -m "remove it again"
      FEATURE=$(git -C "$D/seed" rev-parse HEAD) ;;
    *) FEATURE="$BASE" ;;
  esac
  git -C "$D/seed" push -q "$D/origin.git" polecat/wb
  git -C "$D/seed" checkout -q main
  git clone -q "$D/origin.git" "$D/rig"
  PREP="$(git -C "$D/rig" rev-parse --path-format=absolute --git-common-dir)/gc-refinery-prep"
  printf '{"rigs":[{"name":"myrig","path":"%s"}]}\n' "$D/rig" > "$D/roster.json"
  printf '%s\n' '[{"id":"wb","status":"in_progress","metadata":{"branch":"polecat/wb","target":"main","merge_strategy":"direct"}}]' > "$D/bead.json"
}

# attempt [<env>...]: one patrol's prepare, then its merge-push, both from a
# directory that is no checkout, the bead read as a direct one unless STRATEGY
# says otherwise.
# The logs start over, so each attempt's assertions read only its own calls.
# Sets PREP_RC, RC and OUT.
attempt() {
  : > "$D/gc.log"; : > "$D/lc.log"
  local run=(env GC_RIG_ROOT="$D/rig" GC_RIG=myrig STUB_PACK="$CITY/rigs/gc-toolkit" WORK=wb BRANCH=polecat/wb TARGET=main
    TARGET_BRANCH_DEFAULT=main FAKE_ROSTER="$D/roster.json" FAKE_META="$D/bead.json" FAKE_LOG="$D/gc.log"
    FAKE_LC_LOG="$D/lc.log" DIRECT_MERGE_PUSH_BACKOFF=0 STRATEGY=direct "$@")
  ( cd "$ELSEWHERE" && "${run[@]}" bash "$TMP/prep.sh" ) >"$D/prep.out" 2>&1; PREP_RC=$?
  OUT=$(cd "$ELSEWHERE" && "${run[@]}" bash "$TMP/merge-push.sh" 2>&1); RC=$?
}
recorded_at() { # <label> <sha>: one transition, recording and closing at <sha>
  case "$(cat "$D/lc.log")" in
    "transition wb --to merged --close --set merged_sha=$2 --set merged_target=main --unset rejection_reason --unset direct_landing_sha --append-notes Merged to main at "*)
      ok "$1: recorded and closed at ${2:0:9} through one lifecycle transition" ;;
    *) bad "$1: recorded and closed at ${2:0:9} through one lifecycle transition" "$(cat "$D/lc.log")" ;;
  esac
}
not_parked() { # <label>: no refusal, no escalation, no drain
  hasnt "$(cat "$D/lc.log")" "refused_false_completion" "$1: the bead is not parked as a false completion"
  hasnt "$(cat "$D/gc.log")" "escalate " "$1: nothing is escalated"
  hasnt "$(cat "$D/gc.log")" "runtime drain-ack" "$1: the session does not drain"
}
# unrecorded_landing <label>: the first attempt, whose record never lands.
unrecorded_landing() {
  attempt LC_FAIL=1
  eq "$PREP_RC" 0 "$1, first attempt: the prepare stages the branch"
  eq "$RC" 1 "$1, first attempt: merge-push stops"
  eq "$(git -C "$D/origin.git" rev-parse main)" "$FEATURE" "$1, first attempt: the push landed on origin/main"
  eq "$(merged_tries)" 3 "$1, first attempt: the record was tried three times"
  eq "$(stamp)" "$FEATURE" "$1, first attempt: the bead keeps the stamp"
  eq "$(on_origin polecat/wb)" yes "$1, first attempt: the branch stays on origin for the next attempt to stage"
  hasnt "$(cat "$D/lc.log")" "refused_false_completion" "$1, first attempt: the bead is not parked as a false completion"
}

echo "── a landing whose record failed: the next patrol records it ──"
fixture "$TMP/same" work
unrecorded_landing same
attempt
eq "$PREP_RC" 0 "same, next attempt: the prepare stages the branch"
eq "$(git -C "$PREP" rev-parse HEAD)" "$FEATURE" "same, next attempt: precondition, the prepared head is origin/main's tip, the landing"
eq "$RC" 0 "same, next attempt: merge-push exits 0"
has "$OUT" "pushed without recording; taking the direct path to record it" "same, next attempt: the guard names the unrecorded landing"
recorded_at "same, next attempt" "$FEATURE"
not_parked "same, next attempt"
eq "$(git -C "$D/origin.git" rev-parse main)" "$FEATURE" "same, next attempt: origin/main is unchanged"
eq "$(on_origin polecat/wb)" no "same, next attempt: the branch is deleted once the landing is recorded"

echo "── the same, after origin/main moved on past the landing ──"
fixture "$TMP/later" work
unrecorded_landing later
git -C "$D/seed" fetch -q "$D/origin.git" main
git -C "$D/seed" checkout -q -B main FETCH_HEAD
LATER=$(commit "$D/seed" "landed after the unrecorded landing")
git -C "$D/seed" push -q "$D/origin.git" main
attempt
eq "$(git -C "$PREP" rev-parse HEAD)" "$LATER" "later, next attempt: precondition, the prepared head is the later tip"
eq "$RC" 0 "later, next attempt: merge-push exits 0"
recorded_at "later, next attempt (the landing, not the later tip)" "$FEATURE"
not_parked "later, next attempt"

echo "── the same, when the next attempt reads the bead as mr ──"
fixture "$TMP/mr" work
unrecorded_landing mr
attempt STRATEGY=mr
eq "$RC" 0 "mr, next attempt: merge-push exits 0"
has "$OUT" "MERGE_STRATEGY=direct" "mr, next attempt: the guard sends the bead down the direct path"
recorded_at "mr, next attempt" "$FEATURE"
not_parked "mr, next attempt"

echo "── a branch that never introduced work is refused ──"
fixture "$TMP/nowork" nowork
attempt
eq "$PREP_RC" 0 "nowork: the prepare stages the branch"
eq "$RC" 1 "nowork: merge-push stops"
has "$(cat "$D/lc.log")" "transition wb --to refused_false_completion" "nowork: the bead is parked as a false completion"
has "$(cat "$D/gc.log")" "escalate --subject wb --key refinery-false-completion" "nowork: the refusal is escalated"
has "$(cat "$D/gc.log")" "runtime drain-ack" "nowork: the session drains"
eq "$(merged_tries)" 0 "nowork: nothing is recorded as merged"
eq "$(git -C "$D/origin.git" rev-parse main)" "$BASE" "nowork: nothing is pushed"

echo "── the same, with a stamp the target does not carry ──"
fixture "$TMP/stale" nowork
git -C "$D/seed" checkout -q -b side "$BASE"
SIDE=$(commit "$D/seed" "a push that never landed")
git -C "$D/seed" push -q "$D/origin.git" side
jq --arg s "$SIDE" '.[0].metadata.direct_landing_sha = $s' "$D/bead.json" > "$D/bead.json.new" && mv "$D/bead.json.new" "$D/bead.json"
attempt
eq "$RC" 1 "stale: merge-push stops"
has "$(cat "$D/lc.log")" "transition wb --to refused_false_completion" "stale: the bead is parked as a false completion"
has "$(cat "$D/gc.log")" "escalate --subject wb --key refinery-false-completion" "stale: the refusal is escalated"
eq "$(merged_tries)" 0 "stale: nothing is recorded as merged"
eq "$(git -C "$D/origin.git" rev-parse main)" "$BASE" "stale: nothing is pushed"

echo "── a refusal files its visit through the pack lifecycle.sh came from ──"
# The refinery sits in a scratch directory, GC_RIG_ROOT is unset so the rig
# comes from the roster, and GC_CITY_PATH names no pack. GC_PACK_DIR holds
# rig-root.sh alone, so the block resolves the rig, and the only place that
# names the rest of the pack is the lifecycle.sh the step found.
RR_ONLY="$TMP/rig-root-only"
mkdir -p "$RR_ONLY/assets/scripts"
cp "$HERE/rig-root.sh" "$RR_ONLY/assets/scripts/"
fixture "$TMP/nopack" nowork
: > "$D/gc.log"; : > "$D/lc.log"
( cd "$ELSEWHERE" && env GC_RIG_ROOT="$D/rig" GC_RIG=myrig GC_CITY_PATH="$CITY" WORK=wb BRANCH=polecat/wb TARGET=main \
    TARGET_BRANCH_DEFAULT=main FAKE_ROSTER="$D/roster.json" FAKE_META="$D/bead.json" FAKE_LOG="$D/gc.log" \
    FAKE_LC_LOG="$D/lc.log" bash "$TMP/prep.sh" ) >"$D/prep.out" 2>&1; PREP_RC=$?
eq "$PREP_RC" 0 "nopack: the prepare stages the branch"
nopack_merge_push() { # <lifecycle.sh> [<GC_PACK_DIR>]
  : > "$D/gc.log"; : > "$D/lc.log"
  OUT=$(cd "$ELSEWHERE" && env GC_PACK_DIR="${2-$RR_ONLY}" GC_RIG_ROOT="" GC_RIG=myrig GC_CITY_PATH="" TEST_LC="$1" WORK=wb BRANCH=polecat/wb \
    TARGET=main FAKE_ROSTER="$D/roster.json" FAKE_META="$D/bead.json" FAKE_LOG="$D/gc.log" FAKE_LC_LOG="$D/lc.log" \
    STRATEGY=direct bash "$TMP/merge-push.sh" 2>&1); RC=$?
}
nopack_merge_push "$PACK/lifecycle.sh"
eq "$RC" 1 "nopack: merge-push stops"
has "$(cat "$D/lc.log")" "transition wb --to refused_false_completion" "nopack: the bead is parked as a false completion"
has "$(cat "$D/gc.log")" "escalate --subject wb --key refinery-false-completion" "nopack: the refusal files its visit"
# A lifecycle.sh with no escalate.sh beside it, and no other pack location:
# the park stands, and the block says no visit was filed.
mkdir -p "$TMP/lc-only/assets/scripts"
cp "$PACK/lifecycle.sh" "$TMP/lc-only/assets/scripts/lifecycle.sh"
nopack_merge_push "$TMP/lc-only/assets/scripts/lifecycle.sh"
eq "$RC" 1 "nopack/no escalate.sh: merge-push stops"
has "$(cat "$D/lc.log")" "transition wb --to refused_false_completion" "nopack/no escalate.sh: the bead is parked as a false completion"
hasnt "$(cat "$D/gc.log")" "escalate " "nopack/no escalate.sh: no visit is filed"
has "$OUT" "is parked for a human with no refinery-false-completion visit" "nopack/no escalate.sh: the block says the park has no visit"
# With no pack location at all, rig-root.sh is not found, so the rig does not
# resolve: the block stops before the check, parks nothing and leaves the work
# with the refinery to retry.
nopack_merge_push "$PACK/lifecycle.sh" ""
eq "$RC" 1 "nopack/no rig-root.sh: merge-push stops"
has "$OUT" "cannot resolve the rig root; leaving the work with the refinery to retry" "nopack/no rig-root.sh: the block says the rig did not resolve"
hasnt "$(cat "$D/lc.log")" "transition" "nopack/no rig-root.sh: nothing is parked"
hasnt "$(cat "$D/gc.log")" "escalate " "nopack/no rig-root.sh: nothing is escalated"
has "$(cat "$D/gc.log")" "runtime drain-ack" "nopack/no rig-root.sh: the session drains"

echo "── a branch whose commits net to no change is refused ──"
fixture "$TMP/netzero" netzero
attempt
eq "$PREP_RC" 0 "netzero: the prepare stages the branch"
eq "$(git -C "$PREP" rev-list --count "$BASE..HEAD" 2>/dev/null || echo 0)" 2 "netzero: precondition, the prepared head is two commits ahead of the target"
eq "$RC" 1 "netzero: merge-push stops"
has "$(cat "$D/lc.log")" "transition wb --to refused_false_completion" "netzero: the bead is parked as a false completion"
has "$(cat "$D/gc.log")" "escalate --subject wb --key refinery-false-completion" "netzero: the refusal is escalated"
eq "$(merged_tries)" 0 "netzero: nothing is recorded as merged"
eq "$(git -C "$D/origin.git" rev-parse main)" "$BASE" "netzero: nothing is pushed"

echo "── a check that cannot run is retried, then waits on a visit as a failed check, not as a branch without work ──"
REFINERY=gc-toolkit/gc-toolkit.refinery
POOL=gc-toolkit/gc-toolkit.polecat
# nocheck_fixture <dir>: a branch with work, on a bead in the shape a polecat's
# hand-off leaves it: open, assigned to the refinery, the pool its pour ran on
# still recorded. The prepare stages the branch, then the rig loses
# origin/main, so the check cannot find the merge-base it needs on any patrol
# until it returns. The store of other beads and the edge file start empty.
nocheck_fixture() {
  fixture "$1" work
  jq -c --arg a "$REFINERY" --arg p "$POOL" \
    '.[0].status = "open" | .[0].assignee = $a | .[0].metadata["gc.execution_routed_to"] = $p' \
    "$D/bead.json" > "$D/bead.json.new" && mv "$D/bead.json.new" "$D/bead.json"
  printf '[]\n' > "$D/store.json"; : > "$D/deps.txt"; : > "$D/gc.log"; : > "$D/lc.log"
  NOCHECK_ENV=(env GC_RIG_ROOT="$D/rig" GC_RIG=myrig GC_CITY_PATH="$CITY" GC_AGENT="$REFINERY" WORK=wb BRANCH=polecat/wb
    TARGET=main TARGET_BRANCH_DEFAULT=main FAKE_ROSTER="$D/roster.json" FAKE_META="$D/bead.json"
    FAKE_STORE="$D/store.json" FAKE_DEPS="$D/deps.txt" FAKE_LOG="$D/gc.log" FAKE_LC_LOG="$D/lc.log" STRATEGY=direct)
  ( cd "$ELSEWHERE" && "${NOCHECK_ENV[@]}" bash "$TMP/prep.sh" ) >"$D/prep.out" 2>&1; PREP_RC=$?
  git -C "$D/rig" update-ref -d refs/remotes/origin/main
}
fails() { jq -r '.[0].metadata.zero_diff_check_failures // "none"' "$D/bead.json"; }
field() { jq -r --arg f "$1" '.[0][$f] // ""' "$D/bead.json"; }
meta() { jq -r --arg k "$1" '.[0].metadata[$k] // "<absent>"' "$D/bead.json"; }
visit_of() { jq -r '[ .[] | select(.metadata.escalation_key == "refinery-zero-diff-check-failed") | .id ] | .[0] // ""' "$D/store.json"; }
# nocheck_merge_push [<env>...]: one patrol's merge-push, its logs started over.
nocheck_merge_push() {
  : > "$D/gc.log"; : > "$D/lc.log"
  OUT=$(cd "$ELSEWHERE" && "${NOCHECK_ENV[@]}" "$@" bash "$TMP/merge-push.sh" 2>&1); RC=$?
}
# armed_state: the work's arm as the real deferred-dispatch.sh list reads it,
# through the hold definition its reconcile pass slings by.
armed_state() { (cd "$ELSEWHERE" && "${NOCHECK_ENV[@]}" bash "$PACK/deferred-dispatch.sh" list 2>&1) | grep '^wb -> ' || true; }
nocheck_fixture "$TMP/nocheck"
eq "$PREP_RC" 0 "nocheck: the prepare stages the branch"
for n in 1 2; do
  nocheck_merge_push
  eq "$RC" 1 "nocheck, patrol $n: merge-push stops"
  has "$OUT" "the zero-diff check could not run in $D/rig: merge-base origin/main " \
    "nocheck, patrol $n: it says the check could not run, in the rig, and names the failed git call"
  has "$OUT" "Not a valid object name origin/main (failure $n of 3 in a row); leaving the work with the refinery to retry" \
    "nocheck, patrol $n: it carries git's own error and leaves the work with the refinery"
  eq "$(cat "$D/lc.log")" "" "nocheck, patrol $n: the bead is not parked"
  hasnt "$(cat "$D/gc.log")" "escalate " "nocheck, patrol $n: nothing is escalated"
  has "$(cat "$D/gc.log")" "runtime drain-ack" "nocheck, patrol $n: the session drains"
  eq "$(fails)" "$n" "nocheck, patrol $n: the bead counts $n failed check(s) in a row"
  eq "$(field assignee)" "$REFINERY" "nocheck, patrol $n: the work stays assigned to the refinery"
done
nocheck_merge_push
VISIT=$(visit_of)
eq "$RC" 1 "nocheck, patrol 3: merge-push stops"
eq "$(cat "$D/lc.log")" "" "nocheck, patrol 3: no lifecycle transition parks the bead"
has "$(cat "$D/gc.log")" "escalate --subject wb --key refinery-zero-diff-check-failed --message The zero-diff check of branch polecat/wb against origin/main could not run in $D/rig, 3 patrols in a row. The last error: merge-base origin/main " \
  "nocheck, patrol 3: the visit is a failed-check situation, naming the directory, the count and the failed git call"
has "$(cat "$D/gc.log")" "Not a valid object name origin/main. It verified nothing either way" \
  "nocheck, patrol 3: the visit carries git's own error, its trailing newline not left as a space before the rest"
has "$(cat "$D/gc.log")" "escalate-window 0" "nocheck, patrol 3: the visit is filed with the verdict window off, so the wait has an open visit to sit on"
hasnt "$(cat "$D/gc.log")" "refinery-false-completion" "nocheck, patrol 3: the visit is not a no-change situation"
if [ -n "$VISIT" ]; then ok "nocheck, patrol 3: the visit is filed"; else bad "nocheck, patrol 3: the visit is filed" "$(cat "$D/store.json")"; fi
eq "$(grep -cxF "wb|blocks|$VISIT" "$D/deps.txt")" 1 "nocheck, patrol 3: the work is blocked by its visit"
eq "$(field status) $(field assignee)" "open " "nocheck, patrol 3: the refinery's assignment is released, so find-work no longer offers the work"
eq "$(meta gc.dispatch_when_ready)" "$POOL" "nocheck, patrol 3: a fresh pour is armed to the pool the work's last pour ran on"
eq "$(meta gc.dispatch_when_ready_args)" '["--on","mol-polecat-work"]' "nocheck, patrol 3: the pour is a mol-polecat-work run"
eq "$(meta merge_result)" "<absent>" "nocheck, patrol 3: no merge_result, which the pour's load-context would read as finished work"
eq "$(meta gc.routed_to)" "" "nocheck, patrol 3: the work is routed nowhere"
eq "$(meta blocked_reason) $(meta gc.takeaway)" "<absent> <absent>" "nocheck, patrol 3: no hold marker is written beside the edge"
eq "$(fails)" none "nocheck, patrol 3: the wait clears the count"
has "$(field notes)" "Refinery: the zero-diff check of polecat/wb could not run in $D/rig, 3 patrols in a row (merge-base origin/main " \
  "nocheck, patrol 3: a note on the work says why it waits and what closing the visit does"
has "$OUT" "wb waits on visit $VISIT (refinery-zero-diff-check-failed); closing the visit re-slings it to $POOL --on mol-polecat-work" \
  "nocheck, patrol 3: the patrol says what the work waits on and what releases it"
has "$(cat "$D/gc.log")" "runtime drain-ack" "nocheck, patrol 3: the session drains"
eq "$(merged_tries)" 0 "nocheck: nothing is recorded as merged"
eq "$(git -C "$D/origin.git" rev-parse main)" "$BASE" "nocheck: nothing is pushed"

echo "── closing the visit lets the armed pour take the work ──"
has "$(armed_state)" "wb -> $POOL [HELD by $VISIT" "nocheck, visit open: the deferred-dispatch pass holds the pour on the visit"
jq -c --arg v "$VISIT" 'map(if .id == $v then .status = "closed" else . end)' "$D/store.json" > "$D/store.json.new" \
  && mv "$D/store.json.new" "$D/store.json"
has "$(armed_state)" "wb -> $POOL [DISPATCHABLE NOW]" "nocheck, visit closed: the deferred-dispatch pass pours the work on its next pass"

echo "── a visit or a wait that does not land leaves the work with the refinery ──"
# third_failure <dir>: the nocheck fixture with two failed checks counted, so
# the next patrol meets the third.
third_failure() {
  nocheck_fixture "$1"
  jq -c '.[0].metadata.zero_diff_check_failures = "2"' "$D/bead.json" > "$D/bead.json.new" && mv "$D/bead.json.new" "$D/bead.json"
}
# kept <label>: the work is open and assigned to the refinery, counted at the
# cap and armed nowhere, nothing parks it, and the session drains.
kept() {
  eq "$RC" 1 "$1: merge-push stops"
  eq "$(field status) $(field assignee)" "open $REFINERY" "$1: the work stays assigned to the refinery, so the next patrol takes it up"
  eq "$(fails)" 3 "$1: the count stays at the cap, so the next failed check asks again"
  eq "$(meta gc.dispatch_when_ready)" "<absent>" "$1: no pour is armed"
  eq "$(cat "$D/lc.log")" "" "$1: no lifecycle transition parks the bead"
  has "$OUT" "the wait did not land, so wb stays with the refinery, and the next patrol checks it again" "$1: the patrol says the work stays with the refinery"
  has "$(cat "$D/gc.log")" "runtime drain-ack" "$1: the session drains"
}
third_failure "$TMP/noesc"
nocheck_merge_push ESC_FAIL=1
kept "escalation refused"
has "$OUT" "escalate.sh recorded no visit for wb" "escalation refused: the patrol says no visit was filed"
eq "$(jq length "$D/store.json")" 0 "escalation refused: no visit exists"
eq "$(grep -c . "$D/deps.txt" || true)" 0 "escalation refused: no edge is written"
hasnt "$(cat "$D/gc.log")" "bd unclaim" "escalation refused: the assignment is never released"

# A lifecycle.sh whose pack holds escalate.sh and no await-ruling.sh. The block
# takes both from one pack, so it files no visit that no wait could follow.
third_failure "$TMP/noawait"
mkdir -p "$TMP/esc-only/assets/scripts"
cp "$PACK/lifecycle.sh" "$PACK/escalate.sh" "$TMP/esc-only/assets/scripts/"
nocheck_merge_push TEST_LC="$TMP/esc-only/assets/scripts/lifecycle.sh"
kept "no await-ruling.sh"
has "$OUT" "escalate.sh and await-ruling.sh were not found together beside $TMP/esc-only/assets/scripts/lifecycle.sh or in any pack location, so no visit asks about wb" \
  "no await-ruling.sh: the patrol says no visit was filed"
hasnt "$(cat "$D/gc.log")" "escalate " "no await-ruling.sh: no visit is filed"

third_failure "$TMP/noedge"
nocheck_merge_push FAKE_DEP_FAIL=1
kept "edge refused"
eq "$(jq length "$D/store.json")" 1 "edge refused: precondition, the visit is filed"
hasnt "$(cat "$D/gc.log")" "bd unclaim" "edge refused: the wait stops before it releases the assignment"

# The arm is refused after the wait has released the assignment, so the
# refinery has to take the work back.
third_failure "$TMP/noarm"
nocheck_merge_push FAKE_ARM_WRITE_FAIL=1
kept "arm refused"
has "$(cat "$D/gc.log")" "bd unclaim wb --if-assignee $REFINERY" "arm refused: precondition, the wait released the assignment before the arm"
has "$(cat "$D/gc.log")" "bd update wb --if-assignee  --if-status open --assignee $REFINERY" "arm refused: the refinery takes the released work back"
# The next patrol fails the check again, and its wait lands.
nocheck_merge_push
eq "$(jq '[ .[] | select(.metadata.escalation_key == "refinery-zero-diff-check-failed") ] | length' "$D/store.json")" 1 \
  "arm refused, next patrol: the open visit answers again, and no second one is filed"
eq "$(grep -cF "wb|blocks|" "$D/deps.txt")" 1 "arm refused, next patrol: the edge already in place is not written again"
eq "$(field status) $(field assignee)" "open " "arm refused, next patrol: the work is released to wait"
eq "$(meta gc.dispatch_when_ready)" "$POOL" "arm refused, next patrol: the pour is armed to the pool the first wait recorded"
eq "$(fails)" none "arm refused, next patrol: the wait clears the count"

# The refinery cannot take the released work back either, so it says the work
# is stranded and how to hand it back.
third_failure "$TMP/notaken"
nocheck_merge_push FAKE_ARM_WRITE_FAIL=1 FAKE_ASSIGN_FAIL=1
eq "$RC" 1 "take-back refused: merge-push stops"
eq "$(field assignee)" "" "take-back refused: precondition, the work is left unassigned"
has "$OUT" "the wait did not land, and wb could not be left with the refinery (its assignee reads nobody), so nothing takes it up again; assign it to $REFINERY once the check can run" \
  "take-back refused: the patrol names the stranded work and its hand-back"
has "$(cat "$D/gc.log")" "runtime drain-ack" "take-back refused: the session drains"

echo "── a graduated convoy is parked on its visit, since no pour rebuilds a convoy ──"
# convoy_failure <dir>: the third failure, on a graduated convoy that carries the
# pool its design pour ran on, as graduated convoys do.
convoy_failure() {
  third_failure "$1"
  jq -c '.[0].issue_type = "convoy" | .[0].metadata.graduation = "true"' "$D/bead.json" > "$D/bead.json.new" \
    && mv "$D/bead.json.new" "$D/bead.json"
}
convoy_failure "$TMP/convoy"
nocheck_merge_push
VISIT=$(visit_of)
eq "$RC" 1 "convoy: merge-push stops"
has "$(cat "$D/lc.log")" "transition wb --to blocked --assignee  --route human --set blocked_reason=the zero-diff check could not run in $D/rig, 3 patrols in a row: merge-base origin/main " \
  "convoy: the convoy is parked blocked, its reason naming the rig, the count and the failed git call"
has "$(cat "$D/lc.log")" "--unset zero_diff_check_failures --takeaway the zero-diff check could not run 3 patrols in a row; fix the error its visit names, then hand the convoy back" \
  "convoy: the park clears the count, and its takeaway names the hand-back"
eq "$(grep -cxF "wb|blocks|$VISIT" "$D/deps.txt")" 1 "convoy: the park is held by a blocks edge onto its visit"
has "$(cat "$D/gc.log")" "escalate-window 0" "convoy: the visit is filed with the verdict window off"
has "$(cat "$D/gc.log")" "Fix that error, then hand wb back to the refinery and close this visit." "convoy: the visit asks for the hand-back"
hasnt "$(cat "$D/gc.log")" "bd unclaim" "convoy: the wait that pours a run is not taken"
eq "$(meta gc.dispatch_when_ready)" "<absent>" "convoy: no pour is armed onto the convoy"
hasnt "$OUT" "the wait did not land" "convoy: the park lands"
has "$(cat "$D/gc.log")" "runtime drain-ack" "convoy: the session drains"
# A park lifecycle.sh refuses leaves the convoy with the refinery to retry.
convoy_failure "$TMP/convoy-refused"
nocheck_merge_push LC_FAIL=1
eq "$RC" 1 "convoy, park refused: merge-push stops"
eq "$(field status) $(field assignee)" "open $REFINERY" "convoy, park refused: the convoy stays assigned to the refinery"
eq "$(fails)" 3 "convoy, park refused: the count stays at the cap, so the next failed check asks again"
has "$OUT" "the wait did not land, so wb stays with the refinery, and the next patrol checks it again" \
  "convoy, park refused: the patrol says the convoy stays with the refinery"
# An edge that does not land leaves the convoy with the refinery too: a park
# with no edge onto the visit would hold it on nothing.
convoy_failure "$TMP/convoy-noedge"
nocheck_merge_push FAKE_DEP_FAIL=1
kept "convoy, edge refused"
eq "$(jq length "$D/store.json")" 1 "convoy, edge refused: precondition, the visit is filed"
has "$OUT" "no blocks edge from wb onto its visit landed, so wb is not parked" \
  "convoy, edge refused: the patrol says the convoy is not parked"

echo "── a check that runs again clears the count, and the landing goes on ──"
fixture "$TMP/recheck" work
: > "$D/gc.log"; : > "$D/lc.log"
NOCHECK_ENV=(env GC_RIG_ROOT="$D/rig" GC_RIG=myrig GC_CITY_PATH="$CITY" WORK=wb BRANCH=polecat/wb TARGET=main
  TARGET_BRANCH_DEFAULT=main FAKE_ROSTER="$D/roster.json" FAKE_META="$D/bead.json" FAKE_LOG="$D/gc.log"
  FAKE_LC_LOG="$D/lc.log" DIRECT_MERGE_PUSH_BACKOFF=0 STRATEGY=direct)
( cd "$ELSEWHERE" && "${NOCHECK_ENV[@]}" bash "$TMP/prep.sh" ) >"$D/prep.out" 2>&1; PREP_RC=$?
eq "$PREP_RC" 0 "recheck: the prepare stages the branch"
git -C "$D/rig" update-ref -d refs/remotes/origin/main
nocheck_merge_push
eq "$(fails)" 1 "recheck: a failed check is counted"
git -C "$D/rig" update-ref refs/remotes/origin/main "$BASE"
nocheck_merge_push
eq "$RC" 0 "recheck: once the check runs, merge-push goes on"
eq "$(fails)" none "recheck: the check that ran cleared the count"
recorded_at "recheck" "$FEATURE"
not_parked "recheck"

echo "── a failed git call runs once, and its own error is the one reported ──"
# A git that fails the first call of FLAKY_SUB as a held index.lock does, and
# runs every later call for real, so a rerun of the failed call succeeds. The
# error reported must be the failed call's, and that call must run once.
fixture "$TMP/flaky" work
REAL_GIT=$(command -v git)
mkdir -p "$TMP/flaky-bin"
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; printf 'REAL_GIT=%q\n' "$REAL_GIT"; cat; } > "$TMP/flaky-bin/git" <<'GITW'
if [ "$1" = -C ]; then sub="$3"; else sub="$1"; fi
printf '%s\n' "$sub" >> "$FLAKY_LOG"
if [ "$sub" = "$FLAKY_SUB" ] && [ ! -e "$FLAKY_LOG.tripped" ]; then
  : > "$FLAKY_LOG.tripped"
  echo "fatal: Unable to create '/held/index.lock': File exists." >&2
  exit 128
fi
exec "$REAL_GIT" "$@"
GITW
chmod +x "$TMP/flaky-bin/git"
for sub in merge-base diff rev-list; do
  rm -f "$TMP/flaky.log" "$TMP/flaky.log.tripped"
  OUT=$(cd "$ELSEWHERE" && PATH="$TMP/flaky-bin:$PATH" FLAKY_SUB="$sub" FLAKY_LOG="$TMP/flaky.log" \
    bash -c "$(cat "$TMP/bhrc.sh")"'
branch_has_real_change "$1" origin/main "$2"
echo "rc=$? error=$BHRC_ERROR"' _ "$D/rig" "$FEATURE" 2>&1)
  has "$OUT" "rc=2 error=$sub " "flaky/$sub: a failed $sub is a check that could not run"
  has "$OUT" "failed: fatal: Unable to create '/held/index.lock': File exists." "flaky/$sub: the error reported is the one the failed call wrote"
  eq "$(grep -cx -- "$sub" "$TMP/flaky.log" || true)" 1 "flaky/$sub: the failed call ran once"
done

echo "── a warning git writes ahead of its answer does not cost the check ──"
# Each call's stderr is captured with its stdout, so the answer is read from the
# last line. A git that warns before every answer, as it does for an ambiguous
# refname, still yields a branch with a change.
mkdir -p "$TMP/warn-bin"
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; printf 'REAL_GIT=%q\n' "$REAL_GIT"; cat; } > "$TMP/warn-bin/git" <<'GITW'
echo "warning: refname 'origin/main' is ambiguous." >&2
exec "$REAL_GIT" "$@"
GITW
chmod +x "$TMP/warn-bin/git"
OUT=$(cd "$ELSEWHERE" && PATH="$TMP/warn-bin:$PATH" bash -c "$(cat "$TMP/bhrc.sh")"'
branch_has_real_change "$1" origin/main "$2"
echo "rc=$? error=$BHRC_ERROR"' _ "$D/rig" "$FEATURE" 2>&1)
eq "$OUT" "rc=0 error=" "warning: a branch with a change still reads as one"

echo "-----"
echo "unrecorded-direct-landing: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
