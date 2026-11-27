#!/usr/bin/env bash
# reconcile-rig-checkouts — keep the live rigs/* checkouts advanced to origin.
#
# The live rigs/* checkouts are what the runtime executes (pack
# source = "rigs/<rig>"); the refinery merges PRs via its own clone, so a
# merged PR is NOT live until the checkout syncs. For each rig but the HQ root
# this runs `git fetch origin` and, with HEAD on origin's default branch,
# `git merge --ff-only --no-overwrite-ignore origin/<default>`.
#
# --ff-only advances only on a clean fast-forward, keeps a dirty file the
# incoming commits do not touch, and refuses, mutating nothing, on a divergence,
# on a local change to a path the incoming commits rewrite, or on untracked
# content in the way of what they write. --no-overwrite-ignore makes that
# include an ignored file, which git otherwise overwrites. A file the incoming
# commits delete leaves the working tree with them when its copy is unmodified,
# as in any fast-forward.
#
# The rig root must also stay ON the default branch: it is a deploy mirror, and a
# HEAD parked elsewhere (detached, or a feature/integration branch an agent
# checked out and left) never fast-forwards and serves an off-default build to
# directory-imported packs. ff-only cannot see that, since a checkout ahead of
# the default reports "Already up to date" and looks advanced, so this reads the
# local branch first and runs no fast-forward on a parked HEAD.
#
# A pack the city imports from a checkout runs from its working tree, and the
# city's config names that pack's agents by exact name, so a tree that drops or
# renames one stops the config from loading. Before it fast-forwards such a
# checkout, the pass puts copies of the city's city.toml, pack.toml, packs.lock
# and .gc/site.toml beside the incoming tree and runs `gc config show
# --validate` on them. It holds the fast-forward when the config does not load
# with the incoming tree but does with the tree at HEAD. A config that fails
# with both is no fault of the incoming commits, and holds nothing. A held
# fast-forward takes the exception path, with what gc said.
#
# A parked HEAD and a refused fast-forward take the exception path, which never
# touches the checkout: one idempotent bead per blocked rig records why, and a
# human gate on it asks someone to act. A rig whose fetch fails is skipped until
# a pass that can fetch. The failed fetch leaves the checkout's .git/FETCH_HEAD
# empty, which doctor/check-pour-text-current reports as unfetched. The doctor
# order (orders/doctor-run.toml) records that check every hour, and the helm
# board's city page shows a check that two runs in a row found failing
# (services/helm/README.md), so a fetch that keeps failing reaches a person and
# a single failed pass does not.
#
# A stalled deploy has to reach someone, so a blocked rig is NOT handed to a
# fixed agent address — an address no agent holds is a bead nobody works, and a
# nudge into the void is worse than no safety net. The per-rig bead is the
# durable, self-healing SUBJECT: it carries the diagnosis and auto-closes when
# the rig next fast-forwards cleanly. human-gate.sh files a human gate that
# blocks it, which the helm board shows to the operator. It files nothing and
# exits 0 while that gate is open or while the quiet window below holds. It
# exits non-zero when it could not read the bead's gates, or could not file the
# gate.
#
# Runs as an exec order (no LLM, no agent, no wisp).
set -euo pipefail

warn() { echo "reconcile-rig-checkouts: $*" >&2; }

SELF_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
HUMAN_GATE_SH="${GC_RECONCILE_HUMAN_GATE_TOOL:-$SELF_DIR/human-gate.sh}"

# The store the per-rig subject bead lives in. Its gate lands beside it.
RECONCILE_RIG="${RECONCILE_BEAD_RIG:-gc-toolkit}"
# A blocked rig stays blocked from one pass to the next, and each pass detects
# it again on the same subject bead, so the gate's call declares a quiet window:
# a person's moot or benign answer stands for a day. A rig that blocks again
# after a clean sync files on a new subject bead, which no earlier answer mutes.
QUIET_WINDOW=86400

# id of the single open reconcile bead for a rig (empty if none).
open_bead() {
    gc bd --rig "$RECONCILE_RIG" list --metadata-field "reconcile_rig=$1" --json 2>/dev/null \
        | jq -r '.[0].id // empty' 2>/dev/null || true
}

# File a stalled rig as a human gate that blocks its subject bead. The exit
# status is human-gate.sh's, so the caller can report a total failure.
gate_divergence() {
    local subject="$1" key="$2" message="$3"
    "$HUMAN_GATE_SH" --subject "$subject" --key "$key" --quiet-window "$QUIET_WINDOW" \
        --message "$message" >/dev/null
}

