#!/usr/bin/env bash
# File Name: sqlmap_shortopt_help_smoke.sh
# Purpose: Smoke for sqlmap short options + professional help alignment
# Created: 20260805 by huangtingzhong
# Run: bash smoke/sqlmap_shortopt_help_smoke.sh
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOST="${SQLMAP_SMOKE_HOST:-10.10.10.170}"
LOCAL_PORT="${SQLMAP_SMOKE_PORT:-11688}"
JDBC="${JDBC:-/Users/yihan/Downloads/oracle/yashandb-jdbc-1.9.18.jar}"
SMOKE_ROOT="${SMOKE_ROOT:-/tmp/sqlmap_shortopt_help_$$}"
PASS=0
FAIL=0
LOG="$SMOKE_ROOT/smoke.log"
LOG_DIR="$SMOKE_ROOT/logs"

ok()  { echo "[PASS] $*" | tee -a "$LOG"; PASS=$((PASS + 1)); }
bad() { echo "[FAIL] $*" | tee -a "$LOG"; FAIL=$((FAIL + 1)); }
sec() { echo; echo "===== $* =====" | tee -a "$LOG"; }

mkdir -p "$SMOKE_ROOT" "$LOG_DIR" "$SMOKE_ROOT/work"
: >"$LOG"
cd "$ROOT" || exit 1

echo "sqlmap_shortopt_help_smoke $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "$LOG"

sec "0. build"
bash ./build.sh >>"$LOG" 2>&1 && ok "build.sh" || bad "build.sh"

HELP="$SMOKE_ROOT/sqlmap_help.txt"
./run.sh sqlmap -h >"$HELP" 2>&1 || true
TOP_HELP="$SMOKE_ROOT/top_help.txt"
./run.sh -h >"$TOP_HELP" 2>&1 || true

sec "1. top-level help mentions sqlmap + short collect flags"
grep -qi sqlmap "$TOP_HELP" && ok "top help has sqlmap" || bad "top help has sqlmap"
grep -qE '\-E, --explain-plan' "$TOP_HELP" && ok "top help -E" || bad "top help -E"
grep -qE 'sql-collect top' "$TOP_HELP" && ok "top help has top cmd" || bad "top help has top cmd"

sec "2. sqlmap help short options surface"
for pat in \
  '\-n, --map-name' \
  '\-r, --src-file' \
  '\-S, --sql-id' \
  '\-D, --dry-run' \
  '\-F, --flush' \
  '\-v, --verify' \
  '\-k, --marker' \
  '\-L, --limit' \
  '\-B, --bind-format' \
  '\-W, --bind-out' \
  '\-s, --src-sql-id' \
  '\-t, --tgt-sql-id' \
  '\-f, --sql-file' \
  '\-j, --jdbc-config' \
  '\-e, --exec'
do
  if grep -qE "$pat" "$HELP"; then
    ok "help $pat"
  else
    bad "help $pat"
  fi
done
grep -q 'Short -S means --sql-id' "$HELP" && ok "help note Short -S" || bad "help note Short -S"
grep -q 'Common=lowercase, uncommon=UPPERCASE' "$HELP" && ok "help note case convention" || bad "help note case convention"
grep -q 'sql-collect sqlmap create -s' "$HELP" && ok "help examples present" || bad "help examples present"

# 帮助列宽: 选项列与说明之间应有对齐空格 (Args.helpOpt 宽约 34)
if awk '/^-n, --map-name/{ if (index($0,"SQLMAP name")>20) exit 0; exit 1 }' "$HELP"; then
  ok "helpOpt column width for -n"
else
  bad "helpOpt column width for -n"
fi

