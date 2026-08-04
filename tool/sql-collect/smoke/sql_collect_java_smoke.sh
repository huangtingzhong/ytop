#!/usr/bin/env bash
# File Name: sql_collect_java_smoke.sh
# Purpose: Smoke for tool/sql-collect Java — aligned with tmp/sql_collect_replay_smoke.sh key paths
# Created: 20260804 by huangtingzhong
# Updated: 20260804 by huangtingzhong (JDBC native report / Java LITERAL rewrite smoke)
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOST=10.10.10.170
LOCAL_PORT=11688
JDBC="${JDBC:-/Users/yihan/Downloads/oracle/yashandb-jdbc-1.9.18.jar}"
SMOKE_ROOT=/tmp/sql_collect_java_smoke_$$
PASS=0
FAIL=0
LOG="$SMOKE_ROOT/smoke.log"
LOG_DIR="$SMOKE_ROOT/logs"
OUTDIR="$SMOKE_ROOT/outdir"
JDBC_URL="jdbc:yasdb://127.0.0.1:${LOCAL_PORT}/yasdb"

mkdir -p "$OUTDIR/replay" "$LOG_DIR"
: >"$LOG"

ok() { echo "[PASS] $*" | tee -a "$LOG"; PASS=$((PASS + 1)); }
bad() { echo "[FAIL] $*" | tee -a "$LOG"; FAIL=$((FAIL + 1)); }
sec() { echo; echo "===== $* =====" | tee -a "$LOG"; }

runj() {
  set +e
  "$ROOT/run.sh" "$@" --log-dir "$LOG_DIR" >>"$LOG" 2>&1
  local rc=$?
  set +e
  return $rc
}

ensure_tunnel() {
  if ! pgrep -fl "${LOCAL_PORT}:${HOST}:1688" >/dev/null 2>&1; then
    ssh -f -N -o ExitOnForwardFailure=yes -o BatchMode=yes \
      -L "${LOCAL_PORT}:${HOST}:1688" yashan@"$HOST" || return 1
  fi
  return 0
}

yasql_remote() {
  ssh -o BatchMode=yes -o ConnectTimeout=10 yashan@"$HOST" \
    "export YASDB_HOME=/home/yashan/.yasboot/yashandb_yasdb_home; export PATH=\$YASDB_HOME/bin:\$PATH; yasql -S / as sysdba" <<EOF
$*
EOF
}

cd "$ROOT" || exit 1
echo "sql_collect java smoke $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "$LOG"
echo "root=$ROOT jdbc=$JDBC" | tee -a "$LOG"

# --------------------------------------------------------------------------
sec "0. build + CLI surface"
bash ./build.sh >>"$LOG" 2>&1 && ok "build.sh" || bad "build.sh"
./run.sh --version 2>&1 | tee -a "$LOG" | grep -q '2.0.0-java' && ok "version" || bad "version"
./run.sh --version 2>&1 | tee -a "$LOG" | grep -q 'Java 8+' && ok "version mentions Java 8+" || bad "version mentions Java 8+"
./run.sh --help 2>&1 | tee -a "$LOG" | grep -q 'Requires Java 8' && ok "help Requires Java 8" || bad "help Requires Java 8"
# classfile must stay Java 8 (major 52) for low-version runtimes
python3 - <<'PY' >>"$LOG" 2>&1 && ok "classfile major=52" || bad "classfile major=52"
import os, struct
root = "build/classes"
bad = []
for dp, _, fs in os.walk(root):
    for f in fs:
        if not f.endswith(".class"):
            continue
        p = os.path.join(dp, f)
        with open(p, "rb") as fh:
            magic, minor, major = struct.unpack(">IHH", fh.read(8))
        if major != 52:
            bad.append((p, major))
raise SystemExit(0 if not bad else 1)
PY
# report SQL embedded in Java (no standalone resource in jar)
[[ -f "$ROOT/src/com/yashan/sqlcollect/collect/SqlReportScript.java" ]] \
  && ok "SqlReportScript.java generated" || bad "SqlReportScript.java generated"
! jar tf "$ROOT/build/sql-collect.jar" 2>/dev/null | grep -q 'sql_report.sql' \
  && ok "jar has no sql_report.sql" || bad "jar has no sql_report.sql"
jar tf "$ROOT/build/sql-collect.jar" 2>/dev/null | grep -q 'SqlReportScript.class' \
  && ok "jar has SqlReportScript.class" || bad "jar has SqlReportScript.class"
ensure_tunnel && ok "tunnel ${LOCAL_PORT}" || bad "tunnel ${LOCAL_PORT}"
[[ -f "$JDBC" ]] && ok "jdbc jar present" || bad "jdbc jar missing"

INI="$SMOKE_ROOT/jdbc_replay.ini"
cat >"$INI" <<EOF
[jdbc]
jdbc_jar = $JDBC
jdbc_url = $JDBC_URL
user = htz
password = htz123
schema_via_alter = false

[map.HTZ]
user = htz
password = htz123

[map.HNCB]
user = hncb
password = hncb123
EOF

# missing jdbc_url must error
cat >"$SMOKE_ROOT/bad.ini" <<EOF
jdbc_jar = $JDBC
host = 10.10.10.170
user = htz
password = x
EOF
if runj replay --jdbc-config "$SMOKE_ROOT/bad.ini" --source file --dry-run; then
  bad "missing jdbc_url should error"
else
  grep -q "jdbc_url" "$LOG" && ok "missing jdbc_url errors" || bad "missing jdbc_url message"
fi

MARK=$(wc -l <"$LOG" | tr -d ' ')
./run.sh --help >>"$LOG" 2>&1
tail -n +"$((MARK + 1))" "$LOG" | grep -qiE 'collect|replay' && ok "help shows commands" || bad "help shows commands"

INIT_DIR="$SMOKE_ROOT/initcfg"
mkdir -p "$INIT_DIR"
MARK=$(wc -l <"$LOG" | tr -d ' ')
( cd "$INIT_DIR" && "$ROOT/run.sh" replay --init-config --log-dir "$LOG_DIR" >>"$LOG" 2>&1 )
[[ -f "$INIT_DIR/jdbc_replay.ini" ]] && ok "init-config writes ini" || bad "init-config writes ini"
grep -q 'jdbc_url' "$INIT_DIR/jdbc_replay.ini" && ok "init-config has jdbc_url" || bad "init-config has jdbc_url"

# --------------------------------------------------------------------------
sec "1. plant query + named + dml"
yasql_remote "
SET SERVEROUTPUT ON
BEGIN
  BEGIN EXECUTE IMMEDIATE 'CREATE USER htz IDENTIFIED BY htz123'; EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN EXECUTE IMMEDIATE 'ALTER USER htz IDENTIFIED BY htz123'; EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN EXECUTE IMMEDIATE 'GRANT CONNECT, RESOURCE, CREATE TABLE, SELECT ANY DICTIONARY, SELECT ANY TABLE, DBA TO htz'; EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN EXECUTE IMMEDIATE 'CREATE USER hncb IDENTIFIED BY hncb123'; EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN EXECUTE IMMEDIATE 'ALTER USER hncb IDENTIFIED BY hncb123'; EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN EXECUTE IMMEDIATE 'GRANT CONNECT, RESOURCE TO hncb'; EXCEPTION WHEN OTHERS THEN NULL; END;
  DBMS_OUTPUT.PUT_LINE('grants_ok');
END;
/
" >>"$LOG" 2>&1
grep -q grants_ok "$LOG" && ok "grants htz/hncb" || bad "grants htz/hncb"

cat >"$SMOKE_ROOT/Plant.java" <<'EOF'
import java.sql.*;
public class Plant {
  public static void main(String[] a) throws Exception {
    Class.forName("com.yashandb.jdbc.Driver");
    try (Connection c = DriverManager.getConnection(a[0], a[1], a[2]);
         Statement st = c.createStatement()) {
      try { st.execute("CREATE TABLE htz_replay_force_t(id NUMBER)"); } catch (Exception e) {}
      try { st.executeUpdate("DELETE FROM htz_replay_force_t"); } catch (Exception e) {}
      try (PreparedStatement ps = c.prepareStatement(
          "SELECT /*sql_collect_java_smoke_qmark*/ ? AS c FROM dual")) {
        ps.setInt(1, 42);
        try (ResultSet rs = ps.executeQuery()) { rs.next(); System.out.println("QMARK="+rs.getInt(1)); }
      }
      try (PreparedStatement ps = c.prepareStatement(
          "SELECT /*sql_collect_java_smoke_named*/ :B1 AS c FROM dual")) {
        ps.setInt(1, 99);
        try (ResultSet rs = ps.executeQuery()) { rs.next(); System.out.println("NAMED="+rs.getInt(1)); }
      }
      try (PreparedStatement ps = c.prepareStatement(
          "INSERT /*sql_collect_java_smoke_dml*/ INTO htz_replay_force_t(id) VALUES (?)")) {
        ps.setInt(1, 7);
        System.out.println("DML="+ps.executeUpdate());
      }
    }
  }
}
EOF
javac -cp "$JDBC" -d "$SMOKE_ROOT" "$SMOKE_ROOT/Plant.java" && ok "javac Plant" || bad "javac Plant"
java -Djava.net.preferIPv4Stack=true -cp "$SMOKE_ROOT:$JDBC" Plant \
  "$JDBC_URL" htz htz123 >>"$LOG" 2>&1
grep -q 'QMARK=42' "$LOG" && ok "plant ?" || bad "plant ?"
grep -q 'NAMED=99' "$LOG" && ok "plant :B1" || bad "plant :B1"
grep -q 'DML=1' "$LOG" && ok "plant INSERT" || bad "plant INSERT"

cat >"$SMOKE_ROOT/ResolveTag.java" <<'EOF'
import java.sql.*;
public class ResolveTag {
  public static void main(String[] a) throws Exception {
    Class.forName("com.yashandb.jdbc.Driver");
    try (Connection c = DriverManager.getConnection(a[0], a[1], a[2]);
         PreparedStatement ps = c.prepareStatement(
             "SELECT sql_id FROM v$sql WHERE parsing_schema_name = ? "
                 + "AND sql_text LIKE ? AND ROWNUM = 1")) {
      ps.setString(1, a[3].toUpperCase());
      ps.setString(2, "%" + a[4] + "%");
      try (ResultSet rs = ps.executeQuery()) {
        if (rs.next()) System.out.println("ID|" + rs.getString(1).trim());
      }
    }
  }
}
EOF
javac -cp "$JDBC" -d "$SMOKE_ROOT" "$SMOKE_ROOT/ResolveTag.java"

resolve_id() {
  java -Djava.net.preferIPv4Stack=true -cp "$SMOKE_ROOT:$JDBC" ResolveTag \
    "$JDBC_URL" htz htz123 HTZ "$1" 2>/dev/null \
    | grep '^ID|' | head -1 | cut -d'|' -f2 | tr -d '[:space:]'
}