# Withdraw the gate on a subject whose stall has resolved. The subject bead
# auto-closes on a clean sync, and its gate blocks that close until it is
# cleared, so a rig that recovers before the operator answers would otherwise
# leave a moot gate on the board and the subject open behind it. The subject
# tracks exactly this one stall and clears only on a clean sync, so
# subject-resolved is premise-moot here: human-gate.sh --retract resolves the
# open gate with a moot: reason. A failure returns non-zero so the caller skips
# the subject close: bd list defaults away from closed beads and open_bead does
# not pass --all, so leaving the subject open on failure is the retry handle —
# the next patrol re-finds it and retries.
retract_gate() {
    local subject="$1" key="$2" message="$3"
    if "$HUMAN_GATE_SH" --retract --subject "$subject" --key "$key" --message "$message" >/dev/null; then
        return 0
    fi
    warn "could not withdraw the gate on $subject — leaving its subject open so the next patrol retries"
    return 1
}

# A rig that fast-forwarded clears its exception: withdraw the gate as moot,
# then close the subject. The close waits on retract_gate, so a failed
# withdrawal leaves the subject open as the retry handle.
resolve_subject() {
    local name="$1" reading="$2" bead
    bead=$(open_bead "$name")
    [ -n "$bead" ] || return 0
    if retract_gate "$bead" "reconcile-diverged-$name" "$reading; the stall this gate asked about is resolved."; then
        # Gas City's close gate asks the close of a plain task for its work
        # record, and a subject ships nothing.
        gc bd --rig "$RECONCILE_RIG" update "$bead" --set-metadata gc.work_outcome=no-op >/dev/null 2>&1 || true
        gc bd --rig "$RECONCILE_RIG" close "$bead" --reason "$reading" >/dev/null 2>&1 || true
    fi
}

