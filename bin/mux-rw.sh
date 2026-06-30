#!/usr/bin/env bash
# mux-rw.sh — grid the 'rw'-tagged set in a synchronized tmux session: the
# biweekly second-Tuesday Release-Wechsel hosts.
#
# Thin wrapper around mux.sh: it pins the 'rw' tag, the session name and a label.
# (This replaces the old patch-tuesday.sh default behaviour.)
#
# Usage:
#   mux-rw.sh                 # grid every 'rw'-tagged host
#   mux-rw.sh -l "Some Label" # override the window-pill label
#
# Synchronized input is ON by default — toggle it with:  <prefix> :setw synchronize-panes
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LABEL="${LABEL:-Release Wechsel}"

EXTRA=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    -l|--label) LABEL="$2"; shift 2 ;;
    *)          EXTRA+=("$1"); shift ;;
  esac
done

export TAG="${TAG:-rw}"
export SESSION="${SESSION:-mux-rw}"

exec "$HERE/mux.sh" -l "$LABEL" "${EXTRA[@]}"
