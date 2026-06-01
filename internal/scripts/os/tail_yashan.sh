#!/usr/bin/env bash
# File Name: tail_yashan.sh
# Purpose: Tail YashanDB logs via yasql and v$ params
# Created: 20260517  by  huangtingzhong

set -euo pipefail

TAIL_N="${TAIL_N:-${TAIL_LINES:-1000}}"
YASQL_BIN="${YASQL:-yasql}"
YASQL_SYSDBA="${YASQL_SYSDBA:-1}"

usage() {
  cat <<'EOF'
YashanDB tail: resolve log path from V$PARAMETER (via yasql) and/or environment, then run tail.

Usage:
  yashandb-tail-log.sh [OPTIONS] [TYPE]

Options:
  -h, --help           Show this help and exit.
  -n, --lines N        Print the last N lines before following (default: 1000; env TAIL_N / TAIL_LINES).
  -t, --type TYPE      Log kind: run | alert | slow | audit | diag (default: run).

Arguments:
  TYPE                 Same as --type when -t is not used (first positional argument).

Environment:
  YASQL                Path to yasql (default: yasql).
  YASQL_SYSDBA         Set to 0 to omit "/ as sysdba"; then use YASQL_ARGS for connection.
  YASQL_ARGS           Passed to yasql when YASQL_SYSDBA=0 (e.g. remote login string).
  YASDB_DATA           Instance data directory; expands ?/ paths from V$PARAMETER when set.
  YASHANDB_LOG_TYPE    Default TYPE if none is given on the command line.

Overrides (optional; skip DB lookup when set):
  YASHANDB_RUN_LOG_OVERRIDE    Full path to run.log
  YASHANDB_ALERT_LOG_OVERRIDE Full path to alert.log
  YASHANDB_SLOW_LOG_OVERRIDE  File or directory for slow logs
  YASHANDB_AUDIT_LOG_OVERRIDE File or directory for audit logs
  YASHANDB_DIAG_OVERRIDE      DIAGNOSTIC_DEST directory or a single file to tail

Examples:
  yashandb-tail-log.sh
  yashandb-tail-log.sh -t alert
  yashandb-tail-log.sh alert
  yashandb-tail-log.sh -n 2000 -t slow
  YASDB_DATA=/data/yashan/yasdb_data/db-1-1 yashandb-tail-log.sh -t audit
EOF
}

OPT_LOG_TYPE=""
while [[ "${1:-}" =~ ^- ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    -n|--lines)
      TAIL_N="${2:?--lines requires a line count}"
      shift 2
      ;;
    -t|--type)
      OPT_LOG_TYPE="${2:?-t/--type requires type: run|alert|slow|audit|diag}"
      shift 2
      ;;
    *)
      break
      ;;
  esac
done

if [[ -n "$OPT_LOG_TYPE" ]]; then
  LOG_TYPE="$OPT_LOG_TYPE"
else
  LOG_TYPE="${1:-${YASHANDB_LOG_TYPE:-run}}"
  [[ -n "${1:-}" ]] && shift || true
fi
LOG_TYPE="$(printf '%s' "$LOG_TYPE" | tr '[:upper:]' '[:lower:]')"

run_yasql() {
  local sql="$1"
  if [[ "$YASQL_SYSDBA" == "1" ]]; then
    printf '%s\n' "$sql" | "$YASQL_BIN" / as sysdba
  else
    # shellcheck disable=SC2086
    printf '%s\n' "$sql" | "$YASQL_BIN" ${YASQL_ARGS:-}
  fi
}

query_param() {
  local pname="$1"
  # yasql prints banners and a trailing "YashanDB Server ..." line; do not use tail -1 on full output.
  run_yasql "SET HEADING OFF FEEDBACK OFF VERIFY OFF ECHO OFF PAGESIZE 0 TRIMSPOOL ON TIMING OFF
SELECT TRIM(VALUE) FROM V\$PARAMETER WHERE NAME = '${pname}';" \
    | tr -d '\r' \
    | awk '/^[[:space:]]*(\/|\?)/ {
        sub(/^[[:space:]]+/, "");
        sub(/[[:space:]]+$/, "");
        print;
        exit
      }'
}

