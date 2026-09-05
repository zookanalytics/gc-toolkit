#!/usr/bin/env bash
# test-harness.sh — shared stub fixtures for the merge-cadence test suites.
# Sourced by *.test.sh (never run as a suite itself). Provides stub gc/gh/git
# binaries over a JSON bead store plus assertion helpers, following the
# deferred-dispatch.test.sh pattern: stubs log invocations and serve canned
# JSON; tests assert on the logs, the store, and exit codes.
# Contract: caller sets TMP (tempdir); harness_init installs stubs on PATH and
# exports STUB_* env the stubs read. No live city, network, gc, bd or gh.

ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 (found '$2' in: $1)" ;; *) ok "$3" ;; esac; }

harness_init() {
  PASS=0; FAIL=0
  BIN="$TMP/bin"; GH_DIR="$TMP/gh"
  mkdir -p "$BIN" "$GH_DIR"
  # Pin the merge cadence to its shell implementations. The scripts prefer a
  # deployed `gctk` binary, resolved from the ambient GC_CITY — and these suites
  # run from a tree INSIDE a live city, so left alone a suite would silently
  # test whichever implementation that city last built. A suite that means to
  # exercise the port says so by overriding this after harness_init, the way
  # lifecycle.test.sh does for its second arm.
  export GCTK_BIN=none
  export STUB_STORE="$TMP/beads.json"
  export STUB_DEPS="$TMP/deps.txt"
  export STUB_GC_LOG="$TMP/gc.log"
  export STUB_GH_LOG="$TMP/gh.log"
  export STUB_GH_DIR="$GH_DIR"
  export STUB_SESSION_LOG="$TMP/session.log"
  export STUB_ORIGIN_URL="https://github.com/zook/gc-toolkit"
  export STUB_ORIGIN_HEAD="main"
  export STUB_SELF_LOGIN="gc-city-bot"
  export STUB_UPDATE_FAIL="" STUB_CLOSE_FAIL="" STUB_DROP_KEYS=""
  export STUB_LIST_FAIL="" STUB_SHOW_FAIL=""
  export STUB_SLING_FAIL="" STUB_DEP_GARBAGE=""
  export STUB_LS_REMOTE="" STUB_LS_REMOTE_RC=""
  export STUB_TOPLEVEL="" STUB_FETCHED_HEAD="" STUB_FETCH_RC=""
  export STUB_PR_CREATE_URL="" STUB_PR_CREATE_RC=0 STUB_PR_MERGE_RC=0 STUB_DISMISS_RC=0
  export STUB_GQL_READ_FAIL="" STUB_REACT_RC=0 STUB_REPLY_RC=0 STUB_RESOLVE_RC=0
  export STUB_DELETE_SOURCE_RC="" STUB_DELETE_SOURCE_OUT="" STUB_REOPEN_SOURCE_RC=""
  echo '[]' > "$STUB_STORE"; : > "$STUB_DEPS"; : > "$STUB_GC_LOG"; : > "$STUB_GH_LOG"
  : > "$STUB_SESSION_LOG"
  _write_gc_stub; _write_gh_stub; _write_git_stub
  chmod +x "$BIN/gc" "$BIN/gh" "$BIN/git"
  export PATH="$BIN:$PATH"
}

store() { printf '%s' "$1" > "$STUB_STORE"; }
meta()  { jq -r --arg id "$1" --arg k "$2" '(.[] | select(.id == $id) | .metadata[$k] // "<absent>") // "<absent>"' "$STUB_STORE"; }
bstatus() { jq -r --arg id "$1" '(.[] | select(.id == $id) | .status) // "<absent>"' "$STUB_STORE"; }
bassignee() { jq -r --arg id "$1" '(.[] | select(.id == $id) | .assignee) // "<absent>"' "$STUB_STORE"; }
notes() { jq -r --arg id "$1" '(.[] | select(.id == $id) | .notes) // ""' "$STUB_STORE"; }

