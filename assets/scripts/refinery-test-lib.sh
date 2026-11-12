# shellcheck shell=bash
# refinery-test-lib.sh — the fixture the refinery patrol scripts' suites share.
# Sourced by refinery-*.test.sh, branch by branch; never run as a suite.
#
# rt_init builds, under $TMP:
#   - real git repositories: a bare origin with main and the bead branches a
#     suite adds, the rig's clone of it, and the refinery's home, a worktree
#     of that clone, which GC_DIR names;
#   - a SUT dir holding copies of the scripts under test and the libraries
#     they source, beside stubs for the scripts they call but no suite here
#     proves (human-gate.sh, deferred-dispatch.sh, patrol-finding.sh,
#     pool-route.sh, lifecycle.sh, preexisting-failure.sh,
#     rig-check-pre-existing.sh, stand-down.sh), each logging its argv;
#   - fake gc, gh and gctk on PATH, over a JSON bead store ($STORE).
# No live city, store, GitHub or network.

PASS=0; FAIL=0
rt_ok()   { PASS=$((PASS + 1)); echo "ok   - $1"; }
rt_bad()  { FAIL=$((FAIL + 1)); echo "FAIL - $1${2:+ ($2)}"; }
eq()      { if [ "$1" = "$2" ]; then rt_ok "$3"; else rt_bad "$3" "got '$1' want '$2'"; fi; }
has()     { case "$1" in *"$2"*) rt_ok "$3" ;; *) rt_bad "$3" "missing '$2' in: $1" ;; esac; }
hasnt()   { case "$1" in *"$2"*) rt_bad "$3" "found '$2' in: $1" ;; *) rt_ok "$3" ;; esac; }

# rt_init <sut script>... — the fixture, with the named scripts copied in.
rt_init() {
  unset "${!GC_@}" "${!BEADS_@}" 2>/dev/null || true
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR 2>/dev/null || true
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
  local here f
  here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
  SUT="$TMP/sut"; BIN="$TMP/bin"; GH_DIR="$TMP/gh"; LOGS="$TMP/logs"
  mkdir -p "$SUT" "$BIN" "$GH_DIR" "$LOGS"
  for f in bd-lib.sh refinery-lib.sh gctk-resolve.sh branch-push.sh pr-post.sh "$@"; do
    cp "$here/$f" "$SUT/"; chmod +x "$SUT/$f"
  done
  for f in human-gate deferred-dispatch patrol-finding lifecycle preexisting-failure rig-check-pre-existing stand-down pool-route queue-priority; do
    [ -e "$SUT/$f.sh" ] || _rt_stub "$f"
  done
  export GC_QUEUE_PRIORITY_TOOL="$SUT/queue-priority.sh"
  STORE="$TMP/store.json"; echo '[]' > "$STORE"
  : > "$LOGS/gc.log"; : > "$LOGS/gh.log"; : > "$LOGS/gctk.log"; : > "$LOGS/scripts.log"
  export STORE LOGS GH_DIR SUT
  export STUB_LOGIN="gc-city-bot" STUB_SLING_RC=0 STUB_CREATE_RC=0 STUB_EDIT_RC=0 STUB_RECORD_RC=0
  export STUB_NEXT_PR=500 STUB_UPDATE_FAIL="" STUB_VARS="$TMP/vars.json" STUB_HOLDS="$TMP/holds.txt"
  : > "$STUB_HOLDS"
  rt_vars
  _rt_gc; _rt_gh; _rt_gctk
  export PATH="$BIN:$PATH"
  export GCTK_BIN="$BIN/gctk"
  rt_repos
  export GC_AGENT="rig-a/gc-toolkit.refinery" GC_RIG="rig-a" GC_DIR="$HOME_DIR"
}

# _rt_stub <name> — a stub <name>.sh that logs its argv to scripts.log, prints
# STUB_<NAME>_OUT when set, and exits STUB_<NAME>_RC (default 0). pool-route.sh
# prints rig-a/<pool> unless STUB_POOL_ROUTE_OUT says otherwise.
_rt_stub() {
  local var
  var=$(printf '%s' "$1" | tr 'a-z-' 'A-Z_')
  cat > "$SUT/$1.sh" <<STUB
#!/usr/bin/env bash
echo "$1 \$*" >> "\$LOGS/scripts.log"
out="\${STUB_${var}_OUT:-}"
[ "$1" != pool-route ] || [ -n "\$out" ] || out="rig-a/\$1"
[ -z "\$out" ] || printf '%s\n' "\$out"
exit "\${STUB_${var}_RC:-0}"
STUB
  chmod +x "$SUT/$1.sh"
}

