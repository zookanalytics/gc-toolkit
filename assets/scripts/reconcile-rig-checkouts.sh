#!/usr/bin/env bash
# reconcile-rig-checkouts — keep the live rigs/* checkouts advanced to origin.
#
# The live rigs/* checkouts are what the runtime executes (pack
# source = "rigs/<rig>"); the refinery merges PRs via its own clone, so a
# merged PR is NOT live until the checkout syncs. For each rig this does
# `git fetch origin && git merge --ff-only --no-overwrite-ignore origin/<default>`.
#
# --ff-only advances only on a clean fast-forward, keeps a dirty file the
# incoming commits do not touch, and refuses, mutating nothing, on a divergence,
# on a local change to a path the incoming commits rewrite, or on untracked
# content in the way of what they write. --no-overwrite-ignore makes that
# include an ignored file, which git otherwise overwrites. A refusal on a
# checkout that is only behind gets the set-aside heal, and one on a diverged
# checkout gets the reset heal. A checkout that is only behind also keeps in
# place each file the incoming commits stop tracking while the remote's tree
# ignores it, where the fast-forward would delete it. Each acts only on what it
# can prove loses nothing, and what none of them heals takes the exception path.
#
# The rig root must also stay ON the default branch: it is a deploy mirror, and a
# HEAD parked elsewhere (detached, or a feature/integration branch an agent
# checked out and left) never fast-forwards and serves an off-default build to
# directory-imported packs. ff-only cannot see that — a checkout ahead of the
# default reports "Already up to date" and looks advanced — so this checks the
# local branch first and surfaces a parked checkout through the same subject bead
# and human gate, mutating nothing.
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
#     machine-local config or real work, so the pass takes the exception path
#     instead;
#   - it has no unmerged entry.
# Untracked content in the way of what the fast-forward writes blocks it too: a
# file on a path it writes, a file where it writes a directory, and anything
# under a directory it replaces with a file. A regular file that already holds
# the bytes written on its own path is removed before the retry, because the
# fast-forward writes the same content back; anything else takes the exception
# path. git's own
# listing says what is untracked, and nothing behind a symlink is touched. An
# ignored file counts like any other: a rig ignores machine-local state, such as
# its bd config and credentials, so being ignored proves nothing expendable.
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
# An incoming commit that deletes a tracked path while the remote's tree
# ignores it turns that path into machine-local state, such as the bd config
# gascity rewrites, which the runtime reads from the working tree. The
# fast-forward would delete the file, or refuse over a modified copy, so a
# checkout that is only behind keeps it in place untracked instead. A path is
# kept when:
#   - HEAD tracks it as a regular file, and the incoming commits delete it and
#     leave nothing at or under it and no file above it;
#   - the .gitignore files of the remote's tree ignore it. Only the remote's
#     tree says the path is local state now, so a machine-local exclude rule
#     does not count;
#   - its working copy is a regular file with no symlink above it, and its
#     staged copy is HEAD's or none.
# A modified copy is pinned with the rest. git refuses to fast-forward past the
# deletion while a file sits on the path, unless it may overwrite ignored
# files, which no move here allows. So each kept copy waits under
# .git/gc-toolkit-reconcile-kept while git fast-forwards, and the path holds no
# file for that long. The copy then goes back on its path with its bytes
# unchanged. It never goes over a file written there meanwhile, or through a
# symlink above the path. When a regular file reached through no symlink
# already holds the same bytes there, the copy goes instead, as long as
# removing it leaves those bytes on the path. A pass interrupted in that
# window leaves the copy there, and the next pass puts it back before it
# fetches, since that needs no network. A copy that cannot go back stays there.
# Once its fast-forward has landed, HEAD no longer tracks its path, so no later
# keep finds it. While any copy waits there, the rig takes the exception path
# whatever its fast-forward did, and its gate is withdrawn only once none does.
#
# A checkout that has diverged is almost always SHA churn from an upstream
# rebase/squash/force-push: the live rigs/* checkout is a pure deployment mirror
# (commits are authored in worktrees and the refinery clone, never here), so its
# tracked content is already fully represented in origin. That case is provably
# lossless to reset, so the refusal branch tries to auto-heal it. The reset runs
# only when every check holds, and a check that does not hold takes the
# exception path with nothing touched:
#   - git cherry (patch-id) finds no unique local commit, so a rebased or
#     squashed commit with a new SHA still matches;
#   - git log --merges finds no merge commit unique to local — git cherry
#     ignores merges, so a local merge's tree content is not provably upstream
#     and the guard refuses rather than reset it away;
#   - git status --porcelain is readable (a failed read is not proof of a clean
#     tree), and no dirty tracked path carries local-only content: its working
#     tree differs from the remote, or its staged index matches neither the
#     remote nor the committed HEAD;
#   - nothing untracked is in the way of the remote's tree, judged as for the
#     fast-forward above, except a regular file that already holds the remote's
#     bytes on its own path.
# It then removes those copies, stages each dirty path whose index still holds
# HEAD, and moves the branch to the remote as a reset does, with
# `git checkout --no-overwrite-ignore --no-track -B <default> <remote>`. That
# runs with the rig's hooks off and leaves the branch's upstream config as it
# is. git refuses, rather than overwrites or deletes, anything untracked in its
# way, an ignored file included, where git reset --keep would overwrite the
# ignored file. It also refuses rather than discards a staged change on a path
# it moves, and keeps one on a path it does not. An untracked collision the
# checks above cannot see, such as a name that differs only in case on a file
# system that ignores case, therefore takes the exception path instead of
# losing content. The
# report carries each error git gave, with the paths git named, and what the
# heal had staged and removed. Every other untracked file stays, and the
# divergence bead closes.
#
# When the reset heal stops, its human gate names what stopped it, a line for
# each finding. It also names what the heal would have staged or removed itself,
# the dirty paths and untracked files that already hold the remote's content,
# because a reset by hand must clear them too. A person who resets by hand saves
# real work elsewhere, restores each dirty path that is already upstream or a
# stray write, and moves aside each untracked file in the way. Then
# `git checkout --no-overwrite-ignore -B <default> <remote>` resets the
# checkout. Like the heal's own checkout, it refuses rather than loses a local
# change or an untracked file their judgment missed. A local commit does not
# stop it, so saving real work comes first.
#
# Set RECONCILE_NO_AUTOHEAL=1 to turn off the set-aside heal, the keep and the
# reset heal. The fast-forward then runs as plain git, which deletes a file the
# incoming commits stop tracking, and every refusal takes the exception path.
#
# What no heal resolves takes the exception path: one idempotent bead per
# blocked rig records why, and a human gate on it asks someone to act.
# That includes a failed read of which paths to keep, since the fast-forward
# could then delete one, and a kept copy that could not go back on its path.
# The exception path never touches the checkout.
#
# The exception must never rot silently, which is the whole reason this script
# exists: a stalled deploy has to reach someone. So a blocked rig is NOT handed
# to a fixed agent address — an address no agent holds is a bead nobody works,
# and a nudge into the void is worse than no safety net. The per-rig bead is the
# durable, self-healing SUBJECT: it carries the diagnosis and auto-closes when
# the rig next fast-forwards cleanly with no kept copy waiting aside.
# human-gate.sh files a human gate that blocks it, which the helm board shows
# to the operator, and exits non-zero when it files nothing.
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
# Where a kept path's working copy waits, under the checkout's .git directory,
# while git fast-forwards: on the checkout's file system and out of git's sight.
KEPT_DIR=".git/gc-toolkit-reconcile-kept"

