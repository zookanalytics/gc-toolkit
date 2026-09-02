#!/usr/bin/env bash
# Wiring test across assets/scripts/signoff.sh and
# doctor/check-gate-marker-provenance: what one writes, the other must be able
# to resolve. Both run against ONE stubbed bead store, so the join is the real
# thing and not two fixtures asserted to agree.
#
# The doctor check clears a green marker two ways: a task_kind=review bead
# carrying anchor_bead + reviewed_oid + check_name, or an APPROVED GitHub review
# at the same commit. signoff.sh never approves, so the GitHub reviews served
# here are empty and the bead is the only resolver left. That makes the check a
# direct test of the record signoff writes.
#
# The fixture is the shape that leaves a marker unbacked: a post-open anchor
# whose review bead carries no dispatch pin, so the verdict binds to the live
# head and the bead is the only place that head can be recorded.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/signoff.sh"
CHECK="$HERE/../../doctor/check-gate-marker-provenance/run.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }

BIN="$TMP/bin"; mkdir -p "$BIN"
RIG="$TMP/alpha"; mkdir -p "$RIG"
REAL_GIT=$(command -v git)
"$REAL_GIT" init -q "$RIG"
"$REAL_GIT" -C "$RIG" remote add origin https://github.com/acme/alpha.git
printf '{"rigs":[{"name":"alpha","path":"%s"}]}\n' "$RIG" > "$TMP/rigs.json"

# One store, two readers. The bd surface is only as wide as these two scripts
# use, and each flag is honoured the way bd honours it: --status open hides the
# closed rows, --all shows them, --has-metadata-key selects on key PRESENCE, and
# a --db naming a store that is not this one answers nothing at all.
cat > "$BIN/gc" <<GC
#!/usr/bin/env bash
set -u
STORE="\${STUB_STORE:?}"
printf '%s\n' "\$*" >> "\${STUB_GC_LOG:?}"
case "\${1:-} \${2:-}" in
  "rig list") cat "$TMP/rigs.json"; exit 0 ;;
esac
[ "\${1:-}" = "bd" ] || exit 0
shift
case "\${1:-}" in
  show)
    out=\$(jq -c --arg id "\$2" '[.[] | select(.id == \$id)]' "\$STORE")
    if [ "\$(printf '%s' "\$out" | jq 'length')" = "0" ]; then echo '{"error":"no issues found"}'
    else printf '%s\n' "\$out"; fi ;;
  update)
    shift; id="\$1"; shift
    tmp=\$(mktemp); cp "\$STORE" "\$tmp"
    while [ \$# -gt 0 ]; do
      case "\$1" in
        --set-metadata) shift; k="\${1%%=*}"; v="\${1#*=}"
          jq -c --arg id "\$id" --arg k "\$k" --arg v "\$v" \\
            'map(if .id == \$id then .metadata[\$k] = \$v else . end)' "\$tmp" > "\$tmp.n" && mv "\$tmp.n" "\$tmp" ;;
        --unset-metadata) shift
          jq -c --arg id "\$id" --arg k "\$1" \\
            'map(if .id == \$id then (.metadata |= del(.[\$k])) else . end)' "\$tmp" > "\$tmp.n" && mv "\$tmp.n" "\$tmp" ;;
        --append-notes) shift
          jq -c --arg id "\$id" --arg n "\$1" \\
            'map(if .id == \$id then .notes = ((.notes // "") + "\n" + \$n) else . end)' "\$tmp" > "\$tmp.n" && mv "\$tmp.n" "\$tmp" ;;
        --status=*) st="\${1#--status=}"
          jq -c --arg id "\$id" --arg s "\$st" \\
            'map(if .id == \$id then .status = \$s else . end)' "\$tmp" > "\$tmp.n" && mv "\$tmp.n" "\$tmp" ;;
      esac
      shift || true
    done
    mv "\$tmp" "\$STORE"; echo "updated \$id" ;;
  list)
    shift
    db=""; key=""; status=""; all=0; limit=""
    while [ \$# -gt 0 ]; do
      case "\$1" in
        --db) shift; db="\${1:-}" ;;
        --has-metadata-key) shift; key="\${1:-}" ;;
        --status) shift; status="\${1:-}" ;;
        --status=*) status="\${1#--status=}" ;;
        --limit) shift; limit="\${1:-}" ;;
        --all) all=1 ;;
      esac
      shift || true
    done
    if [ -n "\$db" ] && [ "\$db" != "$RIG/.beads" ]; then
      echo "bd: no store at \$db (stub)" >&2; exit 3
    fi
    out=\$(cat "\$STORE")
    [ -z "\$key" ] || out=\$(printf '%s' "\$out" | jq -c --arg k "\$key" '[.[] | select((.metadata // {}) | has(\$k))]')
    if [ "\$all" -eq 0 ] && [ -n "\$status" ]; then
      out=\$(printf '%s' "\$out" | jq -c --arg s "\$status" '[.[] | select((.status // "open") == \$s)]')
    fi
    if [ -n "\$limit" ] && [ "\$limit" != "0" ]; then
      out=\$(printf '%s' "\$out" | jq -c --argjson n "\$limit" '.[0:\$n]')
    fi
    printf '%s\n' "\$out" ;;
  dep) printf '[]\n' ;;
