#!/usr/bin/env bash
# patch-monday.sh — patch the fleet, canary-first.
#
# Phase 1 (canary): patch the 'canary'-tagged test hosts, reboot them, wait for
#                   them to come back. If any fail, STOP — the fleet is untouched.
# Phase 2 (main):   after you confirm, patch the 'tux'-tagged hosts in parallel.
#                   The fleet is NOT rebooted (cron jobs restart them midweek);
#                   only the canary boxes reboot here.
#
# SAFE BY DEFAULT: dry-run. Only *lists* pending updates until you pass --apply.
#
# Usage:
#   patch-monday.sh                          # dry-run: pending updates, canary + fleet
#   patch-monday.sh --apply                  # canary -> confirm -> fleet (fleet not rebooted)
#   patch-monday.sh --apply --reboot auto    # OVERRIDE: also reboot fleet hosts that need it
#   patch-monday.sh --apply --no-canary      # skip the canary phase
#   patch-monday.sh host1 host2              # explicit hosts (no canary, no tags)
#
# Options:
#   --apply             apply upgrades (default: dry-run)
#   --reboot MODE       fleet reboot policy: never (default, cron handles it) | report | auto
#   --no-canary         skip the canary phase
#   --jobs N            max parallel hosts in the fleet phase (default: 8)
#   --tag TAG           fleet tag (default: tux)
#   --canary-tag TAG    canary tag (default: canary)
#   --yes               skip all confirmation prompts
#   --timeout SEC       per-host upgrade timeout (default: 600)
#   --reboot-wait SEC   how long to wait for a canary host to return (default: 420)
set -uo pipefail

CFG="${SSH_CONFIG:-/mnt/c/Users/KA3135/.ssh/config}"
SSH_BIN="${SSH_BIN:-ssh.exe}"
SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=10)

# ── remote payload: check or upgrade (reboot handled by orchestrator) ──
read -r -d '' REMOTE_PAYLOAD <<'REMOTE' || true
set -u
APPLY="${1:-0}"; REBOOT="${2:-report}"
if [ "$(id -u)" -ne 0 ]; then S="sudo -n"; else S=""; fi
# RHEL 8+ uses dnf; RHEL 7 (e.g. WebLogic boxes) only has yum.
PM="$(command -v dnf || command -v yum || true)"; PM="${PM##*/}"
[ -n "$PM" ] || { echo "NO_PKG_MGR"; exit 5; }

if [ "$APPLY" != "1" ]; then
  out="$($S "$PM" -q check-update)"; rc=$?   # 100=updates, 0=none, else=error (stderr -> log)
  if   [ "$rc" -eq 100 ]; then echo "UPDATES_AVAILABLE $(printf '%s\n' "$out" | grep -c .)"
  elif [ "$rc" -eq 0   ]; then echo "UP_TO_DATE"
  else echo "CHECK_ERROR rc=$rc"; exit 3; fi
  exit 0
fi

if [ "$PM" = dnf ]; then $S dnf -y upgrade --refresh; else $S yum -y update; fi; rc=$?
if [ "$rc" -ne 0 ]; then echo "UPGRADE_FAILED rc=$rc"; exit 4; fi
echo "UPGRADE_OK"

nr=2
if command -v needs-restarting >/dev/null 2>&1; then $S needs-restarting -r >/dev/null 2>&1; nr=$?; fi
case "$REBOOT" in
  auto)  if [ "$nr" -eq 1 ]; then echo "REBOOTING"; ($S systemctl reboot || $S shutdown -r +1) >/dev/null 2>&1 & fi ;;
  never) : ;;
  *)     if   [ "$nr" -eq 1 ]; then echo "REBOOT_REQUIRED"
         elif [ "$nr" -eq 0 ]; then echo "NO_REBOOT_NEEDED"
         else echo "REBOOT_UNKNOWN"; fi ;;
esac
exit 0
REMOTE

classify_sym() {  # XX only if the marker carries a failure token; else OK
  case "$1" in
    *UPGRADE_FAILED*|*CHECK_ERROR*|*NO_PKG_MGR*|*TIMEOUT*|*UNREACHABLE*|NO_OUTPUT) echo "XX " ;;
    *) echo "OK " ;;
  esac
}

