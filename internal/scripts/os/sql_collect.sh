#!/usr/bin/env bash
# File Name: sql_collect.sh
# Purpose: JDBC SQL collect and replay (Java; companion sql_collect.jar)
# Created: 20260804 by huangtingzhong
#
# ytop uploads this script and sql_collect.jar to the target temp dir, then runs:
#   ytop -f "sql_collect.sh collect --outdir ./sql_collect"
#   ytop -f "sql_collect.sh replay --source gv --sql-id <id>"
#
# Requires on target: Java 8+ (8/11/17/21 OK), YashanDB JDBC jar
# (JDBC_JAR or jdbc_replay.ini jdbc_jar=).
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
APP_JAR="${SQL_COLLECT_JAR:-$DIR/sql_collect.jar}"

# classpath separator: Windows Git Bash / Cygwin use ';'
case "$(uname -s 2>/dev/null || echo unknown)" in
  CYGWIN*|MINGW*|MSYS*) CP_SEP=';' ;;
  *) CP_SEP=':' ;;
esac

java_major() {
  local line ver
  line="$(java -version 2>&1 | head -n 1)"
  ver="$(printf '%s\n' "$line" | sed -n 's/.*version "\([^"]*\)".*/\1/p')"
  if [ -z "$ver" ]; then
    echo 0
    return
  fi
  case "$ver" in
    1.*) echo "$ver" | cut -d. -f2 ;;
    *) echo "$ver" | cut -d. -f1 | tr -cd '0-9' ;;
  esac
}

require_java8() {
  local maj
  if ! command -v java >/dev/null 2>&1; then
    echo "java not found on PATH" >&2
    exit 1
  fi
  maj="$(java_major)"
  if [ -z "$maj" ] || [ "$maj" -lt 8 ] 2>/dev/null; then
    echo "sql-collect requires Java 8 or newer (found major=${maj:-?})" >&2
    java -version >&2 || true
    exit 1
  fi
}

resolve_jdbc_jar() {
  if [ -n "${JDBC_JAR:-}" ] && [ -f "$JDBC_JAR" ]; then
    echo "$JDBC_JAR"
    return 0
  fi
  # Optional: parse jdbc_jar= from first matching ini (cwd then script dir).
  local ini candidate
  for ini in "${JDBC_CONFIG:-}" ./jdbc_replay.ini "$DIR/jdbc_replay.ini"; do
    [ -n "$ini" ] || continue
    [ -f "$ini" ] || continue
    candidate="$(awk -F= '
      BEGIN { IGNORECASE=1 }
      /^[[:space:]]*\[/ { in_jdbc=0 }
      /^[[:space:]]*\[jdbc\]/ { in_jdbc=1; next }
      in_jdbc && $1 ~ /^[[:space:]]*jdbc_jar[[:space:]]*$/ {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2)
        print $2
        exit
      }
    ' "$ini" 2>/dev/null || true)"
    if [ -n "$candidate" ] && [ -f "$candidate" ]; then
      echo "$candidate"
      return 0
    fi
  done
  for candidate in \
    "$DIR"/yashandb-jdbc*.jar \
    /opt/yashandb/jdbc/yashandb-jdbc*.jar \
    "$HOME"/Downloads/oracle/yashandb-jdbc*.jar
  do
    if [ -f "$candidate" ]; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

if [ ! -f "$APP_JAR" ]; then
  echo "sql_collect.jar not found: $APP_JAR (ytop should upload companion jar)" >&2
  exit 1
fi

require_java8

JDBC_JAR_RESOLVED="$(resolve_jdbc_jar)" || {
  echo "YashanDB JDBC jar not found; set JDBC_JAR or jdbc_jar= in jdbc_replay.ini" >&2
  exit 1
}

CP="${APP_JAR}${CP_SEP}${JDBC_JAR_RESOLVED}"
exec java -Djava.net.preferIPv4Stack=true -cp "$CP" com.yashan.sqlcollect.Main "$@"
