#!/usr/bin/env bash
# reconcile-rig-checkouts — keep the live rigs/* checkouts advanced to origin.
#
# The live rigs/* checkouts are what the runtime executes (pack
# source = "rigs/<rig>"); the refinery merges PRs via its own clone, so a
# merged PR is NOT live until the checkout syncs. For each rig this does
# `git fetch origin && git merge --ff-only origin/<default>`.
#
# --ff-only advances only on a clean fast-forward, keeps a dirty file the
# incoming commits do not touch, and refuses, mutating nothing, on a divergence
# or on a local change to a path the incoming commits rewrite. A refusal on a
# checkout that is only behind gets the set-aside heal, and one on a diverged
# checkout gets the reset heal. Each acts only on what it can prove loses
# nothing, and what neither heals escalates.
#
# The rig root must also stay ON the default branch: it is a deploy mirror, and a
# HEAD parked elsewhere (detached, or a feature/integration branch an agent
# checked out and left) never fast-forwards and serves an off-default build to
# directory-imported packs. ff-only cannot see that — a checkout ahead of the
# default reports "Already up to date" and looks advanced — so this checks the
# local branch first and surfaces a parked checkout through the same subject bead
# and escalation, mutating nothing.
#
# A checkout that is only behind its remote (HEAD is an ancestor of it) is
# almost always refused over local changes on the paths the fast-forward
# rewrites. Commits are never authored here, so such a change is machine-local
# config or a stray write: an agent's git verb or file write aimed at this
# checkout. `git -C <rig> --work-tree=<dir> checkout <rev> -- <path>`, for one,
# writes the file into <dir> but stages it in this checkout's index. Neither git
# nor the file system runs a hook that could refuse such a write before it
# lands, so the writer cannot be stopped where it acts, and this pass clears
# what it leaves. It sets the blocking paths aside and fast-forwards only when
# each of them passes:
#   - its working copy is absent, equals HEAD, equals the remote, or matches a
#     blob in a remote-tracking ref's history. Any other working copy may be
#     machine-local config or real work, so the pass escalates instead;
#   - it has no unmerged entry.
# An unignored untracked file on a path the fast-forward adds blocks it too.
# One that already holds the bytes the remote adds there is removed before the
# retry, because the fast-forward writes the same content back; any other
# escalates.
# A staged change needs no proof of its own: a directory-imported pack runs from
# the working tree, so the index holds nothing the runtime executes. Before a
# tracked path moves, `git stash create` pins the staged and working-tree state
# of every dirty tracked path in one commit, under
# refs/gc-toolkit/reconcile-set-aside/<UTC time> rather than on the stash stack
# that other sessions share. Only then are the blocking paths restored to HEAD
# and the fast-forward retried. A dirty path the fast-forward does not rewrite,
# such as local bd config, stays as it is. Recover a path with
# `git checkout <ref> -- <path>` for its working copy, or
# `git checkout <ref>^2 -- <path>` for its staged copy.
#
# A checkout that has diverged is almost always SHA churn from an upstream
# rebase/squash/force-push: the live rigs/* checkout is a pure deployment mirror
# (commits are authored in worktrees and the refinery clone, never here), so its
# tracked content is already fully represented in origin. That case is provably
# lossless to reset, so the refusal branch tries to auto-heal it. The reset runs
# only when every check holds, and fails closed (escalates, mutates nothing) on
# anything it cannot prove:
#   - git cherry (patch-id) finds no unique local commit, so a rebased or
#     squashed commit with a new SHA still matches;
#   - git rev-list --merges finds no merge commit unique to local — git cherry
#     ignores merges, so a local merge's tree content is not provably upstream
#     and the guard refuses rather than reset it away;
#   - git status --porcelain is readable (a failed read is not proof of a clean
#     tree), and no dirty tracked path carries local-only content: its working
#     tree differs from the remote, or its staged index matches neither the
#     remote nor the committed HEAD;
#   - no untracked file sits on a path the remote tracks unless it already holds
#     the remote's content, because reset --hard overwrites it.
# It then resets --hard to the remote, which keeps every other untracked file,
# and closes the divergence bead.
#
# Set RECONCILE_NO_AUTOHEAL=1 to disable the set-aside and reset heals and
# escalate every refusal instead.
#
# A refusal neither heal resolves takes the exception path: one idempotent bead
# per blocked rig records why, and escalate.sh raises it so someone actually
# acts. The exception path never touches the checkout.
#
# The escalation must never rot silently, which is the whole reason this script
# exists: a stalled deploy has to reach someone. So a blocked rig is NOT handed
# to a fixed agent address — an address no agent holds is a bead nobody works,
# and a nudge into the void is worse than no safety net. The per-rig bead is the
# durable, self-healing SUBJECT: it carries the diagnosis and auto-closes when
# the rig next fast-forwards cleanly. escalate.sh then files a board-visible
# visit that tracks it. escalate.sh proves its route against the live agent set,
# exits non-zero rather than escalate into the void, and defaults to the human
# helm board, which resolves in every city. Set RECONCILE_ESCALATION_POOL to a
# rig-qualified pool to route the visit to a coordination agent instead; a pool
# that does not resolve falls back to the human board.
#
# Runs as an exec order (no LLM, no agent, no wisp).
set -euo pipefail

