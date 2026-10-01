#!/usr/bin/env bash
# gc-helm-subject-verify.test.sh — the four write verbs (open, engage, dismiss,
# accept) resolve their subject through ONE shared path, verify_subject, which
# tells a data-plane outage apart from a genuine not-found.
#
# The bug this guards: a `gc bd show` that did not ANSWER — an empty read, or an
# error OTHER than the not-found error — was reported by engage/dismiss/accept as
# "no bead with that id", so a Dolt outage read to the operator as a typo on a
# bead that existed. Only `open` classified it correctly. verify_subject is now
# that one code path, so the classification cannot drift between verbs:
#   - a non-answering probe  -> "could not verify … (data plane down?)", retryable
#   - a well-formed not-found -> "bead not found"
#
# Driven over a stubbed `gc` on PATH — no live city, Dolt, or sessions. The happy
# path of each verb is proven in its own suite (gc-helm-open/engage/accept.test.sh
# and gc-helm.test.sh); a failure-mode assertion here is self-validating — it
# names a message only verify_subject emits, so it FAILS if the verb never reached
# verify_subject (a precondition refusing first would carry different words).
set -u

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/gc-helm.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-gc-helm-subjverify.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }
has()    { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (got: $1)" ;; esac; }
hasnot() { case "$1" in *"$2"*) bad "$3 (got: $1)" ;; *) ok "$3" ;; esac; }

[ -f "$SCRIPT" ] && ok "gc-helm.sh present" || bad "gc-helm.sh missing at $SCRIPT"

mkdir -p "$TMP/bin"
# engage refuses a rig that carries no converse template before it reaches the
# subject check, so the fixture rig must carry one for engage to exercise
# verify_subject at all.
mkdir -p "$TMP/rig/agents/converse-opus" "$TMP/rig/agents/converse-codex"
export RIG_PATH="$TMP/rig"

# --- gc stub ------------------------------------------------------------------
# One rig (prefix tk, no suspended/running flags so engage never refuses on
# liveness). `bd show` answers from $FAKE_SHOW_MODE so each case picks the exact
# payload shape the real `bd show` emits for that reading. Every mutating call is
# appended to $FAKE_CALLS so "nothing was written/dispatched/spawned" is asserted
# against the actual argv, not exit status alone.
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
case "${1:-}" in
  "rig")
    [ "${2:-}" = "list" ] && jq -n --arg p "${RIG_PATH:-/nonexistent}" \
      '{rigs:[{name:"gc-toolkit", path:$p, prefix:"tk"}]}' ;;
  "bd")
    case "${2:-}" in
      show)
        # $3 is the id (the stub ignores --db; `gc bd show <id>` is unpinned).
        case "$FAKE_SHOW_MODE" in
          found)   jq -n --arg i "$3" '[{id:$i, title:"a real bead", status:"open", assignee:"", metadata:{task_kind:"task"}}]' ;;
          # The REAL not-found answer: a bare {"error":…} OBJECT, not an array, exit 1.
          missing) printf '{"error":"no issues found matching the provided IDs","schema_version":1}\n'; exit 1 ;;
          # Wedged data plane: nothing at all on stdout.
          down)    exit 1 ;;
          # Wedged data plane that DOES answer — same error channel as not-found,
          # a different error. Existence is unknown, not disproved.
          dberror) printf '{"error":"dial tcp 127.0.0.1:3307: connect: connection refused","schema_version":1}\n'; exit 1 ;;
        esac ;;
      list)    printf '[]\n' ;;
      create)  printf 'bd create %s\n' "$*" >> "$FAKE_CALLS"; jq -n '{id:"tk-visitX"}' ;;
      update)  printf 'bd update %s\n' "$*" >> "$FAKE_CALLS" ;;
      dep)     printf 'bd dep %s\n'    "$*" >> "$FAKE_CALLS" ;;
      comment) printf 'bd comment %s\n' "$*" >> "$FAKE_CALLS" ;;
    esac ;;
  "sling")   printf 'sling %s\n' "$*" >> "$FAKE_CALLS" ;;
  "session")
    [ "${2:-}" = "new" ] && { printf 'session new %s\n' "$*" >> "$FAKE_CALLS"; jq -n '{ok:true, session_id:"s1", session_name:"n1"}'; } ;;
