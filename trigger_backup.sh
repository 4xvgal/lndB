#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CONF_FILE="${CONF_FILE:-$SCRIPT_DIR/lndb.conf}"
BACKUP_SCRIPT="$SCRIPT_DIR/backup.sh"

if [[ ! -f "$CONF_FILE" ]]; then
  echo "[lndB-trigger] missing config: $CONF_FILE" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$CONF_FILE"

: "${TRIGGER_MODE:=direct}"
: "${SYSTEMD_UNIT_NAME:=lndb-backup.service}"
: "${DAEMON_PID_FILE:=/run/lndb-daemon.pid}"
: "${DAEMON_SIGNAL:=USR1}"

log() {
  local level=$1; shift
  local msg="$*"
  local ts
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  printf '%s [trigger:%s] %s\n' "$ts" "$level" "$msg"
}

fail() {
  log "ERROR" "$*"
  exit 1
}

trigger_direct() {
  log "INFO" "running backup.sh directly"
  exec "$BACKUP_SCRIPT" "$@"
}

trigger_systemd() {
  local unit=${SYSTEMD_UNIT_NAME:?SYSTEMD_UNIT_NAME required for systemd mode}
  log "INFO" "requesting systemd unit $unit start"
  systemctl start "$unit"
}

trigger_signal() {
  local pid_file=${DAEMON_PID_FILE:?DAEMON_PID_FILE required for signal mode}
  [[ -f "$pid_file" ]] || fail "PID file not found: $pid_file"
  local pid
  pid=$(<"$pid_file")
  [[ -n "$pid" ]] || fail "PID file $pid_file is empty"
  if ! kill -0 "$pid" >/dev/null 2>&1; then
    fail "process $pid not running (from $pid_file)"
  fi
  local signal=${DAEMON_SIGNAL:-USR1}
  log "INFO" "sending $signal to PID $pid"
  kill -"${signal}" "$pid"
}

case "${TRIGGER_MODE,,}" in
  direct|"")
    trigger_direct "$@"
    ;;
  systemd)
    trigger_systemd "$@"
    ;;
  signal)
    trigger_signal "$@"
    ;;
  *)
    fail "unsupported TRIGGER_MODE: $TRIGGER_MODE"
    ;;
esac
