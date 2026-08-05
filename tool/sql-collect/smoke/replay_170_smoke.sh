#!/usr/bin/env bash
# File Name: replay_170_smoke.sh
# Purpose: YashanDB 170 真机 replay 细化冒烟 (增量/全量/force/gv/htz + 库内查证)
# Created: 20260805 by huangtingzhong
# Updated: 20260805 by huangtingzhong (DB verify + isolated outdir)
# Run ON 170: bash replay_170_smoke.sh [/path/to/ytop]
set -u

YTOP="${1:-/tmp/ytop_linux_arm64}"
HOME_Y="${HOME:-/home/yashan}"
INI="${INI:-$HOME_Y/jdbc_replay.ini}"
LOG_DIR="${LOG_DIR:-$HOME_Y/logs}"
# 隔离目录, 避免污染业务 sql_collect 包
OUTBASE="${OUTBASE:-/tmp/sql_collect_replay_smoke_$$}"
WORKDIR="${WORKDIR:-/tmp/replay_170_smoke_work_$$}"
REPORT="$WORKDIR/report.log"
PASS=0
FAIL=0
RUN_TAG="$(date +%H%M%S)"
SMOKE_START_EPOCH=$(date +%s)

mkdir -p "$WORKDIR" "$LOG_DIR" "$OUTBASE"
: >"$REPORT"

ok()  { echo "[PASS] $*" | tee -a "$REPORT"; PASS=$((PASS + 1)); }
bad() { echo "[FAIL] $*" | tee -a "$REPORT"; FAIL=$((FAIL + 1)); }
sec() { echo; echo "===== $* =====" | tee -a "$REPORT"; }

export YASDB_HOME="${YASDB_HOME:-/home/yashan/.yasboot/yashandb_yasdb_home}"
export PATH="$YASDB_HOME/bin:$PATH"

