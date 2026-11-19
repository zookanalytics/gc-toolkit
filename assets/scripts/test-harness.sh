#!/usr/bin/env bash
# test-harness.sh — shared fixtures for the pack's shell suites. Sourced by
# *.test.sh (never run as a suite itself). Provides the compiled fake gc
# (services/gctk/internal/gcbd/fakegc) over a JSON bead store, stub gh and git
# binaries, readers of the store, and assertion helpers. The fakes log their
# calls, and tests assert on the logs, the store, and exit codes
# (docs/testing.md).
# Contract: caller sets TMP (tempdir); harness_init installs the fakes on PATH
# and exports the STUB_* env they read, and GC_QUEUE_PRIORITY_TOOL, this tree's
# priority writer over the stub store. No live city, network, gc, bd or gh: the
# test floor (tools/test-floor) sits beneath the fakes, so a call none answers
# is refused rather than handed to the real binary.
# Sourcing it only defines functions, except in a suite that declares run-tests
# parts and is run directly: there it runs each part in a process of its own and
# exits (harness_run_parts, at the end of this file).

ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 (found '$2' in: $1)" ;; *) ok "$3" ;; esac; }

# Build gctk from THIS checkout, for a suite whose scripts reach lifecycle.sh or
# merge.sh. Each execs its gctk subcommand and has no other implementation, so
# such a suite needs a binary, and the one it needs is built from the tree under
# test.
# Call this BEFORE harness_init: the stub git harness_init puts on PATH answers
# nothing, and the build must not read a fixture. -buildvcs=false keeps the
# toolchain off git entirely; no assertion reads the binary's version.
# A build that does not happen is recorded in GCTK_BUILD_ERR, and harness_init
# turns it into the suite's first failure. Otherwise the suite would fail every
# lifecycle transition and never name the cause.
harness_build_gctk() {
  GCTK_BUILT=""; GCTK_BUILD_ERR=""; GCTK_BUILD_LOG="$TMP/gctk-build.log"
  local mod
  mod="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../services/gctk" && pwd)"
  if ! command -v go >/dev/null 2>&1; then
    GCTK_BUILD_ERR="no Go toolchain: gctk was not built, so lifecycle.sh, merge.sh and epic.sh had nothing to exec in this suite"
  elif ( cd "$mod" && go build -buildvcs=false -o "$TMP/gctk" ./cmd/gctk ) >"$GCTK_BUILD_LOG" 2>&1; then
    GCTK_BUILT="$TMP/gctk"
  else
    GCTK_BUILD_ERR="gctk did not build, so lifecycle.sh, merge.sh and epic.sh had nothing to exec in this suite — $(tail -3 "$GCTK_BUILD_LOG" | tr '\n' ' ')"
  fi
}

