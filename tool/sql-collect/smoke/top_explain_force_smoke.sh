#!/usr/bin/env bash
# File Name: top_explain_force_smoke.sh
# Purpose: Smoke for collect -s/-E and top (reports rank + EXPLAIN PLAN gate)
# Created: 20260805 by huangtingzhong
# Run (Mac+tunnel): bash smoke/top_explain_force_smoke.sh
# Run on 170:       bash top_explain_force_smoke.sh /tmp/ytop_linux_arm64
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOST="${HOST:-10.10.10.170}"
LOCAL_PORT="${LOCAL_PORT:-11688}"
JDBC="${JDBC:-/Users/yihan/Downloads/oracle/yashandb-jdbc-1.9.18.jar}"
YTOP_REMOTE="${1:-}"
SMOKE_ROOT="${SMOKE_ROOT:-/tmp/top_explain_force_smoke_$$}"
PASS=0
FAIL=0
LOG="$SMOKE_ROOT/smoke.log"
LOG_DIR="$SMOKE_ROOT/logs"
OUTBASE="$SMOKE_ROOT/outdir"
TAG="tef$(date +%H%M%S)"

ok()  { echo "[PASS] $*" | tee -a "$LOG"; PASS=$((PASS + 1)); }
bad() { echo "[FAIL] $*" | tee -a "$LOG"; FAIL=$((FAIL + 1)); }
sec() { echo; echo "===== $* =====" | tee -a "$LOG"; }

mkdir -p "$OUTBASE" "$LOG_DIR" "$SMOKE_ROOT/work"
: >"$LOG"

echo "top_explain_force_smoke $(date '+%Y-%m-%d %H:%M:%S') tag=$TAG" | tee -a "$LOG"
echo "root=$ROOT smoke_root=$SMOKE_ROOT" | tee -a "$LOG"

run_collect() {
  # args: collect 选项; stdout/stderr 同时进 LOG 与调用方管道
  if [[ -n "$YTOP_REMOTE" ]]; then
    "$YTOP_REMOTE" -f "sql_collect.sh collect $* --log-dir $LOG_DIR" 2>&1 | tee -a "$LOG"
    return "${PIPESTATUS[0]}"
  fi
  "$ROOT/run.sh" collect "$@" --log-dir "$LOG_DIR" 2>&1 | tee -a "$LOG"
  return "${PIPESTATUS[0]}"
}

run_top() {
  if [[ -n "$YTOP_REMOTE" ]]; then
    "$YTOP_REMOTE" -f "sql_collect.sh top $* --log-dir $LOG_DIR" 2>&1 | tee -a "$LOG"
    return "${PIPESTATUS[0]}"
  fi
  "$ROOT/run.sh" top "$@" --log-dir "$LOG_DIR" 2>&1 | tee -a "$LOG"
  return "${PIPESTATUS[0]}"
}

latest_run() {
  local base="$1"
  local d
  d=$(ls -1d "$base"/[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9] 2>/dev/null | sort | tail -1 || true)
  if [[ -n "$d" ]]; then echo "$d"; else echo "$base"; fi
}

# --- mode: local (default) needs build+tunnel+jdbc ini ---
if [[ -z "$YTOP_REMOTE" ]]; then
  sec "0. build + tunnel + jdbc ini"
  if ! bash "$ROOT/build.sh" >>"$LOG" 2>&1; then
    bad "build.sh"
  else
    ok "build.sh"
  fi
  if ! pgrep -fl "${LOCAL_PORT}:${HOST}:1688" >/dev/null 2>&1; then
    ssh -f -N -o ExitOnForwardFailure=yes -o BatchMode=yes \
      -L "${LOCAL_PORT}:${HOST}:1688" yashan@"$HOST" >>"$LOG" 2>&1 \
      && ok "ssh tunnel :$LOCAL_PORT" || bad "ssh tunnel"
  else
    ok "ssh tunnel already up"
  fi
  INI="$SMOKE_ROOT/jdbc.ini"
  cat >"$INI" <<EOF
[jdbc]
jdbc_jar=$JDBC
jdbc_url=jdbc:yasdb://127.0.0.1:${LOCAL_PORT}/yasdb
user=htz
password=htz123
EOF
  ok "jdbc.ini"
  HELP_OUT="$SMOKE_ROOT/help.txt"
  "$ROOT/run.sh" -h >"$HELP_OUT" 2>&1 || true
  "$ROOT/run.sh" top -h >>"$HELP_OUT" 2>&1 || true