expand_question_mark() {
  # SLOW_LOG_FILE_PATH default may be ?/log/slow; ? expands to YASDB_DATA when set
  local p="$1"
  local base="${YASDB_DATA:-}"
  if [[ "$p" == \?/* ]]; then
    if [[ -n "$base" ]]; then
      printf '%s%s\n' "$base" "${p#\?}"
    else
      printf '%s\n' "$p"
    fi
  else
    printf '%s\n' "$p"
  fi
}

default_run_log_path() {
  local base="${YASDB_DATA:?Set YASDB_DATA or configure RUN_LOG_FILE_PATH}"
  printf '%s/log/run/run.log\n' "${base%/}"
}

default_alert_log_path() {
  local base="${YASDB_DATA:?Set YASDB_DATA to resolve default alert.log path}"
  printf '%s/log/alert/alert.log\n' "${base%/}"
}

pick_latest_in_dir() {
  local dir="$1"
  local globpat="$2"
  local f
  if [[ ! -d "$dir" ]]; then
    echo "Directory does not exist: $dir" >&2
    exit 1
  fi
  f="$(find "$dir" -maxdepth 1 -type f -name "$globpat" -print0 2>/dev/null \
        | xargs -0 ls -1t 2>/dev/null | head -1 || true)"
  if [[ -z "$f" ]]; then
    echo "No file matching $globpat under $dir" >&2
    exit 1
  fi
  printf '%s\n' "$f"
}

resolve_diag_tail_target() {
  local root="$1"
  # Try common layout under DIAGNOSTIC_DEST
  if [[ -f "${root}/log/alert/alert.log" ]]; then
    printf '%s\n' "${root}/log/alert/alert.log"
    return
  fi
  local found
  found="$(find "$root" -maxdepth 5 -type f -name alert.log 2>/dev/null | head -1)"
  if [[ -n "$found" ]]; then
    printf '%s\n' "$found"
    return
  fi
  # Typical YashanDB layout: DIAGNOSTIC_DEST=<YASDB_DATA>/diag while alert stays at <YASDB_DATA>/log/alert/alert.log
  local sibling="${root%/}"
  sibling="$(dirname "$sibling")"
  if [[ -f "${sibling}/log/alert/alert.log" ]]; then
    printf '%s\n' "${sibling}/log/alert/alert.log"
    return
  fi
  echo "alert.log not found under DIAGNOSTIC_DEST=$root (nor ${sibling}/log/alert/alert.log); set YASHANDB_DIAG_OVERRIDE or use -t alert." >&2
  exit 1
}

resolve_path() {
  case "$LOG_TYPE" in
    run|running)
      if [[ -n "${YASHANDB_RUN_LOG_OVERRIDE:-}" ]]; then
        printf '%s\n' "${YASHANDB_RUN_LOG_OVERRIDE}"
        return
      fi
      local r
      r="$(query_param RUN_LOG_FILE_PATH)"
      if [[ -z "$r" ]]; then
        default_run_log_path
      elif [[ -d "$r" ]]; then
        printf '%s/run.log\n' "${r%/}"
      else
        printf '%s\n' "$r"
      fi
      ;;
    alert)
      if [[ -n "${YASHANDB_ALERT_LOG_OVERRIDE:-}" ]]; then
        printf '%s\n' "${YASHANDB_ALERT_LOG_OVERRIDE}"
        return
      fi
      # Default path is typically \$YASDB_DATA/log/alert/alert.log
      default_alert_log_path
      ;;
    slow)
      if [[ -n "${YASHANDB_SLOW_LOG_OVERRIDE:-}" ]]; then
        printf '%s\n' "${YASHANDB_SLOW_LOG_OVERRIDE}"
        return
      fi
      local s
      s="$(query_param SLOW_LOG_FILE_PATH)"
      s="$(expand_question_mark "$s")"
      if [[ -z "$s" ]]; then
        local base="${YASDB_DATA:?Set YASDB_DATA or configure SLOW_LOG_FILE_PATH}"
        s="${base%/}/log/slow"
      fi
      if [[ -f "$s" ]]; then
        printf '%s\n' "$s"
      else
        pick_latest_in_dir "$s" '*.log'
      fi
      ;;
    audit)
      if [[ -n "${YASHANDB_AUDIT_LOG_OVERRIDE:-}" ]]; then
        printf '%s\n' "${YASHANDB_AUDIT_LOG_OVERRIDE}"
        return
      fi
      local a
      a="$(query_param AUDIT_LOG_FILE_PATH)"
      a="$(expand_question_mark "$a")"
      if [[ -z "$a" ]]; then
        local base="${YASDB_DATA:?Set YASDB_DATA or configure AUDIT_LOG_FILE_PATH}"
        a="${base%/}/log/audit"
      fi
      if [[ -f "$a" ]]; then
        printf '%s\n' "$a"
      else
        pick_latest_in_dir "$a" '*.aud'
      fi
      ;;
    diag|diagnostic)
      if [[ -n "${YASHANDB_DIAG_OVERRIDE:-}" ]]; then
        local o="${YASHANDB_DIAG_OVERRIDE}"
        if [[ -f "$o" ]]; then
          printf '%s\n' "$o"
        else
          resolve_diag_tail_target "$o"
        fi
        return
      fi
      local d
      d="$(query_param DIAGNOSTIC_DEST)"
      d="$(expand_question_mark "$d")"
      if [[ -z "$d" ]]; then
        echo "DIAGNOSTIC_DEST is empty; set YASHANDB_DIAG_OVERRIDE or YASDB_DATA (some installs default to ?/diag)." >&2
        exit 1
      fi
      if [[ -f "$d" ]]; then
        printf '%s\n' "$d"
      else
        resolve_diag_tail_target "$d"
      fi
      ;;
    *)
      echo "Unknown log type: $LOG_TYPE (supported: run alert slow audit diag)" >&2
      exit 1
      ;;
  esac
}

TARGET="$(resolve_path)"

if [[ ! -e "$TARGET" ]]; then
  echo "Path does not exist: $TARGET" >&2
  exit 1
fi

echo "[$LOG_TYPE] tail -n ${TAIL_N} -f -> $TARGET" >&2
exec tail -n "$TAIL_N" -f -- "$TARGET"
