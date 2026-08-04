#!/usr/bin/env bash
# Build sql-collect Java sources (no Maven) for Java 8 bytecode; install into ytop os/.
# Compilers: JDK 8 / 11 / 17 / 21 / 23+ (prefer --release 8 when available).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
SRC="$ROOT/src"
OUT="$ROOT/build/classes"
OS_DIR="$ROOT/../../internal/scripts/os"
JDBC_JAR="${JDBC_JAR:-/Users/yihan/Downloads/oracle/yashandb-jdbc-1.9.18.jar}"
# 目标字节码主版本: 52 = Java 8
TARGET_RELEASE="${TARGET_RELEASE:-8}"
TARGET_MAJOR=52

mkdir -p "$OUT"
SRC_LIST="$ROOT/build/sources.list"
mkdir -p "$ROOT/build"

# 将 sql.sql 嵌入为 Java 源码 (不打包独立 sql_report.sql)
UPSTREAM_SQL="$ROOT/../../internal/scripts/sql/yashandb/sql.sql"
GEN_JAVA="$SRC/com/yashan/sqlcollect/collect/SqlReportScript.java"
GEN_PY="$ROOT/gen_sql_report_script.py"
if [ ! -f "$UPSTREAM_SQL" ]; then
  echo "ERROR: upstream sql missing: $UPSTREAM_SQL" >&2
  exit 1
fi
python3 "$GEN_PY" "$UPSTREAM_SQL" "$GEN_JAVA"

# 不再维护/打包独立资源文件
rm -f "$ROOT/resources/sql_report.sql"
rmdir "$ROOT/resources" 2>/dev/null || true

: >"$SRC_LIST"
FILE_COUNT=0
while IFS= read -r f; do
  printf '%s\n' "$f" >>"$SRC_LIST"
  FILE_COUNT=$((FILE_COUNT + 1))
done < <(find "$SRC" -name '*.java' | LC_ALL=C sort)

if [ "$FILE_COUNT" = "0" ]; then
  echo "No Java sources under $SRC" >&2
  exit 1
fi

CP="$JDBC_JAR"
if [ -f "$JDBC_JAR" ]; then
  CP="$JDBC_JAR"
else
  echo "WARN: JDBC jar not found at $JDBC_JAR (compile may fail on jdbc imports)" >&2
fi

JAVAC="${JAVAC:-javac}"
echo "javac: $($JAVAC -version 2>&1 || true)"
echo "target: Java $TARGET_RELEASE (class major $TARGET_MAJOR)"

# Prefer --release (JDK 9+); fall back to -source/-target for JDK 8 javac.
if "$JAVAC" -help 2>&1 | grep -q -- '--release'; then
  "$JAVAC" -encoding UTF-8 --release "$TARGET_RELEASE" -cp "$CP" -d "$OUT" @"$SRC_LIST"
elif "$JAVAC" -help 2>&1 | grep -q -- '-source'; then
  "$JAVAC" -encoding UTF-8 -source "$TARGET_RELEASE" -target "$TARGET_RELEASE" -cp "$CP" -d "$OUT" @"$SRC_LIST"
else
  echo "ERROR: javac does not support --release or -source/-target" >&2
  exit 1
fi

# 确认 jar 内无独立 sql_report.sql
if [ -f "$OUT/sql_report.sql" ]; then
  rm -f "$OUT/sql_report.sql"
fi

# 校验 class 主版本 = 52 (防止误用更高 --release)
verify_class_major() {
  local root="$1" expect="$2"
  if command -v python3 >/dev/null 2>&1; then
    TARGET_RELEASE="$TARGET_RELEASE" python3 - "$root" "$expect" <<'PY'
import os, struct, sys
root, expect = sys.argv[1], int(sys.argv[2])
bad = []
n = 0
for dp, _, fs in os.walk(root):
    for f in fs:
        if not f.endswith('.class'):
            continue
        n += 1
        p = os.path.join(dp, f)
        with open(p, 'rb') as fh:
            magic, minor, major = struct.unpack('>IHH', fh.read(8))
        if magic != 0xCAFEBABE or major != expect:
            bad.append((p, major))
if bad:
    sys.stderr.write('ERROR: classfile major mismatch (expected %d):\n' % expect)
    for p, maj in bad[:10]:
        sys.stderr.write('  %s major=%s\n' % (p, maj))
    sys.exit(1)
print('Verified %d class files major=%d (Java %s)' % (
    n, expect, os.environ.get('TARGET_RELEASE', '8')))
PY
    return $?
  fi
  local sample="$root/com/yashan/sqlcollect/Main.class"
  if [ -f "$sample" ] && command -v javap >/dev/null 2>&1; then
    local maj
    maj=$(javap -verbose -classpath "$root" com.yashan.sqlcollect.Main 2>/dev/null \
      | awk '/major version:/ {print $3; exit}')
    if [ "$maj" != "$expect" ]; then
      echo "ERROR: Main.class major version=$maj expected=$expect" >&2
      return 1
    fi
    echo "Verified Main.class major=$maj (javap fallback)"
    return 0
  fi
  echo "WARN: skip class major verify (need python3 or javap)" >&2
  return 0
}
verify_class_major "$OUT" "$TARGET_MAJOR"
echo "Built $FILE_COUNT classes -> $OUT"

mkdir -p "$ROOT/build"
JAR="$ROOT/build/sql-collect.jar"
MF="$ROOT/build/MANIFEST.MF"
{
  echo "Manifest-Version: 1.0"
  echo "Main-Class: com.yashan.sqlcollect.Main"
  echo "Created-By: sql-collect build.sh"
  echo "Build-Target-Java: $TARGET_RELEASE"
  echo "Implementation-Version: 2.0.0-java"
} >"$MF"
jar cfm "$JAR" "$MF" -C "$OUT" .
echo "Jar (classes only, no JDBC): $JAR"

# Install into ytop embedded OS scripts (go:embed os)
if [ -d "$OS_DIR" ]; then
  cp "$JAR" "$OS_DIR/sql_collect.jar"
  # Keep os/sql_collect.sh as source of truth; sync tool/run.sh from it for local dev.
  if [ -f "$OS_DIR/sql_collect.sh" ]; then
    cat > "$ROOT/run.sh" <<'EOF'
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
EOF
    chmod +x "$ROOT/run.sh"
  fi
  echo "Installed: $OS_DIR/sql_collect.jar"
else
  echo "WARN: OS_DIR missing: $OS_DIR" >&2
fi