else
  INI="${INI:-$HOME/jdbc_replay.ini}"
  HELP_OUT="$SMOKE_ROOT/help.txt"
  "$YTOP_REMOTE" -f "sql_collect.sh -h" >"$HELP_OUT" 2>&1 || true
  "$YTOP_REMOTE" -f "sql_collect.sh top -h" >>"$HELP_OUT" 2>&1 || true
  ok "remote ytop=$YTOP_REMOTE ini=$INI"
fi

sec "1. CLI help surface"
grep -qE '\-E, --explain-plan' "$HELP_OUT" && ok "help has -E/--explain-plan" || bad "help has -E/--explain-plan"
grep -qE 'Collect ONLY these sql_id' "$HELP_OUT" && ok "help force sql-id wording" || bad "help force sql-id wording"
grep -qE 'sql-collect top' "$HELP_OUT" && ok "help has top command" || bad "help has top command"
grep -qE 'db_time' "$HELP_OUT" && ok "top help mentions db_time" || bad "top help mentions db_time"

sec "2. plant SELECT + INSERT cursors"
PLANT_JAVA="$SMOKE_ROOT/work/PlantTef.java"
cat >"$PLANT_JAVA" <<'EOF'
import java.sql.*;
public class PlantTef {
  public static void main(String[] a) throws Exception {
    Class.forName("com.yashandb.jdbc.Driver");
    String tag = a[3];
    try (Connection c = DriverManager.getConnection(a[0], a[1], a[2])) {
      String q = "SELECT /*" + tag + "_sel*/ COUNT(*) AS c FROM dual";
      try (PreparedStatement ps = c.prepareStatement(q); ResultSet rs = ps.executeQuery()) {
        rs.next();
      }
      try {
        try (PreparedStatement ps = c.prepareStatement(
            "INSERT /*" + tag + "_ins*/ INTO biz_replay_demo(id,note,amt) VALUES (?,?,?)")) {
          ps.setLong(1, 880000L + (System.currentTimeMillis() % 100000));
          ps.setString(2, tag);
          ps.setInt(3, 1);
          ps.executeUpdate();
        }
      } catch (SQLException e) {
        System.out.println("INS_WARN=" + e.getMessage().split("\n")[0]);
      }
      lookup(c, tag + "_sel", "SEL");
      lookup(c, tag + "_ins", "INS");
    }
  }
  static void lookup(Connection c, String marker, String label) throws Exception {
    try (PreparedStatement ps = c.prepareStatement(
        "SELECT sql_id, command_type FROM ("
            + " SELECT sql_id, command_type FROM v$sql"
            + " WHERE sql_text LIKE ? AND sql_text NOT LIKE '%LIKE%'"
            + " AND sql_text NOT LIKE '%sql_fulltext%'"
            + " ORDER BY last_active_time DESC NULLS LAST) WHERE ROWNUM=1")) {
      ps.setString(1, "%" + marker + "%");
      try (ResultSet rs = ps.executeQuery()) {
        if (rs.next()) {
          System.out.println(label + "_ID=" + rs.getString(1));
          System.out.println(label + "_CT=" + rs.getInt(2));
        } else {
          System.out.println(label + "_ID=");
        }
      }
    }
  }
}
EOF

if [[ -z "$YTOP_REMOTE" ]]; then
  javac -cp "$JDBC" -d "$SMOKE_ROOT/work" "$PLANT_JAVA" >>"$LOG" 2>&1 || bad "javac PlantTef"
  PLANT_OUT=$(java -cp "$SMOKE_ROOT/work:$JDBC" PlantTef \
    "jdbc:yasdb://127.0.0.1:${LOCAL_PORT}/yasdb" htz htz123 "$TAG" 2>>"$LOG" | grep -v 'JDKLogger\|maxStringLen\|??:')
else
  # 170: use yasql to plant
  export YASDB_HOME="${YASDB_HOME:-/home/yashan/.yasboot/yashandb_yasdb_home}"
  export PATH="$YASDB_HOME/bin:$PATH"
  yasql -S htz/htz123 >>"$LOG" 2>&1 <<EOF