# Copy the SUT and the named siblings into a private scripts dir so $0-relative
# sibling resolution hits stubs/copies, never the live tree.
mk_sut_dir() { # <dir> <file>...
  local d="$1"; shift
  mkdir -p "$d"
  local f
  for f in "$@"; do cp "$f" "$d/"; chmod +x "$d/$(basename "$f")"; done
}

_write_gc_stub() {
cat > "$BIN/gc" <<'STUB'
#!/usr/bin/env bash
set -u
S="${STUB_STORE:?}"; D="${STUB_DEPS:?}"
printf '%s\n' "$*" >> "${STUB_GC_LOG:?}"
sub="${1:-}"; shift || true
case "$sub" in
  agent)
    [ "${1:-}" = "list" ] && { cat "${STUB_AGENTS:-/dev/null}" 2>/dev/null || echo '{"agents":[]}'; exit 0; }
    exit 0 ;;
  convoy)
    [ "${1:-}" = "list" ] && { cat "${STUB_CONVOYS:-/dev/null}" 2>/dev/null || echo '{"convoys":[]}'; exit 0; }
    exit 0 ;;
  session) printf '%s\n' "gc session $*" >> "${STUB_SESSION_LOG:?}"; exit 0 ;;
  mail) exit 0 ;;
  workflow)
    # delete-source / reopen-source over the JSON store. delete-source matches
    # roots on gc.source_bead_id, so its default here is the already_clean a
    # graph.v2 chain really returns; STUB_DELETE_SOURCE_OUT overrides the line
    # for a store that does carry the linkage. reopen-source performs the real
    # mutation: workflow_id and the session-affinity keys cleared, route
    # preserved, status open, assignee empty.
    verb="${1:-}"; sid="${2:-}"
    case "$verb" in
      delete-source)
        [ -n "${STUB_DELETE_SOURCE_RC:-}" ] && { echo "gc: simulated delete-source failure" >&2; exit "${STUB_DELETE_SOURCE_RC}"; }
        echo "${STUB_DELETE_SOURCE_OUT:-result=already_clean source_bead_id=$sid matched_roots=0 matched_beads=0 closed=0 deleted=0 metadata_cleared=false}"
        exit 0 ;;
      reopen-source)
        [ -n "${STUB_REOPEN_SOURCE_RC:-}" ] && { echo "gc: simulated reopen-source failure" >&2; exit "${STUB_REOPEN_SOURCE_RC}"; }
        tmp="$(mktemp)"
        jq -c --arg id "$sid" 'map(if .id == $id then
              (.metadata |= (del(.workflow_id) | del(.["gc.session_affinity"]) | del(.["gc.continuation_group"])))
              | .status = "open" | .assignee = ""
            else . end)' "$S" > "$tmp" && mv "$tmp" "$S"
        echo "result=reopened source_bead_id=$sid"
        exit 0 ;;
      *) echo "gc stub: unsupported 'workflow $verb'" >&2; exit 2 ;;
    esac ;;
  sling)
    # Emulate the graph.v2 pour on the store: retire gc.routed_to and stamp
    # gc.execution_routed_to=<target>. STUB_SLING_FAIL exits 1 with no writes;
    # STUB_DROP_KEYS="<bead>:gc.execution_routed_to" models a pour whose exec
    # stamp dropped. Invocations land in STUB_GC_LOG like every gc call.
    [ -n "${STUB_SLING_FAIL:-}" ] && { echo "gc: simulated sling failure" >&2; exit 1; }
    target=""; bead=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --rig|--on) shift ;;
        --*) : ;;
        *) if [ -z "$target" ]; then target="$1"; elif [ -z "$bead" ]; then bead="$1"; fi ;;
      esac
      shift || true
    done
    [ -n "$bead" ] || exit 0
    drops=""
    for pair in ${STUB_DROP_KEYS:-}; do
      case "$pair" in "$bead:"*) drops="${pair#*:}" ;; esac
    done
    tmp="$(mktemp)"; cp "$S" "$tmp"
    jq -c --arg id "$bead" 'map(if .id == $id then (.metadata |= del(.["gc.routed_to"])) else . end)' "$tmp" > "$tmp.n" && mv "$tmp.n" "$tmp"
    case ",$drops," in
      *",gc.execution_routed_to,"*) : ;;
      *) jq -c --arg id "$bead" --arg t "$target" 'map(if .id == $id then .metadata["gc.execution_routed_to"] = $t else . end)' "$tmp" > "$tmp.n" && mv "$tmp.n" "$tmp" ;;
    esac
    mv "$tmp" "$S"
    exit 0 ;;
  bd) : ;;
  *) echo "gc stub: unsupported '$sub'" >&2; exit 2 ;;