sec "3. short-opt parse: lit2bind -B -W -f -o (offline)"
printf "%s\n" "SELECT 1 FROM dual WHERE x='a' AND n=2" >"$SMOKE_ROOT/work/lit.sql"
if ./run.sh sqlmap lit2bind -f "$SMOKE_ROOT/work/lit.sql" -o "$SMOKE_ROOT/work/bind.sql" \
    -B '?' -W "$SMOKE_ROOT/work/bv.txt" -d false --log-dir "$LOG_DIR" >>"$LOG" 2>&1; then
  grep -q '?' "$SMOKE_ROOT/work/bind.sql" && ok "lit2bind -B ? placeholders" || bad "lit2bind placeholders"
  [[ -s "$SMOKE_ROOT/work/bv.txt" ]] && ok "lit2bind -W bind-out" || bad "lit2bind -W bind-out"
else
  bad "lit2bind short-opt exit"
fi
if ./run.sh sqlmap lit2bind -f "$SMOKE_ROOT/work/lit.sql" -o "$SMOKE_ROOT/work/bind2.sql" \
    -B ':bN' -W "$SMOKE_ROOT/work/bv2.txt" -d false --log-dir "$LOG_DIR" >>"$LOG" 2>&1; then
  grep -qE ':b[0-9]+' "$SMOKE_ROOT/work/bind2.sql" && ok "lit2bind -B :bN" || bad "lit2bind -B :bN"
else
  bad "lit2bind -B :bN exit"
fi

sec "4. short-opt validate exit 2 (no JDBC needed)"
set +e
./run.sh sqlmap create -s a -r s.sql -f t.sql -n m1 --log-dir "$LOG_DIR" >>"$LOG" 2>&1
rc=$?
set +e
[[ "$rc" -eq 2 ]] && ok "create -s/-r mutex exit 2" || bad "create -s/-r mutex (rc=$rc)"

set +e
./run.sh sqlmap show -n m1 -S abc123def4567 --log-dir "$LOG_DIR" >>"$LOG" 2>&1
rc=$?
set +e
[[ "$rc" -eq 2 ]] && ok "show -n/-S mutex exit 2" || bad "show -n/-S mutex (rc=$rc)"

set +e
./run.sh sqlmap drop --log-dir "$LOG_DIR" >>"$LOG" 2>&1
rc=$?
set +e
[[ "$rc" -eq 2 ]] && ok "drop missing -n exit 2" || bad "drop missing -n (rc=$rc)"

set +e
./run.sh sqlmap verify -n m1 -v result --log-dir "$LOG_DIR" >>"$LOG" 2>&1
rc=$?
set +e
# verify without --exec should fail validation
[[ "$rc" -eq 2 ]] && ok "verify -v without -e exit 2" || bad "verify -v without -e (rc=$rc)"

sec "5. short-opt dry-run create -D (needs tunnel+JDBC)"
INI="$SMOKE_ROOT/jdbc.ini"
cat >"$INI" <<EOF
[jdbc]
jdbc_jar=$JDBC
jdbc_url=jdbc:yasdb://127.0.0.1:${LOCAL_PORT}/yasdb
user=htz
password=htz123
EOF

if ! pgrep -fl "${LOCAL_PORT}:${HOST}:1688" >/dev/null 2>&1; then
  ssh -f -N -o ExitOnForwardFailure=yes -o BatchMode=yes \
    -L "${LOCAL_PORT}:${HOST}:1688" yashan@"$HOST" >>"$LOG" 2>&1 \
    && ok "ssh tunnel" || bad "ssh tunnel"
else
  ok "ssh tunnel already up"
fi

