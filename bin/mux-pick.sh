#!/usr/bin/env bash
# mux-pick.sh — fuzzy-pick any set of SSH hosts and drop them into a
# synchronized tmux grid, so you can assemble an ad-hoc session on the fly
# instead of hand-writing a new mux-<group>.sh wrapper each time.
#
# It lists every host alias from the SSH config (with its tags), lets you
# multi-select with fzf (Tab to mark), then hands the chosen hosts to mux.sh —
# the same engine the per-group wrappers use.
#
# Usage:
#   mux-pick.sh                 # fuzzy multi-select, then build the grid
#   mux-pick.sh -l "Some Label" # set the window-pill label up front
#
# In fzf:  Tab = mark/unmark a host,  Enter = build the grid,  Esc = cancel.
# Synchronized input is ON by default — toggle it with:  <prefix> :setw synchronize-panes
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CFG="${SSH_CONFIG:-/mnt/c/Users/KA3135/.ssh/config}"
LABEL="${LABEL:-Ad-hoc Grid}"

while [ "$#" -gt 0 ]; do
  case "$1" in
    -l|--label) LABEL="$2"; shift 2 ;;
    *)          echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

command -v fzf >/dev/null || { echo "fzf is not installed" >&2; exit 1; }
[ -r "$CFG" ] || { echo "Cannot read SSH config: $CFG" >&2; exit 1; }

# First alias of every 'Host' line + its tags, skipping wildcard stanzas
# (Host *, *-dmz, …). Column 1 is the alias we feed to ssh; the rest is
# just context to fuzzy-match against (e.g. 'tux', 'canary', app names).
mapfile -t ROWS < <(
  grep -E '^[[:space:]]*Host[[:space:]]' "$CFG" | tr -d '\r' \
    | awk '{ a=$2; if (a ~ /\*/) next; tags=""; for (i=3;i<=NF;i++) tags=tags" "$i; printf "%-30s%s\n", a, tags }'
)

if [ "${#ROWS[@]}" -eq 0 ]; then
  echo "No host aliases found in $CFG" >&2
  exit 1
fi

# Multi-select; take column 1 (the alias) of each chosen row.
mapfile -t PICKED < <(
  printf '%s\n' "${ROWS[@]}" \
    | fzf --multi \
          --layout=reverse \
          --border=rounded \
          --border-label=' grid hosts ' \
          --margin=8%,22% \
          --padding=1 \
          --prompt='grid hosts> ' \
          --bind='ctrl-d:abort' \
          --header=$'Tab = mark/unmark   Enter = build grid   Esc/Ctrl-D = cancel' \
    | awk '{ print $1 }'
)

if [ "${#PICKED[@]}" -eq 0 ]; then
  echo "Nothing selected — no grid built."
  exit 0
fi

echo "Building synced grid for ${#PICKED[@]} host(s): ${PICKED[*]}"
exec "$HERE/mux.sh" -l "$LABEL" "${PICKED[@]}"
