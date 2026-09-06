#!/usr/bin/env bash
# Hermetic test for the gc-helm `engage` verb (tk-4abhrt).
#
# engage is the spawn-on-engagement entry point that replaces the retired
# converse routed-pool: it spawns a manual converse-<model> sitting, binds the
# picked visit to that session's runtime NAME (so the session's own
# `gc hook --claim` adopts it with no pool routing), and attaches.
#
# Runs the REAL gc-helm.sh (invoked via `sh`, as shipped) with a stubbed `gc` on
# PATH — no live city, Dolt, network, or sessions. Covered:
#   (MODEL)   an unknown --model is refused before anything spawns (exit 2)
#   (NOARG)   a missing bead-id is refused (exit 2)
#   (VISIT)   engaging an OPEN visit spawns converse-opus --alias <visit>
#             --no-attach and binds the visit to the session's runtime name
#   (SUBJECT) engaging a subject resolves the one open visit tracking it
#   (MODELFLAG) --model codex spawns converse-codex
#   (BUSY)    a visit already in_progress under an owner is not re-spawned (exit 4)
#   (NOSPAWN) a session new that returns no identity aborts without assigning
#   (ATTACH)  the default attaches to the captured session id; --no-attach does not
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/gc-helm.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-gc-helm-engage-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 (unexpected '$2')" ;; *) ok "$3" ;; esac; }

[ -f "$SCRIPT" ] && ok "gc-helm.sh present" || bad "gc-helm.sh missing at $SCRIPT"

mkdir -p "$TMP/bin"

# --- gc stub ------------------------------------------------------------------
# One rig (prefix tk). The subject bead is tk-subj (task_kind from $BEAD_KIND);
# the visit is tk-vis. `session new` prints a fixed identity and records its
# argv; `bd update --assignee` records the assignee to $ASSIGNEE so the read-back
# `bd show tk-vis` reflects it, the way the real store would. $VIS_STATUS drives
# the busy guard. Every session/mutating call is appended to $CALLS.
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
SNAME="gc-toolkit__converse-1"
SID="gc-77"
case "$1 ${2:-}" in
  "rig list")
    jq -n '{rigs:[{name:"gc-toolkit", path:"/nonexistent-rig", prefix:"tk"}]}' ;;
  "bd show")
    id="$3"
    if [ "$id" = "tk-vis" ]; then
      st="$(cat "$VIS_STATUS" 2>/dev/null || echo open)"
      who="$(cat "$ASSIGNEE" 2>/dev/null)"; [ -n "$who" ] || who="$VIS_OWNER"
      jq -n --arg i "$id" --arg s "$st" --arg a "$who" \
        '[{id:$i, status:$s, assignee:$a, metadata:{task_kind:"visit","gc.continuation_group":"tk-subj"}}]'
    else
      jq -n --arg i "$id" --arg k "${BEAD_KIND:-task}" \
        '[{id:$i, status:"open", assignee:"", metadata:{task_kind:$k}}]'
    fi ;;
  "bd list")
    # The one open visit tracking tk-subj, when $HAVE_VISIT is set.
    if [ -n "${HAVE_VISIT:-}" ]; then
      jq -n '[{id:"tk-vis", status:"open", assignee:"", metadata:{task_kind:"visit","gc.continuation_group":"tk-subj"}}]'
    else printf '[]\n'; fi ;;
  "session new")
    printf 'session new %s\n' "$*" >> "$CALLS"
    if [ -n "${SPAWN_EMPTY:-}" ]; then jq -n '{ok:true}'; else
      jq -n --arg id "$SID" --arg n "$SNAME" '{schema_version:"1", ok:true, session_id:$id, session_name:$n, alias:"tk-vis", template:"t", transport:"tmux", work_dir:"/w", deferred_start:true, attached:false}'
    fi ;;
  "session attach")
    printf 'session attach %s\n' "$*" >> "$CALLS" ;;
  "bd update")
    printf 'bd update %s\n' "$*" >> "$CALLS"
    _a="$*"; case "$_a" in *" --assignee "*) _a="${_a##* --assignee }"; printf '%s' "${_a%% *}" > "$ASSIGNEE" ;; esac ;;
  "bd create")
    printf 'bd create %s\n' "$*" >> "$CALLS"; jq -n '{id:"tk-vis"}' ;;
  "bd dep")   printf 'bd dep %s\n' "$*" >> "$CALLS" ;;