esac
verb="${1:-}"; shift || true
case "$verb" in
  show)
    [ -n "${STUB_SHOW_FAIL:-}" ] && { echo "gc: simulated show failure" >&2; exit 1; }
    id="${1:-}"
    # STUB_SHOW_HOOK: executable run before serving each show (gets the id);
    # lets a test mutate the store between reads (mid-pass write modelling).
    if [ -n "${STUB_SHOW_HOOK:-}" ] && [ -x "${STUB_SHOW_HOOK:-}" ]; then
      "$STUB_SHOW_HOOK" "$id" || true
    fi
    jq -c --arg id "$id" '[ .[] | select(.id == $id) ]' "$S"
    ;;
  list)
    [ -n "${STUB_LIST_FAIL:-}" ] && { echo "gc: simulated list failure" >&2; exit 1; }
    statuses=""; fields=(); haskey=""; typ=""; excl=""; tcontains=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --status=*) statuses="${1#--status=}" ;;
        --status) shift; statuses="${1:-}" ;;
        --metadata-field) shift; fields+=("${1:-}") ;;
        --metadata-field=*) fields+=("${1#--metadata-field=}") ;;
        --has-metadata-key) shift; haskey="${1:-}" ;;
        --has-metadata-key=*) haskey="${1#--has-metadata-key=}" ;;
        --type=*) typ="${1#--type=}" ;;
        --exclude-type=*) excl="${1#--exclude-type=}" ;;
        --title-contains) shift; tcontains="${1:-}" ;;
        --title-contains=*) tcontains="${1#--title-contains=}" ;;
        *) : ;;
      esac
      shift || true
    done
    out=$(jq -c --arg st "$statuses" --arg hk "$haskey" --arg ty "$typ" --arg ex "$excl" --arg tc "$tcontains" '
      [ .[]
        | (.status // "open") as $bst
        | select($st == "" or (($st | split(",")) | index($bst)))
        | select($hk == "" or ((.metadata // {}) | has($hk)))
        | select($ty == "" or ((.issue_type // "task") == $ty))
        | select($ex == "" or ((.issue_type // "task") != $ex))
        | select($tc == "" or (((.title // "") | ascii_downcase) | contains($tc | ascii_downcase))) ]' "$S")
    for f in ${fields[@]+"${fields[@]}"}; do
      k="${f%%=*}"; v="${f#*=}"
      out=$(printf '%s' "$out" | jq -c --arg k "$k" --arg v "$v" \
        '[ .[] | select((((.metadata // {})[$k]) // "" | tostring) == $v) ]')
    done
    printf '%s\n' "$out"
    ;;
  update)
    id="${1:-}"; shift || true
    case " ${STUB_UPDATE_FAIL:-} " in *" $id "*) echo "gc: simulated update refusal for $id" >&2; exit 1 ;; esac
    # STUB_CLOSE_FAIL="id id2" — the same knob the `close` subcommand reads,
    # applied to the other spelling of a close: refuse only the writes carrying
    # --status=closed, leaving metadata-only writes on the same bead succeeding.
    # That asymmetry is bd's own — its ownership check is a property of the
    # close, and a bare --set-metadata on a bead assigned to another principal
    # still lands. STUB_UPDATE_FAIL refuses both, so it cannot model a record
    # whose close is permanently refused while a counter beside it still writes.
    case " ${STUB_CLOSE_FAIL:-} " in
      *" $id "*) case " $* " in *" --status=closed "*)
        echo "gc: simulated close refusal for $id" >&2; exit 1 ;; esac ;;
    esac
    sets=(); unsets=(); note=""; note_set=0; asg=""; asg_set=0; newstatus=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --set-metadata) shift; sets+=("${1:-}") ;;
        --set-metadata=*) sets+=("${1#--set-metadata=}") ;;
        --unset-metadata) shift; unsets+=("${1:-}") ;;
        --unset-metadata=*) unsets+=("${1#--unset-metadata=}") ;;
        --assignee=*) asg="${1#--assignee=}"; asg_set=1 ;;
        --assignee) shift; asg="${1-}"; asg_set=1 ;;
        --status=*) newstatus="${1#--status=}" ;;
        --append-notes) shift; note="${1:-}"; note_set=1 ;;
        *) : ;;
      esac
      shift || true
    done
    # STUB_DROP_KEYS="id:key1,key2 id2:key" — apply the update but silently drop
    # the named keys, modelling a write that reported success and half-landed.
    drops=""
    for pair in ${STUB_DROP_KEYS:-}; do
      case "$pair" in "$id:"*) drops="${pair#*:}" ;; esac
    done
    tmp="$(mktemp)"; cp "$S" "$tmp"
    for kv in ${sets[@]+"${sets[@]}"}; do
      k="${kv%%=*}"; v="${kv#*=}"
      case ",$drops," in *",$k,"*) continue ;; esac
      jq -c --arg id "$id" --arg k "$k" --arg v "$v" \
        'map(if .id == $id then .metadata[$k] = $v else . end)' "$tmp" > "$tmp.n" && mv "$tmp.n" "$tmp"
    done
    for k in ${unsets[@]+"${unsets[@]}"}; do
      case ",$drops," in *",$k,"*) continue ;; esac
      jq -c --arg id "$id" --arg k "$k" \
        'map(if .id == $id then (.metadata |= del(.[$k])) else . end)' "$tmp" > "$tmp.n" && mv "$tmp.n" "$tmp"
    done
    if [ "$asg_set" = 1 ]; then
      case ",$drops," in *",assignee,"*) : ;; *)
        jq -c --arg id "$id" --arg a "$asg" \
          'map(if .id == $id then .assignee = $a else . end)' "$tmp" > "$tmp.n" && mv "$tmp.n" "$tmp" ;;
      esac
    fi
    if [ -n "$newstatus" ]; then
      case ",$drops," in *",status,"*) : ;; *)
        jq -c --arg id "$id" --arg s "$newstatus" \
          'map(if .id == $id then .status = $s else . end)' "$tmp" > "$tmp.n" && mv "$tmp.n" "$tmp" ;;
      esac
    fi
    if [ "$note_set" = 1 ]; then
      jq -c --arg id "$id" --arg n "$note" \
        'map(if .id == $id then .notes = ((.notes // "") + (if (.notes // "") == "" then "" else "\n" end) + $n) else . end)' \
        "$tmp" > "$tmp.n" && mv "$tmp.n" "$tmp"
    fi
    mv "$tmp" "$S"
    echo "updated $id"
    ;;
  create)
    title="${1:-}"; shift || true
    body=""
    while [ $# -gt 0 ]; do
      case "$1" in --body-file) shift; [ "${1:-}" = "-" ] && body="$(cat)" ;; esac
      shift || true
    done
    n=$(jq 'length' "$S"); nid="new-$((n + 1))"
    tmp="$(mktemp)"
    jq -c --arg id "$nid" --arg t "$title" --arg b "$body" \
      '. + [{id: $id, status: "open", assignee: "", title: $t, description: $b, notes: "", issue_type: "task", metadata: {}}]' \
      "$S" > "$tmp" && mv "$tmp" "$S"
    printf '{"id":"%s"}\n' "$nid"
    ;;
  close)
    id="${1:-}"
    case " ${STUB_CLOSE_FAIL:-} " in *" $id "*) echo "gc: simulated close refusal" >&2; exit 1 ;; esac
    tmp="$(mktemp)"
    jq -c --arg id "$id" 'map(if .id == $id then .status = "closed" else . end)' "$S" > "$tmp" && mv "$tmp" "$S"
    ;;
  dep)
    # Edge rows are "A|TYPE|B" = "A <TYPE>-edges B" (A blocks B, A tracks B,
    # child A parent-childs parent B). Dependency orientation per type:
    # blocks -> (issue=B, depends_on=A); every other type -> (issue=A,
    # depends_on=B). Queries honor --direction (down = follow the id's own
    # dependency rows; up = rows depending on the id) and -t/--type.
    case "${1:-}" in
      list)
        [ -n "${STUB_DEP_GARBAGE:-}" ] && { echo "not-json"; exit 0; }
        id="${2:-}"; shift 2 || true
        dir=""; dtyp=""
        while [ $# -gt 0 ]; do
          case "$1" in
            --direction=*) dir="${1#--direction=}" ;;
            --direction) shift; dir="${1:-}" ;;
            -t|--type) shift; dtyp="${1:-}" ;;
            --type=*) dtyp="${1#--type=}" ;;
            *) : ;;
          esac
          shift || true
        done
        ids=$(awk -F'|' -v id="$id" -v dir="$dir" -v t="$dtyp" '
          {
            a=$1; ty=$2; b=$3
            if (t != "" && ty != t) next
            if (ty == "blocks") { issue=b; dep=a } else { issue=a; dep=b }
            if (dir == "down")    { if (issue == id) print dep }
            else if (dir == "up") { if (dep == id) print issue }
            else                  { if (b == id) print a }   # legacy: who names me
          }' "$D")
        jq -c --arg ids "$ids" '($ids | split("\n")) as $want
          | [ .[] | select(.id as $b | ($want | index($b))) ]' "$S"
        ;;
      add)
        a="${2:-}"; b="${3:-}"; ty="parent-child"; shift 3 || true
        while [ $# -gt 0 ]; do
          case "$1" in --type=*) ty="${1#--type=}" ;; --type) shift; ty="${1:-}" ;; esac
          shift || true
        done
        printf '%s|%s|%s\n' "$a" "$ty" "$b" >> "$D" ;;
      *)
        # gc bd dep <src> --blocks <dst>
        src="${1:-}"; shift || true
        [ "${1:-}" = "--blocks" ] && printf '%s|%s|%s\n' "$src" "blocks" "${2:-}" >> "$D" ;;
    esac
    ;;
  *) echo "gc bd stub: unsupported '$verb'" >&2; exit 2 ;;
