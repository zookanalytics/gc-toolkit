#!/usr/bin/env bash
# Hermetic test for assets/scripts/rejection-repool.sh — the refinery's
# rejection, handed back to the polecat pool as a mol-polecat-work pour.
# Covers: the usage refusals; the release (one lifecycle transition that clears
# the assignee, the claim route and the last pour's execution stamp, and records
# rejection_reason and existing_pr) landing before the pour; the row read before
# the write, on stdout; the pool route proved and rig-qualified before any pour
# or arm, whether --pool names the pool or the default does; the pour proved by
# its own stamp and never by the one the last pour left; a failed sling armed
# for a retry, an exit-0 pour that does not read back never armed, and neither
# routed bare; and a visit on every other way the repool stops short. The real
# lifecycle.sh (through a gctk built from this tree), pool-route.sh and
# deferred-dispatch.sh run against the harness store, and escalate.sh is a stub
# that records its argv.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-rejection-repool-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"
# The release is a lifecycle transition, and lifecycle.sh execs gctk.
harness_build_gctk
harness_init

ESC_STUB='#!/usr/bin/env bash
printf "%s\n" "$*" >> "${STUB_ESC_LOG:?}"
exit "${STUB_ESC_RC:-0}"'
SD="$TMP/scripts"
mk_sut_dir "$SD" "$HERE/rejection-repool.sh" "$HERE/lifecycle.sh" "$HERE/pool-route.sh" \
  "$HERE/deferred-dispatch.sh"
printf '%s\n' "$ESC_STUB" > "$SD/escalate.sh"; chmod +x "$SD/escalate.sh"
# The same SUT beside a deferred-dispatch.sh whose arm does not land.
SD_NOARM="$TMP/scripts-noarm"
mk_sut_dir "$SD_NOARM" "$HERE/rejection-repool.sh" "$HERE/lifecycle.sh" "$HERE/pool-route.sh"
printf '%s\n' "$ESC_STUB" > "$SD_NOARM/escalate.sh"; chmod +x "$SD_NOARM/escalate.sh"
printf '#!/usr/bin/env bash\necho "deferred-dispatch: arm refused (stub)" >&2\nexit 1\n' > "$SD_NOARM/deferred-dispatch.sh"
chmod +x "$SD_NOARM/deferred-dispatch.sh"
# A gc whose sling exits 0 and stamps nothing, the shape of a pour whose own
# execution stamp did not land. Every other call reaches the harness stub.
NOSTAMP="$TMP/bin-nostamp"; mkdir -p "$NOSTAMP"
printf '#!/usr/bin/env bash\n[ "${1:-}" = sling ] && { printf "%%s\\n" "$*" >> "${STUB_GC_LOG:?}"; exit 0; }\nexec "%s/gc" "$@"\n' "$BIN" > "$NOSTAMP/gc"
chmod +x "$NOSTAMP/gc"
# A gc whose sling pours and stamps as the harness does, and whose every read
# after it fails: a pour that launched while the store stopped answering.
READFAIL="$TMP/bin-readfail"; mkdir -p "$READFAIL"
printf '#!/usr/bin/env bash\nif [ "${1:-}" = sling ]; then "%s/gc" "$@"; rc=$?; : > "%s/slung"; exit $rc; fi\n[ "${1:-} ${2:-}" = "bd show" ] && [ -e "%s/slung" ] && exit 1\nexec "%s/gc" "$@"\n' "$BIN" "$TMP" "$TMP" "$BIN" > "$READFAIL/gc"
chmod +x "$READFAIL/gc"

export STUB_ESC_LOG="$TMP/esc.log"
export GC_RIG="gc-toolkit"
ROUTE="gc-toolkit/gc-toolkit.polecat"
REASON="Conflicts with main at abc123; resume in prepare_mode=merge"

# The bead as the rejection arms leave it for this script: reopen-source has
# reopened it with no assignee, and it still carries the stamp of the pour that
# built it.
work() { # [extra-metadata-fields]
  printf '{"id":"tk-w","status":"open","assignee":"","notes":"","title":"w","metadata":{"branch":"polecat/tk-w","target":"main","gc.routed_to":"","gc.execution_routed_to":"%s"%s}}' \
    "$ROUTE" "${1:-}"
}
reset() { # [extra-metadata-fields]
  store "[$(work "${1:-}")]"
  : > "$STUB_GC_LOG"; : > "$STUB_ESC_LOG"; rm -f "$TMP/slung"
  export STUB_SLING_FAIL="" STUB_UPDATE_FAIL="" STUB_SHOW_FAIL="" STUB_AGENTS="" STUB_ESC_RC=""
}
# $out is stderr and stdout together; $TMP/stdout holds stdout alone.
_run() { "$@" > "$TMP/stdout" 2> "$TMP/stderr"; rc=$?; out=$(cat "$TMP/stderr" "$TMP/stdout"); }
run()  { _run "$SD/rejection-repool.sh" "$@"; }
run_noarm() { _run "$SD_NOARM/rejection-repool.sh" "$@"; }
stdout_meta() { jq -r --arg k "$1" '(.[0].metadata[$k] // "<absent>") | tostring' "$TMP/stdout" 2>/dev/null; }
slings() { grep -c '^sling ' "$STUB_GC_LOG" || true; }
visits() { wc -l < "$STUB_ESC_LOG" | tr -d ' '; }
no_bare_route() { # <label>
  case "$(meta tk-w gc.routed_to)" in
    ""|"<absent>") ok "$1" ;;
    *) bad "$1 (gc.routed_to='$(meta tk-w gc.routed_to)')" ;;
  esac
}