# id of the single open reconcile bead for a rig (empty if none).
open_bead() {
    gc bd --rig "$RECONCILE_RIG" list --metadata-field "reconcile_rig=$1" --json 2>/dev/null \
        | jq -r '.[0].id // empty' 2>/dev/null || true
}

# File a divergence as a human gate that blocks its subject bead. The exit status
# is human-gate.sh's, so the caller can report a total failure.
gate_divergence() {
    local subject="$1" key="$2" message="$3"
    "$HUMAN_GATE_SH" --subject "$subject" --key "$key" --quiet-window "$QUIET_WINDOW" \
        --message "$message" >/dev/null
}

# Withdraw the gate on a subject whose divergence has resolved. The subject bead
# auto-closes on a clean sync, and its gate blocks that close until it is
# cleared, so a self-heal before the operator answers would otherwise leave a
# moot gate on the board and the subject open behind it. The subject tracks
# exactly this one divergence and clears only on a clean sync, so
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

# A rig that advanced or healed, with no kept copy waiting aside, clears its
# exception: withdraw the gate as moot, then close the subject. The close waits
# on retract_gate, so a failed withdrawal leaves the subject open as the retry
# handle.
resolve_subject() {
    local name="$1" reading="$2" bead
    bead=$(open_bead "$name")
    [ -n "$bead" ] || return 0
    if retract_gate "$bead" "reconcile-diverged-$name" "$reading; the stall this gate asked about is resolved."; then
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

# Prints each untracked entry of the checkout at $1, ignored or not, that
# writing a tree would overwrite or delete, as "same<TAB><path>" or
# "other<TAB><path>".
# The tree written is all of $2, as a reset writes it, or with $3 only what $2
# changes from $3, as a fast-forward from $3 writes it. An entry is in the way
# when a file is written on its path or on a directory above it, or when a
# directory is written where it is a file. "same" is a regular file on a path
# where a regular file is written, already holding that file's bytes, so
# writing over it loses nothing. git lists untracked files one by one and never
# behind a symlink. It lists a nested repository, which it does not enter, as
# one entry ending in "/", which is in the way of anything written on or under
# its path. A name git quotes keeps its quoted form, which the tree listing
# quotes the same way, but it cannot be hashed, so it is never "same".
untracked_in_way() {
    local path="$1" to="$2" from="${3:-}" written untracked kind blob p
    if [ -n "$from" ]; then
        written=$(git -C "$path" -c core.quotepath=false diff-tree -r -t "$from" "$to" 2>/dev/null) || return 1
    else
        written=$(git -C "$path" -c core.quotepath=false ls-tree -r -t --full-tree "$to" 2>/dev/null) || return 1
    fi
    # No exclude rules, so the listing holds the ignored files too.
    untracked=$(git -C "$path" -c core.quotepath=false ls-files --others 2>/dev/null) || return 1
    [ -n "$untracked" ] || return 0
    while IFS=$'\t' read -r kind blob p; do
        if [ "$kind" = file ] && [ -f "$path/$p" ] && [ ! -L "$path/$p" ] \
           && [ "$(git -C "$path" hash-object -- "$p" 2>/dev/null)" = "$blob" ]; then
            printf 'same\t%s\n' "$p"
        else
            printf 'other\t%s\n' "$p"
        fi
    done < <(printf '%s\n\n%s\n' "$written" "$untracked" | awk '
        BEGIN { FS = "\t" }
        # Unquoted, a path git lists holds no double quote or backslash, so the
        # inside of a quoted one is a key no unquoted path shares, and "/" still
        # separates its components.
        function key(s) { return (substr(s, 1, 1) == "\"") ? substr(s, 2, length(s) - 2) : s }
        !listed && $0 == "" { listed = 1; next }
        !listed {
            split($1, f, " ")
            if (substr(f[1], 1, 1) == ":") {
                # diff-tree. A path the change deletes is not written.
                if (f[2] == "000000") next
                mode = f[2]; oid = f[4]
            } else {
                mode = f[1]; oid = f[3]
            }
            k = key($2)
            if (mode == "040000") kind[k] = "dir"
            else if (mode == "100644" || mode == "100755") kind[k] = "file"
            else kind[k] = "other"
            sha[k] = oid
            next
        }
        $0 == "" { next }
        {
            k = key($0); nested = 0
            if (substr(k, length(k)) == "/") { nested = 1; k = substr(k, 1, length(k) - 1) }
            n = split(k, part, "/"); up = ""
            for (i = 1; i < n; i++) {
                up = (i == 1) ? part[1] : (up "/" part[i])
                if ((up in kind) && kind[up] != "dir") { print "other\t-\t" $0; next }
            }
            if (!(k in kind)) next
            if (!nested && substr($0, 1, 1) != "\"" && kind[k] == "file") print "file\t" sha[k] "\t" $0
            else print "other\t-\t" $0
        }')
}

# Adds to blocking_report the line for the untracked entry $2 of the checkout
# at $1, which is in the way of the $3 and is no copy of what $4 holds there. It
# names an ignored file as ignored, since git status does not list one.
report_in_way() {
    if git -C "$1" check-ignore -q -- "$2" 2>/dev/null; then
        blocking_report+="ignored and in the way: $2 (git status does not list it, the $3 would write over or remove it, and it is no copy of what $4 holds there)"$'\n'
    else
        blocking_report+="untracked in the way: $2 (the $3 would write over or remove it, and it is no copy of what $4 holds there)"$'\n'
    fi
}

# The paths of the checkout at $1 that a fast-forward to $2 keeps in place
# untracked (see the header), in kept[]. A name git quotes is no usable
# pathspec, so it is never kept. The .gitignore files of the remote's tree are
# read into a scratch repository with no exclude file, and global excludes are
# off, so they alone decide what is ignored. A read that fails returns 1 with
# kept_report saying what failed, since the fast-forward could then delete a
# file that qualifies.
kept=(); kept_report=""
kept_paths() {
    local path="$1" remote="$2" deleted line mode p rest a ok scratch d entry oid ignored="" rc=0
    local -a cand=() dirs=() ign=()
    kept=(); kept_report=""
    deleted=$(git -C "$path" -c core.quotepath=false diff-tree -r --no-renames --diff-filter=D HEAD "$remote" 2>/dev/null) \
        || { kept_report="could not list the paths the incoming commits delete"; return 1; }
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        mode="${line#:}"; mode="${mode%% *}"; p="${line#*$'\t'}"
        case "$mode" in 100644|100755) ;; *) continue ;; esac
        case "$p" in \"*) continue ;; esac
        [ -f "$path/$p" ] && [ ! -L "$path/$p" ] || continue
        git -C "$path" cat-file -e "${remote}:${p}" 2>/dev/null && continue
        ok=1; rest="$p"; a=""
        while [ "${rest#*/}" != "$rest" ]; do
            a="${a:+$a/}${rest%%/*}"; rest="${rest#*/}"
            if [ -L "$path/$a" ]; then ok=""; break; fi
            case "$(git -C "$path" cat-file -t "${remote}:${a}" 2>/dev/null)" in
                ""|tree) ;;
                *) ok=""; break ;;
            esac
        done
        [ -n "$ok" ] || continue
        # A staged copy other than HEAD's is left to the set-aside's proof.
        git --literal-pathspecs -C "$path" diff --cached --quiet HEAD -- "$p" 2>/dev/null \
            || [ -z "$(git --literal-pathspecs -C "$path" ls-files -- "$p" 2>/dev/null)" ] || continue
        cand+=("$p")
    done <<< "$deleted"
    [ "${#cand[@]}" -gt 0 ] || return 0
    scratch=$(mktemp -d "${TMPDIR:-/tmp}/reconcile-rig-checkouts.XXXXXX" 2>/dev/null) \
        || { kept_report="could not make a scratch repository to read the remote's .gitignore files"; return 1; }
    git init -q --template= "$scratch" >/dev/null 2>&1 || rc=1
    for p in "${cand[@]}"; do
        [ "$rc" -eq 0 ] || break
        # The .gitignore of the top directory and of each directory above p.
        d=""; rest="$p"
        while :; do
            if ! in_list "$d" ${dirs[@]+"${dirs[@]}"}; then
                dirs+=("$d")
                entry=$(git --literal-pathspecs -C "$path" ls-tree "$remote" -- "${d}.gitignore" 2>/dev/null) || { rc=1; break; }
                case "$entry" in
                    "100644 blob "*|"100755 blob "*)
                        oid="${entry#* blob }"; oid="${oid%%$'\t'*}"
                        { mkdir -p "$scratch/$d" && git -C "$path" cat-file blob "$oid" > "$scratch/${d}.gitignore"; } 2>/dev/null \
                            || { rc=1; break; } ;;
                esac
            fi
            [ "${rest#*/}" != "$rest" ] || break
            d="$d${rest%%/*}/"; rest="${rest#*/}"
        done
    done
    if [ "$rc" -eq 0 ]; then
        # check-ignore exits 1 when it ignores none of them. It reads a path
        # that starts with a colon as pathspec magic, so each path goes in
        # behind ./, which it prints back as given.
        ignored=$(printf './%s\n' "${cand[@]}" \
            | git -C "$scratch" -c core.excludesFile=/dev/null -c core.quotepath=false check-ignore --stdin 2>/dev/null) \
            || rc=$?
        [ "$rc" -ne 1 ] || rc=0
    fi
    rm -rf "${scratch:?}"
    [ "$rc" -eq 0 ] || { kept_report="could not read whether the remote's .gitignore files ignore ${cand[*]}"; return 1; }
    while IFS= read -r p; do
        [ -n "$p" ] || continue
        ign+=("${p#./}")
    done <<< "$ignored"
    for p in "${cand[@]}"; do
        if in_list "$p" ${ign[@]+"${ign[@]}"}; then kept+=("$p"); fi
    done
    return 0
}

