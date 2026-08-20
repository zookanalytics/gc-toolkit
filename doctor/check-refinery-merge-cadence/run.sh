#!/usr/bin/env bash
# Pack doctor check: the refinery merge cadence is alive on every rig that
# imports this pack, and nothing is driving it out of band.
#
# WHY THIS EXISTS (tk-fdstg). `merge-skill.sh` fires only from the
# `refinery-reconcile` order (orders/refinery-reconcile.toml ->
# assets/scripts/refinery-reconcile.sh, scope = "rig"), so that order IS the
# merge queue's clock. Its own header says what happens when it stops: APPROVED
# + CLEAN pull requests sit unlanded "and nothing reports it". That sentence was
# literally true — no check asserted the cadence was ticking — and the hole cost
# twice over:
#
#   * 2026-08-19, the mechanism this order replaced (a per-rig /tmp daemon) died
#     with a host reboot. ~47 minutes with no merge cadence on any rig, invisible
#     to `gc doctor` by construction. docs/refinery-merge-cadence.md tells that
#     story.
#   * 2026-08-20, the inverse. A P1 was filed saying gc-toolkit's registration
#     had NEVER fired, when it had been firing in lockstep with the other three
#     rigs since the order's first tick. The triage surface lied (see the
#     `--limit 0` note below), and with no authoritative check to contradict it,
#     a guess became a P1.
#
# So this check answers one question, for real: does each rig's merge clock
# still tick? A green verdict here is the thing that was missing in both
# directions — it is what makes an outage loud, and equally what makes a false
# outage report cheap to disprove.
#
# `--limit 0` IS LOAD-BEARING. `gc order history <name>` is store-complete ONLY
# when the read is unbounded. Any positive `--limit` — including the default 50,
# and including a limit far larger than the number of rows that exist — returns
# runs from the city store alone and prints them under a RIG column, so the
# answer looks city-wide and is not. Measured on this city (2026-08-20): with 43
# retained runs across four rigs, `--limit 40`, `--limit 100` and `--since 20m`
# each returned gascity rows only; `--limit 0` returned all four rigs. That is
# two code paths, not an exhausted budget. `--since` keeps the unbounded read
# cheap (~3s here) without re-narrowing it, so the pairing below is deliberate:
#
#     gc order history refinery-reconcile --since "$WINDOW" --limit 0 --json
#
# Do not "optimize" that into a bounded read. A bound turns this check into a
# detector for one rig that reports on four — the exact failure it exists to
# end. The binary-side fix is filed against the gascity repo as gc-6a6vz; when it
# lands, `--limit 0` stays correct, so nothing here needs to change.
#
# ARMS
#   1. REGISTRATION. Every rig that has any of this pack's orders registered
#      must also have refinery-reconcile registered. `gc order list` omits
#      disabled orders, so a rig whose merge clock was switched off in city.toml
#      presents here as a rig missing the registration — which is what we want
#      to say about it either way.
#   2. LIVENESS. Every registered, non-suspended rig must have run the order at
#      least once inside the window (default 15m). Two shapes are separated
#      because they mean different things: some rigs fresh and some stale is a
#      per-rig outage with the controller demonstrably up; every rig stale is
#      the whole cadence down.
#   3. OUT-OF-BAND DRIVERS. A live /tmp/gc-refinery-idle-<rig>/idle-loop.sh is a
#      SECOND merge-skill.sh writer against the same anchors, and the
#      controller's single-flight gate keys on the order's ScopedName() so it
#      cannot see one. The order's whole premise is that there is exactly one
#      writer per rig. Note the deliberate narrowness: a RUNNING driver is
#      flagged; a leftover state DIRECTORY is not, and neither is a process that
#      merely names one. Reading an idle /tmp dir as "armed" is precisely the
#      liveness confusion catalogued in
#      specs/tk-agzpl/refinery-idle-driver-liveness.md, where a lock file
#      reported a driver that had been dead for hours — so the match is on the
#      command's SCRIPT ARGUMENT (the first non-option word of a shell, or
#      argv[0] for the script exec'd directly), not on the path appearing
#      anywhere in the line. `less /tmp/gc-refinery-idle-<rig>/idle-loop.sh` is
#      somebody reading the old driver, quite possibly to confirm it is gone;
#      calling that a live second writer would make this arm cry wolf at
#      exactly the people fixing it. The same holds one level in: `bash -c cat
#      …/idle-loop.sh` is a shell in argv[0] with the path in its command
#      string, and runs no driver — see the matcher for why that shape has to
#      be parsed rather than pattern-matched. Because the match starts at
#      argv[0], the process-table snapshot must be a command-only column; see
#      the ps ladder at the arm itself for why a PID-prefixed fallback silently
#      defeats it.
#
# COLD BOOT. A city started less than one tick ago has registrations and no runs
# yet, and arm 2 will call that stale. It is not a false statement — there is no
# recent run — and it clears itself on the next tick, so the message says so
# rather than the check guessing at uptime it cannot observe.
#
# FAIL CLOSED. An unreadable probe is a WARNING, never a pass. "We could not
# tell" and "there is nothing wrong" are different answers about a merge queue.
#
# Exit codes: 0=OK, 1=Warning, 2=Error
# stdout: first line=message, rest=details

