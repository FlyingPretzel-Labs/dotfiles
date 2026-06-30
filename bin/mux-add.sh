#!/usr/bin/env bash
# mux-add.sh — add one or more SSH hosts to the tmux grid you're CURRENTLY in,
# without rebuilding the session. Fuzzy-pick the host(s), each gets a new pane
# running ssh; the layout re-tiles and — because synchronize-panes is a window
# option — the new panes automatically join the synced typing.
#
# Meant to be triggered from inside a grid via a tmux popup binding:
#   bind a display-popup -E -w 60% -h 60% "/home/auri/bin/mux-add.sh"
# i.e.  <prefix> a  → pick → the hosts drop into the grid live.
#
# Companion to mux-pick.sh (which builds a fresh grid); same host list + fzf.
set -euo pipefail

CFG="${SSH_CONFIG:-/mnt/c/Users/KA3135/.ssh/config}"
SSH_BIN="${SSH_BIN:-ssh.exe}"

[ -n "${TMUX:-}" ] || { echo "mux-add: run this inside a tmux grid (no \$TMUX)." >&2; exit 1; }
command -v fzf >/dev/null || { echo "fzf is not installed" >&2; exit 1; }
[ -r "$CFG" ] || { echo "Cannot read SSH config: $CFG" >&2; exit 1; }

# First alias of every 'Host' line + its tags, skipping wildcard stanzas — the
# same extraction mux-pick.sh uses, so the two pickers always show the same set.
mapfile -t ROWS < <(
  grep -E '^[[:space:]]*Host[[:space:]]' "$CFG" | tr -d '\r' \
    | awk '{ a=$2; if (a ~ /\*/) next; tags=""; for (i=3;i<=NF;i++) tags=tags" "$i; printf "%-30s%s\n", a, tags }'
)

if [ "${#ROWS[@]}" -eq 0 ]; then
  echo "No host aliases found in $CFG" >&2
  exit 1
fi

# Multi-select; take column 1 (the alias) of each chosen row. No --border/--margin
# here: the surrounding tmux display-popup already frames and centers us.
mapfile -t PICKED < <(
  printf '%s\n' "${ROWS[@]}" \
    | fzf --multi \
          --layout=reverse \
          --prompt='add to grid> ' \
          --header=$'Tab = mark/unmark   Enter = add to grid   Esc = cancel' \
    | awk '{ print $1 }'
)

[ "${#PICKED[@]}" -gt 0 ] || exit 0   # nothing picked → leave the grid untouched

for h in "${PICKED[@]}"; do
  # -P -F prints the new pane id so the @host label lands on the right pane.
  pid="$(tmux split-window -P -F '#{pane_id}' "$SSH_BIN $h")"
  tmux set-option -p -t "$pid" @host "$h"
  tmux select-layout tiled >/dev/null
done