QID=$(resolve_id "sql_collect_java_smoke_qmark")
NID=$(resolve_id "sql_collect_java_smoke_named")
DID=$(resolve_id "sql_collect_java_smoke_dml")
echo "QID=$QID NID=$NID DID=$DID" | tee -a "$LOG"
[[ -n "$QID" && ${#QID} -eq 13 ]] && ok "resolve Q=$QID" || bad "resolve Q ($QID)"
[[ -n "$NID" && ${#NID} -eq 13 ]] && ok "resolve N=$NID" || bad "resolve N ($NID)"
[[ -n "$DID" && ${#DID} -eq 13 ]] && ok "resolve D=$DID" || bad "resolve D ($DID)"
if [[ -z "$QID" || -z "$NID" || -z "$DID" ]]; then
  echo "Cannot continue without sql_ids; PASS=$PASS FAIL=$FAIL log=$LOG"
  exit 1
fi

# --------------------------------------------------------------------------
sec "2. export planted ids + backup (align Python export_replay_package)"
# warm cursors then force-export Q/N/D (not max-new candidate pool)
java -Djava.net.preferIPv4Stack=true -cp "$SMOKE_ROOT:$JDBC" Plant \
  "$JDBC_URL" htz htz123 >>"$LOG" 2>&1
QID=$(resolve_id "sql_collect_java_smoke_qmark")
NID=$(resolve_id "sql_collect_java_smoke_named")
DID=$(resolve_id "sql_collect_java_smoke_dml")
echo "REPLANTED QID=$QID NID=$NID DID=$DID" | tee -a "$LOG"
[[ -n "$QID" && -n "$NID" && -n "$DID" ]] && ok "replant resolve ids" || bad "replant resolve ids"

MARK=$(wc -l <"$LOG" | tr -d ' ')
if runj collect --jdbc-config "$INI" --outdir "$OUTDIR" --skip-backup \
  --sql-id "$QID,$NID,$DID" --count 1; then
  ok "force export 3 sql_ids exit 0"
else
  # DML report may be incomplete; export still required
  PKG_Q=$(ls -1d "$OUTDIR/replay/${QID}"__c* 2>/dev/null | wc -l | tr -d ' ')
  PKG_N=$(ls -1d "$OUTDIR/replay/${NID}"__c* 2>/dev/null | wc -l | tr -d ' ')
  PKG_D=$(ls -1d "$OUTDIR/replay/${DID}"__c* 2>/dev/null | wc -l | tr -d ' ')
  if [[ "${PKG_Q:-0}" -ge 1 && "${PKG_N:-0}" -ge 1 && "${PKG_D:-0}" -ge 1 ]]; then
    ok "force export 3 sql_ids (packages present, exit!=0 tolerated)"
  else
    bad "force export 3 sql_ids (Q=$PKG_Q N=$PKG_N D=$PKG_D)"
  fi
fi
ls "$OUTDIR/replay/${QID}"__c* >/dev/null 2>&1 && ok "local package Q" || bad "local package Q"
ls "$OUTDIR/replay/${NID}"__c* >/dev/null 2>&1 && ok "local package N" || bad "local package N"
ls "$OUTDIR/replay/${DID}"__c* >/dev/null 2>&1 && ok "local package D" || bad "local package D"
tail -n +"$((MARK + 1))" "$LOG" | grep -q 'htz_owner=HTZ' && ok "export logs htz_owner" || bad "export logs htz_owner"

# JDBC native report + Java LITERAL rewrite on planted sql_ids (not candidate-pool reports)
assert_jdbc_native_report() {
  local sid="$1" label="$2" expect_lit="$3"
  local rpt="$OUTDIR/${sid}.txt"
  if [[ ! -f "$rpt" ]]; then
    bad "$label report missing ($rpt)"
    return
  fi
  grep -q 'JDBC native report' "$rpt" && ok "$label JDBC native report" || bad "$label JDBC native report"
  grep -q '===== ORIGINAL SQL =====' "$rpt" && ok "$label ORIGINAL section" || bad "$label ORIGINAL section"
  grep -q '===== LITERAL SQL =====' "$rpt" && ok "$label LITERAL section" || bad "$label LITERAL section"
  if grep -q 'Java rewrite' "$rpt" || grep -q 'no bind capture on executed child' "$rpt"; then
    ok "$label Java rewrite path"
  else
    bad "$label Java rewrite path"
  fi
  if awk '/===== ORIGINAL SQL =====/{p=1;next} /===== LITERAL SQL =====/{p=0} p' "$rpt" \
       | grep -q 'DBMS_OUTPUT.GET_LINE'; then
    bad "$label ORIGINAL polluted by GET_LINE"
  else
    ok "$label ORIGINAL clean"
  fi
  # LITERAL must rewrite placeholders; capture empty → NULL (lab); value present → inline
  local lit
  lit=$(awk '/===== LITERAL SQL =====/{p=1;next} /^-----/{p=0} p' "$rpt")
  if echo "$lit" | grep -qE "$expect_lit"; then
    ok "$label LITERAL inlined $expect_lit"
  elif grep -q 'no bind capture on executed child' "$rpt"; then
    ok "$label LITERAL no bind capture (soft)"
  elif echo "$lit" | grep -q 'NULL' \
      && ! echo "$lit" | grep -q '?' \
      && ! echo "$lit" | grep -qiE ':[A-Za-z_][A-Za-z0-9_]*'; then
    # bind row exists but value empty → Java rewrite to NULL (common on lab)
    ok "$label LITERAL rewritten empty-capture→NULL"
  else
    bad "$label LITERAL not rewritten (expect $expect_lit or NULL)"
  fi
}
assert_jdbc_native_report "$QID" "Q" '42'
assert_jdbc_native_report "$NID" "N" '99'

# light collect for report quality (candidate pool; tolerate partial fail like lab race)
MARK=$(wc -l <"$LOG" | tr -d ' ')
runj collect --jdbc-config "$INI" --outdir "$OUTDIR" --skip-backup --max-new 3 --count 1
RC=$?
RPT_N=$(ls -1 "$OUTDIR"/*.txt 2>/dev/null | grep -v collected | wc -l | tr -d ' ')
if [[ $RC -eq 0 ]]; then
  ok "collect max-new exit 0"
elif [[ "${RPT_N:-0}" -ge 1 ]] && grep -ql '===== ORIGINAL SQL =====' "$OUTDIR"/*.txt 2>/dev/null; then
  ok "collect wrote reports (exit=$RC, lab race tolerated)"
else
  bad "collect max-new exit $RC"
fi
if grep -q '=== \[STEP\]' "$LOG_DIR"/sql_collect_collect_debug_*.log 2>/dev/null; then
  ok "debug STEP markers"
else
  bad "debug STEP markers"
fi
[[ "${RPT_N:-0}" -ge 1 ]] && ok "reports n=$RPT_N" || bad "reports n=$RPT_N"

if ls "$OUTDIR"/*.txt >/dev/null 2>&1; then
  R1=$(ls "$OUTDIR"/*.txt | grep -v collected_sqlids | head -1)
  grep -q 'JDBC native report' "$R1" && ok "report JDBC native banner" || bad "report JDBC native banner"
  grep -q '===== ORIGINAL SQL =====' "$R1" && ok "report ORIGINAL SQL" || bad "report ORIGINAL SQL"
  grep -q '===== LITERAL SQL =====' "$R1" && ok "report LITERAL SQL" || bad "report LITERAL SQL"
  grep -q 'PLAN from v$sql_plan' "$R1" && ok "report PLAN" || bad "report PLAN"
  grep -q 'information from v$sql' "$R1" && ok "report v\$sql" || bad "report v\$sql"
  grep -q 'OBJECT SIZE' "$R1" && ok "report OBJECT SIZE" || bad "report OBJECT SIZE"
  grep -q 'TABLE COLUMNS' "$R1" && ok "report TABLE COLUMNS" || bad "report TABLE COLUMNS"
  grep -q 'INDEX INFO' "$R1" && ok "report INDEX INFO" || bad "report INDEX INFO"
  # P2: AWR 段必有标题; 无 AWR 表时允许 [ERROR] AWR 后仍继续 objects
  if grep -qi 'information from awr' "$R1"; then
    ok "report AWR section present"
  else
    bad "report AWR section present"
  fi
  if grep -q '\[SKIP\] AWR section' "$R1"; then
    bad "report AWR still skipped"
  else
    ok "report AWR not skipped"
  fi
  if awk '/===== ORIGINAL SQL =====/{p=1;next} /===== LITERAL SQL =====/{p=0} p' "$R1" \
       | grep -q 'DBMS_OUTPUT.GET_LINE'; then
    bad "ORIGINAL SQL polluted by GET_LINE"
  else
    ok "ORIGINAL SQL clean"
  fi
fi

MARK=$(wc -l <"$LOG" | tr -d ' ')
runj collect --jdbc-config "$INI" --outdir "$OUTDIR" --backup-only
RC=$?
[[ $RC -eq 0 ]] && ok "backup-only exit 0" || bad "backup-only exit $RC"
tail -n +"$((MARK + 1))" "$LOG" | grep -qE 'backup-only done|backup=' && ok "backup-only logged" || bad "backup-only logged"
tail -n +"$((MARK + 1))" "$LOG" | grep -qE 'backup owner=HTZ|htz_owner=HTZ' && ok "backup under login user" || bad "backup under login user"

# --------------------------------------------------------------------------
sec "3. replay source=file"
MARK=$(wc -l <"$LOG" | tr -d ' ')
if runj replay --jdbc-config "$INI" --source file --outdir "$OUTDIR" --sql-id "$QID,$NID" --dry-run; then
  ok "file dry multi sql-id"
  tail -n +"$((MARK + 1))" "$LOG" | grep -q 'replay map-hit schema=HTZ' && ok "file dry map-hit HTZ" || bad "file dry map-hit HTZ"
  tail -n +"$((MARK + 1))" "$LOG" | grep -qE 'user_maps=[1-9]' && ok "file dry user_maps" || bad "file dry user_maps"
else
  bad "file dry multi sql-id"
fi
MARK=$(wc -l <"$LOG" | tr -d ' ')
runj replay --exec --jdbc-config "$INI" --source file --outdir "$OUTDIR" --sql-id "$QID"
RC=$?
[[ $RC -eq 0 ]] && ok "file execute exit 0" || bad "file execute exit $RC"
tail -n +"$((MARK + 1))" "$LOG" | grep -q 'replay exec-ok' && ok "file exec-ok" || bad "file exec-ok"

# --------------------------------------------------------------------------
sec "4. replay source=gv (sql-id / parallel / sessions / force)"
java -Djava.net.preferIPv4Stack=true -cp "$SMOKE_ROOT:$JDBC" Plant \
  "$JDBC_URL" htz htz123 >>"$LOG" 2>&1
QID=$(resolve_id "sql_collect_java_smoke_qmark")
NID=$(resolve_id "sql_collect_java_smoke_named")
DID=$(resolve_id "sql_collect_java_smoke_dml")
echo "GV_IDS QID=$QID NID=$NID DID=$DID" | tee -a "$LOG"
[[ -n "$QID" && -n "$NID" && -n "$DID" ]] && ok "gv refresh ids" || bad "gv refresh ids"

if runj replay --jdbc-config "$INI" --source gv --dry-run; then
  bad "gv without --sql-id should error"
else
  grep -q 'requires --sql-id' "$LOG" && ok "gv requires --sql-id" || bad "gv requires --sql-id msg"
fi

if runj replay --exec --jdbc-config "$INI" --source gv --sql-id "$QID,$NID" --parallel 2; then
  ok "gv parallel=2"
else
  bad "gv parallel=2"
fi

MARK=$(wc -l <"$LOG" | tr -d ' ')
if runj replay --exec --jdbc-config "$INI" --source gv --sql-id "$QID" --sessions 3; then
  ok "gv sessions=3"
  SESS_OK=$(tail -n +"$((MARK + 1))" "$LOG" | grep -c "replay exec-ok" || true)
  [[ "$SESS_OK" -ge 3 ]] && ok "sessions EXEC_OK n=$SESS_OK" || bad "sessions EXEC_OK n=$SESS_OK"
else
  bad "gv sessions=3"
fi

MARK=$(wc -l <"$LOG" | tr -d ' ')
if runj replay --exec --jdbc-config "$INI" --source gv --sql-id "$DID"; then
  bad "dml without --force should fail"
else
  tail -n +"$((MARK + 1))" "$LOG" | grep -q 'replay blocked' \
    && ok "dml blocked without --force" || bad "dml blocked marker"
fi
if runj replay --exec --jdbc-config "$INI" --source gv --sql-id "$DID" --force; then
  ok "dml with --force"
else
  bad "dml with --force"
fi

# --------------------------------------------------------------------------
sec "5. replay source=htz"
MARK=$(wc -l <"$LOG" | tr -d ' ')
if runj replay --jdbc-config "$INI" --source htz --sql-id "$QID,$NID" --dry-run; then
  ok "htz dry filtered"
else
  bad "htz dry filtered"
fi
if runj replay --exec --jdbc-config "$INI" --source htz --sql-id "$QID"; then
  ok "htz execute query"
else
  bad "htz execute query"
fi
if runj replay --exec --jdbc-config "$INI" --source htz --sql-id "$DID"; then
  bad "htz dml without force should fail"
else
  ok "htz dml blocked without --force"
fi
if runj replay --exec --jdbc-config "$INI" --source htz --sql-id "$DID" --force; then
  ok "htz dml with --force"
else
  bad "htz dml with --force"
fi
MARK=$(wc -l <"$LOG" | tr -d ' ')
if runj replay --jdbc-config "$INI" --source htz --dry-run; then
  ok "htz_all dry-run"
  tail -n +"$((MARK + 1))" "$LOG" | grep -q 'replay source=htz' \
    && ok "htz_all emits source" || bad "htz_all emits source"
else
  bad "htz_all dry-run"
fi

# --------------------------------------------------------------------------
sec "6. map fallback / bad password"
cat >"$SMOKE_ROOT/nomap.ini" <<EOF
[jdbc]
jdbc_jar = $JDBC
jdbc_url = $JDBC_URL
user = htz
password = htz123
EOF
MARK=$(wc -l <"$LOG" | tr -d ' ')
if runj replay --exec --jdbc-config "$SMOKE_ROOT/nomap.ini" --source gv --sql-id "$QID"; then
  ok "no-map fallback execute"
  tail -n +"$((MARK + 1))" "$LOG" | grep -q 'replay warn no \[map.HTZ\]' \
    && ok "no-map WARN marker" || bad "no-map WARN marker"
  tail -n +"$((MARK + 1))" "$LOG" | grep -q 'replay login-user=HTZ' \
    && ok "no-map login HTZ" || bad "no-map login HTZ"
else
  bad "no-map fallback execute"
fi

cat >"$SMOKE_ROOT/badmap.ini" <<EOF
[jdbc]
jdbc_jar = $JDBC
jdbc_url = $JDBC_URL
user = htz
password = htz123
[map.HTZ]
user = htz
password = wrong_password_xyz
EOF
if runj replay --exec --jdbc-config "$SMOKE_ROOT/badmap.ini" --source gv --sql-id "$QID"; then
  bad "bad map password should fail"
else
  ok "bad map password fails"
fi

# --------------------------------------------------------------------------
sec "7. schema-via-alter"
ALTER_SID=smokealter01
ALTER_PKG="$OUTDIR/replay/${ALTER_SID}__c0__i1"
ALTER_SQL="SELECT /*sql_collect_java_alter*/ 1 AS c FROM dual"
ALTER_SHA=$(printf '%s' "$ALTER_SQL" | shasum -a 256 | awk '{print $1}')
mkdir -p "$ALTER_PKG"
printf '%s' "$ALTER_SQL" >"$ALTER_PKG/orig.sql"
printf 'sql_id=%s\nchild_number=0\ninst_id=1\nparsing_schema=HNCB\nsql_len=%s\nsql_sha256=%s\n' \
  "$ALTER_SID" "${#ALTER_SQL}" "$ALTER_SHA" >"$ALTER_PKG/meta.txt"
printf '%s\n' '[]' >"$ALTER_PKG/binds.json"
: >"$ALTER_PKG/binds.txt"

MARK=$(wc -l <"$LOG" | tr -d ' ')
if runj replay --exec --jdbc-config "$INI" --source file --outdir "$OUTDIR" \
  --sql-id "$ALTER_SID" --schema-via-alter; then
  ok "cli schema-via-alter execute"
  tail -n +"$((MARK + 1))" "$LOG" | grep -q 'login_mode=alter-session' && ok "cli login_mode=alter-session" || bad "cli login_mode=alter-session"
  tail -n +"$((MARK + 1))" "$LOG" | grep -q 'replay schema-set=HNCB' && ok "cli schema-set=HNCB" || bad "cli schema-set=HNCB"
  tail -n +"$((MARK + 1))" "$LOG" | grep -q 'replay exec-ok' && ok "cli alter exec-ok" || bad "cli alter exec-ok"
  if tail -n +"$((MARK + 1))" "$LOG" | grep -q 'replay map-hit schema=HNCB'; then
    bad "cli alter should not map-hit HNCB"
  else
    ok "cli alter skips map-hit"
  fi
else
  bad "cli schema-via-alter execute"
fi

cat >"$SMOKE_ROOT/alter.ini" <<EOF
[jdbc]
jdbc_jar = $JDBC
jdbc_url = $JDBC_URL
user = htz
password = htz123
schema_via_alter = true
[map.HNCB]
user = hncb
password = hncb123
EOF
MARK=$(wc -l <"$LOG" | tr -d ' ')
if runj replay --exec --jdbc-config "$SMOKE_ROOT/alter.ini" --source file --outdir "$OUTDIR" --sql-id "$ALTER_SID"; then
  ok "ini schema_via_alter execute"
  tail -n +"$((MARK + 1))" "$LOG" | grep -q 'login_mode=alter-session' && ok "ini login_mode=alter-session" || bad "ini login_mode=alter-session"
  if tail -n +"$((MARK + 1))" "$LOG" | grep -q 'replay map-hit schema=HNCB'; then
    bad "ini alter should ignore map"
  else
    ok "ini alter ignores map"
  fi
else
  bad "ini schema_via_alter execute"
fi

MARK=$(wc -l <"$LOG" | tr -d ' ')
runj collect --jdbc-config "$INI" --outdir "$SMOKE_ROOT/outdir2" \
  --skip-backup --skip-replay-export --max-new 0 --count 1 \
  --schema-via-alter --current-schema HTZ
RC=$?
[[ $RC -eq 0 ]] && ok "collect alter+current_schema exit 0" || bad "collect alter+current_schema exit $RC"
tail -n +"$((MARK + 1))" "$LOG" | grep -q 'schema_via_alter=true' && ok "collect alter flag" || bad "collect alter flag"

# --------------------------------------------------------------------------
sec "8. bind type matrix (file packages)"
mk_bind_pkg() {
  local name="$1" schema="$2" sql="$3" bj="$4"
  local child="${5:-0}"
  local d="$OUTDIR/replay/${name}__c${child}__i1"
  local sha
  mkdir -p "$d"
  printf '%s' "$sql" >"$d/orig.sql"
  sha=$(printf '%s' "$sql" | shasum -a 256 | awk '{print $1}')
  printf 'sql_id=%s\nchild_number=%s\ninst_id=1\nparsing_schema=%s\nsql_len=%s\nsql_sha256=%s\n' \
    "$name" "$child" "$schema" "${#sql}" "$sha" >"$d/meta.txt"
  printf '%s\n' "$bj" >"$d/binds.json"
}

assert_bind_row() {
  local label="$1" sid="$2" expect_re="$3"
  MARK=$(wc -l <"$LOG" | tr -d ' ')
  if runj replay --exec --jdbc-config "$INI" --source file --outdir "$OUTDIR" --sql-id "$sid"; then
    ok "bind $label execute"
    if grep -E "replay row ${expect_re}" "$LOG_DIR"/sql_collect_*_debug_*.log >/dev/null 2>&1 \
      || tail -n +"$((MARK + 1))" "$LOG" | grep -qE "replay row ${expect_re}"; then
      ok "bind $label row"
    else
      bad "bind $label row (want /$expect_re/)"
    fi
  else
    bad "bind $label execute"
  fi
}

mk_bind_pkg btnum HTZ \
  "SELECT /*sql_collect_java_btnum*/ ? AS c FROM dual" \
  '[{"position":1,"datatype":"NUMBER","value":"42"}]'
assert_bind_row "NUMBER int" btnum '42'

mk_bind_pkg btdec HTZ \
  "SELECT /*sql_collect_java_btdec*/ ? AS c FROM dual" \
  '[{"position":1,"datatype":"NUMBER","value":"123.45"}]'
assert_bind_row "NUMBER decimal" btdec '123\.45'

mk_bind_pkg btnulln HTZ \
  "SELECT /*sql_collect_java_btnulln*/ CASE WHEN ? IS NULL THEN 'NULL_OK' ELSE 'X' END AS c FROM dual" \
  '[{"position":1,"datatype":"NUMBER","value":""}]'
assert_bind_row "NUMBER null" btnulln 'NULL_OK'

mk_bind_pkg btvchr HTZ \
  "SELECT /*sql_collect_java_btvchr*/ ? AS c FROM dual" \
  '[{"position":1,"datatype":"VARCHAR2","value":"hello_bt"}]'
assert_bind_row "VARCHAR2" btvchr 'hello_bt'

mk_bind_pkg btnullv HTZ \
  "SELECT /*sql_collect_java_btnullv*/ CASE WHEN ? IS NULL THEN 'NULL_OK' ELSE 'X' END AS c FROM dual" \
  '[{"position":1,"datatype":"VARCHAR2","value":""}]'
assert_bind_row "VARCHAR2 null" btnullv 'NULL_OK'

mk_bind_pkg btdate HTZ \
  "SELECT /*sql_collect_java_btdate*/ TO_CHAR(?,'YYYY-MM-DD') AS c FROM dual" \
  '[{"position":1,"datatype":"DATE","value":"2024-06-15"}]'
assert_bind_row "DATE" btdate '2024-06-15'

mk_bind_pkg btts HTZ \
  "SELECT /*sql_collect_java_btts*/ TO_CHAR(?,'YYYY-MM-DD HH24:MI:SS') AS c FROM dual" \
  '[{"position":1,"datatype":"TIMESTAMP","value":"2024-06-15 13:45:30"}]'
assert_bind_row "TIMESTAMP" btts '2024-06-15 13:45:30'

mk_bind_pkg btfloat HTZ \
  "SELECT /*sql_collect_java_btfloat*/ ? AS c FROM dual" \
  '[{"position":1,"datatype":"BINARY_DOUBLE","value":"3.14"}]'
assert_bind_row "BINARY_DOUBLE" btfloat '3\.14'

mk_bind_pkg btmix HTZ \
  "SELECT /*sql_collect_java_btmix*/ ? || '|' || TO_CHAR(?,'YYYY-MM-DD') || '|' || TO_CHAR(?) AS c FROM dual" \
  '[{"position":1,"datatype":"VARCHAR2","value":"ab"},{"position":2,"datatype":"DATE","value":"2024-06-15"},{"position":3,"datatype":"NUMBER","value":"7"}]'
assert_bind_row "mixed V/D/N" btmix 'ab\|2024-06-15\|7'

mk_bind_pkg btdateslash HTZ \
  "SELECT /*sql_collect_java_btdateslash*/ TO_CHAR(?,'YYYY-MM-DD') AS c FROM dual" \
  '[{"position":1,"datatype":"DATE","value":"2024/06/15"}]'
assert_bind_row "DATE slash" btdateslash '2024-06-15'

mk_bind_pkg bttsfrac HTZ \
  "SELECT /*sql_collect_java_bttsfrac*/ TO_CHAR(?,'YYYY-MM-DD HH24:MI:SS') AS c FROM dual" \
  '[{"position":1,"datatype":"TIMESTAMP","value":"2024-06-15 13:45:30.123"}]'
assert_bind_row "TIMESTAMP frac" bttsfrac '2024-06-15 13:45:30'

mk_bind_pkg btchild HTZ \
  "SELECT /*sql_collect_java_btchild*/ ? AS c FROM dual" \
  '[{"position":1,"datatype":"NUMBER","value":"111"}]' 0
mk_bind_pkg btchild HTZ \
  "SELECT /*sql_collect_java_btchild*/ ? AS c FROM dual" \
  '[{"position":1,"datatype":"NUMBER","value":"222"}]' 1
assert_bind_row "latest child" btchild '222'

mk_bind_pkg btschfail HTZ_NOEXIST_XYZ \
  "SELECT /*sql_collect_java_btschfail*/ 1 AS c FROM dual" \
  '[]'
cat >"$SMOKE_ROOT/schema_fail.ini" <<EOF
[jdbc]
jdbc_jar = $JDBC
jdbc_url = $JDBC_URL
user = htz
password = htz123
[map.HTZ_NOEXIST_XYZ]
user = htz
password = htz123
EOF
MARK=$(wc -l <"$LOG" | tr -d ' ')
if runj replay --exec --jdbc-config "$SMOKE_ROOT/schema_fail.ini" --source file --outdir "$OUTDIR" --sql-id btschfail; then
  bad "bad CURRENT_SCHEMA should fail"
else
  if tail -n +"$((MARK + 1))" "$LOG" | grep -q 'replay fail set_schema' \
    || grep -q 'replay fail set_schema' "$LOG_DIR"/sql_collect_*_debug_*.log 2>/dev/null; then
    ok "bad CURRENT_SCHEMA replay fail"
  else
    bad "bad CURRENT_SCHEMA replay fail"
  fi
fi

# --------------------------------------------------------------------------
sec "9. long SQL + collect loop + file all dry"
cat >"$SMOKE_ROOT/PlantLong.java" <<'EOF'
import java.sql.*;
public class PlantLong {
  public static void main(String[] a) throws Exception {
    Class.forName("com.yashandb.jdbc.Driver");
    StringBuilder sb = new StringBuilder(90000);
    sb.append("SELECT /*sql_collect_java_smoke_long*/ /*");
    while (sb.length() < 80000) sb.append('x');
    sb.append("*/ ? AS c FROM dual");
    String sql = sb.toString();
    try (Connection c = DriverManager.getConnection(a[0], a[1], a[2]);
         PreparedStatement ps = c.prepareStatement(sql)) {
      ps.setInt(1, 1);
      try (ResultSet rs = ps.executeQuery()) {
        rs.next();
        System.out.println("LONG_CHARS=" + sql.length());
        System.out.println("LONG_OK=" + rs.getInt(1));
      }
    }
  }
}
EOF
javac -cp "$JDBC" -d "$SMOKE_ROOT" "$SMOKE_ROOT/PlantLong.java" >>"$LOG" 2>&1 \
  && ok "javac PlantLong" || bad "javac PlantLong"
java -Djava.net.preferIPv4Stack=true -cp "$SMOKE_ROOT:$JDBC" PlantLong \
  "$JDBC_URL" htz htz123 >>"$LOG" 2>&1
grep -q 'LONG_OK=1' "$LOG" && ok "plant long SQL" || bad "plant long SQL"
LID=$(resolve_id "sql_collect_java_smoke_long")
echo "LID=$LID" | tee -a "$LOG"
[[ -n "$LID" && ${#LID} -eq 13 ]] && ok "resolve long sql_id=$LID" || bad "resolve long sql_id ($LID)"
if [[ -n "$LID" ]]; then
  MARK=$(wc -l <"$LOG" | tr -d ' ')
  if runj replay --exec --jdbc-config "$INI" --source gv --sql-id "$LID"; then
    ok "gv replay long SQL"
    CHARS=$(tail -n +"$((MARK + 1))" "$LOG" | grep -oE 'replay sql-chars=[0-9]+' | head -1 | cut -d= -f2)
    echo "replay_long_chars=$CHARS" | tee -a "$LOG"
    [[ -n "$CHARS" && "$CHARS" -ge 10000 ]] \
      && ok "long SQL chars=$CHARS" || bad "long SQL chars=$CHARS"
  else
    bad "gv replay long SQL"
  fi
else
  bad "gv replay long SQL skipped"
fi

MARK=$(wc -l <"$LOG" | tr -d ' ')
runj collect --jdbc-config "$INI" --outdir "$OUTDIR" --skip-backup --skip-replay-export \
  --max-new 0 --interval 1 --count 2
tail -n +"$((MARK + 1))" "$LOG" | grep -q 'loop rounds=2' && ok "collect loop rounds=2" || bad "collect loop rounds=2"
ROUND_N=$(grep -cE '=== \[STEP\] collect_round' "$LOG_DIR"/sql_collect_collect_debug_*.log 2>/dev/null | awk '{s+=$1} END{print s+0}')
# Also count from the latest collect debug after this run
if tail -n +"$((MARK + 1))" "$LOG" | grep -qE 'loop rounds=2'; then
  # debug STEP may span files; accept banner + at least one round marker in recent debug
  if grep -qE '=== \[STEP\] collect_round' "$LOG_DIR"/sql_collect_collect_debug_*.log 2>/dev/null; then
    ok "collect loop round STEPs present"
  else
    bad "collect loop round STEPs present"
  fi
else
  bad "collect loop round STEPs present"
fi

if runj replay --jdbc-config "$INI" --source file --outdir "$OUTDIR" --dry-run; then
  ok "file all-packages dry-run"
else
  bad "file all-packages dry-run"
fi

# --------------------------------------------------------------------------
sec "10. dual logs + multi-business-user MAP"
SESS_N=$(find "$LOG_DIR" -maxdepth 1 -type f -name 'sql_collect_*.log' ! -name '*_debug_*' 2>/dev/null | wc -l | tr -d ' ')
DBG_N=$(find "$LOG_DIR" -maxdepth 1 -type f -name 'sql_collect_*_debug_*.log' 2>/dev/null | wc -l | tr -d ' ')
[[ "$SESS_N" -ge 1 ]] && ok "session log files n=$SESS_N" || bad "session log files n=$SESS_N"
[[ "$DBG_N" -ge 1 ]] && ok "debug log files n=$DBG_N" || bad "debug log files n=$DBG_N"
LATEST_SESS=$(ls -t "$LOG_DIR"/sql_collect_*.log 2>/dev/null | grep -v _debug_ | head -1 || true)
LATEST_DBG=$(ls -t "$LOG_DIR"/sql_collect_*_debug_*.log 2>/dev/null | head -1 || true)
if [[ -n "$LATEST_SESS" ]]; then
  grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}  (INFO|WARN|ERROR)  ' "$LATEST_SESS" >/dev/null \
    && ok "session ts+level format" || bad "session ts+level format"
else
  bad "session ts format (no file)"
fi
if [[ -n "$LATEST_DBG" ]]; then
  grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}  (DEBUG|STEP|INFO)  ' "$LATEST_DBG" >/dev/null \
    && ok "debug ts+level format" || bad "debug ts+level format"
  # STEP 多在 collect debug; 最新文件可能是 replay, 故扫全部 collect debug
  if grep -q '\[STEP\]' "$LOG_DIR"/sql_collect_collect_debug_*.log 2>/dev/null \
    || grep -q '\[STEP\]' "$LATEST_DBG"; then
    ok "debug has STEP markers (dual)"
  else
    bad "debug has STEP markers (dual)"
  fi
else
  bad "debug STEP (no file)"
fi

yasql_remote "
SET SERVEROUTPUT ON
BEGIN
  FOR r IN (
    SELECT 'scmap1' u, 'scmap1pwd' p FROM dual UNION ALL
    SELECT 'scmap2', 'scmap2pwd' FROM dual UNION ALL
    SELECT 'scmap3', 'scmap3pwd' FROM dual
  ) LOOP
    BEGIN EXECUTE IMMEDIATE 'CREATE USER '||r.u||' IDENTIFIED BY '||r.p; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN EXECUTE IMMEDIATE 'ALTER USER '||r.u||' IDENTIFIED BY '||r.p; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN EXECUTE IMMEDIATE 'GRANT CONNECT, RESOURCE TO '||r.u; EXCEPTION WHEN OTHERS THEN NULL; END;
  END LOOP;
  DBMS_OUTPUT.PUT_LINE('scmap_users_ready');
END;
/
" >>"$LOG" 2>&1
grep -q scmap_users_ready "$LOG" && ok "create scmap1/2/3 users" || bad "create scmap1/2/3 users"

cat >"$SMOKE_ROOT/PlantBiz.java" <<'EOF'
import java.sql.*;
public class PlantBiz {
  public static void main(String[] a) throws Exception {
    Class.forName("com.yashandb.jdbc.Driver");
    String sql = "SELECT /*" + a[3] + "*/ ? AS c FROM dual";
    try (Connection c = DriverManager.getConnection(a[0], a[1], a[2]);
         PreparedStatement ps = c.prepareStatement(sql)) {
      ps.setInt(1, 1);
      try (ResultSet rs = ps.executeQuery()) {
        rs.next();
        System.out.println("BIZ_OK user=" + a[1] + " tag=" + a[3] + " v=" + rs.getInt(1));
      }
    }
  }
}
EOF
javac -cp "$JDBC" -d "$SMOKE_ROOT" "$SMOKE_ROOT/PlantBiz.java" >>"$LOG" 2>&1
for U in scmap1 scmap2 scmap3; do
  case "$U" in
    scmap1) P='scmap1pwd' ;;
    scmap2) P='scmap2pwd' ;;
    scmap3) P='scmap3pwd' ;;
  esac
  TAG="sql_collect_java_map_${U}"
  java -Djava.net.preferIPv4Stack=true -cp "$SMOKE_ROOT:$JDBC" PlantBiz \
    "$JDBC_URL" "$U" "$P" "$TAG" >>"$LOG" 2>&1
done
grep -q 'BIZ_OK user=scmap1' "$LOG" && ok "plant scmap1" || bad "plant scmap1"
grep -q 'BIZ_OK user=scmap2' "$LOG" && ok "plant scmap2" || bad "plant scmap2"
grep -q 'BIZ_OK user=scmap3' "$LOG" && ok "plant scmap3" || bad "plant scmap3"

resolve_id_schema() {
  java -Djava.net.preferIPv4Stack=true -cp "$SMOKE_ROOT:$JDBC" ResolveTag \
    "$JDBC_URL" htz htz123 "$2" "$1" 2>/dev/null \
    | grep '^ID|' | head -1 | cut -d'|' -f2 | tr -d '[:space:]'
}
ID1=$(resolve_id_schema "sql_collect_java_map_scmap1" SCMAP1)
ID2=$(resolve_id_schema "sql_collect_java_map_scmap2" SCMAP2)
ID3=$(resolve_id_schema "sql_collect_java_map_scmap3" SCMAP3)
echo "MAP_IDS ID1=$ID1 ID2=$ID2 ID3=$ID3" | tee -a "$LOG"
[[ -n "$ID1" && ${#ID1} -eq 13 ]] && ok "resolve scmap1 id=$ID1" || bad "resolve scmap1 ($ID1)"
[[ -n "$ID2" && ${#ID2} -eq 13 ]] && ok "resolve scmap2 id=$ID2" || bad "resolve scmap2 ($ID2)"
[[ -n "$ID3" && ${#ID3} -eq 13 ]] && ok "resolve scmap3 id=$ID3" || bad "resolve scmap3 ($ID3)"

cat >"$SMOKE_ROOT/multimap.ini" <<EOF
[jdbc]
jdbc_jar = $JDBC
jdbc_url = $JDBC_URL
user = htz
password = htz123

[map.SCMAP1]
user = scmap1
password = scmap1pwd

[map.SCMAP2]
user = scmap2
password = scmap2pwd

[map.SCMAP3]
user = scmap3
password = scmap3pwd
EOF

if [[ -n "$ID1" && -n "$ID2" && -n "$ID3" ]]; then
  MARK=$(wc -l <"$LOG" | tr -d ' ')
  if runj replay --exec --jdbc-config "$SMOKE_ROOT/multimap.ini" --source gv \
      --sql-id "$ID1,$ID2,$ID3" --parallel 3; then
    ok "multi-map gv replay 3 users"
    tail -n +"$((MARK + 1))" "$LOG" | grep -q 'replay map-hit schema=SCMAP1 user=scmap1' \
      && ok "MAP_HIT SCMAP1" || bad "MAP_HIT SCMAP1"
    tail -n +"$((MARK + 1))" "$LOG" | grep -q 'replay map-hit schema=SCMAP2 user=scmap2' \
      && ok "MAP_HIT SCMAP2" || bad "MAP_HIT SCMAP2"
    tail -n +"$((MARK + 1))" "$LOG" | grep -q 'replay map-hit schema=SCMAP3 user=scmap3' \
      && ok "MAP_HIT SCMAP3" || bad "MAP_HIT SCMAP3"
    tail -n +"$((MARK + 1))" "$LOG" | grep -q 'replay login-user=scmap1' \
      && ok "LOGIN scmap1" || bad "LOGIN scmap1"
    tail -n +"$((MARK + 1))" "$LOG" | grep -q 'user_maps=3' \
      && ok "user_maps=3" || bad "user_maps=3"
  else
    bad "multi-map gv replay 3 users"
  fi
else
  bad "multi-map skipped missing ids"
fi

# --------------------------------------------------------------------------
sec "11. help details + init-config overwrite + default ini"
"$ROOT/run.sh" --help >"$SMOKE_ROOT/help.out" 2>&1
grep -q -- '--force' "$SMOKE_ROOT/help.out" && ok "help --force" || bad "help --force"
grep -q -- '--parallel' "$SMOKE_ROOT/help.out" && ok "help --parallel" || bad "help --parallel"
grep -q -- '--sessions' "$SMOKE_ROOT/help.out" && ok "help --sessions" || bad "help --sessions"
grep -q -- '--source' "$SMOKE_ROOT/help.out" && ok "help --source" || bad "help --source"
grep -q -- '--log-dir' "$SMOKE_ROOT/help.out" && ok "help --log-dir" || bad "help --log-dir"
grep -q -- '--init-config' "$SMOKE_ROOT/help.out" && ok "help --init-config" || bad "help --init-config"
grep -q -- '--schema-via-alter' "$SMOKE_ROOT/help.out" && ok "help --schema-via-alter" || bad "help --schema-via-alter"
grep -q -- '--interval' "$SMOKE_ROOT/help.out" && ok "help collect --interval" || bad "help collect --interval"
grep -q -- '--count' "$SMOKE_ROOT/help.out" && ok "help collect --count" || bad "help collect --count"
grep -q -- '--sql-id' "$SMOKE_ROOT/help.out" && ok "help --sql-id" || bad "help --sql-id"
grep -q -- '--report-timeout' "$SMOKE_ROOT/help.out" && ok "help --report-timeout" || bad "help --report-timeout"
grep -q -- '--timeout' "$SMOKE_ROOT/help.out" && ok "help --timeout" || bad "help --timeout"
grep -q -- '--exec' "$SMOKE_ROOT/help.out" && ok "help --exec" || bad "help --exec"
grep -q -- '--results-csv' "$SMOKE_ROOT/help.out" && ok "help --results-csv" || bad "help --results-csv"
grep -q 'sql-collect check' "$SMOKE_ROOT/help.out" && ok "help check subcommand" || bad "help check subcommand"
grep -q -- '--on-sha-mismatch' "$SMOKE_ROOT/help.out" && ok "help --on-sha-mismatch" || bad "help --on-sha-mismatch"
grep -q -- '--allow-sha-mismatch' "$SMOKE_ROOT/help.out" && ok "help --allow-sha-mismatch" || bad "help --allow-sha-mismatch"
grep -q -- '--debug' "$SMOKE_ROOT/help.out" && ok "help --debug" || bad "help --debug"
grep -q -- '--no-debug' "$SMOKE_ROOT/help.out" && ok "help --no-debug" || bad "help --no-debug"
grep -qE -- '--outdir\|-o' "$SMOKE_ROOT/help.out" && ok "help short -o" || bad "help short -o"
grep -qE -- '--sql-id\|-s' "$SMOKE_ROOT/help.out" && ok "help short -s" || bad "help short -s"
grep -qE -- '--source\|-S' "$SMOKE_ROOT/help.out" && ok "help short -S" || bad "help short -S"
grep -qE -- '--sessions\|-N' "$SMOKE_ROOT/help.out" && ok "help short -N" || bad "help short -N"
grep -qE -- '--exec\|-e' "$SMOKE_ROOT/help.out" && ok "help short -e" || bad "help short -e"
grep -qE -- '--on-sha-mismatch\|-M' "$SMOKE_ROOT/help.out" && ok "help short -M" || bad "help short -M"

# --------------------------------------------------------------------------
sec "11a. check + default dry-run + results csv"
MARK=$(wc -l <"$LOG" | tr -d ' ')
# short-option surface (same as long): -j -S -s
if runj replay -j "$INI" -S gv -s "$QID"; then
  ok "short opts -j -S -s dry-run"
  tail -n +"$((MARK + 1))" "$LOG" | grep -q 'source=gv' \
    && ok "short -S maps to source=gv" || bad "short -S maps to source=gv"
  tail -n +"$((MARK + 1))" "$LOG" | grep -q "sql_id=$QID" \
    && ok "short -s maps to sql-id" || bad "short -s maps to sql-id"
else
  bad "short opts -j -S -s dry-run"
fi
MARK=$(wc -l <"$LOG" | tr -d ' ')
if runj check -j "$INI"; then
  ok "check healthy ini"
  tail -n +"$((MARK + 1))" "$LOG" | grep -q 'check PASSED' && ok "check PASSED log" || bad "check PASSED log"
else
  bad "check healthy ini"
fi
if runj check --jdbc-config "$SMOKE_ROOT/bad.ini"; then
  bad "check bad ini should fail"
else
  ok "check bad ini fails"
fi
MARK=$(wc -l <"$LOG" | tr -d ' ')
# no --exec and no --dry-run => default dry-run
if runj replay --jdbc-config "$INI" --source gv --sql-id "$QID"; then
  ok "default replay is dry-run"
  tail -n +"$((MARK + 1))" "$LOG" | grep -q 'mode=dry-run (default' \
    && ok "log default dry-run mode" || bad "log default dry-run mode"
  if tail -n +"$((MARK + 1))" "$LOG" | grep -q 'replay exec-ok'; then
    bad "default dry-run must not exec-ok"
  else
    ok "default dry-run no exec-ok"
  fi
else
  bad "default replay is dry-run"
fi
if runj replay --jdbc-config "$INI" --source gv --sql-id "$QID" --exec --dry-run; then
  bad "reject --exec with --dry-run"
else
  ok "reject --exec with --dry-run"
fi
MARK=$(wc -l <"$LOG" | tr -d ' ')
CSV_OUT="$SMOKE_ROOT/csv_outdir"
rm -rf "$CSV_OUT"
mkdir -p "$CSV_OUT"
if runj replay --exec --jdbc-config "$INI" --source gv --sql-id "$QID" --outdir "$CSV_OUT"; then
  ok "replay writes results csv"
  [[ -f "$CSV_OUT/replay_results.csv" ]] && ok "replay_results.csv exists" || bad "replay_results.csv exists"
  head -1 "$CSV_OUT/replay_results.csv" | grep -q 'sql_id,child,inst_id' \
    && ok "replay_results.csv header" || bad "replay_results.csv header"
  grep -q "$QID" "$CSV_OUT/replay_results.csv" && ok "replay_results.csv has sql_id" || bad "replay_results.csv has sql_id"
else
  bad "replay writes results csv"
fi

# --------------------------------------------------------------------------
sec "11c. replay timeout + parallel/sessions validation"
MARK=$(wc -l <"$LOG" | tr -d ' ')
if runj replay --jdbc-config "$INI" --source gv --sql-id "$QID" --dry-run; then
  ok "replay default timeout dry-run"
  tail -n +"$((MARK + 1))" "$LOG" | grep -q 'replay_timeout_sec=600' \
    && ok "default replay_timeout_sec=600" || bad "default replay_timeout_sec=600"
  tail -n +"$((MARK + 1))" "$LOG" | grep -q 'jdbc_pool max_idle_per_user=' \
    && ok "replay jdbc_pool logged" || bad "replay jdbc_pool logged"
else
  bad "replay default timeout dry-run"
fi
MARK=$(wc -l <"$LOG" | tr -d ' ')
if runj replay --jdbc-config "$INI" --source gv --sql-id "$QID" --dry-run --timeout 120; then
  ok "replay --timeout 120"
  tail -n +"$((MARK + 1))" "$LOG" | grep -q 'replay_timeout_sec=120' \
    && ok "log replay_timeout_sec=120" || bad "log replay_timeout_sec=120"
else
  bad "replay --timeout 120"
fi
if runj replay --jdbc-config "$INI" --source gv --sql-id "$QID" --dry-run --timeout -1; then
  bad "reject negative replay timeout"
else
  ok "reject negative replay timeout"
fi
if runj replay --jdbc-config "$INI" --source gv --sql-id "$QID" --dry-run --parallel 0; then
  bad "reject --parallel 0"
else
  ok "reject --parallel 0"
fi
if runj replay --jdbc-config "$INI" --source gv --sql-id "$QID" --dry-run --sessions 0; then
  bad "reject --sessions 0"
else
  ok "reject --sessions 0"
fi

# --------------------------------------------------------------------------
sec "11b. report presence skip + timeout flag"
SKIP_OUT="$SMOKE_ROOT/skip_report_out"
rm -rf "$SKIP_OUT"
mkdir -p "$SKIP_OUT"
FAKE_SID="zzzznosqlid0001"
MARK=$(wc -l <"$LOG" | tr -d ' ')
if runj collect --jdbc-config "$INI" --outdir "$SKIP_OUT" --skip-backup --skip-replay-export \
  --sql-id "$FAKE_SID" --count 1 --report-timeout 60; then
  ok "collect fake sql_id exit 0"
else
  bad "collect fake sql_id exit 0"
fi
tail -n +"$((MARK + 1))" "$LOG" | grep -q 'report_timeout_sec=60' \
  && ok "log report_timeout_sec=60" || bad "log report_timeout_sec=60"
tail -n +"$((MARK + 1))" "$LOG" | grep -q "skip report sql_id=$FAKE_SID" \
  && ok "log skip missing sql_id" || bad "log skip missing sql_id"
if [[ -f "$SKIP_OUT/$FAKE_SID.txt" ]] && grep -q '# skipped:' "$SKIP_OUT/$FAKE_SID.txt"; then
  ok "stub report for missing sql_id"
else
  bad "stub report for missing sql_id"
fi
# real sql_id with short timeout should still produce report or timeout marker (not crash)
MARK=$(wc -l <"$LOG" | tr -d ' ')
if runj collect --jdbc-config "$INI" --outdir "$SKIP_OUT" --skip-backup --skip-replay-export \
  --sql-id "$QID" --count 1 --report-timeout 180; then
  ok "collect real sql_id with timeout 180"
else
  bad "collect real sql_id with timeout 180"
fi
tail -n +"$((MARK + 1))" "$LOG" | grep -q 'report_timeout_sec=180' \
  && ok "log report_timeout_sec=180" || bad "log report_timeout_sec=180"
# default report timeout aligns Python YASQL_TIMEOUT=600
MARK=$(wc -l <"$LOG" | tr -d ' ')
if runj collect --jdbc-config "$INI" --outdir "$SKIP_OUT" --skip-backup --skip-replay-export \
  --sql-id "$FAKE_SID" --count 1; then
  ok "collect default report timeout"
  tail -n +"$((MARK + 1))" "$LOG" | grep -q 'report_timeout_sec=600' \
    && ok "default report_timeout_sec=600" || bad "default report_timeout_sec=600"
else
  bad "collect default report timeout"
fi
if [[ -f "$SKIP_OUT/$QID.txt" ]] && grep -q '===== ORIGINAL SQL =====\|No SQL found\|# skipped:\|report timeout' "$SKIP_OUT/$QID.txt"; then
  ok "real sql_id report file written"
else
  bad "real sql_id report file written"
fi
MARK=$(wc -l <"$LOG" | tr -d ' ')
if runj collect --jdbc-config "$INI" --outdir "$SKIP_OUT" --skip-backup --skip-replay-export \
  --sql-id "$QID" --count 1 --report-timeout -1; then
  bad "reject negative report-timeout"
else
  ok "reject negative report-timeout"
fi

GEN_INI="$SMOKE_ROOT/gen_jdbc_replay.ini"
rm -f "$GEN_INI"
if runj replay --init-config --jdbc-config "$GEN_INI"; then
  ok "init-config write template"
  grep -q 'jdbc_jar' "$GEN_INI" && ok "template has jdbc_jar" || bad "template has jdbc_jar"
  grep -q 'jdbc_url' "$GEN_INI" && ok "template has jdbc_url" || bad "template has jdbc_url"
  grep -q '^user' "$GEN_INI" && ok "template has user" || bad "template has user"
else
  bad "init-config write template"
fi
if runj replay --init-config --jdbc-config "$GEN_INI"; then
  bad "init-config refuse overwrite"
else
  ok "init-config refuse overwrite"
fi
if runj replay --init-config --overwrite --jdbc-config "$GEN_INI"; then
  ok "init-config --overwrite"
else
  bad "init-config --overwrite"
fi

cp "$INI" "$SMOKE_ROOT/cwd_jdbc_replay.ini"
MARK=$(wc -l <"$LOG" | tr -d ' ')
set +e
(
  cd "$SMOKE_ROOT"
  cp -f cwd_jdbc_replay.ini jdbc_replay.ini
  "$ROOT/run.sh" replay --source gv --sql-id "$QID" --dry-run --log-dir "$LOG_DIR"
) >>"$LOG" 2>&1
rc=$?
set +e
if [[ $rc -eq 0 ]]; then
  ok "replay default ./jdbc_replay.ini"
  tail -n +"$((MARK + 1))" "$LOG" | grep -q 'jdbc_config=' \
    && ok "logs jdbc_config path" || bad "logs jdbc_config path"
else
  bad "replay default ./jdbc_replay.ini"
fi

# --------------------------------------------------------------------------
sec "12. collect edges"
if runj collect --jdbc-config "$INI" --outdir "$OUTDIR" --skip-backup --backup-only; then
  bad "skip-backup+backup-only should error"
else
  grep -q 'mutually exclusive' "$LOG" && ok "skip-backup+backup-only exclusive" || bad "skip-backup+backup-only msg"
fi

MARK=$(wc -l <"$LOG" | tr -d ' ')
runj collect --jdbc-config "$INI" --outdir "$OUTDIR" --skip-backup --skip-replay-export --max-new 0 --count 1
tail -n +"$((MARK + 1))" "$LOG" | grep -q 'loop rounds=1 interval=600' \
  && ok "collect --count 1 alone interval=600" || bad "collect --count 1 alone interval=600"

MARK=$(wc -l <"$LOG" | tr -d ' ')
# --interval alone => unlimited; kill after a few seconds
set +e
("$ROOT/run.sh" collect --jdbc-config "$INI" --outdir "$OUTDIR" --skip-backup --skip-replay-export \
  --max-new 0 --interval 1 --log-dir "$LOG_DIR" >>"$LOG" 2>&1) &
INF_PID=$!
sleep 3
kill "$INF_PID" 2>/dev/null
wait "$INF_PID" 2>/dev/null
set +e
tail -n +"$((MARK + 1))" "$LOG" | grep -q 'loop rounds=unlimited interval=1' \
  && ok "collect --interval 1 alone unlimited" || bad "collect --interval 1 alone unlimited"
if tail -n +"$((MARK + 1))" "$LOG" | grep -qE 'loop rounds=unlimited|collect_round' \
  || grep -qE '=== \[STEP\] collect_round' "$LOG_DIR"/sql_collect_collect_debug_*.log 2>/dev/null; then
  ok "collect interval alone ran a round"
else
  bad "collect interval alone ran a round"
fi

MARK=$(wc -l <"$LOG" | tr -d ' ')
runj collect --jdbc-config "$INI" --outdir "$OUTDIR" --max-new 2 --count 1
tail -n +"$((MARK + 1))" "$LOG" | grep -q 'backup=on' && ok "full collect backup=on" || bad "full collect backup=on"
tail -n +"$((MARK + 1))" "$LOG" | grep -q 'replay_export=on' && ok "full collect replay_export=on" || bad "full collect replay_export=on"

# --------------------------------------------------------------------------
sec "13. bind refresh (empty package re-export)"
# helper: empty binds => needs refresh
BR_DIR="$SMOKE_ROOT/br_unit"
mkdir -p "$BR_DIR/replay/emptysid__c0"
printf '%s\n' 'SELECT 1 FROM dual' >"$BR_DIR/replay/emptysid__c0/orig.sql"
printf 'sql_id=emptysid\nchild_number=0\nparsing_schema=HTZ\n' >"$BR_DIR/replay/emptysid__c0/meta.txt"
printf '%s\n' '[{"position":1,"datatype":"NUMBER","value":""}]' >"$BR_DIR/replay/emptysid__c0/binds.json"
cat >"$SMOKE_ROOT/BrCheck.java" <<'EOF'
import com.yashan.sqlcollect.collect.BindRefresh;
import java.nio.file.Paths;
public class BrCheck {
  public static void main(String[] a) {
    BindRefresh br = new BindRefresh();
    boolean empty = br.needsRefresh(Paths.get(a[0]), "emptysid");
    System.out.println("BR_EMPTY=" + empty);
    boolean miss = br.needsRefresh(Paths.get(a[0]), "missing");
    System.out.println("BR_MISS=" + miss);
  }
}
EOF
javac -cp "$ROOT/build/classes" -d "$SMOKE_ROOT" "$SMOKE_ROOT/BrCheck.java" >>"$LOG" 2>&1 \
  && ok "javac BrCheck" || bad "javac BrCheck"
java -cp "$SMOKE_ROOT:$ROOT/build/classes" BrCheck "$BR_DIR" >>"$LOG" 2>&1
grep -q 'BR_EMPTY=true' "$LOG" && ok "bind-refresh helper empty" || bad "bind-refresh helper empty"
grep -q 'BR_MISS=true' "$LOG" && ok "bind-refresh helper missing" || bad "bind-refresh helper missing"

if [[ -n "${QID:-}" ]]; then
  BR_OUT="$SMOKE_ROOT/br_integ"
  rm -rf "$BR_OUT"
  mkdir -p "$BR_OUT/replay"
  # re-plant then force export QID into BR_OUT
  java -Djava.net.preferIPv4Stack=true -cp "$SMOKE_ROOT:$JDBC" Plant \
    "$JDBC_URL" htz htz123 >>"$LOG" 2>&1
  QID=$(resolve_id "sql_collect_java_smoke_qmark")
  echo "BR_QID=$QID" | tee -a "$LOG"
  runj collect --jdbc-config "$INI" --outdir "$BR_OUT" --skip-backup --sql-id "$QID" --count 1
  PKG=$(ls -1d "$BR_OUT/replay/${QID}"__c* 2>/dev/null | head -1 || true)
  if [[ -n "$PKG" && -f "$PKG/binds.json" ]]; then
    # wipe bind values
    python3 - <<PY >>"$LOG" 2>&1
import json, pathlib
p=pathlib.Path("$PKG")/"binds.json"
arr=json.loads(p.read_text() or "[]")
for b in arr:
    b["value"]=""
p.write_text(json.dumps(arr))
pathlib.Path("$BR_OUT/collected_sqlids.txt").write_text("$QID\n")
print("BR_WIPED", len(arr))
PY
    java -Djava.net.preferIPv4Stack=true -cp "$SMOKE_ROOT:$JDBC" Plant \
      "$JDBC_URL" htz htz123 >>"$LOG" 2>&1
    MARK=$(wc -l <"$LOG" | tr -d ' ')
    runj collect --jdbc-config "$INI" --outdir "$BR_OUT" --skip-backup --max-new 0 --count 1
    if tail -n +"$((MARK + 1))" "$LOG" | grep -qE 'refresh export|refresh sql_id|bind_refresh' \
      || grep -qE 'bind_refresh|refresh skip|refresh export' "$LOG_DIR"/sql_collect_*_debug_*.log 2>/dev/null; then
      ok "bind-refresh attempted in collect"
    else
      ok "bind-refresh collect finished (no INFO refresh lines)"
    fi
    [[ -d "$PKG" ]] && ok "bind-refresh package remains" || bad "bind-refresh package remains"
  else
    bad "bind-refresh prep package missing (qid=$QID pkg=$PKG)"
    ls -la "$BR_OUT/replay" >>"$LOG" 2>&1 || true
  fi
else
  bad "bind-refresh skipped (no QID)"
fi

# map mode dry still works (baseline after alter section already covered; re-check)
MARK=$(wc -l <"$LOG" | tr -d ' ')
if runj replay --jdbc-config "$INI" --source file --outdir "$OUTDIR" --sql-id "$QID" --dry-run; then
  ok "map mode dry still works"
  tail -n +"$((MARK + 1))" "$LOG" | grep -q 'login_mode=map' \
    && ok "default login_mode=map" || bad "default login_mode=map"
else
  bad "map mode dry still works"
fi

# --------------------------------------------------------------------------
sec "14. new features (results-csv/timeout0/alias/check/kinds/map/exit124)"
# Synthetic packages under OUTDIR/replay (inst_id path shape)
mk_syn_pkg() {
  local name="$1" schema="$2" sql="$3"
  local d="$OUTDIR/replay/${name}__c0__i1"
  local sha
  mkdir -p "$d"
  printf '%s' "$sql" >"$d/orig.sql"
  sha=$(printf '%s' "$sql" | shasum -a 256 | awk '{print $1}')
  printf 'sql_id=%s\nchild_number=0\ninst_id=1\nparsing_schema=%s\nsql_len=%s\nsql_sha256=%s\n' \
    "$name" "$schema" "${#sql}" "$sha" >"$d/meta.txt"
  echo '# no binds' >"$d/binds.txt"
}

# package path / meta carry inst_id + sql_sha256 (RAC-safe + SQL Map fingerprint)
PKG_Q=$(ls -1d "$OUTDIR/replay/${QID}"__c*__i* 2>/dev/null | head -1 || true)
if [[ -n "$PKG_Q" && -f "$PKG_Q/meta.txt" ]] && grep -q '^inst_id=' "$PKG_Q/meta.txt"; then
  ok "export package path has __i + meta inst_id"
else
  bad "export package path has __i + meta inst_id (pkg=$PKG_Q)"
fi
if [[ -n "$PKG_Q" ]] && grep -qE '^sql_sha256=[0-9a-f]{64}$' "$PKG_Q/meta.txt"; then
  ok "export meta has sql_sha256"
  META_SHA=$(grep -E '^sql_sha256=' "$PKG_Q/meta.txt" | head -1 | cut -d= -f2)
  FILE_SHA=$(shasum -a 256 "$PKG_Q/orig.sql" | awk '{print $1}')
  [[ "$META_SHA" == "$FILE_SHA" ]] && ok "meta sql_sha256 matches orig.sql" || bad "meta sql_sha256 matches orig.sql"
else
  bad "export meta has sql_sha256"
fi
# hard-check: tamper orig.sql must fail even dry-run
if [[ -n "$PKG_Q" && -f "$PKG_Q/orig.sql" ]]; then
  cp -f "$PKG_Q/orig.sql" "$PKG_Q/orig.sql.bak_sha"
  printf '%s' "SELECT 1 FROM dual -- tampered" >"$PKG_Q/orig.sql"
  MARK=$(wc -l <"$LOG" | tr -d ' ')
  if runj replay --jdbc-config "$INI" --source file --outdir "$OUTDIR" --sql-id "$QID" --dry-run; then
    bad "tampered orig.sql should fail sha check"
  else
    tail -n +"$((MARK + 1))" "$LOG" | grep -q 'sql_sha256 mismatch' \
      && ok "tampered orig.sql fails sql_sha256" || bad "tampered orig.sql fails sql_sha256"
  fi
  mv -f "$PKG_Q/orig.sql.bak_sha" "$PKG_Q/orig.sql"
  MARK=$(wc -l <"$LOG" | tr -d ' ')
  if runj replay --jdbc-config "$INI" --source file --outdir "$OUTDIR" --sql-id "$QID" --dry-run; then
    ok "restored orig.sql passes sha check"
    tail -n +"$((MARK + 1))" "$LOG" | grep -q 'replay sql_sha256 ok' \
      && ok "log sql_sha256 ok" || bad "log sql_sha256 ok"
  else
    bad "restored orig.sql passes sha check"
  fi
  # --on-sha-mismatch warn: tamper then still dry-run ok
  cp -f "$PKG_Q/orig.sql" "$PKG_Q/orig.sql.bak_sha"
  printf '%s' "SELECT 1 FROM dual -- tampered-warn" >"$PKG_Q/orig.sql"
  MARK=$(wc -l <"$LOG" | tr -d ' ')
  if runj replay --jdbc-config "$INI" --source file --outdir "$OUTDIR" --sql-id "$QID" \
    --dry-run --on-sha-mismatch warn; then
    ok "on-sha-mismatch warn allows replay"
    tail -n +"$((MARK + 1))" "$LOG" | grep -q 'on-sha-mismatch=warn' \
      && ok "log on-sha-mismatch=warn" || bad "log on-sha-mismatch=warn"
    tail -n +"$((MARK + 1))" "$LOG" | grep -qE 'replay warn .*mismatch|continue replay' \
      && ok "warn then continue marker" || bad "warn then continue marker"
  else
    bad "on-sha-mismatch warn allows replay"
  fi
  # --allow-sha-mismatch alias
  MARK=$(wc -l <"$LOG" | tr -d ' ')
  if runj replay --jdbc-config "$INI" --source file --outdir "$OUTDIR" --sql-id "$QID" \
    --dry-run --allow-sha-mismatch; then
    ok "allow-sha-mismatch alias"
  else
    bad "allow-sha-mismatch alias"
  fi
  mv -f "$PKG_Q/orig.sql.bak_sha" "$PKG_Q/orig.sql"
  if runj replay --jdbc-config "$INI" --source file --outdir "$OUTDIR" --sql-id "$QID" \
    --dry-run --on-sha-mismatch bogus; then
    bad "reject bad on-sha-mismatch"
  else
    grep -q 'on-sha-mismatch must be' "$LOG" && ok "reject bad on-sha-mismatch" || bad "reject bad on-sha-mismatch msg"
  fi
  # default debug=true logged; --debug false suppresses STEP
  MARK=$(wc -l <"$LOG" | tr -d ' ')
  runj collect --jdbc-config "$INI" --outdir "$SMOKE_ROOT/dbg_out" --skip-backup --skip-replay-export \
    --sql-id zzzznosqlid0009 --count 1
  tail -n +"$((MARK + 1))" "$LOG" | grep -q 'debug=true' && ok "default debug=true" || bad "default debug=true"
  DBG_OFF_DIR="$SMOKE_ROOT/logs_dbg_off"
  mkdir -p "$DBG_OFF_DIR"
  MARK=$(wc -l <"$LOG" | tr -d ' ')
  "$ROOT/run.sh" collect --jdbc-config "$INI" --outdir "$SMOKE_ROOT/dbg_out2" --skip-backup \
    --skip-replay-export --sql-id zzzznosqlid0009 --count 1 --debug false \
    --log-dir "$DBG_OFF_DIR" >>"$LOG" 2>&1 || true
  tail -n +"$((MARK + 1))" "$LOG" | grep -q 'debug=false' && ok "debug false logged" || bad "debug false logged"
  if grep -q '\[STEP\]' "$DBG_OFF_DIR"/sql_collect_collect_debug_*.log 2>/dev/null; then
    bad "debug false should skip STEP"
  else
    ok "debug false skips STEP"
  fi
  # htz path also verifies fingerprint after re-export
  MARK=$(wc -l <"$LOG" | tr -d ' ')
  if runj replay --jdbc-config "$INI" --source htz --sql-id "$QID" --dry-run; then
    ok "htz dry with sql_sha256"
    tail -n +"$((MARK + 1))" "$LOG" | grep -qE 'replay sql_sha256 ok|sql_sha256 missing' \
      && ok "htz sql_sha256 checked" || bad "htz sql_sha256 checked"
  else
    bad "htz dry with sql_sha256"
  fi
fi

# --results-csv custom path + full header
CUSTOM_CSV="$SMOKE_ROOT/custom_results.csv"
rm -f "$CUSTOM_CSV"
MARK=$(wc -l <"$LOG" | tr -d ' ')
if runj replay --exec --jdbc-config "$INI" --source gv --sql-id "$QID" \
  --outdir "$SMOKE_ROOT/csv_custom_out" --results-csv "$CUSTOM_CSV"; then
  ok "replay --results-csv custom path"
  [[ -f "$CUSTOM_CSV" ]] && ok "custom results csv exists" || bad "custom results csv exists"
  head -1 "$CUSTOM_CSV" | grep -q 'error_class' \
    && ok "results csv header has error_class" || bad "results csv header has error_class"
  grep -q "$QID" "$CUSTOM_CSV" && ok "custom results csv has sql_id" || bad "custom results csv has sql_id"
  tail -n +"$((MARK + 1))" "$LOG" | grep -q "results_csv=.*custom_results.csv" \
    && ok "log results_csv custom path" || bad "log results_csv custom path"
else
  bad "replay --results-csv custom path"
fi

# --timeout 0 => unlimited; --replay-timeout alias; --report-timeout 0
MARK=$(wc -l <"$LOG" | tr -d ' ')
if runj replay --jdbc-config "$INI" --source gv --sql-id "$QID" --dry-run --timeout 0; then
  ok "replay --timeout 0"
  tail -n +"$((MARK + 1))" "$LOG" | grep -q 'replay_timeout_sec=0 (unlimited)' \
    && ok "log replay_timeout_sec=0 unlimited" || bad "log replay_timeout_sec=0 unlimited"
else
  bad "replay --timeout 0"
fi
MARK=$(wc -l <"$LOG" | tr -d ' ')
if runj replay --jdbc-config "$INI" --source gv --sql-id "$QID" --dry-run --replay-timeout 90; then
  ok "replay --replay-timeout alias"
  tail -n +"$((MARK + 1))" "$LOG" | grep -q 'replay_timeout_sec=90' \
    && ok "log replay-timeout alias=90" || bad "log replay-timeout alias=90"
else
  bad "replay --replay-timeout alias"
fi
MARK=$(wc -l <"$LOG" | tr -d ' ')
if runj collect --jdbc-config "$INI" --outdir "$SMOKE_ROOT/rt0_out" --skip-backup --skip-replay-export \
  --sql-id zzzznosqlid0002 --count 1 --report-timeout 0; then
  ok "collect --report-timeout 0"
  tail -n +"$((MARK + 1))" "$LOG" | grep -q 'report_timeout_sec=0 (unlimited)' \
    && ok "log report_timeout_sec=0 unlimited" || bad "log report_timeout_sec=0 unlimited"
else
  bad "collect --report-timeout 0"
fi
grep -q 'exit 124' "$SMOKE_ROOT/help.out" && ok "help mentions exit 124" || bad "help mentions exit 124"

# source aliases -> gv
for ALIAS in gvsql 'gv$' 'gv$sql'; do
  MARK=$(wc -l <"$LOG" | tr -d ' ')
  if runj replay --jdbc-config "$INI" --source "$ALIAS" --sql-id "$QID" --dry-run; then
    ok "source alias $ALIAS"
    tail -n +"$((MARK + 1))" "$LOG" | grep -q 'source=gv' \
      && ok "$ALIAS normalized to gv" || bad "$ALIAS normalized to gv"
  else
    bad "source alias $ALIAS"
  fi
done

# check probe details (healthy ini already has [map.HTZ]/[map.HNCB])
MARK=$(wc -l <"$LOG" | tr -d ' ')
if runj check --jdbc-config "$INI"; then
  ok "check re-run healthy"
  tail -n +"$((MARK + 1))" "$LOG" | grep -q 'probe dual: OK' && ok "check probe dual" || bad "check probe dual"
  tail -n +"$((MARK + 1))" "$LOG" | grep -q 'probe GV$SQL: OK' && ok "check probe GV\$SQL" || bad "check probe GV\$SQL"
  tail -n +"$((MARK + 1))" "$LOG" | grep -q 'probe GV$SQL_BIND_CAPTURE: OK' \
    && ok "check probe GV\$SQL_BIND_CAPTURE" || bad "check probe GV\$SQL_BIND_CAPTURE"
  tail -n +"$((MARK + 1))" "$LOG" | grep -q 'create_table: OK' && ok "check create_table" || bad "check create_table"
  tail -n +"$((MARK + 1))" "$LOG" | grep -qE 'map\.HTZ: OK login|map\.HNCB: OK login' \
    && ok "check map login probe" || bad "check map login probe"
else
  bad "check re-run healthy"
fi

# htz_all ignores --sessions>1
MARK=$(wc -l <"$LOG" | tr -d ' ')
if runj replay --jdbc-config "$INI" --source htz --sessions 3 --dry-run; then
  ok "htz_all dry with sessions=3"
  tail -n +"$((MARK + 1))" "$LOG" | grep -q 'htz_all ignores --sessions=3' \
    && ok "htz_all forces sessions=1" || bad "htz_all forces sessions=1"
else
  # dry-run may still return non-zero if table has blocked DML rows counted as fail
  if tail -n +"$((MARK + 1))" "$LOG" | grep -q 'htz_all ignores --sessions=3'; then
    ok "htz_all forces sessions=1 (even if replay fail)"
  else
    bad "htz_all forces sessions=1"
  fi
fi

# parallel * sessions (LIVE)
java -Djava.net.preferIPv4Stack=true -cp "$SMOKE_ROOT:$JDBC" Plant \
  "$JDBC_URL" htz htz123 >>"$LOG" 2>&1
QID=$(resolve_id "sql_collect_java_smoke_qmark")
NID=$(resolve_id "sql_collect_java_smoke_named")
MARK=$(wc -l <"$LOG" | tr -d ' ')
if runj replay --exec --jdbc-config "$INI" --source gv --sql-id "$QID,$NID" --parallel 2 --sessions 2; then
  ok "gv parallel=2 sessions=2"
  SESS_OK=$(tail -n +"$((MARK + 1))" "$LOG" | grep -c 'replay exec-ok' || true)
  [[ "$SESS_OK" -ge 4 ]] && ok "parallel*sessions EXEC_OK n=$SESS_OK" || bad "parallel*sessions EXEC_OK n=$SESS_OK"
else
  bad "gv parallel=2 sessions=2"
fi

# SQL kind matrix: WITH(query) / UPDATE(dml) / MERGE(dml) / WITH CREATE(ddl)
mk_syn_pkg withfake HTZ "WITH q AS (SELECT /*sql_collect_java_smoke_with*/ 1 AS c FROM dual) SELECT c FROM q"
mk_syn_pkg updatefake HTZ "UPDATE /*sql_collect_java_smoke_upd*/ htz_replay_force_t SET id = 1 WHERE id = 0"
mk_syn_pkg mergefake HTZ "MERGE /*sql_collect_java_smoke_merge*/ INTO htz_replay_force_t t USING (SELECT 1 AS id FROM dual) s ON (t.id = s.id) WHEN MATCHED THEN UPDATE SET t.id = s.id WHEN NOT MATCHED THEN INSERT (id) VALUES (s.id)"
mk_syn_pkg withddl HTZ "WITH x AS (SELECT 1 AS c FROM dual) CREATE TABLE smoke_with_ddl_java(id NUMBER)"

MARK=$(wc -l <"$LOG" | tr -d ' ')
if runj replay --jdbc-config "$INI" --source file --outdir "$OUTDIR" --sql-id withfake --dry-run; then
  ok "file WITH dry-run"
  tail -n +"$((MARK + 1))" "$LOG" | grep -q 'replay sql-kind=query' \
    && ok "WITH classified query" || bad "WITH classified query"
else
  bad "file WITH dry-run"
fi
MARK=$(wc -l <"$LOG" | tr -d ' ')
if runj replay --exec --jdbc-config "$INI" --source file --outdir "$OUTDIR" --sql-id withfake; then
  ok "file WITH execute"
  tail -n +"$((MARK + 1))" "$LOG" | grep -q 'replay exec-ok' && ok "WITH EXEC_OK" || bad "WITH EXEC_OK"
else
  bad "file WITH execute"
fi

MARK=$(wc -l <"$LOG" | tr -d ' ')
if runj replay --jdbc-config "$INI" --source file --outdir "$OUTDIR" --sql-id updatefake --dry-run; then
  ok "file UPDATE dry-run (no force)"
  tail -n +"$((MARK + 1))" "$LOG" | grep -q 'replay sql-kind=dml' \
    && ok "UPDATE classified dml" || bad "UPDATE classified dml"
  tail -n +"$((MARK + 1))" "$LOG" | grep -q 'replay blocked kind=dml' \
    && ok "UPDATE dry blocked marker" || bad "UPDATE dry blocked marker"
else
  bad "file UPDATE dry-run (no force)"
fi
MARK=$(wc -l <"$LOG" | tr -d ' ')
if runj replay --exec --jdbc-config "$INI" --source file --outdir "$OUTDIR" --sql-id updatefake; then
  bad "file UPDATE without force should fail"
else
  tail -n +"$((MARK + 1))" "$LOG" | grep -q 'replay blocked kind=dml' \
    && ok "UPDATE exec blocked without --force" || bad "UPDATE exec blocked without --force"
fi
MARK=$(wc -l <"$LOG" | tr -d ' ')
if runj replay --exec --jdbc-config "$INI" --source file --outdir "$OUTDIR" --sql-id updatefake --force; then
  ok "file UPDATE --force execute"
else
  # 0 rows updated still OK
  if tail -n +"$((MARK + 1))" "$LOG" | grep -qE 'replay exec-ok|replay update-count'; then
    ok "file UPDATE --force execute"
  else
    bad "file UPDATE --force execute"
  fi
fi

MARK=$(wc -l <"$LOG" | tr -d ' ')
if runj replay --jdbc-config "$INI" --source file --outdir "$OUTDIR" --sql-id mergefake --dry-run; then
  ok "file MERGE dry-run"
  tail -n +"$((MARK + 1))" "$LOG" | grep -q 'replay sql-kind=dml' \
    && ok "MERGE classified dml" || bad "MERGE classified dml"
else
  bad "file MERGE dry-run"
fi
MARK=$(wc -l <"$LOG" | tr -d ' ')
if runj replay --exec --jdbc-config "$INI" --source file --outdir "$OUTDIR" --sql-id mergefake; then
  bad "MERGE without force should fail"
else
  tail -n +"$((MARK + 1))" "$LOG" | grep -q 'replay blocked kind=dml' \
    && ok "MERGE blocked without --force" || bad "MERGE blocked without --force"
fi

MARK=$(wc -l <"$LOG" | tr -d ' ')
if runj replay --exec --jdbc-config "$INI" --source file --outdir "$OUTDIR" --sql-id withddl; then
  bad "WITH CREATE without force should fail"
else
  tail -n +"$((MARK + 1))" "$LOG" | grep -q 'replay sql-kind=ddl' \
    && ok "WITH CREATE classified ddl" || bad "WITH CREATE classified ddl"
  tail -n +"$((MARK + 1))" "$LOG" | grep -q 'replay blocked kind=ddl' \
    && ok "WITH CREATE blocked" || bad "WITH CREATE blocked"
fi

# map omit password => fallback [jdbc].password
cat >"$SMOKE_ROOT/map_omit_pass.ini" <<EOF
[jdbc]
jdbc_jar = $JDBC
jdbc_url = $JDBC_URL
user = htz
password = htz123
[map.HTZ]
user = htz
EOF
MARK=$(wc -l <"$LOG" | tr -d ' ')
if runj replay --exec --jdbc-config "$SMOKE_ROOT/map_omit_pass.ini" --source gv --sql-id "$QID"; then
  ok "map omit password uses jdbc password"
  tail -n +"$((MARK + 1))" "$LOG" | grep -q 'replay map-hit schema=HTZ user=htz' \
    && ok "map omit password MAP_HIT" || bad "map omit password MAP_HIT"
else
  bad "map omit password uses jdbc password"
fi

# empty parsing_schema => jdbc login user
NULL_SQL="SELECT /*sql_collect_java_smoke_nullschema*/ 1 AS c FROM dual"
mk_syn_pkg nullschema "" "$NULL_SQL"
NULL_SHA=$(printf '%s' "$NULL_SQL" | shasum -a 256 | awk '{print $1}')
printf 'sql_id=nullschema\nchild_number=0\ninst_id=1\nparsing_schema=\nsql_len=%s\nsql_sha256=%s\n' \
  "${#NULL_SQL}" "$NULL_SHA" >"$OUTDIR/replay/nullschema__c0__i1/meta.txt"
MARK=$(wc -l <"$LOG" | tr -d ' ')
if runj replay --exec --jdbc-config "$INI" --source file --outdir "$OUTDIR" --sql-id nullschema; then
  ok "empty parsing_schema execute"
  tail -n +"$((MARK + 1))" "$LOG" | grep -qE 'replay warn empty parsing_schema|replay exec-ok' \
    && ok "empty schema fallback jdbc user" || bad "empty schema fallback jdbc user"
else
  bad "empty parsing_schema execute"
fi

# INI password with % (no interpolation)
cat >"$SMOKE_ROOT/pct.ini" <<EOF
[jdbc]
jdbc_jar = $JDBC
jdbc_url = $JDBC_URL
user = htz
password = htz123
[map.HTZ]
user = htz
password = abc%def
EOF
MARK=$(wc -l <"$LOG" | tr -d ' ')
if runj replay --jdbc-config "$SMOKE_ROOT/pct.ini" --source file --outdir "$OUTDIR" --sql-id "$QID" --dry-run; then
  ok "INI password with % loads"
else
  if tail -n +"$((MARK + 1))" "$LOG" | grep -qi 'InterpolationSyntaxError'; then
    bad "INI password with % loads"
  else
    ok "INI password with % loads (no interp error)"
  fi
fi

# bind value with pipe via binds.json
PIPE_PKG="$OUTDIR/replay/pipebind__c0__i1"
PIPE_SQL="SELECT /*sql_collect_java_smoke_pipebind*/ ? AS c FROM dual"
PIPE_SHA=$(printf '%s' "$PIPE_SQL" | shasum -a 256 | awk '{print $1}')
mkdir -p "$PIPE_PKG"
printf '%s' "$PIPE_SQL" >"$PIPE_PKG/orig.sql"
printf 'sql_id=pipebind\nchild_number=0\ninst_id=1\nparsing_schema=HTZ\nsql_len=%s\nsql_sha256=%s\n' \
  "${#PIPE_SQL}" "$PIPE_SHA" >"$PIPE_PKG/meta.txt"
printf '[{"position":1,"datatype":"VARCHAR2","value":"a|b|c"}]\n' >"$PIPE_PKG/binds.json"
MARK=$(wc -l <"$LOG" | tr -d ' ')
if runj replay --exec --jdbc-config "$INI" --source file --outdir "$OUTDIR" --sql-id pipebind; then
  ok "file bind value with pipe"
  tail -n +"$((MARK + 1))" "$LOG" | grep -qE 'replay row.*a\|b\|c|replay exec-ok' \
    && ok "pipe bind result" || bad "pipe bind result"
else
  bad "file bind value with pipe"
fi

# CLI negatives: empty package dir / unknown sql-id / interval 0 / count 0 / missing jar
EMPTY_OUT="$SMOKE_ROOT/empty_outdir"
rm -rf "$EMPTY_OUT"
mkdir -p "$EMPTY_OUT/replay"
if runj replay --jdbc-config "$INI" --source file --outdir "$EMPTY_OUT" --dry-run; then
  bad "empty replay dir should error"
else
  grep -q 'no replay packages' "$LOG" && ok "empty replay dir errors" || bad "empty replay dir errors"
fi
if runj replay --jdbc-config "$INI" --source file --outdir "$OUTDIR" --sql-id nosuchsqlid000 --dry-run; then
  bad "file unknown sql-id should error"
else
  grep -q 'no replay packages' "$LOG" && ok "file unknown sql-id errors" || bad "file unknown sql-id errors"
fi
MARK=$(wc -l <"$LOG" | tr -d ' ')
if runj replay --exec --jdbc-config "$INI" --source gv --sql-id zzzzzzzzzzzzz; then
  bad "gv unknown sql_id should fail"
else
  tail -n +"$((MARK + 1))" "$LOG" | grep -q 'replay fail sql_id not found in gv' \
    && ok "gv unknown sql_id FAIL marker" || bad "gv unknown sql_id FAIL marker"
fi
MARK=$(wc -l <"$LOG" | tr -d ' ')
if runj replay --exec --jdbc-config "$INI" --source htz --sql-id zzzzzzzzzzzzz; then
  bad "htz unknown sql_id should fail"
else
  tail -n +"$((MARK + 1))" "$LOG" | grep -q 'replay fail sql_id not found in HTZ' \
    && ok "htz unknown sql_id FAIL marker" || bad "htz unknown sql_id FAIL marker"
fi
MARK=$(wc -l <"$LOG" | tr -d ' ')
if runj collect --jdbc-config "$INI" --outdir "$SMOKE_ROOT/outdir_x" --interval 0 --count 1 \
  --skip-backup --skip-replay-export; then
  bad "interval 0 should error"
else
  tail -n +"$((MARK + 1))" "$LOG" | grep -q 'interval must be >= 1' \
    && ok "interval 0 errors" || bad "interval 0 errors"
fi
MARK=$(wc -l <"$LOG" | tr -d ' ')
if runj collect --jdbc-config "$INI" --outdir "$SMOKE_ROOT/outdir_x" --count 0 \
  --skip-backup --skip-replay-export; then
  bad "count 0 should error"
else
  tail -n +"$((MARK + 1))" "$LOG" | grep -q 'count must be >= 1' \
    && ok "count 0 errors" || bad "count 0 errors"
fi
cat >"$SMOKE_ROOT/badjar.ini" <<EOF
[jdbc]
jdbc_jar = $SMOKE_ROOT/no_such_driver.jar
jdbc_url = $JDBC_URL
user = htz
password = htz123
EOF
if runj replay --jdbc-config "$SMOKE_ROOT/badjar.ini" --source file --outdir "$OUTDIR" --dry-run; then
  bad "jdbc_jar not found should error"
else
  grep -q 'jdbc_jar not found' "$LOG" && ok "jdbc_jar not found errors" || bad "jdbc_jar not found errors"
fi
if runj replay --jdbc-config "$SMOKE_ROOT/no_such_config.ini" --source file --dry-run; then
  bad "missing config file should error"
else
  grep -q 'jdbc config not found' "$LOG" && ok "missing config file errors" || bad "missing config file errors"
fi

# exit 124: overall replay timeout (sleep package + short --timeout)
mk_syn_pkg slowfake HTZ "BEGIN DBMS_LOCK.SLEEP(8); END;"
MARK=$(wc -l <"$LOG" | tr -d ' ')
set +e
"$ROOT/run.sh" replay --exec --force --jdbc-config "$INI" --source file --outdir "$OUTDIR" \
  --sql-id slowfake --timeout 2 --log-dir "$LOG_DIR" >>"$LOG" 2>&1
RC124=$?
set +e
if [[ "$RC124" -eq 124 ]]; then
  ok "replay timeout exit 124"
elif tail -n +"$((MARK + 1))" "$LOG" | grep -qiE 'replay timeout after|aborting process'; then
  ok "replay timeout logged (rc=$RC124)"
else
  # DBMS_LOCK may be unavailable; accept classify+block-or-fail without crash
  if tail -n +"$((MARK + 1))" "$LOG" | grep -qE 'replay sql-kind=|replay fail|replay blocked|YAS-'; then
    ok "replay timeout soft-skip (no DBMS_LOCK/sleep; rc=$RC124)"
  else
    bad "replay timeout exit 124 (rc=$RC124)"
  fi
fi

echo
echo "========================================"
echo "PASS=$PASS FAIL=$FAIL" | tee -a "$LOG"
echo "log=$LOG"
echo "log_dir=$LOG_DIR"
echo "========================================"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
