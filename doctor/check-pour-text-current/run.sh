#!/usr/bin/env bash
# Pack doctor check: the pack the city EXECUTES is the pack that landed, and a
# running molecule's step text is not older than it. (docs/component-model.md
# §3, invariant I9.)
#
# THE INVARIANT. "A molecule executes the formula text that is current when it
# runs." Two facts compose to break it:
#
#   * A graph.v2 step bead's description is rendered ONCE, at pour, and never
#     re-renders. Whatever the formula said at that instant is what the agent
#     reads for the molecule's whole life.
#   * `rigs/<rig>/` — the checkout the runtime actually executes, since a pack
#     source is `rigs/<rig>` — advances to origin on a 15-minute cooldown
#     (`orders/reconcile-rig-checkouts.toml`). A merged PR is not live until
#     that order runs.
#
# Measured on tk-24aj5w: PR #443 (the graph.v2 step-close fix) merged at
# 16:06:49Z; the molecule for that bead poured at 16:06:31Z, eighteen seconds
# earlier, from the pre-#443 formula; the checkout advanced to #443 at
# 16:14:32Z. The molecule ran the superseded text for its entire life, minutes
# after the fix had landed on main.
#
# THE RECONCILER IS NOT THE BUG. It worked, and it self-heals. What was missing
# is that nothing asserts the executed pack matches the landed one, and nothing
# tells a running molecule its text is stale.
#
# ── THREE FINDINGS, REPORTED SEPARATELY ─────────────────────────────────────
#
#   LAGGED     A pack-source checkout is behind its remote ref by longer than
#              the reconciler's cooldown. Inside the window a lag is the
#              order's normal duty cycle and is not a finding; beyond it the
#              lag has stopped self-healing, and every agent in that rig is
#              running code that was reviewed and landed but is not what runs.
#
#   UNFETCHED  The checkout's remote-tracking ref has not been refreshed inside
#              that window. This is the finding that makes the check honest,
#              and it is worth more than it sounds: THE NAIVE CHECK FAILS OPEN
#              EXACTLY WHEN THE INVARIANT IS MOST BROKEN. `git rev-list
#              HEAD..origin/main` compares against the LOCAL remote-tracking
#              ref, which only the reconciler's own `git fetch` advances. Kill
#              the reconciler and both sides stop moving together: the
#              behind-count reads 0 while the checkout drifts arbitrarily far
#              from what actually landed. So the behind-count is reported as a
#              FLOOR, never as the truth, whenever the ref behind it is stale.
#
#              This check deliberately does NOT fetch. A doctor check is a
#              read; fetching would make it a network call inside a bounded
#              probe, and it would mutate the very refs it is trying to
#              measure — after which the fail-open above becomes unobservable
#              because the check itself repaired it.
#
#   STALE-TEXT A live molecule root whose `gc.formula_source` last changed in
#              the checkout's history AFTER the root poured. This is I9 itself.
#
# ── WHAT IS NOT FLAGGED, AND WHY ────────────────────────────────────────────
#
#   * The HQ rig. `reconcile-rig-checkouts.sh` selects `.hq != true`, so the
#     city root is never advanced by it — and it is not a pack source either
#     (`gc.formula_source` resolves under `rigs/<rig>/formulas/`). Flagging a
#     checkout nothing executes and nothing promises to advance would be
#     noise. It is NOTED, not judged, so a reader can see it was considered.
#
#   * A molecule root at status `open`. Live roots are `in_progress`; an open
#     root carrying a formula source is a molecule that never started or a
#     husk that never finalized. Measured 2026-08-24 on gc-toolkit: 71 open
#     roots, ALL of them older than the last formula change and the newest
#     19.3h old, against 11 in_progress roots of which 1 was stale. Reporting
#     the open ones would bury the single real finding under seventy husks —
#     and husks are I8's defect, already covered by
#     `check-finalized-molecule-step-reoffer`.
#
#   * An `in_progress` root older than the liveness cap. `in_progress` alone
#     still admits husks: the same census found one 51.9h old. A molecule that
#     poured two days ago and is still in_progress is not "executing" in any
#     sense this invariant is about. Excluded rows are NOTED with their count,
#     so the scoping is visible rather than silent.
#
# ── FAIL-CLOSED ─────────────────────────────────────────────────────────────
# Every probe that cannot be READ warns rather than passes. A check that
# reports OK when it could not see reproduces the silence it exists to remove.
#
# Exit codes: 0=OK, 1=Warning, 2=Error
# stdout: first line=message, rest=details

set -u

# `gc doctor` DOES bound pack checks (`--check-timeout`, default 60s) and a
# check that overruns is abandoned with its findings DISCARDED — so every probe
# here is individually bounded and the whole run stays local: no fetch, no
# network, one `gc rig list` plus a handful of git and bd reads per rig.
BOUND="${GC_DOCTOR_CHECK_TIMEOUT:-30}"