set -u

dir="${GC_PACK_DIR:-.}"

ORDER_NAME="refinery-reconcile"

# `gc doctor` applies no timeout to pack checks, so an unbounded probe against a
# wedged control plane would hang the whole doctor run.
BOUND="${GC_DOCTOR_CHECK_TIMEOUT:-30}"

# How recent a run has to be. The declared interval is 60s, but the controller's
# real dispatch cadence on this city is several minutes for EVERY cooldown order
# (measured 2026-08-20: 30s-declared orders firing ~5-6 times per 20 minutes), so
# a window near the declared interval would flap (gascity gc-uhrgn). 15m is ~4
# observed ticks; tighten it when the dispatcher honours the declared interval.
WINDOW="${GC_DOCTOR_MERGE_CADENCE_WINDOW:-15m}"
case "$WINDOW" in
    [0-9]*[smh]) ;;
    *) WINDOW=15m ;;
esac

errors=()
warnings=()
notes=()

run_bounded() {
    if command -v timeout >/dev/null 2>&1; then
        timeout "$BOUND" "$@" </dev/null
    else
        # No coreutils timeout (some macOS hosts). Degrade to an unbounded call
        # rather than skipping the check entirely.
        "$@" </dev/null
    fi
}

# `printf '%s\n' "${arr[@]}"` with an EMPTY array still prints a blank line,
# which reads as an unexplained detail row in doctor output. Print nothing.
print_lines() { [ "$#" -eq 0 ] || printf '%s\n' "$@"; }

emit() { # message, then every collected line
    echo "$1"
    print_lines "${errors[@]+"${errors[@]}"}"
    print_lines "${warnings[@]+"${warnings[@]}"}"
    print_lines "${notes[@]+"${notes[@]}"}"
}

# ---------------------------------------------------------------------------
# Subject check. A check that quietly passes once the thing it watches is gone
# is worse than no check: it reports green about nothing. If this pack no longer
# ships the order, say so instead.
# ---------------------------------------------------------------------------
if [ ! -f "$dir/orders/$ORDER_NAME.toml" ]; then
    echo "merge cadence undetermined — this pack no longer ships orders/$ORDER_NAME.toml"
    echo "GC_PACK_DIR=$dir has no orders/$ORDER_NAME.toml, so this check has no subject."
    echo "If the cadence moved or was renamed, point this check at its new name; if it was deleted, delete this check with it. Do not leave it passing on absence."
    exit 1
fi