echo "# usage refusals do nothing"
reset
run --reason "$REASON";        eq "$rc" 1 "no work bead -> exit 1"
run tk-w;                      eq "$rc" 1 "no --reason -> exit 1"
run tk-w --reason "$REASON" --bogus; eq "$rc" 1 "an unknown flag -> exit 1"
run tk-w tk-x --reason "$REASON"; eq "$rc" 1 "two work beads -> exit 1"
eq "$(wc -l < "$STUB_GC_LOG" | tr -d ' ')" "0" "a usage refusal runs no gc"

echo "# the rejection is released, then poured"
reset
run tk-w --reason "$REASON"
eq "$rc" 0 "a proved pour exits 0"
eq "$(meta tk-w rejection_reason)" "$REASON" "rejection_reason recorded"
eq "$(meta tk-w merge_result)" "<absent>" "merge_result absent: unanchored"
eq "$(bassignee tk-w)" "" "no assignee"
eq "$(meta tk-w gc.execution_routed_to)" "$ROUTE" "the pour stamped the pool it dispatched to"
no_bare_route "no claim route on the bead: the pour is the only dispatch"
eq "$(slings)" "1" "one pour"
has "$(cat "$STUB_GC_LOG")" "sling --rig gc-toolkit $ROUTE tk-w --on mol-polecat-work" "poured mol-polecat-work for the proved route"
release=$(grep '^bd update tk-w' "$STUB_GC_LOG" | head -n 1)
has "$release" "--unset-metadata merge_result" "the release unanchors the bead"
has "$release" "--unset-metadata gc.execution_routed_to" "the release clears the last pour's stamp"
has "$release" "gc.routed_to=" "the release clears the claim route"
has "$release" "--assignee=" "the release clears the assignee"
first_update=$(grep -n '^bd update tk-w' "$STUB_GC_LOG" | head -n 1 | cut -d: -f1)
first_sling=$(grep -n '^sling ' "$STUB_GC_LOG" | head -n 1 | cut -d: -f1)
if [ -n "$first_update" ] && [ -n "$first_sling" ] && [ "$first_update" -lt "$first_sling" ]; then
  ok "the release lands before the pour"
else
  bad "the release lands before the pour (update line '$first_update', sling line '$first_sling')"
fi
eq "$(meta tk-w gc.dispatch_when_ready)" "<absent>" "a proved pour arms nothing"
eq "$(visits)" "0" "a proved pour files no visit"
eq "$(wc -l < "$TMP/stdout" | tr -d ' ')" "1" "stdout is one line"
eq "$(jq -r '.[0].id' "$TMP/stdout" 2>/dev/null)" "tk-w" "stdout is the bead's row"
eq "$(stdout_meta rejection_reason)" "<absent>" "the row is the read before the release: no rejection_reason yet"
eq "$(stdout_meta branch)" "polecat/tk-w" "the row carries the bead's metadata"

echo "# a live PR goes with the rework"
reset ',"pr_url":"https://github.com/o/r/pull/7"'
run tk-w --reason "$REASON"
eq "$rc" 0 "a bead with a PR pours"
eq "$(meta tk-w existing_pr)" "https://github.com/o/r/pull/7" "pr_url carried over as existing_pr"

