#!/usr/bin/env bash
# holds-store.stub.sh — the test seam for a suite whose script asks
# `gctk bead holds`: it builds gctk from this checkout, and it answers the reads
# gctk's store adapter makes from the suite's own fixture store, so the suite
# drives the real binary over its stub store and keeps no copy of the rule.
#
#   holds-store.stub.sh build <dir>
#       Builds gctk from this checkout into <dir>, once per directory, and
#       prints the path of a wrapper that runs it with HOLDS_STUB_READ=1 in its
#       environment. A suite exports that path as GCTK_BIN, and GC_NO_API=1, so
#       the script under test runs the build and every read stays on `gc bd`.
#       The suite's own `gc` stub sends a call made with HOLDS_STUB_READ set to
#       `answer`, since only gctk's calls carry it. The wrapper also answers the
#       `gc rig list --json` an unpinned read routes by, with $HOLDS_RIGS when
#       set and else no store, so such a read stays on the store `where` names,
#       and `gc config show --json`, with $HOLDS_CONFIG when set and else a
#       config that names no agent; every other call goes to the suite's `gc`.
#       It names a scratch city beside the build as gctk's city, so the arm's
#       dispatch locks never land in a live city. Exits 1 with the reason when
#       there is no Go toolchain or the build fails.
#
#   holds-store.stub.sh answer [--db <path>] <verb> [<args>...]
#       Answers one `gc bd` read from $HOLDS_STORE, a JSON array of rows, and
#       the dep rows in $HOLDS_DEPS when that names a file ("A|TYPE|B": A blocks
#       B for a blocks row, A <TYPE>-edges B for any other). A row's own edges
#       are its `dependencies` in either shape bd prints, its `_deps` in the show
#       shape, its `parent`, and its dep rows. An edge marked "external" stands
#       for one onto a bead in another store, as does an edge onto an id no row
#       has. A closed row that names no closed_at carries one, as every bead bd
#       closes does. The verbs are the store adapter's reads:
#         list   the rows --id, --has-metadata-key, --metadata-field, --parent,
#                --title-contains and --all select, each edge in the listing
#                shape, every edge kept; --parent selects the rows whose own
#                parent-child edge names it
#         ready  the open rows --has-metadata-key selects that `blocked` does
#                not hold, unassigned under --unassigned, of no type an
#                --exclude-type names and with no label an --exclude-label
#                names, in the listing shape; $HOLDS_READY, when set, is
#                answered verbatim
#         update the write: each --set-metadata k=v, --unset-metadata k,
#                --status and --append-notes applied to the row in
#                $HOLDS_STORE, which a bead it does not hold refuses
#         blocked  the store's blocked listing, by bd's rule over the rows: a
#                live bead (neither closed nor pinned) is blocked by a blocks or
#                conditional-blocks edge onto a live bead in this store, by a
#                waits-for edge whose spawner has a live child, or through a
#                blocked parent. It lists the bead's own live blockers, its live
#                waits-for spawners among them, or else its blocked parent, and
#                leaves out a bead with neither.
#         sql    the ids the store marks blocked, the beads `blocked` judges so
#         where  the store gc resolves, $HOLDS_WHERE or /stub/.beads, which
#                gctk pins every read to when the script names none
#       $HOLDS_BLOCKED and $HOLDS_MARKS, when set, are answered for `blocked` and
#       `sql` verbatim, the store's answers set by the test. $HOLDS_FAIL names a
#       verb, or "all", whose read fails at exit 1.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "${1:-}" in
  build)
    dir="${2:?holds-store.stub.sh build <dir>}"
    mkdir -p "$dir" || exit 1
    if [ ! -x "$dir/gctk-real" ]; then
      command -v go >/dev/null 2>&1 || { echo "holds-store.stub.sh: no Go toolchain, so gctk was not built" >&2; exit 1; }
      ( cd "$HERE/../../services/gctk" && go build -buildvcs=false -o "$dir/gctk-real" ./cmd/gctk ) > "$dir/gctk-build.log" 2>&1 || {
        echo "holds-store.stub.sh: gctk did not build: $(tail -3 "$dir/gctk-build.log" | tr '\n' ' ')" >&2; exit 1; }
    fi
    mkdir -p "$dir/shim" || exit 1
    cat > "$dir/shim/gc" <<'SHIM' || exit 1