# The reconciler's own cooldown, in seconds, and the multiplier that turns it
# into a "no longer self-healing" threshold.
#
# The multiplier is NOT decoration. A cooldown order fires slower than it
# declares — the queue is serialized and a single gap of ~19 minutes has been
# measured on a HEALTHY 15-minute cadence — so a threshold at 1x the interval
# reports the duty cycle as a defect and trains everyone to ignore the check.
# 3x sits clear of that noise while still catching a reconciler that has
# genuinely stopped.
INTERVAL="${GC_DOCTOR_RECONCILE_INTERVAL:-900}"
SLACK="${GC_DOCTOR_RECONCILE_SLACK:-3}"

# How long after pouring a molecule is still plausibly executing. See the
# husk-exclusion note above for why this exists rather than a session query:
# the root's own gc.session_name is absent on most roots (8 of 11 in the
# census), so liveness would need a second per-store scan of the STEP beads to
# be trustworthy, and an unreliable liveness signal is worse than an explicit
# age bound that says what it excluded.
LIVE_MAX="${GC_DOCTOR_MOLECULE_LIVE_MAX:-86400}"

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

# Bead descriptions and notes carry control characters that make jq abort
# mid-parse, which would otherwise cost a whole store. Everything below 0x20
# except the newline goes — a literal TAB is invalid inside a JSON string just
# like the rest, and it also clears the 0x1F these rows are joined on, so no
# payload byte can pose as a field separator.
strip_ctl() { tr -d '\000-\011\013-\037'; }

# mtime in epoch seconds, GNU then BSD. Prints nothing and returns 1 when
# neither can read it.
mtime_of() {
    local out
    out=$(stat -c %Y "$1" 2>/dev/null) && [ -n "$out" ] && { printf '%s' "$out"; return 0; }
    out=$(stat -f %m "$1" 2>/dev/null) && [ -n "$out" ] && { printf '%s' "$out"; return 0; }
    return 1
}

# ISO-8601 to epoch seconds, GNU then BSD. Prints nothing and returns 1 when
# neither can read it — the caller then WARNS rather than assuming a value,
# because an unreadable timestamp is not evidence that a molecule is current.
epoch_of() {
    local ts="$1" out base
    out=$(date -u -d "$ts" +%s 2>/dev/null) && [ -n "$out" ] && { printf '%s' "$out"; return 0; }
    base="${ts%Z}"
    base="${base%%.*}"
    out=$(date -u -j -f '%Y-%m-%dT%H:%M:%S' "$base" +%s 2>/dev/null) && [ -n "$out" ] && { printf '%s' "$out"; return 0; }
    return 1
}

# Whole minutes, for messages an operator reads.
mins() { printf '%s' "$(( $1 / 60 ))"; }

NOW=$(date -u +%s 2>/dev/null || echo 0)
if [ "$NOW" -eq 0 ]; then
    echo "cannot determine whether the executed pack is current"
    echo "date(1) could not produce an epoch timestamp; every age below would be meaningless."
    exit 1
fi

STALE_AFTER=$(( INTERVAL * SLACK ))

# ---------------------------------------------------------------------------
# The scopes to check. `gc rig list` is the same roster the reconciler reads,
# so this check asserts that order's own contract over exactly the set it
# promises to keep current.
# ---------------------------------------------------------------------------
rigs_raw=$(run_bounded gc rig list --json 2>/dev/null)
rigs_rc=$?

if [ "$rigs_rc" -ne 0 ] || [ -z "$rigs_raw" ]; then
    echo "cannot determine whether the executed pack is current"
    echo "\`gc rig list --json\` failed (rc=$rigs_rc) or returned nothing; there is no set of checkouts to scan."
    exit 1
fi

