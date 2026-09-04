#!/usr/bin/env bash
# doctor/check-pour-text-current — I9: a molecule executes the formula text
# that is current when it runs (docs/component-model.md §3, tk-5w3boh). Two
# facts compose to break it: a graph.v2 step's description renders once at
# pour and never re-renders, and rigs/<rig> — the checkout the runtime
# executes — advances on the reconciler's 15m cooldown
# (orders/reconcile-rig-checkouts.toml). Three findings: LAGGED, a checkout
# behind its remote past the self-heal window; UNFETCHED, the remote-tracking
# ref itself unrefreshed — the fail-open case: only the reconciler's own fetch
# advances the ref rev-list compares against, so the behind-count reads 0 the
# moment the reconciler dies and is reported as a floor; STALE-TEXT, a live
# molecule root whose gc.formula_source last changed (git history, not mtime)
# after the root poured. Deliberately never fetches — a doctor check is a
# read, and fetching would repair the condition it observes. Read-only.
# Exit 0=OK 1=Warning 2=Error. stdout: first line = message, then "  - detail"
# lines. Live probes are bounded; an UNREADABLE probe warns (1), never passes.

set -u


# The reconciler's cooldown, and the multiplier that turns it into a "no
# longer self-healing" threshold. 3x, not 1x: a cooldown order fires slower
# than it declares (the queue is serialized; ~19m gaps measured on a healthy
# 15m cadence), and a threshold at the interval would flag the duty cycle.
INTERVAL="${GC_DOCTOR_RECONCILE_INTERVAL:-900}"
SLACK="${GC_DOCTOR_RECONCILE_SLACK:-3}"

# How long after pouring a molecule still counts as executing. in_progress
# alone admits husks (I8's defect — doctor/check-step-terminal); an explicit
# age bound that reports what it excluded beats an unreliable liveness probe.
LIVE_MAX="${GC_DOCTOR_MOLECULE_LIVE_MAX:-86400}"

errors=(); warnings=(); notes=()
# >>> doctor-budget
# One deadline for the whole check, anchored at process start. `gc doctor
# --check-timeout` (default 60s) abandons an overrunning check and discards
# everything it had buffered, so a check that has not printed by then is never
# heard. A per-probe constant does not hold that line: the probes below run
# once per rig, so their ceilings sum. Each probe gets the time still left
# instead, capped at half the budget so one wedged store cannot eat the rest,
# and a probe that no longer fits is refused with 124 — `timeout`'s own expiry
# code, which every caller's "this store was NOT checked" arm already handles.
# GC_DOCTOR_CHECK_TIMEOUT overrides the default, in whole seconds. Nothing
# exports it: the runner passes GC_CITY_PATH and GC_PACK_DIR and no budget.
BUDGET_DEFAULT=60; BUDGET_RESERVE=5; BUDGET_MIN_PROBE=2
budget_now() { if [ -n "${EPOCHSECONDS:-}" ]; then printf %s "$EPOCHSECONDS"; else date +%s; fi; }
budget_init() {
    BUDGET_TOTAL="${GC_DOCTOR_CHECK_TIMEOUT:-$BUDGET_DEFAULT}"; BUDGET_TOTAL="${BUDGET_TOTAL%s}"
    case "$BUDGET_TOTAL" in ''|*[!0-9]*) BUDGET_TOTAL="$BUDGET_DEFAULT" ;; esac
    BUDGET_CAP=$(( BUDGET_TOTAL / 2 ))
    BUDGET_DEADLINE=$(( $(budget_now) - SECONDS + BUDGET_TOTAL - BUDGET_RESERVE ))
}
budget_slice() {
    local left=$(( BUDGET_DEADLINE - $(budget_now) ))
    [ "$left" -le "$BUDGET_CAP" ] || left="$BUDGET_CAP"
    [ "$left" -ge 0 ] || left=0
    printf %s "$left"
}
budget_spent() { [ "$(budget_slice)" -lt "$BUDGET_MIN_PROBE" ]; }
run_bounded() { local s; s=$(budget_slice); [ "$s" -ge "$BUDGET_MIN_PROBE" ] || return 124
    if command -v timeout >/dev/null 2>&1; then timeout "$s" "$@" </dev/null; else "$@" </dev/null; fi; }
