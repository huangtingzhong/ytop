#!/usr/bin/env bash
# Local-dev launcher for tool/sql-collect (prefer build/classes, else os jar).
# Requires Java 8+ (same as sql_collect.sh).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
OS_SH="$ROOT/../../internal/scripts/os/sql_collect.sh"
CLASSES="$ROOT/build/classes"
JDBC_JAR="${JDBC_JAR:-/Users/yihan/Downloads/oracle/yashandb-jdbc-1.9.18.jar}"

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

need_java() {
  local maj
  maj="$(java_major)"
  if [ -z "$maj" ] || [ "$maj" -lt 8 ] 2>/dev/null; then
    echo "sql-collect requires Java 8 or newer; java -version:" >&2
    java -version >&2 || true
    exit 1
  fi
}

if ! command -v java >/dev/null 2>&1; then
  echo "java not found on PATH" >&2
  exit 1
fi
need_java

if [ -d "$CLASSES" ] && [ -f "$CLASSES/com/yashan/sqlcollect/Main.class" ]; then
  if [ ! -f "$JDBC_JAR" ]; then
    echo "JDBC jar not found: $JDBC_JAR (set JDBC_JAR=...)" >&2
    exit 1
  fi
  exec java -Djava.net.preferIPv4Stack=true -cp "${CLASSES}${CP_SEP}${JDBC_JAR}" com.yashan.sqlcollect.Main "$@"
fi

if [ -x "$OS_SH" ] || [ -f "$OS_SH" ]; then
  export SQL_COLLECT_JAR="${SQL_COLLECT_JAR:-$ROOT/../../internal/scripts/os/sql_collect.jar}"
  export JDBC_JAR
  exec bash "$OS_SH" "$@"
fi

echo "Nothing to run; ./build.sh first" >&2
exit 1