esac
STUB
}

_write_gh_stub() {
cat > "$BIN/gh" <<'STUB'
#!/usr/bin/env bash
set -u
printf '%s\n' "$*" >> "${STUB_GH_LOG:?}"
G="${STUB_GH_DIR:?}"
san() { printf '%s' "$1" | tr '/' '_'; }
sub="${1:-}"; shift || true
case "$sub" in
  pr)
    v="${1:-}"; shift || true
    case "$v" in
      view)
        n="${1:-}"
        f="$G/pr_view_$n.json"
        [ -s "$f" ] || { echo "gh: no such pr" >&2; exit 1; }
        cat "$f" ;;
      list)
        br=""
        while [ $# -gt 0 ]; do
          case "$1" in --head) shift; br="${1:-}" ;; esac
          shift || true
        done
        f="$G/pr_list_$(san "$br").json"
        [ -s "$f" ] && cat "$f" || echo '[]' ;;
      merge)   exit "${STUB_PR_MERGE_RC:-0}" ;;
      comment) exit 0 ;;
      create)
        # The composed body reaches the log only as a temp path, so keep a copy
        # of what the reviewer would read.
        : > "$G/pr_create_body.txt"
        while [ $# -gt 0 ]; do
          case "$1" in --body-file) shift; [ -f "${1:-}" ] && cat "$1" > "$G/pr_create_body.txt" ;; esac
          shift || true
        done
        [ -n "${STUB_PR_CREATE_URL:-}" ] && echo "$STUB_PR_CREATE_URL"
        exit "${STUB_PR_CREATE_RC:-0}" ;;
      *) echo "gh pr stub: unsupported '$v'" >&2; exit 2 ;;
    esac ;;
  api)
    path=""; jqexpr=""; gqvars='{}'; gqquery=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --hostname) shift ;;
        --jq) shift; jqexpr="${1:-}" ;;
        --paginate) : ;;
        -X) shift ;;
        -f|-F)
          kv="${2:-}"; shift
          k="${kv%%=*}"; v="${kv#*=}"
          if [ "$k" = "query" ]; then gqquery="$v"
          else gqvars=$(printf '%s' "$gqvars" | jq -c --arg k "$k" --arg v "$v" '.[$k] = $v'); fi ;;
        --*) : ;;
        *) [ -z "$path" ] && path="$1" ;;
      esac
      shift || true
    done
    if [ "$path" = "graphql" ]; then
      # The write-back surface: three reads plus three mutations, over a fixture
      # the mutations actually MUTATE. A stub that forgot the write would let a
      # second pass look idempotent when the real API would have written twice.
      num=$(printf '%s' "$gqvars" | jq -r '.num // ""')
      f="$G/threads_$num.json"
      # A mutation carries only the global node id, exactly as the real API takes
      # it, so the fixture holding that node has to be found rather than named.
      locate() { # <node-id> <node|thread>
        local cand filt
        if [ "$2" = "thread" ]; then filt='[ .threads[]? | select(.id == $i) ] | length > 0'
        else filt='[ (.reviews[]?, (.threads[]? | .comments.nodes[]?)) | select(.id == $i) ] | length > 0'; fi
        for cand in "$G"/threads_*.json; do
          [ -s "$cand" ] || continue
          jq -e --arg i "$1" "$filt" "$cand" >/dev/null 2>&1 && { printf '%s' "$cand"; return 0; }
        done
        return 1
      }
      case "$gqquery" in
        *addReaction*)
          [ "${STUB_REACT_RC:-0}" = "0" ] || exit "${STUB_REACT_RC:-0}"
          sid=$(printf '%s' "$gqvars" | jq -r '.id // ""')
          c=$(printf '%s' "$gqvars" | jq -r '.c // ""')
          f=$(locate "$sid" node) || { echo "gh graphql stub: no fixture holds node $sid" >&2; exit 1; }
          t=$(mktemp)
          jq --arg id "$sid" --arg c "$c" '
            def mark: if (.id == $id)
              then .reactionGroups = ((((.reactionGroups // []) | map(select(.content != $c)))) + [{content: $c, viewerHasReacted: true}])
              else . end;
            .reviews = ((.reviews // []) | map(mark))
            | .threads = ((.threads // []) | map(.comments.nodes = ((.comments.nodes // []) | map(mark))))
          ' "$f" > "$t" && mv "$t" "$f"
          printf 'REACT %s %s\n' "$sid" "$c" >> "${STUB_GH_LOG:?}"
          echo '{"data":{"addReaction":{"clientMutationId":null}}}'; exit 0 ;;
        *addPullRequestReviewThreadReply*)
          [ "${STUB_REPLY_RC:-0}" = "0" ] || exit "${STUB_REPLY_RC:-0}"
          tid=$(printf '%s' "$gqvars" | jq -r '.t // ""')
          body=$(printf '%s' "$gqvars" | jq -r '.b // ""')
          f=$(locate "$tid" thread) || { echo "gh graphql stub: no fixture holds thread $tid" >&2; exit 1; }
          t=$(mktemp)
          # databaseId 0 and our own login keep the reply out of every react and
          # acted-on filter, exactly as a real reply of ours is kept out.
          jq --arg t "$tid" --arg b "$body" --arg self "${STUB_SELF_LOGIN:-}" '
            .threads = ((.threads // []) | map(
              if .id == $t then
                .comments.nodes = ((.comments.nodes // []) + [{
                  id: ($t + "-reply"), databaseId: 0,
                  author: {login: $self}, body: $b, reactionGroups: []}])
              else . end))
          ' "$f" > "$t" && mv "$t" "$f"
          printf 'REPLY %s\n' "$tid" >> "${STUB_GH_LOG:?}"
          echo '{"data":{"addPullRequestReviewThreadReply":{"clientMutationId":null}}}'; exit 0 ;;
        *resolveReviewThread*)
          [ "${STUB_RESOLVE_RC:-0}" = "0" ] || exit "${STUB_RESOLVE_RC:-0}"
          tid=$(printf '%s' "$gqvars" | jq -r '.t // ""')
          f=$(locate "$tid" thread) || { echo "gh graphql stub: no fixture holds thread $tid" >&2; exit 1; }
          t=$(mktemp)
          jq --arg t "$tid" '.threads = ((.threads // []) | map(if .id == $t then .isResolved = true else . end))' "$f" > "$t" && mv "$t" "$f"
          printf 'RESOLVE %s\n' "$tid" >> "${STUB_GH_LOG:?}"
          echo '{"data":{"resolveReviewThread":{"thread":{"isResolved":true}}}}'; exit 0 ;;
        *reviewThreads*)
          [ -z "${STUB_GQL_READ_FAIL:-}" ] || exit 1
          [ -s "$f" ] || { echo "gh graphql stub: no threads fixture for PR $num" >&2; exit 1; }
          # `first: 100` is a real cap, so a thread longer than a page comes back
          # cut to one — which is the whole reason the caller tops such a thread
          # up. A stub handing back the full list would make that read look
          # unnecessary and hide the resolve it gets wrong.
          jq -c '{data: {repository: {pullRequest: {
              reviewThreads: {pageInfo: {hasNextPage: false, endCursor: null},
                nodes: [ (.threads // [])[] | .comments.nodes = ((.comments.nodes // [])[0:100]) ]}}}}}' "$f"
          exit 0 ;;
        *PullRequestReviewThread*)
          [ -z "${STUB_GQL_READ_FAIL:-}" ] || exit 1
          [ -z "${STUB_GQL_THREAD_FAIL:-}" ] || exit 1
          tid=$(printf '%s' "$gqvars" | jq -r '.id // ""')
          f=$(locate "$tid" thread) || { echo "gh graphql stub: no fixture holds thread $tid" >&2; exit 1; }
          # The caller pages this one to exhaustion, so it answers with the whole
          # thread — the state the real API reaches after following its cursor.
          jq -c --arg t "$tid" '{data: {node: {comments: {
              pageInfo: {hasNextPage: false, endCursor: null},
              nodes: [ (.threads // [])[] | select(.id == $t) | (.comments.nodes // [])[] ]}}}}' "$f"
          exit 0 ;;
        *reviews*)
          [ -z "${STUB_GQL_READ_FAIL:-}" ] || exit 1
          [ -s "$f" ] || { echo "gh graphql stub: no threads fixture for PR $num" >&2; exit 1; }
          jq -c '{data: {repository: {pullRequest: {
              reviews: {pageInfo: {hasNextPage: false, endCursor: null}, nodes: (.reviews // [])}}}}}' "$f"
          exit 0 ;;
        *) echo "gh graphql stub: unsupported query" >&2; exit 2 ;;
      esac
    fi
    out=""
    case "$path" in
      user) out="{\"login\":\"${STUB_SELF_LOGIN:-}\"}" ;;
      */commits/*)
        br="${path##*/commits/}"
        f="$G/head_$(san "$br")"
        # No fixture = the ref does not exist (a branch a merge deleted). Real
        # gh writes the error body to STDOUT, ignores --jq, and exits non-zero.
        if [ ! -s "$f" ]; then
          printf '{"message":"No commit found for SHA: %s","documentation_url":"https://docs.github.com/rest/commits/commits#get-a-commit","status":"422"}' "$br"
          exit 1
        fi
        sha=$(cat "$f")
        repo="${path#repos/}"; repo="${repo%%/commits/*}"
        out="{\"sha\":\"$sha\",\"html_url\":\"https://github.com/$repo/commit/$sha\"}"
        # STUB_GH_COMMIT_RC: a well-formed body delivered with a non-zero exit
        # — the one failure shape no check on the output can refuse.
        if [ -n "${STUB_GH_COMMIT_RC:-}" ]; then
          if [ -n "$jqexpr" ]; then printf '%s' "$out" | jq -r "$jqexpr"; else printf '%s\n' "$out"; fi
          exit "$STUB_GH_COMMIT_RC"
        fi ;;
      */compare/*)
        # basehead is `<base>...<head>`; the fixture is named for it with the
        # branch slashes flattened. No fixture = a compare that does not read,
        # which the real endpoint also answers with a body and a non-zero exit.
        bh="${path##*/compare/}"
        f="$G/compare_$(san "$bh").json"
        if [ ! -s "$f" ]; then
          printf '{"message":"Not Found","status":"404"}'
          exit 1
        fi
        out="$(cat "$f")" ;;
      */pulls/*/reviews/*/dismissals)
        printf 'DISMISS %s\n' "$path" >> "${STUB_GH_LOG:?}"
        exit "${STUB_DISMISS_RC:-0}" ;;
      */pulls/*/reviews*)
        n="${path##*/pulls/}"; n="${n%%/*}"
        f="$G/reviews_$n.json"
        [ -s "$f" ] && out="$(cat "$f")" || out='[]' ;;
      */pulls/*/comments*)
        n="${path##*/pulls/}"; n="${n%%/*}"
        f="$G/comments_$n.json"
        [ -s "$f" ] && out="$(cat "$f")" || out='[]' ;;
      */rules/branches/*)
        b="${path##*/rules/branches/}"
        f="$G/rules_$(san "$b").json"
        [ -s "$f" ] && out="$(cat "$f")" || out='[]' ;;
      */branches/*)
        b="${path##*/branches/}"
        f="$G/branch_$(san "$b").json"
        [ -s "$f" ] && out="$(cat "$f")" || out="{\"name\":\"$b\"}" ;;
      *) echo "gh api stub: unsupported '$path'" >&2; exit 2 ;;
    esac
    if [ -n "$jqexpr" ]; then printf '%s' "$out" | jq -r "$jqexpr"; else printf '%s\n' "$out"; fi ;;
  *) echo "gh stub: unsupported '$sub'" >&2; exit 2 ;;