# ---------------------------------------------------------------------------
# This pack's own order names. Used to work out which rigs import the pack —
# by name, not by source path, so the answer holds no matter which rig's
# checkout GC_PACK_DIR points at.
# ---------------------------------------------------------------------------
pack_orders=""
for f in "$dir"/orders/*.toml; do
    [ -f "$f" ] || continue
    pack_orders="$pack_orders$(basename "$f" .toml)
"
done

# ---------------------------------------------------------------------------
# Live registrations.
# ---------------------------------------------------------------------------
orders_json=$(run_bounded gc order list --json 2>/dev/null)
if ! printf '%s' "$orders_json" | jq -e '(.orders | type) == "array"' >/dev/null 2>&1; then
    echo "merge cadence undetermined — cannot read the order registry"
    echo "\`gc order list --json\` returned no .orders array (timeout ${BOUND}s, or schema drift)."
    echo "Neither the registration arm nor the liveness arm ran; a stopped merge queue would not be visible."
    exit 1
fi

# Rigs where ANY order shipped by this pack is registered = rigs importing it.
pack_rigs=$(printf '%s' "$orders_json" \
    | jq -r --arg names "$pack_orders" '
        ($names | split("\n") | map(select(length > 0))) as $ours
        | [.orders[]? | select((.rig // "") != "") | select(.name as $n | $ours | index($n)) | .rig]
        | unique | .[]' 2>/dev/null)

registered_rigs=$(printf '%s' "$orders_json" \
    | jq -r --arg name "$ORDER_NAME" '
        [.orders[]? | select(.name == $name) | select((.rig // "") != "") | .rig]
        | unique | .[]' 2>/dev/null)

if [ -z "$registered_rigs" ]; then
    errors+=("$ORDER_NAME is not registered on ANY rig — the merge queue has no clock city-wide, and no pull request will land until it is back")
    emit "refinery merge cadence: NOT REGISTERED anywhere"
    echo ""
    echo "The order file exists at $dir/orders/$ORDER_NAME.toml but no live registration names it. Check the rigs' pack imports and any city.toml \`[[orders.overrides]]\` with \`enabled = false\` (\`gc order list\` omits disabled orders, so a disabled clock looks exactly like a missing one)."
    exit 2
fi

# Arm 1: an importing rig with no merge clock. Deliberately NOT skipped for
# suspended rigs, unlike the liveness arm below: a missing recent RUN is
# expected while a rig is suspended, but a missing REGISTRATION is a
# configuration defect that will still be there when it resumes, and saying so
# early is strictly better than discovering it when the rig comes back.
while read -r rig; do
    [ -n "$rig" ] || continue
    printf '%s\n' "$registered_rigs" | grep -qxF "$rig" && continue
    errors+=("$rig: imports this pack but has NO $ORDER_NAME registration — that rig has no merge cadence, so its APPROVED pull requests will not land (a city.toml \`enabled = false\` override presents this way too, because \`gc order list\` omits disabled orders)")
done <<< "$pack_rigs"

# ---------------------------------------------------------------------------
# Suspended rigs. `gc rig list --json` reports EFFECTIVE suspension (runtime
# state, not just suspended_on_start), which is what the skip needs. A roster we
# cannot read is a warning, not a licence to judge suspended rigs as stale.
# ---------------------------------------------------------------------------
suspended_rigs=""
rigs_json=$(run_bounded gc rig list --json 2>/dev/null)
if printf '%s' "$rigs_json" | jq -e '(.rigs | type) == "array"' >/dev/null 2>&1; then
    suspended_rigs=$(printf '%s' "$rigs_json" \
        | jq -r '.rigs[]? | select((.suspended // false) == true) | .name // empty' 2>/dev/null)
else
    warnings+=("could not read the rig roster (\`gc rig list --json\`, timeout ${BOUND}s) — a suspended rig cannot be told apart from a stalled one, so any staleness below may be a suspended rig")
fi

# ---------------------------------------------------------------------------
# Arm 2: liveness. See the --limit 0 note in the header before touching this.
# ---------------------------------------------------------------------------
hist_json=$(run_bounded gc order history "$ORDER_NAME" --since "$WINDOW" --limit 0 --json 2>/dev/null)
if ! printf '%s' "$hist_json" | jq -e '(.entries | type) == "array"' >/dev/null 2>&1; then
    warnings+=("could not read run history (\`gc order history $ORDER_NAME --since $WINDOW --limit 0 --json\`, timeout ${BOUND}s) — the liveness arm did not run, so a stopped cadence would not be visible here")
    if [ "${#errors[@]}" -ne 0 ]; then
        emit "refinery merge cadence: ${#errors[@]} problem(s), liveness undetermined"
        exit 2
    fi
    emit "refinery merge cadence partially determined"
    exit 1
fi

fresh_rigs=$(printf '%s' "$hist_json" \
    | jq -r '[.entries[]? | select((.rig // "") != "") | .rig] | unique | .[]' 2>/dev/null)

stale=()
checked=0
skipped_suspended=0
while read -r rig; do
    [ -n "$rig" ] || continue
    if [ -n "$suspended_rigs" ] && printf '%s\n' "$suspended_rigs" | grep -qxF "$rig"; then
        skipped_suspended=$((skipped_suspended + 1))
        notes+=("$rig: skipped (suspended — a suspended rig is not expected to run its cadence)")
        continue
    fi
    checked=$((checked + 1))
    printf '%s\n' "$fresh_rigs" | grep -qxF "$rig" && continue
    stale+=("$rig")
done <<< "$registered_rigs"

if [ "${#stale[@]}" -ne 0 ] && [ "$checked" -gt 0 ]; then
    if [ "${#stale[@]}" -eq "$checked" ]; then
        errors+=("NO rig has run $ORDER_NAME in the last $WINDOW (${stale[*]}) — the merge cadence is down city-wide and nothing will land until it is back. If the city was started within the last $WINDOW this clears on the next tick; otherwise the controller is not dispatching cooldown orders.")
    else
        for rig in "${stale[@]}"; do
            errors+=("$rig: registered but has NOT run $ORDER_NAME in the last $WINDOW, while other rigs have — this rig's merge queue is stopped on its own, so the controller is up and the fault is rig-scoped. Read its last passes in <GC_PACK_STATE_DIR>/$ORDER_NAME/$rig/pass.log, then \`gc order history $ORDER_NAME --rig $rig --limit 0\`.")
        done
    fi
fi

# ---------------------------------------------------------------------------
# Arm 3: out-of-band drivers. A live process only — see the header on why a
# leftover state directory is deliberately NOT evidence.
# ---------------------------------------------------------------------------
# Is this command line a driver actually RUNNING, rather than a process that
# merely mentions one? True for a shell invoked ON the script, and for the
# script exec'd directly. False for a pager, an editor, or a grep.
#
# The test is on the shell's SCRIPT ARGUMENT, not on argv[0] plus a substring
# match anywhere in the line. Both halves are load-bearing:
#
#   * `bash -c cat /tmp/gc-refinery-idle-<rig>/idle-loop.sh` names a shell in
#     argv[0] and the driver path in the line, and runs no driver at all — the
#     path is a word inside the -c command string. Reading argv[0] alone flags
#     it, which is this arm's own reader-is-not-a-driver false positive coming
#     back through the shell (tk-3t0ab). It is not hypothetical: `-c` wrappers
#     around the retired script are what agents and operators INSPECTING it
#     run, so the arm would cry wolf at exactly the people confirming it is
#     gone — and tell them to stop a service.
#   * `bash /other/script.sh /tmp/gc-refinery-idle-<rig>/idle-loop.sh` passes
#     the path as an argument to something else. Same reasoning.
#
# So: disqualify the shell forms that take no script file (`-c`, `-s`, and any
# short cluster containing either), skip the remaining options, and require the
# first non-option word to BE a driver script path.
#
# The deliberate trade-off: `bash -c '/tmp/gc-refinery-idle-<rig>/idle-loop.sh'`
# would RUN a driver, and this returns false for it. Telling that apart from
# `bash -c 'cat …/idle-loop.sh'` means parsing the command string as shell, and
# a check that guesses at shell semantics to decide whether to tell an operator
# to stop a service is worse than one that under-reports here. It also costs
# little in practice: bash exec's a lone simple command in place, so the
# process's own argv becomes the script path and the direct-exec branch below
# catches it; anything more complex leaves the driver running as a CHILD with
# its own argv, which this catches too. A false alarm aimed at the people
# retiring the driver is the failure that actually happened (tk-3t0ab).
is_driver_path() { # word
    case "$1" in
        *gc-refinery-idle-*/idle-loop.sh) return 0 ;;
    esac
    return 1
}