# Links the file at $1/$3 to $2/$3, making the directories above it, unless
# anything is on $2/$3, since ln links into a directory it is given as the
# target. Then unlinks $1/$3, so the bytes always have a name.
relink() {
    local dir="${3%/*}"
    [ "$dir" != "$3" ] || dir=""
    { [ ! -e "$2/$3" ] && [ ! -L "$2/$3" ]; } || return 1
    mkdir -p "$2/$dir" 2>/dev/null && ln -- "$1/$3" "$2/$3" 2>/dev/null && rm -f -- "${1:?}/${3:?}"
}

# Moves the working copy of $2 in the checkout at $1 aside under $KEPT_DIR,
# never over a copy already there.
move_aside() { relink "$1" "$1/$KEPT_DIR" "$2"; }

# Prints the first directory between the checkout at $1 and its path $2 that is
# a symlink, and returns 1 when none is.
symlink_above() {
    local rest="$2" a=""
    while [ "${rest#*/}" != "$rest" ]; do
        a="${a:+$a/}${rest%%/*}"; rest="${rest#*/}"
        if [ -L "$1/$a" ]; then printf '%s\n' "$a"; return 0; fi
    done
    return 1
}

# 0 when the path $2 in the checkout at $1 is the copy that waits for it under
# $KEPT_DIR: its directory is the copy's directory under another name, so the
# path reads the copy itself, and removing the copy empties the path too.
is_the_copy() {
    local dir="${2%/*}"
    [ "$dir" != "$2" ] || dir=""
    [ "$1/$KEPT_DIR/$dir" -ef "$1/$dir" ]
}