# ── worker mode (one host, invoked by xargs) ──
if [ "${1:-}" = "--worker" ]; then
  host="$2"; logf="$LOGDIR/${host//\//_}.log"
  timeout "${TIMEOUT}s" "$SSH_BIN" "${SSH_OPTS[@]}" "$host" \
    bash -s -- "$APPLY" "$REBOOT" <<<"$REMOTE_PAYLOAD" >"$logf" 2>&1
  rc=$?
  marker=$(grep -hoE 'UPDATES_AVAILABLE [0-9]+|UP_TO_DATE|UPGRADE_OK|UPGRADE_FAILED rc=[0-9]+|CHECK_ERROR rc=[0-9]+|NO_PKG_MGR|REBOOT_REQUIRED|REBOOTING|NO_REBOOT_NEEDED|REBOOT_UNKNOWN' "$logf" 2>/dev/null | paste -sd, -)
  [ "$rc" -eq 124 ] && marker="TIMEOUT"
  [ -z "$marker" ] && [ "$rc" -ne 0 ] && marker="UNREACHABLE rc=$rc"
  marker="${marker:-NO_OUTPUT}"
  printf '%s\t%s\t%s\n' "$rc" "$host" "$marker" >>"$SUMMARY"
  # Stream this host's result the moment it finishes (one atomic line).
  printf '  %s %-26s %s\n' "$(classify_sym "$marker")" "$host" "$marker"
  exit 0
fi

# ── helpers (main process) ──
select_hosts() {  # $1 = tag -> prints first alias of each tagged Host line
  grep -E '^[[:space:]]*Host[[:space:]]' "$CFG" | tr -d '\r' \
    | awk -v tag="$1" '{ for (i=3;i<=NF;i++) if ($i==tag) { print $2; break } }'
}

run_batch() {  # $1 phase label, $2 reboot mode, rest = hosts. Returns #flagged.
  local phase="$1" reboot="$2"; shift 2
  SUMMARY="$LOGDIR/summary-$phase.tsv"; : >"$SUMMARY"
  export SUMMARY REBOOT="$reboot"
  # Workers stream each host live as it finishes; here we only tally + recap.
  printf '%s\n' "$@" | xargs -P "$JOBS" -I{} "$SELF" --worker {}
  local ok=0 fail=0 flagged=()
  while IFS=$'\t' read -r rc host marker; do
    if [ "$(classify_sym "$marker")" = "OK " ]; then ok=$((ok+1))
    else fail=$((fail+1)); flagged+=("$host  $marker"); fi
  done <"$SUMMARY"
  echo "  -- $phase: OK $ok / FLAGGED $fail --"
  [ "$fail" -gt 0 ] && printf '     ! %s\n' "${flagged[@]}"
  return "$fail"
}

reboot_and_wait() {  # $1 host. Reboot, then poll until SSH is back. 0=back, 1=lost.
  local h="$1" deadline
  "$SSH_BIN" "${SSH_OPTS[@]}" "$h" 'sudo -n systemctl reboot || sudo -n shutdown -r now' >/dev/null 2>&1 || true
  sleep 15
  deadline=$(( $(date +%s) + REBOOT_WAIT ))
  while [ "$(date +%s)" -lt "$deadline" ]; do
    if "$SSH_BIN" -o BatchMode=yes -o ConnectTimeout=5 "$h" true >/dev/null 2>&1; then
      echo "  OK  $h is back up"; return 0
    fi
    sleep 10
  done
  echo "  XX  $h did NOT return within ${REBOOT_WAIT}s"; return 1
}

confirm() { [ "$ASSUME_YES" = 1 ] && return 0; local a; read -r -p "$1 [y/N] " a; case "$a" in y|Y|yes|YES) return 0;; *) return 1;; esac; }