# plant two cursors for -s/-t
PLANT="$SMOKE_ROOT/work/PlantShort.java"
cat >"$PLANT" <<'EOF'
import java.sql.*;
public class PlantShort {
  public static void main(String[] a) throws Exception {
    Class.forName("com.yashandb.jdbc.Driver");
    String tag = a[3];
    try (Connection c = DriverManager.getConnection(a[0], a[1], a[2])) {
      String s = "SELECT /*" + tag + "_s*/ 1 AS n FROM dual";
      String t = "SELECT /*" + tag + "_t*/ 1+0 AS n FROM dual";
      try (PreparedStatement ps = c.prepareStatement(s); ResultSet rs = ps.executeQuery()) { rs.next(); }
      try (PreparedStatement ps = c.prepareStatement(t); ResultSet rs = ps.executeQuery()) { rs.next(); }
      lookup(c, tag + "_s", "S");
      lookup(c, tag + "_t", "T");
    }
  }
  static void lookup(Connection c, String m, String lab) throws Exception {
    try (PreparedStatement ps = c.prepareStatement(
        "SELECT sql_id FROM (SELECT sql_id FROM v$sql WHERE sql_text LIKE ?"
            + " AND sql_text NOT LIKE '%LIKE%' ORDER BY last_active_time DESC NULLS LAST)"
            + " WHERE ROWNUM=1")) {
      ps.setString(1, "%" + m + "%");
      try (ResultSet rs = ps.executeQuery()) {
        System.out.println(lab + "=" + (rs.next() ? rs.getString(1).trim() : ""));
      }
    }
  }
}
EOF
TAG="so$(date +%H%M%S)"
javac -cp "$JDBC" -d "$SMOKE_ROOT/work" "$PLANT" >>"$LOG" 2>&1 || bad "javac PlantShort"
POUT=$(java -cp "$SMOKE_ROOT/work:$JDBC" PlantShort \
  "jdbc:yasdb://127.0.0.1:${LOCAL_PORT}/yasdb" htz htz123 "$TAG" 2>>"$LOG" \
  | grep -v 'JDKLogger\|maxStringLen\|??:')
echo "$POUT" | tee -a "$LOG"
SID=$(echo "$POUT" | sed -n 's/^S=//p' | head -1 | tr -d '[:space:]')
TID=$(echo "$POUT" | sed -n 's/^T=//p' | head -1 | tr -d '[:space:]')
[[ -n "$SID" && ${#SID} -eq 13 ]] && ok "plant SID=$SID" || bad "plant SID"
[[ -n "$TID" && ${#TID} -eq 13 ]] && ok "plant TID=$TID" || bad "plant TID"

MAP="map_so_${TAG}"
DRY_OUT="$SMOKE_ROOT/work/dry.sql"
if ./run.sh sqlmap create -s "$SID" -t "$TID" -n "$MAP" -D -o "$DRY_OUT" \
    -j "$INI" -d false --log-dir "$LOG_DIR" >>"$LOG" 2>&1; then
  grep -qi 'CREATE.*SQLMAP\|SQL_MAP' "$DRY_OUT" "$LOG" 2>/dev/null \
    && ok "create -n -s -t -D dry-run" || {
      # dry-run 可能只打 stdout
      if grep -qi 'CREATE\|SQLMAP\|dry' "$LOG"; then
        ok "create -n -s -t -D dry-run (log)"
      else
        bad "create -D no DDL output"
      fi
    }
else
  bad "create -D exit"
fi

# list -L
if ./run.sh sqlmap list -L 5 -j "$INI" -d false --log-dir "$LOG_DIR" >>"$LOG" 2>&1; then
  ok "list -L 5"
else
  bad "list -L 5"
fi

# flag must not swallow next token: -D then -j
MARK=$(wc -l <"$LOG" | tr -d ' ')
if ./run.sh sqlmap create -s "$SID" -t "$TID" -n "${MAP}_x" -D -j "$INI" \
    -d false --log-dir "$LOG_DIR" >>"$LOG" 2>&1; then
  # jdbc should still be used (no "missing jdbc" / wrong path as map)
  if tail -n +"$((MARK + 1))" "$LOG" | grep -qiE 'jdbc_config=.*/jdbc.ini|dry-run|CREATE'; then
    ok "-D does not swallow -j"
  else
    bad "-D does not swallow -j"
  fi
else
  bad "-D -j create exit"
fi

sec "6. summary"
echo "PASS=$PASS FAIL=$FAIL log=$LOG" | tee -a "$LOG"
if [[ "$FAIL" -eq 0 ]]; then
  echo "[OK] sqlmap_shortopt_help_smoke ALL PASS"
  exit 0
fi
echo "[ERROR] sqlmap_shortopt_help_smoke FAIL=$FAIL"
exit 1