is_running_driver() { # command-line
    # Cheap prefilter: no driver path anywhere in the line, nothing to do.
    case "$1" in
        *gc-refinery-idle-*/idle-loop.sh*) ;;
        *) return 1 ;;
    esac

    # `local -` scopes the option change to this function (restored on return).
    # `set -f` matters: these words come from the process table, so an
    # unquoted `*` in somebody's command string must not glob against the
    # check's own cwd before we can read it.
    local -
    set -f
    # shellcheck disable=SC2086 # deliberate split: ps hands us argv as one string
    set -- $1
    [ "$#" -gt 0 ] || return 1

    case "${1##*/}" in
        sh|bash|dash|ksh|zsh)
            shift ;;
        *)
            # Not a shell. The only remaining driver shape is the script
            # exec'd directly, so argv[0] itself must be the driver script.
            is_driver_path "$1"
            return ;;
    esac

    # A shell. Walk its options to find the script argument.
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --)               shift; break ;;
            -c|--command)     return 1 ;;   # script comes from the ARGUMENT
            -s|--stdin)       return 1 ;;   # script comes from stdin
            -o|+o|--rcfile|--init-file)
                              shift 2 2>/dev/null || return 1; continue ;;
            --*)              shift; continue ;;
            -*c*|-*s*|+*c*|+*s*)
                              return 1 ;;   # short cluster, e.g. `-xc`
            -?*|+?*)          shift; continue ;;
            *)                break ;;
        esac
    done

    [ "$#" -gt 0 ] || return 1
    is_driver_path "$1"
}