# shellcheck disable=SC2120  # rt_init calls it bare; the suites pass values
# rt_vars [name=value]... — the rig's formula vars `gc formula show --rig`
# answers with, as rig values over the formula's defaults. The default check
# set names two lanes the pack does not declare: a list of the pack's own
# checks belongs only in its index and the default check_set's configuration.
rt_vars() {
  local pair args=()
  for pair in "$@"; do args+=(--arg "${pair%%=*}" "${pair#*=}"); done
  jq -n ${args[@]+"${args[@]}"} '
    {default_merge_strategy: "direct", delete_merged_branches: "true", check_set: "lane-a,lane-b",
     pending_through_merge: "false", run_tests: "true", setup_command: "", typecheck_command: "",
     lint_command: "", test_command: "", build_command: ""} as $d
    | {ok: true, vars: [ $d | to_entries[] | .key as $k
        | {name: $k, default: .value, rig_default: ($ARGS.named[$k] // null)} ]}' > "$STUB_VARS"
}

# rt_repos — a bare origin with main, the rig's clone and the refinery's home.
rt_repos() {
  ORIGIN="$TMP/origin.git"; SEED="$TMP/seed"; RIG="$TMP/rig"; HOME_DIR="$TMP/rig-homes/refinery"
  git init -q --bare -b main "$ORIGIN"
  git init -q -b main "$SEED"
  printf 'base\n' > "$SEED/base.txt"
  git -C "$SEED" add base.txt && git -C "$SEED" commit -q -m base
  git -C "$SEED" remote add origin "$ORIGIN"
  git -C "$SEED" push -q origin main
  git clone -q "$ORIGIN" "$RIG"
  # The rig's origin is a github.com repository by its URL, which git rewrites
  # to the local bare origin for every fetch and push.
  export REPO_SLUG="zook/rig"
  git -C "$RIG" remote set-url origin "https://github.com/$REPO_SLUG"
  git -C "$RIG" config "url.$ORIGIN.insteadOf" "https://github.com/$REPO_SLUG"
  git -C "$RIG" remote set-head origin main >/dev/null 2>&1 || git -C "$RIG" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
  mkdir -p "$TMP/rig-homes"
  git -C "$RIG" worktree add -q -b gc-refinery-home "$HOME_DIR" origin/main
  HOME_DIR=$(cd "$HOME_DIR" && pwd -P)
}

# branch_with <branch> <file> [<from>]: a branch on origin with one commit of
# its own adding <file>, cut from <from> (default main). Prints its tip.
branch_with() {
  git -C "$SEED" fetch -q origin
  git -C "$SEED" checkout -q -B "$1" "origin/${3:-main}"
  printf '%s\n' "$2" > "$SEED/$2"
  git -C "$SEED" add "$2" && git -C "$SEED" commit -q -m "add $2"
  git -C "$SEED" push -q -f origin "$1"
  git -C "$SEED" rev-parse HEAD
}
# main_with <file>: a commit on origin's main adding <file>. Prints its tip.
main_with() { branch_with main "$1" main; }
tip() { git -C "$ORIGIN" rev-parse --verify -q "refs/heads/$1" 2>/dev/null || echo "<absent>"; }

# put <json object> — add a bead to the store.
put() { jq --argjson b "$1" '. + [$b]' "$STORE" > "$STORE.n" && mv "$STORE.n" "$STORE"; }
# work <id> <branch> [<extra metadata json>] [<status>] [<assignee>] — a work bead handed to the refinery.
work() {
  put "$(jq -nc --arg id "$1" --arg b "$2" --argjson m "${3:-{\}}" --arg s "${4:-open}" --arg a "${5-$GC_AGENT}" \
    '{id: $id, title: ("Work " + $id), status: $s, assignee: $a, issue_type: "task", priority: 2,
      created_at: ("2026-11-12T00:00:" + ($id | length | tostring) + "Z"), notes: "",
      metadata: ({branch: $b, target: "main"} + $m)}')"
}
meta()     { jq -r --arg id "$1" --arg k "$2" '(.[] | select(.id == $id) | .metadata[$k] // "<absent>") // "<absent>"' "$STORE"; }
bstatus()  { jq -r --arg id "$1" '(.[] | select(.id == $id) | .status) // "<absent>"' "$STORE"; }
bassignee(){ jq -r --arg id "$1" '(.[] | select(.id == $id) | .assignee) // "<absent>"' "$STORE"; }
bnotes()   { jq -r --arg id "$1" '(.[] | select(.id == $id) | .notes) // ""' "$STORE"; }
logged()   { cat "$LOGS/$1.log"; }
reset_logs() { : > "$LOGS/gc.log"; : > "$LOGS/gh.log"; : > "$LOGS/gctk.log"; : > "$LOGS/scripts.log"; }
# pr <number> <branch> <author> [<state>] [<base>] [<body>] — a PR the fake gh serves.
pr() {
  jq -n --argjson n "$1" --arg b "$2" --arg a "$3" --arg s "${4:-OPEN}" --arg t "${5:-main}" --arg body "${6:-}" --arg r "$REPO_SLUG" \
    '{number: $n, url: ("https://github.com/" + $r + "/pull/" + ($n | tostring)), state: $s, headRefName: $b,
      baseRefName: $t, headRepository: {name: ($r | split("/")[1])}, headRepositoryOwner: {login: ($r | split("/")[0])},
      isCrossRepository: false, author: {login: $a}, title: ("old title " + ($n | tostring)), body: $body}' > "$GH_DIR/view_$1.json"
}
# prepared <bead> <branch> — the refinery's tree for <bead>, as the prep leaves it.
prepared() {
  git -C "$HOME_DIR" fetch -q origin "+refs/heads/$2:refs/remotes/origin/$2" "+refs/heads/main:refs/remotes/origin/main"
  local read; read=$(git -C "$HOME_DIR" rev-parse "refs/remotes/origin/$2")
  mkdir -p "$HOME_DIR/worktrees"
  git -C "$HOME_DIR" worktree add -q --detach "$HOME_DIR/worktrees/$1" "$read"
  git -C "$HOME_DIR/worktrees/$1" update-ref "refs/worktree/refinery/$2" "$read"
  git -C "$HOME_DIR/worktrees/$1" merge -q --no-edit refs/remotes/origin/main >/dev/null 2>&1 || true
}

_rt_gc() {
cat > "$BIN/gc" <<'GC'
#!/usr/bin/env bash
echo "$*" >> "$LOGS/gc.log"
st() { jq "$@" "$STORE" > "$STORE.n" && mv "$STORE.n" "$STORE"; }
case "$1 $2" in
  "gc-toolkit scripts-dir") echo "$SUT"; exit 0 ;;
  "formula show") cat "$STUB_VARS"; exit 0 ;;
  "sling "*) exit "${STUB_SLING_RC:-0}" ;;
  "workflow delete-source") exit 0 ;;
  "session "*|"mail "*) exit 0 ;;