warn() { echo "reconcile-rig-checkouts: $*" >&2; }

SELF_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
ESCALATE_SH="${GC_RECONCILE_ESCALATE_TOOL:-$SELF_DIR/escalate.sh}"

# The store the per-rig subject bead lives in, and whose board shows the visit.
RECONCILE_RIG="${RECONCILE_BEAD_RIG:-gc-toolkit}"
# Operator knob: route the divergence visit to a coordination pool. Unset means
# escalate.sh's human helm board. RECONCILE_MAYOR_ADDR is the prior name for
# this knob and is still honored.
ESC_POOL="${RECONCILE_ESCALATION_POOL:-${RECONCILE_MAYOR_ADDR:-}}"

# id of the single open reconcile bead for a rig (empty if none).
open_bead() {
    gc bd --rig "$RECONCILE_RIG" list --metadata-field "reconcile_rig=$1" --json 2>/dev/null \
        | jq -r '.[0].id // empty' 2>/dev/null || true
}

# Raise a divergence through escalate.sh. A configured pool is tried first —
# escalate.sh proves it addresses a live agent — and anything unroutable falls
# back to the human board so the divergence still reaches someone. The exit
# status is that of the path that ran, so the caller can report a total failure.
escalate_divergence() {
    local subject="$1" key="$2" message="$3"
    if [ -n "$ESC_POOL" ]; then
        if GC_RIG="$RECONCILE_RIG" "$ESCALATE_SH" \
                --subject "$subject" --key "$key" --message "$message" --pool "$ESC_POOL"; then
            return 0
        fi
        warn "escalation pool '$ESC_POOL' did not route for $subject — falling back to the human board"
    fi
    GC_RIG="$RECONCILE_RIG" "$ESCALATE_SH" \
        --subject "$subject" --key "$key" --message "$message"
}

# Retract the tracking visit for a subject whose divergence has resolved. The
# subject bead auto-closes on a clean sync, but escalate.sh filed a board-visible
# visit routed to a human, and a human-routed visit is not auto-claimed — so a
# self-heal before the operator engages it leaves a moot visit lingering on the
# board. The subject tracks exactly this one divergence and clears only on a
# clean sync, so subject-resolved is premise-moot here: close the open visit as
# moot through the same escalate.sh that filed it (--retract folds the reading
# onto the subject and stamps gc.outcome=moot via visit-close.sh). Only an
# unengaged (open) visit is touched; one a human already claimed is theirs. A
# failure returns non-zero so the caller skips the subject close: bd list defaults
# away from closed beads and open_bead does not pass --all, so a subject closed
# after a failed retract cannot be rediscovered to retry, and its human-routed
# visit would linger. Leaving the subject open on failure is the retry handle —
# the next patrol re-finds it and retries. Called BEFORE the subject close so the
# reading folds onto the subject while it is still open.
retract_visit() {
    local subject="$1" key="$2" message="$3"
    if GC_RIG="$RECONCILE_RIG" "$ESCALATE_SH" --retract \
        --subject "$subject" --key "$key" --message "$message"; then
        return 0
    fi
    warn "could not retract the tracking visit for $subject — leaving its subject open so the next patrol retries"
    return 1
}

