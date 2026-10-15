#!/usr/bin/env bash
# gc gc-toolkit scripts-dir: print the directory that holds this pack's scripts.
# gc runs a pack command with GC_PACK_DIR set to the pack it loaded the command
# from, so the directory is that pack's own copy wherever the city imports the
# pack from, never a checkout the caller happens to be in. An agent calls a
# pack script as "$(gc gc-toolkit scripts-dir)/<script>" inside the command
# that runs it, so no variable has to survive from an earlier shell.
# Exit: 0 printed · 1 GC_PACK_DIR unset or no assets/scripts under it.
set -eu

[ -n "${GC_PACK_DIR:-}" ] || {
    echo "scripts-dir: GC_PACK_DIR is unset; gc sets it for a pack command, so run this as gc gc-toolkit scripts-dir" >&2
    exit 1
}
dir="$GC_PACK_DIR/assets/scripts"
[ -d "$dir" ] || {
    echo "scripts-dir: $dir does not exist" >&2
    exit 1
}
printf '%s\n' "$dir"
