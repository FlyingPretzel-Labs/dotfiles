#!/usr/bin/env bash
# mux-wl.sh — grid the WebLogic prod app servers in a synchronized tmux session,
# so you type a command once and it runs on all of them at once.
#
# Thin wrapper around mux.sh: it pins the 'wl' tag, the session name and a label.
# The hosts themselves live only in ~/.ssh/config (tagged 'wl') — never here —
# so this script carries no infrastructure details and is safe to publish.
#
# Usage:
#   mux-wl.sh                 # grid every 'wl'-tagged host
#   mux-wl.sh -l "Some Label" # override the window-pill label
#
# Synchronized input is ON by default — toggle it with:  <prefix> :setw synchronize-panes
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LABEL="${LABEL:-WebLogic}"

EXTRA=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    -l|--label) LABEL="$2"; shift 2 ;;
    *)          EXTRA+=("$1"); shift ;;
  esac
done

export TAG="${TAG:-wl}"
export SESSION="${SESSION:-mux-wl}"

exec "$HERE/mux.sh" -l "$LABEL" "${EXTRA[@]}"