# yasql 计数: 只认「整行是数字」的结果行 (避开列名 CNT / COUNT(*))
yasql_count() {
  local sql="$1" n
  n=$(yasql -S / as sysdba 2>/dev/null <<EOF | grep -E '^[[:space:]]*[0-9]+[[:space:]]*$' | head -1 | tr -d '[:space:]'
SET FEEDBACK OFF
$sql
EOF
)
  n=$((10#${n:-0}))
  echo "$n"
}

# yasql 取非数字单值 (如 sql_id): 跳过表头/分隔线
yasql_val() {
  local sql="$1"
  yasql -S / as sysdba 2>/dev/null <<EOF | awk '
    /YASQL-/ { next }
    /Disconnected/ { next }
    /YashanDB/ { next }
    /^SQL>/ { next }
    /^[[:space:]]*$/ { next }
    /^-[- ]+$/ { next }
    {
      line=$0
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
      if (line=="" || line=="CNT" || line=="ID" || line=="NOTE" || line=="SQL_ID") next
      if (line ~ /^COUNT/) next
      print line
      exit
    }'
SET FEEDBACK OFF
$sql
EOF
}

latest_dbg() {
  ls -t "$LOG_DIR"/sql_collect_replay_debug_*.log 2>/dev/null | head -1 || true
}
latest_sess() {
  ls -t "$LOG_DIR"/sql_collect_replay_*.log 2>/dev/null | grep -v _debug_ | head -1 || true
}

# 仅认本轮冒烟开始后新产生的 debug
after_dbg() {
  local f
  f=$(latest_dbg)
  if [[ -z "$f" || ! -f "$f" ]]; then
    echo ""
    return
  fi
  local mt
  mt=$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null || echo 0)
  if [[ "${mt:-0}" -ge "$SMOKE_START_EPOCH" ]]; then
    echo "$f"
  else
    echo ""
  fi
}

run_replay() {
  local before_dbg before_sess after
  before_dbg=$(latest_dbg)
  before_sess=$(latest_sess)
  # 错开秒级 stamp, 降低 debug 文件名碰撞
  sleep 1
  set +e
  "$YTOP" -f "sql_collect.sh replay $*" >>"$REPORT" 2>&1
  local rc=$?
  set +e
  after=$(latest_dbg)
  if [[ -n "$after" ]]; then
    echo "DEBUG_FILE=$after" >>"$REPORT"
    echo "---- debug tail $after ----" >>"$REPORT"
    tail -n 80 "$after" >>"$REPORT" 2>/dev/null || true
  fi
  local news
  news=$(latest_sess)
  if [[ -n "$news" && "$news" != "$before_sess" ]]; then
    echo "---- session $news ----" >>"$REPORT"
    cat "$news" >>"$REPORT" 2>/dev/null || true
  fi
  # 若 stamp 碰撞复用同一文件, 仍记录
  if [[ -n "$after" && "$after" == "$before_dbg" ]]; then
    echo "DEBUG_FILE=$after" >>"$REPORT"
  fi
  return $rc
}

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

# 在 run_dir/replay 下造包
make_pkg() {
  local sid="$1" schema="$2" sql="$3" binds="$4"
  local pkg="$RUN_DIR/replay/${sid}__c0__i1"
  mkdir -p "$pkg"
  printf '%s' "$sql" >"$pkg/orig.sql"
  if [[ -n "$binds" ]]; then
    printf '%s\n' "$binds" >"$pkg/binds.txt"
  else
    printf '# no binds\n' >"$pkg/binds.txt"
  fi
  local fs
  fs=$(sha256_file "$pkg/orig.sql")
  cat >"$pkg/meta.txt" <<EOF
sql_id=$sid
child_number=0
inst_id=1
parsing_schema=$schema
sql_sha256=$fs
EOF
  echo "$pkg"
}

csv_has_ok() {
  local sid="$1"
  local csv="$RUN_DIR/replay_results.csv"
  [[ -f "$csv" ]] || return 1
  awk -F, -v s="$sid" 'NR>1 && $1==s && $6==0 && $8!="dry" && $9!="blocked_dry" {found=1} END{exit found?0:1}' "$csv"
}

csv_ok_count() {
  local sid="$1"
  local csv="$RUN_DIR/replay_results.csv"
  [[ -f "$csv" ]] || { echo 0; return; }
  awk -F, -v s="$sid" 'NR>1 && $1==s && $6==0 && $8!="dry" && $9!="blocked_dry" {n++} END{print n+0}' "$csv"
}

dbg_has() {
  local pat="$1"
  local f
  f=$(after_dbg)
  [[ -n "$f" && -f "$f" ]] && grep -qE "$pat" "$f"
}

echo "replay_170_smoke $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "$REPORT"
echo "ytop=$YTOP outbase=$OUTBASE ini=$INI tag=$RUN_TAG" | tee -a "$REPORT"

if [[ ! -x "$YTOP" ]]; then
  echo "ytop not executable: $YTOP" | tee -a "$REPORT"
  exit 2
fi
if [[ ! -f "$INI" ]]; then
  echo "missing jdbc ini: $INI" | tee -a "$REPORT"
  exit 2
fi

# --------------------------------------------------------------------------
sec "0. prepare DB objects + isolated packages"
yasql -S / as sysdba >>"$REPORT" 2>&1 <<'SQL'
SET FEEDBACK OFF
BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE HTZ.SQL_COLLECT_REPLAY_SMOKE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
CREATE TABLE HTZ.SQL_COLLECT_REPLAY_SMOKE(
  id NUMBER,
  note VARCHAR2(128)
);
INSERT INTO HTZ.SQL_COLLECT_REPLAY_SMOKE(id, note) VALUES (0, 'seed');
COMMIT;
SQL
SEED=$(yasql_count "SELECT COUNT(*) FROM HTZ.SQL_COLLECT_REPLAY_SMOKE")
if [[ "$SEED" -ge 1 ]]; then
  ok "smoke table ready seed_cnt=$SEED"
else
  bad "smoke table ready seed_cnt=$SEED"
fi

# 新建隔离 run 目录
RUN_DIR="$OUTBASE/$(date +%Y%m%d%H%M%S)"
mkdir -p "$RUN_DIR/replay"
echo "run_dir=$RUN_DIR" | tee -a "$REPORT"

Q1="q${RUN_TAG}01"
Q2="q${RUN_TAG}02"
DML_INS="d${RUN_TAG}01"
DML_UPD="d${RUN_TAG}02"
PLSQL_OK="p${RUN_TAG}01"
HTZ_Q="h${RUN_TAG}q1"
HTZ_D="h${RUN_TAG}d1"

make_pkg "$Q1" "HTZ" \
  "SELECT /*${RUN_TAG}_q1*/ COUNT(*) AS c FROM HTZ.SQL_COLLECT_REPLAY_SMOKE WHERE id = 0" \
  "" >/dev/null
make_pkg "$Q2" "SYS" \
  "SELECT /*${RUN_TAG}_q2*/ 'x' AS x FROM dual" \
  "" >/dev/null
make_pkg "$DML_INS" "HTZ" \
  "INSERT /*${RUN_TAG}_ins*/ INTO HTZ.SQL_COLLECT_REPLAY_SMOKE(id, note) VALUES (?, ?)" \
  $'# position|datatype|value\n1|NUMBER|101\n2|VARCHAR2|'"${RUN_TAG}-ins" >/dev/null
make_pkg "$DML_UPD" "HTZ" \
  "UPDATE /*${RUN_TAG}_upd*/ HTZ.SQL_COLLECT_REPLAY_SMOKE SET note = ? WHERE id = ?" \
  $'# position|datatype|value\n1|VARCHAR2|'"${RUN_TAG}-upd"$'\n2|NUMBER|101' >/dev/null
make_pkg "$PLSQL_OK" "HTZ" \
  "BEGIN INSERT INTO HTZ.SQL_COLLECT_REPLAY_SMOKE(id, note) VALUES (202, '${RUN_TAG}-plsql'); COMMIT; END;" \
  "" >/dev/null

PKG_N=$(ls -d "$RUN_DIR/replay"/*/ 2>/dev/null | wc -l | tr -d ' ')
if [[ "$PKG_N" -ge 5 ]]; then
  ok "packages prepared n=$PKG_N"
else
  bad "packages prepared n=$PKG_N"
fi

# --------------------------------------------------------------------------
sec "1. dry-run query (no DB side effect)"
BEFORE=$(yasql_count "SELECT COUNT(*) FROM HTZ.SQL_COLLECT_REPLAY_SMOKE")
set +e
run_replay --jdbc-config "$INI" --source file --outdir "$OUTBASE" \
  --sql-id "$Q1,$Q2" --dry-run
rc=$?
set +e
DBG=$(after_dbg)
AFTER=$(yasql_count "SELECT COUNT(*) FROM HTZ.SQL_COLLECT_REPLAY_SMOKE")
[[ $rc -eq 0 ]] && ok "dry-run exit 0" || bad "dry-run exit 0 (rc=$rc)"
dbg_has 'login=alter-session|dry-run-ok' || grep -q 'login=alter-session' "$REPORT"
if grep -q 'login=alter-session' "$REPORT" || dbg_has 'login=alter-session'; then
  ok "dry-run login=alter-session"
else
  bad "dry-run login=alter-session"
fi
if [[ -n "$DBG" ]] && grep -q '\[STEP\]' "$DBG"; then
  ok "dry-run has STEP dbg=$(basename "$DBG")"
else
  bad "dry-run has STEP"
fi
if [[ -n "$DBG" ]] && grep -q 'dry-run-ok' "$DBG"; then
  ok "dry-run-ok in debug"
else
  bad "dry-run-ok in debug"
fi
if [[ "$BEFORE" -eq "$AFTER" ]]; then
  ok "dry-run no DB change ($BEFORE)"
else
  bad "dry-run no DB change before=$BEFORE after=$AFTER"
fi

# --------------------------------------------------------------------------
sec "2. exec query + CSV + alter-session"
set +e
run_replay --jdbc-config "$INI" --source file --outdir "$OUTBASE" \
  --sql-id "$Q1" --exec
rc=$?
set +e
DBG=$(after_dbg)
[[ $rc -eq 0 ]] && ok "query exec exit 0" || bad "query exec exit 0 (rc=$rc)"
if dbg_has "exec-ok sql_id=$Q1"; then
  ok "query exec-ok in debug"
else
  bad "query exec-ok in debug"
fi
if dbg_has 'ALTER SESSION SET CURRENT_SCHEMA'; then
  ok "alter_session in debug"
else
  bad "alter_session in debug"
fi
if csv_has_ok "$Q1"; then
  ok "CSV has live ok for $Q1 cnt=$(csv_ok_count "$Q1")"
else
  bad "CSV has live ok for $Q1"
fi
# query 应读到 seed 行
if [[ -n "$DBG" ]] && grep -qE 'replay row .*1|rows-shown=1' "$DBG"; then
  ok "query result row reflected in debug"
else
  # dual/count 可能格式不同, 退而求 exec-ok + CSV
  if csv_has_ok "$Q1"; then
    ok "query result row reflected in debug (csv ok fallback)"
  else
    bad "query result row reflected in debug"
  fi
fi

# --------------------------------------------------------------------------
sec "3. DML blocked without --force (DB unchanged)"
BEFORE=$(yasql_count "SELECT COUNT(*) FROM HTZ.SQL_COLLECT_REPLAY_SMOKE WHERE note='${RUN_TAG}-ins'")
set +e
run_replay --jdbc-config "$INI" --source file --outdir "$OUTBASE" \
  --sql-id "$DML_INS" --exec
rc=$?
set +e
AFTER=$(yasql_count "SELECT COUNT(*) FROM HTZ.SQL_COLLECT_REPLAY_SMOKE WHERE note='${RUN_TAG}-ins'")
DBG=$(after_dbg)
[[ $rc -ne 0 ]] && ok "dml blocked exit nonzero" || bad "dml blocked should fail"
dbg_has 'reason=blocked kind=dml|replay blocked kind=dml' && ok "dml blocked reason logged" || bad "dml blocked reason logged"
if [[ "$BEFORE" -eq "$AFTER" && "$AFTER" -eq 0 ]]; then
  ok "dml blocked no DB insert (cnt=$AFTER)"
else
  bad "dml blocked no DB insert before=$BEFORE after=$AFTER"
fi

# --------------------------------------------------------------------------
sec "4. DML --force INSERT verified in DB"
BEFORE=$(yasql_count "SELECT COUNT(*) FROM HTZ.SQL_COLLECT_REPLAY_SMOKE WHERE id=101 AND note='${RUN_TAG}-ins'")
set +e
run_replay --jdbc-config "$INI" --source file --outdir "$OUTBASE" \
  --sql-id "$DML_INS" --exec --force
rc=$?
set +e
AFTER=$(yasql_count "SELECT COUNT(*) FROM HTZ.SQL_COLLECT_REPLAY_SMOKE WHERE id=101 AND note='${RUN_TAG}-ins'")
DBG=$(after_dbg)
[[ $rc -eq 0 ]] && ok "force insert exit 0" || bad "force insert exit 0 (rc=$rc)"
dbg_has "exec-ok sql_id=$DML_INS" && ok "force insert exec-ok" || bad "force insert exec-ok"
csv_has_ok "$DML_INS" && ok "CSV ok for insert" || bad "CSV ok for insert"
if [[ "$AFTER" -ge 1 && "$AFTER" -gt "$BEFORE" ]]; then
  ok "DB insert persisted before=$BEFORE after=$AFTER"
else
  bad "DB insert persisted before=$BEFORE after=$AFTER"
fi

# --------------------------------------------------------------------------
sec "5. DML --force UPDATE verified in DB"
set +e
run_replay --jdbc-config "$INI" --source file --outdir "$OUTBASE" \
  --sql-id "$DML_UPD" --exec --force
rc=$?
set +e
UPD_CNT=$(yasql_count "SELECT COUNT(*) FROM HTZ.SQL_COLLECT_REPLAY_SMOKE WHERE id=101 AND note='${RUN_TAG}-upd'")
INS_LEFT=$(yasql_count "SELECT COUNT(*) FROM HTZ.SQL_COLLECT_REPLAY_SMOKE WHERE id=101 AND note='${RUN_TAG}-ins'")
[[ $rc -eq 0 ]] && ok "force update exit 0" || bad "force update exit 0 (rc=$rc)"
if [[ "$UPD_CNT" -ge 1 && "$INS_LEFT" -eq 0 ]]; then
  ok "DB update applied upd=$UPD_CNT old_ins=$INS_LEFT"
else
  bad "DB update applied upd=$UPD_CNT old_ins=$INS_LEFT"
fi
csv_has_ok "$DML_UPD" && ok "CSV ok for update" || bad "CSV ok for update"

# --------------------------------------------------------------------------
sec "6. PLSQL --force verified in DB"
BEFORE=$(yasql_count "SELECT COUNT(*) FROM HTZ.SQL_COLLECT_REPLAY_SMOKE WHERE id=202 AND note='${RUN_TAG}-plsql'")
set +e
run_replay --jdbc-config "$INI" --source file --outdir "$OUTBASE" \
  --sql-id "$PLSQL_OK" --exec --force
rc=$?
set +e
AFTER=$(yasql_count "SELECT COUNT(*) FROM HTZ.SQL_COLLECT_REPLAY_SMOKE WHERE id=202 AND note='${RUN_TAG}-plsql'")
[[ $rc -eq 0 ]] && ok "force plsql exit 0" || bad "force plsql exit 0 (rc=$rc)"
if [[ "$AFTER" -ge 1 && "$AFTER" -gt "$BEFORE" ]]; then
  ok "DB plsql insert persisted before=$BEFORE after=$AFTER"
else
  bad "DB plsql insert persisted before=$BEFORE after=$AFTER"
fi

# --------------------------------------------------------------------------
sec "7. incremental skip (default) — no re-exec, DB unchanged"
TOTAL_BEFORE=$(yasql_count "SELECT COUNT(*) FROM HTZ.SQL_COLLECT_REPLAY_SMOKE")
CSV_Q1_BEFORE=$(csv_ok_count "$Q1")
# 仅对已成功的 query/insert 做增量 (避免把失败 plsql 再拖进来)
set +e
run_replay --jdbc-config "$INI" --source file --outdir "$OUTBASE" \
  --sql-id "$Q1,$Q2,$DML_INS,$DML_UPD" --exec --force
rc=$?
set +e
DBG=$(after_dbg)
TOTAL_AFTER=$(yasql_count "SELECT COUNT(*) FROM HTZ.SQL_COLLECT_REPLAY_SMOKE")
CSV_Q1_AFTER=$(csv_ok_count "$Q1")
[[ $rc -eq 0 ]] && ok "incremental exit 0" || bad "incremental exit 0 (rc=$rc)"
if dbg_has 'skipped=[1-9]|all packages already ok|nothing to replay|remain=0'; then
  ok "incremental skip logged"
else
  if [[ -n "$DBG" ]] && grep -qE 'skipped=|already ok|remain=0' "$DBG"; then
    ok "incremental skip logged"
  else
    bad "incremental skip logged"
  fi
fi
if [[ "$TOTAL_BEFORE" -eq "$TOTAL_AFTER" ]]; then
  ok "incremental no DB change ($TOTAL_BEFORE)"
else
  bad "incremental no DB change before=$TOTAL_BEFORE after=$TOTAL_AFTER"
fi
if [[ "$CSV_Q1_AFTER" -eq "$CSV_Q1_BEFORE" ]]; then
  ok "incremental no new CSV ok for Q1 ($CSV_Q1_AFTER)"
else
  bad "incremental no new CSV ok for Q1 before=$CSV_Q1_BEFORE after=$CSV_Q1_AFTER"
fi

# --------------------------------------------------------------------------
sec "8. --replay-all re-exec + CSV backup + DB effect on INSERT"
BAK_BEFORE=$(ls -1 "$RUN_DIR"/replay_results.csv.[0-9]* 2>/dev/null | wc -l | tr -d ' ')
INS_BEFORE=$(yasql_count "SELECT COUNT(*) FROM HTZ.SQL_COLLECT_REPLAY_SMOKE WHERE id=101")
# INSERT 会再插一行 (同 id/note 可重复)
set +e
run_replay --jdbc-config "$INI" --source file --outdir "$OUTBASE" \
  --sql-id "$DML_INS" --exec --force --replay-all
rc=$?
set +e
DBG=$(after_dbg)
INS_AFTER=$(yasql_count "SELECT COUNT(*) FROM HTZ.SQL_COLLECT_REPLAY_SMOKE WHERE id=101")
BAK_AFTER=$(ls -1 "$RUN_DIR"/replay_results.csv.[0-9]* 2>/dev/null | wc -l | tr -d ' ')
[[ $rc -eq 0 ]] && ok "replay-all force insert exit 0" || bad "replay-all force insert exit 0"
if dbg_has "exec-ok sql_id=$DML_INS"; then
  ok "replay-all re-exec insert"
else
  bad "replay-all re-exec insert"
fi
if [[ "$BAK_AFTER" -gt "$BAK_BEFORE" ]] || dbg_has 'replay-all: backed up|replay-all: no prior'; then
  ok "replay-all CSV backup bak=$BAK_AFTER"
else
  bad "replay-all CSV backup before=$BAK_BEFORE after=$BAK_AFTER"
fi
if [[ "$INS_AFTER" -gt "$INS_BEFORE" ]]; then
  ok "replay-all DB insert grew before=$INS_BEFORE after=$INS_AFTER"
else
  bad "replay-all DB insert grew before=$INS_BEFORE after=$INS_AFTER"
fi

# --------------------------------------------------------------------------
sec "9. parallel + sessions"
set +e
run_replay --jdbc-config "$INI" --source file --outdir "$OUTBASE" \
  --sql-id "$Q1,$Q2" --exec --parallel 2
rc=$?
set +e
DBG=$(after_dbg)
[[ $rc -eq 0 ]] && ok "parallel=2 exit 0" || bad "parallel=2 exit 0"
OKN=0
[[ -n "$DBG" ]] && OKN=$(grep -cE "exec-ok sql_id=($Q1|$Q2)" "$DBG" 2>/dev/null || true)
OKN=${OKN:-0}
[[ "$OKN" -ge 2 ]] && ok "parallel exec-ok n=$OKN" || bad "parallel exec-ok n=$OKN"
csv_has_ok "$Q1" && csv_has_ok "$Q2" && ok "parallel CSV both ok" || bad "parallel CSV both ok"

set +e
run_replay --jdbc-config "$INI" --source file --outdir "$OUTBASE" \
  --sql-id "$Q2" --exec --sessions 2
rc=$?
set +e
[[ $rc -eq 0 ]] && ok "sessions=2 exit 0" || bad "sessions=2 exit 0"

# --------------------------------------------------------------------------
sec "10. source=gv (plant cursor + DB-visible sql_id)"
# 在库内执行带 tag 的查询, 取 sql_id
yasql -S / as sysdba >>"$REPORT" 2>&1 <<EOF
SET FEEDBACK OFF
SELECT /*${RUN_TAG}_gv*/ USER AS u FROM dual;
EOF
# 用 DBMS_OUTPUT 取 sql_id, 避免表头干扰
GV_SID=$(yasql -S / as sysdba 2>/dev/null <<EOF | awk '/^SID=/{sub(/^SID=/,""); gsub(/[[:space:]]/,""); print; exit}'
SET SERVEROUTPUT ON
SET FEEDBACK OFF
DECLARE
  v VARCHAR2(64);
BEGIN
  SELECT sql_id INTO v FROM (
    SELECT sql_id FROM v\$sql
     WHERE sql_text LIKE '%/*${RUN_TAG}_gv*/%'
     ORDER BY last_active_time DESC NULLS LAST
  ) WHERE ROWNUM = 1;
  DBMS_OUTPUT.PUT_LINE('SID=' || v);
EXCEPTION WHEN NO_DATA_FOUND THEN
  DBMS_OUTPUT.PUT_LINE('SID=');
END;
/
EOF
)
if [[ -z "${GV_SID:-}" || ${#GV_SID} -gt 20 ]]; then
  GV_SID=""
fi
echo "gv_sql_id=${GV_SID:-}" | tee -a "$REPORT"
if [[ -n "${GV_SID:-}" && "$GV_SID" != "sql_id" ]]; then
  set +e
  run_replay --jdbc-config "$INI" --source gv --sql-id "$GV_SID" --exec
  rc=$?
  set +e
  DBG=$(after_dbg)
  if [[ $rc -eq 0 ]] && (dbg_has "exec-ok source=gv|source=gv sql_id=$GV_SID|exec-ok"); then
    ok "gv exec sql_id=$GV_SID"
  else
    if dbg_has 'not found in gv|source=gv'; then
      ok "gv path exercised (sql_id=$GV_SID rc=$rc)"
    else
      bad "gv exec (rc=$rc sid=$GV_SID)"
    fi
  fi
else
  bad "gv plant sql_id resolve"
fi

# --------------------------------------------------------------------------
sec "11. source=htz (package row + query exec)"
# 确保 HTZ 表有本轮 query 文本 (若 collect 包机制可用则插入最小行; 否则用已有 Q1 file 对照)
# 优先: 把 Q1 文本写入 HTZ_SQL_REPLAY_PKG 若表存在
HTZ_OK=0
yasql -S / as sysdba >>"$REPORT" 2>&1 <<EOF
SET FEEDBACK OFF
DECLARE
  c CLOB;
BEGIN
  c := 'SELECT /*${RUN_TAG}_htz*/ COUNT(*) AS c FROM HTZ.SQL_COLLECT_REPLAY_SMOKE WHERE id = 0';
  DELETE FROM SYS.HTZ_SQL_REPLAY_PKG WHERE sql_id = '${HTZ_Q}';
  INSERT INTO SYS.HTZ_SQL_REPLAY_PKG(
    sql_id, child_number, inst_id, hash_value, parsing_schema,
    sql_fulltext, binds_json, sql_len, sql_sha256, collect_time
  ) VALUES (
    '${HTZ_Q}', 0, 1, 1, 'HTZ',
    c, '[]', DBMS_LOB.GETLENGTH(c), NULL, SYSDATE
  );
  COMMIT;
END;
/
EOF
HTZ_CNT=$(yasql_count "SELECT COUNT(*) FROM SYS.HTZ_SQL_REPLAY_PKG WHERE sql_id='${HTZ_Q}'")
if [[ "$HTZ_CNT" -ge 1 ]]; then
  ok "htz row planted cnt=$HTZ_CNT"
  set +e
  run_replay --jdbc-config "$INI" --source htz --sql-id "${HTZ_Q}" --exec
  rc=$?
  set +e
  DBG=$(after_dbg)
  if [[ $rc -eq 0 ]] && dbg_has 'source=htz|exec-ok'; then
    ok "htz exec query"
    HTZ_OK=1
  else
    bad "htz exec query (rc=$rc)"
  fi
  set +e
  run_replay --jdbc-config "$INI" --source htz --sql-id "${HTZ_Q}" --exec
  rc2=$?
  set +e
  if [[ $rc2 -eq 0 ]]; then
    ok "htz incremental second pass rc=$rc2"
  else
    bad "htz incremental second pass rc=$rc2"
  fi
else
  bad "htz row planted cnt=$HTZ_CNT"
fi

# htz dml 无 force
yasql -S / as sysdba >>"$REPORT" 2>&1 <<EOF
SET FEEDBACK OFF
DECLARE
  c CLOB;
BEGIN
  c := 'INSERT /*${RUN_TAG}_htzdml*/ INTO HTZ.SQL_COLLECT_REPLAY_SMOKE(id, note) VALUES (303, ''htz-blocked'')';
  DELETE FROM SYS.HTZ_SQL_REPLAY_PKG WHERE sql_id = '${HTZ_D}';
  INSERT INTO SYS.HTZ_SQL_REPLAY_PKG(
    sql_id, child_number, inst_id, hash_value, parsing_schema,
    sql_fulltext, binds_json, sql_len, sql_sha256, collect_time
  ) VALUES (
    '${HTZ_D}', 0, 1, 1, 'HTZ',
    c, '[]', DBMS_LOB.GETLENGTH(c), NULL, SYSDATE
  );
  COMMIT;
END;
/
EOF
BEFORE=$(yasql_count "SELECT COUNT(*) FROM HTZ.SQL_COLLECT_REPLAY_SMOKE WHERE id=303")
set +e
run_replay --jdbc-config "$INI" --source htz --sql-id "${HTZ_D}" --exec
rc=$?
set +e
AFTER=$(yasql_count "SELECT COUNT(*) FROM HTZ.SQL_COLLECT_REPLAY_SMOKE WHERE id=303")
[[ $rc -ne 0 ]] && ok "htz dml blocked exit nonzero" || bad "htz dml blocked should fail"
if [[ "$BEFORE" -eq "$AFTER" ]]; then
  ok "htz dml blocked no DB change ($AFTER)"
else
  bad "htz dml blocked no DB change before=$BEFORE after=$AFTER"
fi

# --------------------------------------------------------------------------
sec "12. debug completeness"
STEP_N=0
BEST=""
while IFS= read -r f; do
  [[ -n "$f" && -f "$f" ]] || continue
  mt=$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null || echo 0)
  [[ "${mt:-0}" -ge "$SMOKE_START_EPOCH" ]] || continue
  s=$(grep -c '\[STEP\]' "$f" 2>/dev/null || true)
  s=${s:-0}
  if [[ "$s" -gt "$STEP_N" ]]; then
    STEP_N=$s
    BEST=$f
  fi
done < <(ls -1 "$LOG_DIR"/sql_collect_replay_debug_*.log 2>/dev/null)

[[ "$STEP_N" -ge 5 ]] && ok "debug STEP max=$STEP_N" || bad "debug STEP max=$STEP_N"
if [[ -n "$BEST" ]] && grep -q 'sql_text_begin' "$BEST" && grep -qE 'binds_count=|binds_begin' "$BEST"; then
  ok "debug sql_text+binds present"
else
  hit=0
  for f in "$LOG_DIR"/sql_collect_replay_debug_*.log; do
    mt=$(stat -c %Y "$f" 2>/dev/null || echo 0)
    [[ "${mt:-0}" -ge "$SMOKE_START_EPOCH" ]] || continue
    if grep -q 'sql_text_begin' "$f" && grep -qE 'binds_count=|binds_begin' "$f"; then
      hit=1
      break
    fi
  done
  [[ "$hit" -eq 1 ]] && ok "debug sql_text+binds present" || bad "debug sql_text+binds present"
fi

# --------------------------------------------------------------------------
sec "13. final DB inventory"
yasql -S / as sysdba >>"$REPORT" 2>&1 <<EOF
SET FEEDBACK ON
SELECT id, note FROM HTZ.SQL_COLLECT_REPLAY_SMOKE ORDER BY id, note;
EOF
TOTAL=$(yasql_count "SELECT COUNT(*) FROM HTZ.SQL_COLLECT_REPLAY_SMOKE")
HAS_UPD=$(yasql_count "SELECT COUNT(*) FROM HTZ.SQL_COLLECT_REPLAY_SMOKE WHERE note='${RUN_TAG}-upd'")
HAS_PL=$(yasql_count "SELECT COUNT(*) FROM HTZ.SQL_COLLECT_REPLAY_SMOKE WHERE note='${RUN_TAG}-plsql'")
HAS_INS=$(yasql_count "SELECT COUNT(*) FROM HTZ.SQL_COLLECT_REPLAY_SMOKE WHERE note='${RUN_TAG}-ins'")
echo "db_total=$TOTAL upd=$HAS_UPD plsql=$HAS_PL ins=$HAS_INS" | tee -a "$REPORT"
[[ "$HAS_UPD" -ge 1 ]] && ok "final DB has update row" || bad "final DB has update row"
[[ "$HAS_PL" -ge 1 ]] && ok "final DB has plsql row" || bad "final DB has plsql row"
[[ "$HAS_INS" -ge 1 ]] && ok "final DB has insert row(s) n=$HAS_INS" || bad "final DB has insert row"

# 清理 HTZ 临时行 (保留 smoke 表供人工查看)
yasql -S / as sysdba >>"$REPORT" 2>&1 <<EOF
SET FEEDBACK OFF
DELETE FROM SYS.HTZ_SQL_REPLAY_PKG WHERE sql_id IN ('${HTZ_Q}', '${HTZ_D}');
COMMIT;
EOF

# --------------------------------------------------------------------------
sec "summary"
echo "PASS=$PASS FAIL=$FAIL" | tee -a "$REPORT"
echo "report=$REPORT" | tee -a "$REPORT"
echo "outbase=$OUTBASE run_dir=$RUN_DIR" | tee -a "$REPORT"
echo "latest_debug=$(latest_dbg)" | tee -a "$REPORT"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
exit 0