# Moves the copy of $2 that waits under $KEPT_DIR back to its path in the
# checkout at $1, never over anything now on that path and never through a
# symlink above it, which kept_paths refuses at keep time too. A regular file
# written there meanwhile that already holds the copy's bytes loses nothing to
# the copy, so the copy goes instead, unless the path is the copy itself, which
# cmp then compares with itself. A hard link to the copy is a second name, so
# its bytes stay on the path. git removes a directory the fast-forward empties,
# so the directories above it are made again.
put_back() {
    symlink_above "$1" "$2" >/dev/null && return 1
    relink "$1/$KEPT_DIR" "$1" "$2" && return 0
    [ -f "$1/$2" ] && [ ! -L "$1/$2" ] && ! is_the_copy "$1" "$2" \
        && cmp -s -- "$1/$KEPT_DIR/$2" "$1/$2" && rm -f -- "$1/${KEPT_DIR:?}/${2:?}"
}

# Puts back each copy that a pass interrupted while git fast-forwarded left
# under the checkout at $1. A copy that cannot go back stays where it is, and a
# keep of its path refuses while it waits.
restore_kept() {
    local path="$1" root="$1/$KEPT_DIR" f p
    [ -d "$root" ] || return 0
    while IFS= read -r -d '' f; do
        p="${f#"$root"/}"
        if put_back "$path" "$p"; then
            warn "put back $path/$p, which an interrupted pass had moved to $f"
        else
            warn "could not put back $path/$p, which an interrupted pass had moved to $f, so it stays there"
        fi
    done < <(find "$root" -type f -print0 2>/dev/null)
    find "$root" -depth -type d -empty -delete 2>/dev/null || true
}

# Each copy still waiting under the keep directory of the checkout at $1, a
# line each in waiting_report. A listing that fails says so, since nothing then
# proves that no copy waits.
waiting_report=""
waiting_copies() {
    local root="$1/$KEPT_DIR" listing f p link
    waiting_report=""
    [ -e "$root" ] || return 0
    listing=$(find "$root" -type f 2>/dev/null) \
        || { waiting_report="could not list the kept copies waiting under $root"$'\n'; return 0; }
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        p="${f#"$root"/}"
        if link=$(symlink_above "$1" "$p"); then
            if is_the_copy "$1" "$p"; then
                waiting_report+="$p waits at $f, and $1/$p reads this copy itself through the symlink $1/$link: deleting or moving the copy takes it from the runtime too, so remove the symlink instead, and the next pass puts the copy back"$'\n'
            else
                waiting_report+="$p waits at $f: $1/$link is a symlink, and a kept copy never goes back through one"$'\n'
            fi
        elif [ -e "$1/$p" ] || [ -L "$1/$p" ]; then
            waiting_report+="$p waits at $f: something else was written on $1/$p after it moved aside, and a kept copy never goes back over it"$'\n'
        else
            waiting_report+="$p waits at $f: it could not go back on its path"$'\n'
        fi
    done <<< "$listing"
}