# Snapshot the process table as a COMMAND-ONLY column.
#
# The matcher above parses each line as argv, starting at argv[0], so the SHAPE
# of this snapshot is load-bearing. `ps -eo args=` gives exactly that shape:
# argv, one process per line, no header and no leading columns. The fallbacks
# exist because that form is not universal — but the shapes are NOT
# interchangeable. `ps ax` prefixes every row with PID TTY STAT TIME, so the
# first word of a driver's line is a PID, never `bash`, and the argv walk can
# never fire.
# Falling back to it raw keeps the arm running while making it structurally
# incapable of reporting the second writer it exists to catch — a green verdict
# with a live driver on the host.
#
# So: ask for command-only forms first, and if the only form this host answers
# is the PID-prefixed one, strip its four leading columns rather than hand them
# to a matcher that cannot read them.
#
# A zero-row snapshot counts as a FAILED read, not as "no drivers running": the
# reading process is always in its own output, so an empty table is not an
# observation anyone can make. That also catches the restricted-/proc container
# where `ps` exits 0 and prints nothing — which would otherwise pass green.
ps_snapshot=""
ps_readable=0
for ps_form in "-eo args=" "ax -o args="; do
    # shellcheck disable=SC2086 # each form is a deliberate multi-word argv
    if ps_snapshot=$(ps $ps_form 2>/dev/null) && [ -n "$ps_snapshot" ]; then
        ps_readable=1
        break
    fi
