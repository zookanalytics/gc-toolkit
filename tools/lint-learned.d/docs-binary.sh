#!/usr/bin/env bash
# docs-binary.sh — hardened learned rule: no binary file sits in a docs tree.
#
# docs/ is the central tier. It holds text that says what is true now, which a
# PR diff can review and an edit keeps true (docs/file-structure.md). A
# screenshot, image, PDF, or video is neither reviewable as a diff nor
# editable in place. It captures one moment, so it is a record of work, and a
# record belongs in specs/<bead-id>/ beside the work it shows. A capture meant
# for a reviewer can instead attach to the PR uncommitted, through
# assets/scripts/demo-deliver.sh.
#
# A path is in a docs tree when the first of its directory segments named
# `docs` or `specs` is `docs`. So services/helm/docs/ counts, and
# specs/<bead-id>/docs/ does not. Paths are read relative to the repository
# root, which is how the runner and the pre-commit hook pass them.
#
# A file is binary when its first 8000 bytes hold a NUL, the test git applies.
# The detector reads the bytes itself, because .gitattributes can mark a text
# file binary. A binary need not carry a NUL that early (a PDF can open with
# plain-text objects), so an image, video, PDF, or archive extension counts as
# well.
#
# Exit: 0 clean, 1 findings as `<file>:<line>: <message>`, 2 a file in a docs
# tree that could not be read.

set -uo pipefail

# Count bytes, not characters, whatever the caller's locale.
export LC_ALL=C

in_docs_tree() {
    local rest="$1" seg
    while :; do
        case "$rest" in
            */*) seg="${rest%%/*}"; rest="${rest#*/}" ;;
            *) return 1 ;;
        esac
        case "$seg" in
            docs) return 0 ;;
            specs) return 1 ;;
        esac
    done
}

has_binary_extension() {
    local rc=1
    shopt -s nocasematch
    case "$1" in
        *.png | *.jpg | *.jpeg | *.gif | *.webp | *.bmp | *.tif | *.tiff | *.ico | *.heic | *.avif | \
        *.pdf | *.mp4 | *.mov | *.webm | *.mkv | *.avi | *.mp3 | *.wav | \
        *.zip | *.gz | *.tgz | *.bz2 | *.xz | *.7z) rc=0 ;;
    esac
    shopt -u nocasematch
    return "$rc"
}

# `read -d ''` stops at the first NUL. It returns 0 with fewer than WINDOW
# bytes read only when it met one; at EOF it returns non-zero.
WINDOW=8000
has_leading_nul() {
    local chunk
    IFS= read -r -d '' -n "$WINDOW" chunk < "$1" || return 1
    [ "${#chunk}" -lt "$WINDOW" ]
}

report() {
    echo "$1:1: binary file in a docs tree. docs/ holds only text that is kept true in place (docs/file-structure.md). Commit a screenshot or other capture under specs/<bead-id>/, or attach it to the PR uncommitted with assets/scripts/demo-deliver.sh (learned rule: docs-binary)"
    found=1
}

# The extension needs no read, so an unreadable image is still a finding. Only
# a file whose bytes decide, and cannot be read, is an error.
found=0
unreadable=0
for f in "$@"; do
    [ -f "$f" ] || continue
    in_docs_tree "$f" || continue
    if has_binary_extension "$f"; then
        report "$f"
    elif [ ! -r "$f" ]; then
        echo "$f: cannot read it to tell whether it is binary (docs-binary)"
        unreadable=1
    elif has_leading_nul "$f"; then
        report "$f"
    fi
done

[ "$unreadable" -eq 0 ] || exit 2
[ "$found" -eq 0 ]