esac
GC

# signoff posts its artifact and probes the head; the doctor asks the same repo
# for its APPROVED reviews. Serving none is the point: resolver B must not be
# what clears these markers.
cat > "$BIN/gh" <<'GH'
#!/usr/bin/env bash
set -u
printf '%s\n' "$*" >> "${STUB_GH_LOG:?}"
case "${1:-}" in
  pr)
    case "$*" in
      *headRefOid*)       printf '%s\n' "${STUB_PR_HEAD:-}" ;;
      *autoMergeRequest*) printf '{"autoMergeRequest":null}\n' ;;
    esac ;;
  api)
    case "$*" in
      *" user "*) printf 'city-bot\n' ;;
      # signoff extracts rows with --jq '.[]' and gets nothing from an empty
      # list; the doctor slurps the raw pages, so it gets the empty array.
      *"/reviews?"*) case "$*" in *--jq*) : ;; *) printf '[]\n' ;; esac ;;
    esac ;;
esac
exit 0
GH

# ls-remote is the only call that would reach the network. Everything else, the
# doctor's `git -C <rig> remote get-url origin` included, runs against the real
# throwaway repo so the origin parse is tested and not simulated.
cat > "$BIN/git" <<GIT
#!/usr/bin/env bash
if [ "\${1:-}" = "ls-remote" ]; then
  [ -n "\${STUB_LSREMOTE:-}" ] && printf '%s\trefs/heads/%s\n' "\$STUB_LSREMOTE" "\${3#refs/heads/}"
  exit 0
fi
exec "$REAL_GIT" "\$@"
GIT
chmod +x "$BIN/gc" "$BIN/gh" "$BIN/git"
export PATH="$BIN:$PATH"
export STUB_STORE="$TMP/store.json" STUB_GC_LOG="$TMP/gc.log" STUB_GH_LOG="$TMP/gh.log"
unset GC_RIG GC_MAX_REVIEW_ROUNDS 2>/dev/null || true

HEAD_OID=$(printf 'head' | sha1sum | cut -d' ' -f1)
export STUB_LSREMOTE="$HEAD_OID" STUB_PR_HEAD="$HEAD_OID"

# A post-open anchor mid-gate, and the review bead a dispatch that could not
# resolve the head left unpinned.
seed() {
  cat > "$STUB_STORE" <<STORE
[{"id":"tk-anc","status":"open","assignee":"","notes":"",
  "metadata":{"merge_result":"pull_request","check_set":"codex","branch":"polecat/tk-anc",
              "target":"main","pr_number":"42","pr_url":"https://github.com/acme/alpha/pull/42"}},
 {"id":"rv-1","status":"in_progress","assignee":"pool/x","notes":"findings",
  "metadata":{"task_kind":"review","check_name":"codex","anchor_bead":"tk-anc"}}]
STORE
  : > "$STUB_GC_LOG"; : > "$STUB_GH_LOG"
}
meta() { jq -r --arg id "$1" --arg k "$2" '(.[] | select(.id == $id) | .metadata[$k]) // "<absent>"' "$STUB_STORE"; }

echo "# signoff's own output satisfies the provenance check"
seed
"$SUT" --review-bead rv-1 --verdict approve >/dev/null 2>&1; rc=$?
eq "$rc" 0 "the post-open approve records a verdict"
eq "$(meta tk-anc check.codex)" "green@$HEAD_OID" "…stamping the marker merge-skill.sh reads"
eq "$(meta rv-1 reviewed_oid)" "$HEAD_OID" "…and recording the same commit on the review bead"
OUT=$(bash "$CHECK" 2>&1); RC=$?
eq "$RC" 0 "the provenance check passes on the store signoff just wrote"
has "$OUT" "OK:" "…with the OK line, not a gap or a finding"

echo "# the check is what makes that pass mean something"
# Strip the one field signoff writes back, leaving the store the pre-fix script
# produced. A check that cleared this marker anyway would clear anything.
jq -c 'map(if .id == "rv-1" then (.metadata |= del(.reviewed_oid)) else . end)' \
  "$STUB_STORE" > "$STUB_STORE.n" && mv "$STUB_STORE.n" "$STUB_STORE"
OUT=$(bash "$CHECK" 2>&1); RC=$?
eq "$RC" 2 "the same marker without that record is an error"
has "$OUT" "commit nothing reviewed it for" "…named as a gate standing on no verdict"
has "$OUT" "tk-anc" "…on the anchor that carries it"

echo "# no GitHub approval is ever what clears it"
if grep -q -- '--approve' "$STUB_GH_LOG"; then
  bad "the suite posted an approval"
else
  ok "nothing in this suite approves a PR; only the bead record clears the marker"
fi

echo
echo "signoff-gate-provenance.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
