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
  export STUB_STORE="$TMP/beads.json"
  export STUB_DEPS="$TMP/deps.txt"
  export STUB_GC_LOG="$TMP/gc.log"
  export STUB_GH_LOG="$TMP/gh.log"
  export STUB_GH_DIR="$GH_DIR"
  export STUB_SESSION_LOG="$TMP/session.log"
  export STUB_ORIGIN_URL="https://github.com/zook/gc-toolkit"
  export STUB_ORIGIN_HEAD="main"
  export STUB_SELF_LOGIN="gc-city-bot"
  export STUB_UPDATE_FAIL="" STUB_DROP_KEYS="" STUB_LIST_FAIL="" STUB_SHOW_FAIL=""
  export STUB_PR_CREATE_URL="" STUB_PR_CREATE_RC=0 STUB_PR_MERGE_RC=0 STUB_DISMISS_RC=0
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
  sling) exit 0 ;;
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
        [ -n "${STUB_PR_CREATE_URL:-}" ] && echo "$STUB_PR_CREATE_URL"
        exit "${STUB_PR_CREATE_RC:-0}" ;;
      *) echo "gh pr stub: unsupported '$v'" >&2; exit 2 ;;
    esac ;;
  api)
    path=""; jqexpr=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --hostname|--jq) [ "$1" = "--jq" ] && { shift; jqexpr="${1:-}"; } || shift ;;
        --paginate) : ;;
        -X) shift ;;
        -f) shift ;;
        --*) : ;;
        *) [ -z "$path" ] && path="$1" ;;
      esac
      shift || true
    done
    out=""
    case "$path" in
      user) out="{\"login\":\"${STUB_SELF_LOGIN:-}\"}" ;;
      */commits/*)
        br="${path##*/commits/}"
        f="$G/head_$(san "$br")"
        [ -s "$f" ] || { echo "gh: no head" >&2; exit 1; }
        sha=$(cat "$f")
        repo="${path#repos/}"; repo="${repo%%/commits/*}"
        out="{\"sha\":\"$sha\",\"html_url\":\"https://github.com/$repo/commit/$sha\"}" ;;
      */pulls/*/reviews/*/dismissals)
        printf 'DISMISS %s\n' "$path" >> "${STUB_GH_LOG:?}"
        exit "${STUB_DISMISS_RC:-0}" ;;
      */pulls/*/reviews*)
        n="${path##*/pulls/}"; n="${n%%/*}"
        f="$G/reviews_$n.json"
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
  *) exit 0 ;;
esac
STUB
}