harness_init() {
  PASS=0; FAIL=0
  # These suites run from a tree inside a live city, whose session environment
  # exports GC_* and BEADS_* — the rig, the city path, the actor, the bead under
  # work. Scripts under test branch on those: a set GC_RIG adds `--rig <rig>` to
  # a logged sling argv, so an inherited value would settle a hermetic assertion
  # on the operator's shell rather than on the code. Clear both namespaces so the
  # harness owns the environment; a suite that wants a rig exports it after
  # harness_init returns. GCTK_* is left out of that sweep, because GCTK_BUILT
  # carries the binary harness_build_gctk left; GCTK_BIN is pinned just below.
  unset "${!GC_@}" "${!BEADS_@}" 2>/dev/null || true
  BIN="$TMP/bin"; GH_DIR="$TMP/gh"
  mkdir -p "$BIN" "$GH_DIR"
  # Pin gctk to the binary this suite built from the checkout, or to none. The
  # scripts resolve a deployed `gctk` from the ambient city otherwise, and these
  # suites run from a tree INSIDE a live city, so left alone a suite would test
  # whichever binary that city last built. A suite that built nothing reaches no
  # binary at all: lifecycle.sh, merge.sh and epic.sh refuse under
  # GCTK_BIN=none, and pr-status-label.sh derives nothing. The pin names a
  # scratch city of the suite's own as gctk's city when nothing names one, for
  # the lock the arm's verbs take under the city's runtime directory: the sweep
  # above cleared the session's, and the ambient city is a live one.
  export GCTK_BIN=none
  if [ -n "${GCTK_BUILT:-}" ]; then
    mkdir -p "$TMP/gctk-city/.gc"
    {
      printf '#!/bin/sh\n'
      printf 'GC_CITY_PATH="${GC_CITY_PATH:-%s}" exec '"'"'%s'"'"' "$@"\n' "$TMP/gctk-city" "$GCTK_BUILT"
    } > "$TMP/gctk-pin" && chmod +x "$TMP/gctk-pin" && GCTK_BIN="$TMP/gctk-pin"
  fi
  [ -z "${GCTK_BUILD_ERR:-}" ] || bad "$GCTK_BUILD_ERR"
  # Pin the gctk read seam to the fake `gc` for the same reason: `gctk`'s
  # bead reads prefer the running supervisor's API, and these suites run inside
  # a live city whose supervisor is up, so left alone a read would answer from
  # that live store instead of the fake's. GC_NO_API=1 keeps every read on the
  # `gc bd` subprocess the fake serves (services/gctk/internal/daemon).
  export GC_NO_API=1
  export STUB_STORE="$TMP/beads.json"
  export STUB_DEPS="$TMP/deps.txt"
  export STUB_KV="$TMP/kv.txt"
  export STUB_COMMENTS="$TMP/comments.json"
  export STUB_GC_LOG="$TMP/gc.log"
  export STUB_GH_LOG="$TMP/gh.log"
  export STUB_GH_DIR="$GH_DIR"
  export STUB_SESSION_LOG="$TMP/session.log"
  export STUB_ORIGIN_URL="https://github.com/zook/gc-toolkit"
  export STUB_ORIGIN_HEAD="main"
  export STUB_SELF_LOGIN="gc-city-bot" STUB_SELF_LOGIN_RC=""
  export STUB_UPDATE_FAIL="" STUB_CLOSE_FAIL="" STUB_DROP_KEYS="" STUB_ENFORCE_BLOCKS=""
  export STUB_LIST_FAIL="" STUB_LIST_FAIL_ON="" STUB_SHOW_FAIL=""
  # STUB_SHOW_NOTICE: when set to a rig name, `gc bd show` leads its stdout with a
  # `gc bd: answering from the rig "<name>" store` notice line, the contaminant a
  # real read can carry. Unset leaves the JSON clean.
  export STUB_SHOW_NOTICE=""
  export STUB_CREATE_FAIL="" STUB_CREATE_GARBAGE=""
  export STUB_SLING_FAIL="" STUB_DEP_GARBAGE="" STUB_DEP_ADD_FAIL="" STUB_KV_FAIL=""
  export STUB_LS_REMOTE="" STUB_LS_REMOTE_RC=""
  export STUB_TOPLEVEL="" STUB_FETCHED_HEAD="" STUB_FETCH_RC=""
  export STUB_PR_CREATE_URL="" STUB_PR_CREATE_RC=0 STUB_PR_MERGE_RC=0 STUB_DISMISS_RC=0
  export STUB_PR_EDIT_RC=0 STUB_TIMELINE_RC=""
  export STUB_GQL_READ_FAIL="" STUB_GQL_COMMITS_FAIL="" STUB_REACT_RC=0 STUB_REPLY_RC=0 STUB_RESOLVE_RC=0
  export STUB_DELETE_SOURCE_RC="" STUB_DELETE_SOURCE_OUT="" STUB_REOPEN_SOURCE_RC=""
  export STUB_DELETE_SOURCE_HANG="" STUB_REOPEN_SOURCE_HANG="" STUB_REOPEN_SOURCE_STALL=""
  # Session roster for `gc session list`. Unset = no stdout (the historical
  # behaviour every existing suite relies on); a file path serves that roster;
  # STUB_SESSION_LIST_RC models the read the liveness guard must fail closed on.
  export STUB_SESSIONS="" STUB_SESSION_LIST_RC=""
  # The `close` verb's ownership check (see its handler). Off = any actor closes.
  export STUB_ENFORCE_CLOSE_OWNER=""
  # The rig list `gc rig list` prints, and the hook a case runs before the call
  # it names (the fake's doc.go). Unset, the rig list names no rig and no hook
  # runs.
  export STUB_RIGS="" STUB_HOOK_AT="" STUB_HOOK=""
  { echo '[]' > "$STUB_STORE" && echo '[]' > "$STUB_COMMENTS" && : > "$STUB_DEPS" && : > "$STUB_KV" && : > "$STUB_GC_LOG" && : > "$STUB_GH_LOG" \
      && : > "$STUB_SESSION_LOG"; } || {
    echo "harness_init: the store files under $TMP could not be written; not running" >&2; exit 2; }
  # A copy, never a link: a suite that writes a gc of its own over $BIN/gc
  # would otherwise write into the binary every suite of the run shares.
  _harness_fake_gc
  if ! { rm -f "$BIN/gc" && cp "$HARNESS_FAKE_GC" "$BIN/gc"; }; then
    echo "harness_init: the fake gc could not be copied to $BIN; not running" >&2; exit 2
  fi
  _write_gh_stub; _write_git_stub
  chmod +x "$BIN/gh" "$BIN/git"
  # The fakes live in TMP, which can go while a script under test still runs:
  # a suite killed by a signal its children never get removes TMP from its EXIT
  # trap. The test floor goes directly beneath them, so a PATH search that
  # misses a fake lands on a refusal, never on the real gc that finds the live
  # city from the working directory
  # (tools/test-floor/refuse.sh). harness/ refuses git, which this harness
  # stubs and other suites run for real. A tree without the floor does not run.
  local floor
  floor="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../tools/test-floor" 2>/dev/null && pwd)" || floor=""
  if [ -z "$floor" ] || [ ! -x "$floor/gc" ] || [ ! -x "$floor/harness/git" ]; then
    echo "harness_init: no test floor at tools/test-floor, so nothing would stand between the fakes and the real gc, bd, gh and git; not running" >&2
    exit 2
  fi
  export PATH="$BIN:$floor/harness:$floor:$PATH"
  # The priority writer a script under test reaches through
  # GC_QUEUE_PRIORITY_TOOL: this tree's queue-priority.sh over the stub store.
  # The writer finds a bead's store in the rig list, which the fake does not
  # serve, so the wrapper names a store directory of the harness's own, where
  # the writer keeps its lock.
  local here
  here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
  mkdir -p "$TMP/qp-rig/.beads"
  { _stub_shebang; printf 'exec %q "$@" --db %q\n' "$here/queue-priority.sh" "$TMP/qp-rig/.beads"; } > "$BIN/queue-priority"
  chmod +x "$BIN/queue-priority"
  export GC_QUEUE_PRIORITY_TOOL="$BIN/queue-priority"
  # run-lib.sh's verbs, answered from this store. A script under test sources
  # run-lib.sh through GC_RUN_LIB, so it gets run-lib.stub.sh, which serves the
  # runs $BIN/harness-runs prints at each call: the runs the store's roots and
  # convoys make, each row carrying its edges from the dep rows, by run-lib.sh's
  # own run_rows. A case's roots and convoys are the runs it reads, and no stub
  # here answers the reads behind them.
  { _stub_shebang; printf '. %q || exit 1\n' "$here/run-lib.sh"; cat <<'RUNS'
# A dep row is "A|TYPE|B": A <TYPE>-edges B, an edge that sits on A for every
# type but blocks.
jq -c --rawfile d "$STUB_DEPS" "$RUN_JQ"'
  [ $d | split("\n")[] | select(length > 0) | split("|") | select(.[1] != "blocks")
    | {issue_id: .[0], depends_on_id: .[2], type: .[1]} ] as $e
  | map(. as $r | .dependencies = ((.dependencies // []) + [ $e[] | select(.issue_id == (($r.id // "") | tostring)) ]))
  | run_rows' "$STUB_STORE"
RUNS
  } > "$BIN/harness-runs"
  chmod +x "$BIN/harness-runs"
  export GC_RUN_LIB="$here/run-lib.stub.sh" RUN_LIB_STUB_CMD="$BIN/harness-runs" RUN_LIB_STUB_FAIL="" RUN_LIB_STUB_LOG=""
}

# A failed write of the store is a failed suite, never a store left as it was.
store() { printf '%s' "$1" > "$STUB_STORE" || { bad "store: the write of $STUB_STORE failed"; return 1; }; }
# The readers of what a bead carries ask the fake gc, which answers them without
# a line in STUB_GC_LOG, and start no jq (fakegc's harnessRead).
meta()  { "$HARNESS_FAKE_GC" --harness-read meta "$1" "$2"; }
bstatus() { "$HARNESS_FAKE_GC" --harness-read status "$1"; }
bassignee() { "$HARNESS_FAKE_GC" --harness-read assignee "$1"; }
# A bead's priority, bd's default 2 when none was written, and the priority a
# sling poured its workflow at, which the fake's sling records.
bprio() { "$HARNESS_FAKE_GC" --harness-read priority "$1"; }
bpoured() { "$HARNESS_FAKE_GC" --harness-read poured "$1"; }
# Every parent a bead carries, comma-joined and empty for none: its parent-child
# edges in the dep rows, and the parent field a create or update wrote.
bparents() { "$HARNESS_FAKE_GC" --harness-read parents "$1"; }
notes() { "$HARNESS_FAKE_GC" --harness-read notes "$1"; }
# A field of a bead's row (bfield <id> <name>), the beads its edges of a type
# point at (bedges <id> <type>), the beads with such an edge onto it (bonto <id>
# <type>), its comments, a line each (bcomments <id>), and the ids of the beads
# whose fields hold given values (bids [<name>=<value>...]). Each answer's form
# is in fakegc's read.go.
bfield() { "$HARNESS_FAKE_GC" --harness-read field "$1" "$2"; }
bedges() { "$HARNESS_FAKE_GC" --harness-read edges "$1" "$2"; }
bonto() { "$HARNESS_FAKE_GC" --harness-read onto "$1" "$2"; }
bcomments() { "$HARNESS_FAKE_GC" --harness-read comments "$1"; }
bids() { "$HARNESS_FAKE_GC" --harness-read ids "$@"; }
# The fixture writers set the state a case starts from, as `store` does for the
# whole store, without a line in STUB_GC_LOG: brow <id> [<setting>...] puts a
# row in place of any under the id, bset <id> <setting>... writes to it, and
# bunset <id> <name>... removes fields or metadata keys from it. A setting is
# <name>=<value>, or <name>:=<json> for a value of another type, and a name
# metadata.<key> names a metadata key (fakegc's fixture.go). An edge is a line
# in $STUB_DEPS.
brow() { "$HARNESS_FAKE_GC" --harness-write row "$@" || bad "brow $*: the fixture write failed"; }
bset() { "$HARNESS_FAKE_GC" --harness-write set "$@" || bad "bset $*: the fixture write failed"; }
bunset() { "$HARNESS_FAKE_GC" --harness-write unset "$@" || bad "bunset $*: the fixture write failed"; }
# Readers of a JSON answer a script under test printed, such as gctk's, read by
# bash itself so a case starts no process for them. Each reads the first
# "<key>" in the text, so it suits an answer whose keys are its own and not
# repeated deeper in, and it decodes no escape: json_get <json> <key> prints
# that key's string value, json_get_strs <json> <key> the strings of its array,
# comma-joined, and json_get_ids <json> <key> the id of each object in its
# array, comma-joined. Each prints nothing for a key the text does not carry.
json_get() { local r=${1#*\""$2"\":\"}; [ "$r" = "$1" ] || printf '%s' "${r%%\"*}"; }
json_get_strs() {
  local r=${1#*\""$2"\":[}
  [ "$r" = "$1" ] && return 0
  r=${r%%]*}
  printf '%s' "${r//\"/}"
}
json_get_ids() {
  local r=${1#*\""$2"\":[} out=""
  [ "$r" = "$1" ] && return 0
  r=${r%%]*}
  while [[ $r == *'"id":"'* ]]; do r=${r#*\"id\":\"}; out="$out,${r%%\"*}"; r=${r#*\"}; done
  printf '%s' "${out#,}"
}

# Copy the SUT and the named siblings into a private scripts dir so $0-relative
# sibling resolution hits stubs/copies, never the live tree.
mk_sut_dir() { # <dir> <file>...
  local d="$1"; shift
  mkdir -p "$d"
  local f
  for f in "$@"; do cp "$f" "$d/"; chmod +x "$d/$(basename "$f")"; done
  # bd-lib.sh (the shared bead-store reads) and pace-lib.sh (the cadence arms'
  # visit order and time budget) are libraries SUTs source by sibling path, and
  # gctk-resolve.sh is what every ported script (lifecycle.sh among them) sources
  # the same way. pr-post.sh is the single writer of the city's PR posts and the
  # owner of the provenance definition every feedback reader asks, so a SUT that
  # posts or reads feedback runs it by sibling path. work-outcome.sh is the
  # gc.work_outcome stamp a conversation's closers source by sibling path, and
  # conversation.sh the one shell definition of a conversation, which
  # blocker-holder.sh sources the same way. Copy
  # each of them beside the SUT so those calls resolve in the private dir; cp
  # keeps pr-post.sh's executable bit. They sit beside this harness, so they are found whatever the
  # SUT's own directory is.
  local here lib; here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
  for lib in "$here/bd-lib.sh" "$here/pace-lib.sh" "$here/gctk-resolve.sh" "$here/pr-post.sh" "$here/work-outcome.sh" "$here/conversation.sh"; do
    [ -f "$lib" ] && cp "$lib" "$d/"
  done
  # review-verdict.sh, the approval rule, review-dismissal.sh, what a dismissal
  # retires, review-answer.sh, what the living answer to a review shows,
  # dispatch-path.sh, the one definition of a dispatch path and a label hold,
  # which gc-helm.sh sources to ask how a bead is dispatched, priority-lib.sh,
  # the priority function, whose reading of a PR's approval pr-facts.sh
  # sources, git-lib.sh, the one read of a branch's head on origin, which
  # gate-ensure.sh and signoff.sh source, and run-lib.sh, the one reader of a
  # run's link to its bead, are sourced by sibling path the same way.
  [ -f "$here/review-verdict.sh" ] && cp "$here/review-verdict.sh" "$d/"
  [ -f "$here/review-dismissal.sh" ] && cp "$here/review-dismissal.sh" "$d/"
  [ -f "$here/review-answer.sh" ] && cp "$here/review-answer.sh" "$d/"
  [ -f "$here/dispatch-path.sh" ] && cp "$here/dispatch-path.sh" "$d/"
  [ -f "$here/priority-lib.sh" ] && cp "$here/priority-lib.sh" "$d/"
  [ -f "$here/git-lib.sh" ] && cp "$here/git-lib.sh" "$d/"
  [ -f "$here/run-lib.sh" ] && cp "$here/run-lib.sh" "$d/"
  return 0
}

# The interpreter line every stub starts with. A `#!/usr/bin/env bash` stub costs
# two execs per call, env's and then bash's, and the suite calls its stubs tens
# of thousands of times, so the stubs name the bash running this harness
# directly: the one on PATH that run-tests.sh (or the operator) already picked.
# env stays the fallback for a bash that does not report its own path.
_stub_shebang() {
  if [ -n "${BASH:-}" ] && [ -x "${BASH:-}" ]; then printf '#!%s\n' "$BASH"
  else printf '#!/usr/bin/env bash\n'; fi
}

# The compiled fake gc (services/gctk/internal/gcbd/fakegc): the one a run of
# tools/run-tests.sh built and named in RUN_TESTS_FAKE_GC, else the one an
# earlier harness_init of this run built, else one this suite builds from the
# checkout, which it exports for the suites it runs in turn. A suite with none
# does not run, because nothing else answers its gc calls.
_harness_fake_gc() {
  if [ -n "${RUN_TESTS_FAKE_GC:-}" ] && [ -x "$RUN_TESTS_FAKE_GC" ]; then
    HARNESS_FAKE_GC="$RUN_TESTS_FAKE_GC"; return 0
  fi
  [ -n "${HARNESS_FAKE_GC:-}" ] && [ -x "$HARNESS_FAKE_GC" ] && return 0
  local mod log="$TMP/fake-gc-build.log"
  mod="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../services/gctk" 2>/dev/null && pwd)" || mod=""
  if [ -z "$mod" ] || ! command -v go >/dev/null 2>&1; then
    echo "harness_init: no Go toolchain, or no services/gctk beside the harness, so the fake gc was not built; not running" >&2
    exit 2
  fi
  if ! ( cd "$mod" && go build -buildvcs=false -o "$TMP/fake-gc" ./internal/gcbd/fakegc ) >"$log" 2>&1; then
    echo "harness_init: the fake gc did not build; not running: $(tail -3 "$log" | tr '\n' ' ')" >&2
    exit 2
  fi
  export HARNESS_FAKE_GC="$TMP/fake-gc"
}

_write_gh_stub() {
cat > "$BIN/gh" <<'STUB'
#!/usr/bin/env bash
set -u
printf '%s\n' "$*" >> "${STUB_GH_LOG:?}"
G="${STUB_GH_DIR:?}"
san() { printf '%s' "${1//\//_}"; }
sub="${1:-}"; shift || true
case "$sub" in
  pr)
    v="${1:-}"; shift || true
    case "$v" in
      view)
        n="${1:-}"; shift || true
        f="$G/pr_view_$n.json"
        # Honour -q/--jq like real gh, so a caller reading one field (e.g.
        # `--json labels -q '.labels[].name'`) gets that field, not the whole row.
        vq=""; vj=""
        while [ $# -gt 0 ]; do
          case "$1" in
            -q|--jq) shift; vq="${1:-}" ;;
            --json) shift; vj="${1:-}" ;;
            --json=*) vj="${1#--json=}" ;;
          esac
          shift || true
        done
        # pr_view_<n>.queue/<fields>/ answers the reads that ask for exactly
        # `--json <fields>`, ahead of the fixture. Each such read takes the first
        # file there in glob order and removes it, and the fixture answers once
        # the queue is empty. That scripts a PR whose answer changes between two
        # reads, the way GitHub's lazily computed merge state does, and a read of
        # any other field set never takes an answer queued for this one. Glob
        # order puts 10.json before 2.json, so number the files at one width
        # (01.json, 02.json). An empty file is a read that fails, and it is
        # consumed like any other.
        qf=""
        if [ -n "$vj" ]; then
          for qf in "$G/pr_view_$n.queue/$vj"/*.json; do break; done
        fi
        if [ -f "$qf" ]; then f="$qf"; else qf=""; fi
        if [ ! -s "$f" ]; then
          [ -z "$qf" ] || rm -f "$qf"
          echo "gh: no such pr" >&2; exit 1
        fi
        if [ -n "$vq" ]; then jq -r "$vq" "$f"; else cat "$f"; fi; vrc=$?
        [ -z "$qf" ] || rm -f "$qf"
        exit "$vrc" ;;
      list)
        br=""
        while [ $# -gt 0 ]; do
          case "$1" in --head) shift; br="${1:-}" ;; esac
          shift || true
        done
        f="$G/pr_list_$(san "$br").json"
        [ -s "$f" ] && cat "$f" || echo '[]' ;;
      merge)   exit "${STUB_PR_MERGE_RC:-0}" ;;
      comment)
        # A Conversation comment, the post pr-post.sh's comment verb makes. On a
        # PR with a threads fixture it MUTATES what the next reads serve: the
        # comment joins .issue_comments there and issue_comments_<n>.json under
        # STUB_SELF_LOGIN, so a caller that reads its own posts back is
        # idempotent because it found its write, and its URL is printed the way
        # gh prints it, so a caller reading the new comment's id back gets one.
        # Its databaseId is 9000 plus the fixture's comment count, clear of the
        # ids the suites pick. On a PR with no threads fixture nothing reads the
        # post back. STUB_PR_COMMENT_RC models a post the API refuses;
        # STUB_PR_COMMENT_QUIET makes it land and print nothing, so the caller
        # cannot read the new id back. A body over 65,536 characters is refused,
        # as GitHub refuses it.
        [ "${STUB_PR_COMMENT_RC:-0}" = "0" ] || exit "${STUB_PR_COMMENT_RC:-0}"
        n="${1:-}"; shift || true
        b=""; rq=""
        while [ $# -gt 0 ]; do
          case "$1" in
            --body) shift; b="${1:-}" ;;
            --body=*) b="${1#--body=}" ;;
            --repo) shift; rq="${1:-}" ;;
          esac
          shift || true
        done
        [ "${#b}" -le 65536 ] || { echo "gh pr stub: Body is too long (maximum is 65536 characters)" >&2; exit 1; }
        printf 'PRCOMMENT %s\n' "$n" >> "${STUB_GH_LOG:?}"
        f="$G/threads_$n.json"
        [ -s "$f" ] || exit 0
        db=$(jq '[ (.threads[]? | .comments.nodes[]?), .issue_comments[]? ] | length + 9000' "$f")
        t="${f%/*}/.gc-stub.$$"
        jq --arg n "$n" --argjson db "$db" --arg b "$b" --arg self "${STUB_SELF_LOGIN:-}" '
          .issue_comments = ((.issue_comments // []) + [{ id: "FI-\($n)-\($db)", databaseId: $db, author: {login: $self}, body: $b, reactionGroups: [] }])
        ' "$f" > "$t" && mv "$t" "$f"
        r="$G/issue_comments_$n.json"
        [ -s "$r" ] || echo '[]' > "$r"
        jq -c --argjson db "$db" --arg b "$b" --arg self "${STUB_SELF_LOGIN:-}" \
          '. + [{ id: $db, user: {login: $self}, body: $b }]' "$r" > "$r.tmp" && mv "$r.tmp" "$r"
        [ -n "${STUB_PR_COMMENT_QUIET:-}" ] || echo "https://${rq:-github.com/zook/gc-toolkit}/pull/$n#issuecomment-$db"
        exit 0 ;;
      ready)   exit "${STUB_PR_READY_RC:-0}" ;;
      edit)
        # The edit MUTATES the fixture the next `pr view` serves, so a second
        # pass over an unchanged store is idempotent because the caller read
        # back its own write — not because the stub forgot it. --title is
        # recorded the same way, so a suite can assert it was never passed.
        n="${1:-}"; shift || true
        f="$G/pr_view_$n.json"
        [ -s "$f" ] || { echo "gh: no such pr" >&2; exit 1; }
        [ "${STUB_PR_EDIT_RC:-0}" = "0" ] || exit "${STUB_PR_EDIT_RC:-0}"
        LBLS="$G/labels.json"; [ -s "$LBLS" ] || echo '[]' > "$LBLS"
        while [ $# -gt 0 ]; do
          case "$1" in
            --body-file)
              shift
              [ -f "${1:-}" ] || { echo "gh: no such body file" >&2; exit 1; }
              t="${f%/*}/.gc-stub.$$"
              jq --rawfile b "$1" '.body = $b' "$f" > "$t" && mv "$t" "$f" ;;
            --title) shift; t="${f%/*}/.gc-stub.$$"
              jq --arg v "${1:-}" '.title = $v' "$f" > "$t" && mv "$t" "$f" ;;
            # Labels mutate .labels so the next `pr view` reads them back — a
            # second reconcile over an unchanged store is a no-op because the
            # caller read its own write. --add-label refuses a label that does
            # not exist in the repo (labels.json), exactly as real gh does, so a
            # test proves the writer created the label first.
            --add-label)
              shift
              IFS=',' read -r -a _adds <<< "${1:-}"
              for _l in ${_adds[@]+"${_adds[@]}"}; do
                _l="${_l#"${_l%%[![:space:]]*}"}"; _l="${_l%"${_l##*[![:space:]]}"}"
                [ -n "$_l" ] || continue
                if ! jq -e --arg n "$_l" 'any(.[]?; .name == $n)' "$LBLS" >/dev/null 2>&1; then
                  echo "gh: label '$_l' not found in repo" >&2; exit 1
                fi
                t="${f%/*}/.gc-stub.$$"
                jq --arg n "$_l" '.labels = ((.labels // []) | if any(.[]?; .name == $n) then . else . + [{name: $n}] end)' "$f" > "$t" && mv "$t" "$f"
              done ;;
            --remove-label)
              shift
              IFS=',' read -r -a _rms <<< "${1:-}"
              for _l in ${_rms[@]+"${_rms[@]}"}; do
                _l="${_l#"${_l%%[![:space:]]*}"}"; _l="${_l%"${_l##*[![:space:]]}"}"
                [ -n "$_l" ] || continue
                t="${f%/*}/.gc-stub.$$"
                jq --arg n "$_l" '.labels = ((.labels // []) | map(select(.name != $n)))' "$f" > "$t" && mv "$t" "$f"
              done ;;
          esac
          shift || true
        done
        exit 0 ;;
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
    path=""; jqexpr=""; gqvars='{}'; gqquery=""; method=""
    # The -f/-F variables. gqv holds each by name, a later value for a name
    # replacing the earlier one, and gqkeys the names in the order they first
    # came. $gqvars is the same variables as one JSON object, built by a single
    # jq once the arguments are read, so a request costs one process for its
    # variables however many it carries. A handler reads one through gqvar.
    declare -A gqv=(); gqkeys=()
    while [ $# -gt 0 ]; do
      case "$1" in
        --hostname) shift ;;
        --jq) shift; jqexpr="${1:-}" ;;
        --paginate) : ;;
        -X|--method) method="${2:-}"; shift ;;
        --method=*) method="${1#--method=}" ;;
        -f|-F)
          kv="${2:-}"; shift
          k="${kv%%=*}"; v="${kv#*=}"
          if [ "$k" = "query" ]; then gqquery="$v"
          else [ -n "${gqv[$k]+set}" ] || gqkeys+=("$k"); gqv[$k]="$v"; fi ;;
        --*) : ;;
        *) [ -z "$path" ] && path="$1" ;;
      esac
      shift || true
    done
    if [ "${#gqkeys[@]}" -gt 0 ]; then
      gqargs=()
      for k in "${gqkeys[@]}"; do gqargs+=(--arg "$k" "${gqv[$k]}"); done
      gqvars=$(jq -cn '$ARGS.named' "${gqargs[@]}")
    fi
    # gqvar <var> <name>: the request variable <name> into <var>, empty when the
    # request carries none, its trailing newlines dropped the way reading it
    # back out of $gqvars through a command substitution drops them.
    gqvar() {
      local val="${gqv[$2]-}"
      while [ "${val%$'\n'}" != "$val" ]; do val="${val%$'\n'}"; done
      printf -v "$1" '%s' "$val"
    }
    if [ "$path" = "graphql" ]; then
      # The write-back surface: three reads plus four mutations, over a fixture
      # the mutations actually MUTATE. A stub that forgot the write would let a
      # second pass look idempotent when the real API would have written twice.
      gqvar num num
      f="$G/threads_$num.json"
      # A mutation carries only the global node id, exactly as the real API takes
      # it, so the fixture holding that node has to be found rather than named.
      # A fixture holding the node carries its id as a quoted JSON string, so one
      # grep narrows the fixtures to those before jq reads each one, and a
      # mutation's cost does not grow with the number of PR fixtures a suite has
      # written. grep lists them in glob order, the order the scan reads them in.
      locate() { # <node-id> <node|thread>
        local cand filt
        if [ "$2" = "thread" ]; then filt='[ .threads[]? | select(.id == $i) ] | length > 0'
        else filt='[ (.reviews[]?, (.threads[]? | .comments.nodes[]?), .issue_comments[]?) | select(.id == $i) ] | length > 0'; fi
        while IFS= read -r cand; do
          [ -s "$cand" ] || continue
          jq -e --arg i "$1" "$filt" "$cand" >/dev/null 2>&1 && { printf '%s' "$cand"; return 0; }
        done < <(grep -lF -- "\"$1\"" "$G"/threads_*.json 2>/dev/null)
        return 1
      }
      # GraphQL answers only the fields a query names, so a review thread's
      # comment keeps its review's state, which a dismissal is read from, and its
      # reactionGroups only for a query that asks for each. asked($q) trims a
      # list of comments to what the query $q names.
      ASKED_JQ='def asked($q):
        ($q | test("pullRequestReview\\s*\\{[^}]*\\bstate\\b")) as $st
        | ($q | test("\\breactionGroups\\b")) as $rx
        | map(if $st or (.pullRequestReview | type) != "object" then . else .pullRequestReview |= del(.state) end
              | if $rx then . else del(.reactionGroups) end);'
      case "$gqquery" in
        *pullRequests\(states:OPEN*)
          # merge.sh's visit-order read: every open PR, served as one page from
          # open_prs.json (a list of PR nodes). No fixture is an empty list, in
          # which every anchor's PR has left the open list.
          [ -z "${STUB_OPEN_PRS_FAIL:-}" ] || exit 1
          of="$G/open_prs.json"
          if [ -s "$of" ]; then nodes=$(cat "$of"); else nodes='[]'; fi
          printf '%s' "$nodes" | jq -c '{data: {repository: {pullRequests: {
              pageInfo: {hasNextPage: false, endCursor: null}, nodes: .}}}}' || exit 1
          exit 0 ;;
        *removeReaction*)
          # Drops the viewer's reaction of that content from the node, so the next
          # read shows it gone. STUB_UNREACT_RC models a removal the API refuses.
          [ "${STUB_UNREACT_RC:-0}" = "0" ] || exit "${STUB_UNREACT_RC:-0}"
          gqvar sid id
          gqvar c c
          f=$(locate "$sid" node) || { echo "gh graphql stub: no fixture holds node $sid" >&2; exit 1; }
          t="${f%/*}/.gc-stub.$$"
          jq --arg id "$sid" --arg c "$c" '
            def unmark: if (.id == $id) then .reactionGroups = ((.reactionGroups // []) | map(select(.content != $c))) else . end;
            .reviews = ((.reviews // []) | map(unmark))
            | .threads = ((.threads // []) | map(.comments.nodes = ((.comments.nodes // []) | map(unmark))))
            | .issue_comments = ((.issue_comments // []) | map(unmark))
          ' "$f" > "$t" && mv "$t" "$f"
          printf 'UNREACT %s %s\n' "$sid" "$c" >> "${STUB_GH_LOG:?}"
          echo '{"data":{"removeReaction":{"clientMutationId":null}}}'; exit 0 ;;
        *addReaction*)
          [ "${STUB_REACT_RC:-0}" = "0" ] || exit "${STUB_REACT_RC:-0}"
          gqvar sid id
          gqvar c c
          f=$(locate "$sid" node) || { echo "gh graphql stub: no fixture holds node $sid" >&2; exit 1; }
          t="${f%/*}/.gc-stub.$$"
          jq --arg id "$sid" --arg c "$c" '
            def mark: if (.id == $id)
              then .reactionGroups = ((((.reactionGroups // []) | map(select(.content != $c)))) + [{content: $c, viewerHasReacted: true}])
              else . end;
            .reviews = ((.reviews // []) | map(mark))
            | .threads = ((.threads // []) | map(.comments.nodes = ((.comments.nodes // []) | map(mark))))
            | .issue_comments = ((.issue_comments // []) | map(mark))
          ' "$f" > "$t" && mv "$t" "$f"
          printf 'REACT %s %s\n' "$sid" "$c" >> "${STUB_GH_LOG:?}"
          echo '{"data":{"addReaction":{"clientMutationId":null}}}'; exit 0 ;;
        *addPullRequestReviewThreadReply*)
          [ "${STUB_REPLY_RC:-0}" = "0" ] || exit "${STUB_REPLY_RC:-0}"
          gqvar tid t
          gqvar body b
          f=$(locate "$tid" thread) || { echo "gh graphql stub: no fixture holds thread $tid" >&2; exit 1; }
          t="${f%/*}/.gc-stub.$$"
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
          gqvar tid t
          f=$(locate "$tid" thread) || { echo "gh graphql stub: no fixture holds thread $tid" >&2; exit 1; }
          t="${f%/*}/.gc-stub.$$"
          jq --arg t "$tid" '.threads = ((.threads // []) | map(if .id == $t then .isResolved = true else . end))' "$f" > "$t" && mv "$t" "$f"
          printf 'RESOLVE %s\n' "$tid" >> "${STUB_GH_LOG:?}"
          echo '{"data":{"resolveReviewThread":{"thread":{"isResolved":true}}}}'; exit 0 ;;
        *reviewThreads*)
          [ -z "${STUB_GQL_READ_FAIL:-}" ] || exit 1
          [ -s "$f" ] || { echo "gh graphql stub: no threads fixture for PR $num" >&2; exit 1; }
          # A thread's comments come back cut to the window the query names, its
          # oldest for `first: N` and its newest for `last: N`, as the API cuts
          # them. So a thread longer than a window comes back holding exactly one,
          # which is the whole reason a caller reads such a thread again to its
          # end. A stub handing back the full list would make that read look
          # unnecessary and hide the answer it gets wrong.
          jq -c --arg q "$gqquery" "$ASKED_JQ"'
            (($q | capture("comments\\((?<end>first|last):(?<n>[0-9]+)")) // {end: "first", n: "100"}) as $w
            | ($w.n | tonumber) as $n
            | {data: {repository: {pullRequest: {
              reviewThreads: {pageInfo: {hasNextPage: false, endCursor: null},
                nodes: [ (.threads // [])[] | .comments.nodes = ((.comments.nodes // [])
                  | if $w.end == "last" then .[-$n:] else .[0:$n] end | asked($q)) ]}}}}}' "$f"
          # STUB_GQL_THREADS_TAIL: raw text after the page, the stream --paginate
          # hands back when a later page came back garbled.
          [ -n "${STUB_GQL_THREADS_TAIL:-}" ] && printf '%s\n' "$STUB_GQL_THREADS_TAIL"
          exit 0 ;;
        *PullRequestReviewThread*)
          [ -z "${STUB_GQL_READ_FAIL:-}" ] || exit 1
          [ -z "${STUB_GQL_THREAD_FAIL:-}" ] || exit 1
          gqvar tid id
          f=$(locate "$tid" thread) || { echo "gh graphql stub: no fixture holds thread $tid" >&2; exit 1; }
          # The caller pages this one to exhaustion, so it answers with the whole
          # thread — the state the real API reaches after following its cursor.
          jq -c --arg t "$tid" --arg q "$gqquery" "$ASKED_JQ"'{data: {node: {comments: {
              pageInfo: {hasNextPage: false, endCursor: null},
              nodes: ([ (.threads // [])[] | select(.id == $t) | (.comments.nodes // [])[] ] | asked($q))}}}}' "$f"
          exit 0 ;;
        *commits\(first:100,after:*)
          # The PR's commits, which a fix's answer cites. Served from the PR
          # fixture's .commits, a list of {oid, message, parents} where parents is
          # the parent count (2 for a merge, 1 when absent). A fixture with no list
          # is a PR none of whose commits names a fix unit. Each read is logged, so
          # a test can tell the read is made only for an answer that is posted.
          # STUB_GQL_COMMITS_FAIL models a commit read the API refuses.
          [ -z "${STUB_GQL_READ_FAIL:-}" ] || exit 1
          [ -z "${STUB_GQL_COMMITS_FAIL:-}" ] || exit 1
          [ -s "$f" ] || { echo "gh graphql stub: no threads fixture for PR $num" >&2; exit 1; }
          printf 'COMMITS %s\n' "$num" >> "${STUB_GH_LOG:?}"
          jq -c '{data: {repository: {pullRequest: {
              commits: {pageInfo: {hasNextPage: false, endCursor: null},
                nodes: [ (.commits // [])[]
                         | {commit: {oid, message, parents: {totalCount: (.parents // 1)}}} ]}}}}}' "$f"
          exit 0 ;;
        *comments\(first:100,after:*)
          # The Conversation-tab (issue comments) read. WB_THREAD_COMMENTS_QUERY
          # carries the same token but is caught above by *PullRequestReviewThread*;
          # the reviews and reviewThreads reads never carry it. Issue comments live
          # in the same PR fixture, under .issue_comments beside .reviews/.threads.
          [ -z "${STUB_GQL_READ_FAIL:-}" ] || exit 1
          [ -s "$f" ] || { echo "gh graphql stub: no threads fixture for PR $num" >&2; exit 1; }
          jq -c '{data: {repository: {pullRequest: {
              comments: {pageInfo: {hasNextPage: false, endCursor: null},
                nodes: (.issue_comments // [])}}}}}' "$f"
          exit 0 ;;
        *reviews*)
          # The reviews, and the logins the PR has pending review requests
          # from, which the fixture keeps as .review_requests.
          [ -z "${STUB_GQL_READ_FAIL:-}" ] || exit 1
          [ -s "$f" ] || { echo "gh graphql stub: no threads fixture for PR $num" >&2; exit 1; }
          jq -c '{data: {repository: {pullRequest: {
              reviewRequests: {nodes: [ (.review_requests // [])[] | {requestedReviewer: {login: .}} ]},
              reviews: {pageInfo: {hasNextPage: false, endCursor: null}, nodes: (.reviews // [])}}}}}' "$f"
          exit 0 ;;
        *) echo "gh graphql stub: unsupported query" >&2; exit 2 ;;
      esac
    fi
    # The REST comment writes, over the same PR fixtures the reads serve: a
    # review comment on a whole file (pr-post.sh file-comment) opens a thread in
    # threads_<n>.json and joins the comments_<n>.json list, and an edit
    # (pr-post.sh edit) rewrites a Conversation comment in place in both. The
    # Conversation comment itself is `gh pr comment`, above. Each write MUTATES
    # what the next read serves, so a pass that posted twice shows two comments
    # rather than looking idempotent. A new comment's databaseId is 9000 plus
    # the fixture's comment count, clear of the ids the suites pick.
    case "${method:-GET}:$path" in
      POST:*/pulls/*/comments)
        [ "${STUB_FCOMMENT_RC:-0}" = "0" ] || exit "${STUB_FCOMMENT_RC:-0}"
        n="${path##*/pulls/}"; n="${n%%/*}"
        f="$G/threads_$n.json"
        [ -s "$f" ] || echo '{"reviews":[],"threads":[],"issue_comments":[]}' > "$f"
        gqvar b body
        gqvar p path
        db=$(jq '[ (.threads[]? | .comments.nodes[]?), .issue_comments[]? ] | length + 9000' "$f")
        t="${f%/*}/.gc-stub.$$"
        jq --arg n "$n" --argjson db "$db" --arg b "$b" --arg p "$p" --arg self "${STUB_SELF_LOGIN:-}" '
          .threads = ((.threads // []) + [{ id: "FT-\($n)-\($db)", isResolved: false, viewerCanResolve: true, path: $p,
            comments: { nodes: [{ id: "FC-\($n)-\($db)", databaseId: $db, author: {login: $self}, body: $b, reactionGroups: [] }] } }])
        ' "$f" > "$t" && mv "$t" "$f"
        r="$G/comments_$n.json"
        [ -s "$r" ] || echo '[]' > "$r"
        jq -c --argjson db "$db" --arg b "$b" --arg p "$p" --arg self "${STUB_SELF_LOGIN:-}" \
          '. + [{ id: $db, user: {login: $self}, body: $b, path: $p, pull_request_review_id: null }]' "$r" > "$r.tmp" && mv "$r.tmp" "$r"
        gqvar fst subject_type; gqvar fcommit commit_id
        printf 'FCOMMENT %s %s %s %s\n' "$n" "$p" "$fst" "$fcommit" >> "${STUB_GH_LOG:?}"
        out="{\"id\":$db}"
        if [ -n "$jqexpr" ]; then printf '%s' "$out" | jq -r "$jqexpr"; else printf '%s\n' "$out"; fi
        exit 0 ;;
      PATCH:*/issues/comments/*)
        [ "${STUB_ICEDIT_RC:-0}" = "0" ] || exit "${STUB_ICEDIT_RC:-0}"
        cid="${path##*/issues/comments/}"
        gqvar b body
        # GitHub refuses an edit to a body over 65,536 characters.
        [ "${#b}" -le 65536 ] || { echo "gh api stub: Body is too long (maximum is 65536 characters)" >&2; exit 1; }
        # The ids this stub gives new comments start over on each PR fixture, so
        # two PRs can hold one id. GitHub's ids are unique, and an edit names its
        # comment by id alone, so the stub picks the fixture whose comment with
        # that id carries the review or finding key the new body carries, and
        # otherwise the first fixture holding the id.
        key=$(printf '%s' "$b" | grep -Eo '<!-- gc-(review-answer:r[0-9]+|finding:[A-Za-z0-9._-]+) -->' | head -1)
        hit=""; first=""
        for cand in "$G"/threads_*.json; do
          [ -s "$cand" ] || continue
          jq -e --arg c "$cid" '[ .issue_comments[]? | select(((.databaseId // 0) | tostring) == $c) ] | length > 0' "$cand" >/dev/null 2>&1 || continue
          [ -n "$first" ] || first="$cand"
          if [ -z "$key" ] || jq -e --arg c "$cid" --arg k "$key" '[ .issue_comments[]? | select(((.databaseId // 0) | tostring) == $c)
               | select((.body // "") | contains($k)) ] | length > 0' "$cand" >/dev/null 2>&1; then
            hit="$cand"; break
          fi
        done
        [ -n "$hit" ] || hit="$first"
        [ -n "$hit" ] || { echo "gh api stub: no fixture holds issue comment $cid" >&2; exit 1; }
        t="${hit%/*}/.gc-stub.$$"
        jq --arg c "$cid" --arg b "$b" '.issue_comments = ((.issue_comments // []) | map(if ((.databaseId // 0) | tostring) == $c then .body = $b else . end))' \
          "$hit" > "$t" && mv "$t" "$hit"
        n="${hit##*/threads_}"; n="${n%.json}"
        r="$G/issue_comments_$n.json"
        if [ -s "$r" ]; then
          jq -c --arg c "$cid" --arg b "$b" 'map(if ((.id // 0) | tostring) == $c then .body = $b else . end)' "$r" > "$r.tmp" && mv "$r.tmp" "$r"
        fi
        printf 'ICEDIT %s\n' "$cid" >> "${STUB_GH_LOG:?}"
        out="{\"id\":$cid}"
        if [ -n "$jqexpr" ]; then printf '%s' "$out" | jq -r "$jqexpr"; else printf '%s\n' "$out"; fi
        exit 0 ;;
      DELETE:*/issues/comments/*)
        # A Conversation comment deleted: it leaves the PR fixture holding it,
        # and issue_comments_<n>.json beside it, so the next read no longer
        # serves it. STUB_ICDELETE_RC models a delete the API refuses.
        [ "${STUB_ICDELETE_RC:-0}" = "0" ] || exit "${STUB_ICDELETE_RC:-0}"
        cid="${path##*/issues/comments/}"
        hit=""
        for cand in "$G"/threads_*.json; do
          [ -s "$cand" ] || continue
          jq -e --arg c "$cid" '[ .issue_comments[]? | select(((.databaseId // 0) | tostring) == $c) ] | length > 0' "$cand" >/dev/null 2>&1 \
            && { hit="$cand"; break; }
        done
        [ -n "$hit" ] || { echo "gh api stub: no fixture holds issue comment $cid" >&2; exit 1; }
        t="${hit%/*}/.gc-stub.$$"
        jq --arg c "$cid" '.issue_comments = [ (.issue_comments // [])[] | select(((.databaseId // 0) | tostring) != $c) ]' \
          "$hit" > "$t" && mv "$t" "$hit"
        n="${hit##*/threads_}"; n="${n%.json}"
        r="$G/issue_comments_$n.json"
        if [ -s "$r" ]; then
          jq -c --arg c "$cid" 'map(select(((.id // 0) | tostring) != $c))' "$r" > "$r.tmp" && mv "$r.tmp" "$r"
        fi
        printf 'ICDELETE %s\n' "$cid" >> "${STUB_GH_LOG:?}"
        exit 0 ;;
    esac
    out=""
    case "$path" in
      user)
        # STUB_SELF_LOGIN_RC models a failed read the way real gh answers it: the
        # error body on STDOUT, --jq ignored, a non-zero exit.
        if [ "${STUB_SELF_LOGIN_RC:-0}" != 0 ]; then
          printf '{"message":"Server Error","documentation_url":"https://docs.github.com/rest","status":"502"}'
          exit "$STUB_SELF_LOGIN_RC"
        fi
        out="{\"login\":\"${STUB_SELF_LOGIN:-}\"}" ;;
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
      */pulls/*/requested_reviewers)
        # Re-request a reviewer. The reviewer login rides the -f arg the full-args
        # log above already captured; this marks the endpoint hit for a test to
        # assert, and STUB_REREQUEST_RC models a re-request the API refuses. One
        # that lands joins the PR fixture's pending review requests, as GitHub
        # records it, so the next read serves it.
        printf 'REREQUEST %s\n' "$path" >> "${STUB_GH_LOG:?}"
        [ "${STUB_REREQUEST_RC:-0}" = "0" ] || exit "${STUB_REREQUEST_RC:-0}"
        n="${path##*/pulls/}"; n="${n%%/*}"
        gqvar rr 'reviewers[]'
        f="$G/threads_$n.json"
        if [ -n "$rr" ] && [ -s "$f" ]; then
          t="${f%/*}/.gc-stub.$$"
          jq --arg r "$rr" '.review_requests = ((.review_requests // []) + [$r] | unique)' "$f" > "$t" && mv "$t" "$f"
        fi
        exit 0 ;;
      */pulls/*/reviews*|*/pulls/*/comments*)
        n="${path##*/pulls/}"; n="${n%%/*}"
        # STUB_GH_LIST_RC: the history delivered as a real gh failure. An absent
        # fixture is an EMPTY history, which a caller cannot tell from an
        # unreadable one on the output alone — only the exit code says which.
        [ -z "${STUB_GH_LIST_RC:-}" ] || exit "$STUB_GH_LIST_RC"
        case "$path" in *comments*) f="$G/comments_$n.json" ;; *) f="$G/reviews_$n.json" ;; esac
        [ -s "$f" ] && out="$(cat "$f")" || out='[]' ;;
      */pulls/*/files*)
        # The files a PR's diff touches. An absent fixture is a diff naming no
        # file; STUB_FILES_RC fails the read.
        n="${path##*/pulls/}"; n="${n%%/*}"
        [ -z "${STUB_FILES_RC:-}" ] || exit "$STUB_FILES_RC"
        f="$G/files_$n.json"
        [ -s "$f" ] && out="$(cat "$f")" || out='[]' ;;
      */issues/*/comments*)
        # The Conversation tab, a separate REST space from the /pulls comment
        # rows above. An absent fixture is an EMPTY conversation, the shape most
        # PRs have; STUB_GH_LIST_RC fails it the same way it fails the others,
        # and STUB_ISSUE_LIST_RC fails ONLY this space, to model a Conversation
        # read that breaks while the reviews and inline comments still read.
        n="${path##*/issues/}"; n="${n%%/*}"
        [ -z "${STUB_GH_LIST_RC:-}" ] || exit "$STUB_GH_LIST_RC"
        [ -z "${STUB_ISSUE_LIST_RC:-}" ] || exit "$STUB_ISSUE_LIST_RC"
        f="$G/issue_comments_$n.json"
        [ -s "$f" ] && out="$(cat "$f")" || out='[]' ;;
      */issues/*/timeline*)
        # A PR's timeline events ({event: ...} rows). An absent fixture is a PR
        # with no events; STUB_TIMELINE_RC models a timeline read that fails.
        n="${path##*/issues/}"; n="${n%%/*}"
        [ -z "${STUB_TIMELINE_RC:-}" ] || exit "$STUB_TIMELINE_RC"
        f="$G/timeline_$n.json"
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
  label)
    # The repo's label set, so `pr edit --add-label` can refuse one that was
    # never created. `list` serves it (honouring -q); `create` appends if absent;
    # `edit` rewrites a label's description, refusing one that does not exist,
    # as real gh does. Each keeps the description it was given.
    v="${1:-}"; shift || true
    LBLS="$G/labels.json"; [ -s "$LBLS" ] || echo '[]' > "$LBLS"
    case "$v" in
      list)
        lq=""
        while [ $# -gt 0 ]; do case "$1" in -q|--jq) shift; lq="${1:-}" ;; esac; shift || true; done
        if [ -n "$lq" ]; then jq -r "$lq" "$LBLS"; else cat "$LBLS"; fi ;;
      create|edit)
        name="${1:-}"; shift || true
        desc=""
        while [ $# -gt 0 ]; do case "$1" in --description) shift; desc="${1:-}" ;; esac; shift || true; done
        if [ "$v" = create ]; then
          [ "${STUB_LABEL_CREATE_RC:-0}" = "0" ] || exit "${STUB_LABEL_CREATE_RC:-0}"
          jq -e --arg n "$name" 'any(.[]?; .name == $n)' "$LBLS" >/dev/null 2>&1 && exit 0
          t="${LBLS%/*}/.gc-stub.$$"
          jq --arg n "$name" --arg d "$desc" '. + [{name: $n, description: $d}]' "$LBLS" > "$t" && mv "$t" "$LBLS"
        else
          [ "${STUB_LABEL_EDIT_RC:-0}" = "0" ] || exit "${STUB_LABEL_EDIT_RC:-0}"
          jq -e --arg n "$name" 'any(.[]?; .name == $n)' "$LBLS" >/dev/null 2>&1 \
            || { echo "gh: label '$name' not found" >&2; exit 1; }
          t="${LBLS%/*}/.gc-stub.$$"
          jq --arg n "$name" --arg d "$desc" 'map(if .name == $n then .description = $d else . end)' "$LBLS" > "$t" && mv "$t" "$LBLS"
        fi
        exit 0 ;;
      *) echo "gh label stub: unsupported '$v'" >&2; exit 2 ;;
    esac ;;
  run)
    # `run rerun <id> [--failed]`, read back from the call log above.
    # STUB_RUN_RERUN_RC models GitHub refusing the re-run.
    v="${1:-}"; shift || true
    case "$v" in
      rerun) exit "${STUB_RUN_RERUN_RC:-0}" ;;
      *) echo "gh run stub: unsupported '$v'" >&2; exit 2 ;;
    esac ;;
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
  # A rig's not-for-review.toml as its default branch carries it, served from
  # the directory -C names: a test declares by writing the file there, and with
  # no file there the branch carries none.
  *"cat-file blob "*":not-for-review.toml"*)
    dir=""; prev=""
    for a in "$@"; do [ "$prev" = "-C" ] && dir="$a"; prev="$a"; done
    [ -n "$dir" ] && [ -f "$dir/not-for-review.toml" ] || exit 128
    exec cat "$dir/not-for-review.toml" ;;
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

# Whether this run executes the named part of a suite that declares parts with
# a `# run-tests-parts:` header (tools/run-tests.sh). The suite wraps each group
# of sections in `if part <name>; then ... fi`. Every run of such a suite names
# its part in RUN_TESTS_PART, whether tools/run-tests.sh started it or a direct
# run did (harness_run_parts, below), and executes only that part. A group under
# a name the header does not declare fails every run, because no run would ever
# execute its sections. With RUN_TESTS_PART unset, every group runs.
part() { # <name>
  [ -n "${RUN_TESTS_PART:-}" ] || return 0
  if [ -n "${RUN_TESTS_PARTS:-}" ]; then
    case " $RUN_TESTS_PARTS " in
      *" $1 "*) ;;
      *) bad "part '$1' is not declared in this suite's run-tests-parts header"; return 1 ;;
    esac
  fi
  [ "$RUN_TESTS_PART" = "$1" ]
}

# A Python whose standard library has tomllib (3.11 and newer), for a suite that
# reads a formula or an order with it. A host's python3 can be older (macOS
# ships 3.9) while a newer one sits on PATH under its versioned name, so the
# search tries python3 and then each python3.N on PATH, newest first. It prints
# the path of the first one that imports tomllib and returns 0. With none, it
# prints what PATH does have and returns 1, and the suite skips the checks that
# need tomllib with that text as the reason.
tomllib_python() {
  local name path ver found=""
  for name in python3 $(compgen -c python3. 2>/dev/null | grep -xE 'python3\.[0-9]+' | sort -t. -k2,2nr -u); do
    path="$(command -v "$name")" || continue
    if "$path" -c 'import tomllib' >/dev/null 2>&1; then
      printf '%s\n' "$path"; return 0
    fi
    ver="$("$path" -c 'import platform; print(platform.python_version())' 2>/dev/null)"
    found="${found:+$found, }$path${ver:+ $ver}"
  done
  printf 'tomllib needs Python 3.11 or newer, and PATH has %s\n' "${found:-no python3}"
  return 1
}

# The parts a suite declares, read the way tools/run-tests.sh reads them: from
# the opening comment block only, which ends at the first line that is neither a
# comment nor blank, so a fixture further down that writes a declaration of its
# own is not read as the suite's.
harness_parts_of() { # <suite>
  awk '/^#/ { if (sub(/^# run-tests-parts:[[:space:]]*/, "")) { print; exit } next }
       /^[[:space:]]*$/ { next }
       { exit }' "$1"
}