# The behind-checkout heal (see the header), which also keeps the paths in
# kept[] in place. On success the checkout has fast-forwarded, set_aside_ref
# names the pin when modified tracked paths moved, and heal_reading says what
# the heal did. On failure blocking_report says what blocked it and names
# whatever the heal had already pinned, restored, removed or moved aside;
# set_aside_ref is set once a pin exists.
set_aside_ref=""; blocking_report=""; upstream_report=""; heal_reading=""
set_aside_and_advance() {
    local path="$1" remote="$2" name="$3"
    local dirty incoming in_way_out kind p blob listed="" gone="" stuck="" moved="" msg pin ref unsafe=0
    local root="$1/$KEPT_DIR" keeping="" pinning="" what advanced="" asidelist="" left="" back=""
    local -a dirty_paths=() blocking=() in_way=() aside=()
    set_aside_ref=""; blocking_report=""; heal_reading=""
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
            # A kept path stays as it is, so nothing restores it.
            in_list "$p" ${kept[@]+"${kept[@]}"} && continue
            blocking+=("$p")
        done <<< "$incoming"
    fi
    # Untracked content in the way of what the fast-forward writes blocks it too
    # (untracked_in_way). A copy of what is written on its own path can go,
    # since the fast-forward writes those bytes back. A path staged for deletion
    # is untracked to git but dirty here, so the proof below covers it.
    in_way_out=$(untracked_in_way "$path" "$remote" HEAD) \
        || { blocking_report="could not list the untracked files in the fast-forward's way"; return 1; }
    while IFS=$'\t' read -r kind p; do
        [ -n "$p" ] || continue
        in_list "$p" ${dirty_paths[@]+"${dirty_paths[@]}"} && continue
        if [ "$kind" = same ]; then
            in_way+=("$p")
        else
            report_in_way "$path" "$p" fast-forward "$remote"
            unsafe=1
        fi
    done <<< "$in_way_out"
    if [ "${#blocking[@]}" -eq 0 ] && [ "${#in_way[@]}" -eq 0 ] && [ "$unsafe" -eq 0 ] && [ "${#kept[@]}" -eq 0 ]; then
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
    # A modified kept path is pinned with the rest before it moves.
    [ "${#blocking[@]}" -eq 0 ] || pinning=1
    for p in ${kept[@]+"${kept[@]}"}; do
        keeping="${keeping:+$keeping, }$p"
        if in_list "$p" ${dirty_paths[@]+"${dirty_paths[@]}"}; then pinning=1; fi
    done
    what="${listed:+set aside $listed}"
    [ -z "$keeping" ] || what="${what:+$what and }kept $keeping in place untracked"
    if [ -n "$pinning" ]; then
        msg="reconcile-rig-checkouts $what so rigs/$name could fast-forward to $remote. This commit's tree holds each dirty path's working copy and its second parent the staged copy."
        ref="refs/gc-toolkit/reconcile-set-aside/$(date -u +%Y%m%dT%H%M%SZ)"
        pin=$(GIT_AUTHOR_NAME=reconcile-rig-checkouts GIT_AUTHOR_EMAIL=reconcile-rig-checkouts@localhost \
            GIT_COMMITTER_NAME=reconcile-rig-checkouts GIT_COMMITTER_EMAIL=reconcile-rig-checkouts@localhost \
            git -C "$path" stash create "$msg" 2>/dev/null) && [ -n "$pin" ] \
            || { blocking_report="could not pin the local changes on ${listed:-$keeping}"; return 1; }
        # An empty old value makes the ref create-only, so no earlier pin is replaced.
        git -C "$path" update-ref -m "$msg" "$ref" "$pin" "" 2>/dev/null \
            || { blocking_report="could not record the pin of ${listed:-$keeping} at $ref"; return 1; }
        set_aside_ref="$ref"
    fi
    if [ "${#blocking[@]}" -gt 0 ]; then
        # Hooks off: git restore runs the rig's post-checkout hook and exits
        # with its status, so a failing hook would report a done restore as failed.
        if ! git -c core.hooksPath=/dev/null --literal-pathspecs -C "$path" restore --source=HEAD --staged --worktree -- "${blocking[@]}" 2>/dev/null; then
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
    # Each kept copy waits under the keep directory while git fast-forwards,
    # and goes back on its path whether or not git did.
    for p in ${kept[@]+"${kept[@]}"}; do
        if ! move_aside "$path" "$p"; then
            stuck="$p"
            break
        fi
        aside+=("$p")
        asidelist="${asidelist:+$asidelist, }$p"
    done
    [ -z "$asidelist" ] || moved="${moved:+$moved and }moving $asidelist aside"
    if [ -z "$stuck" ] && git -C "$path" merge --ff-only --no-overwrite-ignore "$remote" >/dev/null 2>&1; then
        advanced=1
    fi
    for p in ${aside[@]+"${aside[@]}"}; do
        put_back "$path" "$p" || left="${left:+$left, }$p"
    done
    find "$root" -depth -type d -empty -delete 2>/dev/null || true
    # A file written on a kept path meanwhile stays where it is, and the kept
    # copy waits under the keep directory, pinned too when it was modified.
    back=""
    if [ -n "$left" ]; then
        back="; $left could not go back on its path and waits under $root"
    elif [ "${#aside[@]}" -gt 0 ]; then
        back="; each kept copy went back on its path"
    fi
    if [ -n "$stuck" ]; then
        if [ -e "$root/$stuck" ]; then
            blocking_report="could not move the working copy of $stuck aside: an earlier pass's copy of it waits at $root/$stuck"
        else
            blocking_report="could not move the working copy of $stuck aside to $root"
        fi
        blocking_report+="${moved:+, after $moved}$back"
        return 1
    fi
    if [ -z "$advanced" ]; then
        blocking_report="the fast-forward still refused after $moved$back"
        return 1
    fi
    [ -z "$left" ] || warn "rigs/$name fast-forwarded to $remote$back"
    heal_reading=""
    if [ -n "$listed" ] || [ -n "$gone" ]; then
        heal_reading="set aside the local changes blocking its fast-forward"
    fi
    [ -z "$keeping" ] || heal_reading="${heal_reading:+$heal_reading and }kept $keeping in place untracked, since $remote stops tracking them and ignores them"
    heal_reading="$heal_reading${set_aside_ref:+ (pinned at $set_aside_ref)}, then fast-forwarded to $remote"
    [ -z "$left" ] || heal_reading+="$back"
}

