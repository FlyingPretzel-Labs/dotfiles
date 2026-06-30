#!/usr/bin/env bash
# mux.sh — open a set of SSH hosts in a synchronized tmux grid, so you type a
# command once and it runs in every pane. This is the engine behind the mux-*
# wrappers (mux-rw, mux-canary, mux-weblogic, …); call it directly for ad-hoc
# grids, or let a wrapper pin the host list / session / label for you.
#
# You drive it interactively — status checks, upgrades, reboots, edits, whatever.
# Synchronized input is ON by default — toggle it with:  <prefix> :setw synchronize-panes
#
# Usage:
#   mux.sh host1 host2 ...      # grid an explicit host list
#   TAG=rw mux.sh               # grid every host carrying the 'rw' tag in the SSH config
#   mux.sh -l "Some Label"      # set the window-pill label
#
# With neither an explicit host list nor TAG set it prints usage and exits —
# there is no default host set.
# The pill (tmux window name) shows the LABEL; each pane border shows its host.
set -euo pipefail

CFG="${SSH_CONFIG:-/mnt/c/Users/KA3135/.ssh/config}"
TAG="${TAG:-}"
SESSION="${SESSION:-mux${TAG:+-$TAG}}"
SSH_BIN="${SSH_BIN:-ssh.exe}"
LABEL="${LABEL:-Synced Grid}"

EXPLICIT=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    -l|--label) LABEL="$2"; shift 2 ;;
    *)          EXPLICIT+=("$1"); shift ;;
  esac
done

if [ "${#EXPLICIT[@]}" -gt 0 ]; then
  HOSTS=("${EXPLICIT[@]}")
elif [ -n "$TAG" ]; then
  [ -r "$CFG" ] || { echo "Cannot read SSH config: $CFG" >&2; exit 1; }
  # First alias of every 'Host' line carrying the whole-word $TAG token.
  mapfile -t HOSTS < <(
    grep -E '^[[:space:]]*Host[[:space:]]' "$CFG" | tr -d '\r' \
      | awk -v tag="$TAG" '{ for (i=3;i<=NF;i++) if ($i==tag) { print $2; break } }'
  )
else
  cat >&2 <<'EOF'
usage: mux.sh host1 host2 ...     grid an explicit host list
       TAG=<tag> mux.sh           grid every host carrying <tag> in the SSH config
       mux.sh -l "Label"          set the window-pill label
Give an explicit host list or set TAG — there is no default host set.
EOF
  exit 2
fi

if [ "${#HOSTS[@]}" -eq 0 ]; then
  echo "No hosts tagged '$TAG' in $CFG" >&2
  exit 1
fi

echo "Opening ${#HOSTS[@]} host(s): ${HOSTS[*]}"

tmux kill-session -t "$SESSION" 2>/dev/null || true
tmux new-session  -d -s "$SESSION" -n "$LABEL" "$SSH_BIN ${HOSTS[0]}"
# Store the host in a pane-scoped user option — ssh.exe's OSC title can't clobber it.
tmux set-option -p -t "$SESSION" @host "${HOSTS[0]}"

for h in "${HOSTS[@]:1}"; do
  tmux split-window -t "$SESSION" "$SSH_BIN $h"
  tmux set-option -p -t "$SESSION" @host "$h"
  tmux select-layout -t "$SESSION" tiled >/dev/null
done

# Pill = LABEL: lock it so the ssh.exe command can't take the window name over.
tmux set-window-option -t "$SESSION" automatic-rename off
tmux set-window-option -t "$SESSION" allow-rename off
tmux rename-window     -t "$SESSION" "$LABEL"

# Drive the outer terminal (WezTerm) tab title with the LABEL too — its
# format-tab-title falls back to the pane title (ssh.exe) otherwise. Session-scoped.
tmux set-option -t "$SESSION" set-titles on
tmux set-option -t "$SESSION" set-titles-string "#W"

# Pane borders = hostname (from @host, not the clobbered pane_title).
tmux set-window-option -t "$SESSION" pane-border-status top
tmux set-window-option -t "$SESSION" pane-border-format " #{@host} "

tmux select-layout     -t "$SESSION" tiled >/dev/null
tmux set-option        -t "$SESSION" mouse on
tmux set-window-option -t "$SESSION" synchronize-panes on
tmux display-message   -t "$SESSION" "synchronize-panes ON — type once, runs everywhere. Toggle: prefix *"

tmux attach-session -t "$SESSION"