# Run a suite once per declared part, in declaration order, each run a process
# of its own with RUN_TESTS_PART naming its part and RUN_TESTS_PARTS every
# declared part, as tools/run-tests.sh runs it. A part's output goes to a file
# rather than a pipe, so a background child the part leaves running cannot hold
# the run open, and it is printed when the part ends. The part's own tally, its
# last `passed: N  failed: M` line, is printed as a `# part <name>:` line
# instead, and the run ends on one tally line summed over the parts. A part that
# exits non-zero with no failure in its tally counts one, so that sum fails
# whenever a part did.
harness_run_parts() { # <suite> <parts> [<suite arg>...]
  local suite="$1" logdir log tally rc i n m passed=0 failed=0
  local -a parts=()
  read -ra parts <<<"$2"
  shift 2
  logdir="$(mktemp -d "${TMPDIR:-/tmp}/harness-parts.XXXXXX")" || {
    echo "FAIL - no temp directory for the parts' output"; return 1; }
  for i in "${!parts[@]}"; do
    log="$logdir/$i.log"
    echo "# ==== part ${parts[$i]} (RUN_TESTS_PART=${parts[$i]}) ===="
    rc=0
    RUN_TESTS_PART="${parts[$i]}" RUN_TESTS_PARTS="${parts[*]}" \
      "${BASH:-bash}" "$suite" "$@" >"$log" 2>&1 || rc=$?
    tally="$(awk '/^passed: [0-9]+  failed: [0-9]+$/ { t = $0 } END { print t }' "$log")"
    awk 'NR == FNR { if (/^passed: [0-9]+  failed: [0-9]+$/) last = FNR; next }
         FNR != last' "$log" "$log"
    if [ -n "$tally" ]; then
      n="${tally#passed: }"; n="${n%% *}"; m="${tally##*failed: }"
      echo "# part ${parts[$i]}: $n passed, $m failed"
    else
      n=0; m=0
      echo "# part ${parts[$i]}: no passed/failed line"
    fi
    if [ "$rc" -ne 0 ] && [ "$m" -eq 0 ]; then
      m=1; echo "FAIL - part ${parts[$i]} exited $rc with no failure counted"
    fi
    passed=$((passed + 10#$n)); failed=$((failed + 10#$m))
  done
  rm -rf "$logdir"
  echo
  echo "passed: $passed  failed: $failed"
  [ "$failed" -eq 0 ]
}

# A suite that declares parts, run directly with RUN_TESTS_PART unset, runs each
# part in a process of its own rather than every part in this one. A part then
# starts from the suite's own setup, never from the temp files, stub fixtures or
# shell state an earlier part left behind, so a direct run reports what
# tools/run-tests.sh reports. This runs as the suite sources the harness, before
# anything after its source line, and the process exits with the parts' result.
if [ -z "${RUN_TESTS_PART:-}" ] && [ -f "$0" ]; then
  HARNESS_PARTS="$(harness_parts_of "$0")"
  if [ -n "$HARNESS_PARTS" ]; then
    harness_run_parts "$0" "$HARNESS_PARTS" "$@"
    exit $?
  fi
fi