# A graduation's anchor is a convoy that tracks the members it landed.
# POUR models the input convoy Gas City's graph.v2 pour
# gives a run (NormalizeInputConvoy, internal/graphv2/invocation.go at
# gastownhall/gascity 6e35bd5ea): a convoy target is its own input convoy, and
# any other target gets a one-bead convoy, marked gc.synthetic, that tracks it.
# Its sling records the run's input convoy in $TMP/input-convoy and then reaches
# the harness stub, and `convoy status <id> --json` answers the beads a convoy
# tracks as its children. mol-polecat-work takes the one bead its input convoy
# tracks as its work bead, and the derivation is read from the formula itself.
# Each pour also mints its run's workflow root, open until a case ends the run
# (end_runs): gc.input_convoy_id names the input convoy and gc.formula_name the
# formula, as Gas City stamps a graph.v2 root.
# Its `sling --dry-run` is gc sling's preview of that pour, logged to
# $TMP/previews and never poured. It answers the way the preview does
# (dryRunReportBlockingMolecule and dryRunReportBlockingWorkflow in gc's sling
# command, gastownhall/gascity 149ae8df7c95): an open workflow root of the
# formula over a gc.synthetic convoy that tracks the bead exits 1 naming that
# workflow on stderr, and no such root exits 0 with the passing pre-check line.
# STUB_PREVIEW names the other answers: inconclusive (a failed lookup, exit 0
# with no passing line), molecule (an attached molecule, exit 1) and unrelated
# (a usage, route or store failure, exit 1).
POUR="$TMP/bin-pour"; mkdir -p "$POUR"
cat > "$POUR/gc" <<EOF
#!/usr/bin/env bash
if [ "\${1:-}" = sling ]; then
  case " \$* " in
    *" --dry-run "*)
      printf '%s\n' "\$*" >> "$TMP/previews"
      target=""; bead=""; skip=""; formula=""
      for a in "\${@:2}"; do
        if [ -n "\$skip" ]; then [ "\$skip" = --on ] && formula="\$a"; skip=""; continue; fi
        case "\$a" in
          --rig|--on) skip="\$a" ;;
          --*) : ;;
          *) if [ -z "\$target" ]; then target="\$a"; elif [ -z "\$bead" ]; then bead="\$a"; fi ;;
        esac
      done
      case "\${STUB_PREVIEW:-}" in
        molecule)  echo "gc sling: bead \$bead already has attached molecule mol-\$bead" >&2; exit 1 ;;
        unrelated) echo "gc sling: simulated store failure" >&2; exit 1 ;;
      esac
      printf 'Dry run: gc sling %s %s --on=%s\n\n' "\$target" "\$bead" "\$formula"
      if [ "\${STUB_PREVIEW:-}" = inconclusive ]; then
        echo "gc sling: pre-check inconclusive: listing tracking convoys for \$bead: simulated store error" >&2
        exit 0
      fi
      cvs=\$(awk -F'|' -v b="\$bead" '\$2 == "tracks" && \$3 == b { print \$1 }' "\$STUB_DEPS" | jq -Rsc 'split("\n") | map(select(. != ""))')
      root=\$(jq -r --argjson c "\$cvs" --arg f "\$formula" '
        [ .[] | select(.issue_type == "convoy" and (((.metadata // {})["gc.synthetic"] // "") | tostring) == "true") | .id ] as \$syn
        | [ .[] | (.metadata // {}) as \$m | (\$m["gc.input_convoy_id"] // "") as \$i
            | select(.status != "closed" and (\$m["gc.kind"] // "") == "workflow" and (\$m["gc.formula_name"] // "") == \$f
                     and any(\$c[]; . == \$i) and any(\$syn[]; . == \$i))
            | .id ]
        | sort | .[0] // empty' "\$STUB_STORE")
      if [ -n "\$root" ]; then
        echo "gc sling: bead \$bead already has attached workflow \$root" >&2
        exit 1
      fi
      printf 'Attach formula:\n  Formula: %s\n  Pre-check: %s has no existing molecule/wisp children or live formulas-v2 workflow for %s ✓\n\n' "\$formula" "\$bead" "\$formula"
      exit 0 ;;
  esac
fi
if [ "\${1:-}" = sling ] && [ -z "\${STUB_SLING_FAIL:-}" ]; then
  target=""; bead=""; skip=""; formula=""
  for a in "\${@:2}"; do
    if [ -n "\$skip" ]; then [ "\$skip" = --on ] && formula="\$a"; skip=""; continue; fi
    case "\$a" in
      --rig|--on) skip="\$a" ;;
      --*) : ;;
      *) if [ -z "\$target" ]; then target="\$a"; elif [ -z "\$bead" ]; then bead="\$a"; fi ;;
    esac
  done
  n=\$(( \$(cat "$TMP/pours" 2>/dev/null || echo 0) + 1 )); printf '%s\n' "\$n" > "$TMP/pours"
  if [ "\$(jq -r --arg id "\$bead" '[.[] | select(.id == \$id)][0].issue_type // ""' "\$STUB_STORE")" = convoy ]; then
    input="\$bead"
  else
    input="icv-\$bead-\$n"
    jq -c --arg id "\$input" --arg t "input convoy for \$bead" \
      '. + [{id: \$id, status: "open", assignee: "", title: \$t, issue_type: "convoy", metadata: {"gc.synthetic": "true"}}]' \
      "\$STUB_STORE" > "\$STUB_STORE.pour" && mv "\$STUB_STORE.pour" "\$STUB_STORE"
    printf '%s|tracks|%s\n' "\$input" "\$bead" >> "\$STUB_DEPS"
  fi
  jq -c --arg id "wf-\$n" --arg c "\$input" --arg f "\$formula" \
    '. + [{id: \$id, status: "open", assignee: "", title: \$f, issue_type: "task", metadata: {"gc.input_convoy_id": \$c, "gc.formula_name": \$f, "gc.kind": "workflow"}}]' \
    "\$STUB_STORE" > "\$STUB_STORE.pour" && mv "\$STUB_STORE.pour" "\$STUB_STORE"
  printf '%s\n' "\$input" > "$TMP/input-convoy"
fi
if [ "\${1:-} \${2:-}" = "convoy status" ]; then
  awk -F'|' -v c="\${3:-}" '\$1 == c && \$2 == "tracks" { print \$3 }' "\$STUB_DEPS" \
    | jq -Rnc '{children: [inputs | select(. != "") | {id: .}]}'
  exit 0
fi
exec "$BIN/gc" "\$@"
EOF
chmod +x "$POUR/gc"
DERIVE=$(grep -m 1 -o "jq -r 'if (.children | length) == 1 then [^']*'" "$HERE/../../formulas/mol-polecat-work.toml" | sed "s/^jq -r '//; s/'\$//")
has "$DERIVE" ".children[0].id" "mol-polecat-work's work-bead derivation was read from the formula"
work_bead_of() { PATH="$POUR:$PATH" gc convoy status "$1" --json 2>/dev/null | jq -r "$DERIVE" 2>/dev/null; }
run_pour() { PATH="$POUR:$PATH" _run "$SD/rejection-repool.sh" "$@"; }
grad() { # [extra-convoy-metadata-fields]
  local m
  store "[{\"id\":\"tk-g\",\"status\":\"open\",\"assignee\":\"\",\"notes\":\"\",\"title\":\"g\",\"issue_type\":\"convoy\",\"priority\":1,\"metadata\":{\"branch\":\"integration/tk-g\",\"target\":\"main\",\"graduation\":true,\"merge_strategy\":\"mr\",\"gc.routed_to\":\"\"${1:-}}},
          {\"id\":\"tk-m1\",\"status\":\"closed\",\"title\":\"m1\",\"metadata\":{}},
          {\"id\":\"tk-m2\",\"status\":\"closed\",\"title\":\"m2\",\"metadata\":{}},
          {\"id\":\"tk-m3\",\"status\":\"closed\",\"title\":\"m3\",\"metadata\":{}}]"
  : > "$STUB_DEPS"
  for m in tk-m1 tk-m2 tk-m3; do printf 'tk-g|tracks|%s\n' "$m" >> "$STUB_DEPS"; done
  : > "$STUB_GC_LOG"; : > "$STUB_ESC_LOG"; rm -f "$TMP/input-convoy" "$TMP/previews"
  export STUB_SLING_FAIL="" STUB_UPDATE_FAIL="" STUB_SHOW_FAIL="" STUB_AGENTS="" STUB_ESC_RC=""
}
kids_of() { jq -r --arg a "$1" '[.[] | select((.metadata.anchor_bead // "") == $a) | .id] | join(" ")' "$STUB_STORE"; }
# works_on <want> <label> — the run poured last works on <want>, a bead the
# case named: an empty <want> fails, so no case passes on two empty answers.
works_on() {
  local icv got
  icv=$(cat "$TMP/input-convoy" 2>/dev/null); got=$(work_bead_of "$icv")
  if [ -n "$1" ] && [ "$got" = "$1" ]; then ok "$2"
  else bad "$2 (input convoy '${icv:-none}' works on '${got:-no one bead}', want '${1:-a rebuild child}')"; fi
}
slung() { awk '$1 == "sling" { print $(NF - 2) }' "$STUB_GC_LOG" | paste -sd' ' -; }
# end_runs <bead> [gc.outcome] — every run poured onto <bead> ends: the roots
# over the input convoys that track it close, with the outcome when one is given.
end_runs() {
  local cvs
  cvs=$(awk -F'|' -v b="$1" '$2 == "tracks" && $3 == b { print $1 }' "$STUB_DEPS" | jq -Rsc 'split("\n") | map(select(. != ""))')
  store "$(jq -c --argjson c "$cvs" --arg o "${2:-}" '
    map(if ((((.metadata // {})["gc.input_convoy_id"] // "") | tostring) as $i | any($c[]; . == $i))
        then .status = "closed" | (if $o == "" then . else .metadata["gc.outcome"] = $o end)
        else . end)' "$STUB_STORE")"
}
# live_run_on <bead> — a run of mol-polecat-work live on <bead>, poured before
# this case began: its input convoy tracks the bead, and its root is open.
live_run_on() {
  store "$(jq -c --arg b "$1" '. + [
    {id: ("icv-" + $b + "-0"), status: "open", assignee: "", title: ("input convoy for " + $b), issue_type: "convoy", metadata: {"gc.synthetic": "true"}},
    {id: ("wf-" + $b + "-0"), status: "open", assignee: "", title: "mol-polecat-work", issue_type: "task",
     metadata: {"gc.input_convoy_id": ("icv-" + $b + "-0"), "gc.formula_name": "mol-polecat-work", "gc.kind": "workflow"}}]' "$STUB_STORE")"
  printf 'icv-%s-0|tracks|%s\n' "$1" "$1" >> "$STUB_DEPS"
}

echo "# a graduation's anchor is never poured: its rebuild is poured onto a child that resumes its branch"
grad
eq "$(work_bead_of tk-g)" "" "poured as it stands, the convoy's run would find no one work bead"
run_pour tk-g --reason "$REASON"
eq "$rc" 0 "the repool of a graduation is proved"
CHILD=$(kids_of tk-g)
if [ -n "$CHILD" ] && [ "$CHILD" != "${CHILD#* }" ]; then bad "one rebuild child is filed (got '$CHILD')"
elif [ -n "$CHILD" ]; then ok "one rebuild child is filed"
else bad "one rebuild child is filed (none)"; fi
eq "$(slings)" "1" "one pour"
eq "$(slung)" "$CHILD" "the pour is onto the rebuild child, never the convoy"
has "$(grep '^sling ' "$STUB_GC_LOG")" "sling --rig gc-toolkit $ROUTE $CHILD --on mol-polecat-work" "the pour is gc sling's own, to the proved route"
works_on "$CHILD" "the run the repool pours works on the rebuild child"
eq "$(jq -r --arg id "$CHILD" '.[] | select(.id == $id) | [.issue_type, .metadata.task_kind, .metadata.anchor_bead, .metadata.branch, .metadata.target, .metadata.merge_strategy] | map(tostring) | join(" | ")' "$STUB_STORE")" \
  "task | rework | tk-g | integration/tk-g | main | mr" "the child is an ordinary task that resumes the convoy's branch and lands on its target"
eq "$(meta "$CHILD" rejection_reason)" "$REASON" "the child carries the rejection the rebuild starts from"
eq "$(meta "$CHILD" priority_shift)" "-1" "the child is born carrying the PR-finishing shift"
eq "$(jq -r --arg id "$CHILD" '[.[] | select(.id == $id)][0].parent // "<absent>"' "$STUB_STORE")" "<absent>" "the child is born with no parent"
grep -qx "$CHILD|blocks|tk-g" "$STUB_DEPS" && ok "the child blocks the convoy" || bad "the child blocks the convoy (deps: $(tr '\n' ' ' < "$STUB_DEPS"))"
eq "$(jq -r --arg id "$CHILD" '[.[] | select(.id == $id)][0].priority' "$STUB_STORE")" "0" "the child is settled at its priority: the convoy's P1 plus its shift"
eq "$(bpoured "$CHILD")" "0" "the pour copies the settled priority"
eq "$(meta "$CHILD" gc.execution_routed_to)" "$ROUTE" "the child carries the stamp the pour left, the proof the repool reads"
eq "$(meta tk-g gc.execution_routed_to)" "<absent>" "the convoy carries no pour stamp"
eq "$(meta tk-g rejection_reason)" "<absent>" "the convoy records no rejection of its own: the child carries it"
eq "$(bassignee tk-g)" "" "the convoy is released: no assignee"
eq "$(meta tk-g merge_result)" "<absent>" "the convoy is unanchored until the child's work lands"
eq "$(meta "$CHILD" gc.dispatch_when_ready)" "<absent>" "a proved pour arms nothing"
eq "$(visits)" "0" "a proved pour files no visit"
eq "$(jq -r '.[0].id' "$TMP/stdout" 2>/dev/null)" "tk-g" "stdout is the convoy's row as read before the release"

echo "# a convoy with a live PR hands it to its rebuild child"
grad ',"pr_url":"https://github.com/o/r/pull/8"'
run_pour tk-g --reason "$REASON"
eq "$rc" 0 "the repool is proved"
eq "$(meta "$(kids_of tk-g)" existing_pr)" "https://github.com/o/r/pull/8" "the child carries the convoy's PR as existing_pr"
eq "$(meta tk-g existing_pr)" "<absent>" "the convoy keeps only its own pr_url"

echo "# a convoy whose row names its kind as type, not issue_type, is never poured"
# The pack's other convoy checks read .issue_type // .type (gate-ensure.sh,
# duplicate-sweep.sh), and so does this one.
grad
store "$(jq -c 'map(if .id == "tk-g" then (del(.issue_type) | .type = "convoy") else . end)' "$STUB_STORE")"
run_pour tk-g --reason "$REASON"
eq "$rc" 0 "the repool is proved"
CHILD=$(kids_of tk-g)
[ -n "$CHILD" ] && ok "a rebuild child is filed" || bad "a rebuild child is filed (none)"
eq "$(slung)" "$CHILD" "the pour is onto the rebuild child, never the convoy"

echo "# the rebuild child is settled within the merge cadence's lock wait"
# The refinery patrol runs this script, so its settle waits for the priority
# lock no longer than bd-lib's bound for the cadence's scripts.
QP_LOG="$TMP/queue-priority.log"
cat > "$TMP/queue-priority-wrap" <<EOF
#!/usr/bin/env bash
printf '%s %s\n' "\${QUEUE_PRIORITY_LOCK_WAIT_SECS:-<unset>}" "\$*" >> "$QP_LOG"
exec "$GC_QUEUE_PRIORITY_TOOL" "\$@"
EOF
chmod +x "$TMP/queue-priority-wrap"
CADENCE_WAIT=$(sed -n 's/^PR_FINISHING_LOCK_WAIT_SECS=//p' "$HERE/bd-lib.sh")
grad; : > "$QP_LOG"
GC_QUEUE_PRIORITY_TOOL="$TMP/queue-priority-wrap" run_pour tk-g --reason "$REASON"
eq "$rc" 0 "the repool is proved"
eq "$(cat "$QP_LOG")" "${CADENCE_WAIT:-<no bound in bd-lib.sh>} settle $(kids_of tk-g)" \
  "the one settle waits no longer than PR_FINISHING_LOCK_WAIT_SECS"

echo "# the arm a failed sling leaves is on the rebuild child, and its replay works on it"
grad
export STUB_SLING_FAIL=1
run_pour tk-g --reason "$REASON"
eq "$rc" 2 "a failed sling exits 2: an armed dispatch carries it"
CHILD=$(kids_of tk-g)
ARMED=$(jq -r '[.[] | select((.metadata["gc.dispatch_when_ready"] // "") != "") | .id] | join(" ")' "$STUB_STORE")
eq "$ARMED" "$CHILD" "the deferred dispatch is armed on the rebuild child, never the convoy"
eq "$(meta "$CHILD" gc.dispatch_when_ready)" "$ROUTE" "the arm targets the proved route"
eq "$(meta "$CHILD" gc.dispatch_when_ready_args)" '["--on","mol-polecat-work"]' "the arm replays the pour"
eq "$(visits)" "0" "an armed retry files no visit"
# The reconcile pass replays an arm as one gc sling of the armed bead, with the
# target and the args the arm recorded (sling_bead in deferred-dispatch.sh).
export STUB_SLING_FAIL=""
read -r -a REPLAY <<< "$(jq -r '.[] | select((.metadata["gc.dispatch_when_ready"] // "") != "")
  | [.metadata["gc.dispatch_when_ready"], .id] + (.metadata["gc.dispatch_when_ready_args"] | fromjson) | join(" ")' "$STUB_STORE")"
rm -f "$TMP/input-convoy"
PATH="$POUR:$PATH" gc sling --rig "$GC_RIG" "${REPLAY[@]}" >/dev/null 2>&1
works_on "$CHILD" "the run the replayed arm pours works on the rebuild child"

echo "# a repool that finds the convoy's rebuild child adopts it"
REASON2="Conflicts with main at def456; resume in prepare_mode=merge"
grad
run_pour tk-g --reason "$REASON"
CHILD=$(kids_of tk-g)
[ -n "$CHILD" ] && ok "the first repool filed the rebuild child" || bad "the first repool filed the rebuild child (none)"
ROOT=$(jq -r --arg c "$(cat "$TMP/input-convoy" 2>/dev/null)" '[.[] | select(((.metadata // {})["gc.input_convoy_id"] // "") == $c) | .id][0] // empty' "$STUB_STORE")
: > "$STUB_GC_LOG"; rm -f "$TMP/previews"
run_pour tk-g --reason "$REASON2"
eq "$rc" 0 "a child a live run works on stands as the rebuild"
eq "$(kids_of tk-g)" "$CHILD" "no second child is filed"
eq "$(slings)" "0" "and nothing is poured again"
eq "$(grep -c "^bd update $CHILD" "$STUB_GC_LOG" || true)" "0" "the live run's child is never released"
eq "$(meta "$CHILD" rejection_reason)" "$REASON" "the live run's work order is left as it is"
eq "$(cat "$TMP/previews" 2>/dev/null)" "sling --rig gc-toolkit $ROUTE $CHILD --on mol-polecat-work --dry-run" \
  "whether a run is live is gc sling's own preview of the pour, to the proved route and never forced"
has "$out" "workflow ${ROOT:-<no root>} is live on its rebuild child $CHILD" "the run names the workflow gc sling's preview found live"
grad
export STUB_SLING_FAIL=1
run_pour tk-g --reason "$REASON"
CHILD=$(kids_of tk-g)
export STUB_SLING_FAIL=""; : > "$STUB_GC_LOG"
run_pour tk-g --reason "$REASON"
eq "$rc" 2 "a child that is armed is left to its arm: exit 2"
eq "$(slings)" "0" "the repool pours nothing beside the arm"
has "$out" "armed for $ROUTE" "the run names the arm that pours it"
grad
store "$(jq -c '. + [{"id":"tk-c0","status":"open","assignee":"","title":"rebuild","issue_type":"task","priority":1,"metadata":{"task_kind":"rework","anchor_bead":"tk-g","branch":"integration/tk-g","priority_shift":-1}}]' "$STUB_STORE")"
run_pour tk-g --reason "$REASON"
eq "$rc" 0 "a child filed and never dispatched is poured"
eq "$(kids_of tk-g)" "tk-c0" "no second child is filed"
eq "$(slung)" "tk-c0" "the pour is onto the adopted child"
eq "$(meta tk-c0 rejection_reason)" "$REASON" "the adopted child's work order is completed before the pour"
eq "$(meta tk-c0 target)" "main" "including the target it lands on"

echo "# a rebuild child whose run is over is released and poured with the new rejection"
# merge-push anchors the convoy when the child's work lands, then closes the
# child. A close that is refused leaves the child open, still carrying its
# run's stamp and the refinery as its assignee, and the convoy can be rejected
# again before the next pass retries the close.
grad
run_pour tk-g --reason "$REASON"
CHILD=$(kids_of tk-g)
end_runs "$CHILD"
store "$(jq -c --arg id "$CHILD" 'map(if .id == $id then .assignee = "gc-toolkit/gc-toolkit.refinery" else . end)' "$STUB_STORE")"
: > "$STUB_GC_LOG"
run_pour tk-g --reason "$REASON2"
eq "$rc" 0 "the repool is proved"
eq "$(kids_of tk-g)" "$CHILD" "no second child is filed"
eq "$(slings)" "1" "the child is poured again"
eq "$(slung)" "$CHILD" "the pour is onto the same child"
eq "$(meta "$CHILD" rejection_reason)" "$REASON2" "the child carries the new rejection"
eq "$(bassignee "$CHILD")" "" "the refinery's assignment is released, so load-context does not read the child as handed off"
works_on "$CHILD" "the run the repool pours works on the child"
release=$(grep "^bd update $CHILD" "$STUB_GC_LOG" | head -n 1)
has "$release" "--unset-metadata gc.execution_routed_to" "the release clears the last run's stamp, so only this pour can prove itself"
has "$release" "--assignee=" "the release clears the assignee"
first_update=$(grep -n "^bd update $CHILD" "$STUB_GC_LOG" | head -n 1 | cut -d: -f1)
first_sling=$(grep -n '^sling ' "$STUB_GC_LOG" | head -n 1 | cut -d: -f1)
if [ -n "$first_update" ] && [ -n "$first_sling" ] && [ "$first_update" -lt "$first_sling" ]; then
  ok "the release lands before the pour"
else
  bad "the release lands before the pour (update line '$first_update', sling line '$first_sling')"
fi
grad
run_pour tk-g --reason "$REASON"
CHILD=$(kids_of tk-g)
end_runs "$CHILD" canceled
: > "$STUB_GC_LOG"
run_pour tk-g --reason "$REASON2"
eq "$rc" 0 "a child whose run was cancelled is poured again"
eq "$(slung)" "$CHILD" "onto the same child"
eq "$(meta "$CHILD" rejection_reason)" "$REASON2" "carrying the new rejection"

echo "# a preview that proves neither a live workflow nor none pours nothing"
# The child's run is over, so only the preview's answer stands between the
# repool and a pour. An inconclusive lookup exits 0 and an unrelated failure
# exits 1, so a parse of the exit code alone pours the first and reports the
# second live.
for answer in "inconclusive|exit 0: gc sling: pre-check inconclusive:" \
              "molecule|exit 1: gc sling: bead @ already has attached molecule mol-@" \
              "unrelated|exit 1: gc sling: simulated store failure"; do
  kind="${answer%%|*}"
  grad
  run_pour tk-g --reason "$REASON"
  CHILD=$(kids_of tk-g)
  end_runs "$CHILD"
  : > "$STUB_GC_LOG"; : > "$STUB_ESC_LOG"
  STUB_PREVIEW="$kind" run_pour tk-g --reason "$REASON2"
  eq "$rc" 2 "a preview answering $kind -> visit, exit 2"
  eq "$(slings)" "0" "nothing is poured ($kind)"
  eq "$(grep -c "^bd update $CHILD" "$STUB_GC_LOG" || true)" "0" "the child is not released ($kind)"
  eq "$(meta "$CHILD" rejection_reason)" "$REASON" "nothing is written to the child ($kind)"
  eq "$(meta "$CHILD" gc.dispatch_when_ready)" "<absent>" "nothing is armed ($kind)"
  has "$(cat "$STUB_ESC_LOG")" "a live rebuild cannot be told from a finished one" "the visit names the unanswered preview ($kind)"
  said="${answer#*|}"
  has "$(cat "$STUB_ESC_LOG")" "${said//@/$CHILD}" "the visit carries gc's exit and its own words ($kind)"
  has "$(cat "$STUB_ESC_LOG")" "gc sling $ROUTE $CHILD --on mol-polecat-work --dry-run" "the visit names the preview that finishes it ($kind)"
done

echo "# whether the found child is armed or live is never read from a show of the child"
# A gc whose show of $STUB_SHOW_FAIL_ID fails while every listing answers. The
# arm is read from the listing that found the child, and a live run from gc
# sling's preview.
SHOWFAIL="$TMP/bin-showfail"; mkdir -p "$SHOWFAIL"
printf '#!/usr/bin/env bash\n[ "${1:-} ${2:-} ${3:-}" = "bd show ${STUB_SHOW_FAIL_ID:-}" ] && exit 1\nexec "%s/gc" "$@"\n' "$POUR" > "$SHOWFAIL/gc"
chmod +x "$SHOWFAIL/gc"
run_showfail() { STUB_SHOW_FAIL_ID=tk-c1 PATH="$SHOWFAIL:$POUR:$PATH" _run "$SD/rejection-repool.sh" "$@"; }
grad
store "$(jq -c --arg r "$ROUTE" '. + [{"id":"tk-c1","status":"open","assignee":"","title":"rebuild","issue_type":"task","priority":1,"metadata":{"task_kind":"rework","anchor_bead":"tk-g","branch":"integration/tk-g","target":"main","priority_shift":-1,"gc.execution_routed_to":$r}}]' "$STUB_STORE")"
live_run_on tk-c1
run_showfail tk-g --reason "$REASON"
eq "$rc" 0 "a child a live run works on stands as the rebuild when its own read fails"
eq "$(slings)" "0" "nothing is poured again"
eq "$(meta tk-c1 rejection_reason)" "<absent>" "its work order is not rewritten"
eq "$(visits)" "0" "no visit is filed"
grad
store "$(jq -c --arg r "$ROUTE" '. + [{"id":"tk-c1","status":"open","assignee":"","title":"rebuild","issue_type":"task","priority":1,"metadata":{"task_kind":"rework","anchor_bead":"tk-g","branch":"integration/tk-g","target":"main","priority_shift":-1,"gc.dispatch_when_ready":$r}}]' "$STUB_STORE")"
run_showfail tk-g --reason "$REASON"
eq "$rc" 2 "an armed child whose own read fails is still left to its arm: exit 2"
eq "$(slings)" "0" "the repool pours nothing beside the arm"
eq "$(visits)" "0" "the arm carries it, so no visit is filed"

echo "# a convoy's review or ruling rework is not its rebuild child"
grad
store "$(jq -c '. + [{"id":"tk-rv","status":"open","assignee":"","title":"review rework","issue_type":"task","priority":1,"metadata":{"task_kind":"rework","anchor_bead":"tk-g","branch":"integration/tk-g","source_review_bead":"tk-review"}}]' "$STUB_STORE")"
run_pour tk-g --reason "$REASON"
eq "$rc" 0 "the repool is proved"
CHILD=$(kids_of tk-g | tr ' ' '\n' | grep -vx tk-rv)
eq "$(slung)" "$CHILD" "a fresh rebuild child is poured, not the review's rework"
eq "$(meta tk-rv gc.execution_routed_to)" "<absent>" "the review's rework is left alone"

echo "# a convoy that names no target files nothing"
store '[{"id":"tk-g","status":"open","assignee":"","notes":"","title":"g","issue_type":"convoy","priority":1,"metadata":{"branch":"integration/tk-g","graduation":true,"merge_strategy":"mr"}}]'
: > "$STUB_DEPS"; : > "$STUB_GC_LOG"; : > "$STUB_ESC_LOG"
run_pour tk-g --reason "$REASON"
eq "$rc" 2 "a visit carries it: exit 2"
eq "$(kids_of tk-g)" "" "no rebuild child is filed"
eq "$(slings)" "0" "nothing is poured"
has "$(cat "$STUB_ESC_LOG")" "names no branch or no target" "the visit names what is missing"

echo "# the stamp the last pour left proves nothing, and an exit-0 pour is not poured again"
# The bead starts with gc.execution_routed_to naming this very pool. A pour that
# exits 0 without stamping it must not read back as proved off that stale value.
# It launched, and deferred-dispatch's reconcile keys its retry on its own
# marker, never on that stamp, so an arm would pour the work a second time.
reset
PATH="$NOSTAMP:$PATH" run tk-w --reason "$REASON"
eq "$rc" 2 "a pour that leaves no stamp of its own exits 2"
eq "$(slings)" "1" "it was poured once"
eq "$(meta tk-w gc.execution_routed_to)" "<absent>" "the stale stamp was cleared before the pour"
eq "$(meta tk-w gc.dispatch_when_ready)" "<absent>" "an exit-0 pour is never armed for a retry"
no_bare_route "an unproved pour is never routed bare"
eq "$(visits)" "1" "a visit carries it instead"
has "$(cat "$STUB_ESC_LOG")" "after gc sling exited 0" "the visit says the sling succeeded"
has "$(cat "$STUB_ESC_LOG")" "check that no mol-polecat-work workflow is live on it" "the visit asks for the live-workflow check before any re-pour"

echo "# a read that fails after an exit-0 pour is not poured again"
reset
PATH="$READFAIL:$PATH" run tk-w --reason "$REASON"
eq "$rc" 2 "an unreadable stamp after an exit-0 pour exits 2"
eq "$(slings)" "1" "it was poured once"
eq "$(meta tk-w gc.dispatch_when_ready)" "<absent>" "nothing is armed to pour it again"
eq "$(visits)" "1" "a visit carries it"
has "$(cat "$STUB_ESC_LOG")" "check that no mol-polecat-work workflow is live on it" "the visit asks for the live-workflow check"

echo "# a failed sling is armed for a retry"
reset
export STUB_SLING_FAIL=1
run tk-w --reason "$REASON"
eq "$rc" 2 "a failed sling exits 2"
eq "$(meta tk-w rejection_reason)" "$REASON" "the release stands"
eq "$(meta tk-w gc.dispatch_when_ready)" "$ROUTE" "the retry is armed to the proved route"
eq "$(meta tk-w gc.dispatch_when_ready_args)" '["--on","mol-polecat-work"]' "the arm replays the pour"
no_bare_route "a failed sling is never routed bare"
has "$out" "armed a deferred dispatch" "the run says the arm carries it"
eq "$(visits)" "0" "an armed retry files no visit"
eq "$(wc -l < "$TMP/stdout" | tr -d ' ')" "1" "stdout is still the one row: the arm's own output goes to stderr"

echo "# an arm that does not land files the visit"
reset
export STUB_SLING_FAIL=1
run_noarm tk-w --reason "$REASON"
eq "$rc" 2 "a visit carries the bead: exit 2"
eq "$(visits)" "1" "one visit"
esc=$(cat "$STUB_ESC_LOG")
has "$esc" "--subject tk-w --key rejection-repool-failed" "filed on the bead under its situation key"
has "$esc" "gc sling $ROUTE tk-w --on mol-polecat-work" "the visit names the pour that finishes it"
has "$esc" "rejection reason: $REASON)" "the visit carries the reason"
has "$esc" "--message A rejected handoff may never be rebuilt:" "the visit leads with the stake"
no_bare_route "no bare route behind the visit either"

echo "# nothing recorded: exit 3"
reset
export STUB_SLING_FAIL=1 STUB_ESC_RC=1
run_noarm tk-w --reason "$REASON"
eq "$rc" 3 "no arm and no visit -> exit 3"
has "$out" "NOTHING dispatches tk-w" "the run says nothing carries the bead"

echo "# the pool route is proved before any pour"
# A readable roster without the polecat identity, run once on the default pool
# and once with --pool named the way the patrol's rejection arms name it.
printf '%s\n' '{"agents":[{"qualified_name":"gc-toolkit/gc-toolkit.refinery"}]}' > "$TMP/no-polecat.json"
for pool_args in "" "--pool gc-toolkit.polecat"; do
  reset
  export STUB_AGENTS="$TMP/no-polecat.json"
  # shellcheck disable=SC2086 # $pool_args is the flag and its value, or nothing
  run tk-w --reason "$REASON" $pool_args
  how="${pool_args:-the default pool}"
  eq "$rc" 2 "an unclaimed pool ($how) -> visit, exit 2"
  eq "$(slings)" "0" "nothing is poured to a pool nobody claims ($how)"
  eq "$(meta tk-w rejection_reason)" "$REASON" "the reason is recorded for whoever finishes it ($how)"
  has "$(cat "$STUB_ESC_LOG")" "no live pool claims 'gc-toolkit.polecat'" "the visit names the missing pool ($how)"
  eq "$(meta tk-w gc.dispatch_when_ready)" "<absent>" "nothing is armed to an unproved route ($how)"
  no_bare_route "no route is stamped in its place ($how)"
done

echo "# a readable roster that carries the pool proves the route"
reset
printf '%s\n' "{\"agents\":[{\"qualified_name\":\"$ROUTE\"}]}" > "$TMP/agents.json"
export STUB_AGENTS="$TMP/agents.json"
run tk-w --reason "$REASON" --pool gc-toolkit.polecat
eq "$rc" 0 "a proved route pours"
has "$(cat "$STUB_GC_LOG")" "sling --rig gc-toolkit $ROUTE tk-w --on mol-polecat-work" "poured to the rig-qualified identity the roster lists"
case "$out" in *UNVERIFIED*) bad "the route was verified, not passed through unverified" ;; *) ok "the route was verified, not passed through unverified" ;; esac

echo "# --pool names the pool"
reset
run tk-w --reason "$REASON" --pool gc-toolkit.polecat
eq "$rc" 0 "a bare --pool qualified by GC_RIG pours"
has "$(cat "$STUB_GC_LOG")" "sling --rig gc-toolkit $ROUTE tk-w --on mol-polecat-work" "poured to <GC_RIG>/<pool>"
reset
GC_RIG="" run tk-w --reason "$REASON" --pool "$ROUTE"
eq "$rc" 0 "a rig-qualified --pool pours with GC_RIG unset"
has "$(cat "$STUB_GC_LOG")" "sling $ROUTE tk-w --on mol-polecat-work" "poured to the route --pool named"

echo "# a bare route is refused before any pour or arm"
# GC_RIG unset and an unreadable roster leave pool-route.sh only the bare name,
# returned unverified. A polecat pool's pour stamps its rig-qualified identity,
# so a pour to the bare name could never read back as proved.
reset
GC_RIG="" run tk-w --reason "$REASON"
eq "$rc" 2 "a bare route -> visit, exit 2"
eq "$(slings)" "0" "nothing is poured to a bare name"
eq "$(meta tk-w gc.dispatch_when_ready)" "<absent>" "nothing is armed to a bare name"
eq "$(meta tk-w rejection_reason)" "$REASON" "the release stands for whoever finishes it"
no_bare_route "the bare name is not stamped as a route either"
has "$(cat "$STUB_ESC_LOG")" "the bare 'gc-toolkit.polecat'" "the visit names the bare route"
has "$(cat "$STUB_ESC_LOG")" "gc sling <rig>/gc-toolkit.polecat tk-w --on mol-polecat-work" "the visit names the rig-qualified pour that finishes it"
reset
GC_RIG="" run tk-w --reason "$REASON" --pool gc-toolkit.polecat
eq "$rc" 2 "a bare --pool with GC_RIG unset is refused the same way"
eq "$(slings)" "0" "nothing is poured to the bare --pool"

echo "# a refused release pours nothing"
reset
export STUB_UPDATE_FAIL="tk-w"
run tk-w --reason "$REASON"
eq "$rc" 2 "a refused transition -> visit, exit 2"
eq "$(slings)" "0" "nothing is poured onto a bead the release did not reach"
eq "$(meta tk-w rejection_reason)" "<absent>" "the refused release wrote nothing"
has "$(cat "$STUB_ESC_LOG")" "lifecycle transition did not land or did not verify" "the visit names the refused release"
eq "$(jq -r '.[0].id' "$TMP/stdout" 2>/dev/null)" "tk-w" "the row read before the refused release is still on stdout"

echo "# an unreadable bead pours nothing"
reset
export STUB_SHOW_FAIL=1
run tk-w --reason "$REASON"
eq "$rc" 2 "an unreadable bead -> visit, exit 2"
eq "$(grep -c '^bd update' "$STUB_GC_LOG" || true)" "0" "no write"
eq "$(slings)" "0" "no pour"
has "$(cat "$STUB_ESC_LOG")" "it could not be read" "the visit names the unreadable bead"
eq "$(wc -c < "$TMP/stdout" | tr -d ' ')" "0" "no row on stdout"

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