# A probe fed from a pipe cannot borrow run_bounded's </dev/null.
run_piped() { local s; s=$(budget_slice); [ "$s" -ge "$BUDGET_MIN_PROBE" ] || return 124
    if command -v timeout >/dev/null 2>&1; then timeout "$s" "$@"; else "$@"; fi; }
budget_init
# <<< doctor-budget
detail() { local v; for v in "$@"; do printf '  - %s\n' "$v"; done; }
# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload. All but
# LF go: raw TAB and CR do not occur in bd/gh output, and the TAB-splitting
# consumers downstream split jq's own @tsv, emitted after this runs.
scrub() { tr -d '\000-\011\013-\037'; }
# <<< control-char-scrub
mins() { printf '%s' "$(( $1 / 60 ))"; }

# mtime in epoch seconds, GNU then BSD stat; return 1 when neither reads it.
mtime_of() {
    local out
    out=$(stat -c %Y "$1" 2>/dev/null) && [ -n "$out" ] && { printf '%s' "$out"; return 0; }
    out=$(stat -f %m "$1" 2>/dev/null) && [ -n "$out" ] && { printf '%s' "$out"; return 0; }
    return 1
}

# ISO-8601 to epoch seconds, GNU then BSD date; the caller warns on failure —
# an unreadable timestamp is not evidence that a molecule is current.
epoch_of() {
    local ts="$1" out base
    out=$(date -u -d "$ts" +%s 2>/dev/null) && [ -n "$out" ] && { printf '%s' "$out"; return 0; }
    base="${ts%Z}"; base="${base%%.*}"
    out=$(date -u -j -f '%Y-%m-%dT%H:%M:%S' "$base" +%s 2>/dev/null) && [ -n "$out" ] && { printf '%s' "$out"; return 0; }
    return 1
}

NOW=$(date -u +%s 2>/dev/null || echo 0)
if [ "$NOW" -eq 0 ]; then
    echo "cannot determine whether the executed pack is current (I9)"
    detail "date(1) could not produce an epoch timestamp; every age below would be meaningless."
    exit 1
fi
STALE_AFTER=$(( INTERVAL * SLACK ))

# `gc rig list` is the roster the reconciler itself reads
# (assets/scripts/reconcile-rig-checkouts.sh), so this asserts that order's
# own contract over exactly the set it promises to keep current.
rigs_raw=$(run_bounded gc rig list --json 2>/dev/null); rigs_rc=$?
if [ "$rigs_rc" -ne 0 ] || [ -z "$rigs_raw" ]; then
    echo "cannot determine whether the executed pack is current (I9)"
    detail "\`gc rig list --json\` failed (rc=$rigs_rc) or returned nothing; there is no set of checkouts to scan."
    exit 1