esac
[ "$1" = bd ] || { echo "gc stub: unsupported $*" >&2; exit 2; }
shift
verb="$1"; shift
case "$verb" in
  show)
    id="$1"
    row=$(jq -c --arg id "$id" '[ .[] | select(.id == $id) ]' "$STORE")
    [ "$row" != "[]" ] || { echo '{"error":"not found"}'; exit 1; }
    printf '%s\n' "$row" ;;
  list)
    [ -z "${STUB_GC_LIST_FAIL:-}" ] || { echo "store unreachable" >&2; exit 1; }
    f='.'
    for a in "$@"; do
      case "$a" in
        --assignee=*) f="$f | map(select(.assignee == \"${a#--assignee=}\"))" ;;
        --status=*) f="$f | map(select(.status as \$s | \"${a#--status=}\" | split(\",\") | index(\$s)))" ;;
        --has-metadata-key=*) f="$f | map(select(.metadata | has(\"${a#--has-metadata-key=}\")))" ;;
        --exclude-type=*) f="$f | map(select(.issue_type != \"${a#--exclude-type=}\"))" ;;
        --type=*) f="$f | map(select(.issue_type == \"${a#--type=}\"))" ;;
      esac
    done
    prev=""
    for a in "$@"; do
      if [ "$prev" = --metadata-field ]; then
        k="${a%%=*}"; v="${a#*=}"
        f="$f | map(select((.metadata[\"$k\"] // \"\") == \"$v\"))"
      fi
      prev="$a"
    done
    jq -c "$f" "$STORE" ;;
  update)
    id="$1"; shift
    [ -z "${STUB_UPDATE_FAIL:-}" ] || { echo "update refused" >&2; exit 1; }
    [ -z "${STUB_GUARD_FAIL:-}" ] || { echo "guard: the bead moved" >&2; exit 13; }
    cur=$(jq -c --arg id "$id" '.[] | select(.id == $id)' "$STORE")
    [ -n "$cur" ] || { echo "no bead $id" >&2; exit 1; }
    prog='.'
    while [ $# -gt 0 ]; do
      case "$1" in
        --if-assignee=*) [ "$(printf '%s' "$cur" | jq -r '.assignee // ""')" = "${1#--if-assignee=}" ] || { echo "guard: assignee" >&2; exit 13; } ;;
        --if-status=*) [ "$(printf '%s' "$cur" | jq -r '.status')" = "${1#--if-status=}" ] || { echo "guard: status" >&2; exit 13; } ;;
        --status=*) prog="$prog | .status = \"${1#--status=}\"" ;;
        --assignee=*) prog="$prog | .assignee = \"${1#--assignee=}\"" ;;
        --set-metadata) k="${2%%=*}"; v="${2#*=}"; prog="$prog | .metadata[$(jq -Rn --arg k "$k" '$k')] = $(jq -Rn --arg v "$v" '$v')"; shift ;;
        --unset-metadata) prog="$prog | del(.metadata[$(jq -Rn --arg k "$2" '$k')])"; shift ;;
        --append-notes) prog="$prog | .notes = ((.notes // \"\") + \"\\n\" + $(jq -Rn --arg v "$2" '$v'))"; shift ;;
      esac
      shift
    done
    st --arg id "$id" "map(if .id == \$id then $prog else . end)" ;;
  create)
    title="$1"; shift; meta='{}'; type=task
    while [ $# -gt 0 ]; do
      case "$1" in --metadata) meta="$2"; shift ;; -t) type="$2"; shift ;; esac
      shift
    done
    n=$(jq 'length' "$STORE")
    id="rw-$n"
    st --arg id "$id" --arg t "$title" --arg ty "$type" --argjson m "$meta" \
      '. + [{id: $id, title: $t, status: "open", assignee: "", issue_type: $ty, priority: 2, created_at: "2026-11-12T01:00:00Z", notes: "", metadata: $m}]'
    printf '{"id":"%s"}\n' "$id" ;;
  dep) exit 0 ;;
  close)
    id="$1"
    st --arg id "$id" 'map(if .id == $id then .status = "closed" else . end)' ;;
  mol)
    case "$1" in
      wisp)
        n=$(jq 'length' "$STORE"); id="wisp-$n"
        st --arg id "$id" '. + [{id: $id, title: "mol-refinery-patrol", status: "open", assignee: "", issue_type: "molecule", created_at: "2026-11-12T02:00:00Z", notes: "", metadata: {}}]'
        printf '{"new_epic_id":"%s"}\n' "$id" ;;
      burn) st --arg id "$2" 'map(select(.id != $id))' ;;
    esac ;;
  *) echo "gc stub: unsupported bd $verb" >&2; exit 2 ;;