# The diverged-checkout heal (see the header). On success the branch $3, which
# HEAD is on, sits on the remote. On failure blocking_report says why. A check
# that does not hold leaves the checkout untouched, and the report has a line for
# each thing the checks found against the reset. upstream_report then names what
# the heal would have staged or removed before resetting, which a reset by hand
# must clear too. When git refuses the reset itself, blocking_report says so,
# carries each error git gave with the paths git named, and names what the heal
# had already staged and removed.
reset_and_advance() {
    local path="$1" remote="$2" branch="$3"
    local cherry_out merges status_out in_way_out changed kind p line err acted=""
    local -a stage=() same=()
    blocking_report=""; upstream_report=""
    # A read that fails proves nothing about the checkout, so it ends the heal.
    cherry_out=$(git -C "$path" cherry --abbrev -v "$remote" HEAD 2>/dev/null) \
        || { blocking_report="could not compare the local commits with $remote"; return 1; }
    merges=$(git -C "$path" -c log.showSignature=false log --merges --format='%h %s' "$remote"..HEAD 2>/dev/null) \
        || { blocking_report="could not list the local merge commits"; return 1; }
    status_out=$(git -C "$path" -c core.quotepath=false status --porcelain 2>/dev/null) \
        || { blocking_report="could not read git status"; return 1; }
    in_way_out=$(untracked_in_way "$path" "$remote") \
        || { blocking_report="could not list the untracked files in the reset's way"; return 1; }
    while IFS= read -r line; do
        case "$line" in "+ "*) blocking_report+="local commit not upstream: ${line#+ }"$'\n' ;; esac
    done <<< "$cherry_out"
    while IFS= read -r line; do
        [ -z "$line" ] || blocking_report+="local merge commit: $line (git cherry does not compare a merge, so nothing proves its content upstream)"$'\n'
    done <<< "$merges"
    while IFS= read -r changed; do
        [ -n "$changed" ] || continue
        # A name git quotes is no usable pathspec, so nothing about it is proven.
        case "$changed" in \"*) blocking_report+="a changed path has a name git quotes: $changed"$'\n'; continue ;; esac
        # Neither the working tree nor the staged index may carry content the
        # reset would lose. Working tree: safe only when it already equals the
        # remote (the regenerated-to-upstream case). Index: safe when it equals
        # the remote, or equals HEAD — committed content, proven upstream by the
        # cherry check above — and then the working tree is staged over it,
        # since the checkout refuses an unstaged change on a path it moves.
        # Content staged but never committed (differs from both HEAD and the
        # remote) has no way back, even when an upstream-matching worktree copy
        # hides it from a diff against remote.
        if ! git -C "$path" diff --quiet "$remote" -- "$changed" 2>/dev/null; then
            blocking_report+="local-only content: $changed (its working copy differs from $remote)"$'\n'
        elif git -C "$path" diff --cached --quiet HEAD -- "$changed" 2>/dev/null; then
            stage+=("$changed")
        elif ! git -C "$path" diff --cached --quiet "$remote" -- "$changed" 2>/dev/null; then
            blocking_report+="local-only content: $changed (its staged copy matches neither HEAD nor $remote)"$'\n'
        fi
    done < <(printf '%s\n' "$status_out" | grep -v '^??' | sed -E 's/^.{3}//; s/^.* -> //')
    while IFS=$'\t' read -r kind p; do
        case "$kind" in
            same) same+=("$p") ;;
            other) report_in_way "$path" "$p" reset "$remote" ;;
        esac
    done <<< "$in_way_out"
    if [ -n "$blocking_report" ]; then
        # The checkout refuses each of these, so a reset by hand must clear them.
        for p in ${stage[@]+"${stage[@]}"}; do
            upstream_report+="dirty, already upstream: $p (its working copy holds what $remote holds there)"$'\n'
        done
        for p in ${same[@]+"${same[@]}"}; do
            if git -C "$path" check-ignore -q -- "$p" 2>/dev/null; then
                upstream_report+="ignored, already upstream: $p (git status does not list it, and it holds what $remote holds there)"$'\n'
            else
                upstream_report+="untracked, already upstream: $p (it holds what $remote holds there)"$'\n'
            fi
        done
        return 1
    fi
    if [ "${#stage[@]}" -gt 0 ]; then
        if ! git --literal-pathspecs -C "$path" add -- "${stage[@]}" 2>/dev/null; then
            blocking_report="the reset heal could not stage ${stage[*]}"
            return 1
        fi
        acted="staged ${stage[*]}"
    fi
    for p in ${same[@]+"${same[@]}"}; do
        if ! rm -f -- "$path/$p"; then
            blocking_report="the reset heal ${acted:+$acted, then }could not remove the untracked $p"
            return 1
        fi
        acted="${acted:+$acted, }removed the untracked $p, a copy of $remote's"
    done
    # Hooks off: git checkout runs the rig's post-checkout hook and exits with
    # its status, so a failing hook would report a refusal after the branch had
    # moved. --no-track leaves the branch's upstream config as it is.
    if ! err=$(git -c core.hooksPath=/dev/null -C "$path" checkout -q --no-overwrite-ignore --no-track -B "$branch" "$remote" 2>&1); then
        # git gives an error for each kind of blocker and names each path under
        # its error on a tab-indented line. Its advice lines are about switching
        # branches, so the report leaves them out.
        blocking_report="git checkout --no-overwrite-ignore --no-track -B $branch $remote refused${acted:+ after the heal $acted}: $(printf '%s\n' "$err" | awk '/^(Please |Aborting$|hint: )/ || NF == 0 { next } { sub(/^\t/, "  "); print }')"
        return 1
    fi
}

advanced=0; healed=0; blocked=0
rigs=$(gc rig list --json 2>/dev/null | jq -r '.rigs[] | select(.hq != true) | "\(.name)\t\(.path)"') || exit 0