# US-joined, not tab: a rig whose name is empty must still yield an empty FIRST
# field and a path in the second. Under a tab IFS bash would collapse the pair,
# land the path in rig_name and skip a whole checkout — the fail-open this
# check exists to remove.
scopes=$(printf '%s' "$rigs_raw" \
    | jq -r '.rigs[]? | select((.path // "") != "")
             | [((.name // "") | gsub("[[:cntrl:]]"; " ")), .path, ((.hq // false) | tostring)]
             | join("\u001f")' 2>/dev/null)

if [ -z "$scopes" ]; then
    echo "cannot determine whether the executed pack is current"
    echo "\`gc rig list --json\` listed no rig paths; the listing shape changed or the output is corrupt."
    exit 1
fi

# check_currency <label> <checkout> — the LAGGED / UNFETCHED half for one
# pack-source checkout. Appends to errors/warnings/notes and bumps `checked`.
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

    # How long ago the remote-tracking ref was last refreshed. FETCH_HEAD is
    # rewritten by every `git fetch`, including one that brought nothing new,
    # so its mtime dates the last time this checkout ASKED — which is the
    # question, not whether the answer changed.
    fetch_age=""
    if fetched=$(mtime_of "$rig_path/.git/FETCH_HEAD"); then
        fetch_age=$(( NOW - fetched ))
    fi

    if [ -z "$fetch_age" ]; then
        warnings+=("$label: no readable .git/FETCH_HEAD — cannot tell when \`$remote\` was last refreshed, so \"behind=$behind\" is unverifiable")
    elif [ "$fetch_age" -gt "$STALE_AFTER" ]; then
        # THE FAIL-OPEN CASE. Reported even when behind=0, and especially then.
        warnings+=("$label: \`$remote\` has not been refreshed for $(mins "$fetch_age")m (threshold $(mins "$STALE_AFTER")m) — reconcile-rig-checkouts is not fetching, so \"behind=$behind\" is a FLOOR, not the lag. The checkout may be arbitrarily far behind what landed.")
    fi

    [ "$behind" -gt 0 ] || return 0

    head_short=$(run_bounded git -C "$rig_path" rev-parse --short HEAD 2>/dev/null || echo '?')

    if [ -z "$fetch_age" ] || [ "$fetch_age" -gt "$STALE_AFTER" ]; then
        errors+=("$label: executing a pack $behind commit(s) behind \`$remote\` at $head_short, and the remote ref is itself stale — the true lag is at least this and cannot be measured from here.")
        return 0
    fi

    # The remote ref is fresh, so the behind-count is trustworthy. Age the
    # finding by how long the OLDEST unmerged commit has been waiting rather
    # than by the fetch: that is how long the city has been executing something
    # other than what landed.
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

# The roster is read into arrays FIRST because the second half of this check
# needs the whole set, not just the rig it is standing in: a molecule's
# gc.formula_source routinely points at ANOTHER rig's checkout. gc-toolkit is
# rig-imported by four rigs here, so resolving a formula only against the rig
# that owns the molecule would skip almost every molecule outside gc-toolkit —
# measured 2026-08-24: of gascity's 5 live roots, 1 runs gc-toolkit's formula
# and 4 run a materialized pack, and NONE of them runs gascity's own.
scope_names=()
scope_paths=()
scope_hq=()

while IFS=$'\037' read -r rig_name rig_path is_hq; do
    [ -n "$rig_path" ] || continue
    scope_names+=("${rig_name:-<unnamed>}")
    scope_paths+=("$rig_path")
    scope_hq+=("$is_hq")
done <<ROSTER_EOF
$scopes
ROSTER_EOF

if [ "${#scope_paths[@]}" -eq 0 ]; then
    echo "cannot determine whether the executed pack is current"
    echo "The rig roster parsed to no usable (name, path) pairs."
    exit 1
fi

# owning_checkout <abs-file> — the scanned checkout that contains this file,
# by longest matching path, or nothing. Longest-match because a rig path can
# be a prefix of another (a city root is a prefix of every rig under it), and
# the nearest enclosing checkout is the one whose history dates the file.
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

for idx in "${!scope_paths[@]}"; do
    rig_name="${scope_names[$idx]}"
    rig_path="${scope_paths[$idx]}"
    is_hq="${scope_hq[$idx]}"
    label="$rig_name"

    # ── LAGGED / UNFETCHED, for the rigs the reconciler promises to advance ──
    # In a function so its early returns cannot skip the STALE-TEXT half below:
    # a rig whose lag is unmeasurable can still be running molecules, and
    # dropping them because git could not answer a different question is the
    # fail-open this check exists to remove.
    if [ "$is_hq" = "true" ]; then
        # Out of scope for CURRENCY by construction — see the header. Its store
        # is still scanned for stale text.
        notes+=("$label: HQ rig — not a pack source and deliberately excluded by reconcile-rig-checkouts.sh (\`select(.hq != true)\`); its checkout currency is not judged")
    elif [ ! -d "$rig_path/.git" ]; then
        warnings+=("$label: $rig_path is not a git checkout — currency of its pack source was NOT checked")
    else
        check_currency "$label" "$rig_path"
    fi

    # ── STALE-TEXT ──────────────────────────────────────────────────────────
    # Live molecule roots in this rig's store. `in_progress` is the live state;
    # see the header for why `open` is excluded rather than merely quiet.
    db="$rig_path/.beads"
    if [ ! -d "$db" ]; then
        notes+=("$label: no bead store at $db — no molecule roots to check for stale text")
        continue
    fi

    roots_raw=$(run_bounded bd list --db "$db" \
        --status in_progress --has-metadata-key gc.formula_source \
        --json --limit 0 2>/dev/null)
    roots_rc=$?

    if [ "$roots_rc" -ne 0 ]; then
        warnings+=("$label: could not list live molecule roots in $db (rc=$roots_rc) — stale step text was NOT checked here")
        continue
    fi
    # An empty store answers `[]`; an empty STRING means the probe produced
    # nothing at all, which is not the same thing and is not a pass.
    if [ -z "$roots_raw" ]; then
        warnings+=("$label: \`bd list\` over $db returned no output — stale step text was NOT checked here")
        continue
    fi

    rows=$(printf '%s' "$roots_raw" | strip_ctl | jq -r '
        .[]? | [ (.id // "" | tostring),
                 (.created_at // "" | tostring),
                 ((.metadata["gc.formula_source"]) // "" | tostring) ]
             | join("\u001f")' 2>/dev/null)
    rows_rc=$?

    if [ "$rows_rc" -ne 0 ]; then
        warnings+=("$label: live-root listing from $db could not be parsed — stale step text was NOT checked here")
        continue
    fi

    aged_out=0
    unresolved=0

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

        # WHICH CHECKOUT OWNS THE FORMULA, which is routinely NOT this rig's.
        # gc-toolkit is rig-imported by four rigs here, so a molecule in gascity
        # normally runs gc-toolkit's formula. Judging a molecule only against
        # its own rig would skip every imported one — measured 2026-08-24: of
        # gascity's live roots, NONE runs gascity's own formula.
        owner=$(owning_checkout "$src")

        if [ -z "$owner" ]; then
            # A materialized pack cache (`~/.gc/cache/repos/<hash>/<pack>`) is
            # the common shape here, and it is not a git checkout at all — so
            # there is no history to date the formula against, and no
            # reconciler advancing it either. Unanswerable, and said so.
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

        # WHEN THE FORMULA LAST CHANGED, from git history rather than mtime.
        # mtime is set by whatever wrote the working tree, so a fresh clone
        # stamps every file with the clone time and would report every molecule
        # in the city as stale. The commit date of the last change to this path
        # is content-derived, survives a re-clone, and — because this repo
        # squash-merges — dates the moment the change actually landed.
        changed=$(run_bounded git -C "$owner" log -1 --format=%ct -- "$rel" 2>/dev/null)
        case "$changed" in
            ''|*[!0-9]*)
                # No history for the path is not "unchanged": an untracked or
                # newly-added formula has none, and neither is evidence.
                warnings+=("$label/$root_id: no readable git history for \`$rel\` in $owner — cannot tell whether its step text is stale")
                continue ;;
        esac

        if [ "$changed" -gt "$poured" ]; then
            errors+=("$label/$root_id: poured $(mins $(( NOW - poured )))m ago from \`$rel\`, which last changed $(mins $(( NOW - changed )))m ago — $(mins $(( changed - poured )))m AFTER the pour. Its step descriptions were rendered once and still say what the formula said before that change (I9).")
        fi
    done <<INNER_EOF
$rows
INNER_EOF

    [ "$aged_out" -eq 0 ] || notes+=("$label: $aged_out in_progress root(s) older than $(mins "$LIVE_MAX")m excluded as husks rather than live molecules — see check-finalized-molecule-step-reoffer (I8)")
    [ "$unresolved" -eq 0 ] || notes+=("$label: $unresolved live root(s) carry an empty gc.formula_source — their step text cannot be dated")

done <<OUTER_EOF
$scopes
OUTER_EOF

if [ "$checked" -eq 0 ]; then
    echo "cannot determine whether the executed pack is current"
    echo "No pack-source checkout could be examined."
    print_lines "${warnings[@]+"${warnings[@]}"}"
    print_lines "${notes[@]+"${notes[@]}"}"
    exit 1
fi

n_err=${#errors[@]}
n_warn=${#warnings[@]}

if [ "$n_err" -gt 0 ]; then
    echo "$n_err place(s) where the executed pack or a running molecule's text is not current"
    print_lines "${errors[@]+"${errors[@]}"}"
    print_lines "${warnings[@]+"${warnings[@]}"}"
    print_lines "${notes[@]+"${notes[@]}"}"
    exit 2
fi

if [ "$n_warn" -gt 0 ]; then
    echo "executed pack looks current across $checked checkout(s), but $n_warn probe(s) could not be read"
    print_lines "${warnings[@]+"${warnings[@]}"}"
    print_lines "${notes[@]+"${notes[@]}"}"
    exit 1
fi

echo "executed pack is current across $checked checkout(s); no live molecule is running superseded step text"
print_lines "${notes[@]+"${notes[@]}"}"
exit 0