esac
GC
chmod +x "$BIN/gc"
}

_rt_gh() {
cat > "$BIN/gh" <<'GH'
#!/usr/bin/env bash
echo "$*" >> "$LOGS/gh.log"
case "$1 $2" in
  "api --hostname"|"api user")
    [ -n "${STUB_LOGIN:-}" ] || { echo "gh: not logged in" >&2; exit 1; }
    echo "$STUB_LOGIN"; exit 0 ;;
  "pr view")
    ref="$3"; num="${ref##*/}"
    f="$GH_DIR/view_$num.json"
    [ -f "$f" ] || { echo "GraphQL: Could not resolve to a PullRequest with the number of $num." >&2; exit 1; }
    cat "$f"; exit 0 ;;
  "pr list")
    head=""; base=""; prev=""
    for a in "$@"; do
      [ "$prev" = --head ] && head="$a"
      [ "$prev" = --base ] && base="$a"
      prev="$a"
    done
    [ -z "${STUB_LIST_FAIL:-}" ] || exit 1
    rows='[]'
    for f in "$GH_DIR"/view_*.json; do
      [ -f "$f" ] || continue
      rows=$(jq -c --slurpfile r "$f" --arg h "$head" --arg b "$base" '. + [ $r[0] | select(.headRefName == $h and .baseRefName == $b and .state == "OPEN") ]' <<< "$rows")
    done
    printf '%s\n' "$rows"; exit 0 ;;
  "pr create")
    [ "${STUB_CREATE_RC:-0}" = 0 ] || exit "$STUB_CREATE_RC"
    head=""; base=""; title=""; bodyf=""; prev=""
    for a in "$@"; do
      case "$prev" in --head) head="$a" ;; --base) base="$a" ;; --title) title="$a" ;; --body-file) bodyf="$a" ;; esac
      prev="$a"
    done
    n="$STUB_NEXT_PR"
    jq -n --argjson n "$n" --arg b "$head" --arg t "$base" --arg title "$title" --rawfile body "$bodyf" --arg a "$STUB_LOGIN" --arg r "$REPO_SLUG" \
      '{number: $n, url: ("https://github.com/" + $r + "/pull/" + ($n | tostring)), state: "OPEN", headRefName: $b,
        baseRefName: $t, headRepository: {name: ($r | split("/")[1])}, headRepositoryOwner: {login: ($r | split("/")[0])},
        isCrossRepository: false, author: {login: $a}, isDraft: true, title: $title, body: $body}' > "$GH_DIR/view_$n.json"
    echo "https://github.com/$REPO_SLUG/pull/$n"; exit 0 ;;
  "pr edit")
    [ "${STUB_EDIT_RC:-0}" = 0 ] || exit "$STUB_EDIT_RC"
    exit 0 ;;
