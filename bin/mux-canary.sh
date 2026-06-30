#!/usr/bin/env bash
# mux-canary.sh — grid the 'canary'-tagged test boxes in a synchronized tmux
# session for hands-on work. Type a command once and it runs in every pane.
#
# Thin wrapper around mux.sh: it pins the 'canary' tag, the session name and a
# label. (Replaces the old self-contained patch-canary.sh.)
#
# Usage:
#   mux-canary.sh                 # grid all 'canary'-tagged hosts
#   mux-canary.sh -l "Some Label" # override the window-pill label
#   mux-canary.sh host1 host2 ... # explicit host list (ignores the tag)
#
# Synchronized input is ON by default — toggle it with:  <prefix> :setw synchronize-panes
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LABEL="${LABEL:-Canary}"

EXTRA=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    -l|--label) LABEL="$2"; shift 2 ;;
    *)          EXTRA+=("$1"); shift ;;
  esac
done

export TAG="${TAG:-canary}"
export SESSION="${SESSION:-mux-canary}"

exec "$HERE/mux.sh" -l "$LABEL" "${EXTRA[@]}"
