#!/usr/bin/env bash
# Hermetic test for converse-auto-open.sh — the live-intake auto-open action.
# Runs the REAL script with `gc` (via CONVERSE_AUTO_OPEN_GC) and `gc-helm.sh`
# (via GC_HELM_TOOL) stubbed — no live city, Dolt, sessions, or network.
#
# What each case guards:
#   (NOLIVE)    no gc.interactive_intake on the subject => NO engage. This is the
#               whole point: gc.origin=operator rides stale subjects a scan
#               re-reacts, and auto-engaging on it is the retired-pool runaway.
#   (CONSUME)   the marker is consumed (one shot) the moment it is read, before
#               any branch, so a replayed reaction finds nothing to arm.
#   (ENGAGE)    armed + parked visit + under cap => gc-helm engage <visit>
#               --no-attach, and gc.auto_opened/_at stamped AFTER the spawn.
#   (RESOLVE)   --visit omitted resolves the subject's single parked visit.
#   (AMBIG)     two parked visits => decline, engage nothing (operator names one).
#   (CAP)       at/over CONVERSE_AUTO_OPEN_CAP => park, do not engage; slot saved.
#   (REFUSED)   engage declining (blocked/raced) leaves NO auto_opened stamp —
#               a phantom auto-open would be counted against the cap forever.
#   (DRY)       --dry-run engages nothing and writes nothing.
#   (USAGE)     --subject is required.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/converse-auto-open.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-converse-auto-open-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
has() { grep -qF -- "$2" <<< "$1" && ok "$3" || bad "$3 (in: $1)"; }
hasnt() { grep -qF -- "$2" <<< "$1" && bad "$3 (in: $1)" || ok "$3"; }

[ -f "$SUT" ] && ok "converse-auto-open.sh present" || { bad "missing at $SUT"; exit 1; }

mkdir -p "$TMP/bin" "$TMP/fix"
CALLS="$TMP/calls"

# ── stub gc ──────────────────────────────────────────────────────────────────
# bd show <id>        -> $TMP/fix/show-<id>.json (else a not-found object, exit 1)
# bd update <id> ...  -> record; exit ${FAKE_UPDATE_RC:-0}
# bd list ...         -> the cap query (carries gc.auto_opened) or the parked
#                        visit query, each from its own fixture file.
cat > "$TMP/bin/gc" <<EOF
#!/usr/bin/env bash
echo "gc \$*" >> "$CALLS"
case "\$1 \${2:-}" in
  "bd show")
    f="$TMP/fix/show-\${3}.json"
    if [ -f "\$f" ]; then cat "\$f"; exit 0; fi
    echo '{"error":"no issues found"}'; exit 1 ;;
  "bd update")
    exit \${FAKE_UPDATE_RC:-0} ;;
  "bd list")
    for a in "\$@"; do case "\$a" in *gc.auto_opened*) cat "$TMP/fix/standing.json" 2>/dev/null || echo '[]'; exit 0;; esac; done
    cat "$TMP/fix/parked.json" 2>/dev/null || echo '[]'; exit 0 ;;
esac
exit 0
EOF
chmod +x "$TMP/bin/gc"

# ── stub gc-helm.sh: record engage, succeed unless FAKE_ENGAGE_RC set ─────────
cat > "$TMP/bin/gc-helm.sh" <<EOF
#!/usr/bin/env bash
echo "helm \$*" >> "$CALLS"
case "\$1" in engage) exit \${FAKE_ENGAGE_RC:-0} ;; esac
exit 0
EOF
chmod +x "$TMP/bin/gc-helm.sh"

export CONVERSE_AUTO_OPEN_GC="$TMP/bin/gc"
export GC_HELM_TOOL="$TMP/bin/gc-helm.sh"

# subject_fixture <id> <interactive_intake-value|"">  — writes show-<id>.json
subject_fixture() {
  local meta=""
  [ -n "$2" ] && meta="\"gc.interactive_intake\":\"$2\""
  printf '[{"id":"%s","status":"open","metadata":{%s}}]\n' "$1" "$meta" > "$TMP/fix/show-$1.json"
}
reset() { : > "$CALLS"; rm -f "$TMP/fix/"*.json; printf '[]' > "$TMP/fix/parked.json"; printf '[]' > "$TMP/fix/standing.json"; unset FAKE_ENGAGE_RC FAKE_UPDATE_RC; }
run() { OUT="$("$SUT" "$@" 2>&1)"; RC=$?; }

# ── (NOLIVE) no marker => no engage ───────────────────────────────────────────
reset; subject_fixture tk-subj ""
run --subject tk-subj --visit tk-visit
hasnt "$(cat "$CALLS")" "helm engage" "(NOLIVE) no engage without the live marker"
has "$OUT" "no live" "(NOLIVE) says why it declined"
[ "$RC" = "0" ] && ok "(NOLIVE) exits 0 (visit stays parked)" || bad "(NOLIVE) rc=$RC"

