#!/usr/bin/env bash
# File Name: sql_collect.sh
# Purpose: JDBC SQL collect, replay, and sqlmap toolkit (Java; companion sql_collect.jar)
# Created: 20260804 by huangtingzhong
# Updated: 20260805 by huangtingzhong (aligned -h; -h/--help skips JDBC anywhere in argv)
#
# ytop uploads this script and sql_collect.jar to the target temp dir, then runs:
#   ytop -f "sql_collect.sh collect --outdir ./sql_collect"
#   ytop -f "sql_collect.sh replay --source gv --sql-id <id>"
#
# Requires on target: Java 8+ (8/11/17/21 OK), YashanDB JDBC jar
# (JDBC_JAR or jdbc_jar= in jdbc_replay.ini). Help/version do not need the JDBC jar.
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
    echo "ERROR: java not found on PATH." >&2
    echo "  sql_collect needs Java 8+ on the target host (ytop -f runs a non-login SSH shell)." >&2
    echo "  Fix: install a JRE/JDK, or export PATH so 'java' is visible in non-interactive SSH." >&2
    echo "  Check: ssh <user@host> 'command -v java; java -version; echo PATH=\$PATH'" >&2
    exit 1
  fi
  maj="$(java_major)"
  if [ -z "$maj" ] || [ "$maj" -lt 8 ] 2>/dev/null; then
    echo "ERROR: sql_collect requires Java 8 or newer (found major=${maj:-?})." >&2
    java -version >&2 || true
    exit 1
  fi
}

# True when argv is help/version/init-config only (no JDBC driver needed on classpath).
args_skip_jdbc() {
  local a
  if [ "$#" -eq 0 ]; then
    return 1
  fi
  case "$1" in
    -h|--help|-V|--version)
      return 0
      ;;
    top)
      # top only scans local reports/*.txt
      return 0
      ;;
  esac
  for a in "$@"; do
    case "$a" in
      -h|--help|-V|--version|--init-config)
        return 0
        ;;
    esac
  done
  return 1
}

# Read jdbc_jar= under [jdbc] from an ini; empty if absent.
read_jdbc_jar_from_ini() {
  local ini="$1"
  [ -f "$ini" ] || return 0
  awk -F= '
    BEGIN { IGNORECASE=1 }
    /^[[:space:]]*\[/ { in_jdbc=0 }
    /^[[:space:]]*\[jdbc\]/ { in_jdbc=1; next }
    in_jdbc && $1 ~ /^[[:space:]]*jdbc_jar[[:space:]]*$/ {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2)
      print $2
      exit
    }
  ' "$ini" 2>/dev/null || true
}

# Print resolved jar path on stdout; diagnostics on failure go to stderr via die_jdbc.
resolve_jdbc_jar() {
  local ini candidate

  if [ -n "${JDBC_JAR:-}" ]; then
    if [ -f "$JDBC_JAR" ]; then
      echo "$JDBC_JAR"
      return 0
    fi
    echo "HINT: JDBC_JAR is set but file missing: $JDBC_JAR" >&2
  fi

  for ini in "${JDBC_CONFIG:-}" ./jdbc_replay.ini "$DIR/jdbc_replay.ini"; do
    [ -n "$ini" ] || continue
    [ -f "$ini" ] || continue
    candidate="$(read_jdbc_jar_from_ini "$ini")"
    if [ -z "$candidate" ]; then
      echo "HINT: $ini has no jdbc_jar= under [jdbc]" >&2
      continue
    fi
    if [ -f "$candidate" ]; then
      echo "$candidate"
      return 0
    fi
    echo "HINT: $ini jdbc_jar= points to missing file: $candidate" >&2
  done

  for candidate in \
    "$DIR"/yashandb-jdbc*.jar \
    /opt/yashandb/jdbc/yashandb-jdbc*.jar \
    "$HOME"/Downloads/oracle/yashandb-jdbc*.jar
  do
    # glob may stay literal when no match
    [ -f "$candidate" ] || continue
    echo "$candidate"
    return 0
  done
  return 1
}

die_jdbc_missing() {
  echo "ERROR: YashanDB JDBC jar not found." >&2
  echo "  sql_collect needs the driver jar on the target host classpath." >&2
  echo "  Fix (pick one):" >&2
  echo "    1) export JDBC_JAR=/absolute/path/to/yashandb-jdbc-*.jar" >&2
  echo "    2) put jdbc_jar=/absolute/path/... under [jdbc] in ./jdbc_replay.ini" >&2
  echo "       (generate template: sql_collect.sh replay --init-config)" >&2
  echo "    3) copy yashandb-jdbc-*.jar next to sql_collect.jar, or to" >&2
  echo "       /opt/yashandb/jdbc/yashandb-jdbc-*.jar" >&2
  echo "  Then re-run, e.g.:" >&2
  echo "    ytop -t <host> -f \"sql_collect.sh -h\"" >&2
  echo "    ytop -t <host> -f \"sql_collect.sh collect --jdbc-config ./jdbc_replay.ini --outdir ./sql_collect --count 1\"" >&2
  exit 1
}

if [ ! -f "$APP_JAR" ]; then
  echo "ERROR: sql_collect.jar not found: $APP_JAR" >&2
  echo "  ytop should upload the companion jar with this script (internal/scripts/os/sql_collect.jar)." >&2
  exit 1
fi

require_java8

if args_skip_jdbc "$@"; then
  CP="$APP_JAR"
else
  JDBC_JAR_RESOLVED="$(resolve_jdbc_jar)" || die_jdbc_missing
  CP="${APP_JAR}${CP_SEP}${JDBC_JAR_RESOLVED}"
fi

exec java -Djava.net.preferIPv4Stack=true -cp "$CP" com.yashan.sqlcollect.Main "$@"