# pack_source <rel> — whether the city's config imports a pack from <rel>, a
# path inside the city, or from a folder under it.
pack_source() {
    local source
    while IFS= read -r source; do
        case "$source" in "$1" | "$1"/*) return 0 ;; esac
    done < <(sed -n 's/^[[:space:]]*source[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' \
        "$CITY_DIR/city.toml" "$CITY_DIR/pack.toml" 2>/dev/null)
    return 1
}

# scratch_city <dir> <path> <rel> <rev> — copies of the city's config files in
# <dir>, with the tree of <rev> in the checkout at <path> where <rel> puts it.
scratch_city() {
    local dir="$1" path="$2" rel="$3" rev="$4" file
    mkdir -p "$dir/.gc" "$dir/$rel" || return 1
    for file in city.toml pack.toml packs.lock .gc/site.toml; do
        [ ! -f "$CITY_DIR/$file" ] || cp "$CITY_DIR/$file" "$dir/$file" || return 1
    done
    git -C "$path" archive "$rev" | tar -x -C "$dir/$rel"
}

# config_refusal <path> <remote> — gc's error lines when the city's config does
# not load with the tree a fast-forward of the checkout at <path> to <remote>
# brings, but does with the tree at HEAD (see the header). It prints nothing
# for a checkout no pack of the city comes from, or one the fast-forward would
# not move.
config_refusal() {
    local path="$1" remote="$2" rel head next scratch said=""
    [ -n "$CITY_DIR" ] && [ -f "$CITY_DIR/city.toml" ] || return 0
    case "$path" in "$CITY_DIR"/*) rel="${path#"$CITY_DIR"/}" ;; *) return 0 ;; esac
    pack_source "$rel" || return 0
    head=$(git -C "$path" rev-parse HEAD 2>/dev/null) && next=$(git -C "$path" rev-parse "$remote" 2>/dev/null) || return 0
    [ "$head" != "$next" ] && git -C "$path" merge-base --is-ancestor "$head" "$next" 2>/dev/null || return 0
    scratch=$(mktemp -d "${TMPDIR:-/tmp}/reconcile-config.XXXXXX") || return 0
    if scratch_city "$scratch/next" "$path" "$rel" "$next" \
        && ! said=$(gc config show --validate --city "$scratch/next" 2>&1 >/dev/null) \
        && scratch_city "$scratch/head" "$path" "$rel" "$head" \
        && gc config show --validate --city "$scratch/head" >/dev/null 2>&1; then
        said=$(printf '%s\n' "$said" | grep -v ': warning: ' || true)
        printf '%s\n' "${said:-gc config show --validate refused the incoming tree with no error line}"
    fi
    rm -rf -- "$scratch"
}

advanced=0; blocked=0
map=$("$SELF_DIR/rig-map.sh") || exit 0
rigs=$(jq -r '.rigs[] | select(.hq != true) | "\(.name)\t\(.path)"' <<< "$map") || exit 0
# The city's root, whose config the packs in its checkouts feed.
CITY_DIR=$(jq -r '[.rigs[] | select(.hq == true) | .path][0] // empty' <<< "$map")

while IFS=$'\t' read -r name path; do
    [ -n "${name:-}" ] && [ -d "$path/.git" ] || continue
    git -C "$path" fetch origin --quiet 2>/dev/null || continue
    remote=$(git -C "$path" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || echo origin/main)
    default_branch="${remote#origin/}"

    # The fast-forward runs only on the default branch (see the header). When
    # git refuses it, the refusal keeps git's error lines and the paths it names
    # under them, and drops git's advice lines, which suggest commits, stashes
    # and merges that a deploy mirror never takes.
    local_branch=$(git -C "$path" symbolic-ref --short HEAD 2>/dev/null || true)
    refusal=""
    held=""
    [ "$local_branch" != "$default_branch" ] || held=$(config_refusal "$path" "$remote")
    if [ "$local_branch" = "$default_branch" ] && [ -z "$held" ]; then
        if refusal=$(git -C "$path" merge --ff-only --no-overwrite-ignore "$remote" 2>&1 >/dev/null); then
            # Advanced or already up to date.
            advanced=$((advanced + 1))
            resolve_subject "$name" "rigs/$name fast-forwarded cleanly to $remote"
            continue
        fi
        refusal=$(printf '%s\n' "$refusal" | awk '/^(Please |Aborting$|hint:)/ || NF == 0 { next } { sub(/^\t/, "  "); print }')
        [ -n "$refusal" ] || refusal="git merge --ff-only refused with no message"
    fi

    # Reached when the HEAD is parked off the default branch, the city's config
    # does not load with the incoming tree, or git refused the fast-forward.
    # File the subject bead and its human gate.
    blocked=$((blocked + 1))
    porcelain=$(git -C "$path" status --porcelain 2>/dev/null || true)
    local_log=$(git -C "$path" log --oneline "$remote"..HEAD 2>/dev/null || true)
    title="Reconcile: rigs/$name cannot fast-forward to $remote"
    # The reset a diverged checkout's gate hands a person. It refuses rather
    # than loses what is in its way.
    reset_cmd="git -C $path checkout --no-overwrite-ignore -B $default_branch $remote"
    restore_cmd="git -C $path restore --source=HEAD --staged --worktree -- <file>"
    if [ -n "$held" ]; then
        stall=config
        incoming_log=$(git -C "$path" log --oneline HEAD.."$remote" 2>/dev/null || true)
        body=$(printf 'rigs/%s is held where it is: the config of the city does not load with the\ntree %s brings, though it loads with the tree the checkout holds now.\nPath: %s\nCity: %s\n\n## What gc config show --validate said\n%s\n\nThe city.toml of the town names the agents of this pack by exact name, so an\nincoming commit that deletes or renames one fails the whole load. Make the\nconfig load with the incoming tree, and this bead closes on its own when the\nrig next fast-forwards cleanly:\n- An agent the incoming commits delete or rename: take each entry that names\n  it out of the city.toml of the town, or rename it there.\n- A pack change that should not have landed: revert it on %s.\n\n## git log --oneline HEAD..%s\n%s\n' \
            "$name" "$remote" "$path" "$CITY_DIR" "$held" "$default_branch" "$remote" "$incoming_log")
    elif [ "$local_branch" != "$default_branch" ]; then
        stall=parked
        body=$(printf 'rigs/%s is parked off %s — its live checkout HEAD is on %s.\nPath: %s\n\nThe rig root is a deploy mirror: reconcile fast-forwards it to %s and\ndirectory-imported packs build from its working tree, so nothing checks out a\nbranch or commits there. Restore it once any local work is saved elsewhere:\n  git -C %s checkout %s\nThis bead closes on its own when the rig next fast-forwards cleanly.\n\n## git status --porcelain\n%s\n\n## git log --oneline %s..HEAD\n%s\n' \
            "$name" "$default_branch" "${local_branch:-<detached HEAD>}" "$path" \
            "$default_branch" "$path" "$default_branch" "$porcelain" "$remote" "$local_log")
    elif git -C "$path" merge-base --is-ancestor HEAD "$remote" 2>/dev/null; then
        stall=behind
        body=$(printf 'rigs/%s could not fast-forward to %s, though it is only behind it.\nPath: %s\n\n## What git refused\n%s\n\nJudge each path git names, then act. This bead closes on its own when the\nrig next fast-forwards cleanly.\n- A stray write: %s\n- Machine-local config: carry it across the incoming change by hand.\n- Real work: save it elsewhere first.\n- An untracked file in the way: move it aside. git calls an ignored file in\n  the way untracked too, though git status does not list it.\n\n## git status --porcelain\n%s\n' \
            "$name" "$remote" "$path" "$refusal" "$restore_cmd" "$porcelain")
    else
        stall=diverged
        body=$(printf 'rigs/%s could not fast-forward to %s: its live checkout holds commits that\n%s does not.\nPath: %s\n\n## What git refused\n%s\n\nJudge and act. This bead closes on its own when the rig next fast-forwards\ncleanly. To reset the checkout by hand:\n1. Save real work elsewhere, since the reset drops each local commit.\n2. Restore each local change you judge a stray write:\n     %s\n3. Move aside each untracked file in the way of the reset, an ignored one\n   included, which git status does not list.\n4. Reset:\n     %s\nThe reset keeps a local change on a path it does not rewrite, such as\nmachine-local config. It refuses, rather than overwrites or deletes, a local\nchange or an untracked file still in its way, an ignored file included, so\nskipping step 2 or 3 costs a refusal, not content. A local commit does not\nstop it, so only step 1 keeps one. Carry machine-local config across by hand\nwhere the reset rewrites its path.\n\n## git status --porcelain\n%s\n\n## git log --oneline %s..HEAD\n%s\n' \
            "$name" "$remote" "$remote" "$path" "$refusal" "$restore_cmd" "$reset_cmd" \
            "$porcelain" "$remote" "$local_log")
    fi

    bead=$(open_bead "$name")
    if [ -n "$bead" ]; then
        gc bd --rig "$RECONCILE_RIG" update "$bead" --title "$title" --description "$body" >/dev/null 2>&1 || true
    else
        bead=$(gc bd --rig "$RECONCILE_RIG" create "$title" \
            -t task -d "$body" --json 2>/dev/null | jq -r '.id // empty' 2>/dev/null || true)
        [ -n "$bead" ] || { warn "could not file a reconcile bead for rigs/$name — its stalled deploy is UNTRACKED and nobody was asked"; continue; }
        gc bd --rig "$RECONCILE_RIG" update "$bead" --set-metadata reconcile_rig="$name" >/dev/null 2>&1 || true
    fi

    # Make someone hear about it. A failure here is reported, never swallowed —
    # a stall nobody is asked about is the exact silent rot this script
    # prevents.
    case "$stall" in
        config)
            msg=$(printf 'rigs/%s is held off %s: the config of the city does not load with the tree it brings, so its pack change is not live.\ngc config show --validate said: %s\nPath: %s\nSubject bead %s carries what gc said in full and the incoming commits, and clears when rigs/%s next fast-forwards cleanly.\nMake the config load with the incoming tree: take each city.toml entry that names an agent the incoming commits delete or rename out of the town repo, or revert the pack change.' \
                "$name" "$remote" "$(printf '%s\n' "$held" | head -1)" "$path" "$bead" "$name") ;;
        parked)
            msg=$(printf 'rigs/%s is parked off its deploy branch %s — HEAD is on %s, so reconcile cannot advance it and its working tree serves an off-%s build to every directory-imported pack.\nPath: %s\nSubject bead %s carries the full git status and log, and clears when rigs/%s next fast-forwards cleanly.\nRestore it: save any local work elsewhere, then git -C %s checkout %s.' \
                "$name" "$default_branch" "${local_branch:-<detached HEAD>}" "$default_branch" "$path" "$bead" "$name" "$path" "$default_branch") ;;
        behind)
            msg=$(printf 'rigs/%s cannot fast-forward to %s, though it is only behind it, and its deploy is stalled.\nPath: %s\nSubject bead %s names what git refused and carries the full git status, and clears when rigs/%s next fast-forwards cleanly.\nRestore a stray write with %s, carry machine-local config across the incoming change by hand, save real work elsewhere first, and move aside an untracked file in the way.' \
                "$name" "$remote" "$path" "$bead" "$name" "$restore_cmd") ;;
        *)
            msg=$(printf 'rigs/%s cannot fast-forward to %s: its live checkout holds commits that %s does not, and its deploy is stalled.\nPath: %s\nSubject bead %s names what git refused and the steps to reset by hand, carries the full git status and divergence log, and clears when rigs/%s next fast-forwards cleanly.\nTo reset by hand: save real work elsewhere, restore each stray write, and move aside each untracked file in the way. Then run %s, which refuses rather than overwrites or deletes a local change or an untracked file still in its way, an ignored file included.' \
                "$name" "$remote" "$remote" "$path" "$bead" "$name" "$reset_cmd") ;;
    esac
    if ! gate_divergence "$bead" "reconcile-diverged-$name" "$msg"; then
        warn "rigs/$name stall could NOT be put to a person (human-gate.sh failed) — subject bead $bead"
    fi
done <<< "$rigs"

echo "reconcile-rig-checkouts: $advanced advanced, $blocked blocked"