while IFS=$'\t' read -r name path; do
    [ -n "${name:-}" ] && [ -d "$path/.git" ] || continue
    # A kept copy an interrupted pass left aside goes back before anything
    # reads the working tree. That needs no network, so it runs before the
    # fetch, and a failed fetch does not keep the copy off its path.
    restore_kept "$path"
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

    # A checkout that is only behind its remote keeps in place each path the
    # fast-forward would delete while the remote's tree ignores it. The plain
    # fast-forward runs only when there is none and the read that finds them
    # worked, since it would delete each one.
    behind=""; kept=(); kept_report=""; kept_read=1
    if [ -z "$parked" ] && git -C "$path" merge-base --is-ancestor HEAD "$remote" 2>/dev/null; then
        behind=1
        if [ "${RECONCILE_NO_AUTOHEAL:-0}" != "1" ] && ! kept_paths "$path" "$remote"; then
            kept_read=""
        fi
    fi

    # A move that lands names itself in outcome and says what it did in reading.
    outcome=""; reading=""
    if [ -z "$parked" ] && [ -n "$kept_read" ] && [ "${#kept[@]}" -eq 0 ] \
       && git -C "$path" merge --ff-only --no-overwrite-ignore "$remote" >/dev/null 2>&1; then
        # Advanced or already up to date.
        outcome=advanced; reading="rigs/$name fast-forwarded cleanly to $remote"
    fi

    # ff-only refused or did not run, or the HEAD is parked. A checkout that is
    # only behind its remote takes the set-aside heal, which also keeps the
    # kept paths in place; a diverged one takes the guarded reset below.
    # Neither runs on a parked HEAD, where it would act on the wrong branch, or
    # under RECONCILE_NO_AUTOHEAL=1, and the set-aside does not run when the
    # kept paths could not be read.
    set_aside_ref=""; blocking_report=""; upstream_report=""; heal_reading=""
    if [ -z "$outcome" ] && [ -n "$behind" ] && [ -n "$kept_read" ] && [ "${RECONCILE_NO_AUTOHEAL:-0}" != "1" ] \
       && set_aside_and_advance "$path" "$remote" "$name"; then
        outcome=healed; reading="rigs/$name auto-healed: $heal_reading"
    fi
    [ -n "$kept_read" ] || blocking_report="$kept_report"

    # A diverged checkout is almost always SHA churn from an upstream
    # rebase/squash/force-push, with its content already upstream, and takes
    # the reset heal (see the header). Anything its checks cannot prove — a real
    # divergence, an unreadable status, a local merge, untracked content in the
    # way — falls through to the exception path untouched.
    if [ -z "$outcome" ] && [ -z "$parked" ] && [ -z "$behind" ] && [ "${RECONCILE_NO_AUTOHEAL:-0}" != "1" ] \
       && reset_and_advance "$path" "$remote" "$default_branch"; then
        outcome=healed; reading="rigs/$name auto-healed: already-upstream, reset to $remote"
    fi

    # A kept copy still waiting aside is a file the runtime reads on its path.
    # Once its fast-forward has landed, HEAD no longer tracks that path, so no
    # later keep finds it. A move that landed therefore clears a lingering
    # exception only when none waits.
    waiting_copies "$path"
    if [ -n "$outcome" ] && [ -z "$waiting_report" ]; then
        if [ "$outcome" = advanced ]; then advanced=$((advanced + 1)); else healed=$((healed + 1)); fi
        resolve_subject "$name" "$reading"
        continue
    fi

    # Reached when the HEAD is parked off the default branch, when a behind
    # checkout's blocking changes could not all be set aside or its kept paths
    # could not be read or kept, when the reset heal could not prove a
    # divergence lossless or git refused to reset, and when a kept copy waits
    # aside. File the subject bead and its human gate.
    blocked=$((blocked + 1))
    nl=$'\n'
    waiting=""
    [ -z "$waiting_report" ] || waiting=$(printf '## Waiting aside\n%s\n\nEach copy above is a working copy the keep moved aside while git fast-forwarded,\nwith its bytes unchanged, and this bead stays open while any of them waits.\nCompare each with what its path holds and keep the one the runtime should read:\nmove what the path holds elsewhere, and the next pass puts the copy back, or\ndelete the copy.' \
        "${waiting_report%"$nl"}")"$nl$nl"
    title="Reconcile: rigs/$name cannot fast-forward to $remote"
    # The reset a diverged checkout's gate hands a person. Like the reset
    # heal's own checkout, it refuses rather than loses what is in its way.
    reset_cmd="git -C $path checkout --no-overwrite-ignore -B $default_branch $remote"
    if [ -n "$parked" ]; then
        body=$(printf 'rigs/%s is parked off %s — its live checkout HEAD is on %s.\nPath: %s\n\nThe rig root is a deploy mirror: reconcile fast-forwards it to %s and\ndirectory-imported packs build from its working tree, so nothing checks out a\nbranch or commits there. Restore it once any local work is saved elsewhere:\n  git -C %s checkout %s\nIt auto-closes when the rig next fast-forwards cleanly.\n\n%s## git status --porcelain\n%s\n\n## git log --oneline %s..HEAD\n%s\n' \
            "$name" "$default_branch" "${local_branch:-<detached HEAD>}" "$path" \
            "$default_branch" "$path" "$default_branch" "$waiting" \
            "$(git -C "$path" status --porcelain 2>/dev/null)" \
            "$remote" "$(git -C "$path" log --oneline "$remote"..HEAD 2>/dev/null)")
    elif [ -n "$outcome" ]; then
        title="Reconcile: rigs/$name holds a kept file it could not put back"
        body=$(printf 'rigs/%s holds a kept file it could not put back on its path.\nPath: %s\n\nThis pass: %s.\nIt auto-closes once no kept copy waits aside and the rig next ff-s cleanly.\n\n%s## git status --porcelain\n%s\n' \
            "$name" "$path" "$reading" "$waiting" \
            "$(git -C "$path" status --porcelain 2>/dev/null)")
    elif [ -n "$behind" ]; then
        report="${blocking_report%"$nl"}"
        [ -n "$report" ] || report="not examined: RECONCILE_NO_AUTOHEAL=1 turns the heals off"
        pinned=""
        [ -z "$set_aside_ref" ] || pinned=$(printf 'The local changes were pinned at %s before anything moved.\nRecover a path with git checkout %s -- <path> (working copy)\nor git checkout %s^2 -- <path> (staged copy).' \
            "$set_aside_ref" "$set_aside_ref" "$set_aside_ref")"$nl$nl"
        body=$(printf 'rigs/%s could not fast-forward to %s — the incoming commits rewrite paths\nwhere the live checkout holds local changes or files it keeps in place, and\nnot all of them could be set aside or kept without losing content.\nPath: %s\n\n## Blocking the fast-forward\n%s\n\n%sJudge and act, then close this bead (it auto-closes when the rig next\nff-s cleanly): stray write -> git -C %s restore --source=HEAD --staged --worktree -- <path>;\nmachine-local config -> carry it across the incoming change by hand;\nreal work -> save it elsewhere first.\n\n%s## git status --porcelain\n%s\n' \
            "$name" "$remote" "$path" "$report" "$pinned" "$path" "$waiting" \
            "$(git -C "$path" status --porcelain 2>/dev/null)")
    else
        report="${blocking_report%"$nl"}"
        [ -n "$report" ] || report="not examined: RECONCILE_NO_AUTOHEAL=1 turns the heals off"
        upstream=""
        [ -z "$upstream_report" ] || upstream="$nl$nl## Already upstream, but in a reset's way$nl${upstream_report%"$nl"}"
        body=$(printf 'rigs/%s could not fast-forward to %s — the live checkout diverged.\nPath: %s\n\n## The reset heal stopped\n%s%s\n\nJudge and act, then close this bead (it auto-closes when the rig next\nff-s cleanly). To reset the checkout by hand once you have judged each item\nabove:\n1. Save real work elsewhere, since the reset drops a local commit that is\n   not upstream.\n2. Restore each dirty path listed as already upstream, and each listed as\n   local-only content that you judge a stray write:\n     git -C %s restore --source=HEAD --staged --worktree -- <path>\n3. Move aside each untracked or ignored file named above. One already\n   upstream can be deleted instead.\n4. Reset:\n     %s\nThe reset keeps a local change on a path it does not rewrite, such as\nmachine-local config. It refuses, rather than overwrites or deletes, a local\nchange or an untracked file still in its way, an ignored file included, so\nskipping step 2 or 3 costs a refusal, not content. A local commit does not\nstop it, so only step 1 keeps one. Carry machine-local config across by hand\nwhere the reset rewrites its path.\n\n%s## git status --porcelain\n%s\n\n## git log --oneline %s..HEAD\n%s\n' \
            "$name" "$remote" "$path" "$report" "$upstream" "$path" "$reset_cmd" "$waiting" \
            "$(git -C "$path" status --porcelain 2>/dev/null)" \
            "$remote" "$(git -C "$path" log --oneline "$remote"..HEAD 2>/dev/null)")
    fi

    bead=$(open_bead "$name")
    if [ -n "$bead" ]; then
        gc bd --rig "$RECONCILE_RIG" update "$bead" --title "$title" --description "$body" >/dev/null 2>&1 || true
    else
        bead=$(gc bd --rig "$RECONCILE_RIG" create "$title" \
            -t task -d "$body" --json 2>/dev/null | jq -r '.id // empty' 2>/dev/null || true)
        [ -n "$bead" ] || { warn "could not file a reconcile bead for rigs/$name — divergence UNTRACKED and nobody asked"; continue; }
        gc bd --rig "$RECONCILE_RIG" update "$bead" --set-metadata reconcile_rig="$name" >/dev/null 2>&1 || true
    fi

    # Make someone hear about it. A failure here is reported, never swallowed —
    # a divergence nobody is asked about is the exact silent rot this script
    # prevents.
    if [ -n "$parked" ]; then
        msg=$(printf 'rigs/%s is parked off its deploy branch %s — HEAD is on %s, so reconcile cannot advance it and its working tree serves an off-%s build to every directory-imported pack.\nPath: %s\nSubject bead %s carries the full git status and log, and clears when rigs/%s next fast-forwards cleanly.\nRestore it: save any local work elsewhere, then git -C %s checkout %s.' \
            "$name" "$default_branch" "${local_branch:-<detached HEAD>}" "$default_branch" "$path" "$bead" "$name" "$path" "$default_branch")
    elif [ -n "$outcome" ]; then
        msg=$(printf 'rigs/%s holds a kept file it could not put back on its path, so the runtime reads whatever that path holds now instead.\nPath: %s\nSubject bead %s names each copy waiting under %s, and clears once none waits and rigs/%s next ff-s cleanly.\nCompare each copy with what its path holds and keep the one the runtime should read: move what the path holds elsewhere, and the next pass puts the copy back, or delete the copy.' \
            "$name" "$path" "$bead" "$path/$KEPT_DIR" "$name")
    elif [ -n "$behind" ]; then
        msg=$(printf 'rigs/%s cannot fast-forward to %s — the incoming commits rewrite paths where its live checkout holds local changes or files it keeps in place, and its deploy is stalled.\nPath: %s\nSubject bead %s names the blocking paths and carries the full git status, and clears when rigs/%s next ff-s cleanly.\nstray write -> git -C %s restore --source=HEAD --staged --worktree -- <path>; machine-local config -> carry it across the incoming change by hand; real work -> save it elsewhere first.' \
            "$name" "$remote" "$path" "$bead" "$name" "$path")
    else
        msg=$(printf 'rigs/%s cannot fast-forward to %s — its live checkout diverged and its deploy is stalled.\nPath: %s\nSubject bead %s names what stopped the reset heal and the steps to reset by hand, carries the full git status and divergence log, and clears when rigs/%s next ff-s cleanly.\nTo reset by hand: save real work elsewhere, restore each dirty path that is already upstream or a stray write, and move aside each untracked file in the way, as the subject bead lists them. Then run %s, which refuses rather than overwrites or deletes a local change or an untracked file still in its way, an ignored file included.' \
            "$name" "$remote" "$path" "$bead" "$name" "$reset_cmd")
    fi
    [ -z "$waiting_report" ] || [ -n "$outcome" ] \
        || msg+="${nl}A kept copy also waits under $path/$KEPT_DIR, since it could not go back on its path, and the subject bead names it."
    if ! gate_divergence "$bead" "reconcile-diverged-$name" "$msg"; then
        warn "rigs/$name divergence could NOT be put to a person (human-gate.sh failed) — subject bead $bead"
    fi
done <<< "$rigs"

echo "reconcile-rig-checkouts: $advanced advanced, $healed auto-healed, $blocked blocked"
