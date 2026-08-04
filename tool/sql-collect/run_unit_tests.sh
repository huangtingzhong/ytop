#!/usr/bin/env bash
# Compile and run pure-logic unit tests (main + assert, no Maven/JUnit jar).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
TEST="$ROOT/test"
OUT="$ROOT/build/classes"
TOUT="$ROOT/build/test-classes"
JDBC_JAR="${JDBC_JAR:-/Users/yihan/Downloads/oracle/yashandb-jdbc-1.9.18.jar}"

if [ ! -d "$OUT" ]; then
  echo "ERROR: $OUT missing; run ./build.sh first" >&2
  exit 1
fi

mkdir -p "$TOUT"
CP="$OUT"
if [ -f "$JDBC_JAR" ]; then
  CP="$OUT:$JDBC_JAR"
fi

SRC_LIST="$ROOT/build/test-sources.list"
find "$TEST" -name '*Test.java' | LC_ALL=C sort >"$SRC_LIST"
if [ ! -s "$SRC_LIST" ]; then
  echo "No *Test.java under $TEST" >&2
  exit 1
fi

if javac -help 2>&1 | grep -q -- '--release'; then
  javac -encoding UTF-8 --release 8 -cp "$CP" -d "$TOUT" @"$SRC_LIST"
else
  javac -encoding UTF-8 -source 8 -target 8 -cp "$CP" -d "$TOUT" @"$SRC_LIST"
fi

FAIL=0
while IFS= read -r classfile; do
  rel="${classfile#$TOUT/}"
  cls="${rel%.class}"
  cls=$(echo "$cls" | tr '/' '.')
  case "$cls" in
    *Test) ;;
    *) continue ;;
  esac
  echo "==> $cls"
  if ! java -cp "$TOUT:$CP" "$cls"; then
    echo "FAIL: $cls" >&2
    FAIL=1
  fi
done < <(find "$TOUT" -name '*Test.class' | LC_ALL=C sort)

if [ "$FAIL" -ne 0 ]; then
  echo "Unit tests FAILED" >&2
  exit 1
fi
echo "Unit tests PASSED"