esac
STUB
}

_write_git_stub() {
cat > "$BIN/git" <<'STUB'
#!/usr/bin/env bash
set -u
case "$*" in
  *"remote get-url origin"*) echo "${STUB_ORIGIN_URL:-}" ;;
  *"symbolic-ref"*) echo "origin/${STUB_ORIGIN_HEAD:-main}" ;;
  # The checkout a merge pass runs over. Empty by default, which is a host with
  # no repository under it and therefore no committed artifact to keep current.
  *"rev-parse --show-toplevel"*) printf '%s\n' "${STUB_TOPLEVEL:-}" ;;
  *"rev-parse --verify --quiet"*) printf '%s\n' "${STUB_FETCHED_HEAD:-}" ;;
  *"fetch "*) exit "${STUB_FETCH_RC:-0}" ;;
  *"ls-remote"*)
    # STUB_LS_REMOTE names a file of branch names, one per line, served in
    # ls-remote's own "<sha>\trefs/heads/<name>" shape. STUB_LS_REMOTE_RC
    # models the unreachable remote: real git prints nothing and exits
    # non-zero, which no check on the output alone can tell from "no refs".
    [ -n "${STUB_LS_REMOTE_RC:-}" ] && exit "$STUB_LS_REMOTE_RC"
    while IFS= read -r b; do
      [ -n "$b" ] || continue
      printf '%s\trefs/heads/%s\n' "$(printf '%s' "$b" | sha1sum | cut -d' ' -f1)" "$b"
    done < "${STUB_LS_REMOTE:-/dev/null}"
    exit 0 ;;
  *) exit 0 ;;
esac
STUB
}