SELECT /*${TAG}_sel*/ COUNT(*) AS c FROM dual;
INSERT /*${TAG}_ins*/ INTO biz_replay_demo(id,note,amt) VALUES (880001,'${TAG}',1);
EOF
  PLANT_OUT=$(yasql -S htz/htz123 2>>"$LOG" <<EOF | tr -d '\r'
SET FEEDBACK OFF PAGESIZE 0
SELECT 'SEL_ID='||sql_id||CHR(10)||'SEL_CT='||command_type
  FROM (SELECT sql_id, command_type FROM v\$sql
         WHERE sql_text LIKE '%${TAG}_sel%' AND sql_text NOT LIKE '%LIKE%'
         ORDER BY last_active_time DESC NULLS LAST) WHERE ROWNUM=1;
SELECT 'INS_ID='||sql_id||CHR(10)||'INS_CT='||command_type
  FROM (SELECT sql_id, command_type FROM v\$sql
         WHERE sql_text LIKE '%${TAG}_ins%' AND sql_text NOT LIKE '%LIKE%'
         ORDER BY last_active_time DESC NULLS LAST) WHERE ROWNUM=1;
EOF
)
fi
echo "$PLANT_OUT" | tee -a "$LOG"
# yasql 可能在数值后补空格, 统一 trim
SEL_ID=$(echo "$PLANT_OUT" | sed -n 's/^SEL_ID=//p' | head -1 | tr -d '[:space:]')
INS_ID=$(echo "$PLANT_OUT" | sed -n 's/^INS_ID=//p' | head -1 | tr -d '[:space:]')
SEL_CT=$(echo "$PLANT_OUT" | sed -n 's/^SEL_CT=//p' | head -1 | tr -d '[:space:]')
INS_CT=$(echo "$PLANT_OUT" | sed -n 's/^INS_CT=//p' | head -1 | tr -d '[:space:]')

[[ -n "$SEL_ID" ]] && ok "plant SELECT sql_id=$SEL_ID ct=$SEL_CT" || bad "plant SELECT sql_id"
[[ "$SEL_CT" == "1" || "$SEL_CT" == "6" ]] && ok "SELECT command_type query" || bad "SELECT command_type query got=$SEL_CT"
[[ -n "$INS_ID" ]] && ok "plant INSERT sql_id=$INS_ID ct=$INS_CT" || bad "plant INSERT sql_id"
[[ "$INS_CT" == "2" ]] && ok "INSERT command_type=2" || bad "INSERT command_type got=$INS_CT"

sec "3. collect -s SELECT -E (explain on)"
OUT1="$OUTBASE/sel_e"
mkdir -p "$OUT1"
if run_collect -s "$SEL_ID" -E -K -n -o "$OUT1" -j "$INI" -d false --report-timeout 180; then
  ok "collect SELECT -E rc=0"
else
  bad "collect SELECT -E rc!=0"
fi
RUN1=$(latest_run "$OUT1")
REP1="$RUN1/reports/${SEL_ID}.txt"
if [[ -f "$REP1" ]]; then
  ok "report exists $REP1"
  grep -q 'EXPLAIN PLAN (optional' "$REP1" && ok "report has EXPLAIN section" || bad "report has EXPLAIN section"
  grep -q 'command_type=1' "$REP1" && ok "explain command_type=1" || bad "explain command_type=1"
  grep -qE '\|[[:space:]]*[0-9]+[[:space:]]*\|.*SELECT STATEMENT|\| Id \|' "$REP1" \
    && ok "explain has Id/position table" || bad "explain has Id/position table"
  grep -q 'PLAN from v\$sql_plan\|PLAN from v$sql_plan' "$REP1" \
    && ok "still has v\$sql_plan section" || bad "still has v\$sql_plan section"
else
  bad "report missing for SELECT"
fi
grep -q 'explain_plan=true' "$LOG" && ok "log explain_plan=true" || bad "log explain_plan=true"
grep -q "explain ok sql_id=$SEL_ID" "$LOG" && ok "log explain ok" || bad "log explain ok"

sec "4. collect -s INSERT -E (must skip explain body)"
OUT2="$OUTBASE/ins_e"
mkdir -p "$OUT2"
if run_collect -s "$INS_ID" -E -K -n -o "$OUT2" -j "$INI" -d false --report-timeout 180; then
  ok "collect INSERT -E rc=0"
else
  # export may fail if insert text not replayable; still check report/skipped
  bad "collect INSERT -E rc!=0 (see log)"
fi
RUN2=$(latest_run "$OUT2")
REP2="$RUN2/reports/${INS_ID}.txt"
[[ ! -f "$REP2" ]] && REP2="$RUN2/skipped/${INS_ID}.txt"
if [[ -f "$REP2" ]]; then
  ok "INSERT report/skipped exists"
  if grep -q 'EXPLAIN PLAN (optional' "$REP2"; then
    grep -q '\[SKIP\] explain: non-query' "$REP2" \
      && ok "INSERT explain skipped in report" || bad "INSERT should SKIP explain"
    grep -q 'Operation type' "$REP2" \
      && bad "INSERT must not have explain plan table" || ok "INSERT no explain plan table"
  else
    # if report incomplete without explain block - still accept skip log
    grep -q "explain skip sql_id=$INS_ID" "$LOG" \
      && ok "log explain skip INSERT" || bad "no explain section and no skip log"
  fi