esac
exit 0
GC
chmod +x "$TMP/bin/gc"

export PATH="$TMP/bin:$PATH"
export CALLS="$TMP/calls" ASSIGNEE="$TMP/assignee" VIS_STATUS="$TMP/vstatus"
unset GC_HELM_FIXTURE || true
export TMPDIR="$TMP"

# run_engage <bead> [extra-args...] -> RC/OUT, with per-case env preset by caller
run_engage() {
    : > "$CALLS"; : > "$ASSIGNEE"
    set +e
    OUT="$(sh "$SCRIPT" engage "$@" 2>"$TMP/err")"; RC=$?
    set -e
    OUT="$OUT$(cat "$TMP/err")"
    CALLED="$(cat "$CALLS")"
}

echo "# argument validation refuses before anything spawns"
BEAD_KIND=visit run_engage tk-vis --model bogus
eq "$RC" 2 "(MODEL) an unknown --model exits 2"
hasnt "$CALLED" "session new" "(MODEL) …and nothing was spawned"

run_engage ""
eq "$RC" 2 "(NOARG) a missing bead-id exits 2"

echo "# engaging an OPEN visit spawns a sitting and binds the visit to it"
export BEAD_KIND=visit VIS_OWNER="" HAVE_VISIT=""
printf 'open' > "$VIS_STATUS"
run_engage tk-vis --no-attach
eq "$RC" 0 "(VISIT) engaging an open visit exits 0"
has "$CALLED" "session new converse-opus --alias tk-vis --no-attach --json" "(VISIT) spawns converse-opus --alias <visit> --no-attach"
eq "$(cat "$ASSIGNEE")" "gc-toolkit__converse-1" "(BIND) the visit is assigned to the session's runtime name"
has "$CALLED" "bd update tk-vis --assignee gc-toolkit__converse-1" "(BIND) …by name, the identity the claim adopts"

echo "# --model selects the tier"
run_engage tk-vis --model codex --no-attach
has "$CALLED" "session new converse-codex --alias tk-vis" "(MODELFLAG) --model codex spawns converse-codex"

echo "# engaging a SUBJECT resolves the one open visit tracking it"
export BEAD_KIND=task HAVE_VISIT=1
printf 'open' > "$VIS_STATUS"
run_engage tk-subj --no-attach
eq "$RC" 0 "(SUBJECT) engaging a subject with an open visit exits 0"
has "$CALLED" "session new converse-opus --alias tk-vis --no-attach --json" "(SUBJECT) spawns for the tracking visit"
unset HAVE_VISIT

echo "# a visit already engaged is not re-spawned"
export BEAD_KIND=visit VIS_OWNER="gc-toolkit__converse-9"
printf 'in_progress' > "$VIS_STATUS"
run_engage tk-vis --no-attach
eq "$RC" 4 "(BUSY) an in_progress visit under an owner exits 4"
hasnt "$CALLED" "session new" "(BUSY) …and spawns no duplicate sitting"
has "$OUT" "already engaged" "(BUSY) …and points at the running session"
export VIS_OWNER=""
printf 'open' > "$VIS_STATUS"

echo "# a spawn that yields no identity aborts without assigning"
export SPAWN_EMPTY=1
run_engage tk-vis --no-attach
eq "$RC" 4 "(NOSPAWN) a session with no identity exits 4"
eq "$(cat "$ASSIGNEE")" "" "(NOSPAWN) …and the visit is not assigned"
unset SPAWN_EMPTY

echo "# attach behaviour: default attaches, --no-attach does not"
run_engage tk-vis --no-attach
hasnt "$CALLED" "session attach" "(ATTACH) --no-attach does not attach"
run_engage tk-vis
has "$CALLED" "session attach gc-77" "(ATTACH) the default attaches to the captured session id"

echo
echo "gc-helm engage: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