# A rig that advanced or healed clears its escalation: retract the tracking
# visit as moot, then close the subject. The close waits on retract_visit, so a
# failed retract leaves the subject open as the retry handle.
resolve_subject() {
    local name="$1" reading="$2" bead
    bead=$(open_bead "$name")
    [ -n "$bead" ] || return 0
    if retract_visit "$bead" "reconcile-diverged-$name" "$reading; the stall this visit tracked is resolved."; then
        gc bd --rig "$RECONCILE_RIG" close "$bead" --reason "$reading" >/dev/null 2>&1 || true
    fi
}

# 0 when the history of a remote-tracking ref holds the object. awk reads the
# whole listing, so rev-list never writes into a closed pipe.
on_pushed_ref() {
    git -C "$1" rev-list --objects --remotes 2>/dev/null \
        | awk -v want="$2" '$1 == want { found = 1 } END { exit !found }'
}

in_list() {
    local want="$1" item
    shift
    for item in "$@"; do
        [ "$item" = "$want" ] && return 0
    done
    return 1
}

# The behind-checkout heal (see the header). On success the checkout has
# fast-forwarded, and set_aside_ref names the pin when tracked paths were set
# aside. On failure blocking_report says what blocked it and names whatever the
# heal had already pinned, restored or removed; set_aside_ref is set once a pin
# exists.
set_aside_ref=""; blocking_report=""
set_aside_and_advance() {
    local path="$1" remote="$2" name="$3"
    local dirty incoming added p blob listed="" gone="" stuck="" moved="" msg pin ref unsafe=0
    local -a dirty_paths=() blocking=() in_way=()
    set_aside_ref=""; blocking_report=""
    # Tracked paths whose working tree or index differs from HEAD. git quotes a
    # name holding a control character, a double quote or a backslash, and a
    # quoted name is no usable pathspec, so it fails the proof.
    dirty=$(git -C "$path" -c core.quotepath=false diff --name-only --no-renames HEAD 2>/dev/null \
        && git -C "$path" -c core.quotepath=false diff --cached --name-only --no-renames HEAD 2>/dev/null) \
        || { blocking_report="could not list the checkout's local changes"; return 1; }
    while IFS= read -r p; do
        [ -n "$p" ] || continue
        case "$p" in \"*) blocking_report="a changed path has a name git quotes: $p"; return 1 ;; esac
        dirty_paths+=("$p")
    done <<< "$dirty"
    if [ "${#dirty_paths[@]}" -gt 0 ]; then
        incoming=$(git --literal-pathspecs -C "$path" -c core.quotepath=false \
            diff --name-only --no-renames HEAD "$remote" -- "${dirty_paths[@]}" 2>/dev/null) \
            || { blocking_report="could not list the paths the fast-forward rewrites"; return 1; }
        while IFS= read -r p; do
            [ -n "$p" ] || continue
            blocking+=("$p")
        done <<< "$incoming"
    fi
    # An untracked file on a path the fast-forward adds blocks it too. git
    # overwrites an ignored one, so only an unignored file counts. A regular
    # file holding the remote's blob for its path can go, since the
    # fast-forward writes those bytes back.
    added=$(git -C "$path" -c core.quotepath=false diff --name-only --no-renames --diff-filter=A HEAD "$remote" 2>/dev/null) \
        || { blocking_report="could not list the paths the fast-forward adds"; return 1; }
    while IFS= read -r p; do
        [ -n "$p" ] || continue
        [ -e "$path/$p" ] || [ -L "$path/$p" ] || continue
        in_list "$p" ${dirty_paths[@]+"${dirty_paths[@]}"} && continue
        git --literal-pathspecs -C "$path" check-ignore -q -- "$p" 2>/dev/null && continue
        if [ -f "$path/$p" ] && [ ! -L "$path/$p" ] \
           && blob=$(git -C "$path" hash-object -- "$p" 2>/dev/null) \
           && [ "$blob" = "$(git -C "$path" rev-parse -q --verify "$remote:$p" 2>/dev/null)" ]; then
            in_way+=("$p")
        else
            blocking_report+="untracked file in the way: $p (it holds other content than $remote adds there)"$'\n'
            unsafe=1
        fi
    done <<< "$added"
    if [ "${#blocking[@]}" -eq 0 ] && [ "${#in_way[@]}" -eq 0 ] && [ "$unsafe" -eq 0 ]; then
        blocking_report="no local change sits on a path the fast-forward rewrites"
        return 1
    fi
    for p in ${blocking[@]+"${blocking[@]}"}; do
        listed="${listed:+$listed, }$p"
        if [ -n "$(git --literal-pathspecs -C "$path" ls-files -u -- "$p" 2>/dev/null)" ]; then
            blocking_report+="unmerged: $p"$'\n'
            unsafe=1
        elif { [ ! -e "$path/$p" ] && [ ! -L "$path/$p" ]; } \
             || git --literal-pathspecs -C "$path" diff --quiet HEAD -- "$p" 2>/dev/null \
             || git --literal-pathspecs -C "$path" diff --quiet "$remote" -- "$p" 2>/dev/null; then
            :   # the working copy is absent, committed, or what the fast-forward writes
        elif [ -f "$path/$p" ] && [ ! -L "$path/$p" ] \
             && blob=$(git -C "$path" hash-object -- "$p" 2>/dev/null) \
             && on_pushed_ref "$path" "$blob"; then
            :   # the working copy matches content a pushed branch carries
        else
            blocking_report+="local-only content: $p (its working copy matches neither HEAD, $remote nor any pushed branch)"$'\n'
            unsafe=1
        fi
    done
    [ "$unsafe" -eq 0 ] || return 1
    if [ "${#blocking[@]}" -gt 0 ]; then
        msg="reconcile-rig-checkouts set aside $listed so rigs/$name could fast-forward to $remote. This commit's tree holds each dirty path's working copy and its second parent the staged copy."
        ref="refs/gc-toolkit/reconcile-set-aside/$(date -u +%Y%m%dT%H%M%SZ)"
        pin=$(GIT_AUTHOR_NAME=reconcile-rig-checkouts GIT_AUTHOR_EMAIL=reconcile-rig-checkouts@localhost \
            GIT_COMMITTER_NAME=reconcile-rig-checkouts GIT_COMMITTER_EMAIL=reconcile-rig-checkouts@localhost \
            git -C "$path" stash create "$msg" 2>/dev/null) && [ -n "$pin" ] \
            || { blocking_report="could not pin the local changes on $listed"; return 1; }
        # An empty old value makes the ref create-only, so no earlier pin is replaced.
        git -C "$path" update-ref -m "$msg" "$ref" "$pin" "" 2>/dev/null \
            || { blocking_report="could not record the pin of $listed at $ref"; return 1; }
        set_aside_ref="$ref"
        if ! git --literal-pathspecs -C "$path" restore --source=HEAD --staged --worktree -- "${blocking[@]}" 2>/dev/null; then
            blocking_report="could not restore $listed to HEAD after pinning them"
            return 1
        fi
        moved="restoring $listed to HEAD"
    fi
    for p in ${in_way[@]+"${in_way[@]}"}; do
        if ! rm -f -- "$path/$p"; then
            stuck="$p"
            break
        fi
        gone="${gone:+$gone, }$p"
    done
    [ -z "$gone" ] || moved="${moved:+$moved and }removing the untracked $gone, which held $remote's content"
    if [ -n "$stuck" ]; then
        blocking_report="could not remove the untracked $stuck${moved:+ after $moved}"
        return 1
    fi
    if ! git -C "$path" merge --ff-only "$remote" >/dev/null 2>&1; then
        blocking_report="the fast-forward still refused after $moved"
        return 1
    fi
}