esac
echo "gh stub: unsupported $*" >&2
exit 2
GH
chmod +x "$BIN/gh"
}

_rt_gctk() {
cat > "$BIN/gctk" <<'GCTK'
#!/usr/bin/env bash
echo "$*" >> "$LOGS/gctk.log"
case "$1 $2" in
  "bead holds")
    shift 2
    for id in "$@"; do
      by=$(awk -v i="$id" '$1 == i { print $2 }' "$STUB_HOLDS")
      if [ -n "$by" ]; then
        printf '{"id":"%s","status":"held","waits":[{"id":"%s"}]}\n' "$id" "$by"
      else
        printf '{"id":"%s","status":"clear","waits":[]}\n' "$id"
      fi
    done ;;
  "pr compose")
    owner="$3"; shift 3; head=""; bodyf=""
    while [ $# -gt 0 ]; do
      case "$1" in --head) head="$2"; shift ;; --body-file) bodyf="$2"; shift ;; esac
      shift
    done
    body="<!-- gc:pr-summary -->composed for $owner at $head<!-- /gc:pr-summary -->"
    outcome=written
    [ -n "$bodyf" ] && grep -qF "at $head" "$bodyf" && outcome=current
    jq -n --arg t "feat: $owner (${owner})" --arg b "$body" --arg o "$outcome" \
      '{title: $t, body: $b, summary: $o, branch_beads: "single", branch_bead_count: 1}' ;;
  "pr record")
    bead="$3"; shift 3; url=""; head=""; target=""
    while [ $# -gt 0 ]; do
      case "$1" in --pr) url="$2"; shift ;; --head) head="$2"; shift ;; --target) target="$2"; shift ;; esac
      shift
    done
    rc="${STUB_RECORD_RC:-0}"
    [ "$rc" = 0 ] || exit "$rc"
    jq --arg id "$bead" --arg u "$url" --arg h "$head" --arg t "$target" \
      'map(if .id == $id then .status = "blocked" | .metadata += {merge_result: "pull_request_pending", pr_url: $u, pr_head_sha: $h, merged_target: $t, pr_reconcile_pending: "true", existing_pr: $u} else . end)' \
      "$STORE" > "$STORE.n" && mv "$STORE.n" "$STORE" ;;
  rig\ *)
    check="$2"; shift 2; cmd=""
    while [ $# -gt 0 ]; do case "$1" in --command) cmd="$2"; shift ;; esac; shift; done
    bash -c "$cmd" </dev/null; rc=$?
    case "$rc" in
      0) echo "gctk rig $check: pass" ;;
      1) echo "gctk rig $check: fail"; exit 1 ;;
      *) echo "gctk rig $check: stopped short ($rc)"; exit "$rc" ;;
    esac ;;
  *) echo "gctk stub: unsupported $*" >&2; exit 2 ;;
esac
GCTK
chmod +x "$BIN/gctk"
}