esac
exit 0
GC
chmod +x "$TMP/bin/gc"

export PATH="$TMP/bin:$PATH"
export FAKE_CALLS="$TMP/calls"
unset GC_HELM_FIXTURE || true
export TMPDIR="$TMP"

# run_verb <show-mode> <verb> [args...] -> RC / ERR (stderr) / CALLS (mutations)
run_verb() {
    : > "$FAKE_CALLS"
    _mode="$1"; shift
    RC=0
    ERR="$(FAKE_SHOW_MODE="$_mode" sh "$SCRIPT" "$@" 2>&1 >/dev/null)" || RC=$?
    CALLS="$(cat "$FAKE_CALLS")"
}

# The subject fails to resolve three ways. For each verb, a non-answer (DOWN,
# DBERROR) must read as retryable "could not verify", never as a missing bead,
# and a well-formed not-found (MISSING, valid prefix) must read as "bead not
# found". Every refusal exits 4 and writes nothing. The verb's own "Nothing …"
# clause must thread through, proving the shared helper carries each caller's tail.
#
# Args: label, verb(+args as one field expanded), the "Nothing …" clause.
check_verb() {
    _label="$1"; _nothing="$2"; shift 2
    # $@ is now the verb invocation (e.g. `open tk-real1`).

    run_verb down "$@"
    eq "$RC" 4 "($_label DOWN) a wedged data plane exits 4 (fail closed)"
    has    "$ERR" "could not verify"   "($_label DOWN) says 'could not verify', not a typo"
    has    "$ERR" "data plane down"    "($_label DOWN) names the likely cause"
    hasnot "$ERR" "no bead with that id" "($_label DOWN) never claims the bead is missing"
    has    "$ERR" "$_nothing"          "($_label DOWN) carries this verb's '$_nothing'"
    eq "$CALLS" "" "($_label DOWN) nothing written/dispatched/spawned"

    run_verb dberror "$@"
    eq "$RC" 4 "($_label DBERROR) an error payload exits 4 (fail closed)"
    has    "$ERR" "could not verify"   "($_label DBERROR) reported as unverifiable, not a typo"
    has    "$ERR" "connection refused" "($_label DBERROR) surfaces the underlying error"
    hasnot "$ERR" "no bead with that id" "($_label DBERROR) a non-not-found error is not a missing bead"
    eq "$CALLS" "" "($_label DBERROR) nothing written/dispatched/spawned"

    run_verb missing "$@"
    eq "$RC" 4 "($_label MISSING) a well-formed not-found exits 4"
    has    "$ERR" "bead not found"      "($_label MISSING) says 'bead not found'"
    hasnot "$ERR" "could not verify"    "($_label MISSING) a real not-found is not reported as an outage"
    eq "$CALLS" "" "($_label MISSING) nothing written/dispatched/spawned"
}

check_verb OPEN    "No visit filed."   open    tk-real1
check_verb ENGAGE  "Nothing spawned."  engage  tk-real1 --no-attach --model codex
check_verb DISMISS "Nothing was written." dismiss tk-real1
check_verb ACCEPT  "Nothing dispatched." accept  tk-real1

# --- positive controls: the verb CAN pass verify_subject ----------------------
# A gate that refused everything would satisfy every assertion above while
# breaking the verb outright, so prove a resolvable subject gets through. (engage
# spawns on the happy path; that path is proven in gc-helm-engage.test.sh.)
run_verb found open tk-real1
eq "$RC" 0 "(OPEN found) a resolvable subject exits 0"
hasnot "$ERR" "could not verify" "(OPEN found) verify_subject passed"
has    "$CALLS" "bd create" "(OPEN found) the visit is filed — verify passed"

run_verb found dismiss tk-real1
eq "$RC" 0 "(DISMISS found) a resolvable subject exits 0 (no sitting to end)"
hasnot "$ERR" "could not verify" "(DISMISS found) verify_subject passed"
hasnot "$ERR" "bead not found"   "(DISMISS found) verify_subject passed"

run_verb found accept tk-real1
hasnot "$ERR" "could not verify" "(ACCEPT found) verify_subject passed"
hasnot "$ERR" "bead not found"   "(ACCEPT found) verify_subject passed"
eq "$CALLS" "" "(ACCEPT found) a discuss-only subject dispatches nothing"

echo ""
echo "subject-verify: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
