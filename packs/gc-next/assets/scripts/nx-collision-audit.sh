#!/bin/sh
# nx-collision-audit.sh — the O1/§1 non-collision guarantee, executable.
# (Brand: no gc-next artifact basename may shadow the live pack, the
# imported gastown layer, or the bundled builtin packs.)
#
# Pack artifacts resolve by layer, and a same-name artifact in a
# higher-priority layer SILENTLY shadows the lower one (gascity-packs.md
# §7) — so this audit compares basenames, not manifests. Agent-name
# collisions fail loading outright; catching them here is still cheaper.
#
# Usage: nx-collision-audit.sh [<repo-root>]
#   exit 0 — no collisions; exit 1 — collisions listed on stdout.
#
# The gastown/builtin layers are not present in this checkout, so their
# known artifact basenames are pinned in the deny list below (sources:
# root pack.toml header, docs/gascity-packs.md §4, gascity-routing-model
# provenance). Extend the list when a new base-layer artifact is learned;
# stage-1 validation re-runs this audit inside a real city where the
# resolved layers are on disk.
set -eu

ROOT="${1:-$(git rev-parse --show-toplevel)}"
NX="$ROOT/packs/gc-next"

collect() { # collect <dir> <pattern> -> sorted basenames (no extension)
  [ -d "$1" ] || return 0
  find "$1" -maxdepth "${3:-1}" -name "$2" 2>/dev/null | while read -r f; do
    basename "$f" | sed 's/\.template\.md$//; s/\.toml$//; s/\.sh$//'
  done | sort -u
}

# Known base-layer basenames (gastown import + builtin packs), pinned:
BASE_KNOWN="mol-polecat-work mol-polecat-base mol-review-leg mol-dog-backup
mol-dog-compactor mol-shutdown-dance mol-do-work graph-worker tmux-theme
status-line boot deacon mayor polecat refinery witness dog"

check_set() { # check_set <label> <nx-list> <live-list>
  label="$1"; nx_list="$2"; live_list="$3"
  for name in $nx_list; do
    if printf '%s\n' $live_list $BASE_KNOWN | grep -qx "$name"; then
      echo "COLLISION [$label]: $name (gc-next vs live/base layer)"
    fi
  done
}

NX_FORMULAS=$(collect "$NX/formulas" "*.toml")
NX_AGENTS=$(for d in "$NX"/agents/*/; do [ -d "$d" ] && basename "$d"; done | sort -u)
NX_FRAGMENTS=$(collect "$NX/template-fragments" "*.template.md")
NX_SCRIPTS=$(collect "$NX/assets/scripts" "*.sh")
NX_DOCTOR=$(for d in "$NX"/doctor/*/; do [ -d "$d" ] && basename "$d"; done | sort -u)
NX_ORDERS=$(collect "$NX/orders" "*.toml")

LIVE_FORMULAS=$(collect "$ROOT/formulas" "*.toml")
LIVE_AGENTS=$(for d in "$ROOT"/agents/*/; do [ -d "$d" ] && basename "$d"; done | sort -u)
LIVE_FRAGMENTS=$(collect "$ROOT/template-fragments" "*.template.md")
LIVE_SCRIPTS=$( { collect "$ROOT/assets/scripts" "*.sh"; collect "$ROOT/tools" "*.sh"; } | sort -u)
LIVE_DOCTOR=$(for d in "$ROOT"/doctor/*/; do [ -d "$d" ] && basename "$d"; done | sort -u)
LIVE_ORDERS=$(collect "$ROOT/orders" "*.toml")
KEEPER_FRAGMENTS=$(collect "$ROOT/packs/gascity-keeper/template-fragments" "*.template.md")
KEEPER_FORMULAS=$(collect "$ROOT/packs/gascity-keeper/formulas" "*.toml")

OUT=$( {
  check_set formulas  "$NX_FORMULAS"  "$LIVE_FORMULAS $KEEPER_FORMULAS"
  check_set agents    "$NX_AGENTS"    "$LIVE_AGENTS"
  check_set fragments "$NX_FRAGMENTS" "$LIVE_FRAGMENTS $KEEPER_FRAGMENTS"
  check_set scripts   "$NX_SCRIPTS"   "$LIVE_SCRIPTS"
  check_set doctor    "$NX_DOCTOR"    "$LIVE_DOCTOR"
  check_set orders    "$NX_ORDERS"    "$LIVE_ORDERS"
} )

if [ -n "$OUT" ]; then
  printf '%s\n' "$OUT"
  exit 1
fi
echo "nx-collision-audit: clean (formulas, agents, fragments, scripts, doctor, orders)"