#!/bin/sh
# The stores an unpinned gctk read routes by, from the suite; every other call
# goes to the suite's own gc, with the PATH gctk started with, so nothing that
# call runs meets this shim.
if [ "${1:-} ${2:-}" = "rig list" ]; then
  if [ -n "${HOLDS_RIGS:-}" ]; then printf '%s\n' "$HOLDS_RIGS"; else printf '%s\n' '{"rigs":[]}'; fi
  exit 0
fi
if [ "${1:-} ${2:-}" = "config show" ]; then
  if [ -n "${HOLDS_CONFIG:-}" ]; then printf '%s\n' "$HOLDS_CONFIG"; else printf '%s\n' '{"ok":true,"config":{"Agents":[]}}'; fi
  exit 0
fi
PATH="$HOLDS_PATH"; export PATH
exec "$HOLDS_NEXT_GC" "$@"
SHIM
    chmod +x "$dir/shim/gc" || exit 1
    mkdir -p "$dir/city/.gc" || exit 1
    printf '#!/bin/sh\nHOLDS_NEXT_GC=$(command -v gc) || HOLDS_NEXT_GC=/no-gc-on-path\nHOLDS_PATH="$PATH"\nexport HOLDS_NEXT_GC HOLDS_PATH\nPATH="%s:$PATH" HOLDS_STUB_READ=1 GC_CITY_PATH="%s" GC_CITY= GC_CITY_ROOT= exec %s "$@"\n' \
      "$dir/shim" "$dir/city" "$dir/gctk-real" > "$dir/gctk" && chmod +x "$dir/gctk" || exit 1
    printf '%s\n' "$dir/gctk"
    exit 0 ;;
  answer) shift ;;
  *) echo "usage: holds-store.stub.sh build <dir> | answer [--db <path>] <verb> [<args>...]" >&2; exit 2 ;;
esac

[ "${1:-}" = "--db" ] && shift 2
verb="${1:-}"; shift || true
case "${HOLDS_FAIL:-}" in
  all|"$verb") echo "gc bd: simulated $verb failure" >&2; exit 1 ;;
esac
store="${HOLDS_STORE:?holds-store.stub.sh answer: HOLDS_STORE names no store}"
deps="${HOLDS_DEPS:-/dev/null}"
[ -f "$deps" ] || deps=/dev/null