else
  bad "INSERT report/skipped missing"
fi
grep -q "explain skip sql_id=$INS_ID" "$LOG" && ok "log explain skip INSERT" || true

sec "5. collect -s SELECT without -E (default off)"
OUT3="$OUTBASE/sel_off"
mkdir -p "$OUT3"
# re-plant select to keep cursor warm
if [[ -z "$YTOP_REMOTE" ]]; then
  java -cp "$SMOKE_ROOT/work:$JDBC" PlantTef \
    "jdbc:yasdb://127.0.0.1:${LOCAL_PORT}/yasdb" htz htz123 "${TAG}b" >/dev/null 2>&1 || true
  SEL_ID2=$(java -cp "$SMOKE_ROOT/work:$JDBC" PlantTef \
    "jdbc:yasdb://127.0.0.1:${LOCAL_PORT}/yasdb" htz htz123 "${TAG}b" 2>/dev/null \
    | grep '^SEL_ID=' | head -1 | cut -d= -f2)
  [[ -n "$SEL_ID2" ]] && SEL_ID="$SEL_ID2"
fi
if run_collect -s "$SEL_ID" -K -n -o "$OUT3" -j "$INI" -d false --report-timeout 180; then
  ok "collect SELECT default rc=0"
else
  bad "collect SELECT default rc!=0"
fi
RUN3=$(latest_run "$OUT3")
REP3="$RUN3/reports/${SEL_ID}.txt"
if [[ -f "$REP3" ]]; then
  if grep -q 'EXPLAIN PLAN (optional' "$REP3"; then
    bad "default collect must not include EXPLAIN section"
  else
    ok "default collect has no EXPLAIN section"
  fi
else
  bad "default SELECT report missing"
fi
grep -q 'explain_plan=false' "$LOG" && ok "log explain_plan=false" || bad "log explain_plan=false"

sec "6. top rank reports"
# ensure RUN1 has at least one report; also copy into a flat top dir with multiple if needed
TOPDIR="$OUTBASE/top_src"
mkdir -p "$TOPDIR/reports"
cp -f "$RUN1/reports/"*.txt "$TOPDIR/reports/" 2>/dev/null || true
cp -f "$RUN3/reports/"*.txt "$TOPDIR/reports/" 2>/dev/null || true
NREP=$(ls "$TOPDIR/reports"/*.txt 2>/dev/null | wc -l | tr -d ' ')
[[ "$NREP" -ge 1 ]] && ok "top input reports=$NREP" || bad "top input reports=$NREP"
CSV="$SMOKE_ROOT/top.csv"
TOP_OUT="$SMOKE_ROOT/top.out"
if run_top -o "$TOPDIR" -L 20 --csv "$CSV" -d false >"$TOP_OUT" 2>&1; then
  cat "$TOP_OUT" >>"$LOG"
  ok "top rc=0"
else
  cat "$TOP_OUT" >>"$LOG"
  bad "top rc!=0"
fi
grep -q '^RANK' "$TOP_OUT" && ok "top has RANK header" || bad "top has RANK header"
grep -q '^----' "$TOP_OUT" && ok "top has separator line" || bad "top has separator line"
grep -q 'parse_fail=0' "$TOP_OUT" "$LOG" && ok "top parse_fail=0" || bad "top parse_fail=0"
grep -q 'sort=db_time' "$TOP_OUT" "$LOG" && ok "top default sort db_time" || bad "top default sort db_time"
[[ -f "$CSV" ]] && grep -q 'db_time_us' "$CSV" && ok "top csv written" || bad "top csv written"
# alignment: header RANK and first data line should both start with RANK/spaces+digit column
if awk '/^RANK /{h=1; next} h && /^[0-9 ]+[0-9]/{print; exit}' "$TOP_OUT" | grep -q .; then
  ok "top data row present"
else
  bad "top data row present"
fi

sec "7. summary"
echo "PASS=$PASS FAIL=$FAIL log=$LOG" | tee -a "$LOG"
if [[ "$FAIL" -eq 0 ]]; then
  echo "[OK] top_explain_force_smoke ALL PASS"
  exit 0
fi
echo "[ERROR] top_explain_force_smoke FAIL=$FAIL"
exit 1