advanced=0; healed=0; blocked=0
rigs=$(gc rig list --json 2>/dev/null | jq -r '.rigs[] | select(.hq != true) | "\(.name)\t\(.path)"') || exit 0

while IFS=$'\t' read -r name path; do
    [ -n "${name:-}" ] && [ -d "$path/.git" ] || continue
    git -C "$path" fetch origin --quiet 2>/dev/null || continue
    remote=$(git -C "$path" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || echo origin/main)
    default_branch="${remote#origin/}"

    # The rig root is a deploy mirror: it sits ON the default branch and only
    # fast-forwards. A HEAD parked elsewhere — detached, or a feature/integration
    # branch an agent checked out and left — never advances, and its working tree
    # serves an off-default build a directory-imported pack then compiles. ff-only
    # cannot see this: a checkout ahead of the default reports "Already up to
    # date" and counts as advanced. Detect the parked state before the ff attempt
    # and route it through the same subject bead; skip the ff and the auto-heal,
    # which would act on the wrong branch.
    local_branch=$(git -C "$path" symbolic-ref --short HEAD 2>/dev/null || true)
    parked=""
    [ "$local_branch" = "$default_branch" ] || parked="HEAD is on ${local_branch:-<detached HEAD>}, not $default_branch"

    if [ -z "$parked" ] && git -C "$path" merge --ff-only "$remote" >/dev/null 2>&1; then
        # Advanced or already up to date: clear any lingering escalation.
        advanced=$((advanced + 1))
        resolve_subject "$name" "rigs/$name fast-forwarded cleanly to $remote"
        continue
    fi

    # ff-only refused, or the HEAD is parked. A checkout that is only behind its
    # remote takes the set-aside heal; a diverged one takes the guarded reset
    # below. Neither runs on a parked HEAD, where it would act on the wrong
    # branch, or under RECONCILE_NO_AUTOHEAL=1.
    behind=""
    if [ -z "$parked" ] && git -C "$path" merge-base --is-ancestor HEAD "$remote" 2>/dev/null; then
        behind=1
    fi
    set_aside_ref=""; blocking_report=""
    if [ -n "$behind" ] && [ "${RECONCILE_NO_AUTOHEAL:-0}" != "1" ] \
       && set_aside_and_advance "$path" "$remote" "$name"; then
        healed=$((healed + 1))
        resolve_subject "$name" "rigs/$name auto-healed: set aside the local changes blocking its fast-forward${set_aside_ref:+ (pinned at $set_aside_ref)}, then fast-forwarded to $remote"
        continue
    fi

    # A diverged checkout is almost always SHA churn from an upstream
    # rebase/squash/force-push, with its content already upstream. reset --hard
    # is lossless only when the guard proves it: git cherry (patch-id) finds no
    # unique local commit, no merge commit is unique to local (git cherry ignores
    # merges, so a local merge's tree content is not provably upstream), the
    # status read succeeds, no dirty tracked path carries local-only content (a
    # working tree that differs from the remote, or a staged index matching
    # neither remote nor HEAD), and no untracked file on a path the remote tracks
    # holds other content. Anything the guard cannot prove — a real divergence,
    # an unreadable status, a local merge — falls through to the escalation path
    # unchanged.
    if [ -z "$parked" ] && [ -z "$behind" ] \
       && [ "${RECONCILE_NO_AUTOHEAL:-0}" != "1" ] \
       && cherry_out=$(git -C "$path" cherry "$remote" HEAD 2>/dev/null) \
       && [ -z "$(printf '%s' "$cherry_out" | grep '^+' || true)" ] \
       && merges=$(git -C "$path" rev-list --merges "$remote"..HEAD 2>/dev/null) \
       && [ -z "$merges" ] \
       && status_out=$(git -C "$path" -c core.quotepath=false status --porcelain 2>/dev/null); then
        unique_local=0
        while IFS= read -r changed; do
            [ -n "$changed" ] || continue
            # reset --hard overwrites both the working tree and the staged index
            # for this path, so neither may carry content the reset would lose.
            # Working tree: safe only when it already equals the remote (the
            # regenerated-to-upstream case). Index: safe when it equals the remote,
            # or equals HEAD — committed content, proven upstream by the cherry
            # check above. Content staged but never committed (differs from both
            # HEAD and the remote) is discarded with no way back, even when an
            # upstream-matching worktree copy hides it from a diff against remote.
            if ! git -C "$path" diff --quiet "$remote" -- "$changed" 2>/dev/null; then
                unique_local=$((unique_local + 1))
            elif ! git -C "$path" diff --cached --quiet "$remote" -- "$changed" 2>/dev/null \
                 && ! git -C "$path" diff --cached --quiet HEAD -- "$changed" 2>/dev/null; then
                unique_local=$((unique_local + 1))
            fi
        done < <(printf '%s\n' "$status_out" | grep -v '^??' | sed -E 's/^.{3}//; s/^.* -> //')
        # reset --hard also writes every path the remote tracks, so an untracked
        # file on one is overwritten: safe only when it already holds the
        # remote's content. A name git quotes cannot be looked up, so it counts.
        while IFS= read -r untracked; do
            [ -n "$untracked" ] || continue
            case "$untracked" in \"*) unique_local=$((unique_local + 1)); continue ;; esac
            remote_blob=$(git -C "$path" rev-parse -q --verify "$remote:$untracked" 2>/dev/null) || continue
            [ "$(git -C "$path" hash-object -- "$untracked" 2>/dev/null)" = "$remote_blob" ] \
                || unique_local=$((unique_local + 1))
        done < <(printf '%s\n' "$status_out" | sed -n 's/^?? //p')
        if [ "$unique_local" -eq 0 ] && git -C "$path" reset --hard "$remote" >/dev/null 2>&1; then
            healed=$((healed + 1))
            resolve_subject "$name" "rigs/$name auto-healed: already-upstream, reset --hard to $remote"
            continue
        fi
    fi

    # Reached three ways: the HEAD is parked off the default branch, a behind
    # checkout's blocking changes could not all be set aside, or a divergence
    # the guard could not prove lossless. File the subject bead and escalate.
    blocked=$((blocked + 1))
    if [ -n "$parked" ]; then
        body=$(printf 'rigs/%s is parked off %s — its live checkout HEAD is on %s.\nPath: %s\n\nThe rig root is a deploy mirror: reconcile fast-forwards it to %s and\ndirectory-imported packs build from its working tree, so nothing checks out a\nbranch or commits there. Restore it once any local work is saved elsewhere:\n  git -C %s checkout %s\nIt auto-closes when the rig next fast-forwards cleanly.\n\n## git status --porcelain\n%s\n\n## git log --oneline %s..HEAD\n%s\n' \
            "$name" "$default_branch" "${local_branch:-<detached HEAD>}" "$path" \
            "$default_branch" "$path" "$default_branch" \
            "$(git -C "$path" status --porcelain 2>/dev/null)" \
            "$remote" "$(git -C "$path" log --oneline "$remote"..HEAD 2>/dev/null)")
    elif [ -n "$behind" ]; then
        nl=$'\n'
        report="${blocking_report%"$nl"}"
        [ -n "$report" ] || report="not examined: RECONCILE_NO_AUTOHEAL=1 turns the heals off"
        pinned=""
        [ -z "$set_aside_ref" ] || pinned=$(printf 'The blocking paths were pinned at %s and restored to HEAD.\nRecover a path with git checkout %s -- <path> (working copy)\nor git checkout %s^2 -- <path> (staged copy).\n\n' \
            "$set_aside_ref" "$set_aside_ref" "$set_aside_ref")
        body=$(printf 'rigs/%s could not fast-forward to %s — local changes in the live checkout\nsit on paths the incoming commits rewrite, and not all of them could be set\naside without losing content.\nPath: %s\n\n## Blocking the fast-forward\n%s\n\n%sJudge and act, then close this bead (it auto-closes when the rig next\nff-s cleanly): stray write -> git -C %s restore --source=HEAD --staged --worktree -- <path>;\nmachine-local config -> carry it across the incoming change by hand;\nreal work -> save it elsewhere first.\n\n## git status --porcelain\n%s\n' \
            "$name" "$remote" "$path" "$report" "$pinned" "$path" \
            "$(git -C "$path" status --porcelain 2>/dev/null)")
    else
        body=$(printf 'rigs/%s could not fast-forward to %s — the live checkout diverged.\nPath: %s\n\nJudge and act, then close this bead (it auto-closes when the rig next\nff-s cleanly): already-upstream -> git -C %s reset --hard %s; machine-local\nconfig -> leave it; real work -> handle it.\n\n## git status --porcelain\n%s\n\n## git log --oneline %s..HEAD\n%s\n' \
            "$name" "$remote" "$path" "$path" "$remote" \
            "$(git -C "$path" status --porcelain 2>/dev/null)" \
            "$remote" "$(git -C "$path" log --oneline "$remote"..HEAD 2>/dev/null)")
    fi

    bead=$(open_bead "$name")
    if [ -n "$bead" ]; then
        gc bd --rig "$RECONCILE_RIG" update "$bead" --description "$body" >/dev/null 2>&1 || true
    else
        bead=$(gc bd --rig "$RECONCILE_RIG" create "Reconcile: rigs/$name cannot fast-forward to $remote" \
            -t task -d "$body" --json 2>/dev/null | jq -r '.id // empty' 2>/dev/null || true)
        [ -n "$bead" ] || { warn "could not file a reconcile bead for rigs/$name — divergence UNTRACKED and UNESCALATED"; continue; }
        gc bd --rig "$RECONCILE_RIG" update "$bead" --set-metadata reconcile_rig="$name" >/dev/null 2>&1 || true
    fi

    # Make someone hear about it. A failure here is reported, never swallowed —
    # an unescalated divergence is the exact silent rot this script prevents.
    if [ -n "$parked" ]; then
        msg=$(printf 'rigs/%s is parked off its deploy branch %s — HEAD is on %s, so reconcile cannot advance it and its working tree serves an off-%s build to every directory-imported pack.\nPath: %s\nSubject bead %s carries the full git status and log, and clears when rigs/%s next fast-forwards cleanly.\nRestore it: save any local work elsewhere, then git -C %s checkout %s.' \
            "$name" "$default_branch" "${local_branch:-<detached HEAD>}" "$default_branch" "$path" "$bead" "$name" "$path" "$default_branch")
    elif [ -n "$behind" ]; then
        msg=$(printf 'rigs/%s cannot fast-forward to %s — local changes in its live checkout sit on paths the incoming commits rewrite, and its deploy is stalled.\nPath: %s\nSubject bead %s names the blocking paths and carries the full git status, and clears when rigs/%s next ff-s cleanly.\nstray write -> git -C %s restore --source=HEAD --staged --worktree -- <path>; machine-local config -> carry it across the incoming change by hand; real work -> save it elsewhere first.' \
            "$name" "$remote" "$path" "$bead" "$name" "$path")
    else
        msg=$(printf 'rigs/%s cannot fast-forward to %s — its live checkout diverged and its deploy is stalled.\nPath: %s\nSubject bead %s carries the full git status and divergence log, and clears when rigs/%s next ff-s cleanly.\nalready-upstream -> git -C %s reset --hard %s; machine-local config -> leave it; real work -> handle it.' \
            "$name" "$remote" "$path" "$bead" "$name" "$path" "$remote")
    fi
    if ! escalate_divergence "$bead" "reconcile-diverged-$name" "$msg"; then
        warn "rigs/$name divergence could NOT be escalated (escalate.sh failed) — subject bead $bead"
    fi
done <<< "$rigs"

echo "reconcile-rig-checkouts: $advanced advanced, $healed auto-healed, $blocked blocked"