# ── parse args ──
APPLY=0; REBOOT="never"; JOBS=8; TAG="${TAG:-tux}"; CANARY_TAG="canary"
ASSUME_YES=0; TIMEOUT=600; REBOOT_WAIT=420; DO_CANARY=1; EXPLICIT=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --apply)       APPLY=1 ;;
    --reboot)      REBOOT="$2"; shift ;;
    --no-canary)   DO_CANARY=0 ;;
    --jobs)        JOBS="$2"; shift ;;
    --tag)         TAG="$2"; shift ;;
    --canary-tag)  CANARY_TAG="$2"; shift ;;
    --yes|-y)      ASSUME_YES=1 ;;
    --timeout)     TIMEOUT="$2"; shift ;;
    --reboot-wait) REBOOT_WAIT="$2"; shift ;;
    -h|--help)     sed -n '2,30p' "$0"; exit 0 ;;
    -*)            echo "Unknown option: $1" >&2; exit 2 ;;
    *)             EXPLICIT+=("$1") ;;
  esac
  shift
done

[ -r "$CFG" ] || { echo "Cannot read SSH config: $CFG" >&2; exit 1; }
if [ "${#EXPLICIT[@]}" -gt 0 ]; then
  MAIN=("${EXPLICIT[@]}"); CANARY=(); DO_CANARY=0
else
  mapfile -t MAIN   < <(select_hosts "$TAG")
  mapfile -t CANARY < <(select_hosts "$CANARY_TAG")
fi
[ "${#MAIN[@]}" -gt 0 ] || { echo "No hosts tagged '$TAG' in $CFG" >&2; exit 1; }
[ "$DO_CANARY" = 1 ] || CANARY=()

SELF="$(readlink -f "$0")"
LOGDIR="$HOME/patch-logs/$(date +%Y%m%d-%H%M%S)-$TAG"; mkdir -p "$LOGDIR"
export SSH_BIN REMOTE_PAYLOAD LOGDIR APPLY TIMEOUT

mode="DRY-RUN (no changes)"; [ "$APPLY" = 1 ] && mode="APPLY (fleet reboot=$REBOOT)"
echo "Mode: $mode | parallel: $JOBS | logs: $LOGDIR"
[ "${#CANARY[@]}" -gt 0 ] && echo "Canary (${#CANARY[@]}): ${CANARY[*]}"
echo "Fleet  (${#MAIN[@]}):"; printf '%s\n' "${MAIN[@]}" | column
echo

# ── DRY-RUN: just report pending updates ──
if [ "$APPLY" != 1 ]; then
  [ "${#CANARY[@]}" -gt 0 ] && { echo "== canary =="; run_batch canary report "${CANARY[@]}"; echo; }
  echo "== fleet =="; run_batch fleet report "${MAIN[@]}"
  echo; echo "Dry-run only. Re-run with --apply to patch."
  exit 0
fi

confirm "Patch canary now? (${#MAIN[@]} fleet hosts wait for a 2nd confirm)" || { echo "Aborted."; exit 0; }

# ── PHASE 1: canary ──
if [ "${#CANARY[@]}" -gt 0 ]; then
  echo "== PHASE 1: canary — patching =="
  if ! run_batch canary never "${CANARY[@]}"; then
    echo "Canary upgrade had failures — STOPPING. Fleet untouched. See $LOGDIR" >&2; exit 1
  fi
  echo "== PHASE 1: canary — rebooting & waiting =="
  cfail=0
  for h in "${CANARY[@]}"; do reboot_and_wait "$h" || cfail=$((cfail+1)); done
  if [ "$cfail" -gt 0 ]; then
    echo "$cfail canary host(s) did not return — STOPPING. Fleet untouched." >&2; exit 1
  fi
  echo "Canary healthy."; echo
  confirm "Proceed to fleet (${#MAIN[@]} hosts)?" || { echo "Stopped after canary."; exit 0; }
fi

# ── PHASE 2: fleet ──
echo "== PHASE 2: fleet =="
run_batch fleet "$REBOOT" "${MAIN[@]}"; rc=$?
echo
echo "Done. OK=clean, XX=needs a look. Logs: $LOGDIR"
[ "$rc" -eq 0 ]