# Every row with its own edges as {type, id, external}, from each place a
# fixture can put them, and nothing else changed but the fields the stub owns.
# shellcheck disable=SC2016  # jq source; its $names are jq's
EDGES='
  def edge_of: {type: ((.dependency_type // .type // "") | tostring),
                id: ((.depends_on_id // .id // "") | tostring),
                external: (.external == true)};
  def rows($d):
    ($d | split("\n") | map(select(length > 0) | split("|")
       | if .[1] == "blocks" then {on: .[2], type: "blocks", id: .[0]}
         else {on: .[0], type: .[1], id: .[2]} end)) as $rows
    | map(. as $r
        | ([ ($r.dependencies // [])[]?, ($r._deps // [])[]? | objects | edge_of ]
           + (if ($r.parent // "") != "" then [{type: "parent-child", id: ($r.parent | tostring), external: false}] else [] end)
           + [ $rows[] | select(.on == $r.id) | {type, id, external: false} ]
           | unique_by([.type, .id])) as $e
        | del(.dependencies, ._deps, ._ready) | . + {_edges: $e}
        | if ((.status // "") == "closed") and ((.closed_at // "") == "") then .closed_at = "2026-01-01T00:00:00Z" else . end);
  def live: ((.status // "open") | tostring | ascii_downcase) as $s | $s != "closed" and $s != "pinned";
  def held_in($byid; $e): ($e.external | not) and ($byid[$e.id] != null);
  # The store blocked rule over every row, as {id: {own: [...], parent: p}} for
  # each blocked bead, reached by a fixpoint over the parent-child cascade.
  def blocked_map:
    (map({key: .id, value: .}) | from_entries) as $byid
    | (map(.) | map(select(live))) as $live
    | ([ $live[] | . as $b
         | {key: $b.id, value: {
             own: [ $b._edges[] | select(.type == "blocks" or .type == "conditional-blocks")
                    | select(held_in($byid; .)) | select($byid[.id] | live) | .id ],
             spawners: [ $b._edges[] | select(.type == "waits-for") | select(held_in($byid; .))
                         | .id as $s | select($byid[$s] | live) | $s ],
             gate: any($b._edges[] | select(.type == "waits-for") | select(held_in($byid; .)) | .id;
                       . as $s | any($live[]; any(._edges[]; .type == "parent-child" and .id == $s))),
             parent: (first($b._edges[] | select(.type == "parent-child") | select(held_in($byid; .)) | .id) // "") } } ]
       | from_entries) as $f
    | def step($m): reduce ($f | keys[]) as $id ($m;
        if .[$id] then . else
          ($f[$id]) as $x
          | if ($x.own | length) > 0 or $x.gate or ($x.parent != "" and (.[$x.parent] != null)) then
              .[$id] = {own: ($x.own + $x.spawners | unique), parent: $x.parent}
            else . end
        end);
      def fix($m; $n): (step($m)) as $next | if $n <= 0 or ($next == $m) then $m else fix($next; $n - 1) end;
      fix({}; 64);
'

case "$verb" in
  list)
    ids=""; key=""; field=""; parent=""; title=""; all=0
    while [ $# -gt 0 ]; do
      case "$1" in
        --title-contains) shift; title="${1:-}" ;;
        --title-contains=*) title="${1#--title-contains=}" ;;
        --id) shift; ids="${1:-}" ;;
        --id=*) ids="${1#--id=}" ;;
        --has-metadata-key) shift; key="${1:-}" ;;
        --has-metadata-key=*) key="${1#--has-metadata-key=}" ;;
        --metadata-field) shift; field="${1:-}" ;;
        --metadata-field=*) field="${1#--metadata-field=}" ;;
        --parent) shift; parent="${1:-}" ;;
        --parent=*) parent="${1#--parent=}" ;;
        --all) all=1 ;;
      esac
      shift || true
    done
    jq -c --rawfile d "$deps" --arg ids "$ids" --arg key "$key" --arg field "$field" --arg parent "$parent" --arg title "$title" --argjson all "$all" "$EDGES"'
      ($ids | if . == "" then [] else split(",") end) as $want
      | ($field | if . == "" then null else (index("=")) as $i | {k: .[:$i], v: .[$i + 1:]} end) as $f
      | rows($d)
      | [ .[]
          | select(($want | length) == 0 or (.id as $i | $want | index($i)))
          | select($key == "" or ((.metadata // {}) | has($key)))
          | select($f == null or ((((.metadata // {})[$f.k]) // "") | tostring) == $f.v)
          | select($parent == "" or any(._edges[]; .type == "parent-child" and .id == $parent))
          | select($title == "" or (((.title // "") | tostring) | contains($title)))
          | select($all == 1 or ((.status // "open") != "closed"))
          | .id as $self
          | .dependencies = [ ._edges[] | {issue_id: $self, depends_on_id: .id, type} ]
          | del(._edges) ]' "$store"
    ;;
  blocked)
    if [ -n "${HOLDS_BLOCKED:-}" ]; then printf '%s\n' "$HOLDS_BLOCKED"; exit 0; fi
    jq -c --rawfile d "$deps" "$EDGES"'
      rows($d) | blocked_map | to_entries
      | [ .[] | if (.value.own | length) > 0 then {id: .key, blocked_by: .value.own}
                elif .value.parent != "" then {id: .key, blocked_by: [.value.parent]}
                else empty end ]' "$store"
    ;;
  sql)
    if [ -n "${HOLDS_MARKS:-}" ]; then printf '%s\n' "$HOLDS_MARKS"; exit 0; fi
    jq -c --rawfile d "$deps" "$EDGES"'rows($d) | blocked_map | keys | map({id: .})' "$store"
    ;;
  where)
    jq -nc --arg p "${HOLDS_WHERE:-/stub/.beads}" '{path: $p, prefix: "stub", schema_version: 1}'
    ;;
  ready)
    if [ -n "${HOLDS_READY:-}" ]; then printf '%s\n' "$HOLDS_READY"; exit 0; fi
    key=""; unassigned=0; types="[]"; labels="[]"
    while [ $# -gt 0 ]; do
      case "$1" in
        --has-metadata-key) shift; key="${1:-}" ;;
        --has-metadata-key=*) key="${1#--has-metadata-key=}" ;;
        --unassigned) unassigned=1 ;;
        --exclude-type) shift; types=$(jq -c --arg t "${1:-}" '. + [$t]' <<< "$types") ;;
        --exclude-type=*) types=$(jq -c --arg t "${1#--exclude-type=}" '. + [$t]' <<< "$types") ;;
        --exclude-label) shift; labels=$(jq -c --arg l "${1:-}" '. + [$l]' <<< "$labels") ;;
        --exclude-label=*) labels=$(jq -c --arg l "${1#--exclude-label=}" '. + [$l]' <<< "$labels") ;;
      esac
      shift || true
    done
    jq -c --rawfile d "$deps" --arg key "$key" --argjson un "$unassigned" --argjson types "$types" --argjson labels "$labels" "$EDGES"'
      rows($d) | (blocked_map) as $held
      | [ .[]
          | select(((.status // "open") | ascii_downcase) == "open")
          | select($held[.id] == null)
          | select($key == "" or ((.metadata // {}) | has($key)))
          | select($un == 0 or (((.assignee // "") | tostring) == ""))
          | select(((.issue_type // "") | tostring) as $t | ($types | index($t)) == null)
          | select(all((.labels // [])[]?; . as $l | ($labels | index($l)) == null))
          | .id as $self
          | .dependencies = [ ._edges[] | {issue_id: $self, depends_on_id: .id, type} ]
          | del(._edges) ]' "$store"
    ;;
  update)
    id="${1:-}"; shift || true
    tmp="$store.update.$$"
    jq -e --arg id "$id" 'any(.[]; .id == $id)' "$store" >/dev/null 2>&1 || { echo "gc bd: no issue found matching $id" >&2; exit 1; }
    sets="[]"; unsets="[]"; notes=""; status=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --set-metadata) shift; sets=$(jq -c --arg kv "${1:-}" '. + [$kv]' <<< "$sets") ;;
        --unset-metadata) shift; unsets=$(jq -c --arg k "${1:-}" '. + [$k]' <<< "$unsets") ;;
        --append-notes) shift; notes="${1:-}" ;;
        --status) shift; status="${1:-}" ;;
      esac
      shift || true
    done
    jq -c --arg id "$id" --argjson sets "$sets" --argjson unsets "$unsets" --arg n "$notes" --arg st "$status" '
      map(if .id != $id then . else
            reduce $sets[] as $kv (.; ($kv | index("=")) as $i | .metadata[$kv[:$i]] = $kv[$i + 1:])
            | reduce $unsets[] as $k (.; .metadata |= ((. // {}) | del(.[$k])))
            | (if $n == "" then . else .notes = ((.notes // "") + (if (.notes // "") == "" then "" else "\n" end) + $n) end)
            | (if $st == "" then . else .status = $st end)
          end)' "$store" > "$tmp" || { rm -f "$tmp"; exit 1; }
    mv "$tmp" "$store" || exit 1
    echo "updated $id"
    ;;
  *) echo "holds-store.stub.sh: gctk reads no '$verb'" >&2; exit 2 ;;
esac