done
if [ "$ps_readable" -eq 0 ]; then
    ps_raw=$(ps ax 2>/dev/null) || ps_raw=""
    if [ -n "$ps_raw" ]; then
        # Drop the header row, then everything up to and including the TIME
        # column, leaving COMMAND alone. Addressed by pattern rather than by
        # line number so both expressions stay portable across GNU and BSD sed.
        #
        # The strip anchors on TIME (`N:NN`) instead of counting a fixed number
        # of leading fields, because the count is not fixed: procps prints PID
        # TTY STAT TIME, busybox prints PID USER TIME. Blindly dropping four
        # fields on a three-column `ps` eats the first word of COMMAND, which
        # turns `less /tmp/gc-refinery-idle-<rig>/idle-loop.sh` into a bare
        # script path — and arm 3 reads a bare script path as a driver. That is
        # the reader-is-not-a-driver false positive this arm is written to
        # avoid, reintroduced through the fallback. Bounding the intermediate
        # fields to two keeps the match from running into COMMAND.
        ps_snapshot=$(printf '%s\n' "$ps_raw" | sed -E \
            -e '/^[[:space:]]*PID[[:space:]]+[A-Z]/d' \
            -e 's/^[[:space:]]*[0-9]+([[:space:]]+[^[:space:]]+){0,2}[[:space:]]+[0-9]+:[0-9][0-9][[:space:]]+//')
        [ -n "$ps_snapshot" ] && ps_readable=1
    fi
fi

if [ "$ps_readable" -eq 1 ]; then
    # ONE finding per rig, not per process. A driver is a shell loop: its
    # command substitutions fork children that inherit the same argv, so the
    # single live driver on this city showed up as three identical `ps` lines.
    # Emitting one error each would say "3 problems" about one daemon.
    rogue_rigs=""
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        is_running_driver "$line" || continue
        rig=$(printf '%s' "$line" | sed -n 's|.*gc-refinery-idle-\([^/ ]*\)/idle-loop\.sh.*|\1|p')
        rig="${rig:-<unknown>}"
        printf '%s\n' "$rogue_rigs" | grep -qxF "$rig" && continue
        rogue_rigs="$rogue_rigs$rig
"
        procs=$(printf '%s\n' "$ps_snapshot" | grep -cF "gc-refinery-idle-$rig/idle-loop.sh")
        errors+=("out-of-band refinery driver running for rig $rig ($procs process(es), e.g. \"$line\") — this is a SECOND merge-skill.sh writer against the same anchors, and the controller's single-flight gate keys on the order's ScopedName() so it cannot see this one. Retire it (\`systemctl --user stop gc-refinery-idle-$rig.service\`); the order already runs the same pass set.")
    done <<< "$ps_snapshot"
else
    # FAIL CLOSED. "We could not look" is not "there is nothing there": a note
    # leaves the exit code at 0, which publishes an OK verdict whose own summary
    # line claims "no out-of-band driver" on evidence nobody gathered.
    warnings+=("could not snapshot the process table — the out-of-band driver arm did not run, so a second merge-skill.sh writer against these anchors would not be visible here. \`ps\` answered none of the forms tried (-eo args=, ax -o args=, ax); check that it is installed and on PATH.")
fi

# ---------------------------------------------------------------------------
# Verdict.
# ---------------------------------------------------------------------------
if [ "${#errors[@]}" -ne 0 ]; then
    emit "refinery merge cadence: ${#errors[@]} problem(s)"
    echo ""
    echo "The merge cadence is the merge queue's clock — merge-skill.sh fires from nothing else. docs/refinery-merge-cadence.md has the mechanism and the single-flight contract. Do NOT restore an out-of-band driver as a workaround: that is a second writer the controller cannot serialise, and retiring it is why the order exists (tk-d83wm)."
    exit 2
fi

if [ "${#warnings[@]}" -ne 0 ]; then
    emit "refinery merge cadence partially determined"
    exit 1
fi

summary="OK: $ORDER_NAME registered and ticking on $checked rig(s) within $WINDOW, no out-of-band driver"
[ "$skipped_suspended" -gt 0 ] && summary="$summary ($skipped_suspended suspended rig(s) skipped)"
echo "$summary"
print_lines "${notes[@]+"${notes[@]}"}"
exit 0