fi
# US-joined so a rig with an empty name still yields its other fields intact.
scopes=$(printf '%s' "$rigs_raw" \
    | jq -r '.rigs[]? | select((.path // "") != "")
             | [((.name // "") | gsub("[[:cntrl:]]"; " ")), .path,
                ((.hq // false) | tostring), ((.suspended // false) | tostring)]
             | join("\u001f")' 2>/dev/null)
if [ -z "$scopes" ]; then
    echo "cannot determine whether the executed pack is current (I9)"
    detail "\`gc rig list --json\` listed no rig paths; the listing shape changed or the output is corrupt."
    exit 1
fi

# The roster is read into arrays FIRST because the stale-text half needs the
# whole set, not the rig it is standing in: a molecule's gc.formula_source
# routinely points at ANOTHER rig's checkout (rig-imported packs), and
# resolving only against the owning rig would skip every imported formula.
scope_names=(); scope_paths=(); scope_hq=(); scope_susp=()
while IFS=$'\037' read -r rig_name rig_path is_hq is_susp; do
    [ -n "$rig_path" ] || continue
    scope_names+=("${rig_name:-<unnamed>}")
    scope_paths+=("$rig_path")
    scope_hq+=("$is_hq")
    scope_susp+=("$is_susp")
done <<< "$scopes"
if [ "${#scope_paths[@]}" -eq 0 ]; then
    echo "cannot determine whether the executed pack is current (I9)"
    detail "The rig roster parsed to no usable (name, path) pairs."
    exit 1
fi

# owning_checkout <abs-file> — the scanned checkout containing this file, by
# LONGEST matching path (a city root is a prefix of every rig under it, and
# the nearest enclosing checkout is the one whose history dates the file).
owning_checkout() {
    local target="$1" best="" i
    for i in "${!scope_paths[@]}"; do
        case "$target" in
            "${scope_paths[$i]}"/*)
                if [ "${#scope_paths[$i]}" -gt "${#best}" ]; then best="${scope_paths[$i]}"; fi ;;
        esac
    done
    [ -z "$best" ] || printf '%s' "$best"
}

checked=0

# check_currency <label> <checkout> — the LAGGED / UNFETCHED half for one
# pack-source checkout.
check_currency() {
    local label="$1" rig_path="$2"
    local remote behind fetch_age fetched head_short oldest waited

    # The remote the reconciler advances to, resolved the same way it does.
    remote=$(run_bounded git -C "$rig_path" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)
    [ -n "$remote" ] || remote="origin/main"
    if ! run_bounded git -C "$rig_path" rev-parse --verify --quiet "$remote" >/dev/null 2>&1; then
        warnings+=("$label: remote-tracking ref \`$remote\` does not exist in $rig_path — currency was NOT checked")
        return 0
    fi
    behind=$(run_bounded git -C "$rig_path" rev-list --count "HEAD..$remote" 2>/dev/null)
    case "$behind" in
        ''|*[!0-9]*)
            warnings+=("$label: could not count commits behind \`$remote\` — currency was NOT checked")
            return 0 ;;
    esac
    checked=$((checked + 1))

    # FETCH_HEAD is rewritten by every `git fetch`, including one that brought
    # nothing new — its mtime dates the last time this checkout ASKED, which
    # is the question, not whether the answer changed.
    fetch_age=""
    if fetched=$(mtime_of "$rig_path/.git/FETCH_HEAD"); then
        fetch_age=$(( NOW - fetched ))
    fi
    if [ -z "$fetch_age" ]; then
        warnings+=("$label: no readable .git/FETCH_HEAD — cannot tell when \`$remote\` was last refreshed, so \"behind=$behind\" is unverifiable")
    elif [ "$fetch_age" -gt "$STALE_AFTER" ]; then
        # The fail-open case, reported even when behind=0 — and especially then.
        warnings+=("$label: \`$remote\` has not been refreshed for $(mins "$fetch_age")m (threshold $(mins "$STALE_AFTER")m) — reconcile-rig-checkouts is not fetching, so \"behind=$behind\" is a floor, not the lag. The checkout may be arbitrarily far behind what landed.")
    fi

    [ "$behind" -gt 0 ] || return 0
    head_short=$(run_bounded git -C "$rig_path" rev-parse --short HEAD 2>/dev/null || echo '?')
    if [ -z "$fetch_age" ] || [ "$fetch_age" -gt "$STALE_AFTER" ]; then
        errors+=("$label: executing a pack $behind commit(s) behind \`$remote\` at $head_short, and the remote ref is itself stale — the true lag is at least this and cannot be measured from here.")
        return 0
    fi

    # The remote ref is fresh, so the behind-count is trustworthy. Age the
    # finding by how long the OLDEST unmerged commit has waited: that is how
    # long the city has been executing something other than what landed.
    oldest=$(run_bounded git -C "$rig_path" log --format=%ct --reverse "HEAD..$remote" 2>/dev/null | head -n1)
    case "$oldest" in
        ''|*[!0-9]*)
            notes+=("$label: behind \`$remote\` by $behind commit(s) at $head_short; could not date them, so not judged against the $(mins "$STALE_AFTER")m threshold")
            return 0 ;;
    esac
    waited=$(( NOW - oldest ))
    if [ "$waited" -gt "$STALE_AFTER" ]; then
        errors+=("$label: executing a pack $behind commit(s) behind \`$remote\` at $head_short, and the oldest has been waiting $(mins "$waited")m — past the $(mins "$STALE_AFTER")m self-heal window. Agents in this rig are running reviewed code that is not what landed.")
    else
        notes+=("$label: behind \`$remote\` by $behind commit(s) at $head_short, oldest $(mins "$waited")m — inside the reconciler's $(mins "$STALE_AFTER")m window, self-healing")
    fi
}

for idx in "${!scope_paths[@]}"; do
    rig_name="${scope_names[$idx]}"
    rig_path="${scope_paths[$idx]}"
    is_hq="${scope_hq[$idx]}"
    is_susp="${scope_susp[$idx]}"
    label="$rig_name"

    # ── LAGGED / UNFETCHED, for the rigs the reconciler promises to advance.
    # In a function so its early returns cannot skip the stale-text half: a
    # rig whose lag is unmeasurable can still be running molecules.
    if [ "$is_hq" = "true" ]; then
        # Not a pack source, and reconcile-rig-checkouts.sh deliberately
        # excludes it (`select(.hq != true)`) — noted, not judged.
        notes+=("$label: HQ rig — not a pack source and deliberately excluded by reconcile-rig-checkouts.sh (\`select(.hq != true)\`); its checkout currency is not judged")
    elif [ ! -d "$rig_path/.git" ]; then
        warnings+=("$label: $rig_path is not a git checkout — currency of its pack source was NOT checked")
    else
        check_currency "$label" "$rig_path"
    fi

    # ── STALE-TEXT: live molecule roots in this rig's store. in_progress
    # only — an open root carrying a formula source is a husk (I8's defect,
    # doctor/check-step-terminal), and reporting husks would bury the finding.
    db="$rig_path/.beads"
    if [ "$is_susp" = "true" ]; then
        notes+=("$label: store skipped (suspended — querying it would auto-start an orphan Dolt server); stale step text was not checked here")
        continue
    fi
    if [ ! -d "$db" ]; then
        notes+=("$label: no bead store at $db — no molecule roots to check for stale text")
        continue
    fi
    roots_raw=$(run_bounded gc bd list --db "$db" \
        --status in_progress --has-metadata-key gc.formula_source \
        --json --limit 0 2>/dev/null)
    roots_rc=$?
    if [ "$roots_rc" -ne 0 ]; then
        warnings+=("$label: could not list live molecule roots in $db (rc=$roots_rc) — stale step text was NOT checked here")
        continue
    fi
    # An empty store answers `[]`; an empty STRING is a probe that produced
    # nothing at all, which is not the same thing and is not a pass.
    if [ -z "$roots_raw" ]; then
        warnings+=("$label: \`gc bd list\` over $db returned no output — stale step text was NOT checked here")
        continue
    fi
    rows=$(printf '%s' "$roots_raw" | scrub | jq -r '
        .[]? | [ (.id // "" | tostring),
                 (.created_at // "" | tostring),
                 ((.metadata["gc.formula_source"]) // "" | tostring) ]
             | join("\u001f")' 2>/dev/null)
    if [ $? -ne 0 ]; then
        warnings+=("$label: live-root listing from $db could not be parsed — stale step text was NOT checked here")
        continue
    fi

    aged_out=0; unresolved=0
    while IFS=$'\037' read -r root_id created src; do
        [ -n "$root_id" ] || continue
        if ! poured=$(epoch_of "$created"); then
            warnings+=("$label/$root_id: unreadable created_at (\"$created\") — cannot tell whether its step text is stale")
            continue
        fi
        # Older than the liveness cap: a husk, not a running molecule.
        if [ $(( NOW - poured )) -gt "$LIVE_MAX" ]; then
            aged_out=$((aged_out + 1))
            continue
        fi
        if [ -z "$src" ]; then
            unresolved=$((unresolved + 1))
            continue
        fi
        # Which checkout owns the formula — routinely NOT this rig's, because
        # rig-imported packs run another rig's formulas.
        owner=$(owning_checkout "$src")
        if [ -z "$owner" ]; then
            # A materialized pack cache is the common shape here — no git
            # history to date against and no reconciler advancing it.
            notes+=("$label/$root_id: gc.formula_source is under no scanned checkout ($src) — no git history to date it against, so staleness is unanswerable here")
            continue
        fi
        if [ ! -f "$src" ]; then
            warnings+=("$label/$root_id: gc.formula_source names a file that does not exist ($src) — the molecule's own formula cannot be read")
            continue
        fi
        if [ ! -d "$owner/.git" ]; then
            notes+=("$label/$root_id: gc.formula_source lives under $owner, which is not a git checkout — staleness is unanswerable there")
            continue
        fi
        rel="${src#"$owner"/}"
        # When the formula last changed, from git history rather than mtime:
        # a fresh clone stamps every file with the clone time, while the
        # commit date of the last change to the path dates when it landed.
        changed=$(run_bounded git -C "$owner" log -1 --format=%ct -- "$rel" 2>/dev/null)
        case "$changed" in
            ''|*[!0-9]*)
                # No history is not "unchanged": an untracked or newly-added
                # formula has none, and neither is evidence.
                warnings+=("$label/$root_id: no readable git history for \`$rel\` in $owner — cannot tell whether its step text is stale")
                continue ;;
        esac
        if [ "$changed" -gt "$poured" ]; then
            errors+=("$label/$root_id: poured $(mins $(( NOW - poured )))m ago from \`$rel\`, which last changed $(mins $(( NOW - changed )))m ago — $(mins $(( changed - poured )))m AFTER the pour. Its step descriptions were rendered once and still say what the formula said before that change (I9).")
        fi
    done <<< "$rows"

    [ "$aged_out" -eq 0 ] || notes+=("$label: $aged_out in_progress root(s) older than $(mins "$LIVE_MAX")m excluded as husks rather than live molecules — see doctor/check-step-terminal (I8)")
    [ "$unresolved" -eq 0 ] || notes+=("$label: $unresolved live root(s) carry an empty gc.formula_source — their step text cannot be dated")
done

if [ "$checked" -eq 0 ]; then
    echo "cannot determine whether the executed pack is current (I9)"
    detail "No pack-source checkout could be examined."
    detail ${warnings[@]+"${warnings[@]}"}
    detail ${notes[@]+"${notes[@]}"}
    exit 1
fi
if budget_spent; then
    warnings+=("this run reached its ${BUDGET_TOTAL}s doctor budget before every probe ran — what follows is partial, and an arm skipped for time is not an arm that passed")
fi
if [ "${#errors[@]}" -ne 0 ]; then
    echo "${#errors[@]} place(s) where the executed pack or a running molecule's text is not current (I9)"
    detail "${errors[@]}"
    detail ${warnings[@]+"${warnings[@]}"}
    detail ${notes[@]+"${notes[@]}"}
    exit 2
fi
if [ "${#warnings[@]}" -ne 0 ]; then
    echo "executed pack looks current across $checked checkout(s), but ${#warnings[@]} probe(s) could not be read (I9)"
    detail "${warnings[@]}"
    detail ${notes[@]+"${notes[@]}"}
    exit 1
fi
echo "OK: executed pack is current across $checked checkout(s); no live molecule is running superseded step text"
detail ${notes[@]+"${notes[@]}"}
exit 0