# ── (CONSUME) marker is consumed before branching ─────────────────────────────
reset; subject_fixture tk-subj 1
run --subject tk-subj --visit tk-visit
has "$(cat "$CALLS")" "bd update tk-subj --unset-metadata gc.interactive_intake" "(CONSUME) the live marker is consumed one-shot"

# ── (ENGAGE) armed + under cap => engage --no-attach, stamp after ─────────────
reset; subject_fixture tk-subj 1
run --subject tk-subj --visit tk-visit
has "$(cat "$CALLS")" "helm engage tk-visit --no-attach" "(ENGAGE) engages the visit --no-attach"
has "$(cat "$CALLS")" "bd update tk-visit --set-metadata gc.auto_opened=1" "(ENGAGE) stamps gc.auto_opened on the visit"
has "$(cat "$CALLS")" "gc.auto_opened_at=" "(ENGAGE) stamps the age clock gc.auto_opened_at"
[ "$RC" = "0" ] && ok "(ENGAGE) exits 0" || bad "(ENGAGE) rc=$RC"

# ── (RESOLVE) --visit omitted resolves the single parked visit ────────────────
reset; subject_fixture tk-subj 1
printf '[{"id":"tk-visit","status":"open","assignee":"","metadata":{"task_kind":"visit","gc.continuation_group":"tk-subj"}}]\n' > "$TMP/fix/parked.json"
run --subject tk-subj
has "$(cat "$CALLS")" "helm engage tk-visit --no-attach" "(RESOLVE) resolves and engages the subject's parked visit"

# ── (AMBIG) two parked visits => decline ──────────────────────────────────────
reset; subject_fixture tk-subj 1
printf '[{"id":"tk-v1","status":"open","assignee":"","metadata":{"task_kind":"visit","gc.continuation_group":"tk-subj"}},{"id":"tk-v2","status":"open","assignee":"","metadata":{"task_kind":"visit","gc.continuation_group":"tk-subj"}}]\n' > "$TMP/fix/parked.json"
run --subject tk-subj
hasnt "$(cat "$CALLS")" "helm engage" "(AMBIG) engages nothing when the visit is ambiguous"
has "$OUT" "parked visits" "(AMBIG) names the ambiguity"

# ── (CAP) at cap => park, no engage ───────────────────────────────────────────
reset; subject_fixture tk-subj 1
printf '[{"id":"tk-a","metadata":{"gc.auto_opened":"1"}},{"id":"tk-b","metadata":{"gc.auto_opened":"1"}}]\n' > "$TMP/fix/standing.json"
CONVERSE_AUTO_OPEN_CAP=2 run --subject tk-subj --visit tk-visit
hasnt "$(cat "$CALLS")" "helm engage" "(CAP) does not engage past the cap"
has "$OUT" "cap" "(CAP) says it hit the cap"

# an already-attended standing visit does NOT count toward the cap
reset; subject_fixture tk-subj 1
printf '[{"id":"tk-a","metadata":{"gc.auto_opened":"1","gc.auto_open_attended_at":"2026-09-11T00:00:00Z"}},{"id":"tk-b","metadata":{"gc.auto_opened":"1"}}]\n' > "$TMP/fix/standing.json"
CONVERSE_AUTO_OPEN_CAP=2 run --subject tk-subj --visit tk-visit
has "$(cat "$CALLS")" "helm engage tk-visit --no-attach" "(CAP) attended sittings do not count against the cap"

# ── (REFUSED) engage declines => no auto_opened stamp ─────────────────────────
reset; subject_fixture tk-subj 1
FAKE_ENGAGE_RC=4 run --subject tk-subj --visit tk-visit
has "$(cat "$CALLS")" "helm engage tk-visit --no-attach" "(REFUSED) it attempts the engage"
hasnt "$(cat "$CALLS")" "bd update tk-visit --set-metadata gc.auto_opened=1" "(REFUSED) no phantom auto_opened stamp on a failed engage"
[ "$RC" = "0" ] && ok "(REFUSED) exits 0 (visit stays parked)" || bad "(REFUSED) rc=$RC"

# ── (DRY) --dry-run changes nothing ───────────────────────────────────────────
reset; subject_fixture tk-subj 1
run --dry-run --subject tk-subj --visit tk-visit
hasnt "$(cat "$CALLS")" "helm engage" "(DRY) engages nothing"
hasnt "$(cat "$CALLS")" "bd update" "(DRY) writes nothing (no consume, no stamp)"
has "$OUT" "would auto-open" "(DRY) reports the plan"

# ── (USAGE) --subject required ────────────────────────────────────────────────
reset
run --visit tk-visit
[ "$RC" = "2" ] && ok "(USAGE) missing --subject is a usage error" || bad "(USAGE) rc=$RC"

echo "converse-auto-open: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
